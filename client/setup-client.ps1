<#
.SYNOPSIS
  Connects this PC's Claude Code to the cc-telemetry server.

.DESCRIPTION
  Merges the telemetry keys into the "env" section of the user settings
  (%USERPROFILE%\.claude\settings.json) and, for every -Project folder, of
  <project>\.claude\settings.local.json. Other keys are left untouched;
  each file is backed up to <file>.bak before the first change.
  Works on stock Windows PowerShell 5.1, no Node/Python needed.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp 192.168.1.10 -Project C:\Projects\ProjA, C:\Projects\ProjB

.EXAMPLE
  # Custom PC name; project settings kept in a folder other than .claude:
  ... -ServerIp 192.168.1.10 -PcName pc-office -Project C:\Projects\ProjA -SettingsDir my-claude-dir
#>
param(
  [Parameter(Mandatory = $true)][string]$ServerIp,
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$PcName = $env:COMPUTERNAME,
  [string[]]$Project = @(),
  [string]$SettingsDir = '.claude',
  [string]$UserSettings = (Join-Path $env:USERPROFILE '.claude\settings.json'),
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Merge-Env([string]$Path, [System.Collections.IDictionary]$Add) {
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
Merge-Env $UserSettings $userEnv

foreach ($p in $Project) {
  $full = (Resolve-Path $p).Path
  $name = (Split-Path $full -Leaf).ToLower()
  Merge-Env (Join-Path $full "$SettingsDir\settings.local.json") @{ OTEL_RESOURCE_ATTRIBUTES = "project=$name,host=$PcName" }
}

$tcp = Test-NetConnection $ServerIp -Port 4317 -WarningAction SilentlyContinue
Write-Host ("server {0}:4317 reachable: {1}" -f $ServerIp, $tcp.TcpTestSucceeded)
Write-Host 'Restart Claude Code sessions (VS Code: reload the window; CLI: claude -c) to start sending telemetry.'
