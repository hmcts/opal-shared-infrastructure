#!/usr/bin/env python3
"""Read Kubernetes health and generate a daily report. Delivery is opt-in."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import warnings
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet"}
MAX_PAYLOAD_BYTES = 26000  # Leave headroom below the Teams 28 KB limit.
K9S_SETUP_URL = "https://hmcts.atlassian.net/wiki/spaces/PO/pages/271490998/Connect+to+Azure+Kubernetes+pods"


class ReportError(Exception):
    """An error safe to display without exposing credentials or raw API responses."""


def timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def iso(value):
    return value.astimezone(timezone.utc).isoformat()


def age(seconds):
    seconds = max(0, int(seconds))
    if seconds >= 86400:
        return f"{seconds // 86400}d {(seconds % 86400) // 3600}h"
    if seconds >= 3600:
        return f"{seconds // 3600}h {(seconds % 3600) // 60}m"
    return f"{seconds // 60}m"


def load_config(path):
    config = json.loads(path.read_text())
    if not isinstance(config.get("namespace"), str) or not config["namespace"]:
        raise ValueError("Config must specify a namespace")
    environments = config.get("environments", [])
    if not environments:
        raise ValueError("Config must specify environments")
    excluded = config.get("excluded_services", [])
    if (not isinstance(excluded, list) or any(not isinstance(v, str) or not v for v in excluded)
            or len(set(excluded)) != len(excluded)):
        raise ValueError("excluded_services must contain unique non-empty names")
    names = set()
    for environment in environments:
        name = environment["name"]
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("Environment names must be non-empty and unique")
        names.add(name)
        for key in ("contexts", "expected_services"):
            values = environment[key]
            if (not isinstance(values, list) or not values
                    or any(not isinstance(v, str) or not v for v in values)
                    or len(set(values)) != len(values)):
                raise ValueError(f"{name}: {key} must contain unique non-empty names")
        optional = environment.get("optional_contexts", [])
        if (not isinstance(optional, list) or any(not isinstance(v, str) or not v for v in optional)
                or len(set(optional)) != len(optional) or not set(optional) <= set(environment["contexts"])):
            raise ValueError(f"{name}: optional_contexts must be unique configured context names")
    return config


def write_json(path, data):
    """Write report files atomically, including on mounted volumes."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            json.dump(data, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def collect(context, namespace):
    # Explicit context on every request: never switch the user's current context.
    command = ["kubectl", "--context", context, "--namespace", namespace,
               "--request-timeout=15s", "get",
               "deployments,statefulsets,daemonsets,replicasets,pods", "-o", "json"]
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=45, check=False)
    except subprocess.TimeoutExpired:
        raise ReportError("Cluster check timed out; verify network access and authentication") from None
    except FileNotFoundError:
        raise ReportError("kubectl is not installed on the report runner") from None
    if result.returncode:
        # kubectl/auth plugin errors can include URLs and tokens; do not echo them.
        raise ReportError("Cluster check failed; verify context, network access and read permissions")
    try:
        data = json.loads(result.stdout)
        if not isinstance(data.get("items"), list):
            raise ValueError()
        return data["items"]
    except (ValueError, AttributeError):
        raise ReportError("Cluster returned an invalid response") from None


def controller_uid(resource):
    return next((owner["uid"] for owner in resource.get("metadata", {}).get("ownerReferences", [])
                 if owner.get("controller")), None)


def image_list(containers):
    return sorted(f"{c['name']}={c['image']}" for c in containers)


def pod_ready(pod):
    status = pod.get("status", {})
    statuses = status.get("containerStatuses", [])
    return (status.get("phase") == "Running"
            and any(c.get("type") == "Ready" and c.get("status") == "True"
                    for c in status.get("conditions", []))
            and len(statuses) == len(pod.get("spec", {}).get("containers", []))
            and bool(statuses) and all(c.get("ready") for c in statuses))


