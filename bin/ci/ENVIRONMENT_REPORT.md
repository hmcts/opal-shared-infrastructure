# Daily environment report

A snapshot of **service, status, ready replicas, pod age and image**, grouped by
Staging, Demo, ITHC and Test. There is no saved history or comparison between runs.
Scheduled runs send to Teams when the webhook repository secret is configured.
Local runs preview by default; `--send` explicitly posts to Teams.
PR and manual GitHub runs generate reports without sending messages.

## Run locally

Use your existing Kubernetes contexts, with kubectl and Python 3.9+ installed,
your usual Azure sign-in active, and any required VPN connected. If your Azure
session has expired, run `az login` first.

```sh
python3 bin/ci/environment_report.py
```

The script prints the full saved path. Files are written to
`.environment-report/output/` in this repository, regardless of your current
folder. Open `report.md`; `report.json` contains cluster details and
`teams-cards.json` contains prepared Teams cards.

To generate the current report and post it to your Teams Workflow endpoint:

```sh
python3 bin/ci/environment_report.py --send
```

Paste the webhook URL at the hidden prompt and press Enter. The URL is used only
for that run; it is not saved in the code, report files or shell history.
If `OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK` is already set, the script uses it
without prompting. Local runs use your existing cluster authentication and do
not need the GitHub Azure secrets or federated credential.

## Test from a PR

Commit and push the report files, then open a PR. The workflow automatically:

1. Runs the tests and generates a clearly labelled sample report.
2. Generates the real report if the Azure connection below is configured.
3. Shows the reports in the workflow summary and uploads them as downloads.

No label or enable flag is needed. Without Azure access, only the sample runs.
Fork PRs run the tests and sample only. After merge, the workflow also runs daily
at **09:00 Europe/London**, including GMT/BST changes. It can be run manually from
GitHub's **Run workflow** button once on the default branch. GitHub queues can
cause scheduled runs to start late. Only scheduled runs send Teams messages,
once the webhook secret below is configured.

## GitHub connection settings

The only setup for the real report is a GitHub machine that can reach the clusters
and an Azure identity allowed to read them. Your platform team can provide these.
Under **Settings → Secrets and variables → Actions → Secrets → New repository secret**, add:

| Repository secret | Value |
| --- | --- |
| `OPAL_REPORT_AZURE_CLIENT_ID` | Client ID of the Azure identity. |
| `OPAL_REPORT_AZURE_TENANT_ID` | Azure tenant ID. |
| `OPAL_REPORT_AZURE_SUBSCRIPTION_ID` | Subscription ID for initial login. |

If a different runner is needed to reach the clusters, set `OPAL_REPORT_RUNNER`
under **Actions → Variables** to its runner label. It defaults to `ubuntu-latest`.

An administrator must configure [GitHub-to-Azure authentication](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
and grant access to obtain AKS user credentials and read the `opal` namespaces.
The workflow uses the GitHub environment **opal-environment-report**; the Azure
trust subject is `repo:hmcts/opal-shared-infrastructure:environment:opal-environment-report`.
The supplied `environment-report-rbac.yaml` defines the Kubernetes read permissions.
The runner needs Azure CLI; the workflow sets up Python, kubectl and kubelogin.
The three IDs are read from repository secrets. No Azure password is needed;
Azure authenticates the GitHub run using the configured trust.

## Teams delivery

1. In Teams, use **Workflows** to create a workflow that receives a webhook and
   posts the supplied Adaptive Card to your chosen channel or chat. See
   [Microsoft's webhook setup guide](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook).
2. Save its webhook URL as the repository secret
   `OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK`.
3. Once this workflow is merged to the default branch, the daily **09:00
   Europe/London** run passes the secret to the script and uses `--send`.
   PR and manual runs remain report-only and do not receive the webhook secret.

The script already sends the prepared cards to that URL. The Teams workflow
chooses the destination, so no channel name is stored in the report configuration.
Without the secret, scheduled runs still generate the report and show a warning
that Teams delivery was skipped. To stop delivery later, remove the secret.

## Report configuration

Edit `environment-report.json` to choose clusters and services. Frontend-test and
legacy-db-stub are excluded. Staging `00` is optional: included when reachable and
ignored otherwise. Required cluster failures remain visible. Age is the
youngest–oldest pod age; status reflects Kubernetes readiness. Jobs and CronJobs
are excluded. The subscriptions and AKS naming convention are already configured.

Offline checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s bin/ci/tests -v
```
