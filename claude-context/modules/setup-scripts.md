# Setup scripts — server, clients, Linux helpers

How `setup-server.ps1` / `setup-server.sh` and the client scripts work, the Linux helpers and the
LAN path. `--update` and `migrate_storage`: `modules/server-update.md`.

## Files

| Path | Role |
| --- | --- |
| `setup-server.ps1` | Windows server setup (Docker Desktop or WSL2), re-runnable; doubles as a health check |
| `setup-server.sh` | Linux server setup, re-runnable; `--update` updates a running server |
| `client/setup-client.ps1` | per-user client setup on Windows, re-runnable; embeds and installs the session-meta hook `session-meta.ps1` |
| `client/setup-client.sh` | per-user client setup on Linux (python3, or jq ≥ 1.6), re-runnable; embeds and installs `session-meta.sh` |
| `linux-server-tools/install-docker.sh` | Docker Engine + compose plugin from download.docker.com on Ubuntu/Debian and derivatives (`ID`/`ID_LIKE`; a derivative's codename is checked against download.docker.com first); enables the service, adds the user to `docker`; run as root |
| `linux-server-tools/ch.sh` | SQL from stdin or args against the stack, password read from `.env` |
| `linux-server-tools/backup.sh` | `dump` all `otel.*` tables to `$BACKUP_DIR/<table>.native` (default `backup/`; fails if `SHOW TABLES` fails); `restore [table]` appends, skips empty files and missing tables |
| `client/*.json` | env templates for manual client setup (no hook: no session meta) |

## setup-server.ps1 (Windows)

```
1 Docker   auto: docker on PATH answers → desktop; else WSL distro exists → wsl
           wsl: no docker → check PID 1 = systemd → ask (or -Yes) → wsl -u root install-docker.sh
                → wsl --terminate (docker group)
2 .env     created with two random 32-hex passwords (UTF-8 no BOM, LF); existing file kept
3 stack    docker compose up -d (direct wsl.exe / docker call, not the Compose wrapper); fails →
           Compose logs --tail 50 views-init, then Fail; poll views-init until Exited, must be 0
4 checks   GET localhost:3000/api/health; TCP localhost:4317 and :4318
5 wsl      write <Startup>/cc-telemetry-keepalive.vbs (hidden wsl --exec sleep infinity), start it if not running
6 -EnableLan  not admin → relaunch itself elevated (UAC) with -LanOnly, transcript in %TEMP%\cc-telemetry-lan.log
           per port in $otlpPorts (4317, 4318):
             firewall rule "OTLP <port> (Claude Code telemetry)" Private (a re-run adds a missing one)
             wsl: portproxy <LAN_IP>:<port> → 127.0.0.1:<port>, deletes other *:<port> forwards
             TCP test <LAN_IP>:<port>
           warn if the LAN profile is Public
```
- Params: `-Mode auto|desktop|wsl`, `-Distro` (`Ubuntu`), `-EnableLan`, `-LanIp`, `-Yes`, internal `-LanOnly`.
- Writes no bind/port keys: compose defaults apply (4317, 4318 on `0.0.0.0`, Grafana `127.0.0.1:3000`);
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
  --update → run_update (`modules/server-update.md`), ends in exec
2 .env     missing → created (umask 077, two random 32-hex); then only the managed keys:
           OTLP_BIND          flag (lan 0.0.0.0 / local 127.0.0.1) > kept > 0.0.0.0
           GRAFANA_BIND       flag > kept > OTLP_BIND as resolved (warns when that newly opens Grafana)
           GRAFANA_PORT       --grafana-port > kept (validated) > 3000; busy by another program → fail
           CLICKHOUSE_VERSION flag > old ARM: missing → 22.3.20.29, 23.3.22.3 → 22.3.20.29 (warn) > kept
           4317/4318 busy by another program → warn only
           warn: tag ≥ 22.10 on old ARM; tag < 24 = out of support
3 stack    LAN note when a bind is not local; compose up -d (fails → logs --tail 50 views-init, fail);
           poll views-init until exited (90 × 2 s), must be 0; then migrate_storage (`modules/server-update.md`);
           [update re-run: reload_changed_config]
4 checks   http <bind|127.0.0.1>:<GRAFANA_PORT>/api/health; TCP 4317, 4318; docker enabled at boot (ask → enable)
5 LAN      only if OTLP_BIND or GRAFANA_BIND is not 127.0.0.1/localhost
           lan_ports = 4317 4318 (OTLP_BIND not local) + GRAFANA_PORT (GRAFANA_BIND not local)
           LAN IP = --lan-ip or src of `ip -4 route get 1.1.1.1`
           firewalld (active): ask → runtime + permanent port rules; ufw (if active): ask → allow
           warn: Docker bypasses the firewall; TCP test of <LAN IP>:4317, :4318 / :GRAFANA_PORT
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
  Exception: the retention question of `migrate_storage` is not `confirm` — `--yes` does not answer it.

### migrate_storage and --update

In `modules/server-update.md`: `migrate_storage` (every run, after views-init exited 0) and
`--update` (`run_update`, `reload_changed_config`, `finish_update`, EXIT trap). Linux only.

## Clients

| | `setup-client.ps1` | `setup-client.sh` |
| --- | --- | --- |
| params | `-ServerIp` (required, `[A-Za-z0-9._-]+`), `-PcName` (`$env:COMPUTERNAME`), `-Project` folders, `-SettingsDir` (`.claude`), `-UserSettings` (test override), `-NoSessionMeta`, `-ImportHistory`, `-WhatIf` | `--server-ip` (required, `[A-Za-z0-9._-]+`), `--pc-name` (`hostname -s`), `--project` (repeat), `--settings-dir`, `--user-settings`, `--no-session-meta`, `--import-history`, `--dry-run` |
| JSON | `ConvertFrom-Json`; 5.1 re-indents (content unchanged) | python3 preferred, else jq with `$ARGS` (≥ 1.6), else fail |
| order | hook script, user settings, then project files one by one | two phases: merge all in memory (invalid JSON / non-object / non-object `env` / bad `hooks` layout → stop before any write), then hook script, then write |
| write | UTF-8 without BOM, re-parse | shell redirection (keeps mode, follows symlinks), re-validate |
| end | TCP test of 4317 and (hook on) 4318 via `Test-NetConnection`; then the import | same via `/dev/tcp` (timeout 3 s); then the import |

- Both merge into `env` of the user settings (9 keys, `project=unknown`) and of
  `<project>/<SettingsDir>/settings.local.json` (`project=<folder lower-case>,host=<PcName>`);
  `PcName` matches `[A-Za-z0-9._-]+`. A missing or empty file counts as `{}`.
- Keep every other key; `<file>.bak` once before the first change. Per-user only: no HKLM, no
  machine env, no admin, no sudo.
- A project whose `.claude` is a junction/symlink to another folder needs no `-SettingsDir`: the
  write goes through it.

### Session-meta hook (default; data: `modules/telemetry-data.md`)

```
install    <settings dir>/cc-telemetry/session-meta.{ps1,sh} rewritten on every run (.sh: chmod 700)
           user settings hooks.UserPromptSubmit: our entry = command containing cc-telemetry/session-meta
           (\ → /); updated in place, never duplicated, other hooks kept; new: {type command, async true,
           timeout 60}; command passes server (localhost → 127.0.0.1) and PC name as arguments
           ps1: powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<path, />" ...
run        stdin transcript_path → projects root = its grandparent; silent, always exit 0
           back-off: last failed send < 600 s ago → do nothing (a fail time in the future counts as expired)
           files = current JSONL + every <root>/*/*.jsonl (not agent-*) changed since last scan − 120 s
                   (no scan yet → current only; import → all)
           per file: title (custom-title over ai-title), last gitBranch, first cwd, version
           skip if all empty or hash(src,title,branch,cwd) = state; POST batches of 100 to
           http://<server>:4318/v1/logs (5 s timeout); first failed batch → rest counted failed
           state: scan time kept on any failure; fail time set when a batch failed
-NoSessionMeta  removes our hook entry (and empty hooks keys) + script, state, state temp files;
                the folder only if empty. Cannot be combined with -ImportHistory
-ImportHistory  runs the hook once with --import-history over <settings dir>/projects, prints
                "found, sent, unchanged, failed"; skipped under -WhatIf / --dry-run
```
- State file `session-meta.state.json` (ps1) / `session-meta.state` (sh): keyed by `server|PC`
  (another key = fresh state), holds only hashes; merged with the file on disk, replaced atomically.
- Reads only title/branch/cwd/version lines, never prompt or answer text.
- `session-meta.sh` needs bash 4+, GNU `find` (`-newermt`), python3 or jq, curl or python3;
  otherwise it exits silently. Its jq path is untested (pending-bugs.md).
- ps1 parses lines by string search (no JSON parse per line), opens files with shared read.

## Client reachability

```
Windows server: client ──TCP 4317/4318──► LAN IP ── firewall (Private profile) ── [wsl: portproxy] ── 127.0.0.1:<port> ── wslrelay ── collector
Linux server:   client ──TCP 4317/4318──► LAN IP ── Docker publish on OTLP_BIND (ufw/firewalld bypassed) ── collector
```
- A server set up before 4318 was published: Claude Code telemetry still arrives, session meta does
  not (client prints a hint) until the server setup is updated and re-run.
- Public network profile → rule does not apply → connection refused; the fix is the user's (mark
  the network Private) — never change it yourself.
- Corporate VPN clients usually cannot be reached from the corporate side (gateway policy): not
  fixable here, never suggest a workaround.
