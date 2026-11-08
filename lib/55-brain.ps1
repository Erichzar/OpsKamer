# 55-brain.ps1 - Second brain: an Obsidian vault you deposit into and ask questions about
# Dot-sourced by the root script; relies on the script-scoped config globals ($SecondBrain*, $Pi*,
# $DefaultEngine, ...) defined there.
#
# The vault is a plain folder of Markdown notes that Obsidian opens. Mission Centre only does the
# quick, offline parts: set the vault up, drop captures and files into _inbox/, show counts, open
# Obsidian. Filing, linking and answering questions is the agent's job, through the bundled
# second-brain skill (skills/second-brain/SKILL.md), which finds the vault via ~/.second-brain/config.

function Get-SecondBrainFolders {
    # The default layout (also described in skills/second-brain/SKILL.md and the vault's BRAIN.md).
    return @('_inbox', '_attachments', '_archive', '_templates', 'notes', 'sources', 'people', 'projects', 'journal', 'answers')
}

function Get-SecondBrainVault {
    # The configured vault: config.json secondBrain.vault, else the SECOND_BRAIN_VAULT variable. '' = not set up.
    if (-not [string]::IsNullOrWhiteSpace($SecondBrainVault)) { return $SecondBrainVault }
    if (-not [string]::IsNullOrWhiteSpace($env:SECOND_BRAIN_VAULT)) { return (Resolve-UserPath $env:SECOND_BRAIN_VAULT) }
    return ''
}

function Get-SecondBrainDefaultVault {
    # Suggested location. On a Mac with Obsidian's iCloud folder, a vault there also syncs to the phone.
    param([string]$HomeDir = $HOME)
    if ($MissionIsMacOS) {
        $icloud = Join-Path $HomeDir 'Library/Mobile Documents/iCloud~md~obsidian/Documents'
        if (Test-Path -LiteralPath $icloud -PathType Container) { return (Join-Path $icloud 'SecondBrain') }
    }
    return (Join-Path $HomeDir 'SecondBrain')
}