def pod_issues(pod):
    status = pod.get("status", {})
    reasons = []
    for container in status.get("initContainerStatuses", []) + status.get("containerStatuses", []):
        state = container.get("state", {})
        if state.get("waiting", {}).get("reason"):
            reasons.append(state["waiting"]["reason"])
        terminated = state.get("terminated", {})
        if terminated and terminated.get("exitCode", 0) != 0:
            reasons.append(terminated.get("reason", "Container failed"))
    for condition in status.get("conditions", []):
        if condition.get("type") == "PodScheduled" and condition.get("status") == "False":
            reasons.append(condition.get("reason", "Unschedulable"))
    if not pod_ready(pod) and not reasons:
        reasons.append(status.get("reason") or status.get("phase") or "Not ready")
    if reasons:
        return [f"{pod['metadata']['name']}: {', '.join(sorted(set(reasons)))}"]
    return []


def service_for(workload, expected):
    metadata = workload["metadata"]
    labels = metadata.get("labels", {})
    release = labels.get("app.kubernetes.io/instance") or labels.get("release")
    if release in expected:
        return release
    name = metadata["name"]
    return next((service for service in sorted(expected, key=len, reverse=True)
                 if name == service or name.startswith(service + "-")), name)


def workload_row(workload, pods, expected, now):
    metadata, spec = workload["metadata"], workload.get("spec", {})
    status, kind = workload.get("status", {}), workload["kind"]
    pods = [p for p in pods if not p["metadata"].get("deletionTimestamp")]
    desired = (status.get("desiredNumberScheduled", 0) if kind == "DaemonSet"
               else spec.get("replicas", 1))
    ready = sum(pod_ready(p) for p in pods)
    desired_images = image_list(spec.get("template", {}).get("spec", {}).get("containers", []))
    running_images = sorted({image for pod in pods
                             for image in image_list(pod.get("spec", {}).get("containers", []))})
    issues = [issue for pod in pods for issue in pod_issues(pod)]
    observed = status.get("observedGeneration", 0) >= metadata.get("generation", 1)
    if not observed:
        issues.append("Controller has not observed the latest configuration")
    if desired and ready < desired:
        issues.append(f"Only {ready}/{desired} replicas ready")
    if desired and not desired_images:
        issues.append("No container image found in workload template")
    target_names = {c["name"] for c in spec.get("template", {}).get("spec", {}).get("containers", [])}
    # Admission controllers may inject sidecars not present in the workload template.
    app_images = {image for pod in pods
                  for image in image_list([c for c in pod.get("spec", {}).get("containers", [])
                                           if c["name"] in target_names])}
    if desired and app_images != set(desired_images):
        issues.append("Pod images differ from target; rollout may be in progress")
    if kind == "Deployment" and desired:
        if (status.get("updatedReplicas", 0) < desired
                or status.get("availableReplicas", 0) < desired):
            issues.append("Deployment rollout incomplete")
    if kind == "StatefulSet" and desired:
        # OnDelete and partitioned updates intentionally leave older replicas.
        if (spec.get("updateStrategy", {}).get("type", "RollingUpdate") != "OnDelete"
                and status.get("currentRevision") != status.get("updateRevision")):
            issues.append("StatefulSet revisions differ")
    if kind == "DaemonSet" and desired:
        if status.get("numberUnavailable", 0):
            issues.append("DaemonSet has unavailable pods")
        if (spec.get("updateStrategy", {}).get("type", "RollingUpdate") != "OnDelete"
                and status.get("updatedNumberScheduled", 0) < desired):
            issues.append("DaemonSet rollout incomplete")
    ages = [(now - timestamp(p["metadata"]["creationTimestamp"])).total_seconds()
            for p in pods if p["metadata"].get("creationTimestamp")]
    age_labels = [age(min(ages)), age(max(ages))] if ages else []
    pod_age = "–".join(dict.fromkeys(age_labels)) if age_labels else "No pods"
    health = "Attention" if issues else ("Scaled to zero" if desired == 0 else "Healthy")
    row = {"name": metadata["name"], "kind": kind, "service": service_for(workload, expected),
           "health": health, "ready": ready, "desired": desired, "pod_age": pod_age,
           "desired_images": desired_images, "running_images": running_images,
           "target_differs": app_images != set(desired_images),
           "issues": sorted(set(issues))}
    return row


