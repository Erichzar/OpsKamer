# 05-vibe.ps1 - Retro-future ANSI vibe engine (boxed "mission control" banner + animation)
# Dot-sourced by the root script.
#
# Constraints baked in (verified on Windows PowerShell 5.1 on this machine):
#   * ESC must be [char]27 - backtick-e prints a literal 'e' on 5.1; $PSStyle is 7.2+ only.
#   * Box/block glyphs are built from [char] CODES (not literals), so a no-BOM .ps1 can't mojibake.
#   * [Console]::KeyAvailable / ReadKey THROW under redirected input -> always guard.
#   * Gated behind $script:McVt (may emit ANSI) and $script:McAnimate (may animate); piped/CI/
#     redirected/NO_COLOR fall back to the plain banner and never hang.
#
# Design: a rounded box with the title in the top border + a two-column body (bold logomark left,
# identity panel right), restrained to teal (#2BB3A3 hero) + amber (#F2B33D) + white + grey. The
# placeholder logomark is hand-built block art; swap in a faithful chafa render later (see README).

$script:McEsc   = [char]27
$script:McReset = "$([char]27)[0m"
$script:McVt    = $false
$script:McAnimate = $false
$script:McSound = $false
$script:McSoundVolume = 0.2    # 0.0-1.0, scales synthesized fanfare amplitude
$script:McPanelCache = $null
$script:McProjectCount = 0
$script:McDormantCount = 0
$script:McLogoArt = $null

# OpsKamer palette (dark terminal)
$script:McRule        = @(60, 66, 74)     # #3C424A rules
$script:McAccent      = @(242, 179, 61)   # #F2B33D accent (the lit door)
$script:McPrimary     = @(43, 179, 163)   # #2BB3A3 primary / hero
$script:McPrimaryLite = @(140, 220, 205)  # lighter teal for the gradient top
$script:McWhite    = @(255, 255, 255)  # #FFFFFF
$script:McGrey     = @(163, 164, 170)  # #A3A4AA sub-title

# Glyphs from code points (BOM-safe).
$script:McG = @{
    TL = [char]0x256D; TR = [char]0x256E; BL = [char]0x2570; BR = [char]0x256F   # rounded corners
    H  = [char]0x2500; V  = [char]0x2502                                          # box lines
    FB = [char]0x2588                                                             # full block
    DOT = [char]0x00B7                                                            # middot
}

$script:McTitle = 'MISSION CENTRE'
$script:McInnerWidth = 52

function New-McFg {
    param([int[]]$Rgb)
    return "$($script:McEsc)[38;2;$($Rgb[0]);$($Rgb[1]);$($Rgb[2])m"
}

function Get-McLerpRgb {
    param([int[]]$From, [int[]]$To, [double]$T)
    if ($T -lt 0) { $T = 0 } elseif ($T -gt 1) { $T = 1 }
    return @(
        [int][math]::Round($From[0] + ($To[0] - $From[0]) * $T),
        [int][math]::Round($From[1] + ($To[1] - $From[1]) * $T),
        [int][math]::Round($From[2] + ($To[2] - $From[2]) * $T)
    )
}

function Get-McTitleColored {
    # Solid primary base with an optional moving white shimmer band ($Phase >= 0).
    param([string]$Text, [int]$Phase = -1, [int]$Depth = 5)
    $n = $Text.Length
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $n; $i++) {
        $ch = $Text[$i]
        $rgb = $script:McPrimary
        if ($Phase -ge 0 -and $ch -ne ' ') {
            $d = [math]::Abs($i - $Phase)
            if ($d -lt $Depth) { $rgb = Get-McLerpRgb $script:McPrimary $script:McWhite (1 - ($d / $Depth)) }
        }
        [void]$sb.Append((New-McFg $rgb)); [void]$sb.Append($ch)
    }
    [void]$sb.Append($script:McReset)
    return $sb.ToString()
}

function Add-McSeg {
    # Append a colored segment, return its VISIBLE length (for width-correct padding).
    param([System.Text.StringBuilder]$Sb, [int[]]$Rgb, [string]$Text)
    [void]$Sb.Append((New-McFg $Rgb)); [void]$Sb.Append($Text); [void]$Sb.Append($script:McReset)
    return $Text.Length
}

