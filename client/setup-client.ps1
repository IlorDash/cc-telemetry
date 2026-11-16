<#
.SYNOPSIS
  Connects this PC's Claude Code to the cc-telemetry server.

.DESCRIPTION
  Merges the telemetry keys into the "env" section of the user settings
  (%USERPROFILE%\.claude\settings.json) and, for every -Project folder, of
  <project>\.claude\settings.local.json. Other keys are left untouched;
  each file is backed up to <file>.bak before the first change.
  Works on stock Windows PowerShell 5.1, no Node/Python needed.

  Also installs a small hook (UserPromptSubmit, async) that sends each session's title, git
  branch and working directory to the server (OTLP/JSON, port 4318). The hook script is written
  to <settings folder>\cc-telemetry\session-meta.ps1 and registered under "hooks" of the user
  settings; other hooks are kept. -NoSessionMeta skips it (and removes it on a re-run).
  -ImportHistory sends the sessions already on this PC once (read from <settings folder>\projects;
  only title, branch and folder are read, never the prompts).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp 192.168.1.10 -Project C:\Projects\ProjA, C:\Projects\ProjB

.EXAMPLE
  # Custom PC name; project settings kept in a folder other than .claude:
  ... -ServerIp 192.168.1.10 -PcName pc-office -Project C:\Projects\ProjA -SettingsDir my-claude-dir