def summarise_cluster(items, expected, now, excluded_services=()):
    excluded_services = set(excluded_services)
    expected = [service for service in expected if service not in excluded_services]
    known_services = expected + sorted(excluded_services)
    workloads = [item for item in items if item.get("kind") in WORKLOAD_KINDS
                 and service_for(item, known_services) not in excluded_services]
    owners = {w["metadata"]["uid"]: w["metadata"]["uid"] for w in workloads}
    for item in items:
        if item.get("kind") == "ReplicaSet" and controller_uid(item) in owners:
            owners[item["metadata"]["uid"]] = controller_uid(item)
    pods = {}
    for item in items:
        if item.get("kind") == "Pod":
            owner = owners.get(controller_uid(item))
            if owner:
                pods.setdefault(owner, []).append(item)
    rows = [workload_row(workload, pods.get(workload["metadata"]["uid"], []), expected, now)
            for workload in workloads]
    found = {row["service"] for row in rows}
    for missing in sorted(set(expected) - found):
        rows.append({"name": missing, "service": missing, "kind": "Missing",
                     "health": "Missing", "ready": 0, "desired": None,
                     "pod_age": "No pods", "desired_images": [], "running_images": [],
                     "issues": ["Expected service has no Deployment, StatefulSet or DaemonSet"]})
    rows.sort(key=lambda row: (row["health"] not in ("Missing", "Attention"), row["name"]))
    return {"rows": rows}


def generate_report(config, now, collector=None):
    collector = collector or collect
    targets = [(env, context) for env in config["environments"] for context in env["contexts"]]

    def check(target):
        environment, context = target
        optional = context in environment.get("optional_contexts", [])
        try:
            items = collector(context, config["namespace"])
            summary = summarise_cluster(items, environment["expected_services"], now,
                                        config.get("excluded_services", []))
            return {"context": context, "optional": optional, **summary}
        except ReportError as error:
            return {"context": context, "optional": optional, "error": str(error), "rows": []}

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(check, targets))
    environments, offset = [], 0
    for environment in config["environments"]:
        count = len(environment["contexts"])
        environments.append({"name": environment["name"], "clusters": results[offset:offset + count]})
        offset += count
    return {"captured_at": iso(now), "namespace": config["namespace"], "environments": environments}


def reported_clusters(environment):
    """Optional clusters contribute when reachable; retain failures if no data is available."""
    clusters = [cluster for cluster in environment["clusters"]
                if not (cluster.get("optional") and cluster.get("error"))]
    return clusters or environment["clusters"]


def environment_health(environment):
    clusters = reported_clusters(environment)
    if all(cluster.get("error") for cluster in clusters):
        return "Check failed"
    if any(cluster.get("error") for cluster in clusters):
        return "Incomplete — cluster check failed"
    rows = [row for cluster in clusters for row in cluster["rows"]]
    count = sum(row["health"] in ("Missing", "Attention") for row in rows)
    if count:
        return f"Attention — {count} workload(s) need checking"
    scaled = sum(row["health"] == "Scaled to zero" for row in rows)
    return f"Healthy; {scaled} workload(s) scaled to zero" if scaled else "All services healthy"


def local_time(value):
    return timestamp(value).astimezone(ZoneInfo("Europe/London")).strftime("%d %b %Y %H:%M %Z")


def image_summary(images):
    """Keep the image/tag (or digest); full references remain in report.json."""
    return "; ".join(sorted({image.split("=", 1)[-1].rsplit("/", 1)[-1] for image in images})) or "—"


def service_name(name):
    name = name.removeprefix("opal-").removesuffix("-java").removesuffix("-nodejs")
    return name.removesuffix("-service")


def combined_age(rows):
    labels = [label for row in rows for label in row["pod_age"].split("–") if label != "No pods"]
    if not labels:
        return "—"

    def seconds(label):
        return sum(int(value) * {"d": 86400, "h": 3600, "m": 60}[unit]
                   for value, unit in re.findall(r"(\d+)([dhm])", label))

    labels.sort(key=seconds)
    return "–".join(dict.fromkeys([labels[0], labels[-1]]))


