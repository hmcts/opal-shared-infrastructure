# Opal Shared Infrastructure
This repository contains the shared common infrastructure components for Opal ?!


## OPAL-owned database reader access

No changes to the upstream PostgreSQL module are required. Both existing
module sources, inputs, administrator resources and ownership remain unchanged.
`database-reader-access.tf` adds one OPAL-owned grant provisioner per active
server, covering its configured databases:

| Environment | Reader group |
| --- | --- |
| `prod` | `DTS JIT Access opal DB Reader SC` |
| Non-production | `DTS JIT Access opal DB Reader NonProd` |

Create the groups through `azure-access` first. The grant step uses the
pipeline's existing Entra administrator identity. Its short-lived PostgreSQL
token is captured in memory and passed only in the psql child environment;
no password/token is placed in arguments, files or output. Python 3, Azure CLI
and psql are required on the existing Jenkins agent.

`bin/configure_database_reader.py` creates the group-linked non-admin role
only if absent and rejects a conflicting role/object-ID mapping. A transaction
advisory lock in postgres serialises concurrent creation on a server. It then
uses the existing application owner role to grant CONNECT, schema USAGE and
SELECT on public tables, including default SELECT for future tables created
by that configured owner. It grants no writes, DDL or administrator roles and
does not reassign ownership. SQL errors fail the provisioner; a retry safely
replays previously committed grants. No destroy provisioner is defined.

The Terraform triggers are deterministic: script hash, server, database list,
reader name/object ID, existing administrator ID and a fixed grants revision.
They are not timestamps. A subsequent unchanged apply does not rerun the step.
Historical SDS reader grants are not revoked; removing old access is separate.

### Rollout and verification

1. Merge/apply the group definitions in azure-access.
2. Merge this PR to master and promote through existing environment branches.
   Review plans for OPAL grant provisioners only, with no module resource changes.
3. Apply and validate reader logins before publishing the access packages.
4. Publish the separate production/non-production reader packages. Production
   eligibility starts empty until the approved SC cohort is confirmed;
   non-production eligibility uses DTS Green on Black.

Validate SELECT succeeds and INSERT/UPDATE/DELETE/DDL fail for a package-only
account; validate future tables using the actual migration owner. Non-public
schemas or other table-creator roles require explicit follow-up configuration.
No unmanaged databases (including gctest) are adopted. Verify assignment and
expiry using fresh connections; existing sessions need not terminate on expiry.
Require a post-apply no-change plan. The fines Test server must be healthy
before its grant/login checks can succeed.

The local unit tests exercise failure handling and token confinement. The
PostgreSQL integration test checks repeated execution, wrong-group rejection,
existing/future table reads and denied writes against an isolated database;
it stubs Azure's pgaadauth functions and does not replace a live Entra login test.
