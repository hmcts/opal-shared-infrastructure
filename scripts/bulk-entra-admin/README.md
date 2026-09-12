# Bulk Entra Admin

PowerShell 7.2+ utility for updating test accounts in the fixed domain `dev.platform.hmcts.net`.

For every account, the tool:

1. Sets the supplied password.
2. Deactivates the account.
3. Reactivates the account.

## Setup

Install Microsoft Graph PowerShell and connect to the dev tenant:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -TenantId 'GET_ID_FROM_TEAM_MEMBER' `
  -Scopes 'User.EnableDisableAccount.All', 'User.ReadWrite.All'
```

The script can also connect itself if `-TenantId` is supplied or entered when prompted.

## Preview first

For numbered accounts, include `{id}` and provide an inclusive start/end range:

```powershell
pwsh ./BulkEntraAdmin.ps1 `
  -Pattern 'opal-user-{id}' -StartId 1 -EndId 3 -WhatIf
```

This only lists the accounts; it does not ask for a password or connect to Graph.

For one account without a number, omit the range:

```powershell
pwsh ./BulkEntraAdmin.ps1 -Pattern 'opal-test' -WhatIf
```

The domain is appended automatically.

## Run

```powershell
pwsh ./BulkEntraAdmin.ps1 `
  -Pattern 'opal-user-{id}' `
  -StartId 1 -EndId 2000 `
  -TenantId 'GET_ID_FROM_TEAM_MEMBER'
```

The password is requested securely. The script previews the targets and asks for confirmation before making changes.

To provide the password through a secure prompt in the command instead:

```powershell
pwsh ./BulkEntraAdmin.ps1 `
  -Pattern 'opal-user-{id}' -StartId 1 -EndId 2000 `
  -Password (Read-Host -AsSecureString)
```

## Useful options

- `-ThrottleLimit 3` controls parallelism. Start low and increase cautiously.
- `-MaxRetries 5` controls retry attempts for Graph updates.
- `-LogPath ./results.csv` chooses the CSV result location. A timestamped CSV is created by default.
- `-SkipPreview` skips the account list and confirmation prompt. Use only after testing the exact command with `-WhatIf`.

The required delegated Graph permissions are `User.EnableDisableAccount.All` and `User.ReadWrite.All`. If parallel Graph calls are not supported by the current PowerShell session, use `-ThrottleLimit 1`.
