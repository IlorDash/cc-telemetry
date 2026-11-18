# Pending bugs

Suspected bugs, traps and unverified behaviour, **not fixed**. Found by reading the code and
running the stack (wsl mode) on 2026-11-13/14; confirm before fixing. Remove an entry once fixed
(or confirmed intended). Severity: **H** data loss / security / broken setup, **M** wrong result or
behaviour, **L** cosmetic, trap; `?` = unsure or unverified.

## setup-server.ps1

- **M** `Enable-Lan` deletes every `portproxy` entry on port 4317 or 4318 whose listen address is
  not the current LAN IP — also a forward the user added on purpose for a second adapter. Only one
  LAN address can be served.
- **M?** Desktop mode never ran (no Docker Desktop on the test PC): `Test-DesktopDocker`, `Compose`
  without `wsl`, the summary output.
- **L** `Get-LanIp` takes the up adapter with a default gateway and the lowest interface metric; a
  full-tunnel VPN (default gateway on the VPN adapter) can win and get the firewall/portproxy.
- **L** Keepalive detection matches any `wsl.exe` running `sleep infinity`, whatever the distro: with
  `-Distro` other than the one already kept alive, the new keepalive is not started this time
  (the Startup file is correct, so it starts after the next logon).

- **?** The new `compose up -d` failure path (print views-init log, then `Fail`) never ran: the
  `.ps1` was not executed after the change (Linux test machine only).
- **L** Step 3 calls `wsl.exe ... docker compose up -d` / `docker compose up -d` directly,
  duplicating the `Compose` wrapper's mode switch: a change to the wrapper must be repeated there.

- **L** The final summary prints `.\setup-client.ps1` for other PCs, while in the repo the file is
  `client\setup-client.ps1` (right only for a copied file).

## setup-server.sh

- **M?** Unverified on a physical Linux host: the Docker install path (`install-docker.sh` on
  Ubuntu/Debian and derivatives) and the ufw / firewalld rule paths.

- **M?** `reload_changed_config` restarts only `otel-collector` and `grafana`: a pulled change to
  `clickhouse/config.d/low-resource.xml` or `clickhouse/users.d/low-resource.xml` leaves
  `clickhouse` running on the old values (its service definition is unchanged, so `compose up -d`
  does not recreate it). Both are single-file bind mounts: git replaces the file, the running
  container likely keeps the old inode until a restart (unverified).

## setup-client.ps1

- **L** `-PcName` defaults to `$env:COMPUTERNAME` (upper case); a PC configured by hand with a
  lower-case name shows up as a second `host` value.
- **L** Not two-phase like the .sh: the user settings file is written before the `-Project` folders
  are resolved, so a missing project folder (`Resolve-Path`) stops the script after the first write.

## setup-client.sh

- **M?** The jq branch (no python3, jq ≥ 1.6) never ran; only the python3 branch was tested. Same
  for the jq paths of the generated `session-meta.sh` (`JQ_META`, `JQ_PAYLOAD`, `hook_json`).

## collector / clients

- **M?** Whether running Claude Code sessions reconnect after the collector restarts is
  unconfirmed (2026-11-14: no events for ~50 min after a restart, cause unknown).
  A plain `setup-server.sh --update` (`compose up -d`) recreates only changed containers, so the
  collector restarts only when its service definition (image tag, environment, ports) changes,
  or when the pulled commits changed `otel-collector.yaml` (`reload_changed_config`).

## ClickHouse config (`clickhouse/config.d/`, `clickhouse/users.d/`)

- **M?** `background_pool_size` sits in the `default` profile (`users.d`). 22.3 still reads it there
  (shows as changed in `system.settings`, observed 2026-11-17; the actual pool size was not
  measured); in 25.8 it is a server-level setting, so in a profile it is likely ignored and the
  2-thread merge limit does not apply on 25.8 servers. Unverified on 25.8.
- **L** On 22.3 adding the `query_log` TTL renamed the old table to `system.query_log_0` (~78k rows
  2026-11-14..16, observed 2026-11-17); it has no TTL and stays until dropped (`DROP`: user's "yes").

## AI setup (`claude-context/settings.json`)

- **?** The guard-secrets hook command is `if command -v py ...; then py -3 ...; else python3 ...; fi`:
  POSIX shell syntax, run on Linux only so far. On Windows it works only if Claude Code runs hook
  commands under Git Bash (not cmd/PowerShell); untested there — a broken hook means no secrets guard.

## views (`clickhouse/views.sql`)

- **L?** `cc.tool_calls` makes paths relative at the **first** `/<project>` in the path: a parent
  folder whose name starts with the project name (`.../proj-old/x/proj/...`) gives a wrong
  `path`/`area`.
- **?** `query_source` of the main session in the interactive terminal CLI is unverified
  (expected `repl_main_thread`, matched by `startsWith(query_source, 'repl_main')`); any other
  value shows as `aux:<value>`.
- **L** `cc.session_project` worktree fold is a name-prefix heuristic: it merges different
  projects sharing a prefix (`my` and `my-app`) and is not transitive (`b`, `b-c`, `b-c-d`). A
  project in an unusual layout (`/data/x/y/`) is named after its first folder (`data`).
- **L** `cc.tips` `repeated-read` puts `cc.tool_calls.path` in the title: a file outside the
  project keeps its absolute path there.
- **?** `cc.tips` rules (now in `refresh.sql`) verified only on ClickHouse 22.3; 25.8 untested.
- **?** `cc.tips` rules `cache`, `big-results`, `agent-outlier`, `denials`, `slow-ttft` have not
  fired on real data yet: SQL and thresholds unconfirmed.

## materialization (`clickhouse/schema.sql`, `backfill.sql`, `refresh.sql`, `cc-refresh`)

- **?** Run only on ClickHouse 22.3.20.29 (2026-11-18): `schema.sql`, the backfill, `refresh.sql`
  (`EXCHANGE TABLES`) and the new views never ran on 23.3 or 25.8.
- **?** The `throwIf` abort path of `refresh.sql` (duplicate `session_id` → no swap, old table
  kept, next run drops the leftover `_new`) was never triggered.
- **?** A very large first backfill (upgrade over a big history) was not timed against the setup
  scripts' views-init wait (90 × 2 s after `compose up -d`).
- **?** `backup.sh restore` refilling `cc.events_t` (through `cc.events_mv`, or the next views-init
  backfill) follows from the code but was not run.
- **L?** A row from a client whose clock is more than 30 s ahead, arriving while a month pass
  runs, may be inserted by both the MV and the backfill (duplicate in `cc.events_t`); rare, not
  observed.
- **L** A changed `clickhouse/refresh-loop.sh` is not picked up by `setup-server.sh --update`
  (`cc-refresh`'s service definition is unchanged, `reload_changed_config` does not restart it)
  until `cc-refresh` is restarted by hand.
- **L** Path rules are written three times (`cc.events_mv`, `backfill.sql`, `cwd` part of
  `cc.path_roots`) and the project rule twice (`cc.events`, `cc.tool_calls`): an edit to one copy
  silently diverges.

## dashboards (`grafana/dashboards/*.json`)

- **?** A real `setup-server.sh --update` across the `cc-usage.json` → `overview.json` rename is
  untested: the home path changes in the `grafana` env (recreated by `compose up -d`) while the
  provider picks up the new file only within 30 s — possibly a short window without the dashboard.
