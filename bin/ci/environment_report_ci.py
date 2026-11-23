#!/usr/bin/env python3
"""CI setup and sample previews. Neither command sends Teams messages."""

import argparse
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import re
import subprocess
import sys

import environment_report as report


def sample_resources(service, now, ready=True):
    """Small synthetic API response, clearly distinct from live cluster data."""
    image = f"example.invalid/opal/{service.removeprefix('opal-')}:sample-v1"
    container = {"name": "app", "image": image}
    return [
        {"kind": "Deployment", "metadata": {"name": service, "uid": service, "generation": 1},
         "spec": {"replicas": 1, "template": {"spec": {"containers": [container]}}},
         "status": {"observedGeneration": 1, "updatedReplicas": 1, "availableReplicas": int(ready)}},
        {"kind": "ReplicaSet", "metadata": {"name": service + "-rs", "uid": service + "-rs",
            "ownerReferences": [{"uid": service, "controller": True}]}},
        {"kind": "Pod", "metadata": {"name": service + "-pod", "uid": service + "-pod",
            "creationTimestamp": report.iso(now - timedelta(days=2)),
            "ownerReferences": [{"uid": service + "-rs", "controller": True}]},
         "spec": {"containers": [container]},
         "status": {"phase": "Running" if ready else "Pending",
            "conditions": [{"type": "Ready", "status": "True" if ready else "False"}],
            "containerStatuses": [{"name": "app", "ready": ready, "restartCount": 0,
                                   "state": {"running": {}} if ready else
                                            {"waiting": {"reason": "PodInitializing"}}}]}}
    ]


def generate_sample(config, output_dir, now):
    by_context = {}
    for environment in config["environments"]:
        for context in environment["contexts"]:
            items = []
            for service in environment["expected_services"]:
                ready = not (environment["name"].lower() == "test" and service == "opal-maintenance-service")
                items.extend(sample_resources(service, now, ready))
            by_context[context] = items
    data = report.generate_report(config, now,
                                     collector=lambda context, namespace: by_context[context])
    data["sample_data"] = True
    cards = report.render_cards(data)
    output_dir.mkdir(parents=True, exist_ok=True)
    report.write_json(output_dir / "report.json", data)
    report.write_card_files(output_dir, cards)
    (output_dir / "report.md").write_text(report.render_markdown(data))
    print(f"Sample report saved to: {(output_dir / 'report.md').resolve()}")


def prepare_contexts(config):
    """Use the AKS naming convention already used by this repository."""
    kubeconfig = os.environ.get("KUBECONFIG")
    if not kubeconfig:
        raise report.ReportError("CI context setup requires an explicit KUBECONFIG file")
    targets = []
    for environment in config["environments"]:
        subscription = environment.get("azure_subscription")
        if not isinstance(subscription, str) or not subscription:
            raise report.ReportError(f"Set azure_subscription for {environment['name']} in the report config")
        for context in environment["contexts"]:
            if not re.fullmatch(r"ss-[a-z0-9-]+-\d+-aks", context):
                raise report.ReportError("CI context names must use the ss-<environment>-<number>-aks convention")
            targets.append((context, subscription))
    destination = Path(kubeconfig)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Start from a fresh job-local file; never reuse a runner's personal kubeconfig.
    destination.write_text("apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\ncurrent-context: ''\n")
    destination.chmod(0o600)
    for context, subscription in targets:
        command = ["az", "aks", "get-credentials", "--subscription", subscription,
                   "--resource-group", context.removesuffix("-aks") + "-rg", "--name", context,
                   "--context", context, "--file", str(destination), "--overwrite-existing"]
        try:
            result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, timeout=45, check=False)
            print(f"{context}: " + ("context ready" if result.returncode == 0 else
                                    "credentials unavailable; the report will record the failed check"))
        except subprocess.TimeoutExpired:
            print(f"{context}: credential request timed out; the report will record the failed check")
        except FileNotFoundError:
            raise report.ReportError("Azure CLI is required on the live report runner") from None
    try:
        result = subprocess.run(["kubelogin", "convert-kubeconfig", "-l", "azurecli"],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=30, check=False)
        if result.returncode:
            raise report.ReportError("Could not configure noninteractive Kubernetes authentication")
    except FileNotFoundError:
        raise report.ReportError("kubelogin is required on the live report runner") from None
    except subprocess.TimeoutExpired:
        raise report.ReportError("Kubernetes authentication setup timed out") from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("sample", "contexts"))
    parser.add_argument("--config", type=Path, default=report.HERE / "environment-report.json")
    parser.add_argument("--output-dir", type=Path, default=report.ROOT / ".environment-report/sample")
    args = parser.parse_args(argv)
    try:
        config = report.load_config(args.config)
        if args.command == "sample":
            generate_sample(config, args.output_dir, datetime.now(timezone.utc))
        else:
            prepare_contexts(config)
        return 0
    except report.ReportError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError):
        print("CI report setup failed; check configuration and output permissions.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
