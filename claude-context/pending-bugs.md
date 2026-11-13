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

## setup-client.ps1

- **L** `-PcName` defaults to `$env:COMPUTERNAME` (upper case); a PC configured by hand with a
  lower-case name shows up as a second `host` value.

## views (`clickhouse/views.sql`)

- **L?** `cc.tool_calls` makes paths relative at the **first** `/<project>` in the path: a parent
  folder whose name starts with the project name (`.../proj-old/x/proj/...`) gives a wrong
  `path`/`area`.
- **?** `query_source` of the main session in the interactive terminal CLI is unverified
  (expected `repl_main_thread`, matched by `startsWith(query_source, 'repl_main')`); any other
  value shows as `aux:<value>`.

## dashboard (`cc-usage.json`)

- **L** Summary "Sessions" counts sessions with a model request; panel 7 also lists sessions with
  a prompt but no request, so the two numbers can differ.