def service_notes(entries):
    """Keep actionable reasons; omit repeated pod names and rollout symptoms."""
    notes, reasons, generic = [], {}, set()
    for context, row in entries:
        label = re.sub(r"^ss-.*-(\d+)-aks$", r"\1", context)
        if row["health"] == "Missing":
            notes.append("Missing in " + label)
            continue
        if row["health"] == "Scaled to zero":
            notes.append("Scaled to zero in " + label)
        for issue in row["issues"]:
            if issue.startswith("Only "):
                continue
            if "rollout incomplete" in issue.lower():
                generic.add("Rollout incomplete")
            elif issue.startswith("Pod images differ"):
                generic.add("Image update pending")
            else:
                reason = re.sub(r"^[a-z0-9][a-z0-9.-]*: ", "", issue)
                reasons.setdefault(reason, set()).add(label)
    for reason, contexts in sorted(reasons.items()):
        suffix = " (" + ", ".join(sorted(contexts)) + ")" if len(contexts) < len(entries) else ""
        notes.append(reason + suffix)
    if not reasons:
        notes.extend(sorted(generic))
    return "; ".join(dict.fromkeys(notes))


def summarise_environment(environment):
    """One service row across checked clusters; retain missing/unknown coverage."""
    groups, warnings = {}, []
    for cluster in reported_clusters(environment):
        if cluster.get("error"):
            warnings.append("Unavailable: " + cluster["context"])
            continue
        for row in cluster["rows"]:
            groups.setdefault(row["service"], []).append((cluster["context"], row))
    rows = []
    incomplete = any(cluster.get("error") for cluster in reported_clusters(environment))
    for name, entries in groups.items():
        parts = [row for _, row in entries]
        healths = {row["health"] for row in parts}
        missing = "Missing" in healths
        # Keep a failure in either cluster visible even when aggregate replicas look sufficient.
        if healths == {"Missing"}:
            health = "Missing"
        elif missing or "Attention" in healths:
            health = "Attention"
        elif incomplete:
            health = "Partial"
        elif healths == {"Scaled to zero"}:
            health = "Scaled to zero"
        elif "Scaled to zero" in healths:
            health = "Partly scaled down"
        else:
            health = "Healthy"
        ready = sum(row["ready"] for row in parts)
        desired = sum(row["desired"] or 0 for row in parts)
        replicas = f"{ready}/{desired}" + (" + ?" if missing else "")
        if healths == {"Missing"}:
            replicas = "—"
        rows.append({"name": service_name(name), "health": health, "replicas": replicas,
                     "age": combined_age(parts),
                     "image": image_summary([image for row in parts for image in row["running_images"]]),
                     "full_images": sorted({image.split("=", 1)[-1] for row in parts
                                            for image in row["running_images"]}),
                     "notes": service_notes(entries)})
    rows.sort(key=lambda row: (row["health"] not in ("Missing", "Attention"), row["name"]))
    health = environment_health(environment).split(" — ", 1)[0]
    if health.startswith("Healthy") or health == "All services healthy":
        health = "Healthy"
    return {"name": environment["name"], "health": health, "warnings": warnings, "rows": rows}


def render_markdown(report):
    lines = ["# Opal environment report", local_time(report["captured_at"]), ""]
    for environment in report["environments"]:
        summary = summarise_environment(environment)
        lines.extend([f"## {summary['name']} — {summary['health']}", ""])
        if summary["warnings"]:
            lines.extend([". ".join(summary["warnings"]), ""])
        if summary["rows"]:
            lines.extend(["| Service | Status | Ready | Age | Image |", "| --- | --- | --- | --- | --- |"])
        for row in summary["rows"]:
            values = [row["name"], row["health"], row["replicas"], row["age"], row["image"]]
            lines.append("| " + " | ".join(v.replace("|", "\\|").replace("\n", " ") for v in values) + " |")
        lines.append("")
        for row in summary["rows"]:
            if row["notes"]:
                lines.append(f"- **{row['name']}:** {row['notes']}")
        if any(row["notes"] for row in summary["rows"]):
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def clipped(value, limit):
    return value if len(value) <= limit else value[:limit - 1] + "…"


