# 66-sources.ps1 - Update third-party parts from THEIR sources, not from a copy in this repo.
#
# Mission Centre already updates Claude Code (Anthropic), pi (npm) and a pi fork (its git remote) from
# where they come from (65-updates.ps1). This file does the same for the rest:
#   * vendored skills  - skills/<name>/source.json names the upstream repo, branch, files and licence.
#                        New upstream commits are staged in .mission-centre/skill-sources/<name> and
#                        installed into ~/.claude/skills and ~/.agents/skills.
#   * pi packages      - `pi update --extensions` (pi updates its own packages from their sources).
#   * tokenjuice       - re-run its own installer when npm has a newer version than the pi extension.
#
# Rules (same as the rest of the updater): throttled by toolUpdates.intervalHours, mode check asks and
# auto does not, never blocks a launch, never throws. Two extra rules for skills:
#   * A skill you changed locally is never overwritten; it is reported instead.
#   * If the upstream licence file no longer matches the licence recorded in source.json, the update
#     is refused: licences travel with the code, and a changed one needs a human look.

function Get-SkillSourceConfig {
    # skills/<name>/source.json as an object, or $null when the skill has no upstream (it lives here).
    param([string]$Name)
    $p = Join-Path (Join-Path $BundledSkillsDir $Name) 'source.json'
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-SkillStagingDir {
    param([string]$Name)
    return (Join-Path (Join-Path $MissionStateDir 'skill-sources') $Name)
}

function Get-SkillSourceDir {
    # Where installs copy a skill from: the newest upstream copy staged by Update-SkillFromSource when
    # there is one, else the copy bundled in this repo.
    param([string]$Name)
    $staged = Get-SkillStagingDir $Name
    if (Test-Path -LiteralPath (Join-Path $staged 'SKILL.md') -PathType Leaf) { return $staged }
    return (Join-Path $BundledSkillsDir $Name)
}

function Get-SkillSourceCommit {
    # The upstream commit the current source copy (staged or bundled) was taken from.
    param([string]$Name)
    $p = Join-Path (Get-SkillSourceDir $Name) 'source.json'
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
    try { return [string](Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json).commit } catch { return '' }
}

function Get-SkillUpstreamHead {
    # Commit at the tip of the upstream branch, '' when unreachable. Read-only (git ls-remote).
    param([object]$Source)
    $git = Get-GitExecutable
    if (-not $git) { return '' }
    $ref = "refs/heads/$([string]$Source.ref)"
    $r = Invoke-ProcessCapture -FilePath $git -ArgumentList @('ls-remote', [string]$Source.repo, $ref) -TimeoutSeconds 30
    if (-not $r.ok -or $r.out -notmatch '^([0-9a-f]{40})\s') { return '' }
    return $Matches[1]
}

function Test-SkillLicenceMatches {
    # Pure: does the upstream licence text still match the licence recorded in source.json?
    # 'MIT' -> the text must contain 'MIT License' (or 'Permission is hereby granted, free of charge').
    param([string]$LicenceText, [string]$Expected)
    if ([string]::IsNullOrWhiteSpace($LicenceText) -or [string]::IsNullOrWhiteSpace($Expected)) { return $false }
    switch -regex ($Expected) {
        '^MIT$'        { return ($LicenceText -match 'MIT License' -or $LicenceText -match 'Permission is hereby granted, free of charge') }
        '^Apache-2\.0$' { return ($LicenceText -match 'Apache License' -and $LicenceText -match 'Version 2\.0') }
        default        { return ($LicenceText -match [regex]::Escape($Expected)) }
    }
}

function Update-SkillFromSource {
    # Fetch the upstream branch, stage the listed files over the bundled copy, and install it into every
    # harness where the installed copy is unmodified. Returns @{ status; detail }:
    #   status = current | updated | refused | failed
    param([string]$Name)
    $res = [PSCustomObject]@{ status = 'failed'; detail = '' }
    $src = Get-SkillSourceConfig $Name
    if (-not $src) { $res.detail = 'no source.json'; return $res }
    $git = Get-GitExecutable
    if (-not $git) { $res.detail = 'git not found'; return $res }

    $head = Get-SkillUpstreamHead $src
    if (-not $head) { $res.detail = "cannot reach $($src.repo)"; return $res }
    $have = Get-SkillSourceCommit $Name
    if ($head -eq $have) { $res.status = 'current'; $res.detail = $head.Substring(0, 9); return $res }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mc-skill-' + [guid]::NewGuid().ToString('N'))
    try {
        $clone = Join-Path $tmp 'upstream'
        $c = Invoke-ProcessCapture -FilePath $git -ArgumentList @('clone', '--quiet', '--depth', '1', '--branch', [string]$src.ref, [string]$src.repo, $clone) -TimeoutSeconds 120
        if (-not $c.ok) { $res.detail = "clone of $($src.repo) failed"; return $res }

        $licFile = Join-Path $clone ([string]$(if ($src.PSObject.Properties['licenceFile']) { $src.licenceFile } else { 'LICENSE' }))
        $licText = if (Test-Path -LiteralPath $licFile -PathType Leaf) { [System.IO.File]::ReadAllText($licFile) } else { '' }
        if (-not (Test-SkillLicenceMatches $licText ([string]$src.licence))) {
            $res.status = 'refused'
            $res.detail = "upstream licence no longer reads as $($src.licence); not updated (check $($src.repo))"
            return $res
        }

        # New source copy = the bundled folder (provenance files) with the upstream files laid over it.
        $stage = Join-Path $tmp 'stage'
        Copy-Item -LiteralPath (Join-Path $BundledSkillsDir $Name) -Destination $stage -Recurse -Force
        foreach ($item in @($src.include)) {
            $from = Join-Path $clone ([string]$item)
            $to = Join-Path $stage ([string]$item)
            if (-not (Test-Path -LiteralPath $from)) { $res.detail = "upstream no longer has '$item'"; return $res }
            if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
            Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
        }
        $meta = Get-Content -LiteralPath (Join-Path $stage 'source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $meta.commit = $head
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $stage 'source.json'), ($meta | ConvertTo-Json -Depth 5), $utf8)

        # Install where the user has not changed the skill (installed == old source copy) or it is missing.
        $oldPrint = Get-SkillDirFingerprint (Get-SkillSourceDir $Name)
        $kept = @()
        foreach ($t in Get-SkillInstallTargets) {
            $dst = Join-Path $t.dir $Name
            if (Test-Path -LiteralPath (Join-Path $dst 'SKILL.md') -PathType Leaf) {
                if ((Get-SkillDirFingerprint $dst) -ne $oldPrint) { $kept += $t.harness; continue }
                Remove-Item -LiteralPath $dst -Recurse -Force
            } elseif (-not (Test-Path -LiteralPath $t.dir)) {
                New-Item -ItemType Directory -Path $t.dir -Force | Out-Null
            }
            Copy-Item -LiteralPath $stage -Destination $dst -Recurse -Force
        }

        $staging = Get-SkillStagingDir $Name
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        New-Item -ItemType Directory -Path (Split-Path $staging -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $stage -Destination $staging -Recurse -Force

        $res.status = 'updated'
        $res.detail = "now at $($head.Substring(0, 9))"
        if ($kept.Count -gt 0) { $res.detail += "; kept your changed copy for $($kept -join ', ') ([G] shows it)" }
        return $res
    } catch {
        $res.detail = "update failed: $_"
        return $res
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-SkillSourceUpdateCheck {
    # Throttled check of every vendored skill against its upstream. check = ask, auto = just do it.
    param([string]$Mode = $ToolUpdatesMode, [int]$IntervalHours = $ToolUpdateIntervalHours, [switch]$Force)
    $Mode = ([string]$Mode).ToLowerInvariant()
    if ($Mode -eq 'off') { return }
    $state = Get-ToolUpdateState
    foreach ($name in @(Get-BundledSkillNames)) {
        $src = Get-SkillSourceConfig $name
        if (-not $src) { continue }
        $key = "skill:$name"
        if (-not $Force -and -not (Test-ToolCheckDue $state $key $IntervalHours)) { continue }
        $head = Get-SkillUpstreamHead $src
        $state[$key] = @{ lastCheck = (Get-Date).ToString('o'); latest = $head }
        Save-ToolUpdateState $state
        if (-not $head) {
            if ($Force) { Write-Host "   skill $name`: cannot reach $($src.repo)" -ForegroundColor Yellow }
            continue
        }
        $have = Get-SkillSourceCommit $name
        if ($head -eq $have) {
            if ($Force) { Write-Host "   skill $name`: up to date with $($src.repo) ($($head.Substring(0, 9)))" -ForegroundColor DarkGreen }
            continue
        }
        Write-Host ''
        Write-Host "  skill $name`: new upstream version at $($src.repo)" -ForegroundColor Yellow
        $go = if ($Mode -eq 'auto') { $true } else { Read-YesNo '  Update it now?' 'Y' }
        if (-not $go) { Write-Host '  Skipped. [U] offers it again.' -ForegroundColor DarkGray; continue }
        $r = Update-SkillFromSource $name
        $color = switch ($r.status) { 'updated' { 'Green' } 'current' { 'DarkGreen' } default { 'Yellow' } }
        Write-Host "   skill $name`: $($r.status) - $($r.detail)" -ForegroundColor $color
        Write-UpdateLog $(if ($r.status -eq 'updated') { 'INFO' } else { 'WARN' }) "skill $name from source: $($r.status) $($r.detail)"
    }
}

function Get-TokenjuiceExtensionVersion {
    # Version stamped in pi's tokenjuice extension ('generated by tokenjuice vX'), '' when not installed.
    $cfgDir = Get-Variable -Name PiAgentDir -ValueOnly -ErrorAction SilentlyContinue
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $dir = if ($cfgDir) { $cfgDir } else { Join-Path (Join-Path $userHome '.pi') 'agent' }
    $f = Join-Path (Join-Path $dir 'extensions') 'tokenjuice.js'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return '' }
    try {
        $head = @(Get-Content -LiteralPath $f -TotalCount 5 -Encoding UTF8) -join "`n"
        if ($head -match 'generated by tokenjuice v([0-9][0-9A-Za-z.\-]*)') { return $Matches[1] }
    } catch { }
    return ''
}

function Invoke-PiSourceUpdates {
    # pi's packages (from their own sources, via pi) and tokenjuice (via its own installer).
    # Throttled; check = ask, auto = do. Runs before pi launches and from [U].
    param([string]$Mode = $ToolUpdatesMode, [int]$IntervalHours = $ToolUpdateIntervalHours, [switch]$Force)
    $Mode = ([string]$Mode).ToLowerInvariant()
    if ($Mode -eq 'off') { return }
    $state = Get-ToolUpdateState

    $pi = Get-Command 'pi' -ErrorAction SilentlyContinue
    if ($pi -and ($Force -or (Test-ToolCheckDue $state 'pi:packages' $IntervalHours))) {
        $go = if ($Mode -eq 'auto') { $true } elseif ($Force) { Read-YesNo '  Update pi packages from their sources (pi update --extensions)?' 'Y' } else { $false }
        if ($go) {
            $r = Invoke-ProcessCapture -FilePath $pi.Source -ArgumentList @('update', '--extensions', '--no-approve') -WorkingDirectory $MissionRootDir -TimeoutSeconds 300
            if ($r.ok) { if ($Force) { Write-Host '   pi packages: updated from their sources' -ForegroundColor DarkGreen } }
            else { Write-Host '   pi packages: pi update --extensions did not finish; try it by hand' -ForegroundColor Yellow }
            $state = Get-ToolUpdateState
            $state['pi:packages'] = @{ lastCheck = (Get-Date).ToString('o'); latest = '' }
            Save-ToolUpdateState $state
        }
    }

    $have = Get-TokenjuiceExtensionVersion
    if ($have -and ($Force -or (Test-ToolCheckDue $state 'npm:tokenjuice' $IntervalHours))) {
        $latest = Get-NpmLatestVersion 'tokenjuice'
        $state = Get-ToolUpdateState
        $state['npm:tokenjuice'] = @{ lastCheck = (Get-Date).ToString('o'); latest = $latest }
        Save-ToolUpdateState $state
        if ($latest -and (Compare-SemverLike $have $latest) -lt 0) {
            Write-Host "  tokenjuice for pi: $have -> $latest" -ForegroundColor Yellow
            $go = if ($Mode -eq 'auto') { $true } else { Read-YesNo '  Update it now (npx tokenjuice install pi)?' 'Y' }
            if ($go) {
                $npx = Get-Command 'npx' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $npx) { $npx = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1 }
                $r = if ($npx) { Invoke-ProcessCapture -FilePath $npx.Source -ArgumentList @('--yes', "tokenjuice@$latest", 'install', 'pi') -TimeoutSeconds 300 } else { $null }
                $now = Get-TokenjuiceExtensionVersion
                if ($r -and $r.ok -and $now -eq $latest) { Write-Host "   tokenjuice for pi: $now" -ForegroundColor Green }
                else { Write-Host '   tokenjuice for pi: update did not confirm; run npx tokenjuice install pi by hand' -ForegroundColor Yellow }
            }
        } elseif ($Force) {
            Write-Host "   tokenjuice for pi: $have (current)" -ForegroundColor DarkGreen
        }
    }
}

function Get-UpdateSourceRows {
    # Pure-ish: where every part updates from, for the [U] screen and the docs.
    $rows = New-Object System.Collections.Generic.List[object]
    $selfRemote = ''
    $git = Get-GitExecutable
    if ($git -and (Test-Path (Join-Path $MissionRootDir '.git'))) {
        $u = Invoke-ProcessCapture -FilePath $git -ArgumentList @('remote', 'get-url', 'origin') -WorkingDirectory $MissionRootDir -TimeoutSeconds 10
        if ($u.ok) { $selfRemote = Remove-UrlCredential $u.out.Trim() }
    }
    $rows.Add([PSCustomObject]@{ part = 'Mission Centre, profiles, own skills'; source = $(if ($selfRemote) { "$selfRemote (self-update)" } else { 'not a git checkout: no self-update' }) })
    if ($ToolUpdateIncludeClaudeCode) { $rows.Add([PSCustomObject]@{ part = 'Claude Code'; source = 'Anthropic (claude update / winget)' }) }
    foreach ($p in @($ToolUpdatePackages + $ToolUpdatePiPackages | Select-Object -Unique)) { $rows.Add([PSCustomObject]@{ part = $p; source = 'npm registry' }) }
    if ($PiForkEnabled) { $rows.Add([PSCustomObject]@{ part = 'pii (pi from source)'; source = "$PiForkRemote/$PiForkBranch in $PiForkRepoPath" }) }
    if (Get-Command 'pi' -ErrorAction SilentlyContinue) { $rows.Add([PSCustomObject]@{ part = 'pi packages'; source = 'their own sources (pi update --extensions)' }) }
    if (Get-TokenjuiceExtensionVersion) { $rows.Add([PSCustomObject]@{ part = 'tokenjuice for pi'; source = 'npm registry (npx tokenjuice install pi)' }) }
    foreach ($n in @(Get-BundledSkillNames)) {
        $s = Get-SkillSourceConfig $n
        if ($s) { $rows.Add([PSCustomObject]@{ part = "skill $n"; source = "$($s.repo) ($($s.ref)), licence $($s.licence)" }) }
    }
    return $rows.ToArray()
}
