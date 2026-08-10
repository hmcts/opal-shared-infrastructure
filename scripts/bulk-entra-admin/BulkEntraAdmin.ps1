#requires -Version 7.2
<#
.SYNOPSIS
  Safely bulk-update test users in Microsoft Entra ID.

.DESCRIPTION
  Generates users from a pattern such as opal-user-{id}, previews the target
  list, and optionally sets a password, disables, and/or re-enables accounts.
  Requires an existing Microsoft Graph PowerShell connection.
#>
[CmdletBinding()]
param(
    # Username prefix. Include the literal {id} when generating a range.
    # Examples: opal-user-{id}, opal-test-{id}, or opal-test.
    [string]$Pattern,
    # Inclusive numeric range. Required only when Pattern contains {id}.
    [int]$StartId,
    [int]$EndId,
    # If omitted, the password is requested securely.
    [securestring]$Password,
    # Number of concurrent users; 1 is sequential. Valid range: 1-20.
    [int]$ThrottleLimit = 5,
    # Attempts per Graph operation, including the first attempt.
    [int]$MaxRetries = 5,
    # Fixed tenant domain appended to the generated username.
    [string]$Domain = 'dev.platform.hmcts.net',
    # Optional tenant ID. Used to connect to, or validate, the intended tenant.
    [string]$TenantId,
    # CSV destination. A timestamped file in the current directory is the default.
    [string]$LogPath = (Join-Path (Get-Location) ("BulkEntraAdmin-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),
    # Bypass the target preview and confirmation. Use with care.
    [switch]$SkipPreview,
    # Show the generated targets and exit without connecting or changing anything.
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Read-Required([string]$Prompt) {
    do { $value = (Read-Host $Prompt).Trim() } while ([string]::IsNullOrWhiteSpace($value))
    $value
}

if (-not $Pattern) { $Pattern = Read-Required 'Username pattern (for example opal-user-{id} or opal-test)' }
if ($Pattern -match '@') { $Pattern = ($Pattern -split '@', 2)[0] }
$hasId = $Pattern -match '\{id\}'

if ($hasId) {
    if (-not $PSBoundParameters.ContainsKey('StartId')) { $StartId = [int](Read-Required 'Starting ID') }
    if (-not $PSBoundParameters.ContainsKey('EndId')) { $EndId = [int](Read-Required 'Ending ID') }
    if ($StartId -lt 0 -or $EndId -lt $StartId) { throw 'The ID range is invalid.' }
} else {
    $StartId = 0; $EndId = 0
}

if ($ThrottleLimit -lt 1 -or $ThrottleLimit -gt 20) { throw 'ThrottleLimit must be between 1 and 20.' }
if (-not $Password -and -not $WhatIf) {
    $Password = Read-Host 'New password (input is hidden)' -AsSecureString
}

$users = if ($hasId) {
    $StartId..$EndId | ForEach-Object { "$($Pattern -replace '\{id\}', $_)@$Domain" }
} else { @("$Pattern@$Domain") }

if (-not $SkipPreview) {
    Write-Host "`nTargeting $($users.Count) account(s):" -ForegroundColor Cyan
    $users | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    if ($users.Count -gt 10) { Write-Host "  ... and $($users.Count - 10) more" }
    if ($WhatIf) { Write-Host 'WhatIf: no changes made.' -ForegroundColor Yellow; return }
    if ((Read-Host 'Continue? (Y/N)') -notmatch '^(y|yes)$') { return }
}
if ($WhatIf) { Write-Host 'WhatIf: no changes made.' -ForegroundColor Yellow; return }

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) { throw 'Install Microsoft.Graph.Users before running this script.' }
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
try { $context = Get-MgContext -ErrorAction Stop } catch { $context = $null }

if (-not $context) {
    if (-not $TenantId) { $TenantId = Read-Required 'Microsoft Entra tenant ID' }
    Connect-MgGraph -TenantId $TenantId -Scopes 'User.EnableDisableAccount.All', 'User.ReadWrite.All' -NoWelcome
    $context = Get-MgContext -ErrorAction Stop
}
if (-not $context) { throw 'Unable to connect to Microsoft Graph.' }
if ($TenantId -and $context.TenantId -and $context.TenantId -ne $TenantId) {
    throw "The current Graph connection is for tenant $($context.TenantId), not the requested tenant $TenantId. Disconnect and reconnect to the intended tenant."
}

$plainPassword = $null
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try { $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }

$worker = {
    Import-Module Microsoft.Graph.Users
    $upn = $_
    $maxRetriesLocal = $using:MaxRetries
    $plainPasswordLocal = $using:plainPassword
    $out = [ordered]@{
        User = $upn; Status = 'Failed'; Actions = ''; Error = ''
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    $done = [System.Collections.Generic.List[string]]::new()
    try {
        $invoke = {
            param($body)
            for ($attempt = 1; $attempt -le $maxRetriesLocal; $attempt++) {
                try {
                    Update-MgUser -UserId $upn -BodyParameter $body -ErrorAction Stop
                    return
                } catch {
                    if ($attempt -eq $maxRetriesLocal) { throw }
                    Start-Sleep -Seconds ([Math]::Min(60, [Math]::Pow(2, $attempt)))
                }
            }
        }
        & $invoke @{ passwordProfile = @{ password = $plainPasswordLocal; forceChangePasswordNextSignIn = $false } }
        $done.Add('password')
        & $invoke @{ accountEnabled = $false }
        $done.Add('disabled')
        & $invoke @{ accountEnabled = $true }
        $done.Add('enabled')
        $out.Status = 'OK'; $out.Actions = $done -join ','
    } catch { $out.Actions = $done -join ','; $out.Error = $_.Exception.Message }
    [pscustomobject]$out
}

Write-Host "Processing $($users.Count) account(s) with throttle $ThrottleLimit..." -ForegroundColor Cyan
$results = if ($ThrottleLimit -eq 1) { $users | ForEach-Object { & $worker } } else {
    $users | ForEach-Object -Parallel $worker -ThrottleLimit $ThrottleLimit
}
$results | Export-Csv -Path $LogPath -NoTypeInformation
$successCount = @($results | Where-Object Status -eq 'OK').Count
$failedCount = $results.Count - $successCount
Write-Host "`nCompleted: $successCount succeeded, $failedCount failed" -ForegroundColor $(if ($failedCount) { 'Yellow' } else { 'Green' })
Write-Host "CSV log: $LogPath"
if ($failedCount) { $results | Where-Object Status -ne 'OK' | Format-Table User, Actions, Error -AutoSize }