function Get-McLogoRows {
    # Logomark: a small room ("kamer") with a lit door. Each row is exactly 9 cells; the door
    # blocks (rows 2-4, column 4) are drawn in the accent colour.
    $fb = [string]$script:McG.FB
    return @(
        "   $fb$fb$fb   ",
        " $fb$fb$fb$fb$fb$fb$fb ",
        " $fb$fb $fb $fb$fb ",
        " $fb$fb $fb $fb$fb ",
        " $fb$fb $fb $fb$fb "
    )
}

function Add-McLogoRow {
    # Append one logomark row (9 cells) to $Sb, shimmering a bright band across it when $Phase >= 0.
    # The band metric (col + row*2) makes the highlight sweep diagonally, in sync with the title.
    param([System.Text.StringBuilder]$Sb, [int]$Li, [int]$Phase)
    $logo = Get-McLogoRows
    if ($Li -lt 0 -or $Li -ge $logo.Count) { [void]$Sb.Append(' ' * 9); return 9 }
    $rowStr = $logo[$Li]
    $fb = [string]$script:McG.FB
    $shade = Get-McLerpRgb $script:McPrimaryLite $script:McPrimary ($Li / 4.0)
    $depth = 4
    for ($c = 0; $c -lt $rowStr.Length; $c++) {
        if ([string]$rowStr[$c] -eq $fb) {
            $base = if ($Li -ge 2 -and $c -eq 4) { $script:McAccent } else { $shade }
            $rgb = $base
            if ($Phase -ge 0) {
                $d = [math]::Abs(($c + $Li * 2) - $Phase)
                if ($d -lt $depth) { $rgb = Get-McLerpRgb $base $script:McWhite (1 - ($d / $depth)) }
            }
            [void]$Sb.Append((New-McFg $rgb)); [void]$Sb.Append($rowStr[$c])
        } else {
            [void]$Sb.Append(' ')
        }
    }
    [void]$Sb.Append($script:McReset)
    return $rowStr.Length
}

function Get-McTruncated {
    param([string]$Text, [int]$Max)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, [math]::Max(1, $Max - 1)) + '~'
}

function Build-McTopBorder {
    # The top border line with the embedded, optionally-shimmered title (one inner+2 wide line).
    param([int]$Phase = -1)
    $W = $script:McInnerWidth; $g = $script:McG
    $titlePlain = " $($script:McTitle) "
    $rightPlain = " opskamer "
    $fill = $W - 1 - $titlePlain.Length - $rightPlain.Length - 1
    if ($fill -lt 1) { $fill = 1 }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append((New-McFg $script:McPrimary)); [void]$sb.Append("$($g.TL)$($g.H) ")
    [void]$sb.Append((Get-McTitleColored $script:McTitle $Phase))
    [void]$sb.Append((New-McFg $script:McPrimary)); [void]$sb.Append(' ')
    [void]$sb.Append(([string]$g.H * $fill))
    [void]$sb.Append((New-McFg $script:McGrey)); [void]$sb.Append($rightPlain)
    [void]$sb.Append((New-McFg $script:McPrimary)); [void]$sb.Append("$($g.H)$($g.TR)"); [void]$sb.Append($script:McReset)
    return $sb.ToString()
}

