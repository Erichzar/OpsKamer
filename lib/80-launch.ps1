# 80-launch.ps1 - Terminal spawning + launch paths
# Split from Mission-Centre.ps1. Dot-sourced by the root script; relies on the
# script-scoped config globals ($ScanRoot, $Pi*, etc.) defined there.

function New-MetaMissionBrief {
    param([string]$Goal, [object[]]$Projects, [string]$MissionName)
    if (-not (Test-Path $MissionBriefsDir)) {
        New-Item -ItemType Directory -Path $MissionBriefsDir -Force | Out-Null
    }

    $briefPath = Join-Path $MissionBriefsDir "$MissionName.md"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Mission Brief: $Goal")
    $lines.Add('')
    $lines.Add("Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add("Scan root: $ScanRoot")
    $lines.Add("Meta profile: $MetaProfile")
    $lines.Add('')
    $lines.Add('## Goal')
    $lines.Add($Goal)
    $lines.Add('')
    $lines.Add('## Selected Projects')
    if ($Projects.Count -eq 0) {
        $lines.Add('- No projects selected. Ask the user to narrow the mission before broad exploration.')
    } else {
        foreach ($p in $Projects) {
            $lines.Add("- $(Get-ProjectName $p)")
            $lines.Add("  - Path: $($p.path)")
            $lines.Add("  - Profile: $(Get-OptionalProperty $p 'profile' $DefaultProfile)")
            $lines.Add("  - Description: $(Get-OptionalProperty $p 'description' '')")
        }
    }
    $lines.Add('')
    $lines.Add('## Operating Instructions')
    $lines.Add('- Use Forge mission planning to decide whether this needs one agent or a coordinated team.')
    $lines.Add('- Read only the selected project paths unless the user expands scope.')
    $lines.Add('- Start with project CLAUDE.md files and local mission notes before broad file exploration.')
    $lines.Add('- Prefer focused searches, small plans, and explicit artifact handoffs.')
    $lines.Add('- Keep token usage low by summarizing findings and avoiding full-tree reads.')

    Set-Content -Path $briefPath -Value $lines -Encoding UTF8
    return $briefPath
}

function Start-TerminalCommand {
    param([string]$WorkingDirectory, [string]$Command)

    $psCommand = "Set-Location -LiteralPath $(ConvertTo-PowerShellQuotedString $WorkingDirectory); $Command"
    Write-MissionLog 'INFO' "Start-TerminalCommand: Platform=$MissionPlatform OS=$MissionOS IsMac=$MissionIsMacOS IsLinux=$MissionIsLinux IsWin=$MissionIsWindows"

    if ($MissionIsWindows) {
        $shell = Get-Command 'pwsh' -ErrorAction SilentlyContinue
        if (-not $shell) { $shell = Get-Command 'powershell' -ErrorAction SilentlyContinue }
        if (-not $shell) {
            Write-Host "  ERROR: Could not find pwsh or powershell." -ForegroundColor Red
            return
        }
        try {
            Start-Process -FilePath $shell.Source -ArgumentList @('-NoExit', '-Command', $psCommand)
        } catch {
            Write-Host "  ERROR: Failed to launch terminal: $_" -ForegroundColor Red
            Write-MissionLog 'ERROR' "Start-Process (Windows) failed: $_"
        }
        return
    }

    if ($MissionIsMacOS) {
        if (-not (Test-Path '/usr/bin/osascript')) {
            $msg = 'osascript not found; cannot open Terminal.app.'
            Write-Host "  ERROR: $msg" -ForegroundColor Red
            Write-MissionLog 'ERROR' $msg
            return
        }
        $shellCommand = "pwsh -NoExit -Command $(ConvertTo-PosixQuotedString $psCommand)"
        $escaped = $shellCommand.Replace('\', '\\').Replace('"', '\"')
        $appleScript = 'tell application "Terminal" to do script "' + $escaped + '"'
        Write-MissionLog 'INFO' "Launching via osascript: $shellCommand"
        try {
            & /usr/bin/osascript -e $appleScript | Out-Null
        } catch {
            Write-Host "  ERROR: Failed to open Terminal.app: $_" -ForegroundColor Red
            Write-MissionLog 'ERROR' "osascript launch failed: $_"
        }
        return
    }

    $terminal = @('x-terminal-emulator', 'gnome-terminal', 'konsole', 'xfce4-terminal') |
        Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if (-not $terminal) {
        $msg = "Could not find a supported terminal emulator. Platform=$MissionPlatform IsMac=$MissionIsMacOS"
        Write-Host '  ERROR: Could not find a supported terminal emulator.' -ForegroundColor Red
        Write-MissionLog 'ERROR' $msg
        return
    }
    $shellCommand = "pwsh -NoExit -Command $(ConvertTo-PosixQuotedString $psCommand)"
    try {
        if ($terminal -eq 'gnome-terminal') {
            Start-Process -FilePath $terminal -ArgumentList @('--', 'bash', '-lc', $shellCommand)
        } else {
            # konsole, xfce4-terminal, x-terminal-emulator all accept '-e <cmd>'
            Start-Process -FilePath $terminal -ArgumentList @('-e', 'bash', '-lc', $shellCommand)
        }
    } catch {
        Write-Host "  ERROR: Failed to launch ${terminal}: $_" -ForegroundColor Red
        Write-MissionLog 'ERROR' "Start-Process ($terminal) failed: $_"
    }
}

function Start-ProfileClaudeCommand {
    param(
        [string]$ProjectPath,
        [string]$ProfileName,
        [string[]]$ClaudeArgs,
        [string]$Description,
        [bool]$AllowClaudeFallback = $true,
        [bool]$RunPreflight = $true
    )
    if (-not (Assert-DirExists $ProjectPath)) { return }

    $jig = Get-Command 'jig' -ErrorAction SilentlyContinue
    $claude = if ($AllowClaudeFallback) { Get-Command 'claude' -ErrorAction SilentlyContinue } else { $null }
    if (-not $jig -and -not $claude) {
        if ($AllowClaudeFallback) {
            Write-Host "  ERROR: Neither 'jig' nor 'claude' is in PATH." -ForegroundColor Red
        } else {
            Write-Host "  ERROR: 'jig' is not in PATH. Is it installed?" -ForegroundColor Red
        }
        return
    }
    if ($jig -and $RunPreflight -and -not (Invoke-ProfilePreflight $ProjectPath $ProfileName)) { return }

    # Side effects only once the launch will definitely proceed: a blocked preflight must not
    # have already rewritten ~/.obsidian-wiki/config or refreshed the context index.
    Set-WikiConfig $ProfileName $ProjectPath
    Invoke-ContextIndexRefresh $ProjectPath
    [void](Install-BundledSkills -Quiet)   # fill gaps only; never overwrites an install

    if ($jig) {
        Write-Host "  $Description with jig run $ProfileName ..." -ForegroundColor Green
        Start-TerminalCommand $ProjectPath (New-JigRunCommand $ProfileName $ClaudeArgs)
    } else {
        Write-Host "  Jig not found; $Description with plain Claude Code ..." -ForegroundColor Yellow
        Start-TerminalCommand $ProjectPath (New-ClaudeCommand $ClaudeArgs)
    }
}

function Start-WithProfile {
    param([string]$ProjectPath, [string]$ProfileName, [string]$MissionLabel)
    $base = if ($MissionLabel) { $MissionLabel } else { Split-Path $ProjectPath -Leaf }
    $missionName = New-MissionName $base
    Start-ProfileClaudeCommand $ProjectPath $ProfileName @('--name', $missionName) 'Launching new mission' $true $true
}

function Test-PiServerHealth {
    # Best-effort probe of an optional local model server (pi.healthUrl). Returns $true when it
    # answers with any 2xx status (or when no health URL is configured). Never throws - a down
    # server should warn, not crash the launcher.
    if ([string]::IsNullOrWhiteSpace($PiServerHealthUrl)) { return $true }
    try {
        $resp = Invoke-WebRequest -Uri $PiServerHealthUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        return ([int]$resp.StatusCode -ge 200 -and [int]$resp.StatusCode -lt 300)
    } catch {
        return $false
    }
}

function Wait-PiServerHealthy {
    # Poll the health endpoint until it answers ok or the timeout elapses.
    param([int]$TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ((Get-Date) -lt $deadline) {
        if (Test-PiServerHealth) { return $true }
        Start-Sleep -Milliseconds 750
    }
    return (Test-PiServerHealth)
}

function Start-PiServer {
    # Bring the local model server up when the health probe fails. Prefers a configured Windows
    # Scheduled Task (pi.taskName); falls back to pi.startCommand run in pi.workingDir.
    # Best-effort and non-throwing: returns $true only when the server answers healthy in time.
    if (Test-PiServerHealth) { return $true }
    if (-not $PiServerAutoStart) { return $false }

    $started = $false

    # 1. A Windows Scheduled Task, when one is configured.
    if ($MissionIsWindows -and -not [string]::IsNullOrWhiteSpace($PiServerTaskName)) {
        try {
            $task = Get-ScheduledTask -TaskName $PiServerTaskName -ErrorAction SilentlyContinue
            if ($task) {
                Write-Host "  Starting the model server via scheduled task '$PiServerTaskName' ..." -ForegroundColor DarkCyan
                Start-ScheduledTask -TaskName $PiServerTaskName -ErrorAction Stop
                Write-MissionLog 'INFO' "Started model server scheduled task '$PiServerTaskName'."
                $started = $true
            }
        } catch {
            Write-MissionLog 'WARN' "Start-ScheduledTask '$PiServerTaskName' failed: $_"
        }
    }

    # 2. Fallback: an explicit start command (e.g. 'ollama serve') in the configured working dir.
    if (-not $started -and -not [string]::IsNullOrWhiteSpace($PiServerStartCommand)) {
        $wd = if (-not [string]::IsNullOrWhiteSpace($PiServerWorkingDir)) { $PiServerWorkingDir } else { (Get-Location).Path }
        try {
            Write-Host "  Starting the model server: $PiServerStartCommand ..." -ForegroundColor DarkCyan
            if ($MissionIsWindows) {
                Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
                    "Set-Location -LiteralPath '$wd'; $PiServerStartCommand")
            } else {
                Start-Process -FilePath 'bash' -ArgumentList @('-lc', "cd '$wd' && $PiServerStartCommand")
            }
            Write-MissionLog 'INFO' "Started model server via command in '$wd': $PiServerStartCommand"
            $started = $true
        } catch {
            Write-MissionLog 'WARN' "Model server start command failed: $_"
        }
    }

    if (-not $started) { return $false }

    Write-Host "  Waiting for the model server to answer at $PiServerHealthUrl ..." -ForegroundColor DarkCyan
    return (Wait-PiServerHealthy $PiServerStartWaitSeconds)
}

function Start-PiCommand {
    # Core pi launch path (mirrors Start-ProfileClaudeCommand for the jig/claude
    # engine). ProfileName is used only to keep wiki access scoped like the other launch paths;
    # pi itself does not consume jig profiles.
    param(
        [string]$ProjectPath,
        [string]$ProfileName,
        [string[]]$PiArgs,
        [string]$Description
    )
    $piCmd = Initialize-PiLaunch $ProjectPath $ProfileName
    if (-not $piCmd) { return }
    Write-Host "  $Description with $piCmd ($(Get-PiModelLabel)) ..." -ForegroundColor Green
    Start-TerminalCommand $ProjectPath (New-PiCommand -PiArgs $PiArgs -Command $piCmd)
}

function Initialize-PiLaunch {
    # Everything a pi launch needs before the terminal opens: toolchain + fork updates, optional
    # model-server health, wiki scope, skills. Returns the pi command to run, or $null to abort.
    # Shared by plain pi launches and the kickoff (which runs pi after Claude has planned).
    param([string]$ProjectPath, [string]$ProfileName)
    if (-not (Assert-DirExists $ProjectPath)) { return $null }

    # Opening a pi project is the moment to keep pi, an optional source build (pii) and
    # Claude Code current. Throttled + best-effort. Runs before resolving the launcher so a
    # fresh source build is used.
    Invoke-PiLaunchUpdateGate

    $piCmd = Get-EffectivePiCommand
    if (-not (Assert-CmdExists $piCmd)) { return $null }

    if (-not (Test-PiServerHealth)) {
        if (Start-PiServer) {
            Write-Host "  Model server is up." -ForegroundColor Green
        } else {
            Write-Host "  WARN: the model server did not answer at $PiServerHealthUrl." -ForegroundColor Yellow
            Write-Host '  Start it (or fix pi.healthUrl / pi.startCommand in config.json), then retry.' -ForegroundColor DarkYellow
            if (-not (Read-YesNo '  Launch pi anyway?' 'N')) { return $null }
        }
    }

    Set-WikiConfig $ProfileName $ProjectPath
    Invoke-ContextIndexRefresh $ProjectPath
    # pi reads ~/.agents/skills, not ~/.claude/skills: make sure the bundled skills are there.
    [void](Install-BundledSkills -Quiet)
    return $piCmd
}

# --- Kickoff: plan in Claude Code (Forge or vibe-check), then build in pi ---------------------
# Forge is a Claude Code plugin, so planning runs there. Its output is handed to pi through
# files pi loads itself: PLAN.md, pointed to from CLAUDE.md. When the Claude session ends and
# PLAN.md exists, the same window asks to start pi on the first step.

function Get-KickoffPlanFileName { return 'PLAN.md' }

function Test-ProjectHasPlan {
    param([string]$ProjectPath)
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $ProjectPath (Get-KickoffPlanFileName)) -PathType Leaf)
}

