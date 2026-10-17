# 10-util.ps1 - Leaf helpers + command/quoting builders
# Split from Mission-Centre.ps1. Dot-sourced by the root script; relies on the
# script-scoped config globals ($ScanRoot, $Pi*, etc.) defined there.

function Read-YesNo {
    # Single source of truth for confirmation prompts. $Default sets both the [Y/n]/[y/N]
    # hint and the value returned on an empty (Enter-only) response.
    param([string]$Prompt, [ValidateSet('Y', 'N')][string]$Default = 'N')
    $hint = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    $ans = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return ($Default -eq 'Y') }
    return ($ans.Trim().ToUpperInvariant() -in @('Y', 'YES'))
}

function Get-TruncatedSummary {
    param([string]$Text, [int]$MaxLength = 55)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    # Session openers can be multiline; collapse whitespace so a menu row stays one line.
    $Text = ($Text -replace '\s+', ' ').Trim()
    if ($Text.Length -le $MaxLength) { return $Text }
    return $Text.Substring(0, $MaxLength - 3) + '...'
}

function Get-OptionalProperty {
    param([object]$Object, [string]$Name, [object]$DefaultValue)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        $value = $Object.PSObject.Properties[$Name].Value
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
    }
    return $DefaultValue
}

function Get-RawProperty {
    # Presence-based lookup: the raw property value if the property exists, else the default.
    # Use this instead of Get-OptionalProperty for object/array-valued properties - its
    # [string] emptiness probe stringifies an array of PSCustomObjects to '' on PS 5.1
    # (PSCustomObject.ToString() is empty) and would silently discard a real value.
    param([object]$Object, [string]$Name, [object]$DefaultValue = $null)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $DefaultValue
}

function ConvertTo-MissionBool {
    param([object]$Value, [bool]$DefaultValue)
    if ($null -eq $Value) { return $DefaultValue }
    if ($Value -is [bool]) { return $Value }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'y', 'on')) { return $true }
    if ($text -in @('false', '0', 'no', 'n', 'off')) { return $false }
    return $DefaultValue
}

function ConvertTo-MissionInt {
    param([object]$Value, [int]$DefaultValue)
    if ($null -eq $Value) { return $DefaultValue }
    try { return [int]$Value } catch { return $DefaultValue }
}

function ConvertTo-MissionArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Get-OptionalArrayProperty {
    # Array-typed config lookup. Get-OptionalProperty stringifies to test emptiness, so an
    # explicitly configured [] looks "missing" and silently regains the default - which for
    # an allow-list would turn a lockdown config back into the permissive default.
    # Here the default applies only when the property is absent (or JSON null).
    param([object]$Object, [string]$Name, [object[]]$DefaultValue = @())
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        $value = $Object.PSObject.Properties[$Name].Value
        if ($null -ne $value) { return @(ConvertTo-MissionArray $value) }
    }
    return @($DefaultValue)
}

function Resolve-LaunchAction {
    # Map a project-menu key to its engine-independent action. With defaultEngine 'pi' the
    # single letters run pi and Claude moves to CL/CC/CR; with 'claude' it is the original layout.
    # Returns one of: claude-new claude-continue claude-resume pi-new pi-continue pi-resume, or ''.
    param([string]$Key, [string]$Engine = 'claude')
    $k = ([string]$Key).ToUpperInvariant()
    if ($Engine -eq 'pi') {
        switch ($k) {
            'L'  { return 'pi-new' }     'C'  { return 'pi-continue' }     'R'  { return 'pi-resume' }
            'CL' { return 'claude-new' } 'CC' { return 'claude-continue' } 'CR' { return 'claude-resume' }
        }
    } else {
        switch ($k) {
            'L'  { return 'claude-new' } 'C'  { return 'claude-continue' } 'R'  { return 'claude-resume' }
        }
    }
    switch ($k) { 'PI' { return 'pi-new' } 'PC' { return 'pi-continue' } 'PR' { return 'pi-resume' } }
    return ''
}

function Resolve-UserPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~')) {
        return (Join-Path $HOME $expanded.Substring(1).TrimStart('/','\'))
    }
    return $expanded
}

function ConvertTo-MissionSlug {
    param([string]$Value)
    $slug = ([string]$Value).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'mission' }
    if ($slug.Length -gt 42) { $slug = $slug.Substring(0, 42).Trim('-') }
    return $slug
}

function New-MissionName {
    param([string]$BaseName)
    "$(ConvertTo-MissionSlug $BaseName)-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}

function Invoke-InDirectory {
    param([string]$Path, [scriptblock]$Script)
    $prev = Get-Location
    try {
        Set-Location -LiteralPath $Path
        & $Script
    } finally {
        Set-Location $prev
    }
}

function Split-CommandLine {
    param([string]$CommandLine)
    $tokens = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }

    $tokenMatches = [regex]::Matches($CommandLine, '[^\s"]+|"([^"]*)"')
    foreach ($m in $tokenMatches) {
        $value = $m.Value
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $tokens.Add($value)
    }
    return $tokens.ToArray()
}

