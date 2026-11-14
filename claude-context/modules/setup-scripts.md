# Setup scripts — server, clients, Linux helpers

How `setup-server.ps1` / `setup-server.sh` and the client scripts work, the Linux helpers, the
update flow and the LAN path.

## Files

| Path | Role |
| --- | --- |
| `setup-server.ps1` | Windows server setup (Docker Desktop or WSL2), re-runnable; doubles as a health check |
| `setup-server.sh` | Linux server setup, re-runnable; `--update` updates a running server |
| `client/setup-client.ps1` | per-user client setup on Windows, re-runnable |
| `client/setup-client.sh` | per-user client setup on Linux (python3, or jq ≥ 1.6), re-runnable |
| `linux-server-tools/install-docker.sh` | Docker Engine + compose plugin from download.docker.com on Ubuntu/Debian and derivatives (`ID`/`ID_LIKE`; a derivative's codename is checked against download.docker.com first); enables the service, adds the user to `docker`; run as root |
| `linux-server-tools/ch.sh` | SQL from stdin or args against the stack, password read from `.env` |
| `linux-server-tools/backup.sh` | `dump` all `otel.*` tables to `$BACKUP_DIR/<table>.native` (default `backup/`; fails if `SHOW TABLES` fails); `restore [table]` appends, skips empty files and missing tables |
| `client/*.json` | env templates for manual client setup |

## setup-server.ps1 (Windows)

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
- Writes no bind/port keys: compose defaults apply (4317 on `0.0.0.0`, Grafana `127.0.0.1:3000`);
  the checks assume Grafana on `localhost:3000`.
- LAN IP = IPv4 of the up adapter with a default gateway and the lowest interface metric.
- Compose in wsl mode: `wsl -d <distro> --cd <repo> -- docker compose …`.
- WSL stops a distro ~15 s after the last Windows-started process exits — hence the keepalive.
- WSL2 on Windows 10 has no mirrored networking: the port is on `localhost` only, hence portproxy.
- Desktop mode is untested (pending-bugs.md).

## setup-server.sh (Linux)

```
args       --local-only | --lan (= --enable-lan), --lan-ip <IPv4>, --grafana-port <1-65535>,
           --clickhouse-version <tag>, --update, --yes/-y, --help
1 Docker   docker info ok → docker; "permission denied" → sudo docker for this run (warn: docker group)
           daemon down → fail; docker/compose missing on Ubuntu/Debian(-like) → ask → sudo install-docker.sh
           other distro → fail with the docs link
  --update → run_update (below), ends in exec
2 .env     missing → created (umask 077, two random 32-hex); then only the managed keys:
           OTLP_BIND          flag (lan 0.0.0.0 / local 127.0.0.1) > kept > 0.0.0.0
           GRAFANA_BIND       flag > kept > OTLP_BIND as resolved (warns when that newly opens Grafana)
           GRAFANA_PORT       --grafana-port > kept (validated) > 3000; busy by another program → fail
           CLICKHOUSE_VERSION flag > old ARM: missing → 22.3.20.29, 23.3.22.3 → 22.3.20.29 (warn) > kept
           4317/4318 busy by another program → warn only
           warn: tag ≥ 22.10 on old ARM; tag < 24 = out of support
3 stack    LAN note when a bind is not local; compose up -d; poll views-init until exited, must be 0
4 checks   http <bind|127.0.0.1>:<GRAFANA_PORT>/api/health; TCP 4317; docker enabled at boot (ask → enable)
5 LAN      only if OTLP_BIND or GRAFANA_BIND is not 127.0.0.1/localhost
           LAN IP = --lan-ip or src of `ip -4 route get 1.1.1.1`
           firewalld (active): ask → runtime + permanent port rules; ufw (if active): ask → allow
           warn: Docker bypasses the firewall; TCP test of <LAN IP>:4317 / :GRAFANA_PORT
6 summary  client commands for this PC (setup-client.sh --server-ip localhost) and other PCs (.ps1 / .sh)
  update re-run → finish_update
```
- `get_env`: last `KEY=` line, `\r` stripped. `set_env`: `sed` replace or append; a CRLF `.env`
  stays CRLF. No other line of `.env` is read or written.
- A re-run without `--lan`/`--local-only` keeps the binds; `--local-only` never removes firewall
  rules added earlier.
- Old ARM = `uname -m` is `aarch64` and the `/proc/cpuinfo` `Features` line lacks `lrcpc`
  (no `Features` line → not old). Any other `CLICKHOUSE_VERSION` value is the user's and stays.
- `confirm`: `--yes` answers yes; no terminal answers no. `as_root`: direct as root, else `sudo`.

### --update

```
run_update   (all post-pull code is in this function, parsed before the pull; ends in exec)
  checks     .env exists; ClickHouse answers (ch.sh SELECT 1); no tracked local changes; prev = HEAD; upstream?
  dump       backup/pre-update-<YYYYmmdd-HHMMSS>/; free space (df) vs sum(data_uncompressed_bytes)
             of active otel parts: less → fail, < 1.5× → warn; BACKUP_DIR=<dir> backup.sh dump; rowcounts.tsv
  code       upstream → git pull --ff-only; no upstream / no repo → warn, files as they are
  exec       CCT_UPDATE=1 CCT_UPDATE_DIR=<dir> CCT_UPDATE_PREV=<prev> bash setup-server.sh <args minus --update>
re-run       steps 2–6; in step 3 after views-init exited 0 → reload_changed_config (below)
             then finish_update: every table rows now ≥ before, else LOST banner + restore command, exit 1
             after a pull prints the rollback: git checkout <prev> && bash setup-server.sh
EXIT trap    failing exit once the dump folder is set → prints it (+ rollback command after a pull)
```
- `CCT_UPDATE_DIR` is honoured only with `CCT_UPDATE=1`, under `backup/`, without `..`, as an
  existing folder; the three variables are unset at start.
- `reload_changed_config` (only with dump folder + prev): `git diff --name-only <prev> HEAD` →
  `otel-collector.yaml` → `compose restart otel-collector`; `grafana/provisioning/*` →
  `compose restart grafana`; ok line per service, else "nothing to restart". git fails → warn
  (restart by hand), continue; restart fails → fail (EXIT trap prints dump folder + rollback).
- No reload needed: `clickhouse/` (views) — `compose up -d` starts the exited one-shot views-init
  again on every run; `grafana/dashboards/` — Grafana re-reads it every 30 s.
- Nothing is removed (no `down -v`); earlier dumps stay. With `sudo docker` the dump files belong to root.

## Clients

| | `setup-client.ps1` | `setup-client.sh` |
| --- | --- | --- |
| params | `-ServerIp` (required), `-PcName` (`$env:COMPUTERNAME`), `-Project` folders, `-SettingsDir` (`.claude`), `-UserSettings` (test override), `-WhatIf` | `--server-ip` (required, `[A-Za-z0-9._-]+`), `--pc-name` (`hostname -s`), `--project` (repeat), `--settings-dir`, `--user-settings`, `--dry-run` |
| JSON | `ConvertFrom-Json`; 5.1 re-indents (content unchanged) | python3 preferred, else jq with `$ARGS` (≥ 1.6), else fail |
| order | file by file | two phases: merge all in memory (invalid JSON / non-object / non-object `env` → stop before any write), then write |
| write | UTF-8 without BOM, re-parse | shell redirection (keeps mode, follows symlinks), re-validate |
| end | TCP test via `Test-NetConnection` | TCP test via `/dev/tcp` (timeout 3 s) |

- Both merge into `env` of the user settings (9 keys, `project=unknown`) and of
  `<project>/<SettingsDir>/settings.local.json` (`project=<folder lower-case>,host=<PcName>`);
  `PcName` matches `[A-Za-z0-9._-]+`. A missing or empty file counts as `{}`.
- Keep every other key; `<file>.bak` once before the first change. Per-user only: no HKLM, no
  machine env, no admin, no sudo.
- A project whose `.claude` is a junction/symlink to another folder needs no `-SettingsDir`: the
  write goes through it.

## Client reachability

```
Windows server: client ──TCP 4317──► LAN IP ── firewall (Private profile) ── [wsl: portproxy] ── 127.0.0.1:4317 ── wslrelay ── collector
Linux server:   client ──TCP 4317──► LAN IP ── Docker publish on OTLP_BIND (ufw/firewalld bypassed) ── collector
```
- Public network profile → rule does not apply → connection refused; the fix is the user's (mark
  the network Private) — never change it yourself.
- Corporate VPN clients usually cannot be reached from the corporate side (gateway policy): not
  fixable here, never suggest a workaround.