function Build-McPanel {
    # Returns the full boxed banner as one colored string. $Phase >= 0 shimmers the title.
    param([int]$Phase = -1)
    $W = $script:McInnerWidth
    $g = $script:McG
    $logo = Get-McLogoRows
    $user = if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { 'operator' }
    $root = Get-McTruncated ([string]$ScanRoot) 28
    $countLine = "$($script:McProjectCount) projects tracked"
    if ($script:McDormantCount -gt 0) {
        $countLine = "$($script:McProjectCount - $script:McDormantCount) active $($g.DOT) $($script:McDormantCount) dormant"
    }

    # Identity lines (text only; colored below). Index aligns to logo rows 0..4.
    $idWelcome = "Welcome back, $user"
    $idRule    = ([string]$g.H * [math]::Min(34, $idWelcome.Length + 6))
    $idTag     = "opskamer $($g.DOT) mission control"
    $idRootLbl = 'scan root  '

    $sb = [System.Text.StringBuilder]::new()

    # --- top border with embedded title ---
    [void]$sb.Append((Build-McTopBorder $Phase)); [void]$sb.Append("`n")

    # --- body rows (logo left, identity right) ---
    for ($r = 0; $r -lt 7; $r++) {
        $row = [System.Text.StringBuilder]::new()
        $vis = 0
        [void]$row.Append((New-McFg $script:McPrimary)); [void]$row.Append($g.V); [void]$row.Append($script:McReset)
        $vis += Add-McSeg $row $script:McGrey '  '            # left margin

        # logo cell (body rows 1..5 carry the 5 logo rows; shimmers with $Phase)
        $vis += Add-McLogoRow $row ($r - 1) $Phase
        $vis += Add-McSeg $row $script:McGrey '   '           # gap

        # identity cell
        switch ($r) {
            2 { $vis += Add-McSeg $row $script:McWhite $idWelcome }
            3 { $vis += Add-McSeg $row $script:McRule $idRule }
            4 { $vis += Add-McSeg $row $script:McGrey $idTag }
            5 { $vis += Add-McSeg $row $script:McGrey $idRootLbl; $vis += Add-McSeg $row $script:McWhite $root }
            6 { $vis += Add-McSeg $row $script:McGrey $countLine }
            default { }
        }

        if ($vis -lt $W) { [void]$row.Append(' ' * ($W - $vis)) }
        [void]$row.Append((New-McFg $script:McPrimary)); [void]$row.Append($g.V); [void]$row.Append($script:McReset)
        [void]$sb.Append($row.ToString()); [void]$sb.Append("`n")
    }

    # --- bottom border ---
    [void]$sb.Append((New-McFg $script:McPrimary)); [void]$sb.Append($g.BL); [void]$sb.Append(([string]$g.H * $W)); [void]$sb.Append($g.BR); [void]$sb.Append($script:McReset); [void]$sb.Append("`n")
    return $sb.ToString()
}

function Write-McVibeBanner {
    if (-not $script:McPanelCache) { $script:McPanelCache = Build-McPanel -1 }
    [Console]::Out.Write($script:McPanelCache)
    # Remember the panel's BUFFER row (not its window row) so the shimmer can tell later whether it
    # is still where it was painted. The panel is 9 lines (top border, 7 body rows, bottom border);
    # after writing it the cursor sits on the next line.
    $script:McPanelTop = $null
    try {
        $abs = [Console]::CursorTop - 9
        if ($abs - [Console]::WindowTop -ge 0) { $script:McPanelTop = $abs }
    } catch { }
}

function Reset-McPanelCache { $script:McPanelCache = $null; $script:McPanelTop = $null }

function Get-McPanelWindowRow {
    # Pure: the panel's current 0-based WINDOW row, or $null when it may no longer be where it was
    # painted. Called at the prompt, i.e. after the whole menu has been written below the panel.
    #   - Cursor on the buffer's last line: the buffer itself may have scrolled. Under Windows
    #     Terminal (ConPTY) the buffer is the window, so a menu taller than the window shifts every
    #     line up while CursorTop/WindowTop stay put - nothing else reveals it. 2026-10-14: the menu
    #     was 2 lines taller than the window, the shimmer repainted at the old row and drew a second
    #     banner over the first project lines, leaving the real one clipped above it.
    #   - Classic conhost (large buffer): the window moves instead (WindowTop grows), so the row
    #     goes negative.
    #   - Cursor not below the panel: the screen was cleared or rewritten since.
    param($PanelTop, [int]$CursorTop, [int]$WindowTop, [int]$WindowHeight, [int]$BufferHeight)
    if ($null -eq $PanelTop) { return $null }
    $top = [int]$PanelTop
    if ($BufferHeight -le 0 -or $CursorTop -ge $BufferHeight - 1) { return $null }
    if ($CursorTop -lt $top + 9) { return $null }
    $row = $top - $WindowTop
    if ($row -lt 0 -or $row + 9 -gt $WindowHeight) { return $null }
    return $row
}

