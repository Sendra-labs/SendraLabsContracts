# Creates temporary admin keys on this machine and writes them to a gitignored file.
# Fund the addresses, approve them with the three cold wallets, run the deploy scripts, then
# penalize these admins from the cold wallets and sweep the remaining gas.
#
#   .\script\ops\New-HotAdmins.ps1
#   .\script\ops\New-HotAdmins.ps1 -Count 3 -OutFile .\script\ops\hot-admins.local.json

[CmdletBinding()]
param(
    [int]$Count = 3,
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
if ($Count -lt 1 -or $Count -gt 10) { throw "Count must be between 1 and 10" }

$opsDir = $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $opsDir "hot-admins.local.json" }
if (Test-Path -LiteralPath $OutFile) { throw "Refusing to overwrite $OutFile" }

$cast = (Get-Command cast -ErrorAction SilentlyContinue).Source
if (-not $cast) {
    $foundry = Join-Path $env:USERPROFILE ".foundry\bin\cast.exe"
    if (Test-Path -LiteralPath $foundry) { $cast = $foundry }
}
if (-not $cast) { throw "cast is not installed. Install Foundry and run this again." }

$wallets = @()
for ($i = 1; $i -le $Count; $i++) {
    $raw = & $cast wallet new
    if ($LASTEXITCODE -ne 0) { throw "cast wallet new failed" }
    $address = $null
    $key = $null
    foreach ($line in $raw) {
        if ($line -match "^Address:\s*(\S+)") { $address = $Matches[1] }
        if ($line -match "^Private key:\s*(\S+)") { $key = $Matches[1] }
    }
    if (-not $address -or -not $key) { throw "could not parse cast output" }
    $wallets += [ordered]@{
        name = "hot-admin-$i"
        address = $address
        privateKey = $key
    }
    Write-Host ("hot-admin-{0}  {1}" -f $i, $address)
}

$payload = [ordered]@{
    createdAt = (Get-Date).ToString("o")
    warning = "Local only. Do not commit, paste into chat, or copy to a synced folder. Penalize these admins and sweep the gas when the deploy is finished."
    wallets = $wallets
}
$payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutFile -Encoding utf8
Write-Host "wrote $OutFile"
Write-Host "private keys were not printed"
