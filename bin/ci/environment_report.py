#!/usr/bin/env python3
"""Read Kubernetes health and generate a daily report. Delivery is opt-in."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from teams_card import make_card


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet"}
MAX_PAYLOAD_BYTES = 26000  # Leave headroom below the Teams 28 KB limit.


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
                     "notes": service_notes(entries)})
    rows.sort(key=lambda row: (row["health"] not in ("Missing", "Attention"), row["name"]))
    health = environment_health(environment).split(" — ", 1)[0]
    if health.startswith("Healthy") or health == "All services healthy":
        health = "Healthy"
    return {"name": environment["name"], "health": health, "warnings": warnings, "rows": rows}


def render_markdown(report):
    lines = ["# Opal environment report", local_time(report["captured_at"]), ""]
    if report.get("sample_data"):
        lines[0] = "# SAMPLE — Opal environment report"
        lines.extend(["Synthetic data; no live cluster checks.", ""])
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


def service_card_row(row):
    columns = [{"type": "Column", "width": width, "items": [
        {"type": "TextBlock", "text": value, "wrap": True, **style}]}
        for width, value, style in (
            (3, row["name"], {"weight": "Bolder"}), (2, row["health"], {}),
            (1, row["replicas"], {}), (2, row["age"], {}), (5, row["image"], {}))]
    items = [{"type": "ColumnSet", "columns": columns}]
    if row["notes"]:
        items.append({"type": "TextBlock", "text": row["notes"], "wrap": True, "size": "Small",
                      "color": "Attention" if row["health"] in ("Missing", "Attention") else "Default"})
    return {"type": "Container", "separator": True, "items": items}


def envelope(card):
    return {"type": "message", "attachments": [{
        "contentType": "application/vnd.microsoft.card.adaptive", "contentUrl": None,
        "content": card}]}


def encode_payload(card):
    return json.dumps(envelope(card), ensure_ascii=False).encode("utf-8")


def payload_size(card):
    return len(encode_payload(card))


def render_cards(report):
    """Use the same compact service summary as Markdown; repeat headings on splits."""
    def card(body):
        title, message = "Opal environment report", local_time(report["captured_at"])
        if report.get("sample_data"):
            title = "SAMPLE — " + title
            message += " · Synthetic data; no live cluster checks"
        return make_card(title, message, "emphasis", [], details=body)

    def block(value, heading=False):
        return {"type": "TextBlock", "text": value, "wrap": True,
                **({"weight": "Bolder", "size": "Medium", "separator": True} if heading else {})}

    cards, body = [], []
    for environment in report["environments"]:
        summary = summarise_environment(environment)
        headings = [block(summary["name"] + " — " + summary["health"], True)]
        if summary["warnings"]:
            headings.append(block(". ".join(summary["warnings"])))
        if summary["rows"]:
            headings.append(service_card_row({"name": "Service", "health": "Status", "replicas": "Ready",
                                              "age": "Age", "image": "Image", "notes": ""}))
        entries = [service_card_row(row) for row in summary["rows"]] or [block("Check failed")]
        pending_headings = headings
        for entry in entries:
            candidate = body + pending_headings + [entry]
            if payload_size(card(candidate)) > MAX_PAYLOAD_BYTES and body:
                cards.append(card(body))
                body = []
                pending_headings = headings
                candidate = headings + [entry]
            if payload_size(card(candidate)) > MAX_PAYLOAD_BYTES:
                # Full unabridged detail remains in report.json.
                texts = []

                def collect_text(item):
                    if item.get("text"):
                        texts.append(item["text"])
                    for child in item.get("items", []) + item.get("columns", []):
                        collect_text(child)

                collect_text(entry)
                entry = block(" · ".join(texts)[:2500] + " · Additional detail in the saved report.")
                candidate = body + pending_headings + [entry]
            if payload_size(card(candidate)) > MAX_PAYLOAD_BYTES:
                raise ReportError("Environment heading exceeds the Teams card size limit")
            body = candidate
            pending_headings = []
    if body:
        cards.append(card(body))
    return cards


def send_cards(cards, webhook):
    """Only called after --send; never expose a secret URL in logs or arguments."""
    parsed = urlparse(webhook)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ReportError("The report webhook must be an HTTPS URL")
    for card in cards:
        request = Request(webhook, data=encode_payload(card),
                          headers={"Content-Type": "application/json"}, method="POST")
        for attempt in range(3):
            try:
                with urlopen(request, timeout=20) as response:
                    if not 200 <= response.status < 300:
                        raise ReportError("Teams workflow did not accept the report")
                break
            except HTTPError as error:
                if error.code not in (429, 502, 503, 504) or attempt == 2:
                    raise ReportError(f"Teams workflow rejected the report (HTTP {error.code})") from None
                time.sleep(2 ** attempt)
            except (URLError, OSError):
                raise ReportError("Teams workflow request failed; check connectivity and workflow history") from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=HERE / "environment-report.json")
    parser.add_argument("--output-dir", type=Path, default=ROOT / ".environment-report/output")
    parser.add_argument("--send", action="store_true", help="Explicitly send using OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK")
    args = parser.parse_args(argv)
    try:
        args.output_dir = args.output_dir.expanduser().resolve()
        webhook = os.environ.get("OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK", "")
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