function Get-McPanelFrameHome {
    # The cursor-home sequence for a shimmer frame, or $null when the panel is not where it was
    # painted (screen scrolled or resized since): then there is no shimmer, never a blind repaint.
    try {
        $row = Get-McPanelWindowRow $script:McPanelTop ([Console]::CursorTop) ([Console]::WindowTop) ([Console]::WindowHeight) ([Console]::BufferHeight)
    } catch { return $null }
    if ($null -eq $row) { return $null }
    return "$($script:McEsc)[$($row + 1);1H"
}

function Read-McMenuLine {
    # Animated line reader for the home prompt: shimmers the title in the top border while waiting
    # for input, echoing what you type. Returns exactly what Read-Host would. Falls back to plain
    # Read-Host whenever we cannot safely animate (redirected, non-console, animations off, a short
    # window where the banner would have scrolled, or any error) - so input is never at risk.
    param([string]$Prompt)
    if (-not $script:McAnimate) { return (Read-Host $Prompt) }
    try { if ([Console]::IsInputRedirected) { return (Read-Host $Prompt) } } catch { return (Read-Host $Prompt) }
    try {
        [Console]::Out.Write($Prompt + ': ')
        # Where to paint: the panel's recorded row. If the screen has scrolled since (the panel's
        # row is off-screen or unknown) we read input without any shimmer at all.
        $frameHome = Get-McPanelFrameHome
        # Bare Read-Host: the prompt is already on screen. An empty-string prompt THROWS ("name cannot be null
        # or empty"), and the catch below then printed the whole prompt a second time.
        if ($null -eq $frameHome) { return (Read-Host) }
        $buffer = ''
        $depth = 5
        $minPhase = -$depth
        $maxPhase = $script:McTitle.Length + $depth
        # Ambient shimmer is OCCASIONAL, not constant: idle quietly, then every 5-20s (random) run
        # one slow sweep across the header and settle back. Calm, but alive. Cursor is saved/restored
        # to the prompt each frame and the repaint is wrapped in synchronized output.
        $nextShimmer = [Environment]::TickCount + (Get-Random -Minimum 5000 -Maximum 20001)
        $framePre = "$($script:McEsc)7$($script:McEsc)[?2026h$frameHome"
        # Restore the cursor BEFORE ending sync, so the atomic frame already has it back at the
        # prompt - otherwise its blink briefly flashes at row 10 (the first recent-projects line).
        $framePost = "$($script:McEsc)8$($script:McEsc)[?2026l"
        while ($true) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    [Console]::Out.Write("`r`n")
                    return $buffer
                } elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                    if ($buffer.Length -gt 0) {
                        $buffer = $buffer.Substring(0, $buffer.Length - 1)
                        [Console]::Out.Write("`b `b")
                    }
                } elseif ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                    $buffer += $key.KeyChar
                    [Console]::Out.Write([string]$key.KeyChar)
                }
            } elseif ([Environment]::TickCount -ge $nextShimmer) {
                # one slow sweep (~110ms per step = a gentle ~2.5s wave), interruptible by a keypress.
                # Hide the cursor for the whole sweep so its blink can't flash below the panel even
                # on terminals without synchronized-output support; restore it when we settle.
                [Console]::Out.Write("$($script:McEsc)[?25l")
                for ($phase = $minPhase; $phase -le $maxPhase; $phase++) {
                    [Console]::Out.Write($framePre + (Build-McPanel $phase) + $framePost)
                    Start-Sleep -Milliseconds 110
                    if ([Console]::KeyAvailable) { break }
                }
                [Console]::Out.Write($framePre + (Build-McPanel -1) + $framePost + "$($script:McEsc)[?25h")   # settle + show cursor
                $nextShimmer = [Environment]::TickCount + (Get-Random -Minimum 5000 -Maximum 20001)
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {
        try { [Console]::Out.Write("`r`n") } catch { }
        return (Read-Host $Prompt)
    }
}

