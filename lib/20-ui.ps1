# 20-ui.ps1 - Console rendering + menus
# Split from Mission-Centre.ps1. Dot-sourced by the root script; relies on the
# script-scoped config globals ($ScanRoot, $Pi*, etc.) defined there.

function Write-Banner {
    # Retro-future banner when ANSI is available; the original 16-color box is the fallback.
    if ($script:McVt) { Write-McVibeBanner; return }
    $inner  = 44
    $title  = '  MISSION CENTRE  '
    $padL   = [int][math]::Floor(($inner - $title.Length) / 2)
    $padR   = $inner - $title.Length - $padL
    $hLine  = [string]$C_H * $inner
    $top    = [string]$C_TL + $hLine + [string]$C_TR
    $mid    = [string]$C_V  + (' ' * $padL) + $title + (' ' * $padR) + [string]$C_V
    $bot    = [string]$C_BL + $hLine + [string]$C_BR
    Write-Host ''
    Write-Host $top -ForegroundColor Cyan
    Write-Host $mid -ForegroundColor Cyan
    Write-Host $bot -ForegroundColor Cyan
    Write-Host ''
}

function Write-Divider {
    Write-Host ([string]$C_DH * 46) -ForegroundColor DarkGray
}

function Write-MissionLog {
    param([string]$Level, [string]$Message)
    try {
        if (-not (Test-Path $MissionStateDir)) {
            New-Item -ItemType Directory -Path $MissionStateDir -Force | Out-Null
        }
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
        Add-Content -Path $MissionLogPath -Value $line -Encoding UTF8
    } catch { }
}

function Show-ProfileMenu {
    Write-Host '  Profiles:' -ForegroundColor DarkCyan
    foreach ($pname in $StarterProfiles) {
        $desc = Get-ProfileDescription $pname
        $label = "    $($pname.PadRight(10))"
        Write-Host $label -NoNewline -ForegroundColor White
        if ($desc) { Write-Host $desc -ForegroundColor DarkGray }
        else       { Write-Host '(not installed)' -ForegroundColor DarkGray }
    }
}

function Format-SessionAge {
    param($Session)
    try {
        # Prefer fileMtime (epoch ms) — always up-to-date; fall back to modified string
        if ($Session.fileMtime -and [long]$Session.fileMtime -gt 0) {
            $epoch = [datetime]'1970-01-01'
            $mod   = $epoch.AddMilliseconds([long]$Session.fileMtime).ToLocalTime()
        } else {
            $mod = [datetime]$Session.modified
        }
        $diff = (Get-Date) - $mod
        if ($diff.TotalMinutes -lt 60)  { return "$([int]$diff.TotalMinutes)m ago" }
        if ($diff.TotalHours   -lt 24)  { return "$([int]$diff.TotalHours)h ago" }
        if ($diff.TotalDays    -lt 30)  { return "$([int]$diff.TotalDays)d ago" }
        return $mod.ToString('yyyy-MM-dd')
    } catch {
        return '?'
    }
}

function Format-EpochMsAge {
    # Age string from a raw epoch-millisecond timestamp (the home screen's recency probe).
    param([long]$Ms)
    if ($Ms -le 0) { return '' }
    try {
        $mod  = ([datetime]'1970-01-01').AddMilliseconds($Ms).ToLocalTime()
        $diff = (Get-Date) - $mod
        if ($diff.TotalMinutes -lt 60) { return "$([int]$diff.TotalMinutes)m ago" }
        if ($diff.TotalHours   -lt 24) { return "$([int]$diff.TotalHours)h ago" }
        if ($diff.TotalDays    -lt 30) { return "$([int]$diff.TotalDays)d ago" }
        return $mod.ToString('yyyy-MM-dd')
    } catch { return '' }
}

function Write-ProjectRow {
    # Shared one-line project row used by the home, all-projects, and find views.
    # $Number is the project's stable global index so it means the same thing everywhere.
    param([int]$Number, [object]$Project, [string]$Trailer = '')
    $name = [string](Get-ProjectName $Project)
    $prof = [string](Get-OptionalProperty $Project 'profile' '')
    $num  = ("[{0}]" -f $Number).PadRight(5)
    Write-Host "   $num " -NoNewline -ForegroundColor Yellow
    Write-Host $name.PadRight(22) -NoNewline -ForegroundColor White
    if ($prof) { Write-Host (" [$prof]").PadRight(13) -NoNewline -ForegroundColor DarkCyan }
    else       { Write-Host (''.PadRight(13))         -NoNewline }
    if ($Trailer) { Write-Host "  $Trailer" -ForegroundColor DarkGray } else { Write-Host '' }
}

