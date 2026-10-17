# 40-sessions.ps1 - Claude Code session history
# Split from Mission-Centre.ps1. Dot-sourced by the root script; relies on the
# script-scoped config globals ($ScanRoot, $Pi*, etc.) defined there.

function Get-SessionFolderName {
    param([string]$ProjectPath)
    # Claude encodes paths by dashing every non-alphanumeric char (hyphens map to themselves):
    # F:\AI\Foo Bar -> F--AI-Foo-Bar. Match that superset - replacing only \ : / and space
    # missed '.'/'_' etc., so e.g. a 'my.app' project silently showed no session history.
    $ProjectPath -replace '[^A-Za-z0-9-]', '-'
}

function Get-MessageContentText {
    # First text from a message 'content' value: a raw string, an array of typed blocks
    # ({type:'text', text:...}), or a bare block - Get-OptionalProperty's `return` unrolls a
    # single-element blocks array to its lone block, so @() re-normalizes before scanning.
    param([object]$Content)
    if ($null -eq $Content) { return $null }
    if ($Content -is [string]) {
        if ($Content) { return $Content }
        return $null
    }
    foreach ($b in @($Content)) {
        $blockType = Get-OptionalProperty $b 'type' $null
        $blockText = Get-OptionalProperty $b 'text' $null
        if ($blockType -eq 'text' -and $blockText) { return [string]$blockText }
    }
    return $null
}

function Get-SessionLabel {
    # Returns the best available label for a session:
    # 1. custom-title (auto-generated slug, hyphens → spaces) — best recap
    # 2. first user message — fallback
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    try {
        $customTitle = $null
        $firstPrompt = $null
        # Scan up to 150 lines — custom-title is generated after ~80 lines of setup
        $lines = Get-Content $FilePath -TotalCount 150 -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $msg = $line | ConvertFrom-Json
                # Preferred: auto-generated session title
                $msgType = Get-OptionalProperty $msg 'type' $null
                if (-not $customTitle -and $msgType -eq 'custom-title' -and (Get-OptionalProperty $msg 'customTitle' $null)) {
                    $customTitle = ((Get-OptionalProperty $msg 'customTitle' '') -replace '-', ' ')
                }
                # Fallback: first user message (multiple formats). Content is fetched with
                # Get-RawProperty: block-array content stringifies to '' on 5.1 and would be
                # discarded by Get-OptionalProperty's emptiness probe.
                if (-not $firstPrompt) {
                    # Formats A/B: {"type":"user"|"human","message":{"content":...}} (CLI / older)
                    if ($msgType -in @('user', 'human')) {
                        $firstPrompt = Get-MessageContentText (Get-RawProperty (Get-RawProperty $msg 'message') 'content')
                    }
                    # Format C: {"role":"user","content":"..."}
                    if (-not $firstPrompt -and (Get-OptionalProperty $msg 'role' $null) -eq 'user') {
                        $firstPrompt = Get-MessageContentText (Get-RawProperty $msg 'content')
                    }
                }
                if ($customTitle -and $firstPrompt) { break }
            } catch { }
        }
        if ($customTitle) { return $customTitle }
        return $firstPrompt
    } catch { }
    return $null
}

# Parse cache for the recency probe below: the home screen calls it for EVERY project on EVERY
# redraw, and re-parsing each sessions-index.json is the launcher's hottest I/O path. Keyed by
# the index file's mtime, so a session update (Claude rewrites the index) invalidates naturally.
$script:McActivityMsCache = @{}