def status_colour(health):
    if health == "Healthy":
        return "Good"
    if health in ("Attention", "Missing", "Check failed"):
        return "Attention"
    return "Warning"


def card_text(value, **style):
    return {"type": "TextBlock", "text": value, "wrap": True, **style}


def application_images(row):
    """Keep every app version visible, including old replicas during a rollout."""
    images = row["image"].split("; ") if row["image"] != "—" else []
    primary = [image for image in images
               if service_name(re.split(r"[:@]", image, maxsplit=1)[0]) == row["name"]]
    return primary or images, len(images) - len(primary or images)


def image_build_time(image):
    """Tags have no zone; assume UTC for approximate age, preserving the wall time."""
    tag = image.split("@", 1)[0].partition(":")[2]
    date_match = re.search(r"(?:^|-)(\d{14})$", tag)
    try:
        return datetime.strptime(date_match[1], "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc) if date_match else None
    except ValueError:
        return None


def image_alert_level(row, captured_at):
    """Unknown/future dates need checking; image age is separate from pod health."""
    images, _ = application_images(row)
    level = 0 if images else 1
    for image in images:
        built = image_build_time(image)
        seconds = (timestamp(captured_at) - built).total_seconds() if built else None
        if seconds is None or seconds < 0:
            level = max(level, 1)
        elif seconds >= 14 * 86400:
            level = 2
        elif seconds >= 12 * 86400:
            level = max(level, 1)
    return level


def image_build_detail(image, captured_at):
    """Read build time from the tag; it is not registry creation/expiry metadata."""
    tag = image.split("@", 1)[0].partition(":")[2]
    build = re.fullmatch(r"(.+)-([a-fA-F0-9]{7,40})-(\d{14})", tag)
    reference = f"{build[1]} · {build[2][:7]}" if build else tag or image
    built = image_build_time(image)
    if built is None:
        return card_text("Build date unavailable · " + clipped(reference, 100),
                         size="Small", spacing="Small", color="Warning")
    seconds = (timestamp(captured_at) - built).total_seconds()
    elapsed = "~" + age(seconds).replace(" ", "") + " old" if seconds >= 0 else "future tag date"
    warning, colour = "", "Warning" if seconds < 0 else "Default"
    if seconds >= 14 * 86400:
        warning, colour = " · 14+ days old", "Attention"
    elif seconds >= 12 * 86400:
        warning, colour = " · nearing 14 days", "Warning"
    return card_text(f"Built {built:%d %b %Y %H:%M:%S} · {elapsed}{warning} · {clipped(reference, 100)}",
                     size="Small", spacing="Small", color=colour)


def service_card_row(row, captured_at):
    health, replicas = row["health"], row["replicas"]
    status = f"✓ {replicas} ready" if health == "Healthy" else f"{health} · {replicas}"
    pod_age = row["age"].replace(" ", "")
    items = [{"type": "ColumnSet", "columns": [
        {"type": "Column", "width": "stretch", "items": [card_text(row["name"], weight="Bolder")]},
        {"type": "Column", "width": "auto", "items": [
            card_text(status, color=status_colour(health), size="Small", weight="Bolder",
                      horizontalAlignment="Right")]},
    ]}]
    images, supporting = application_images(row)
    items.extend(image_build_detail(image, captured_at) for image in images)
    if not images:
        items.append(card_text("Build date unavailable · No running image", size="Small", spacing="Small"))
    metadata = f"Pod age {pod_age}"
    if supporting:
        metadata += f" · +{supporting} supporting image{'s' if supporting != 1 else ''} in details"
    items.append(card_text(metadata, size="Small", isSubtle=True, spacing="Small"))
    if row["notes"]:
        items.append(card_text(clipped(row["notes"], 350), size="Small", spacing="Small",
                               color=status_colour(health)))
    return {"type": "Container", "separator": True, "spacing": "Medium", "items": items}


def envelope(card):
    return {"type": "message", "attachments": [{
        "contentType": "application/vnd.microsoft.card.adaptive", "contentUrl": None,
        "content": card}]}


def encode_payload(card):
    return json.dumps(envelope(card), ensure_ascii=False).encode("utf-8")


def payload_size(card):
    return len(encode_payload(card))


def render_cards(report):
    """Show exceptions by environment, or one all-clear card for the whole report."""
    summaries = [summarise_environment(environment) for environment in report["environments"]]
    for summary in summaries:
        summary["attention_rows"] = [row for row in summary["rows"]
            if row["health"] != "Healthy" or image_alert_level(row, report["captured_at"])]
    affected = [summary for summary in summaries
                if summary["attention_rows"] or summary["warnings"] or summary["health"] != "Healthy"]
    clear = [summary["name"] for summary in summaries if summary not in affected]

    def card(summary, rows, continued=False):
        label = "OPAL ENVIRONMENT REPORT"
        title = summary["name"] + (" · continued" if continued else "")
        total = len(summary["rows"])
        counts = f"{total} services checked · {len(summary['attention_rows'])} flagged"
        health, colour = summary["health"], status_colour(summary["health"])
        if summary.get("all_clear"):
            health, colour = "All clear", "Good"
            counts = f"{total} services checked · {len(summaries)} environments"
        elif health == "Healthy" and any(row["health"] != "Healthy" for row in summary["attention_rows"]):
            health, colour = "Check services", "Warning"
        elif health == "Healthy":
            level = max((image_alert_level(row, report["captured_at"]) for row in summary["attention_rows"]), default=0)
            health, colour = ("Image age alert", "Attention") if level == 2 else ("Image age warning", "Warning")
        body = [card_text(label, size="Small", isSubtle=True),
                {"type": "ColumnSet", "spacing": "Small", "columns": [
                    {"type": "Column", "width": "stretch", "items": [card_text(title, size="Large", weight="Bolder")]},
                    {"type": "Column", "width": "auto", "verticalContentAlignment": "Center", "items": [
                        card_text(health, color=colour,
                                  weight="Bolder", horizontalAlignment="Right")]},
                ]},
                card_text(local_time(report["captured_at"]) + "  ·  " + counts,
                          size="Small", isSubtle=True, spacing="Small")]
        for warning in summary["warnings"]:
            body.append(card_text(warning, color="Warning"))
        if summary.get("all_clear"):
            body.append(card_text("No service issues or application images aged 12 days or more.", color="Good"))
            body.append(card_text("Checked: " + ", ".join(clear), size="Small", isSubtle=True))
        body.extend(service_card_row(row, report["captured_at"]) for row in rows)
        if affected and summary is affected[0] and not continued and clear:
            body.append(card_text("No alerts: " + ", ".join(clear), size="Small", isSubtle=True))
        details = []
        for row in rows:
            images = row["full_images"] or ["No running pod image available"]
            detail = [card_text(row["name"], weight="Bolder"),
                      card_text(f"{row['health']} · {row['replicas']} ready · Pod age {row['age']}",
                                size="Small", isSubtle=True, spacing="Small")]
            detail.extend(card_text(image, size="Small", spacing="Small") for image in images)
            if row["notes"]:
                detail.append(card_text(row["notes"], size="Small", color=status_colour(row["health"])))
            if row.get("abridged"):
                detail.append(card_text("Additional detail in the saved report.", size="Small", isSubtle=True))
            details.append({"type": "Container", "separator": True, "spacing": "Medium", "items": detail})
        actions = [{"type": "Action.ShowCard", "title": "Images & details", "card": {
            "type": "AdaptiveCard", "version": "1.2", "body": details}}] if details else []
        actions.append({"type": "Action.OpenUrl", "title": "Set up k9s", "url": K9S_SETUP_URL})
        return {"$schema": "http://adaptivecards.io/schemas/adaptive-card.json", "type": "AdaptiveCard",
                "version": "1.2", "msteams": {"width": "Full"}, "body": body, "actions": actions,
                "fallbackText": f"Opal · {summary['name']} · {health} · {counts}"}

    if not affected:
        final = card({"name": "All environments", "health": "Healthy", "warnings": [],
                      "rows": [row for summary in summaries for row in summary["rows"]],
                      "attention_rows": [], "all_clear": True}, [])
        if payload_size(final) > MAX_PAYLOAD_BYTES:
            raise ReportError("Environment heading exceeds the Teams card size limit")
        return [final]
    cards = []
    for summary in affected:
        rows, part = [], 0
        for row in summary["attention_rows"]:
            if payload_size(card(summary, rows + [row], part > 0)) > MAX_PAYLOAD_BYTES and rows:
                cards.append(card(summary, rows, part > 0))
                rows, part = [], part + 1
            if payload_size(card(summary, [row], part > 0)) > MAX_PAYLOAD_BYTES:
                # Keep the report complete; only the Teams rendering is abridged.
                row = {**row, "name": clipped(row["name"], 150), "image": clipped(row["image"], 1000),
                       "full_images": [clipped(image, 400) for image in row["full_images"][:10]],
                       "notes": clipped(row["notes"], 600), "abridged": True}
            if payload_size(card(summary, rows + [row], part > 0)) > MAX_PAYLOAD_BYTES:
                raise ReportError("Environment heading exceeds the Teams card size limit")
            rows.append(row)
        final = card(summary, rows, part > 0)
        if payload_size(final) > MAX_PAYLOAD_BYTES:
            raise ReportError("Environment heading exceeds the Teams card size limit")
        cards.append(final)
    return cards


def validate_webhook(webhook):
    parsed = urlparse(webhook)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or any(character.isspace() for character in webhook) or not parsed.path.strip("/")):
        raise ReportError("Use the complete HTTPS webhook URL, including its path.")


