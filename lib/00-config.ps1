# 00-config.ps1 - Configuration + first-run bootstrap
# Split from Mission-Centre.ps1. Dot-sourced by the root script; relies on the
# script-scoped config globals ($ScanRoot, $Pi*, etc.) defined there.

function Get-DefaultScanRoot {
    $candidates = @()
    if ($MissionIsMacOS -or $MissionIsLinux) {
        $candidates += (Join-Path $HOME 'Code')
        $candidates += (Join-Path $HOME 'Projects')
        $candidates += $HOME
    } else {
        $candidates += (Join-Path $HOME 'Projects')
        $candidates += 'C:\Dev'
        $candidates += $HOME
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate -PathType Container)) { return $candidate }
    }
    return $PSScriptRoot
}

function Get-WikiProfileVaults {
    # Build the profile -> vault routing map from config.json `wikiVaults` (see the wiki
    # section in Mission-Centre.ps1). Entries without a vault path are ignored.
    param([object]$Config)
    $map = @{}
    $vaultsConfig = Get-OptionalProperty $Config 'wikiVaults' $null
    if ($vaultsConfig) {
        foreach ($prop in $vaultsConfig.PSObject.Properties) {
            $vaultPath = [string](Get-OptionalProperty $prop.Value 'vault' '')
            if ([string]::IsNullOrWhiteSpace($vaultPath)) { continue }
            $map[$prop.Name] = @{
                vault   = $vaultPath
                sources = [string](Get-OptionalProperty $prop.Value 'sources' '')
            }
        }
    }
    return $map
}

function Get-AppConfig {
    $existing = $null
    if (Test-Path $AppConfigPath) {
        try {
            $existing = Get-Content $AppConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            # Corrupt/unparseable config: preserve it before prompting for a fresh one,
            # rather than silently overwriting the user's settings.
            $backup = "$AppConfigPath.bak"
            try { Copy-Item -LiteralPath $AppConfigPath -Destination $backup -Force } catch { }
            Write-Host "  WARN: config.json could not be parsed; backed up to $(Split-Path $backup -Leaf) and starting fresh." -ForegroundColor Yellow
            $existing = $null
        }
        if ($existing) {
            $scanRoot = Get-OptionalProperty $existing 'scanRoot' $null
            if ($scanRoot) {
                $existing.scanRoot = Resolve-UserPath $scanRoot
                return $existing
            }
        }
    }

    # First-run (config missing/corrupt) or an existing config that parsed but lacks scanRoot.
    Write-Host ''
    Write-Host '  Welcome to Mission Centre!' -ForegroundColor Cyan
    $defaultRoot = Get-DefaultScanRoot
    Write-Host '  Enter the root folder to scan for AI projects.' -ForegroundColor DarkGray
    if ($MissionIsMacOS -or $MissionIsLinux) {
        Write-Host '  Example: ~/Code  or  ~/Projects' -ForegroundColor DarkGray
    } else {
        Write-Host '  Example: C:\Dev  or  D:\Projects' -ForegroundColor DarkGray
    }
    Write-Host ''
    $root = Read-Host "  Scan root [$defaultRoot]"
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $defaultRoot }
    $root = Resolve-UserPath $root
    # Same check Set-ScanRoot does: a typo here would otherwise be saved silently and every
    # scan would just find nothing. Warn (don't block) - the folder may be created later.
    if (-not (Test-Path $root -PathType Container)) {
        Write-Host "  WARN: '$root' does not exist yet. Saving anyway; use [SR] later to change it." -ForegroundColor Yellow
    }

    if ($existing) {
        # Config parsed but only scanRoot was missing: merge in place, preserve all other keys.
        if (-not $existing.PSObject.Properties['scanRoot']) {
            $existing | Add-Member -NotePropertyName 'scanRoot' -NotePropertyValue $root
        } else {
            $existing.scanRoot = $root
        }
        try {
            $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $AppConfigPath -Encoding UTF8
            Write-Host '  Added scan root to existing config.json (other settings preserved).' -ForegroundColor Green
        } catch {
            Write-Host "  ERROR: Could not write config.json: $_" -ForegroundColor Red
            Write-Host '  Continuing with in-memory config for this session.' -ForegroundColor DarkYellow
        }
        Write-Host ''
        return $existing
    }

    $cfg = [PSCustomObject]@{
        scanRoot      = $root
        defaultProfile = 'standard'
        metaProfile    = 'forge'
        preflightMode  = 'warn'
        homeRecentCount = 5
        dormantIdleDays = 60
        autoDormant    = $true
        animations     = $true
        sound          = $true
        soundVolume    = 0.2
        wikiVaults     = [PSCustomObject]@{}
        contextIndex   = [PSCustomObject]@{
            enabled    = $false
            command    = 'npx ai-codex'
            maxAgeDays = 3
        }
        # Keep the toolchain current: agent CLIs release constantly, and Anthropic
        # version-gates new models on the Claude Code build (an old CLI gets
        # "version X or newer is required" for models that otherwise work).
        toolUpdates    = [PSCustomObject]@{
            enabled           = $true
            mode              = 'check'   # off | check | auto
            intervalHours     = 24
            includeClaudeCode = $true
            checkPiOnLaunch   = $true
            packages          = @('@earendil-works/pi-coding-agent')
            piPackages        = @('@earendil-works/pi-coding-agent')
            # Optional pi build from a git checkout, run as `pii` (set pi.command = 'pii').
            piFork            = [PSCustomObject]@{
                enabled         = $false
                repoPath        = ''
                remote          = 'origin'
                branch          = 'main'
                buildScript     = 'build:offline'
                fallbackCommand = 'pi'
            }
        }
        # pi launch engine. Empty provider/model = pi's own settings (~/.pi/agent/settings.json).
        # Model access is your own. See docs/MODEL-ACCESS.md.
        pi             = [PSCustomObject]@{
            enabled          = $false
            command          = 'pi'
            provider         = ''
            model            = ''
            modelCycle       = ''
            # Optional local model server: probed before a pi launch (any 2xx = up). Empty = off.
            healthUrl        = ''
            autoStart        = $true
            # Windows Scheduled Task that starts the server, or a shell command run in workingDir.
            taskName         = ''
            startCommand     = ''
            workingDir       = ''
            startWaitSeconds = 15
        }
    }
    # -Depth must exceed the deepest config nesting.
    try {
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $AppConfigPath -Encoding UTF8
        Write-Host "  Config saved to config.json" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: Could not write config.json: $_" -ForegroundColor Red
        Write-Host '  Continuing with in-memory defaults for this session.' -ForegroundColor DarkYellow
    }
    Write-Host ''
    return $cfg
}