#>
param(
  [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ServerIp,
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$PcName = $env:COMPUTERNAME,
  [string[]]$Project = @(),
  [string]$SettingsDir = '.claude',
  [string]$UserSettings = (Join-Path $env:USERPROFILE '.claude\settings.json'),
  [switch]$NoSessionMeta,
  [switch]$ImportHistory,
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$hookMarker = 'cc-telemetry/session-meta'

function Set-Prop($o, [string]$Name, $Value) {
  if ($o.PSObject.Properties[$Name]) { $o.$Name = $Value }
  else { $o | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# Registers (or, with -Remove, deletes) our UserPromptSubmit hook in settings object $obj.
# Our entry is the one whose command contains $hookMarker; it is updated in place, never duplicated.
function Update-Hook($obj, [string]$Command, [bool]$Remove) {
  $ev = 'UserPromptSubmit'
  if ($obj.PSObject.Properties['hooks']) {
    if ($obj.hooks -isnot [System.Management.Automation.PSCustomObject]) { throw '"hooks" is not an object' }
  } elseif ($Remove) { return }
  else { $obj | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object psobject) }
  $hooks = $obj.hooks
  $groups = @()
  if ($hooks.PSObject.Properties[$ev]) {
    if ($hooks.$ev -isnot [object[]]) { throw "hooks.$ev is not an array" }
    $groups = @($hooks.$ev)
  }
  $found = $false
  $newGroups = @()
  foreach ($g in $groups) {
    if (($g -is [System.Management.Automation.PSCustomObject]) -and $g.PSObject.Properties['hooks'] -and ($g.hooks -is [object[]])) {
      $inner = @()
      $touched = $false
      foreach ($h in $g.hooks) {
        $isOurs = ($h -is [System.Management.Automation.PSCustomObject]) -and ($h.command -is [string]) -and
                  ($h.command.Replace('\', '/').Contains($hookMarker))
        if (-not $isOurs) { $inner += $h; continue }
        $touched = $true
        if ($Remove -or $found) { continue }
        $found = $true
        Set-Prop $h 'type' 'command'
        Set-Prop $h 'command' $Command
        Set-Prop $h 'async' $true
        if (-not $h.PSObject.Properties['timeout']) { Set-Prop $h 'timeout' 60 }
        $inner += $h
      }
      if ($touched -and $inner.Count -eq 0) { continue }
      if ($touched) { $g.hooks = @($inner) }
    }
    $newGroups += $g
  }
  if (-not $Remove -and -not $found) {
    $entry = [pscustomobject]@{ type = 'command'; command = $Command; async = $true; timeout = 60 }
    $newGroups += [pscustomobject]@{ hooks = @($entry) }
  }
  if ($newGroups.Count -gt 0) { Set-Prop $hooks $ev @($newGroups) }
  else {
    if ($hooks.PSObject.Properties[$ev]) { $hooks.PSObject.Properties.Remove($ev) }
    if (@($hooks.PSObject.Properties).Count -eq 0) { $obj.PSObject.Properties.Remove('hooks') }
  }
}

function Merge-Env([string]$Path, [System.Collections.IDictionary]$Add, [string]$HookCommand = '', [bool]$HookRemove = $false) {
  $dir = Split-Path $Path -Parent
  if (Test-Path $Path) {
    $text = [IO.File]::ReadAllText($Path)
    $obj = if ($text.Trim()) { $text | ConvertFrom-Json } else { New-Object psobject }
  } else {
    $obj = New-Object psobject
  }
  if (-not $obj.PSObject.Properties['env']) { $obj | Add-Member -NotePropertyName env -NotePropertyValue (New-Object psobject) }
  foreach ($k in $Add.Keys) {
    if ($obj.env.PSObject.Properties[$k]) { $obj.env.$k = $Add[$k] }
    else { $obj.env | Add-Member -NotePropertyName $k -NotePropertyValue $Add[$k] }
  }
  if ($HookCommand -or $HookRemove) { Update-Hook $obj $HookCommand $HookRemove }
  $json = $obj | ConvertTo-Json -Depth 50
  if ($WhatIf) { Write-Host "--- $Path (not written)"; Write-Host $json; return }
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  if ((Test-Path $Path) -and -not (Test-Path "$Path.bak")) { Copy-Item $Path "$Path.bak" }
  [IO.File]::WriteAllText($Path, $json + "`n", $utf8NoBom)
  # Re-read to make sure the file is still valid JSON.
  [IO.File]::ReadAllText($Path) | ConvertFrom-Json | Out-Null
  Write-Host "updated $Path"
}

$userEnv = [ordered]@{
  CLAUDE_CODE_ENABLE_TELEMETRY = '1'
  OTEL_LOGS_EXPORTER           = 'otlp'
  OTEL_METRICS_EXPORTER        = 'otlp'
  OTEL_EXPORTER_OTLP_PROTOCOL  = 'grpc'
  OTEL_EXPORTER_OTLP_ENDPOINT  = "http://${ServerIp}:4317"
  OTEL_LOG_TOOL_DETAILS        = '1'
  OTEL_LOG_USER_PROMPTS        = '1'
  OTEL_LOGS_EXPORT_INTERVAL    = '2000'
  OTEL_RESOURCE_ATTRIBUTES     = "project=unknown,host=$PcName"
}

# --- session-meta hook ---------------------------------------------------------------------------
# The hook script lives next to the user settings (<settings folder>\cc-telemetry\). It is rewritten on
# every run, so a re-run also updates it. Keep it ASCII (5.1) and never let it print or fail.
$hookScript = @'
# cc-telemetry session-meta hook. Written by setup-client.ps1 - edits are overwritten on the next run.
# Sends session title, git branch and working directory (never prompts or answers) to the server.
param(
  [string]$Server,
  [string]$PcName,
  [string]$ProjectsRoot,
  [switch]$ImportHistory
)
$ErrorActionPreference = 'SilentlyContinue'
$import = $ImportHistory.IsPresent
if ($Server -eq 'localhost') { $Server = '127.0.0.1' }
$stateFile = Join-Path $PSScriptRoot 'session-meta.state.json'
$stateKey = "$Server|$PcName"
$epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
$counts = @{ found = 0; sent = 0; unchanged = 0; failed = 0 }

# Raw (still JSON-escaped) value of "key":"..." in a line, or $null.
function Get-Raw([string]$line, [string]$key) {
  $i = $line.IndexOf($key, [StringComparison]::Ordinal)
  if ($i -lt 0) { return $null }
  $s = $i + $key.Length
  $j = $s
  while ($true) {
    $j = $line.IndexOf('"', $j)
    if ($j -lt 0) { return $null }
    $b = 0
    $k = $j - 1
    while ($k -ge $s -and $line[$k] -eq '\') { $b++; $k-- }
    if (($b % 2) -eq 0) { break }
    $j++
  }
  return $line.Substring($s, $j - $s)
}

function Convert-Raw($raw) {
  if (-not $raw) { return '' }
  if (-not $raw.Contains('\')) { return $raw }
  $o = ('{"v":"' + $raw + '"}') | ConvertFrom-Json
  return [string]$o.v
}

# title / title source / branch / first cwd / version of one session file; only a few line kinds are looked at.
function Get-Meta([string]$path) {
  $ct = $null; $at = $null; $b = $null; $c = $null; $v = $null
  $fs = $null; $sr = $null
  try {
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    while ($null -ne ($line = $sr.ReadLine())) {
      if ($line.Contains('"gitBranch":"')) {
        $r = Get-Raw $line '"gitBranch":"'
        if ($r) { $b = $r }
        $r = Get-Raw $line '"version":"'
        if ($r -and $r -match '^\d+(\.\d+)+$') { $v = $r }
      }
      if (-not $c -and $line.Contains('"cwd":"')) {
        $r = Get-Raw $line '"cwd":"'
        if ($r) { $c = $r }
      }
      if ($line.Contains('"custom-title"')) {
        if ($line.Contains('"type":"custom-title"')) {
          $r = Get-Raw $line '"customTitle":"'
          if ($r) { $ct = $r }
        }
      } elseif ($line.Contains('"ai-title"')) {
        if ($line.Contains('"type":"ai-title"')) {
          $r = Get-Raw $line '"aiTitle":"'
          if ($r) { $at = $r }
        }
      }
    }
  } finally {
    if ($sr) { $sr.Dispose() }
    if ($fs) { $fs.Dispose() }
  }
  $title = ''; $src = ''
  if ($ct) { $title = Convert-Raw $ct; $src = 'custom' }
  elseif ($at) { $title = Convert-Raw $at; $src = 'ai' }
  return @{ title = $title; src = $src; branch = (Convert-Raw $b); cwd = (Convert-Raw $c); version = (Convert-Raw $v) }
}

function Get-Hash([string]$text) {
  $sha = [Security.Cryptography.SHA1]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '').ToLower()
}

function Read-State {
  $st = @{ scan = [long]0; fail = [long]0; s = @{} }
  try {
    $o = [IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
    if ($o.key -eq $stateKey) {
      $st.scan = [long]$o.scan
      $st.fail = [long]$o.fail
      foreach ($p in $o.s.PSObject.Properties) { $st.s[$p.Name] = [string]$p.Value }
    }
  } catch { }
  return $st
}

# Merge into the file as it is now (other sessions may have written meanwhile), then replace it atomically.
function Save-State($updates, [long]$scan, [long]$fail) {
  $st = Read-State
  foreach ($k in $updates.Keys) { $st.s[$k] = $updates[$k] }
  if ($scan -gt 0) { $st.scan = $scan }
  $json = @{ key = $stateKey; scan = $st.scan; fail = $fail; s = $st.s } | ConvertTo-Json -Compress -Depth 5
  $tmp = "$stateFile.$PID.tmp"
  try {
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $stateFile) { [IO.File]::Replace($tmp, $stateFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $stateFile) }
  } catch { }
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
}

function New-Attr([string]$k, [string]$v) { return @{ key = $k; value = @{ stringValue = $v } } }

function Send-Batch($items) {
  $now = [long]([DateTime]::UtcNow - $epoch).TotalMilliseconds
  $recs = New-Object System.Collections.ArrayList
  foreach ($it in $items) {
    $m = $it.meta
    $attrs = New-Object System.Collections.ArrayList
    [void]$attrs.Add((New-Attr 'event.name' 'session_meta'))
    [void]$attrs.Add((New-Attr 'session.id' $it.sid))
    [void]$attrs.Add((New-Attr 'title' $m.title))
    [void]$attrs.Add((New-Attr 'title_source' $m.src))
    [void]$attrs.Add((New-Attr 'git_branch' $m.branch))
    [void]$attrs.Add((New-Attr 'cwd' $m.cwd))
    if ($m.version) { [void]$attrs.Add((New-Attr 'cc_version' $m.version)) }
    [void]$recs.Add(@{ timeUnixNano = "${now}000000"; body = @{ stringValue = 'session_meta' }; attributes = $attrs })
  }
  $payload = @{ resourceLogs = @(@{
    resource = @{ attributes = @((New-Attr 'service.name' 'cc-session-meta'), (New-Attr 'host' $PcName)) }
    scopeLogs = @(@{ scope = @{ name = 'cc-session-meta' }; logRecords = $recs })
  }) } | ConvertTo-Json -Compress -Depth 10
  try {
    $req = [Net.HttpWebRequest]::Create("http://${Server}:4318/v1/logs")
    $req.Method = 'POST'
    $req.ContentType = 'application/json'
    $req.Timeout = 5000
    $req.ReadWriteTimeout = 5000
    $req.KeepAlive = $false
    $req.Proxy = $null
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $req.ContentLength = $bytes.Length
    $rs = $req.GetRequestStream()
    $rs.Write($bytes, 0, $bytes.Length)
    $rs.Close()
    $resp = $req.GetResponse()
    $ok = ([int]$resp.StatusCode -eq 200)
    $resp.Close()
    return $ok
  } catch { return $false }
}

function Invoke-Main {
  $startSec = [long]([DateTime]::UtcNow - $epoch).TotalSeconds
  $current = $null
  $root = $ProjectsRoot
  if (-not $import) {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
    $inp = $reader.ReadToEnd() | ConvertFrom-Json
    $current = [string]$inp.transcript_path
    if (-not $current) { return }
    $root = Split-Path (Split-Path $current -Parent) -Parent
  }
  if (-not $root -or -not $Server -or -not $PcName) { return }
  $state = Read-State
  # Back-off: after a failed send (server down) hook runs do nothing for 10 minutes - no 5 s wait on every
  # prompt, no re-parsing. Afterwards the next run retries; the unchanged scan time re-includes the files.
  if (-not $import -and $state.fail -gt 0 -and ($startSec - $state.fail) -ge 0 -and ($startSec - $state.fail) -lt 600) { return }
  # Files changed since the last scan (a margin covers writes that raced with it); no scan yet = only this session.
  $since = $null
  if ($state.scan -gt 0) { $since = $epoch.AddSeconds($state.scan - 120) }
  $files = New-Object System.Collections.ArrayList
  $seen = @{}
  if ($current -and (Test-Path -LiteralPath $current)) {
    [void]$files.Add((New-Object IO.FileInfo $current)); $seen[$current] = $true
  }
  if (Test-Path -LiteralPath $root) {
    foreach ($d in [IO.Directory]::GetDirectories($root)) {
      foreach ($f in (New-Object IO.DirectoryInfo $d).GetFiles('*.jsonl')) {
        if ($seen[$f.FullName] -or -not $f.Name.EndsWith('.jsonl') -or $f.Name.StartsWith('agent-')) { continue }
        if ($import -or ($since -and $f.LastWriteTimeUtc -ge $since)) { [void]$files.Add($f); $seen[$f.FullName] = $true }
      }
    }
  }
  $pending = New-Object System.Collections.ArrayList
  foreach ($f in $files) {
    $counts.found++
    try {
      $sid = [IO.Path]::GetFileNameWithoutExtension($f.Name)
      $m = Get-Meta $f.FullName
      $sig = Get-Hash (($m.src, $m.title, $m.branch, $m.cwd) -join "`t")
      if ((-not $m.title -and -not $m.branch -and -not $m.cwd) -or $state.s[$sid] -eq $sig) { $counts.unchanged++; continue }
      [void]$pending.Add(@{ sid = $sid; sig = $sig; meta = $m })
    } catch { $counts.failed++ }
  }
  $updates = @{}
  $down = $false
  for ($i = 0; $i -lt $pending.Count; $i += 100) {
    $chunk = @($pending[$i..([Math]::Min($i + 99, $pending.Count - 1))])
    if (-not $down -and (Send-Batch $chunk)) {
      $counts.sent += $chunk.Count
      foreach ($it in $chunk) { $updates[$it.sid] = $it.sig }
    } else {
      $down = $true
      $counts.failed += $chunk.Count
    }
  }
  # A failed send keeps the old scan time so the next run looks at those files again.
  $scan = 0
  if ($counts.failed -eq 0) { $scan = $startSec }
  $fail = 0
  if ($counts.failed -gt 0 -and $down) { $fail = $startSec }
  Save-State $updates $scan $fail
}

try { $null = Invoke-Main } catch { $counts.failed++ }
if ($import) { Write-Output ("found {0}, sent {1}, unchanged {2}, failed {3}" -f $counts.found, $counts.sent, $counts.unchanged, $counts.failed) }
exit 0
'@

$cfgDir = Split-Path ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($UserSettings)) -Parent
$metaScript = Join-Path (Join-Path $cfgDir 'cc-telemetry') 'session-meta.ps1'
$hookServer = if ($ServerIp -eq 'localhost') { '127.0.0.1' } else { $ServerIp }
# Forward slashes: valid for PowerShell and cmd, and safe if Claude Code runs the command through Git Bash.
$hookCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $metaScript.Replace('\', '/') + '" -Server ' + $hookServer + ' -PcName ' + $PcName
if ($NoSessionMeta -and $ImportHistory) { throw '-ImportHistory cannot be combined with -NoSessionMeta' }

$hookArg = if ($NoSessionMeta) { '' } else { $hookCommand }
$metaDir = Split-Path $metaScript -Parent
# The script file comes before the settings entry that points to it.
if (-not $NoSessionMeta) {
  if ($WhatIf) { Write-Host "--- $metaScript (not written)" }
  else {
    New-Item -ItemType Directory -Path $metaDir -Force | Out-Null
    [IO.File]::WriteAllText($metaScript, ($hookScript -replace "`r?`n", "`r`n"), $utf8NoBom)
    Write-Host "updated $metaScript"
  }
}
Merge-Env $UserSettings $userEnv $hookArg ([bool]$NoSessionMeta)
if ($NoSessionMeta) {
  # Remove only our own files, then the folder if nothing else is in it.
  $ours = @($metaScript, (Join-Path $metaDir 'session-meta.state.json'))
  if (Test-Path -LiteralPath $metaDir) { $ours += @(Get-ChildItem -LiteralPath $metaDir -Filter 'session-meta.state.json.*.tmp' -File | ForEach-Object { $_.FullName }) }
  foreach ($f in $ours) {
    if (Test-Path -LiteralPath $f) {
      if ($WhatIf) { Write-Host "would delete $f" } else { Remove-Item -LiteralPath $f -Force; Write-Host "deleted $f" }
    }
  }
  if (-not $WhatIf -and (Test-Path -LiteralPath $metaDir) -and -not @(Get-ChildItem -LiteralPath $metaDir -Force).Count) { Remove-Item -LiteralPath $metaDir -Force }
}

foreach ($p in $Project) {
  $full = (Resolve-Path $p).Path
  $name = (Split-Path $full -Leaf).ToLower()
  Merge-Env (Join-Path $full "$SettingsDir\settings.local.json") @{ OTEL_RESOURCE_ATTRIBUTES = "project=$name,host=$PcName" }
}

$tcp = Test-NetConnection $ServerIp -Port 4317 -WarningAction SilentlyContinue
Write-Host ("server {0}:4317 reachable: {1}" -f $ServerIp, $tcp.TcpTestSucceeded)
if (-not $NoSessionMeta) {
  $tcp2 = Test-NetConnection $hookServer -Port 4318 -WarningAction SilentlyContinue
  Write-Host ("server {0}:4318 (session titles) reachable: {1}" -f $hookServer, $tcp2.TcpTestSucceeded)
  if (-not $tcp2.TcpTestSucceeded) { Write-Host 'Session titles are sent only once port 4318 is reachable (update and re-run the server setup).' }
}
if ($ImportHistory) {
  $histRoot = Join-Path $cfgDir 'projects'
  if ($WhatIf) { Write-Host "import of $histRoot skipped (-WhatIf)" }
  else {
    Write-Host "importing session titles from $histRoot ..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $metaScript -Server $hookServer -PcName $PcName -ImportHistory -ProjectsRoot $histRoot
    if ($LASTEXITCODE -ne 0) { Write-Host "import failed (exit code $LASTEXITCODE)" }
  }
}
Write-Host 'Restart Claude Code sessions (VS Code: reload the window; CLI: claude -c) to start sending telemetry.'