function Show-ProjectMenu {
    param([object[]]$Projects)

    Write-Banner

    # Compact home: show only the most-recently-active projects. Everything else is one
    # keystroke away ([/] find, [A] all), so the actions + prompt stay on screen no matter
    # how many projects exist.
    $ranked = @()
    $dormantCount = 0
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        if (Test-ProjectDormant $Projects[$i]) { $dormantCount++; continue }
        $ms = Get-ProjectLastActivityMs $Projects[$i].path
        if ($ms -gt 0) {
            $ranked += [PSCustomObject]@{ Num = $i + 1; Project = $Projects[$i]; Ms = $ms }
        }
    }
    $recent = @($ranked | Sort-Object Ms -Descending | Select-Object -First $HomeRecentCount)

    if ($recent.Count -gt 0) {
        Write-Host '  Recent projects' -ForegroundColor DarkCyan
        foreach ($r in $recent) { Write-ProjectRow $r.Num $r.Project (Format-EpochMsAge $r.Ms) }
    } else {
        Write-Host '  No recent sessions yet - use [A] all projects or [/] find.' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   [/] find a project        [A] all projects (by profile)' -ForegroundColor Cyan
    Write-Host "   [D] dormant projects ($dormantCount)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Divider

    Write-Host "  [M]   New focused Meta Mission - jig run $MetaProfile" -ForegroundColor Magenta
    Write-Host '  [MC]  Continue latest meta mission'                       -ForegroundColor Magenta
    Write-Host '  [MR]  Open meta mission resume picker'                    -ForegroundColor Magenta
    Write-Host '  [N]   New project'                                        -ForegroundColor Green
    Write-Host '  [I]   Import existing folder as a project'                 -ForegroundColor Green
    Write-Host '  [NA]  New App (vibe-check) - idea -> buildable plan'      -ForegroundColor Green
    Write-Host '  [H]   Environment health check'                          -ForegroundColor Cyan
    Write-Host '  [G]   Install starter Jig profiles + bundled skills'      -ForegroundColor Cyan
    Write-Host '  [U]   Update tools (pi, claude, agent CLIs)'               -ForegroundColor Cyan
    Write-Host "  [SR]  Change scan root (current: $ScanRoot)"              -ForegroundColor DarkGray
    Write-Host ''
    $choice = Read-McMenuLine '  Pick a recent #, [/] find, [A] all, [D] Dormant, [O] Other devices, [M] Meta, [N] New, [I] Import, [NA] New App, [S] Scan, [SR] Root, [H] Health, [G] Profiles, [U] Updates, [Q] Quit'
    if ($null -eq $choice) { return 'Q' }
    return $choice.Trim()
}

function Show-AllProjects {
    # Full project list grouped by profile (alphabetical, blank profile last). Returns the
    # typed choice: a stable global project number, or 'B' to go back.
    param([object[]]$Projects)

    Clear-Host
    Write-Banner
    Write-Host '  All projects (by profile)' -ForegroundColor Cyan
    Write-Host ''

    $byProfile = @{}
    $order = [System.Collections.Generic.List[string]]::new()
    $dormantCount = 0
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        if (Test-ProjectDormant $Projects[$i]) { $dormantCount++; continue }
        $prof = [string](Get-OptionalProperty $Projects[$i] 'profile' '')
        $key = if ([string]::IsNullOrWhiteSpace($prof)) { '(no profile)' } else { $prof }
        if (-not $byProfile.ContainsKey($key)) {
            $byProfile[$key] = [System.Collections.Generic.List[object]]::new()
            [void]$order.Add($key)
        }
        [void]$byProfile[$key].Add([PSCustomObject]@{ Num = $i + 1; Project = $Projects[$i] })
    }
    $groups = @($order | Where-Object { $_ -ne '(no profile)' } | Sort-Object)
    if ($order -contains '(no profile)') { $groups += '(no profile)' }

    foreach ($g in $groups) {
        Write-Host ("  == {0} ==" -f $g) -ForegroundColor DarkCyan
        foreach ($entry in $byProfile[$g]) {
            $desc = Get-TruncatedSummary ([string](Get-OptionalProperty $entry.Project 'description' '')) 40
            Write-ProjectRow $entry.Num $entry.Project $desc
        }
    }
    if ($dormantCount -gt 0) {
        Write-Host ''
        Write-Host "  $dormantCount dormant project(s) hidden - [D] to view" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Divider
    $choice = Read-Host '  Pick a project number, [D] dormant, or [B] back'
    if ($null -eq $choice) { return 'B' }
    return $choice.Trim()
}