function Get-PlanHandoffInstructions {
    # No double quotes anywhere in prompts: Start-TerminalCommand passes the command line
    # through Start-Process, which would strip them.
    $plan = Get-KickoffPlanFileName
    return ("When I approve the plan, write it to $plan in the project root with these sections: " +
        'Goal; Scope and non-goals; Tech stack; Steps (numbered, each with how to check it is done); Open questions. ' +
        "Then add a short Project plan section to CLAUDE.md (create the file if missing) saying the plan lives in $plan and which step is next. " +
        'The build continues in pi, a different coding agent: it reads CLAUDE.md and the plan, but cannot use Claude Code agent teams or .claude/agents, ' +
        'so keep the plan self-contained and suited to a single agent. ' +
        "Stop once $plan is written; do not start building.")
}

function Get-ForgeKickoffPrompt {
    param([string]$Name)
    return ("You are starting a project called '$Name'. Read CLAUDE.md if present. " +
        'Use the mission-planner skill to plan it with me: goal, scope, tech stack and the first implementation steps. ' +
        (Get-PlanHandoffInstructions))
}

function Get-VibeOpening {
    param([string]$Name)
    return "You are helping plan a brand-new app called '$Name' from scratch. Use the vibe-check skill to take me from idea to a buildable plan."
}

