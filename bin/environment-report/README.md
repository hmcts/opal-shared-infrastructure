# Local environment report

Checks Staging, Demo, ITHC and Test. Teams shows service problems, images aged
12+ days (red at 14), and unverifiable image dates, grouped by environment.
Full reports retain every service. Build dates come from image tags; ages assume UTC.

Requires Python 3.9+, kubectl, Azure CLI, kubelogin, your Azure sign-in and VPN access.
Run commands from the repository root.

## Run once

`python3 bin/environment-report/report.py` saves a preview to `.environment-report/output/`.
Add `--send` to post to Teams; it prompts for the webhook URL without displaying it.

## Teams setup

1. Create a Teams Workflow using **When a Teams webhook request is received**,
   select **Anyone**, save, and copy the complete HTTP URL.
2. Add **Post a card in a chat or channel** and choose the destination.
3. Set **Adaptive Card** through the expression editor to
   `first(triggerBody()?['attachments'])?['content']`.

## Daily Mac schedule

```sh
python3 bin/environment-report/macos.py configure
python3 bin/environment-report/macos.py install
```

Configuration saves the URL privately. Installation schedules **9am daily in the
Mac's timezone**, without running immediately. The job runs independently of Codex;
if the Mac is asleep, it runs after waking.

- Schedule: `~/Library/LaunchAgents/com.opal.environment-report.plist`
- Log: `.environment-report/local/schedule.log`
- Stop: `python3 bin/environment-report/macos.py uninstall`

## Configuration and tests

Edit `bin/environment-report/config.json` for contexts and services.
Run offline tests with `python3 -m unittest discover -s bin/environment-report/tests`.