function Initialize-SecondBrainVault {
    # Create the folders and copy the starter files (BRAIN.md, index.md, templates, Obsidian settings)
    # that are missing. Never overwrites a file. A vault that already has its own .obsidian/ keeps its
    # Obsidian settings untouched. Returns the number of files created.
    param([string]$VaultPath, [string]$TemplateDir = $SecondBrainTemplateDir)
    $hadObsidian = Test-Path -LiteralPath (Join-Path $VaultPath '.obsidian') -PathType Container
    if (-not (Test-Path -LiteralPath $VaultPath -PathType Container)) { New-Item -ItemType Directory -Path $VaultPath -Force | Out-Null }
    foreach ($f in Get-SecondBrainFolders) {
        $d = Join-Path $VaultPath $f
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    $created = 0
    if ([string]::IsNullOrWhiteSpace($TemplateDir) -or -not (Test-Path -LiteralPath $TemplateDir -PathType Container)) { return $created }
    $root = (Resolve-Path -LiteralPath $TemplateDir).Path.TrimEnd('\', '/')
    # -Force: on macOS/Linux, .obsidian/ is hidden and would be skipped without it.
    foreach ($src in @(Get-ChildItem -LiteralPath $TemplateDir -Recurse -File -Force)) {
        $rel = $src.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($hadObsidian -and $rel -match '^\.obsidian[\\/]') { continue }
        $dst = Join-Path $VaultPath $rel
        if (Test-Path -LiteralPath $dst) { continue }
        $dir = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $src.FullName -Destination $dst
        $created++
    }
    return $created
}

function Get-SecondBrainPointerPath { return (Join-Path $SecondBrainConfigDir 'config') }

function Write-SecondBrainPointer {
    # ~/.second-brain/config tells the second-brain skill (in any agent, any folder) where the vault is.
    # BOM-free so shell tools read it cleanly. Unchanged files are not rewritten; a changed one is backed up.
    # Returns $true when the file was written.
    param([string]$VaultPath)
    if ([string]::IsNullOrWhiteSpace($VaultPath)) { return $false }
    $path = Get-SecondBrainPointerPath
    $new = "# Written by Mission Centre ([BR] Second brain): where the second-brain skill finds your vault.`nVAULT=$VaultPath`n"
    $old = if (Test-Path -LiteralPath $path -PathType Leaf) { [System.IO.File]::ReadAllText($path) } else { $null }
    if ($old -eq $new) { return $false }
    if (-not (Test-Path -LiteralPath $SecondBrainConfigDir -PathType Container)) { New-Item -ItemType Directory -Path $SecondBrainConfigDir -Force | Out-Null }
    if ($null -ne $old) { Copy-Item -LiteralPath $path -Destination ($path + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force }
    [System.IO.File]::WriteAllText($path, $new, (New-Object System.Text.UTF8Encoding $false))
    return $true
}

function Read-SecondBrainPointer {
    # The VAULT= value from ~/.second-brain/config, or ''.
    $path = Get-SecondBrainPointerPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*VAULT\s*=\s*(.+?)\s*$') { return $Matches[1] }
    }
    return ''
}

function Sync-SecondBrainPointer {
    # Start-up: keep the pointer in step with config.json. Best effort, silent, never blocks.
    try {
        $v = Get-SecondBrainVault
        if ($v) { [void](Write-SecondBrainPointer $v) }
    } catch { Write-MissionLog 'WARN' "second brain pointer not written: $_" }
}

function Save-SecondBrainVaultSetting {
    # Store secondBrain.vault in config.json (backed up first). Returns $true on success.
    param([string]$VaultPath)
    $cfg = $null
    if (Test-Path -LiteralPath $AppConfigPath) {
        try {
            $cfg = Get-Content -LiteralPath $AppConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Host '  WARN: config.json could not be parsed; the vault is set for this session only.' -ForegroundColor Yellow
            return $false
        }
    }
    if ($null -eq $cfg) { $cfg = [PSCustomObject]@{} }
    $sb = Get-RawProperty $cfg 'secondBrain' $null
    if ($null -eq $sb) {
        $sb = [PSCustomObject]@{ vault = $VaultPath }
        $cfg | Add-Member -NotePropertyName 'secondBrain' -NotePropertyValue $sb -Force
    } elseif ($sb.PSObject.Properties['vault']) {
        $sb.vault = $VaultPath
    } else {
        $sb | Add-Member -NotePropertyName 'vault' -NotePropertyValue $VaultPath
    }
    try {
        if (Test-Path -LiteralPath $AppConfigPath) {
            Copy-Item -LiteralPath $AppConfigPath -Destination ($AppConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
        }
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $AppConfigPath -Encoding UTF8
        return $true
    } catch {
        Write-Host "  WARN: could not write config.json ($_); the vault is set for this session only." -ForegroundColor Yellow
        return $false
    }
}

function Get-UniqueFilePath {
    # "<dir>/<name>", or "<dir>/<base> (2)<ext>", "(3)", ... when taken.
    param([string]$Dir, [string]$Name)
    $p = Join-Path $Dir $Name
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $ext = [System.IO.Path]::GetExtension($Name)
    for ($i = 2; $i -lt 1000; $i++) {
        $p = Join-Path $Dir ("{0} ({1}){2}" -f $base, $i, $ext)
        if (-not (Test-Path -LiteralPath $p)) { return $p }
    }
    return (Join-Path $Dir ("{0} {1}{2}" -f $base, [guid]::NewGuid().ToString('N').Substring(0, 8), $ext))
}

function ConvertTo-YamlQuoted {
    param([string]$Value)
    return '"' + ([string]$Value).Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-SecondBrainCaptureText {
    # Pure: the Markdown of one inbox capture. The text itself is kept exactly as typed.
    param([string]$Text, [datetime]$When, [string]$Attachment = '')
    $first = @(($Text -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -First 1)
    $summary = if ($first.Count -gt 0) { $first[0].Trim() } elseif ($Attachment) { "File: $Attachment" } else { '' }
    if ($summary.Length -gt 120) { $summary = $summary.Substring(0, 117) + '...' }
    $lines = @(
        '---',
        ('title: ' + (ConvertTo-YamlQuoted ('Capture ' + $When.ToString('yyyy-MM-dd HH:mm')))),
        ('summary: ' + (ConvertTo-YamlQuoted $summary)),
        'type: capture',
        ('created: ' + $When.ToString('yyyy-MM-dd')),
        'source: "Mission Centre"',
        '---',
        ''
    )
    if ($Attachment) { $lines += @("File: [[$Attachment]]", '') }
    $body = ([string]$Text).TrimEnd()
    if ($body) { $lines += $body }
    return (($lines -join "`n").TrimEnd() + "`n")
}

function Add-SecondBrainCapture {
    # Write one capture to <vault>/_inbox/ ("2026-11-08 140512 capture.md"). One file per capture, so
    # a phone and a computer syncing the vault never edit the same file. Returns the new file's path.
    param([string]$VaultPath, [string]$Text, [datetime]$When = (Get-Date), [string]$Attachment = '')
    $inbox = Join-Path $VaultPath '_inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { New-Item -ItemType Directory -Path $inbox -Force | Out-Null }
    $path = Get-UniqueFilePath $inbox ($When.ToString('yyyy-MM-dd HHmmss') + ' capture.md')
    [System.IO.File]::WriteAllText($path, (New-SecondBrainCaptureText $Text $When $Attachment), (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function ConvertFrom-TerminalPathText {
    # Pure: a path typed or dragged into a terminal, cleaned up: trimmed, outer quotes removed and, off Windows,
    # backslash-escaped characters unescaped (macOS Terminal drags "My\ Vault" for "My Vault").
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t.Length -ge 2 -and (($t.StartsWith("'") -and $t.EndsWith("'")) -or ($t.StartsWith('"') -and $t.EndsWith('"')))) {
        $t = $t.Substring(1, $t.Length - 2).Trim()
    }
    if (-not $MissionIsWindows) { $t = $t -replace '\\(.)', '$1' }
    return $t
}

function Resolve-DroppedFilePath {
    # A file dragged into a terminal arrives as a path: maybe 'quoted' or "quoted", or with
    # backslash-escaped spaces (macOS Terminal). Returns the full path of an existing file, else ''.
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $t = $Line.Trim()
    if ($t.Length -gt 1024 -or $t.Contains("`n")) { return '' }
    if ($t.Length -ge 2 -and (($t.StartsWith("'") -and $t.EndsWith("'")) -or ($t.StartsWith('"') -and $t.EndsWith('"')))) {
        $t = $t.Substring(1, $t.Length - 2)
    }
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $candidates = @(Resolve-UserPath $t)
    if (-not $MissionIsWindows) { $candidates += (Resolve-UserPath ($t -replace '\\(.)', '$1')) }
    foreach ($c in $candidates) {
        try {
            if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
        } catch { }
    }
    return ''
}

function Add-SecondBrainFile {
    # Copy (never move) a file into <vault>/_inbox/. Returns the copy's path.
    param([string]$VaultPath, [string]$FilePath)
    $inbox = Join-Path $VaultPath '_inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { New-Item -ItemType Directory -Path $inbox -Force | Out-Null }
    $dst = Get-UniqueFilePath $inbox (Split-Path $FilePath -Leaf)
    Copy-Item -LiteralPath $FilePath -Destination $dst
    return $dst
}

function Get-SecondBrainStats {
    # Counts for the menu: notes (outside _ and . folders, not the vault's own pages), inbox items, last log line.
    param([string]$VaultPath)
    $stats = [PSCustomObject]@{ exists = $false; notes = 0; inbox = 0; lastLog = '' }
    if ([string]::IsNullOrWhiteSpace($VaultPath) -or -not (Test-Path -LiteralPath $VaultPath -PathType Container)) { return $stats }
    $stats.exists = $true
    $root = (Resolve-Path -LiteralPath $VaultPath).Path.TrimEnd('\', '/')
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($rel -match '^[._]' -or $rel -match '[\\/][._]') { continue }
        if ($rel -in @('index.md', 'log.md', 'BRAIN.md')) { continue }
        $n++
    }
    $stats.notes = $n
    $inbox = Join-Path $root '_inbox'
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        $stats.inbox = @(Get-ChildItem -LiteralPath $inbox -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'README.md' -and -not $_.Name.StartsWith('.') }).Count
    }
    $log = Join-Path $root 'log.md'
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $last = @([System.IO.File]::ReadAllLines($log) | Where-Object { $_ -match '^\s*-\s+\S' } | Select-Object -Last 1)
        if ($last.Count -gt 0) { $stats.lastLog = $last[0].Trim().TrimStart('-').Trim() }
    }
    return $stats
}

function ConvertTo-PromptText {
    # One line, no double quotes: Start-TerminalCommand passes the command through Start-Process,
    # which would strip them (see Get-PlanHandoffInstructions).
    param([string]$Text)
    return ((([string]$Text) -replace '"', "'") -replace '\s*\r?\n\s*', ' ').Trim()
}

function Get-SecondBrainPrompt {
    # Pure: the opening message for an agent session in the vault.
    param([ValidateSet('ask', 'process', 'chat')][string]$Mode, [string]$VaultPath, [string]$Text = '')
    $head = "Use the second-brain skill. My second brain is the Obsidian vault at $VaultPath (read BRAIN.md there first)."
    switch ($Mode) {
        'ask' {
            return (ConvertTo-PromptText ("$head My question: $Text Search my notes in Afrikaans and English, answer from them, " +
                'cite each point with [[note]] links, and say plainly what my notes do not cover.'))
        }
        'process' {
            return (ConvertTo-PromptText ("$head Process my inbox (_inbox/): file every capture as proper notes, link and log them, " +
                'move processed captures to _archive/inbox/, then tell me briefly what you did.'))
        }
        default {
            return (ConvertTo-PromptText "$head Ask me briefly what I want to deposit or look up.")
        }
    }
}

function Get-SecondBrainEngine {
    # Which agent the brain sessions use: the default engine (pi only when enabled).
    if ($DefaultEngine -eq 'pi' -and $PiEnabled) { return 'pi' }
    return 'claude'
}

function Start-SecondBrainAgent {
    # Open Claude Code (or pi) in the vault folder with the skill installed and an opening message.
    param([string]$VaultPath, [string]$Prompt)
    if (-not (Assert-DirExists $VaultPath)) { return }
    [void](Install-BundledSkill -Name 'second-brain' -Quiet)   # fill the gap only; never overwrites
    try { [void](Write-SecondBrainPointer $VaultPath) } catch { Write-Host "  WARN: ~/.second-brain/config not written: $_" -ForegroundColor Yellow }
    $name = New-MissionName 'second-brain'
    if ((Get-SecondBrainEngine) -eq 'pi') {
        $piCmd = Get-EffectivePiCommand
        if (-not (Assert-CmdExists $piCmd)) { return }
        Write-Host "  Opening your second brain in $piCmd ..." -ForegroundColor Green
        Start-TerminalCommand $VaultPath (New-PiCommand -PiArgs @('--name', $name, $Prompt) -Command $piCmd)
        return
    }
    if (-not (Assert-CmdExists 'claude')) { return }
    Write-Host '  Opening your second brain in Claude Code ...' -ForegroundColor Green
    Start-TerminalCommand $VaultPath (New-ClaudeCommand @('--name', $name, $Prompt))
}

function Get-ObsidianConfigPath {
    # Obsidian's own list of known vaults (obsidian.json).
    if ($MissionIsWindows) { return (Join-Path (Join-Path $env:APPDATA 'obsidian') 'obsidian.json') }
    if ($MissionIsMacOS) { return (Join-Path $HOME 'Library/Application Support/obsidian/obsidian.json') }
    return (Join-Path $HOME '.config/obsidian/obsidian.json')
}

function Test-ObsidianKnowsVault {
    # Has Obsidian opened this folder as a vault before? Read-only. Only then can obsidian://open find it.
    param([string]$VaultPath, [string]$ObsidianJsonPath = (Get-ObsidianConfigPath))
    if ([string]::IsNullOrWhiteSpace($ObsidianJsonPath) -or -not (Test-Path -LiteralPath $ObsidianJsonPath -PathType Leaf)) { return $false }
    try {
        $j = Get-Content -LiteralPath $ObsidianJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $vaults = Get-RawProperty $j 'vaults' $null
        if ($null -eq $vaults) { return $false }
        $want = ConvertTo-NormalizedPathKey $VaultPath
        foreach ($p in $vaults.PSObject.Properties) {
            if ((ConvertTo-NormalizedPathKey ([string](Get-OptionalProperty $p.Value 'path' ''))) -eq $want) { return $true }
        }
    } catch { }
    return $false
}

function Get-ObsidianOpenUri {
    param([string]$VaultPath)
    return ('obsidian://open?path=' + [uri]::EscapeDataString($VaultPath))
}

function Open-SecondBrainInObsidian {
    param([string]$VaultPath)
    if (-not (Assert-DirExists $VaultPath)) { return }
    $known = Test-ObsidianKnowsVault $VaultPath
    $target = if ($known) { Get-ObsidianOpenUri $VaultPath } else { 'obsidian://' }
    try {
        if ($MissionIsWindows) { Start-Process $target }
        elseif ($MissionIsMacOS) { & open $target 2>$null; if ($LASTEXITCODE -ne 0) { throw 'Obsidian is not installed' } }
        else { & xdg-open $target 2>$null }
    } catch {
        Write-Host '  Obsidian did not open. Install it (free) from https://obsidian.md, then try [O] again.' -ForegroundColor Yellow
        return
    }
    if (-not $known) {
        Write-Host '  First time in Obsidian: choose "Open folder as vault" and pick this folder:' -ForegroundColor Cyan
        Write-Host "    $VaultPath" -ForegroundColor White
        Write-Host '  After that, [O] opens the vault directly.' -ForegroundColor DarkGray
    }
}

function Read-SecondBrainLines {
    # Read pasted or typed lines until two empty lines in a row (one empty line is kept as a paragraph
    # break). An empty first line cancels. $ReadLine is injectable for tests. Returns the text or ''.
    param([scriptblock]$ReadLine = { Write-Host '  > ' -NoNewline; [Console]::ReadLine() })
    $lines = [System.Collections.Generic.List[string]]::new()
    $blank = 0
    while ($true) {
        $l = & $ReadLine
        if ($null -eq $l) { break }
        if ([string]::IsNullOrWhiteSpace($l)) {
            if ($lines.Count -eq 0) { return '' }
            $blank++
            if ($blank -ge 2) { break }
            $lines.Add('')
            continue
        }
        $blank = 0
        $lines.Add($l)
        # A file dropped in as the first line: no need to wait for more.
        if ($lines.Count -eq 1 -and (Resolve-DroppedFilePath $l)) { break }
    }
    return (($lines -join "`n").Trim())
}

function Invoke-SecondBrainDeposit {
    param([string]$VaultPath)
    Write-Host ''
    Write-Host '  Deposit: type or paste what you want to keep, or drag a file into this window.' -ForegroundColor Cyan
    Write-Host '  Press Enter on two empty lines to finish. An empty first line cancels.' -ForegroundColor DarkGray
    $text = Read-SecondBrainLines
    if (-not $text) { Write-Host '  Nothing saved.' -ForegroundColor DarkGray; return $false }
    try {
        $file = Resolve-DroppedFilePath $text
        if ($file) {
            $copy = Add-SecondBrainFile $VaultPath $file
            $why = Read-Host '  What is this, or why keep it? (optional, Enter to skip)'
            [void](Add-SecondBrainCapture $VaultPath ([string]$why) (Get-Date) (Split-Path $copy -Leaf))
            Write-Host "  Copied to the inbox: $(Split-Path $copy -Leaf) (your original stays where it is)." -ForegroundColor Green
        } else {
            $path = Add-SecondBrainCapture $VaultPath $text
            Write-Host "  Saved to the inbox: $(Split-Path $path -Leaf)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ERROR: could not save to the inbox: $_" -ForegroundColor Red
        return $false
    }
    Write-Host '  The agent files the inbox into notes with [P] (do several deposits first if you like).' -ForegroundColor DarkGray
    return $true
}

function Invoke-SecondBrainSetup {
    # Choose (or change) the vault folder, create its starter files, remember it. Returns the vault path or ''.
    Write-Host ''
    Write-Host '  Second brain setup' -ForegroundColor Cyan
    Write-Host '  Your second brain is a folder of notes that Obsidian opens (an Obsidian "vault").' -ForegroundColor DarkGray
    Write-Host '  Already have a vault? Type its folder path to use it: nothing in it is changed or deleted.' -ForegroundColor DarkGray
    $default = Get-SecondBrainDefaultVault
    $answer = Read-Host "  Folder for your second brain (Enter for $default)"
    if ($null -eq $answer) { return '' }
    $raw = if ([string]::IsNullOrWhiteSpace($answer)) { $default } else { ConvertFrom-TerminalPathText $answer }
    try { $vault = [System.IO.Path]::GetFullPath((Resolve-UserPath $raw)).TrimEnd('\', '/') } catch {
        Write-Host "  ERROR: not a valid folder path: $raw" -ForegroundColor Red
        return ''
    }
    if ([string]::IsNullOrWhiteSpace($vault) -or $vault -match '^[A-Za-z]:$' -or $vault -eq (([string]$HOME).TrimEnd('\', '/'))) {
        Write-Host '  Pick a folder of its own (for example SecondBrain in your home folder), not a drive or your home folder itself.' -ForegroundColor Yellow
        return ''
    }
    try {
        $created = Initialize-SecondBrainVault $vault
    } catch {
        Write-Host "  ERROR: could not set up ${vault}: $_" -ForegroundColor Red
        return ''
    }
    [void](Save-SecondBrainVaultSetting $vault)
    $script:SecondBrainVault = $vault
    try { [void](Write-SecondBrainPointer $vault) } catch { Write-Host "  WARN: ~/.second-brain/config not written: $_" -ForegroundColor Yellow }
    [void](Install-BundledSkill -Name 'second-brain' -Quiet)
    Write-Host "  Second brain ready at $vault ($created starter file(s) added)." -ForegroundColor Green
    Write-Host '  Next: press [O] to open it in Obsidian, or [D] to deposit your first thing.' -ForegroundColor DarkGray
    return $vault
}

function Invoke-SecondBrainMenu {
    # [BR] on the home screen.
    $vault = Get-SecondBrainVault
    if (-not $vault) {
        Clear-Host
        Write-Banner
        $vault = Invoke-SecondBrainSetup
        if (-not $vault) { Read-Host '  Press Enter to continue' | Out-Null; return }
        Read-Host '  Press Enter to continue' | Out-Null
    }
    while ($true) {
        Clear-Host
        Write-Banner
        $s = Get-SecondBrainStats $vault
        Write-Host '  Second brain' -ForegroundColor Cyan
        Write-Host "   vault : $vault" -ForegroundColor DarkGray
        if ($s.exists) {
            Write-Host "   notes : $($s.notes)   inbox: $($s.inbox) waiting" -ForegroundColor DarkGray
            if ($s.lastLog) { Write-Host "   last  : $(Get-TruncatedSummary $s.lastLog 70)" -ForegroundColor DarkGray }
        } else {
            Write-Host '   The vault folder is not there (an unplugged drive, or iCloud not synced yet?). [V] picks another.' -ForegroundColor Yellow
        }
        $engine = if ((Get-SecondBrainEngine) -eq 'pi') { 'pi' } else { 'Claude Code' }
        Write-Host ''
        Write-Divider
        Write-Host '  [D]  Deposit - type, paste or drag in something to keep'      -ForegroundColor Green
        Write-Host "  [A]  Ask - a question about what you saved ($engine)"        -ForegroundColor Green
        Write-Host "  [P]  Process inbox - $engine files it into linked notes"     -ForegroundColor Green
        Write-Host "  [C]  Chat with your second brain ($engine)"                  -ForegroundColor Green
        Write-Host '  [O]  Open in Obsidian'                                       -ForegroundColor Cyan
        Write-Host '  [F]  Open the folder'                                        -ForegroundColor Cyan
        Write-Host '  [V]  Change vault folder'                                    -ForegroundColor DarkGray
        Write-Host '  [B]  Back'                                                   -ForegroundColor DarkGray
        Write-Host ''
        $c = Read-Host '  Choice'
        if ($null -eq $c) { return }
        $c = $c.Trim().ToUpperInvariant()
        if ($c -in @('', 'B', 'Q')) { return }
        if ($c -ne 'V' -and -not $s.exists) { Write-Host '  The vault folder is missing; press [V] first.' -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
        switch ($c) {
            'D' { [void](Invoke-SecondBrainDeposit $vault); Read-Host '  Press Enter to continue' | Out-Null }
            'A' {
                $q = Read-Host '  Your question (Enter to cancel)'
                if (-not [string]::IsNullOrWhiteSpace($q)) {
                    Start-SecondBrainAgent $vault (Get-SecondBrainPrompt 'ask' $vault $q)
                    Start-Sleep -Seconds 1
                }
            }
            'P' {
                if ($s.inbox -eq 0) { Write-Host '  The inbox is empty.' -ForegroundColor DarkGray; Start-Sleep -Seconds 1 }
                else { Start-SecondBrainAgent $vault (Get-SecondBrainPrompt 'process' $vault); Start-Sleep -Seconds 1 }
            }
            'C' { Start-SecondBrainAgent $vault (Get-SecondBrainPrompt 'chat' $vault); Start-Sleep -Seconds 1 }
            'O' { Open-SecondBrainInObsidian $vault; Read-Host '  Press Enter to continue' | Out-Null }
            'F' { Open-ProjectFolder $vault }
            'V' {
                $nv = Invoke-SecondBrainSetup
                if ($nv) { $vault = $nv }
                Read-Host '  Press Enter to continue' | Out-Null
            }
            default { Write-Host '  Unknown option.' -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