function Get-PiBuildPrompt {
    $plan = Get-KickoffPlanFileName
    return "Read $plan and CLAUDE.md, then start on the first step of the plan. Tell me what you are doing as you go, and mark steps done in $plan when they are finished."
}

function New-KickoffThenPiCommand {
    # One PowerShell line: the Claude planning session, then - once it exits - pi if a plan
    # was written and the user says yes. Runs in the project folder (Start-TerminalCommand).
    param([string]$ClaudeCommand, [string]$PiCommand)
    $plan = Get-KickoffPlanFileName
    return ("$ClaudeCommand; " +
        "if (Test-Path -LiteralPath '$plan') { " +
            "Write-Host ''; " +
            "`$mcGo = Read-Host '  Plan saved to $plan. Start building in pi? [Y/n]'; " +
            "if (`$mcGo -notmatch '^\s*[nN]') { $PiCommand } " +
            "else { Write-Host '  OK. Later: open the project in Mission Centre and press [L] to build in pi.' } " +
        "} else { Write-Host '  No $plan was written, so pi was not started. Press [L] in Mission Centre to run the kickoff again.' }")
}

function Start-KickoffThenPi {
    # Plan with Forge (jig run <metaProfile>) or vibe-check (jig run vibe) in Claude Code, then
    # build in pi in the same window. pi's launch checks run now, before Claude starts.
    param(
        [string]$ProjectPath,
        [string]$Name,
        [string]$ProfileName,
        [ValidateSet('forge', 'vibe')][string]$Planner = 'forge'
    )
    if (-not (Assert-DirExists $ProjectPath)) { return }
    $jig = Get-Command 'jig' -ErrorAction SilentlyContinue
    if (-not $jig -and -not (Get-Command 'claude' -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: Neither 'jig' nor 'claude' found in PATH." -ForegroundColor Red
        return
    }
    if ($Planner -eq 'vibe') {
        [void](Install-BundledSkill -Name 'vibe-check' -Quiet)
        # Beginner path: refuse to launch if the installed vibe profile drifted away from plan mode.
        if ($jig -and -not (Confirm-ProfileLaunchIntent 'vibe' 'plan')) { return }
    }
    $piCmd = Initialize-PiLaunch $ProjectPath $ProfileName
    if (-not $piCmd) { return }

    $opening = if ($Planner -eq 'vibe') { (Get-VibeOpening $Name) + ' ' + (Get-PlanHandoffInstructions) } else { Get-ForgeKickoffPrompt $Name }
    $claudeArgs = @('--name', (New-MissionName $Name), $opening)
    $planProfile = if ($Planner -eq 'vibe') { 'vibe' } else { $MetaProfile }
    $claudeCmd = if ($jig) { New-JigRunCommand $planProfile $claudeArgs } else { New-ClaudeCommand $claudeArgs }
    $piFull = New-PiCommand -PiArgs @('--name', (New-MissionName $Name), (Get-PiBuildPrompt)) -Command $piCmd

    $how = if ($jig) { "jig run $planProfile" } else { 'Claude Code (Jig not found)' }
    $plannerName = if ($Planner -eq 'vibe') { 'vibe-check' } else { 'Forge' }
    Write-Host "  Kickoff: planning with $plannerName in $how." -ForegroundColor Magenta
    Write-Host "  When the plan is saved to $(Get-KickoffPlanFileName), exit Claude (/exit): the same window offers to start pi." -ForegroundColor DarkGray
    Start-TerminalCommand $ProjectPath (New-KickoffThenPiCommand $claudeCmd $piFull)
}

function Start-PiNewMission {
    # [L] on a project with pi as the default engine. A project without PLAN.md is offered the
    # kickoff once; choosing to go straight to pi is remembered (kickoff = skipped, shared
    # across devices) so established projects are not asked again.
    param([ref]$ConfigRef, [int]$Index)
    $project = $ConfigRef.Value[$Index]
    $prof = Get-OptionalProperty $project 'profile' $DefaultProfile
    $name = Get-ProjectName $project
    $skipped = [string](Get-OptionalProperty $project 'kickoff' '') -eq 'skipped'
    if ((Test-ProjectHasPlan $project.path) -or $skipped) {
        Start-PiNew $project.path $prof $name
        return
    }
    Write-Host ''
    Write-Host "  This project has no $(Get-KickoffPlanFileName) yet." -ForegroundColor Cyan
    Write-Host '  [K]      Kickoff first: plan with Forge in Claude Code, then build in pi' -ForegroundColor Magenta
    Write-Host '  [Enter]  Start pi now (this project will not be asked again)'          -ForegroundColor Green
    $choice = (Read-Host '  Choice').Trim().ToUpperInvariant()
    if ($choice -eq 'K') {
        Start-KickoffThenPi $project.path $name $prof 'forge'
        return
    }
    Set-ProjectProperty $project 'kickoff' 'skipped'
    Save-Config $ConfigRef.Value
    Start-PiNew $project.path $prof $name
}

function Start-PiNew {
    # -Prompt: optional opening message (pi takes trailing messages, like claude).
    param([string]$ProjectPath, [string]$ProfileName, [string]$MissionLabel, [string]$Prompt = '')
    $base = if ($MissionLabel) { $MissionLabel } else { Split-Path $ProjectPath -Leaf }
    $missionName = New-MissionName $base
    $piArgs = @('--name', $missionName)
    if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $piArgs += $Prompt }
    Start-PiCommand $ProjectPath $ProfileName $piArgs 'Launching new pi mission'
}

