# Conventions — SQL, dashboard JSON, PowerShell, shell, config

Rules for writing and reviewing code in this repo, with the traps already hit.

## Minimal change
Do what was asked; no unrequested options, wrappers or "for later" code. Never cut: input checks,
error handling, exit-code checks, idempotency of the setup scripts (every step must be safe to
re-run and must keep existing data, `.env` and foreign settings keys).

## ClickHouse (`clickhouse/*.sql`; details in `modules/materialization.md`)
Layers: `schema.sql` (tables `cc.events_t`, `cc.session_project_t`, `cc.tips_t` and the MV
`cc.events_mv`, all `IF NOT EXISTS`) → `backfill.sql` → `views.sql` (`CREATE OR REPLACE VIEW` only)
→ `refresh.sql` (run only by `cc-refresh`).
- **Per-event parsing lives in the MV, not in views.** A fix to how an event is parsed (MV
  expressions, `events_t` columns) does not reach stored rows and is not applied by `views-init`
  (the MV is `IF NOT EXISTS`): it needs an explicit migration (new table/MV + re-backfill, or
  `ALTER` + `DROP`/`CREATE` of the MV) — the user's "yes" first, `otel.otel_logs` stays the source.
  A fix in `views.sql` or `refresh.sql` still applies to all history (next query / next refresh).
- Keep in step, character for character: the `cc.events_mv` SELECT and `backfill.sql`; the path
  regex and stop list in the MV, `backfill.sql` and the cwd part of `cc.path_roots`.
- Read attributes as `LogAttributes['key']`; convert with `toUInt64OrZero` / `toFloat64OrZero`
  (attributes are strings; missing → `''`).
- `ServiceName` is filtered in the MV and `backfill.sql` (`claude-code`) and in `cc.session_meta`
  (`cc-session-meta`, a plain view straight over `otel.otel_logs`). Every other view reads the
  `*_t` tables or other views, never `otel.otel_logs`. Views build on `cc.events` (effective
  project) or, when they feed it or need no project, on `cc.events_raw`.
- New attribute → a column at the end of `cc.events_t` in `schema.sql`, the MV, `backfill.sql`
  (same position: the backfill inserts by position) and `cc.events_raw` (reaches `cc.events` via
  `e.*`) — a migration (above); old rows get it only by a manual rebuild from `otel.otel_logs`
  (the migration above). Document it in
  `modules/telemetry-data.md` (via context-auditor) and, if it is collected text, on the `data`
  page (`docs/data.md` + `docs/data.ru.md`).
- `refresh.sql` rebuilds a table as `*_new` → INSERT → check → `EXCHANGE TABLES` → `DROP *_new`;
  never run it by hand while `cc-refresh` is up. A new column of a `*_t` table it fills also needs
  an `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in `schema.sql` (`CREATE ... AS` copies the old one).
- `views-init` must stay idempotent: a re-run inserts nothing (anti-join on `(session_id, seq, ts)`).
- Explicit column aliases in joins (`e.ts AS ts`): ClickHouse keeps the `e.` prefix otherwise.
- Target ClickHouse 22.3 (old ARM servers) through 25.8: never several `USING` joins in one query
  (22.3/23.3 reject them) — join with `ON`. Applies to dashboard queries too.

## Dashboards (`grafana/dashboards/*.json`, seven files, plus their generated `ru/` copies)
- Edit the files, keep their 2-space formatting; panel `id`s and `gridPos` stay unique within a
  file. Never reuse the retired ids 6, 12, 25.
- Variables, `timepicker`, `tags` and `links` are shared: change them in all seven files alike.
- Every query honours all five shared variables and the time range (`$__timeFilter(ts)`, or
  `$__fromTime`/`$__toTime` when filtering an aggregate): Account (multi-value, its All value is
  `'__all'` with quotes) with `('__all' IN (${account:singlequote}) OR account_uuid IN
  (${account:singlequote}))`, Project, Session, Actor and Skill with `('${v}' = '__all' OR col =
  '${v}')`. Documented exceptions: `claude-context/modules/dashboard.md`.
- Variable queries are plain strings; keep `query` and `definition` identical.
- `rawSql` is one JSON string with `\n` — edit it with exact replacements, then validate the JSON.
- **Russian copies are generated:** never edit `grafana/dashboards/ru/*.json` by hand. After any
  change to an English file, to `grafana/rail/` or to `grafana/i18n/` — and after merging another
  branch that touched them — run `node grafana/rail/sync-rail.js`, then
  `node grafana/i18n/build-ru.js`, and commit the regenerated copies with the change. New static
  English text needs a `grafana/i18n/ru.json` entry (`grafana-style.md`, "Russian copies").
- `isSwitch()` (the EN/RU link matcher) exists in both `sync-rail.js` and `build-ru.js`: change
  both alike.
- `.json` files are LF (`.gitattributes`): the scripts write LF and `--check` compares bytes.

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

## Tooling traps
Windows PC:
- Git Bash rewrites `/mnt/c/...` arguments of `wsl` — run WSL-path commands from PowerShell.
- Quoting PowerShell → `wsl` → bash breaks: put SQL in a scratchpad file and pipe it to
  `linux-server-tools/ch.sh`; put bash logic in a `.sh` file.
- The Grep tool fails (no `rg`); use `grep` in Bash. Python only as `py -3`; Node is available.

Linux PC:
- Python is `python3` (no `py`). Node may be missing (`command -v node`): without it
  `check-dashboard.js` cannot run — see `verification.md`.
- No PowerShell: `*.ps1` cannot be parsed or run here.
- Docker may need `sudo` if the user is not in the `docker` group — hand such commands to the user.

Both:
- Grafana's API escapes `>` as `>` — parse the JSON before searching it.
