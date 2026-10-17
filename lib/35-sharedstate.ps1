# 35-sharedstate.ps1 - Mission Centre on every device: self-update + shared project registry
# Dot-sourced by the root script; relies on the script-scoped globals defined there
# ($SelfUpdateEnabled, $DeviceName, $SharedState*, $MissionRootDir, $MissionStateDir).
#
# Why: each device kept its own projects.json (gitignored, path-keyed) and its own code
# checkout, so devices drifted apart. Two fixes:
#
#  1. Self-update. On launch, fast-forward this checkout to its upstream and restart into
#     the new code. Only a clean tree that is purely behind is touched; anything else is
#     left alone with a note.
#  2. Shared registry. A git repo (e.g. a PRIVATE https://github.com/<you>/<registry>.git; any git@host:repo also works)
#     holds one JSON file per project under projects/. A project is identified by its
#     normalized git remote, so the same repository is the same project on every device,
#     and it records its local folder PER DEVICE. projects.json stays as this device's
#     cache, so Mission Centre works offline and every existing function keeps using `path`.
#
# Merge rules: shared fields (name, description, profile, dormancy, remote) come from the
# shared record, which is what any device saved last; a device's own edits are written to
# the record at save time and win a rebase over older remote state. Paths are per device.

$script:SharedRecords = $null          # id -> ordered record; set by Import-ProjectConfig
$script:SharedStateStatus = 'off'      # off | synced | offline | error: <why>
# kickoff = 'skipped': [L] goes straight to pi without offering a kickoff (asked once, any device).
$SharedFields = @('name', 'description', 'profile', 'added', 'dormant', 'dormantSince', 'reactivatedOn', 'remote', 'kickoff')

# ---------------------------------------------------------------------------
# Pure helpers (no git, no disk) - unit tested
# ---------------------------------------------------------------------------

function Get-DefaultDeviceName {
    $n = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($n)) { try { $n = [System.Net.Dns]::GetHostName() } catch { $n = '' } }
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'device' }
    return ($n.Split('.')[0]).ToUpperInvariant()
}

function ConvertTo-RemoteId {
    # Normalize a git remote URL to a stable project id:
    #   https://<user>@github.com/Owner/Repo.git | git@github.com:Owner/Repo.git
    #   | ssh://git@github.com:22/Owner/Repo   ->  github.com/owner/repo
    # Returns '' for local paths and anything that is not a recognizable remote.
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    $u = $Url.Trim()
    if ($u -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        if ($u -match '^file://') { return '' }
        $u = $u -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
        $u = $u -replace '^[^@/]*@', ''
        $u = $u -replace '^([^/:]+):\d+/', '$1/'
    } elseif ($u -match '^[^@/\\\s]+@[^:/\\\s]+:') {
        $u = $u -replace '^[^@]+@', ''
        $u = $u -replace '^([^:]+):', '$1/'
    } elseif ($u -match '^[^/\\\s:]{2,}:[^/\\]') {
        # ssh host alias, e.g. myserver:notes (two+ chars before ':' so C:\x never matches)
        $u = $u -replace '^([^:]+):', '$1/'
    } else {
        return ''
    }
    $u = ($u -replace '\.git/?$', '') -replace '/+$', ''
    if ($u -notmatch '/') { return '' }
    return $u.ToLowerInvariant()
}

function Remove-UrlCredential {
    # Never let a token embedded in a remote URL (https://user:token@host/...) reach the
    # shared registry.
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    return ($Url.Trim() -replace '^([a-zA-Z][a-zA-Z0-9+.-]*://)[^@/]+@', '$1')
}

function ConvertTo-StateFileName {
    param([string]$Id)
    $n = ($Id.ToLowerInvariant() -replace '[^a-z0-9._-]+', '_').Trim('_')
    if (-not $n) { $n = 'project' }
    return "$n.json"
}

function New-LocalProjectId {
    # For a project with no git remote: unique, stable once stored.
    param([string]$Name)
    return 'local/' + (ConvertTo-MissionSlug $Name) + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 6))
}