function Start-PiContinue {
    param([string]$ProjectPath, [string]$ProfileName)
    Start-PiCommand $ProjectPath $ProfileName @('--continue') 'Continuing latest pi mission'
}

function Start-PiResume {
    param([string]$ProjectPath, [string]$ProfileName)
    Start-PiCommand $ProjectPath $ProfileName @('--resume') 'Opening pi resume picker'
}

function Start-Jig {
    param([string]$ProjectPath, [string]$ProfileName)
    if (-not (Assert-DirExists $ProjectPath)) { return }
    if (-not (Assert-CmdExists  'jig'))       { return }

    Set-WikiConfig $ProfileName $ProjectPath
    Invoke-ContextIndexRefresh $ProjectPath
    Write-Host "  Launching Jig in $ProjectPath ..." -ForegroundColor Green
    Start-TerminalCommand $ProjectPath 'jig'
}

function Start-ContinueMission {
    param([string]$ProjectPath, [string]$ProfileName)
    Start-ProfileClaudeCommand $ProjectPath $ProfileName @('--continue') 'Continuing latest mission' $true $true
}

function Start-ResumePicker {
    param([string]$ProjectPath, [string]$ProfileName)
    Start-ProfileClaudeCommand $ProjectPath $ProfileName @('--resume') 'Opening resume picker' $true $true
}

