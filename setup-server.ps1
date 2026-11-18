<#
.SYNOPSIS
  Sets up the cc-telemetry server on this PC.

.DESCRIPTION
  1. Finds Docker: Docker Desktop, or Docker Engine inside WSL2 (installs it there if missing).
  2. Creates .env with random passwords (an existing .env is kept).
  3. Starts the stack and waits until the cc.* views are created.
  4. Checks Grafana (:3000) and the OTLP ports (:4317 gRPC, :4318 HTTP).
  5. WSL only: keeps WSL running and adds that to autostart (Startup folder, no admin rights).
  6. With -EnableLan: firewall rules for 4317 and 4318 and, for WSL, port forwards from the LAN address.
     This step needs admin rights; the script asks for them through UAC.
  Safe to re-run: every step checks what is already done.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-server.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-server.ps1 -EnableLan
#>
param(
  [ValidateSet('auto', 'desktop', 'wsl')][string]$Mode = 'auto',
  [string]$Distro = 'Ubuntu',
  [switch]$EnableLan,
  [string]$LanIp,
  [switch]$Yes,      # do not ask before installing Docker into WSL
  [switch]$LanOnly   # internal: the elevated pass started by -EnableLan
)
# Not 'Stop': in Windows PowerShell 5.1 any stderr line of a native program (apt warnings, "docker: not found" in a probe)
# would then abort the script. Native results are checked through $LASTEXITCODE; cmdlets that matter use -ErrorAction Stop.
$ErrorActionPreference = 'Continue'
$env:WSL_UTF8 = '1'
$root = $PSScriptRoot
Set-Location $root

$otlpPorts = @(4317, 4318)   # OTLP gRPC (Claude Code) and OTLP HTTP (session-meta hook)

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "   WARN $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "   FAIL $m" -ForegroundColor Red; exit 1 }

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Port([string]$HostName, [int]$Port) {
  $c = New-Object Net.Sockets.TcpClient
  try { return $c.ConnectAsync($HostName, $Port).Wait(2000) -and $c.Connected } catch { return $false } finally { $c.Dispose() }
}

function Get-LanIp {
  if ($LanIp) { return $LanIp }
  $best = Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
    Sort-Object { (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).InterfaceMetric } |
    Select-Object -First 1
  if ($best) { return $best.IPv4Address[0].IPAddress }
  return $null
}

function Test-DesktopDocker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
  docker info --format '{{.ServerVersion}}' *> $null
  return ($LASTEXITCODE -eq 0)
}

function Test-DistroExists {
  $names = (wsl.exe -l -q 2>$null) | ForEach-Object { ($_ -replace "`0", '').Trim() }
  return ($names -contains $Distro)
}

function Test-WslDocker {
  wsl.exe -d $Distro -- docker info --format '{{.ServerVersion}}' *> $null
  return ($LASTEXITCODE -eq 0)
}

function Compose {
  if ($script:Mode -eq 'wsl') { & wsl.exe -d $Distro --cd $root -- docker compose @args }
  else { & docker compose @args }
  if ($LASTEXITCODE -ne 0) { Fail "docker compose $args failed (exit $LASTEXITCODE)" }
}