function Set-ProjectProperty {
    param([object]$Project, [string]$Name, [object]$Value)
    if ($Project.PSObject.Properties[$Name]) { $Project.$Name = $Value }
    else { $Project | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Remove-ProjectProperty {
    param([object]$Project, [string]$Name)
    if ($Project.PSObject.Properties[$Name]) { $Project.PSObject.Properties.Remove($Name) }
}

function ConvertTo-RecordTable {
    # Parsed JSON (PSCustomObject) -> ordered record with an ordered `paths` table.
    param([object]$Obj)
    $t = [ordered]@{}
    foreach ($p in $Obj.PSObject.Properties) { $t[$p.Name] = $p.Value }
    $paths = [ordered]@{}
    if ($t.Contains('paths') -and $null -ne $t['paths']) {
        foreach ($p in $t['paths'].PSObject.Properties) { $paths[$p.Name] = [string]$p.Value }
    }
    $t['paths'] = $paths
    return $t
}

function ConvertTo-RecordJson {
    # Content used for change detection: excludes the updated/updatedBy stamp.
    param([System.Collections.IDictionary]$Record, [switch]$WithStamp)
    $t = [ordered]@{}
    foreach ($k in @($Record.Keys)) {
        if (-not $WithStamp -and ($k -eq 'updated' -or $k -eq 'updatedBy')) { continue }
        $t[$k] = $Record[$k]
    }
    return (ConvertTo-Json -InputObject $t -Depth 6)
}

function New-RecordFromProject {
    # Build the shared record for a project, keeping other devices' paths from $Existing.
    param([object]$Project, [string]$Device, [System.Collections.IDictionary]$Existing = $null)
    $r = [ordered]@{ id = [string]$Project.id }
    foreach ($f in $SharedFields) {
        $v = Get-OptionalProperty $Project $f $null
        if ($null -ne $v -and [string]$v -ne '') { $r[$f] = $v }
    }
    $paths = [ordered]@{}
    if ($null -ne $Existing -and $Existing.Contains('paths')) {
        foreach ($k in @($Existing['paths'].Keys)) { $paths[$k] = [string]$Existing['paths'][$k] }
    }
    $paths[$Device] = [string]$Project.path
    $r['paths'] = $paths
    if ($null -ne $Existing) {
        foreach ($k in @('updated', 'updatedBy')) { if ($Existing.Contains($k)) { $r[$k] = $Existing[$k] } }
    }
    return $r
}

function New-ProjectFromRecord {
    param([System.Collections.IDictionary]$Record, [string]$Path)
    $p = [PSCustomObject]@{ path = $Path }
    foreach ($f in @('name', 'description', 'added', 'profile')) {
        Set-ProjectProperty $p $f $(if ($Record.Contains($f)) { $Record[$f] } else { '' })
    }
    foreach ($f in @('dormant', 'dormantSince', 'reactivatedOn', 'remote')) {
        if ($Record.Contains($f)) { Set-ProjectProperty $p $f $Record[$f] }
    }
    Set-ProjectProperty $p 'id' ([string]$Record['id'])
    return $p
}

function Set-StampIfChanged {
    # Stamp a record as changed by this device, only when its content really changed.
    param([System.Collections.IDictionary]$New, [System.Collections.IDictionary]$Old, [string]$Device)
    if ($null -ne $Old -and (ConvertTo-RecordJson $New) -eq (ConvertTo-RecordJson $Old)) { return $false }
    $New['updated'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $New['updatedBy'] = $Device
    return $true
}

function Merge-SharedProjects {
    # Local cache + shared records -> this device's project list, plus the ids of records
    # that changed (new projects, this device's path). Mutates $Records. No git, no disk
    # (Get-ProjectSharedId may ask git for a remote, once per project, then caches it).
    param([object[]]$Local, [System.Collections.IDictionary]$Records, [string]$Device)
    $projects = [System.Collections.Generic.List[object]]::new()
    $changed = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($p in @($Local)) {
        if ($null -eq $p) { continue }
        $hasId = [bool][string](Get-OptionalProperty $p 'id' '')
        $hasRemote = [bool][string](Get-OptionalProperty $p 'remote' '')
        if (-not $hasId -or (-not $hasRemote -and [string]$p.id -notlike 'local/*')) {
            # Learn the git remote once (it then rides in the cache): it is the id, and the
            # record needs it so other devices can clone the project from [O].
            $remote = Get-ProjectGitRemote ([string](Get-OptionalProperty $p 'path' ''))
            $rid = ConvertTo-RemoteId $remote
            if ($remote -and -not $hasRemote) { Set-ProjectProperty $p 'remote' $remote }
            if (-not $hasId) {
                if ($rid) { Set-ProjectProperty $p 'id' $rid }
                else {
                    # No remote: adopt a remote-less record with the same name that this
                    # device doesn't have yet, so one folder on two devices stays one project.
                    $match = Find-RecordByName $Records (Get-ProjectName $p) $Device
                    if ($match) { Set-ProjectProperty $p 'id' $match }
                }
            }
        }
        $id = Get-ProjectSharedId $p
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        if ($Records.Contains($id)) {
            $r = $Records[$id]
            # Shared fields: the record wins (it is what any device saved last).
            foreach ($f in $SharedFields) {
                if ($r.Contains($f)) { Set-ProjectProperty $p $f $r[$f] }
                elseif ($f -in @('dormant', 'dormantSince', 'reactivatedOn')) { Remove-ProjectProperty $p $f }
            }
            # What the record lacks (this device's path, a remote no device knew yet) comes
            # from the project; everything the record has, it keeps.
            $new = New-RecordFromProject $p $Device $r
            if (Set-StampIfChanged $new $r $Device) { $Records[$id] = $new; $changed.Add($id) }
        } else {
            $new = New-RecordFromProject $p $Device
            [void](Set-StampIfChanged $new $null $Device)
            $Records[$id] = $new
            $changed.Add($id)
        }
        $projects.Add($p)
    }
    # Records that list this device but are missing from the local cache (cache lost, or
    # the project was adopted on this device by another Mission Centre checkout). Path
    # existence is NOT checked: an unmounted drive must not drop a project.
    foreach ($id in @($Records.Keys)) {
        if ($seen.ContainsKey($id)) { continue }
        $r = $Records[$id]
        if ($r['paths'].Contains($Device) -and [string]$r['paths'][$Device]) {
            $projects.Add((New-ProjectFromRecord $r ([string]$r['paths'][$Device])))
            $seen[$id] = $true
        }
    }
    return [PSCustomObject]@{ projects = $projects.ToArray(); changed = $changed.ToArray() }
}

function Find-RecordByName {
    # Id of a remote-less record named $Name (case-insensitive) that $Device has no path
    # for yet; '' when none or ambiguous.
    param([System.Collections.IDictionary]$Records, [string]$Name, [string]$Device)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $hits = @(foreach ($id in @($Records.Keys)) {
        $r = $Records[$id]
        if ($r.Contains('remote') -and [string]$r['remote']) { continue }
        if ($r['paths'].Contains($Device)) { continue }
        if ([string]$r['name'] -ieq $Name.Trim()) { $id }
    })
    if ($hits.Count -eq 1) { return [string]$hits[0] }
    return ''
}

function Update-SharedRecordsFromProjects {
    # This device's saved project list -> changed and deleted record ids. Mutates $Records.
    # A project missing from the list loses only THIS device's path; the record goes when
    # no device has it any more.
    param([object[]]$Projects, [System.Collections.IDictionary]$Records, [string]$Device)
    $changed = [System.Collections.Generic.List[string]]::new()
    $deleted = [System.Collections.Generic.List[string]]::new()
    $present = @{}
    foreach ($p in @($Projects)) {
        if ($null -eq $p) { continue }
        $id = Get-ProjectSharedId $p
        $present[$id] = $true
        $old = if ($Records.Contains($id)) { $Records[$id] } else { $null }
        $new = New-RecordFromProject $p $Device $old
        if (Set-StampIfChanged $new $old $Device) { $Records[$id] = $new; $changed.Add($id) }
    }
    foreach ($id in @($Records.Keys)) {
        if ($present.ContainsKey($id)) { continue }
        $r = $Records[$id]
        if (-not $r['paths'].Contains($Device)) { continue }
        $r['paths'].Remove($Device)
        if ($r['paths'].Count -eq 0) {
            $Records.Remove($id); $deleted.Add($id)
        } else {
            [void](Set-StampIfChanged $r $null $Device); $changed.Add($id)
        }
    }
    return [PSCustomObject]@{ changed = $changed.ToArray(); deleted = $deleted.ToArray() }
}

function Get-OtherDeviceRecords {
    # Shared projects with no folder on this device (candidates for [O] clone).
    param([System.Collections.IDictionary]$Records, [string]$Device)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Records) { return @() }
    foreach ($id in @($Records.Keys)) {
        $r = $Records[$id]
        if (-not $r['paths'].Contains($Device)) { $out.Add($r) }
    }
    return @($out | Sort-Object { [string]$_['name'] })
}

# ---------------------------------------------------------------------------
# Disk + git
# ---------------------------------------------------------------------------

function Get-ProjectGitRemote {
    param([string]$Path)
    $git = Get-GitExecutable
    if (-not $git -or [string]::IsNullOrWhiteSpace($Path)) { return '' }
    # Not Join-Path: on PS 5.1 it THROWS (DriveNotFound) for an unmounted drive, e.g. a
    # G:\ Google shared drive that is offline, which would abort the whole sync.
    try { $dotGit = [System.IO.Path]::Combine($Path, '.git') } catch { return '' }
    if (-not (Test-Path -LiteralPath $dotGit)) { return '' }
    $r = Invoke-ProcessCapture -FilePath $git -ArgumentList @('remote', 'get-url', 'origin') -WorkingDirectory $Path -TimeoutSeconds 10
    if ($r.ok) { return (Remove-UrlCredential $r.out) }
    return ''
}

function Get-ProjectSharedId {
    # Stable id for a project: kept on the object once computed (it rides in projects.json).
    param([object]$Project)
    $id = [string](Get-OptionalProperty $Project 'id' '')
    if ($id) { return $id }
    $remote = Get-ProjectGitRemote ([string](Get-OptionalProperty $Project 'path' ''))
    $rid = ConvertTo-RemoteId $remote
    $id = if ($rid) { $rid } else { New-LocalProjectId (Get-ProjectName $Project) }
    Set-ProjectProperty $Project 'id' $id
    if ($remote -and -not [string](Get-OptionalProperty $Project 'remote' '')) { Set-ProjectProperty $Project 'remote' $remote }
    return $id
}

function Read-SharedRecords {
    param([string]$Dir)
    $records = [ordered]@{}
    $pdir = Join-Path $Dir 'projects'
    if (-not (Test-Path $pdir)) { return $records }
    foreach ($f in @(Get-ChildItem -Path $pdir -Filter '*.json' -File | Sort-Object Name)) {
        try {
            $o = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $t = ConvertTo-RecordTable $o
            if ([string]$t['id']) { $records[[string]$t['id']] = $t }
        } catch {
            Write-MissionLog 'WARN' "shared state: unreadable $($f.Name): $_"
        }
    }
    return $records
}

function Write-SharedRecords {
    param([System.Collections.IDictionary]$Records, [string[]]$Changed, [string[]]$Deleted, [string]$Dir)
    $pdir = Join-Path $Dir 'projects'
    if (-not (Test-Path $pdir)) { New-Item -ItemType Directory -Path $pdir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false     # no BOM: same bytes from PS 5.1 and 7
    foreach ($id in @($Changed)) {
        if (-not $Records.Contains($id)) { continue }
        $json = (ConvertTo-RecordJson $Records[$id] -WithStamp) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText((Join-Path $pdir (ConvertTo-StateFileName $id)), $json + "`n", $utf8)
    }
    foreach ($id in @($Deleted)) {
        $f = Join-Path $pdir (ConvertTo-StateFileName $id)
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
}

function Test-SharedStateEnabled {
    return ($SharedStateEnabled -and -not [string]::IsNullOrWhiteSpace($SharedStateRemote))
}

function Invoke-SharedGit {
    # git in the shared-state clone, non-interactive and quick to give up when offline.
    param([string[]]$GitArgs, [int]$TimeoutSeconds = 20, [string]$Dir = $SharedStateDir)
    $git = Get-GitExecutable
    if (-not $git) { return [PSCustomObject]@{ ok = $false; exit = $null; out = 'git not found' } }
    $oldSsh = $env:GIT_SSH_COMMAND; $oldPrompt = $env:GIT_TERMINAL_PROMPT
    try {
        $ssh = 'ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new'
        if (-not [string]::IsNullOrWhiteSpace($SharedStateSshKey)) {
            $ssh += ' -o IdentitiesOnly=yes -i "' + ($SharedStateSshKey -replace '\\', '/') + '"'
        }
        $env:GIT_SSH_COMMAND = $ssh
        $env:GIT_TERMINAL_PROMPT = '0'
        return (Invoke-ProcessCapture -FilePath $git -ArgumentList $GitArgs -WorkingDirectory $Dir -TimeoutSeconds $TimeoutSeconds)
    } finally {
        $env:GIT_SSH_COMMAND = $oldSsh; $env:GIT_TERMINAL_PROMPT = $oldPrompt
    }
}

function Save-SharedStateCommit {
    # Commit whatever changed under projects/ (local only; cheap, works offline).
    param([string]$Message)
    [void](Invoke-SharedGit @('add', '-A', 'projects'))
    $st = Invoke-SharedGit @('status', '--porcelain')
    if ($st.ok -and -not [string]::IsNullOrWhiteSpace($st.out)) {
        [void](Invoke-SharedGit @('commit', '--quiet', '-m', $Message))
    }
}

function Sync-SharedStatePull {
    # Clone or update the local copy. Never fatal: offline means "use the last copy".
    # Returns $true when the remote was reached.
    if (-not (Test-Path (Join-Path $SharedStateDir '.git'))) {
        if (-not (Test-Path $MissionStateDir)) { New-Item -ItemType Directory -Path $MissionStateDir -Force | Out-Null }
        $c = Invoke-SharedGit @('clone', '--quiet', $SharedStateRemote, $SharedStateDir) -Dir $MissionStateDir -TimeoutSeconds 30
        if (-not $c.ok) {
            $script:SharedStateStatus = 'offline'
            Write-MissionLog 'WARN' "shared state: clone of $SharedStateRemote failed"
            return $false
        }
        [void](Invoke-SharedGit @('symbolic-ref', 'HEAD', 'refs/heads/main'))
        [void](Invoke-SharedGit @('config', 'user.name', "Mission Centre ($DeviceName)"))
        [void](Invoke-SharedGit @('config', 'user.email', "mission-centre@$($DeviceName.ToLowerInvariant()).local"))
        [void](Invoke-SharedGit @('config', 'core.autocrlf', 'false'))
    } else {
        # sharedState.remote changed (e.g. moved from a home server to GitHub): repoint the
        # existing copy. Its unpushed commits are replayed onto the new remote below.
        $u = Invoke-SharedGit @('remote', 'get-url', 'origin')
        if ($u.ok -and $u.out.Trim() -ne $SharedStateRemote) {
            [void](Invoke-SharedGit @('remote', 'set-url', 'origin', $SharedStateRemote))
            Write-MissionLog 'INFO' "shared state: remote changed $($u.out.Trim()) -> $SharedStateRemote"
        }
    }
    Save-SharedStateCommit "$DeviceName`: pending changes"
    $f = Invoke-SharedGit @('fetch', '--quiet', 'origin') -TimeoutSeconds 15
    if (-not $f.ok) { $script:SharedStateStatus = 'offline'; return $false }
    if (-not (Invoke-SharedGit @('rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main')).ok) {
        $script:SharedStateStatus = 'synced'; return $true          # remote still empty
    }
    if (-not (Invoke-SharedGit @('rev-parse', '--verify', '--quiet', 'HEAD')).ok) {
        [void](Invoke-SharedGit @('reset', '--quiet', '--hard', 'origin/main'))
        $script:SharedStateStatus = 'synced'; return $true
    }
    # Replay this device's unpushed commits on top; on a same-file clash, this device's
    # version wins (-X theirs means "the commits being replayed" during a rebase).
    $rb = Invoke-SharedGit @('rebase', '--quiet', '-X', 'theirs', 'origin/main') -TimeoutSeconds 30
    if (-not $rb.ok) {
        [void](Invoke-SharedGit @('rebase', '--abort'))
        $script:SharedStateStatus = 'error: rebase failed'
        Write-MissionLog 'WARN' 'shared state: rebase onto origin/main failed; using the local copy'
        return $false
    }
    $script:SharedStateStatus = 'synced'
    return $true
}

function Push-SharedState {
    param([string]$Message)
    Save-SharedStateCommit $Message
    $p = Invoke-SharedGit @('push', '--quiet', 'origin', 'HEAD:main') -TimeoutSeconds 20
    if (-not $p.ok -and (Sync-SharedStatePull)) {
        $p = Invoke-SharedGit @('push', '--quiet', 'origin', 'HEAD:main') -TimeoutSeconds 20
    }
    if (-not $p.ok) {
        $script:SharedStateStatus = 'offline'
        Write-MissionLog 'WARN' 'shared state: push failed; changes kept locally and retried next time'
    }
    return $p.ok
}

function Sync-ProjectsWithSharedState {
    # Called by Import-ProjectConfig: pull, merge with the local cache, push what changed.
    param([object[]]$Local)
    $online = Sync-SharedStatePull
    $records = Read-SharedRecords $SharedStateDir
    $m = Merge-SharedProjects $Local $records $DeviceName
    $script:SharedRecords = $records
    if (@($m.changed).Count -gt 0) {
        Write-SharedRecords $records $m.changed @() $SharedStateDir
        if ($online) { [void](Push-SharedState "$DeviceName`: sync $(@($m.changed).Count) project(s)") }
        else { Save-SharedStateCommit "$DeviceName`: sync $(@($m.changed).Count) project(s)" }
    } elseif ($online) {
        # Nothing new, but commits may still be waiting: saved while offline, or made before
        # sharedState.remote moved. Push them now rather than on the next change.
        $ahead = Invoke-SharedGit @('rev-list', '--count', 'origin/main..HEAD')
        $pending = if ($ahead.ok) { [int]($ahead.out.Trim()) -gt 0 }
                   else { (Invoke-SharedGit @('rev-parse', '--verify', '--quiet', 'HEAD')).ok }   # remote still empty
        if ($pending) { [void](Push-SharedState "$DeviceName`: push pending changes") }
    }
    Save-LocalProjectCache $m.projects
    return $m.projects
}

function Save-ProjectsToSharedState {
    # Called by Save-Config after any registry change on this device.
    param([object[]]$Projects)
    if ($null -eq $script:SharedRecords) { return }
    $u = Update-SharedRecordsFromProjects $Projects $script:SharedRecords $DeviceName
    $n = @($u.changed).Count + @($u.deleted).Count
    if ($n -eq 0) { return }
    Write-SharedRecords $script:SharedRecords $u.changed $u.deleted $SharedStateDir
    [void](Push-SharedState "$DeviceName`: update $n project(s)")
}

# ---------------------------------------------------------------------------
# [O] projects on other devices
# ---------------------------------------------------------------------------

function Show-OtherDeviceProjects {
    param([ref]$ConfigRef)
    if (-not (Test-SharedStateEnabled)) {
        Write-Host '  Shared registry is off. Set sharedState in config.json (see README).' -ForegroundColor Yellow
        Read-Host '  Press Enter to continue' | Out-Null
        return
    }
    while ($true) {
        Clear-Host
        $others = @(Get-OtherDeviceRecords $script:SharedRecords $DeviceName)
        Write-Host ''
        Write-Host ("  Projects on other devices ({0})  -  this device: {1}, registry: {2}" -f $others.Count, $DeviceName, $script:SharedStateStatus) -ForegroundColor Cyan
        Write-Divider
        if ($others.Count -eq 0) {
            Write-Host '  Every shared project is already on this device.' -ForegroundColor DarkGray
            Read-Host '  Press Enter to continue' | Out-Null
            return
        }
        for ($i = 0; $i -lt $others.Count; $i++) {
            $r = $others[$i]
            $devs = (@($r['paths'].Keys) -join ', ')
            $hint = if ($r.Contains('remote') -and $r['remote']) { 'clonable' } else { 'no git remote' }
            Write-Host ("   [{0,2}] {1,-30} {2}  ({3})" -f ($i + 1), (Get-TruncatedSummary ([string]$r['name']) 30), $devs, $hint)
        }
        Write-Host ''
        $c = Read-Host '  Number to clone onto this device, or [B] back'
        if ([string]::IsNullOrWhiteSpace($c) -or $c.Trim().ToUpper() -eq 'B') { return }
        $n = 0
        if (-not [int]::TryParse($c.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $others.Count) { continue }
        $r = $others[$n - 1]
        if (-not ($r.Contains('remote') -and $r['remote'])) {
            Write-Host "  '$($r['name'])' has no git remote, so it can't be cloned. It lives at:" -ForegroundColor Yellow
            foreach ($k in @($r['paths'].Keys)) { Write-Host "    $k  $($r['paths'][$k])" -ForegroundColor DarkGray }
            Read-Host '  Press Enter to continue' | Out-Null
            continue
        }
        $default = Join-Path $ScanRoot ([string]$r['name'] -replace '[\\/:*?"<>|]', '-')
        $target = Read-Host "  Clone into [$default]"
        if ([string]::IsNullOrWhiteSpace($target)) { $target = $default }
        $target = Resolve-UserPath $target.Trim()
        if (Test-Path -LiteralPath $target) {
            $rid = ConvertTo-RemoteId (Get-ProjectGitRemote $target)
            if ($rid -ne [string]$r['id']) {
                Write-Host "  $target already exists and is not this project. Choose another folder." -ForegroundColor Yellow
                Read-Host '  Press Enter to continue' | Out-Null
                continue
            }
            Write-Host '  Already cloned there; adding it.' -ForegroundColor DarkGray
        } else {
            $git = Get-GitExecutable
            Write-Host "  git clone $($r['remote'])" -ForegroundColor DarkGray
            $cl = Invoke-ProcessCapture -FilePath $git -ArgumentList @('clone', [string]$r['remote'], $target) -TimeoutSeconds 1800 -Stream
            if (-not $cl.ok) {
                Write-Host '  Clone failed (credentials or network?). Nothing was added.' -ForegroundColor Red
                Read-Host '  Press Enter to continue' | Out-Null
                continue
            }
        }
        $p = New-ProjectFromRecord $r $target
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($e in @($ConfigRef.Value)) { $list.Add($e) }
        $list.Add($p)
        $ConfigRef.Value = $list.ToArray()
        Save-Config $ConfigRef.Value
        Write-Host "  Added '$($r['name'])' at $target." -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
}

# ---------------------------------------------------------------------------
# Self-update
# ---------------------------------------------------------------------------

function Invoke-SelfUpdate {
    # Fast-forward this checkout to its upstream and restart into the new code. Touches
    # nothing unless: enabled, a git checkout on a branch with an upstream, no tracked
    # changes, and purely behind. Offline or anything unusual = skip (logged).
    if (-not $SelfUpdateEnabled -or $env:MISSION_CENTRE_SELF_UPDATED) { return }
    $git = Get-GitExecutable
    $root = $MissionRootDir
    if (-not $git -or -not (Test-Path (Join-Path $root '.git'))) { return }
    $up = Invoke-ProcessCapture -FilePath $git -ArgumentList @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -WorkingDirectory $root -TimeoutSeconds 10
    if (-not $up.ok) { return }
    $f = Invoke-ProcessCapture -FilePath $git -ArgumentList @('fetch', '--quiet') -WorkingDirectory $root -TimeoutSeconds 15
    if (-not $f.ok) { Write-MissionLog 'INFO' 'self-update: fetch failed (offline?)'; return }
    $counts = Invoke-ProcessCapture -FilePath $git -ArgumentList @('rev-list', '--left-right', '--count', 'HEAD...@{u}') -WorkingDirectory $root -TimeoutSeconds 10
    if (-not $counts.ok -or $counts.out -notmatch '^\s*(\d+)\s+(\d+)\s*$') { return }
    $ahead = [int]$Matches[1]; $behind = [int]$Matches[2]
    if ($behind -eq 0) { return }
    if ($ahead -gt 0) {
        Write-Host "  Mission Centre: $behind update(s) available, but this checkout has local commits - not updating." -ForegroundColor Yellow
        return
    }
    $dirty = Invoke-ProcessCapture -FilePath $git -ArgumentList @('status', '--porcelain', '--untracked-files=no') -WorkingDirectory $root -TimeoutSeconds 10
    if (-not $dirty.ok -or -not [string]::IsNullOrWhiteSpace($dirty.out)) {
        Write-Host "  Mission Centre: $behind update(s) available, but there are uncommitted changes - not updating." -ForegroundColor Yellow
        return
    }
    $m = Invoke-ProcessCapture -FilePath $git -ArgumentList @('merge', '--ff-only', '--quiet', '@{u}') -WorkingDirectory $root -TimeoutSeconds 30
    if (-not $m.ok) { Write-MissionLog 'WARN' 'self-update: fast-forward failed'; return }
    Write-MissionLog 'INFO' "self-update: fast-forwarded $behind commit(s)"
    Write-Host "  Mission Centre updated ($behind new commit(s)) - restarting ..." -ForegroundColor Green
    Start-Sleep -Milliseconds 600
    $env:MISSION_CENTRE_SELF_UPDATED = '1'
    & (Join-Path $root 'Mission-Centre.ps1')
    exit
}