function Start-Resume {
    # Every caller passes a profile ($MetaProfile / project profile), so this
    # always routes through the profile launch path (jig with claude fallback).
    param([string]$ProjectPath, [string]$SessionId, [string]$ProfileName)
    $argList = @('--resume')
    if ($SessionId) { $argList += $SessionId }
    Start-ProfileClaudeCommand $ProjectPath $ProfileName $argList "Resuming session $SessionId" $true $true
}

function Start-MetaMission {
    param([object[]]$Projects)
    if (-not (Assert-DirExists $ScanRoot)) { return }

    # Meta missions are cross-project. Bind wiki access to the meta profile
    # (which is not corporate by default), so the wiki config clears unless
    # the user explicitly routes their meta profile to a vault.
    Set-WikiConfig $MetaProfile

    Write-Host ''
    $goal = Read-Host '  Meta mission goal'
    if ([string]::IsNullOrWhiteSpace($goal)) {
        Write-Host '  Meta mission cancelled: no goal provided.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host '  Select project numbers for this mission.' -ForegroundColor Cyan
    # Dormant projects are hidden but keep their numbers, so they can still be typed in.
    $i = 1
    $hidden = 0
    foreach ($p in $Projects) {
        if (Test-ProjectDormant $p) { $hidden++; $i++; continue }
        Write-Host "   [$i] $(Get-ProjectName $p)" -ForegroundColor White
        Write-Host "       $($p.path)" -ForegroundColor DarkGray
        $i++
    }
    if ($hidden -gt 0) {
        Write-Host "  ($hidden dormant project(s) hidden - their numbers still work)" -ForegroundColor DarkGray
    }
    $selection = Read-Host '  Projects (example: 1,3-4)'
    $selected = @(ConvertTo-ProjectSelection $selection $Projects)
    if ($selected.Count -eq 0) {
        Write-Host '  No valid projects selected. Meta mission cancelled to avoid broad scan-root context.' -ForegroundColor Yellow
        return
    }

    $missionName = New-MissionName $goal
    $briefPath = New-MetaMissionBrief $goal $selected $missionName
    Write-Host "  Mission brief: $briefPath" -ForegroundColor DarkCyan

    $claudeArgs = @('--name', $missionName)
    foreach ($p in $selected) {
        $claudeArgs += @('--add-dir', $p.path)
    }
    $claudeArgs += "Use the mission brief at $briefPath. Begin with Forge mission planning for this goal: $goal"

    if (Get-Command 'jig' -ErrorAction SilentlyContinue) {
        if (-not (Invoke-ProfilePreflight $ScanRoot $MetaProfile)) { return }
        Write-Host "  Launching focused Meta Mission with jig run $MetaProfile ..." -ForegroundColor Magenta
        Start-TerminalCommand $ScanRoot (New-JigRunCommand $MetaProfile $claudeArgs)
        return
    }
    if (Get-Command 'claude' -ErrorAction SilentlyContinue) {
        Write-Host '  Jig not found; launching a plain Claude Code meta mission ...' -ForegroundColor Yellow
        Start-TerminalCommand $ScanRoot (New-ClaudeCommand $claudeArgs)
        return
    }
    Write-Host "  ERROR: Neither 'jig' nor 'claude' is in PATH." -ForegroundColor Red
}

function Start-VibeKickoff {
    # Launch a greenfield planning session in $Path with the vibe-check skill.
    # Used by the [NA] New App action and the [V] kickoff choice in Add-NewProject.
    param([string]$Path, [string]$Name)

    # Ensure the bundled skill is installed before launching (no-op if already present).
    [void](Install-BundledSkill -Name 'vibe-check' -Quiet)

    if ($PiEnabled -and $DefaultEngine -eq 'pi') {
        # Plan with vibe-check in Claude Code (plan mode), then build in pi.
        Start-KickoffThenPi $Path $Name 'vibe' 'vibe'
        return
    }

    $missionName = New-MissionName $Name
    $opening = Get-VibeOpening $Name
    $claudeArgs = @('--name', $missionName, $opening)

    if (Get-Command 'jig' -ErrorAction SilentlyContinue) {
        # Beginner path: refuse to silently launch if the installed vibe profile
        # has drifted away from plan-mode (it has happened - an old copy extended yolo).
        if (-not (Confirm-ProfileLaunchIntent 'vibe' 'plan')) { return }
        Write-Host '  Launching New App planning with jig run vibe ...' -ForegroundColor Magenta
        Start-TerminalCommand $Path (New-JigRunCommand 'vibe' $claudeArgs)
        return
    }
    if (Get-Command 'claude' -ErrorAction SilentlyContinue) {
        Write-Host '  Jig not found; launching a plain Claude Code session with the vibe-check skill ...' -ForegroundColor Yellow
        Start-TerminalCommand $Path (New-ClaudeCommand $claudeArgs)
        return
    }
    Write-Host "  ERROR: Neither 'jig' nor 'claude' found in PATH." -ForegroundColor Red
}

function Start-NewApp {
    param([ref]$ConfigRef)

    Write-Host ''
    Write-Host '  New App (vibe-check)' -ForegroundColor Cyan
    Write-Host '  Turn a vague idea into a buildable plan -- great if you have never coded.' -ForegroundColor DarkGray
    Write-Host "  Projects are created in: $ScanRoot" -ForegroundColor DarkGray
    Write-Host ''

    $project = New-ScaffoldedProject -ConfigRef $ConfigRef -DefaultProfileName 'vibe'
    if ($null -eq $project) { return }

    Write-Host ''
    Start-VibeKickoff $project.path $project.name
}