def send_cards(cards, webhook):
    """Only called after --send; never expose a secret URL in logs or arguments."""
    validate_webhook(webhook)
    headers = {"Content-Type": "application/json"}
    for card in cards:
        request = Request(webhook, data=encode_payload(card),
                          headers=headers, method="POST")
        for attempt in range(3):
            try:
                with urlopen(request, timeout=20) as response:
                    if not 200 <= response.status < 300:
                        raise ReportError("Teams workflow did not accept the report")
                break
            except HTTPError as error:
                if error.code == 401:
                    raise ReportError("Teams workflow rejected the request (HTTP 401); check the complete URL "
                                      "and set the workflow trigger to Anyone") from None
                if error.code not in (429, 502, 503, 504) or attempt == 2:
                    raise ReportError(f"Teams workflow rejected the report (HTTP {error.code})") from None
                time.sleep(2 ** attempt)
            except (URLError, OSError):
                raise ReportError("Teams workflow request failed; check connectivity and workflow history") from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=HERE / "config.json")
    parser.add_argument("--output-dir", type=Path, default=ROOT / ".environment-report/output")
    parser.add_argument("--send", action="store_true",
                        help="Send to Teams; use OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK or enter the URL when prompted")
    args = parser.parse_args(argv)
    try:
        args.output_dir = args.output_dir.expanduser().resolve()
        webhook = os.environ.get("OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK", "")
        if args.send and not webhook and sys.stdin.isatty():
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", getpass.GetPassWarning)
                    webhook = getpass.getpass("Teams Workflow webhook URL (hidden): ").strip()
            except (EOFError, KeyboardInterrupt, getpass.GetPassWarning):
                raise ReportError("Webhook entry cancelled or hidden input unavailable; no message sent") from None
        if args.send and not webhook:
            raise ReportError("--send requires OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK")
        config = load_config(args.config)
        print(f"Checking environments. Output directory: {args.output_dir}", flush=True)
        report = generate_report(config, datetime.now(timezone.utc))
        cards = render_cards(report)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        write_json(args.output_dir / "report.json", report)
        write_json(args.output_dir / "teams-cards.json", cards)
        markdown = render_markdown(report)
        (args.output_dir / "report.md").write_text(markdown)
        print(markdown)
        print(f"Report saved to: {args.output_dir / 'report.md'}", flush=True)
        if args.send:
            send_cards(cards, webhook)
            print("Teams workflow accepted the report; workflow history confirms channel delivery.")
        else:
            print("Preview only. No Teams messages sent.")
        # Optional cluster failures are skipped; required failures or no data fail the check.
        return 1 if any(cluster.get("error") for env in report["environments"]
                        for cluster in reported_clusters(env)) else 0
    except ReportError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        print("Report generation failed; check config format and output file permissions.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
