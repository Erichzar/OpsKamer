#Requires -Version 5.1
# Bootstrap pi on Windows (or anywhere with PowerShell): installs pi, adds OpsKamer's pi config to
# ~/.pi/agent where you have none yet, optionally adds tokenjuice. Idempotent: safe to re-run.
# An existing pi config is KEPT (your provider, models and settings stay as they are); -Force replaces
# it, after a backup. Never touches keys: model access is yours (see ../../docs/MODEL-ACCESS.md).
param([switch]$Yes, [switch]$NoTokenjuice, [switch]$Force)
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$UserHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
$PiAgent  = Join-Path (Join-Path $UserHome '.pi') 'agent'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Confirm-Step([string]$q) { if ($Yes) { return $true }; return ((Read-Host "    $q [Y/n]") -notmatch '^\s*[nN]') }

# Get-FileHash is missing on some Windows PowerShell 5.1 installs, which made every re-run die.
# Hash via .NET instead.
function Get-Sha256($Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try { return [System.BitConverter]::ToString($sha.ComputeHash($stream)) }
    finally { $stream.Dispose(); $sha.Dispose() }
}
function Copy-WithBackup($Src, $Dst) {
    if (Test-Path $Dst) {
        if ((Get-Sha256 $Src) -eq (Get-Sha256 $Dst)) { Info "$(Split-Path -Leaf $Dst) already current"; return }
        if (-not $Force) { Info "kept your $(Split-Path -Leaf $Dst) (OpsKamer's version: $Src; -Force replaces yours after a backup)"; return }
        Copy-Item $Dst "$Dst.bak-$Stamp"
        Warn "backed up existing $(Split-Path -Leaf $Dst) -> $(Split-Path -Leaf $Dst).bak-$Stamp"
    }
    Copy-Item $Src $Dst -Force
    Info "installed $(Split-Path -Leaf $Dst)"
}

# --- 1. prerequisites -------------------------------------------------------
Info 'Checking prerequisites'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22.19 or newer is required: https://nodejs.org' }
$v = ((node --version) -replace '^v', '') -split '\.'
if ([int]$v[0] -lt 22 -or ([int]$v[0] -eq 22 -and [int]$v[1] -lt 19)) { throw "Node.js 22.19 or newer is required, found $(node --version)" }

if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
    Info 'Installing pi (@earendil-works/pi-coding-agent) globally'
    npm install -g '@earendil-works/pi-coding-agent'
} else {
    Info "pi already installed: $(pi --version)"
}

# --- 2. pi config -----------------------------------------------------------
# settings.json and semantic-grep.json only. models.json is yours (it can hold provider keys), so it
# is never overwritten; pi/pi-config/models.local-example.json shows how to add a local server.
Info "Installing pi config -> $PiAgent"
New-Item -ItemType Directory -Force -Path $PiAgent | Out-Null
foreach ($f in @('settings.json', 'semantic-grep.json')) {
    Copy-WithBackup (Join-Path (Join-Path $RepoRoot 'pi-config') $f) (Join-Path $PiAgent $f)
}

# --- 3. optional: tokenjuice (MIT, github.com/vincentkoc/tokenjuice) -------------------------------
# Compacts noisy shell output before it reaches the model. Installed by its own installer, not vendored.
if (-not $NoTokenjuice -and (Confirm-Step 'Install tokenjuice for pi (compacts long command output)?')) {
    npx --yes tokenjuice install pi
}

# --- 4. next steps ----------------------------------------------------------
Write-Host ''
Info 'Done. Next:'
Write-Host @"

  1. If pi has no model access yet, add your own (see docs/MODEL-ACCESS.md). For Anthropic, an API key:
       setx ANTHROPIC_API_KEY "<your key>"      (new terminals pick it up)
  2. Check it works:
       pi -p "Reply with exactly: PI OK"
  3. Skills: Mission Centre installs OpsKamer's skills into ~/.agents/skills on launch.
     Without Mission Centre, copy them yourself: skills/<name> -> ~/.agents/skills/<name>

"@