function Show-ProjectFilter {
    # Substring search over name/description/profile. Loops so the user can refine the term.
    # Returns a stable global project number, or 'B' to go back.
    param([object[]]$Projects, [string]$Term)

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($Term)) {
            Clear-Host
            Write-Banner
            $entered = Read-Host '  Find (part of a name or description), or [B] back'
            if ($null -eq $entered) { return 'B' }
            $Term = $entered.Trim()
            if ([string]::IsNullOrWhiteSpace($Term) -or $Term.ToUpper() -eq 'B') { return 'B' }
        }

        $needle = $Term.ToLowerInvariant()
        $hits = @()
        for ($i = 0; $i -lt $Projects.Count; $i++) {
            $p = $Projects[$i]
            $hay = ("{0} {1} {2}" -f (Get-ProjectName $p), (Get-OptionalProperty $p 'description' ''), (Get-OptionalProperty $p 'profile' '')).ToLowerInvariant()
            if ($hay.Contains($needle)) { $hits += [PSCustomObject]@{ Num = $i + 1; Project = $p } }
        }

        Clear-Host
        Write-Banner
        Write-Host ("  Find: ""{0}""  -  {1} of {2}" -f $Term, $hits.Count, $Projects.Count) -ForegroundColor Cyan
        Write-Host ''
        if ($hits.Count -eq 0) {
            Write-Host '  No matches.' -ForegroundColor DarkGray
        } else {
            foreach ($entry in $hits) {
                $desc = Get-TruncatedSummary ([string](Get-OptionalProperty $entry.Project 'description' '')) 40
                if (Test-ProjectDormant $entry.Project) { $desc = "(dormant) $desc" }
                Write-ProjectRow $entry.Num $entry.Project $desc
            }
        }
        Write-Host ''
        Write-Divider
        $choice = Read-Host '  Pick a number, [/] new search, or [B] back'
        if ($null -eq $choice) { return 'B' }
        $choice = $choice.Trim()
        if ($choice.ToUpper() -eq 'B') { return 'B' }
        if ($choice -eq '/' -or $choice -eq '') { $Term = ''; continue }
        if ($choice -like '/*') { $Term = $choice.Substring(1).Trim(); continue }
        return $choice
    }
}

