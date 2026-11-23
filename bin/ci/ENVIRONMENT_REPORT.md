# Daily environment report

A snapshot of **service, status, ready replicas, pod age and image**, grouped by
Staging, Demo, ITHC and Test. There is no saved history or comparison between runs.
Scheduled runs send to Teams when the webhook repository secret is configured.
Local runs preview by default; `--send` explicitly posts to Teams.
PR and manual GitHub runs generate reports without sending messages.

Teams shows a separate card for each environment, with coloured status, ready
replicas, compact ages and short build references. Problems stay visible; use
**Images & details** to expand full image references. Large environments split
across additional cards within the Teams size limit. Markdown and JSON reports
retain the complete image details.

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
`teams-cards.json` contains the card collection for tools. The compact files
`teams-card-1.json`, `teams-card-2.json`, etc. each contain one card object for
manual use. Paste one individual file's contents into an Adaptive Card field;
the collection file is an array and is not a single Adaptive Card.

To generate the current report and post it to your Teams Workflow endpoint:

```sh
python3 bin/ci/environment_report.py --send
```

Paste the webhook URL at the hidden prompt and press Enter. The URL is used only
for that run; it is not saved in the code, report files or shell history.
If `OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK` is already set, the script uses it
without prompting. Local runs use your existing cluster authentication and do
not need the GitHub Azure secrets or federated credential.

For a Teams workflow set to **Any user in my tenant** or **Specific users in my
tenant**, use your Azure sign-in to authenticate the request:

```sh
python3 bin/ci/environment_report.py --send --teams-auth azure-cli
```

Your Azure account must belong to the workflow's tenant and, for specific-user
workflows, be on its allowed list. The script obtains a short-lived Power
Automate token from Azure CLI without printing or saving it. If sign-in has
expired or uses a different tenant, run `az login` first.

If the Teams workflow belongs to a different tenant from your clusters, select
it explicitly with `--teams-tenant <TEAMS_TENANT_ID>` on that command. This selects
the token's tenant without changing cluster configuration or the active Azure
subscription. Your Azure CLI user session must already be able to obtain a token
in the Teams tenant; a successful token lookup in the cluster tenant does not
prove access to the Teams workflow.

If token retrieval fails, the error includes Azure's `AADSTS` code when present,
without displaying the raw response or token. To diagnose it without posting a
message or changing your active subscription, run:

```sh
az account get-access-token --tenant <TEAMS_TENANT_ID> \
  --resource https://service.flow.microsoft.com/ --query expiresOn --output tsv
```

This displays only the token expiry on success, or Azure's sign-in error. The
tenant ID alone does not sign you in; additional login, consent or administrator
approval may be needed depending on the error.

To keep Teams sign-in separate from your cluster login, sign in once using a
dedicated Azure CLI folder. Replace `TEAMS_TENANT_ID` with the workflow tenant:

```sh
AZURE_CONFIG_DIR="$HOME/.azure-teams" az login --tenant TEAMS_TENANT_ID \
  --allow-no-subscriptions --scope https://service.flow.microsoft.com//.default
```

Then run the report using that folder only for Teams authentication:

```sh
python3 bin/ci/environment_report.py --send --teams-auth azure-cli \
  --teams-tenant TEAMS_TENANT_ID --teams-login-dir "$HOME/.azure-teams"
```

The script leaves the cluster login and active subscription unchanged. Azure CLI
stores the separate Teams session in this folder; it may require interactive
renewal when the organisation's sign-in policy expires it (`AADSTS70043`).

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
   The default GitHub sending command uses URL-only authentication, for the
   **Anyone** trigger option where available. Tenant-restricted workflows require
   `--teams-auth azure-cli` on the sending command and an Azure identity accepted
   by the Teams workflow; the GitHub report identity's cluster permissions alone
   do not configure this access.
2. Save its webhook URL as the repository secret
   `OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK`.
3. Once this workflow is merged to the default branch, the daily **09:00
   Europe/London** run passes the secret to the script and uses `--send`.
   PR and manual runs remain report-only and do not receive the webhook secret.

The script already sends the prepared cards to that URL. The Teams workflow
chooses the destination, so no channel name is stored in the report configuration.
Without the secret, scheduled runs still generate the report and show a warning
that Teams delivery was skipped. To stop delivery later, remove the secret.

In the workflow's **Post card in a chat or channel** action, set the **Adaptive
Card** field to the incoming attachment's **content**. For a posting action
directly after the webhook trigger, use this expression:

```text
first(triggerBody()?['attachments'])?['content']
```

If the posting action is inside a loop over incoming attachments, use the current
attachment's `content` instead. The script sends one attachment per request.
Do not paste `teams-cards.json`, a whole webhook request, or a formatted card
collection into that field. Teams posting actions have an approximately 28 KB
limit; the script splits outbound cards below 26 KB, but adding formatted JSON
as a string can exceed the limit. Use the individual compact exports for a
manual test. A webhook acceptance confirms receipt; check workflow run history
to confirm the posting action succeeded.

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
