# Opal Shared Infrastructure
This repository contains the shared common infrastructure components for Opal ?!


## OPAL database reader access packages

Both the service-owned and consolidated PostgreSQL module calls use OPAL-only
Entra reader groups:

| Environment | Database login group |
| --- | --- |
| Production (`prod`) | `DTS JIT Access opal DB Reader SC` |
| All configured non-production environments | `DTS JIT Access opal DB Reader NonProd` |

The groups are created in `hmcts/azure-access`. Time-limited memberships are
managed in `hmcts/azure-access-packages`, not by direct membership of the
reader groups in `prod_users.yml`. The Production requestor group starts empty
until the approved SC cohort is confirmed. Non-production requestors are
members of `DTS Green on Black`. Reader packages do not grant writer/admin
privileges or network/bastion access.

### Deployment order

1. Merge/apply the Azure group definitions.
2. Merge the PostgreSQL module reader-group override and opt-in legacy Jenkins
   administrator preservation into its `master` branch.
3. Merge this configuration into `master`, then promote using the existing
   environment-branch process. Do not cherry-pick fixes directly to perftest.
4. Apply database permissions and verify logins before publishing the packages.

Both module calls explicitly preserve the existing legacy Jenkins admin,
enable reader access and disable writer access. The `master` module source
is already approved by the Jenkins infrastructure allowlist. Do not merge
this change until the required module inputs exist on upstream `master`.

Only the existing configured databases and schemas are covered (`public` is
the module default). This does not adopt the deliberately unmanaged `gctest`
database or change any database/server names, storage or network settings.
Changing the reader group reruns the deterministic permission provisioner;
it does not revoke historical SDS reader grants or remove existing roles.
A separate reviewed change is required if historical access must be removed.

### Acceptance checks

- Inspect plans for preserved database/server and administrator identities;
  only intended group-permission provisioner replacements should be present.
- Verify SELECT succeeds and INSERT/UPDATE/DELETE/DDL are rejected for a
  package-only account on each intended database.
- Verify future-table SELECT using the actual migration/table-creator role;
  the existing module's default-privileges SQL runs as the provisioning user
  and is not proof that every application's object-owner defaults are covered.
- Verify package assignment/expiry and cross-environment isolation using new
  connections; an existing database session need not terminate on expiry.
- Require a subsequent no-change plan after apply.

The fines Test server must be healthy before its apply/login checks can pass.
No deployment is performed by the preparation of these PRs.
