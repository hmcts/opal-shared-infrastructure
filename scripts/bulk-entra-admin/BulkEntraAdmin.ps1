#requires -Version 7.2
<#!
.SYNOPSIS
  Safely bulk-update test users in Microsoft Entra ID.

.DESCRIPTION
  Generates users from a pattern such as opal-user-{id}, previews the target
  list, and optionally sets a password, disables, and/or re-enables accounts.
  Requires an existing Microsoft Graph PowerShell connection.
#>
[CmdletBinding()]
param(
    [string]$Pattern,
    [int]$StartId,
    [int]$EndId,
    [securestring]$Password,
    [switch]$ResetPassword,
    [switch]$DisableAccount,
    [switch]$EnableAccount,
    [int]$ThrottleLimit = 5,
    [int]$MaxRetries = 5,
    [string]$Domain = 'dev.platform.hmcts.net',
    [string]$LogPath = (Join-Path (Get-Location) ("BulkEntraAdmin-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),
    [switch]$SkipPreview,
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

$actionsSpecified = $ResetPassword -or $DisableAccount -or $EnableAccount
if (-not $actionsSpecified) {
    $ResetPassword = $true; $DisableAccount = $true; $EnableAccount = $true
}
if ($ThrottleLimit -lt 1 -or $ThrottleLimit -gt 20) { throw 'ThrottleLimit must be between 1 and 20.' }
if ($ResetPassword -and -not $Password -and -not $WhatIf) {
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

try { $context = Get-MgContext -ErrorAction Stop } catch { throw 'Connect to Microsoft Graph first, for example: Connect-MgGraph -Scopes User.ReadWrite.All' }
if (-not $context) { throw 'No Microsoft Graph connection found.' }
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) { throw 'Install Microsoft.Graph.Users before running this script.' }

$plainPassword = $null
if ($ResetPassword) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try { $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$worker = {
    Import-Module Microsoft.Graph.Users
    $upn = $_
    $maxRetriesLocal = $using:MaxRetries
    $resetPasswordLocal = $using:ResetPassword
    $disableAccountLocal = $using:DisableAccount
    $enableAccountLocal = $using:EnableAccount
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
        if ($resetPasswordLocal) {
            & $invoke @{ passwordProfile = @{ password = $plainPasswordLocal; forceChangePasswordNextSignIn = $false } }
            $done.Add('password')
        }
        if ($disableAccountLocal) { & $invoke @{ accountEnabled = $false }; $done.Add('disabled') }
        if ($enableAccountLocal) { & $invoke @{ accountEnabled = $true }; $done.Add('enabled') }
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
