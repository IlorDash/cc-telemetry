# Pending bugs

Suspected bugs, traps and unverified behaviour, **not fixed**. Found by reading the code and
running the stack (wsl mode) on 2026-11-13/14; confirm before fixing. Remove an entry once fixed
(or confirmed intended). Severity: **H** data loss / security / broken setup, **M** wrong result or
behaviour, **L** cosmetic, trap; `?` = unsure or unverified.

## setup-server.ps1

- **M** `Enable-Lan` deletes every `portproxy` entry on port 4317 whose listen address is not the
  current LAN IP — also a forward the user added on purpose for a second adapter. Only one LAN
  address can be served.
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

## setup-client.sh

- **M?** The jq branch (no python3, jq ≥ 1.6) never ran; only the python3 branch was tested.

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
- **L?** Cost: every query on `cc.events` reads `otel.otel_logs` about 4 times (`events_raw` itself,
  `session_project` over `path_roots`, and both halves of its `names` union). Deferred until an
  ARMv8.0 Linux server gets slow.

## dashboard (`cc-usage.json`)

- **L** Summary "Sessions" counts sessions with a model request; panel 7 also lists sessions with
  a prompt but no request, so the two numbers can differ.