function Format-CommandForPowerShell {
    param([string]$Command, [string[]]$Arguments)
    $parts = @('&', $Command)
    foreach ($arg in $Arguments) { $parts += (ConvertTo-PowerShellQuotedString $arg) }
    return ($parts -join ' ')
}

function New-JigRunCommand {
    param(
        [string]$ProfileName,
        [string[]]$ClaudeArgs = @()
    )
    $argList = @('run', $ProfileName)
    if ($ClaudeArgs.Count -gt 0) {
        $argList += '--'
        $argList += $ClaudeArgs
    }
    return Format-CommandForPowerShell 'jig' $argList
}

function New-ClaudeCommand {
    param([string[]]$ClaudeArgs = @())
    return Format-CommandForPowerShell 'claude' $ClaudeArgs
}

function Get-PiModelLabel {
    # Display text for the configured pi model: provider/model, or pi's own default when unset.
    $p = [string]$PiProvider; $m = [string]$PiModel
    if ($p -and $m) { return "$p/$m" }
    if ($p) { return "$p (pi's default model)" }
    if ($m) { return $m }
    return "pi's own default model"
}

function New-PiCommand {
    # Build a `pi [--provider <provider>] [--model <model>] [--models <cycle>] <args...>` invocation.
    # Reads the script-scoped $Pi* globals set in Mission-Centre.ps1. An empty provider or model is
    # not passed, so pi falls back to its own ~/.pi/agent/settings.json (an existing pi setup is used as is).
    # -Command overrides the launcher (e.g. vanilla `pi` fallback when the `pii` fork build is missing).
    param([string[]]$PiArgs = @(), [string]$Command = '')
    if ([string]::IsNullOrWhiteSpace($Command)) { $Command = $PiCommand }
    $argList = @()
    if (-not [string]::IsNullOrWhiteSpace($PiProvider)) { $argList += @('--provider', $PiProvider) }
    if (-not [string]::IsNullOrWhiteSpace($PiModel))    { $argList += @('--model', $PiModel) }
    $cycle = ConvertTo-PiModelCycle $PiModelCycle $PiProvider
    if (-not [string]::IsNullOrWhiteSpace($cycle)) {
        $argList += @('--models', $cycle)
    }
    if ($PiArgs.Count -gt 0) { $argList += $PiArgs }
    return Format-CommandForPowerShell $Command $argList
}

function ConvertTo-PiModelCycle {
    # Qualify bare model ids in the Ctrl+P cycle with the configured provider.
    # pi's --models resolver matches a bare id against EVERY provider: `claude-sonnet-5`
    # can exist under several providers (say anthropic/ and a proxy), so the exact match is ambiguous and it
    # falls back to substring matching - which picked the wrong provider
    # (bypassing the configured one), turned `claude-opus-5-5` into `claude-opus-5-5-200k`, and
    # dropped `claude-opus-5` as a duplicate. `provider/id` is an exact, unambiguous match.
    # Left as-is: already-qualified entries (a deliberate other provider) and globs.
    param([string]$Cycle, [string]$Provider)
    if ([string]::IsNullOrWhiteSpace($Cycle)) { return '' }
    $out = foreach ($entry in ($Cycle -split ',')) {
        $e = $entry.Trim()
        if (-not $e) { continue }
        if ([string]::IsNullOrWhiteSpace($Provider) -or $e.Contains('/') -or $e -match '[\*\?\[]') { $e }
        else { "$Provider/$e" }
    }
    return (@($out) -join ',')
}

function ConvertTo-NormalizedPathKey {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return (Resolve-UserPath $Path).TrimEnd('\','/').ToLowerInvariant()
}

function ConvertTo-PowerShellQuotedString {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Format-ProcessArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    # Windows CommandLineToArgvW rule: backslashes are literal EXCEPT before a quote. Double any run
    # of backslashes that precedes a quote (or the closing wrapper quote); escape each quote as \".
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append([char]34)
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq [char]92) {
            $slashes++
        } elseif ($ch -eq [char]34) {
            [void]$sb.Append(([string][char]92) * ($slashes * 2 + 1))
            [void]$sb.Append([char]34)
            $slashes = 0
        } else {
            if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * $slashes); $slashes = 0 }
            [void]$sb.Append($ch)
        }
    }
    if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * ($slashes * 2)) }
    [void]$sb.Append([char]34)
    return $sb.ToString()
}

function ConvertTo-PosixQuotedString {
    param([string]$Value)
    $sq = [string][char]39
    $dq = [string][char]34
    return $sq + $Value.Replace($sq, "$sq$dq$sq$dq$sq") + $sq
}