function Show-DormantProjects {
    # The dormant shelf: list, reactivate (R#, lists/ranges ok), bulk-park idle projects, or
    # open one. Loops until the user opens a project (returns its stable number) or goes back ('B').
    param([ref]$ConfigRef)

    while ($true) {
        $projects = @($ConfigRef.Value)
        $dormant = @()
        for ($i = 0; $i -lt $projects.Count; $i++) {
            if (Test-ProjectDormant $projects[$i]) {
                $dormant += [PSCustomObject]@{ Num = $i + 1; Project = $projects[$i] }
            }
        }

        Clear-Host
        Write-Banner
        Write-Host ("  Dormant projects ({0})  -  hidden from home, [A] and meta missions" -f $dormant.Count) -ForegroundColor Cyan
        Write-Host ''
        if ($dormant.Count -eq 0) {
            Write-Host '  Nothing dormant. Use [P] to park idle projects, or [Z] inside any project.' -ForegroundColor DarkGray
        } else {
            foreach ($d in ($dormant | Sort-Object { (Get-ProjectName $_.Project).ToLowerInvariant() })) {
                $since = [string](Get-OptionalProperty $d.Project 'dormantSince' '')
                $trail = if ($since) { "dormant since $since" } else { '' }
                Write-ProjectRow $d.Num $d.Project $trail
            }
        }
        Write-Host ''
        Write-Divider
        Write-Host "   [R#] reactivate (e.g. R12 or R3,5-7)   [P] park projects idle $DormantIdleDays+ days" -ForegroundColor Cyan
        $choice = Read-Host '  Pick a number to open, [R#] reactivate, [P] park idle, or [B] back'
        if ($null -eq $choice) { return 'B' }
        $choice = $choice.Trim()
        $up = $choice.ToUpper()
        if ($up -eq 'B' -or $up -eq '') { return 'B' }

        if ($up -eq 'P') {
            Invoke-ParkIdleProjects $ConfigRef $DormantIdleDays
            Read-Host '  Press Enter to continue'
        } elseif ($up -match '^R\s*([\d,\-\s]+)$') {
            # Only dormant entries are touched; other numbers are ignored.
            $pick = @(ConvertTo-ProjectIndexSelection ($Matches[1] -replace '\s', '') $projects.Count |
                      Where-Object { Test-ProjectDormant $projects[$_] })
            if ($pick.Count -eq 0) {
                Write-Host '  No dormant project matched that number.' -ForegroundColor Red
            } else {
                $n = Set-ProjectDormant $ConfigRef $pick $false
                Write-Host "  Reactivated $n project(s) - back on the home screen and [A]." -ForegroundColor Green
            }
            Start-Sleep -Seconds 1
        } elseif ($choice -match '^\d+$') {
            return $choice
        } else {
            Write-Host '  Unknown option.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Show-LaunchMenu {
    param([object]$Project)

    $profileName = Get-OptionalProperty $Project 'profile' $DefaultProfile
    $profileDesc = Get-ProfileDescription $profileName

    Write-Host ''
    Write-Host '  Project : ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Project.name  -NoNewline -ForegroundColor Cyan
    Write-Host "  [$profileName]" -ForegroundColor DarkCyan
    if ($profileDesc) {
        Write-Host "            $profileDesc" -ForegroundColor DarkGray
    }
    Write-Host '  Path    : ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Project.path  -ForegroundColor DarkGray
    $isDormant = Test-ProjectDormant $Project
    if ($isDormant) {
        Write-Host '  Status  : DORMANT - hidden from home; [Z] reactivates' -ForegroundColor Yellow
    }
    Write-Host ''

    # Show recent sessions if any exist
    $sessions = @(Get-RecentSessions $Project.path)
    if ($sessions.Count -gt 0) {
        Write-Host '  Recent missions:' -ForegroundColor DarkCyan
        $si = 1
        foreach ($s in $sessions) {
            $age     = Format-SessionAge $s
            $summary = if ($s.summary) { $s.summary } else { $s.firstPrompt }
            $summary = Get-TruncatedSummary $summary
            $msgs    = if ($s.messageCount -gt 0) { "$($s.messageCount) msgs" } else { '' }
            Write-Host "   [R$si] " -NoNewline -ForegroundColor Green
            Write-Host "$summary" -NoNewline -ForegroundColor White
            if ($msgs) { Write-Host "  ($msgs, $age)" -ForegroundColor DarkGray }
            else       { Write-Host "  ($age)" -ForegroundColor DarkGray }
            $si++
        }
        Write-Host ''
    }

    if ($DefaultEngine -eq 'pi') {
        $needsKickoff = -not (Test-ProjectHasPlan $Project.path) -and [string](Get-OptionalProperty $Project 'kickoff' '') -ne 'skipped'
        if ($needsKickoff) {
            Write-Host "  [L]  New mission (pi)      - no $(Get-KickoffPlanFileName) yet: offers a kickoff (plan, then build) first" -ForegroundColor Green
        } else {
            Write-Host "  [L]  New mission (pi)      - $(Get-PiModelLabel), profile $profileName" -ForegroundColor Green
        }
        Write-Host '  [C]  Continue latest (pi)  - continue in this project'           -ForegroundColor Green
        Write-Host '  [R]  Resume picker (pi)    - choose from pi sessions'            -ForegroundColor Green
        Write-Host "  [CL] New mission (Claude)  - jig run $profileName -- --name ..." -ForegroundColor Blue
        Write-Host '  [CC] Continue latest (Claude)'                                   -ForegroundColor Blue
        Write-Host '  [CR] Resume picker (Claude)'                                     -ForegroundColor Blue
        Write-Host '  [J]  Launch with Jig       - pick a different profile'           -ForegroundColor Yellow
    } else {
        Write-Host "  [L]  New mission           - jig run $profileName -- --name ..." -ForegroundColor Green
        Write-Host '  [C]  Continue latest       - continue in this project'      -ForegroundColor Green
        Write-Host '  [R]  Resume picker         - choose from Claude sessions'   -ForegroundColor Green
        Write-Host '  [J]  Launch with Jig       - pick a different profile'           -ForegroundColor Yellow
        if ($PiEnabled) {
            Write-Host "  [PI] New mission (pi)      - $(Get-PiModelLabel)"      -ForegroundColor Blue
            Write-Host '  [PC] Continue latest (pi)  - continue in this project'           -ForegroundColor Blue
            Write-Host '  [PR] Resume picker (pi)    - choose from pi sessions'            -ForegroundColor Blue
        }
    }
    if ($sessions.Count -gt 0) {
        Write-Host '  [R#] Resume mission        - resume a session listed above'      -ForegroundColor Green
    }
    Write-Host '  [P]  Preflight profile'                                           -ForegroundColor Yellow
    Write-Host '  [X]  Context health/setup'                                        -ForegroundColor Cyan
    Write-Host '  [E]  Open folder'                                                    -ForegroundColor Cyan
    Write-Host '  [RN] Edit name / description / profile'                              -ForegroundColor DarkGray
    if ($isDormant) {
        Write-Host '  [Z]  Reactivate (back on the home screen)'                       -ForegroundColor Yellow
    } else {
        Write-Host '  [Z]  Make dormant (hide from home and [A])'                      -ForegroundColor DarkGray
    }
    Write-Host '  [RM] Remove from project list (folder untouched)'                    -ForegroundColor DarkGray
    Write-Host '  [B]  Back'                                                           -ForegroundColor DarkGray
    Write-Host ''
    Write-Divider
    $choice = Read-Host '  Choose'
    if ($null -eq $choice) { return 'B' }
    return $choice.Trim().ToUpper()
}
