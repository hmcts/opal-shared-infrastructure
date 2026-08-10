# Bulk Entra Admin

PowerShell 7.2+ utility for controlled bulk operations on test users in the fixed domain `dev.platform.hmcts.net`.

The below scrips are intended to be ran in Powershell, you may need admin rights on your machine. You will also need permission in the dev tenant to authenticate with the required permissions, these can be added to your user, or the scripts can be ran by someone who already has access. Depending on the volume of accounts you are updating, this can take a while.

## Setup

Open Powershell, or if on Mac, run `pwsh` (after installing powershell)

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -Scopes User.ReadWrite.All
```

## Preview safely

```powershell
pwsh ./BulkEntraAdmin.ps1 -Pattern 'opal-user-{id}' -StartId 1 -EndId 3 -WhatIf
```

## Run

```powershell
pwsh ./BulkEntraAdmin.ps1 -Pattern 'opal-user-{id}' -StartId 1 -EndId 2000
```

The password is requested securely. If no action switch is supplied, the script sets the password, disables the account, and re-enables it. A fixed name such as `opal-test` targets one account; ranges are only used when `{id}` is present.

To select actions explicitly:

```powershell
pwsh ./BulkEntraAdmin.ps1 -Pattern 'opal-test-{id}' -StartId 1 -EndId 50 `
  -ResetPassword -ThrottleLimit 3
```

Use `-DisableAccount` and/or `-EnableAccount` for account-state actions. Start with a low throttle and increase cautiously; Microsoft Graph may throttle write-heavy workloads. Each run writes a CSV result log, including partial-action failures.

## Notes

- Test with a one-user range before a large batch.
- The script assumes the current Graph connection has permission to update passwords and account state.
- Parallel Graph SDK calls depend on the current PowerShell Graph session being available to runspaces. If that is not available in your environment, use `-ThrottleLimit 1` or an app-only worker design.