function Enable-Lan {
  Step 'LAN access (admin)'
  $ip = Get-LanIp
  if (-not $ip) { Fail 'Could not find the LAN address. Re-run with -LanIp <address>.' }
  Ok "LAN address: $ip"

  # 4317 = OTLP gRPC, 4318 = OTLP HTTP (session-meta hook). One rule per port; a server set up before 4318
  # existed only has the first one, a re-run adds the missing one.
  foreach ($port in $otlpPorts) {
    $ruleName = "OTLP $port (Claude Code telemetry)"
    if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) { Ok "firewall rule for $port already exists" }
    else {
      New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Private -ErrorAction Stop | Out-Null
      Ok "firewall rule for $port created (Private networks)"
    }
  }

  $alias = (Get-NetIPAddress -IPAddress $ip -ErrorAction SilentlyContinue).InterfaceAlias
  $netProfile = if ($alias) { (Get-NetConnectionProfile -InterfaceAlias $alias -ErrorAction SilentlyContinue).NetworkCategory } else { $null }
  if ($netProfile -eq 'Public') {
    Warn "network '$alias' is Public, the firewall rule does not apply to it. If this is your home/office network, run as admin:"
    Warn "  Set-NetConnectionProfile -InterfaceAlias '$alias' -NetworkCategory Private"
  } else { Ok "network '$alias' profile: $netProfile" }

  if ($script:Mode -eq 'wsl') {
    foreach ($port in $otlpPorts) {
      $existing = @(netsh interface portproxy show v4tov4 | Select-String "^\s*(\S+)\s+$port\s" | ForEach-Object { $_.Matches[0].Groups[1].Value })
      foreach ($old in $existing) {
        if ($old -ne $ip) { netsh interface portproxy delete v4tov4 listenaddress=$old listenport=$port | Out-Null; Ok "removed old port forward ${old}:$port" }
      }
      if ($existing -contains $ip) { Ok "port forward ${ip}:$port -> 127.0.0.1:$port already exists" }
      else {
        netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$port connectaddress=127.0.0.1 connectport=$port | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "netsh portproxy add failed (exit $LASTEXITCODE)" }
        Ok "port forward ${ip}:$port -> 127.0.0.1:$port added"
      }
    }
  }
  foreach ($port in $otlpPorts) {
    if (Test-Port $ip $port) { Ok "${ip}:$port is reachable" } else { Warn "${ip}:$port is not reachable yet" }
  }
}

# ---------------------------------------------------------------- elevated pass
if ($LanOnly) {
  Start-Transcript -Path (Join-Path $env:TEMP 'cc-telemetry-lan.log') -Force | Out-Null
  try { Enable-Lan } finally { Stop-Transcript | Out-Null }
  exit 0
}

# ---------------------------------------------------------------- 1. Docker
Step 'Docker'
if ($Mode -eq 'auto') {
  if (Test-DesktopDocker) { $Mode = 'desktop' }
  elseif (Test-DistroExists) { $Mode = 'wsl' }
  else {
    Fail ("No Docker found. Install Docker Desktop (Windows 10 22H2+ / Windows 11), or on older Windows install WSL2 " +
          "with Ubuntu (admin: wsl --install -d Ubuntu), reboot, and run this script again.")
  }
}
if ($Mode -eq 'desktop') {
  if (-not (Test-DesktopDocker)) { Fail 'Docker Desktop is not running. Start it and run this script again.' }
  Ok ("Docker Desktop, engine " + (docker info --format '{{.ServerVersion}}'))
} else {
  if (-not (Test-DistroExists)) { Fail "WSL distro '$Distro' not found (wsl -l -v). Use -Distro <name>." }
  if (-not (Test-WslDocker)) {
    $pid1 = (wsl.exe -d $Distro -- ps -p 1 -o comm= | Out-String).Trim()
    if ($pid1 -ne 'systemd') {
      Fail ("systemd is off in WSL '$Distro'. Add to /etc/wsl.conf:  [boot]  systemd=true  " +
            "then run 'wsl --terminate $Distro' and this script again.")
    }
    if (-not $Yes) {
      $answer = Read-Host "Docker is not installed in WSL '$Distro'. Install Docker Engine there now? [Y/n]"
      if ($answer -match '^[Nn]') { Fail 'Docker is required.' }
    }
    $linuxUser = (wsl.exe -d $Distro -- whoami | Out-String).Trim()
    & wsl.exe -d $Distro -u root --cd $root -- bash linux-server-tools/install-docker.sh $linuxUser
    if ($LASTEXITCODE -ne 0) { Fail 'Docker installation in WSL failed, see the output above.' }
    wsl.exe --terminate $Distro | Out-Null   # applies the docker group
    if (-not (Test-WslDocker)) { Fail 'Docker was installed but does not answer. Run: wsl -d <distro> -- docker info' }
  }
  Ok ("Docker Engine in WSL '$Distro', version " + (wsl.exe -d $Distro -- docker info --format '{{.ServerVersion}}' | Out-String).Trim())
}

