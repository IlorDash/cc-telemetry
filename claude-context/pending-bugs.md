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

- **L** The final summary prints `.\setup-client.ps1` for other PCs, while in the repo the file is
  `client\setup-client.ps1` (right only for a copied file).

## setup-server.sh

- **M?** Unverified on a physical Linux host: the Docker install path (`install-docker.sh` on
  Ubuntu/Debian and derivatives) and the ufw / firewalld rule paths.

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
- **L?** Cost: every query on `cc.events` reads `otel.otel_logs` about 6 times (`events_raw` itself;
  `session_project` over `path_roots`, which reads `events_raw` and `session_meta`; and both halves
  of its `names` union, `path_roots` again plus `events_raw`). Deferred until an ARMv8.0 Linux
  server gets slow.
- **L** `cc.tips` `repeated-read` puts `cc.tool_calls.path` in the title: a file outside the
  project keeps its absolute path there.
- **?** `cc.tips` verified only on ClickHouse 22.3 (`count()` ~0.5 s on ~4.9k events); 25.8
  untested. It reads `otel.otel_logs` once per rule through the views — watch the cost as data grows.
- **?** `cc.tips` rules `cache`, `agent-outlier`, `slow-ttft` have not fired on real data yet
  (2026-11-19): SQL and thresholds unconfirmed.
- **?** No `api_error` event in the live data yet (2026-11-19, Claude Code 2.1.327): its attribute
  names, `cc.events_raw.status_code`/`error` and the Health panels 493/495 are checked only on empty
  data; whether `api_error` carries `agent_id` / `skill.name` (used for the Actor/Skill filter) is unknown.

## dashboards (`grafana/dashboards/*.json`)

- **?** A real `setup-server.sh --update` across the `cc-usage.json` → `overview.json` rename is
  untested: the home path changes in the `grafana` env (recreated by `compose up -d`) while the
  provider picks up the new file only within 30 s — possibly a short window without the dashboard.