function Build-McFanfareBytes {
    # Synthesize a chiptune as an 8-bit mono PCM WAV (byte[]) - Console.Beep is monophonic, so we
    # mix square waves ourselves. 11025 Hz keeps the high C7 reasonably clean.
    #   Lead : G6 C7 G6 C7(held) B6 A6 G6 A6(held) - the user-specified melody
    #   Bass : a light low root anchoring the held notes for body
    $sr = 11025
    # each note: @(freqHz, startMs, durMs, isDecayingPeak). NEVER put bare arithmetic inside these
    # @() literals - PowerShell parses "a,2*b" as "(a,2)*b" (comma binds tighter than *).
    $lead = @(
        @(1568,0,100,$false),   @(2093,120,100,$false), @(1568,240,100,$false), @(2093,360,220,$false),
        @(1976,600,100,$false), @(1760,720,100,$false), @(1568,840,100,$false), @(1760,960,470,$true)
    )
    $bass = @(@(131,360,220,$false), @(110,960,470,$true))
    $channels = @(@($lead, 0.50), @($bass, 0.34))

    $totalMs = 1430
    $n = [int]($sr * $totalMs / 1000.0) + 1
    $mix = New-Object 'double[]' $n
    foreach ($chan in $channels) {
        $notes = $chan[0]; $amp = [double]$chan[1]
        foreach ($note in $notes) {
            $freq = [double]$note[0]
            $i0 = [int]($note[1] / 1000.0 * $sr)
            $i1 = [int](($note[1] + $note[2]) / 1000.0 * $sr)
            if ($i1 -gt $n) { $i1 = $n }
            $span = [double]($i1 - $i0)
            for ($i = $i0; $i -lt $i1; $i++) {
                $ph = (($i / [double]$sr) * $freq) % 1.0
                $sq = if ($ph -lt 0.5) { 1.0 } else { -1.0 }
                if ($note[3]) {
                    $env = [math]::Exp(-3.2 * (($i - $i0) / $span))      # peak: ring out
                } else {
                    $rel = ($i1 - $i)
                    $env = if ($rel -lt 48) { $rel / 48.0 } else { 1.0 } # tiny release to soften clicks
                }
                $mix[$i] += $amp * $env * $sq
            }
        }
    }
    # SoundPlayer has no volume API, so loudness is baked into the samples here: scale the
    # peak deviation (max 127 for 8-bit) by the configured volume. 0.2 -> peak ~24 (~-14 dB).
    $vol = if ($null -ne $script:McSoundVolume) { [double]$script:McSoundVolume } else { 0.2 }
    if ($vol -lt 0) { $vol = 0 } elseif ($vol -gt 1) { $vol = 1 }
    $peak = 120 * $vol
    $pcm = New-Object 'byte[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $v = $mix[$i]; if ($v -gt 1) { $v = 1 } elseif ($v -lt -1) { $v = -1 }
        $pcm[$i] = [byte][int](128 + $v * $peak)
    }
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([uint32](36 + $n)); $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('fmt ')); $bw.Write([uint32]16); $bw.Write([uint16]1); $bw.Write([uint16]1)
    $bw.Write([uint32]$sr); $bw.Write([uint32]$sr); $bw.Write([uint16]1); $bw.Write([uint16]8)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([uint32]$n); $bw.Write($pcm)
    $bw.Flush()
    return $ms.ToArray()
}

function Play-McChiptune {
    # Build the chiptune WAV, then play it on a background runspace (PlaySync keeps the player +
    # stream alive) so it rings over the intro animation. Windows only, gated, all failures swallowed.
    if (-not $script:McSound) { return }
    if (-not $MissionIsWindows) { return }
    try {
        $wav = Build-McFanfareBytes
        $rs = [PowerShell]::Create()
        [void]$rs.AddScript({
            param($bytes)
            try {
                $ms = New-Object System.IO.MemoryStream (, $bytes)
                $sp = New-Object System.Media.SoundPlayer $ms
                $sp.PlaySync()
                $sp.Dispose(); $ms.Dispose()
            } catch { }
        }).AddArgument($wav)
        [void]$rs.BeginInvoke()
    } catch { }
}