function Get-PiSessionFolderName {
    # pi's session-dir naming (session-manager.ts getDefaultSessionDirPath, identical in
    # vanilla pi and the leo-labs-ai fork): strip one leading slash, map / \ : to '-', wrap in
    # '--'. Spaces and dots are kept: F:\AI\Pi Mono -> --F--AI-Pi Mono--
    param([string]$ProjectPath)
    $p = ($ProjectPath.TrimEnd('\', '/')) -replace '^[/\\]', ''
    return '--' + ($p -replace '[/\\:]', '-') + '--'
}

function Get-PiProjectLastActivityMs {
    # Newest pi session (epoch ms) for a project, or 0. pi appends to the session .jsonl on
    # every turn - including [PC] continue, which reuses an existing file - so the file
    # mtime is the activity signal (a folder mtime would miss continues).
    param([string]$ProjectPath)
    if ([string]::IsNullOrWhiteSpace($PiSessionsDir)) { return 0 }
    $folderPath = Join-Path $PiSessionsDir (Get-PiSessionFolderName $ProjectPath)
    if (-not (Test-Path -LiteralPath $folderPath)) { return 0 }
    try {
        $newest = Get-ChildItem -LiteralPath $folderPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($newest) { return [long]($newest.LastWriteTimeUtc - [datetime]'1970-01-01').TotalMilliseconds }
    } catch { }
    return 0
}

function Get-ProjectLastActivityMs {
    # Home-screen recency: newest session activity across BOTH engines - Claude Code
    # (~/.claude/projects) and pi (~/.pi/agent/sessions). Claude-only history meant
    # projects launched with [PI]/[PC] never rose in the recent list.
    param([string]$ProjectPath)
    $claude = Get-ClaudeProjectLastActivityMs $ProjectPath
    $pi = Get-PiProjectLastActivityMs $ProjectPath
    if ($pi -gt $claude) { return $pi }
    return $claude
}

function Get-ClaudeProjectLastActivityMs {
    # Cheap Claude recency probe: newest session timestamp (epoch ms) for a project, or 0
    # if it has no Claude history. Avoids the per-session .jsonl enrichment that
    # Get-RecentSessions does, so it is fast to call across every project.
    param([string]$ProjectPath)
    $folderPath = Join-Path $ClaudeProjectsDir (Get-SessionFolderName $ProjectPath)
    if (-not (Test-Path $folderPath)) { return 0 }
    $best = 0
    $indexPath = Join-Path $folderPath 'sessions-index.json'
    if (Test-Path $indexPath) {
        $stamp = 0
        try { $stamp = (Get-Item -LiteralPath $indexPath).LastWriteTimeUtc.Ticks } catch { }
        $cached = $script:McActivityMsCache[$indexPath]
        if ($cached -and $stamp -ne 0 -and $cached.Stamp -eq $stamp) {
            $best = $cached.Ms
        } else {
            try {
                $index = Get-Content $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($e in @(Get-RawProperty $index 'entries' @())) {
                    $m = [long](Get-OptionalProperty $e 'fileMtime' 0)
                    if ($m -gt $best) { $best = $m }
                }
            } catch { }
            $script:McActivityMsCache[$indexPath] = @{ Stamp = $stamp; Ms = $best }
        }
    }
    if ($best -eq 0) {
        try {
            $newest = Get-ChildItem -Path $folderPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($newest) { $best = [long]($newest.LastWriteTime.ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds }
        } catch { }
    }
    return $best
}

function Get-RecentSessions {
    param([string]$ProjectPath, [int]$MaxCount = 5)

    $folderName = Get-SessionFolderName $ProjectPath
    $folderPath = Join-Path $ClaudeProjectsDir $folderName
    $indexPath  = Join-Path $folderPath 'sessions-index.json'

    if (Test-Path $indexPath) {
        try {
            $raw   = Get-Content $indexPath -Raw -Encoding UTF8
            $index = $raw | ConvertFrom-Json
            # Get-RawProperty, NOT Get-OptionalProperty: the latter stringifies to test
            # emptiness, and [string] of an object array is '' on 5.1, which would wrongly
            # discard a real multi-entry index.
            $entries = @(Get-RawProperty $index 'entries' @())
            if ($entries.Count -gt 0) {
                # Sort by fileMtime (epoch ms) — more accurate than modified (can be stale)
                $sorted = $entries |
                    Sort-Object { [long](Get-OptionalProperty $_ 'fileMtime' 0) } -Descending |
                    Select-Object -First $MaxCount

                # Enrich: index entries have summary+messageCount but no firstPrompt.
                # When summary is absent (no /compact ever run), read the .jsonl to get the opener.
                $enriched = @()
                foreach ($entry in $sorted) {
                    $sid = Get-OptionalProperty $entry 'sessionId' (Get-OptionalProperty $entry 'id' $null)
                    $fp  = $null
                    $summary = Get-OptionalProperty $entry 'summary' $null
                    if (-not $summary -and $sid) {
                        $fp = Get-SessionLabel (Join-Path $folderPath "$sid.jsonl")
                    }
                    $enriched += [PSCustomObject]@{
                        sessionId    = $sid
                        firstPrompt  = if ($fp) { $fp } else { '(no prompt captured)' }
                        summary      = $summary
                        messageCount = ConvertTo-MissionInt (Get-OptionalProperty $entry 'messageCount' 0) 0
                        fileMtime    = [long](Get-OptionalProperty $entry 'fileMtime' 0)
                        modified     = Get-OptionalProperty $entry 'modified' $null
                    }
                }
                return $enriched
            }
        } catch { }
    }

    # Fallback: scan .jsonl files directly when index is missing or empty
    if (-not (Test-Path $folderPath)) { return @() }
    try {
        $jsonls = Get-ChildItem -Path $folderPath -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $MaxCount

        $results = @()
        foreach ($f in $jsonls) {
            $fp = Get-SessionLabel $f.FullName
            $results += [PSCustomObject]@{
                sessionId    = $f.BaseName
                firstPrompt  = if ($fp) { $fp } else { '(no prompt captured)' }
                summary      = $null
                messageCount = 0
                fileMtime    = [long]($f.LastWriteTime.ToUniversalTime() - [datetime]'1970-01-01').TotalMilliseconds
                modified     = $f.LastWriteTime.ToString('o')
            }
        }
        return $results
    } catch {
        return @()
    }
}
