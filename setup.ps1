#Requires -Version 5.1
<#
.SYNOPSIS
    One-time (and safe to re-run) setup for OpsKamer on Windows or macOS.

    * Checks the tools Mission Centre uses: git, node/npm, Claude Code, pi, and optionally Jig + Forge.
    * Installs pi (npm: @earendil-works/pi-coding-agent) when it is missing and you agree.
    * Optional -WithFork: clones a pi fork you choose (default github.com/leo-labs-ai/pi-mono) and adds
      a `pii` launcher; Mission Centre then keeps it merged and built.
    * Writes the pi engine settings into Mission Centre's config.json.

    It never stores keys. Model access is yours to set up: see docs/MODEL-ACCESS.md.
    Everything it changes is backed up first (*.bak-<timestamp>). Re-running only fixes drift.

.PARAMETER Provider
    pi provider for Mission Centre's pi launches (e.g. anthropic). Default: none, so pi uses the
    defaultProvider in your own ~/.pi/agent/settings.json. An existing pi setup is kept as it is.
.PARAMETER Model
    pi model id (e.g. claude-sonnet-5). Default: none (pi's own defaultModel).
.PARAMETER PiDefault
    Make pi the default engine for the single-letter launch keys ([L]/[C]/[R]). Without it,
    those keys keep launching Claude Code and pi stays on [PI]/[PC]/[PR].
.PARAMETER WithFork
    Also set up a pi fork from source as `pii`.
.PARAMETER ForkUrl
    Git URL of the fork. Default: https://github.com/leo-labs-ai/pi-mono.git
.PARAMETER ForkPath
    Where the fork clone is or should go. Default: <scanRoot>/pi-mono.
.PARAMETER Yes
    Answer yes to every prompt (for scripted installs).
.EXAMPLE
    pwsh ./setup.ps1                     # macOS
    powershell -ExecutionPolicy Bypass -File .\setup.ps1   # Windows
#>
param(
    [string]$Provider = '',
    [string]$Model = '',
    [switch]$PiDefault,
    [switch]$WithFork,
    [string]$ForkUrl = 'https://github.com/leo-labs-ai/pi-mono.git',
    [string]$ForkPath = '',
    [switch]$Yes
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$McDir      = $PSScriptRoot
$ConfigPath = Join-Path $McDir 'config.json'
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$IsWin      = ($env:OS -eq 'Windows_NT')
$UserHome   = if ($HOME) { $HOME } else { $env:USERPROFILE }
$script:Problems = [System.Collections.Generic.List[string]]::new()

function Step($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   ok   $m" -ForegroundColor Green }
function Info($m) { Write-Host "        $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "   WARN $m" -ForegroundColor Yellow; $script:Problems.Add($m) }
function Confirm-Step([string]$Question) {
    if ($Yes) { return $true }
    $a = Read-Host "   $Question [Y/n]"
    return ($a -notmatch '^\s*[nN]')
}
function Test-Cmd([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Invoke-Git {
    # git without prompts; returns @{ ok; out }. Never throws (native stderr stays out of the error stream).
    param([string[]]$GitArgs, [string]$Dir = $McDir)
    $old = $env:GIT_TERMINAL_PROMPT; $env:GIT_TERMINAL_PROMPT = '0'
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Dir @GitArgs 2>&1 | ForEach-Object { "$_" }
        return [PSCustomObject]@{ ok = ($LASTEXITCODE -eq 0); out = (($out -join "`n").Trim()) }
    } finally { $ErrorActionPreference = $prevEap; $env:GIT_TERMINAL_PROMPT = $old }
}
function Backup($path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Copy-Item -LiteralPath $path -Destination "$path.bak-$Stamp"
        Info "backup: $path.bak-$Stamp"
    }
}
function Set-Prop {
    param($Obj, [string]$Name, $Value)
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Get-Child {
    param($Obj, [string]$Name)
    if (-not $Obj.PSObject.Properties[$Name] -or $null -eq $Obj.$Name) { Set-Prop $Obj $Name ([PSCustomObject]@{}) }
    return $Obj.$Name
}
function Resolve-Home([string]$p) {
    if ($p -and $p.StartsWith('~')) { return (Join-Path $UserHome $p.Substring(1).TrimStart('/', '\')) }
    return $p
}

# ---------------------------------------------------------------------------------------------
Step 'Prerequisites'
if (-not (Test-Cmd 'git')) { throw 'git is required. Install it first (Windows: winget install Git.Git; macOS: xcode-select --install).' }
Ok 'git found'
foreach ($cmd in 'node', 'npm') {
    if (Test-Cmd $cmd) { Ok "$cmd found" } else { Warn "$cmd is not on PATH (install Node.js LTS: https://nodejs.org)" }
}
if (Test-Cmd 'claude') { Ok 'Claude Code found' }
else { Warn 'Claude Code is not on PATH (https://docs.anthropic.com/en/docs/claude-code). The Claude launch keys need it.' }
if (Test-Cmd 'jig') { Ok 'jig found' }
else { Info 'jig not found (optional): launches fall back to plain Claude Code. Install: https://github.com/jdforsythe/jig' }
$pluginsFile = Join-Path (Join-Path (Join-Path $UserHome '.claude') 'plugins') 'installed_plugins.json'
if ((Test-Path -LiteralPath $pluginsFile) -and ((Get-Content -LiteralPath $pluginsFile -Raw) -match '"forge@forge"')) { Ok 'Forge plugin installed in Claude Code' }
else { Info 'Forge plugin not installed (optional, for kickoffs). In Claude Code: /plugin marketplace add jdforsythe/forge  then  /plugin install forge@forge' }
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "No config.json in $McDir yet. Start Mission Centre once (launch.bat / launch.sh creates it), close it, then re-run this."
}

# ---------------------------------------------------------------------------------------------
Step 'pi'
$piPkg = '@earendil-works/pi-coding-agent'
if (Test-Cmd 'pi') { Ok 'pi found' }
elseif ((Test-Cmd 'npm') -and (Confirm-Step "pi is not installed. Install it now (npm i -g $piPkg)?")) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & npm i -g "$piPkg@latest" 2>&1 | ForEach-Object { Info "$_" }
    $ErrorActionPreference = $prevEap
    if (Test-Cmd 'pi') { Ok 'pi installed' } else { Warn 'pi did not install; see the npm output above.' }
} else { Warn "pi is not installed. Install it with: npm i -g $piPkg" }

# Which provider pi will use: -Provider, else the defaultProvider in pi's own settings.json.
$piAgentDir = Join-Path (Join-Path $UserHome '.pi') 'agent'
$effective = $Provider
if (-not $effective) {
    $piSettings = Join-Path $piAgentDir 'settings.json'
    try {
        if (Test-Path -LiteralPath $piSettings) {
            $ps = Get-Content -LiteralPath $piSettings -Raw | ConvertFrom-Json
            if ($ps.PSObject.Properties['defaultProvider']) { $effective = [string]$ps.defaultProvider }
        }
    } catch { Warn "could not read $piSettings ($_)" }
    if ($effective) { Ok "pi's own default provider: $effective (Mission Centre will use it)" }
    else { Info "no default provider in pi's settings yet; pi will ask, or pass -Provider" }
}
# Model access check for Anthropic: presence only, never the contents. Other providers: pi's docs.
$authFile = Join-Path $piAgentDir 'auth.json'
if ($effective -eq 'anthropic' -and -not $env:ANTHROPIC_API_KEY -and -not (Test-Path -LiteralPath $authFile)) {
    Warn 'No ANTHROPIC_API_KEY in this shell and no pi auth file yet: pi cannot reach Anthropic until you add a key. See docs/MODEL-ACCESS.md.'
}

# ---------------------------------------------------------------------------------------------
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$scanRoot = Resolve-Home ([string]$config.scanRoot)
$forkReady = $null
if ($WithFork) {
    Step "pi fork from source (pii): $ForkUrl"
    if (-not $ForkPath) { $ForkPath = Join-Path $scanRoot 'pi-mono' }
    $ForkPath = Resolve-Home $ForkPath
    if (Test-Path -LiteralPath (Join-Path $ForkPath '.git')) {
        $u = Invoke-Git @('remote', 'get-url', 'origin') $ForkPath
        if ($u.out -ne $ForkUrl) { Warn "$ForkPath is a clone of $($u.out), not $ForkUrl. Pass -ForkPath <folder> for another place." }
        else { Ok "found the fork at $ForkPath"; $forkReady = $ForkPath }
    } elseif (Test-Path -LiteralPath $ForkPath) {
        Warn "$ForkPath exists but is not a git clone. Pass -ForkPath <folder> for another place."
    } elseif (Confirm-Step "Clone $ForkUrl into $ForkPath (large)?") {
        $clone = Invoke-Git @('clone', '--quiet', $ForkUrl, $ForkPath) (Split-Path $ForkPath)
        if ($clone.ok) { Ok "cloned to $ForkPath"; $forkReady = $ForkPath } else { Warn "clone failed: $($clone.out)" }
    }
    if ($forkReady) {
        # A fork's .gitattributes may mark generated files merge=ours. Right for the fork's own
        # upstream merges, wrong downstream: every sync would keep YOUR stale copies. Mission
        # Centre refuses to update while the driver is registered, so remove it here.
        if ((Invoke-Git @('config', '--local', '--get', 'merge.ours.driver') $forkReady).ok) {
            [void](Invoke-Git @('config', '--local', '--unset', 'merge.ours.driver') $forkReady)
            Ok 'removed merge.ours.driver from the clone'
        }
        $prefix = ''
        try { $prefix = ([string](& npm config get prefix 2>$null | Select-Object -First 1)).Trim() } catch { }
        $binDir = if ($IsWin) { $prefix } else { Join-Path $prefix 'bin' }
        $cli = Join-Path (Join-Path (Join-Path (Join-Path $forkReady 'packages') 'coding-agent') 'dist') 'cli.js'
        if ($prefix -and (Test-Path -LiteralPath $binDir)) {
            # PI_SKIP_VERSION_CHECK: a fork numbers itself differently from upstream pi, so pi's own
            # "update available" banner is wrong for pii; Mission Centre updates the fork.
            # PI_COMMAND_NAME: in-app hints (resume / update / restart) name `pii`, not `pi`.
            if ($IsWin) {
                $piiPath = Join-Path $binDir 'pii.cmd'
                $body = (@('@echo off', "rem pii = pi built from $forkReady by Mission Centre", 'setlocal',
                    'set PI_SKIP_VERSION_CHECK=1', 'set "PI_COMMAND_NAME=pii"', "set `"PII_CLI=$cli`"",
                    'if not exist "%PII_CLI%" (',
                    '    >&2 echo pii: build not found at "%PII_CLI%". Launch pi from Mission Centre once to build it.',
                    '    exit /b 1', ')', 'node "%PII_CLI%" %*', 'exit /b %ERRORLEVEL%') -join "`r`n") + "`r`n"
            } else {
                $piiPath = Join-Path $binDir 'pii'
                $body = (@('#!/bin/sh', "# pii = pi built from $forkReady by Mission Centre",
                    'export PI_SKIP_VERSION_CHECK=1', 'export PI_COMMAND_NAME=pii', "PII_CLI='$cli'",
                    'if [ ! -f "$PII_CLI" ]; then', '  echo "pii: build not found at $PII_CLI. Launch pi from Mission Centre once to build it." >&2',
                    '  exit 1', 'fi', 'exec node "$PII_CLI" "$@"') -join "`n") + "`n"
            }
            $cur = if (Test-Path -LiteralPath $piiPath) { [System.IO.File]::ReadAllText($piiPath) } else { '' }
            if ($cur -ne $body) {
                [System.IO.File]::WriteAllText($piiPath, $body)
                if (-not $IsWin) { & chmod +x $piiPath }
                Ok "pii launcher: $piiPath"
            } else { Ok 'pii launcher in place' }
            if (-not (Test-Path -LiteralPath $cli)) { Info 'pii is not built yet: Mission Centre builds it on the first pi launch (several minutes).' }
        } else { Warn 'npm prefix not found - pii launcher not written' }
    }
}

# ---------------------------------------------------------------------------------------------
Step "Mission Centre config ($ConfigPath)"
$before = Get-Content -LiteralPath $ConfigPath -Raw
$pi = Get-Child $config 'pi'
Set-Prop $pi 'enabled' $true
Set-Prop $pi 'command' $(if ($forkReady) { 'pii' } else { 'pi' })
# Only an explicit -Provider / -Model changes them; otherwise keep what is there (empty = pi's own).
if ($PSBoundParameters.ContainsKey('Provider')) { Set-Prop $pi 'provider' $Provider }
elseif (-not $pi.PSObject.Properties['provider']) { Set-Prop $pi 'provider' '' }
if ($PSBoundParameters.ContainsKey('Model')) { Set-Prop $pi 'model' $Model }
elseif (-not $pi.PSObject.Properties['model']) { Set-Prop $pi 'model' '' }
$piLabel = if ($pi.provider -or $pi.model) { (@($pi.provider, $pi.model) | Where-Object { $_ }) -join '/' } else { "pi's own settings" }
if ($PiDefault) { Set-Prop $config 'defaultEngine' 'pi' }

$tu = Get-Child $config 'toolUpdates'
Set-Prop $tu 'enabled' $true
if (-not $tu.PSObject.Properties['mode']) { Set-Prop $tu 'mode' 'check' }
Set-Prop $tu 'includeClaudeCode' $true
Set-Prop $tu 'checkPiOnLaunch' $true
if (-not $tu.PSObject.Properties['intervalHours']) { Set-Prop $tu 'intervalHours' 24 }
$pf = Get-Child $tu 'piFork'
if ($forkReady) {
    Set-Prop $pf 'enabled' $true
    Set-Prop $pf 'repoPath' $forkReady
    Set-Prop $pf 'remote' 'origin'
    Set-Prop $pf 'branch' 'main'
    if (-not $pf.PSObject.Properties['buildScript']) { Set-Prop $pf 'buildScript' 'build:offline' }
    Set-Prop $pf 'fallbackCommand' 'pi'
}
Set-Prop (Get-Child $config 'selfUpdate') 'enabled' $true
if (-not $config.PSObject.Properties['deviceName'] -or -not $config.deviceName) {
    Set-Prop $config 'deviceName' $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName })
}

$after = $config | ConvertTo-Json -Depth 20
if (($before -replace '\s', '') -ne ($after -replace '\s', '')) {
    Backup $ConfigPath
    $after | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Ok "config.json updated: pi engine ($piLabel)$(if ($PiDefault) { ', pi is the default engine' }), tool updates, self-update"
} else { Ok 'config.json already up to date' }

# ---------------------------------------------------------------------------------------------
Write-Host ''
if ($script:Problems.Count -eq 0) {
    Write-Host 'Done. Start Mission Centre again (close any open Mission Centre window first).' -ForegroundColor Green
} else {
    Write-Host "Done with $($script:Problems.Count) warning(s):" -ForegroundColor Yellow
    foreach ($p in $script:Problems) { Write-Host "  - $p" -ForegroundColor Yellow }
    exit 1
}