function Get-McLogoArt {
    # Optional full-screen splash art from lib/splash.ans (block art, read at runtime so Unicode
    # glyphs are safe regardless of .ps1 encoding). None ships; without it the intro shows the panel.
    if ($null -ne $script:McLogoArt) { return $script:McLogoArt }
    $script:McLogoArt = @()
    try {
        $path = Join-Path $MissionLibDir 'splash.ans'
        if (Test-Path $path) { $script:McLogoArt = @(Get-Content -Path $path -Encoding UTF8) }
    } catch { }
    return $script:McLogoArt
}

function Show-McIntro {
    # Intro splash: the splash art (or the panel) with the chiptune. With -Hold
    # it waits ~1.5s then clears (the old one-shot behaviour); without it, it RETURNS with the
    # logo still up, so the caller can show start-up progress beneath it (Start-MissionCentre
    # does: self-update, registry sync, checks) and clear when ready - no black screen while the
    # checks run. $script:McIntroShownAt records when the logo went up.
    param([switch]$Hold)
    $script:McIntroShownAt = [Environment]::TickCount
    if (-not $script:McAnimate) { return }
    $logo = Get-McLogoArt
    try {
        try { [Console]::CursorVisible = $false } catch { }
        Clear-Host
        if ($logo.Count -gt 0) {
            $w = 80; try { $w = [Console]::WindowWidth } catch { }
            $h = 30; try { $h = [Console]::WindowHeight } catch { }
            $indent = ' ' * [math]::Max(0, [int](($w - 56) / 2))
            $top = [math]::Max(0, [int](($h - $logo.Count - 2) / 2))
            $sb = [System.Text.StringBuilder]::new()
            for ($i = 0; $i -lt $top; $i++) { [void]$sb.Append("`n") }
            [void]$sb.Append((New-McFg $script:McPrimary))
            foreach ($row in $logo) { [void]$sb.Append($indent); [void]$sb.Append($row); [void]$sb.Append("`n") }
            [void]$sb.Append($script:McReset)
            [Console]::Out.Write($sb.ToString())
        } else {
            [Console]::Out.Write((Build-McPanel -1))
        }
        Play-McChiptune
        if (-not $Hold) { [Console]::Out.Write("`n"); return }
        # hold while the riff rings out (~1.5s), skippable by any key
        $waited = 0
        while ($waited -lt 1550) {
            Start-Sleep -Milliseconds 50; $waited += 50
            if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }
        }
    } catch {
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        [Console]::Out.Write($script:McReset)
        if ($Hold) { Clear-Host }                             # splash goes away; menu takes over
    }
}

