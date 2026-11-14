# Setup scripts — server, clients, WSL helpers

How `setup-server.ps1` and `client/setup-client.ps1` work, the WSL helpers, and the LAN path.

## Files

| Path | Role |
| --- | --- |
| `setup-server.ps1` | server setup, re-runnable; doubles as a health check |
| `client/setup-client.ps1` | per-user client setup, re-runnable |
| `linux-server-tools/install-docker.sh` | Docker Engine + compose plugin from download.docker.com into Ubuntu (run as root) |
| `linux-server-tools/ch.sh` | SQL from stdin or args against the stack, password read from `.env` |
| `linux-server-tools/backup.sh` | `dump` all `otel.*` tables to `backup/<table>.native`; `restore [table]` appends, skips empty files |
| `client/*.json` | env templates for manual client setup |

## setup-server.ps1

```
1 Docker   auto: docker on PATH answers → desktop; else WSL distro exists → wsl
           wsl: no docker → check PID 1 = systemd → ask (or -Yes) → wsl -u root install-docker.sh
                → wsl --terminate (docker group)
2 .env     created with two random 32-hex passwords (UTF-8 no BOM, LF); existing file kept
3 stack    docker compose up -d; poll views-init until Exited, must be 0
4 checks   GET localhost:3000/api/health; TCP localhost:4317
5 wsl      write <Startup>/cc-telemetry-keepalive.vbs (hidden wsl --exec sleep infinity), start it if not running
6 -EnableLan  not admin → relaunch itself elevated (UAC) with -LanOnly, transcript in %TEMP%\cc-telemetry-lan.log
           firewall rule "OTLP 4317 (Claude Code telemetry)" Private; warn if the LAN profile is Public
           wsl: portproxy <LAN_IP>:4317 → 127.0.0.1:4317, deletes other *:4317 forwards
```
- Params: `-Mode auto|desktop|wsl`, `-Distro` (`Ubuntu`), `-EnableLan`, `-LanIp`, `-Yes`, internal `-LanOnly`.
- LAN IP = IPv4 of the up adapter with a default gateway and the lowest interface metric.
- Compose in wsl mode: `wsl -d <distro> --cd <repo> -- docker compose …`.
- WSL stops a distro ~15 s after the last Windows-started process exits — hence the keepalive.
- WSL2 on Windows 10 has no mirrored networking: the port is on `localhost` only, hence portproxy.
- Desktop mode is untested (pending-bugs.md).

## setup-client.ps1

- `-ServerIp` (required), `-PcName` (default `$env:COMPUTERNAME`, `[A-Za-z0-9._-]+`), `-Project`
  folders, `-SettingsDir` (`.claude`), `-UserSettings` (test override), `-WhatIf`.
- Merges into `env` of `%USERPROFILE%\.claude\settings.json` (9 keys, `project=unknown`) and of
  `<project>\<SettingsDir>\settings.local.json` (`project=<folder lower-case>,host=<PcName>`).
- Keeps every other key; `<file>.bak` once before the first change; writes UTF-8 without BOM;
  re-parses the result; finally TCP-tests `<ServerIp>:4317`.
- Windows PowerShell 5.1 re-indents the JSON (content unchanged). Per-user only: no HKLM, no
  machine env, no admin.
- A project whose `.claude` is a junction to another folder needs no `-SettingsDir`: the write
  goes through the junction.

## Client reachability

```
client ──TCP 4317──► server LAN IP ── firewall (Private profile) ── [wsl: portproxy] ── 127.0.0.1:4317 ── wslrelay ── collector
```
- Public network profile → rule does not apply → connection refused; the fix is the user's (mark
  the network Private) — never change it yourself.
- Corporate VPN clients usually cannot be reached from the corporate side (gateway policy): not
  fixable here, never suggest a workaround.
