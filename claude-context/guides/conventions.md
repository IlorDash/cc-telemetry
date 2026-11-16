# Conventions — SQL, dashboard JSON, PowerShell, shell, config

Rules for writing and reviewing code in this repo, with the traps already hit.

## Minimal change
Do what was asked; no unrequested options, wrappers or "for later" code. Never cut: input checks,
error handling, exit-code checks, idempotency of the setup scripts (every step must be safe to
re-run and must keep existing data, `.env` and foreign settings keys).

## ClickHouse views (`clickhouse/views.sql`)
- `CREATE OR REPLACE VIEW`, plain views only (no materialized views, no tables of our own): history
  is re-derived on every query, so a fix applies to all data.
- Read attributes as `LogAttributes['key']`; convert with `toUInt64OrZero` / `toFloat64OrZero`
  (attributes are strings; missing → `''`).
- Filter `ServiceName = 'claude-code'` once, in `cc.events_raw` (the raw layer); other views build
  on `cc.events` (effective project) or, when they feed it or need no project, on `cc.events_raw`.
  The one exception: `cc.session_meta` reads the client hook's records (`ServiceName = 'cc-session-meta'`)
  straight from `otel.otel_logs`.
- New attribute → add a column to `cc.events_raw` (reaches `cc.events` via `e.*`), document it in
  `modules/telemetry-data.md` (via context-auditor) and, if it is collected text, in README "What is sent".
- Explicit column aliases in joins (`e.ts AS ts`): ClickHouse keeps the `e.` prefix otherwise.
- Target ClickHouse 22.3 (old ARM servers) through 25.8: never several `USING` joins in one query
  (22.3/23.3 reject them) — join with `ON`. Applies to dashboard queries too.

## Dashboards (`grafana/dashboards/*.json`, seven files)
- Edit the files, keep their 2-space formatting; panel `id`s and `gridPos` stay unique within a
  file. Never reuse the retired ids 6, 12, 25.
- Variables, `timepicker`, `tags` and `links` are shared: change them in all seven files alike.
- Every query honours all four variables with `('${v}' = '__all' OR col = '${v}')` and the time
  range (`$__timeFilter(ts)`, or `$__fromTime`/`$__toTime` when filtering an aggregate).
- Variable queries are plain strings; keep `query` and `definition` identical.
- `rawSql` is one JSON string with `\n` — edit it with exact replacements, then validate the JSON.

## PowerShell (`*.ps1`) — Windows PowerShell 5.1
- ASCII only (5.1 reads BOM-less files as ANSI); write JSON/text with
  `New-Object Text.UTF8Encoding($false)` (no BOM — Claude Code and Node reject it).
- `$ErrorActionPreference = 'Continue'`: with `'Stop'`, any stderr line of a native program
  (apt warnings, a `docker: not found` probe) aborts the script. Check `$LASTEXITCODE` after
  every native call that matters; give important cmdlets `-ErrorAction Stop` (also
  `Start-Process -Verb RunAs`, or a UAC refusal passes silently).
- `"$var:text"` parses as a drive-qualified variable — write `"${var}:4317"`.
- Never name a variable `$profile`, `$pid`, `$args`, `$input`, `$host` (automatic variables).
- `ConvertFrom-Json` → `PSCustomObject`: add keys with `Add-Member`; `ConvertTo-Json -Depth 50`.
- No machine-wide changes in client code: only `%USERPROFILE%` and project files.
- `$env:WSL_UTF8 = '1'` before calling `wsl.exe` (else its own messages are UTF-16).

## Shell (`*.sh`) and config
- `#!/bin/bash`, `set -euo pipefail`, LF endings (`.gitattributes`).
- Never put a password on a command line you print; read `.env` inside the script (`linux-server-tools/ch.sh`).
- `.env` may be CRLF (edited on Windows): strip `\r` when reading a key, keep the file's endings
  when writing (`get_env` / `set_env` in `setup-server.sh`).
- bash reads a script while it runs: code that runs after `git pull` of that script lives in a
  function parsed before the pull and ends in `exec` (`run_update`).
- On Linux Docker-published ports bypass ufw/firewalld: limit access with the bind address
  (`OTLP_BIND` / `GRAFANA_BIND`), not a firewall rule.
- `otel-collector.yaml`: secrets via `${env:NAME}`; a new processor must be added to the pipeline
  list too; restart the collector and check its log for `Everything is ready`.
- Image tags pinned to exact versions.

## Tooling traps (this PC)
- Git Bash rewrites `/mnt/c/...` arguments of `wsl` — run WSL-path commands from PowerShell.
- Quoting PowerShell → `wsl` → bash breaks: put SQL in a scratchpad file and pipe it to
  `linux-server-tools/ch.sh`; put bash logic in a `.sh` file.
- The Grep tool fails (no `rg`); use `grep` in Bash. No Python except `py -3`; Node is available.
- Grafana's API escapes `>` as `>` — parse the JSON before searching it.