function Invoke-McStartupStep {
    # Run one start-up step with a progress line under the intro logo:  "  > label ... done (0.8s)".
    # Output the step prints itself (update notices, warnings) stays visible beneath, so nothing
    # is hidden; the screen is cleared only when the menu is ready (Complete-McIntro).
    param([string]$Label, [scriptblock]$Action)
    $w = 80; try { $w = [Console]::WindowWidth } catch { }
    $pad = ' ' * [math]::Max(0, [int](($w - 56) / 2))
    Write-Host ("{0}  > {1} ..." -f $pad, $Label) -NoNewline -ForegroundColor DarkGray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $null
    try { $result = & $Action } finally {
        $sw.Stop()
        Write-Host (" done ({0:0.0}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
    return $result
}

function Complete-McIntro {
    # Keep the logo up for at least ~1.5s in total (the riff), then clear for the menu.
    if ($script:McAnimate -and $script:McIntroShownAt) {
        $left = 1550 - ([Environment]::TickCount - $script:McIntroShownAt)
        while ($left -gt 0) {
            Start-Sleep -Milliseconds 50; $left -= 50
            if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }
        }
    }
    try { [Console]::CursorVisible = $true } catch { }
    [Console]::Out.Write($script:McReset)
    Clear-Host
}

function Show-McMatrixRain {
    # Easter egg: a short teal/amber "digital rain" splash. Any key skips. Gated like everything.
    param([int]$Frames = 26, [int]$Width = 54, [int]$Height = 12)
    if (-not $script:McAnimate) { return }
    $chars = 'OPSKAMER01<>/\|=+*{}'.ToCharArray()
    $heads  = New-Object 'double[]' $Width
    $speeds = New-Object 'double[]' $Width
    for ($c = 0; $c -lt $Width; $c++) {
        $heads[$c]  = -1 * (Get-Random -Minimum 0 -Maximum $Height)
        $speeds[$c] = (Get-Random -Minimum 4 -Maximum 11) / 10.0
    }
    try {
        try { [Console]::CursorVisible = $false } catch { }
        Clear-Host
        for ($f = 0; $f -lt $Frames; $f++) {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("$($script:McEsc)[H")
            for ($row = 0; $row -lt $Height; $row++) {
                for ($col = 0; $col -lt $Width; $col++) {
                    $d = $heads[$col] - $row
                    if ($heads[$col] -ge 0 -and $row -le $heads[$col] -and $d -lt 9) {
                        $ch = $chars[(Get-Random -Maximum $chars.Length)]
                        if ($d -lt 1) {
                            [void]$sb.Append("$($script:McEsc)[38;2;255;255;255m$ch")
                        } elseif ($d -lt 2.5) {
                            [void]$sb.Append("$($script:McEsc)[38;2;0;176;255m$ch")
                        } elseif ($d -lt 4 -and ($col % 7) -eq ($f % 7)) {
                            [void]$sb.Append("$($script:McEsc)[38;2;227;95;43m$ch")
                        } else {
                            $k = 1 - ($d / 9)
                            [void]$sb.Append("$($script:McEsc)[38;2;0;$([int](150 * $k));$([int](200 * $k))m$ch")
                        }
                    } else {
                        [void]$sb.Append(' ')
                    }
                }
                [void]$sb.Append("$($script:McEsc)[0m`n")
            }
            [Console]::Out.Write($sb.ToString())
            for ($col = 0; $col -lt $Width; $col++) {
                $heads[$col] += $speeds[$col]
                if (($heads[$col] - $Height) -gt (Get-Random -Maximum 6)) {
                    $heads[$col] = 0
                    $speeds[$col] = (Get-Random -Minimum 4 -Maximum 11) / 10.0
                }
            }
            Start-Sleep -Milliseconds 55
            if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }
        }
    } catch {
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        [Console]::Out.Write($script:McReset)
        Clear-Host
    }
}

function Enable-McVtMode {
    if ($PSVersionTable.PSVersion.Major -ge 6) { return $true }
    if ($MissionIsMacOS -or $MissionIsLinux) { return $true }
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Mc.NativeVt').Type) {
            Add-Type -Namespace 'Mc' -Name 'NativeVt' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [Mc.NativeVt]::GetStdHandle(-11)
        $mode = 0
        if (-not [Mc.NativeVt]::GetConsoleMode($h, [ref]$mode)) { return $false }
        return [Mc.NativeVt]::SetConsoleMode($h, ($mode -bor 0x0004))
    } catch {
        return $false
    }
}

function Initialize-McVibe {
    param([bool]$AnimationsEnabled = $true, [bool]$SoundEnabled = $true, [double]$SoundVolume = 0.2)
    if ($SoundVolume -lt 0) { $SoundVolume = 0 } elseif ($SoundVolume -gt 1) { $SoundVolume = 1 }
    $script:McSoundVolume = $SoundVolume
    $outRedir = $true; $inRedir = $true; $supportsVt = $false
    try { $outRedir = [Console]::IsOutputRedirected } catch { }
    try { $inRedir  = [Console]::IsInputRedirected } catch { }
    try { $supportsVt = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
    $noColor = [bool]$env:NO_COLOR
    $dumb    = ($env:TERM -eq 'dumb' -or $env:TERM -eq 'xterm-mono')
    if (-not $outRedir -and -not $noColor -and -not $dumb) {
        $vtOk = Enable-McVtMode
        $script:McVt = ($vtOk -and ($supportsVt -or $PSVersionTable.PSVersion.Major -ge 6 -or $MissionIsWindows))
    } else {
        $script:McVt = $false
    }
    $script:McAnimate = $script:McVt -and $AnimationsEnabled -and (-not $inRedir) -and ($Host.Name -eq 'ConsoleHost')
    $script:McSound = $SoundEnabled -and (-not $inRedir) -and $MissionIsWindows -and ($Host.Name -eq 'ConsoleHost')
}
