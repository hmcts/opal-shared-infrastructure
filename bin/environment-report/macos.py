#!/usr/bin/env python3
"""Configure a local webhook and manage the daily macOS report schedule."""

import argparse
from datetime import datetime
import getpass
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import warnings
from zoneinfo import ZoneInfo

import report

HERE = Path(__file__).resolve().parent
LOCAL = report.ROOT / ".environment-report/local"
WEBHOOK = LOCAL / "teams-webhook"
LABEL = "com.opal.environment-report"
AGENT = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
SEARCH_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"


def private_write(path, data):
    """Replace a private file atomically; never expose the webhook in arguments."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            os.chmod(temporary, 0o600)
            handle.write(data)
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def prepare_local():
    LOCAL.mkdir(parents=True, mode=0o700, exist_ok=True)
    LOCAL.chmod(0o700)


def configure():
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        value = getpass.getpass("Teams workflow URL (hidden; saves only): ").strip()
    report.validate_webhook(value)
    prepare_local()
    private_write(WEBHOOK, (value + "\n").encode())
    print("Webhook saved privately. No message sent.")


def settings():
    if not WEBHOOK.is_file():
        raise report.ReportError("Webhook missing. Run macos.py configure first.")
    if WEBHOOK.stat().st_mode & 0o077:
        raise report.ReportError("The local teams-webhook file must have permissions 600.")
    webhook = WEBHOOK.read_text().strip()
    report.validate_webhook(webhook)
    for command in ("kubectl", "az", "kubelogin"):
        if not shutil.which(command, path=SEARCH_PATH):
            raise report.ReportError(command + " is missing from the scheduled job's PATH.")
    environment = os.environ.copy()
    environment.update(PATH=SEARCH_PATH, PYTHONDONTWRITEBYTECODE="1", PYTHONUNBUFFERED="1",
                       OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK=webhook)
    return environment


def job_config():
    log = str(LOCAL / "schedule.log")
    return {"Label": LABEL,
            "ProgramArguments": [sys.executable, str(HERE / "macos.py"), "run"],
            "WorkingDirectory": str(report.ROOT),
            "StartCalendarInterval": {"Hour": 9, "Minute": 0},
            "RunAtLoad": False, "ProcessType": "Background", "Umask": 0o077,
            "EnvironmentVariables": {"PATH": SEARCH_PATH, "PYTHONDONTWRITEBYTECODE": "1",
                                     "PYTHONUNBUFFERED": "1"},
            "StandardOutPath": log, "StandardErrorPath": log}


def launchctl(*args):
    return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True, check=False)


def manage_schedule(install):
    if sys.platform != "darwin":
        raise report.ReportError("Installing or removing the local schedule requires macOS.")
    domain = f"gui/{os.getuid()}"
    service = domain + "/" + LABEL
    previous = AGENT.read_bytes() if AGENT.exists() else None
    loaded = launchctl("print", service).returncode == 0
    if previous and plistlib.loads(previous).get("Label") != LABEL:
        raise report.ReportError("An unrelated configuration exists at the schedule path; preserving it.")
    if install:
        prepare_local()
        log = LOCAL / "schedule.log"
        log.touch(mode=0o600, exist_ok=True)
        log.chmod(0o600)
        AGENT.parent.mkdir(parents=True, exist_ok=True)
    if loaded and launchctl("bootout", service).returncode:
        raise report.ReportError("Could not unload the existing local report schedule.")
    if not install:
        AGENT.unlink(missing_ok=True)
        print("Schedule removed. The saved webhook, reports and logs are retained.")
        return
    try:
        private_write(AGENT, plistlib.dumps(job_config()))
        if launchctl("bootstrap", domain, str(AGENT)).returncode:
            raise report.ReportError("Could not register the schedule in your Mac login session.")
    except (OSError, report.ReportError):
        if previous:
            private_write(AGENT, previous)
            if loaded and launchctl("bootstrap", domain, str(AGENT)).returncode:
                raise report.ReportError("Schedule update failed; the previous file was restored but must be reloaded.") from None
        else:
            AGENT.unlink(missing_ok=True)
        raise
    print("Installed: " + str(AGENT))
    print("Runs every day at 09:00 in the Mac's timezone. Installation does not run or send a report.")
    if not WEBHOOK.exists():
        print("Webhook still needed: run macos.py configure before the first scheduled run.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("configure", "check", "install", "uninstall", "run"))
    args = parser.parse_args(argv)
    os.umask(0o077)
    try:
        if args.command == "configure":
            configure()
        elif args.command in ("install", "uninstall"):
            manage_schedule(args.command == "install")
        elif args.command == "check":
            settings()
            print("Local settings are ready. No cluster query or Teams message sent.")
        else:
            print("Starting daily report: " + datetime.now(ZoneInfo("Europe/London")).isoformat(), flush=True)
            environment = settings()
            result = subprocess.run([sys.executable, str(HERE / "report.py"), "--send"],
                                    cwd=report.ROOT, env=environment, stdin=subprocess.DEVNULL, timeout=600)
            print("Daily report exit code: " + str(result.returncode), flush=True)
            return result.returncode
        return 0
    except report.ReportError as error:
        print(str(error), file=sys.stderr)
    except subprocess.TimeoutExpired:
        print("Daily report timed out; check VPN, Azure sign-in and the log.", file=sys.stderr)
    except (OSError, ValueError, EOFError, KeyboardInterrupt, getpass.GetPassWarning):
        print("Local setup failed; check file permissions and the complete webhook URL.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