# ---------------------------------------------------------------- 2. .env
Step '.env'
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) { Ok '.env exists, kept as is' }
else {
  function New-Secret { $b = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $_.ToString('x2') }) }
  $text = "CLICKHOUSE_PASSWORD=$(New-Secret)`nGRAFANA_ADMIN_PASSWORD=$(New-Secret)`n"
  [IO.File]::WriteAllText($envFile, $text, (New-Object Text.UTF8Encoding($false)))
  Ok '.env created with random passwords (Grafana login: admin / GRAFANA_ADMIN_PASSWORD from .env)'
}

# ---------------------------------------------------------------- 3. stack
Step 'Stack'
# Not through Compose: it fails at once, and a failed views-init (cc-refresh waits for it) must show its log first.
if ($script:Mode -eq 'wsl') { & wsl.exe -d $Distro --cd $root -- docker compose up -d } else { & docker compose up -d }
if ($LASTEXITCODE -ne 0) {
  Compose logs --tail 50 views-init
  Fail 'docker compose up failed (cc-refresh waits for views-init: its log is above), see the output above.'
}
$state = $null
for ($i = 0; $i -lt 90; $i++) {
  $state = (Compose ps -a views-init --format '{{.State}} {{.ExitCode}}' | Out-String).Trim()
  if ($state -like 'exited*') { break }
  Start-Sleep 2
}
if ($state -eq 'exited 0') { Ok 'cc.* views are ready' }
else { Compose logs views-init; Fail "views-init did not finish cleanly ($state)" }

# ---------------------------------------------------------------- 4. checks
Step 'Checks'
$grafanaOk = $false
for ($i = 0; $i -lt 45 -and -not $grafanaOk; $i++) {
  try { $grafanaOk = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:3000/api/health).StatusCode -eq 200 } catch { Start-Sleep 2 }
}
if ($grafanaOk) { Ok 'Grafana: http://localhost:3000' } else { Warn 'Grafana does not answer yet; check: docker compose logs grafana' }
foreach ($port in $otlpPorts) {
  if (Test-Port 'localhost' $port) { Ok "OTLP: localhost:$port" } else { Warn "localhost:$port is closed; check: docker compose logs otel-collector" }
}

# ---------------------------------------------------------------- 5. WSL autostart
if ($Mode -eq 'wsl') {
  Step 'Keep WSL running'
  $vbs = @"
' cc-telemetry: keeps WSL '$Distro' (and Docker inside it) running. Created by setup-server.ps1.
CreateObject("WScript.Shell").Run "wsl.exe -d $Distro --exec /bin/sleep infinity", 0, False
"@
  $startupFile = Join-Path ([Environment]::GetFolderPath('Startup')) 'cc-telemetry-keepalive.vbs'
  [IO.File]::WriteAllText($startupFile, $vbs, [Text.Encoding]::ASCII)
  Ok "autostart: $startupFile"
  $running = Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" | Where-Object { $_.CommandLine -like '*sleep infinity*' }
  if ($running) { Ok 'keepalive already running' } else { Start-Process wscript.exe -ArgumentList "`"$startupFile`""; Ok 'keepalive started' }
}

# ---------------------------------------------------------------- 6. LAN
if ($EnableLan) {
  if (Test-Admin) { Enable-Lan }
  else {
    Step 'LAN access: asking for admin rights (UAC)'
    $log = Join-Path $env:TEMP 'cc-telemetry-lan.log'
    Remove-Item $log -ErrorAction SilentlyContinue
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -LanOnly -Mode $Mode -Distro $Distro"
    if ($LanIp) { $argList += " -LanIp $LanIp" }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait -WindowStyle Hidden -ErrorAction Stop }
    catch { Fail 'admin rights were not granted; LAN access is not configured' }
    if (Test-Path $log) { Get-Content $log | Where-Object { $_ -match '^(==|   )' } | ForEach-Object { Write-Host $_ } }
  }
}

# ---------------------------------------------------------------- summary
$ip = Get-LanIp
Step 'Done'
Write-Host "   Grafana:  http://localhost:3000   (admin / password in .env)"
Write-Host "   This PC as a client:"
Write-Host "     powershell -ExecutionPolicy Bypass -File .\client\setup-client.ps1 -ServerIp localhost -Project <project folder>"
if ($ip) {
  Write-Host "   Other PCs (after -EnableLan):"
  Write-Host "     powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 -ServerIp $ip -Project <project folder>"
}
