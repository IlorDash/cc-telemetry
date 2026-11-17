# Verification — checking a change on the live stack

There are no unit tests: every change is checked against the running stack on the server PC.
Commands below are in the Windows form (Docker in WSL: `wsl -d Ubuntu -- ...`, run from PowerShell
in the repo root). On a Linux server run them without the `wsl -d Ubuntu --` prefix from bash in
the repo root (add `sudo` only if the user is not in the `docker` group — then hand the command to
the user). `*.ps1` checks need a Windows PC; on Linux report them as not verified. Report what ran
and what did not; never claim a check that did not run.

| Changed | Check |
| --- | --- |
| `clickhouse/views.sql` | `wsl -d Ubuntu -- docker compose run --rm views-init` (must print `cc.* views are ready`); then a `SELECT count()` per touched view and a sample of the changed columns through `linux-server-tools/ch.sh`; then the dashboard check |
| `grafana/dashboards/*.json` | `JSON.parse` every changed file with `node -e`; wait ≤ 30 s for Grafana to reload; dashboard check (`check-dashboard.js` runs every file's queries and checks that each uid is provisioned and home = `cc-usage`) |
| `otel-collector.yaml` | `wsl -d Ubuntu -- docker compose restart otel-collector`; log shows `Everything is ready`; a fresh event arrives (`SELECT max(Timestamp) FROM otel.otel_logs`) |
| `docker-compose.yml` | `wsl -d Ubuntu -- docker compose up -d`; `docker compose ps -a` all Up, `views-init` Exited (0) |
| `clickhouse/config.d/*.xml`, `clickhouse/users.d/*.xml` | `wsl -d Ubuntu -- docker compose restart clickhouse` (neither compose nor `--update` restarts it for these); healthy again; the changed value in `system.server_settings` (25.x) / `system.settings` (profile keys) through `ch.sh`; then the dashboard check |
| `*.ps1` | parse: `[System.Management.Automation.Language.Parser]::ParseFile(...)` with 0 errors; no bytes > 127; run it (below) |
| `setup-server.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-server.ps1` — must exit 0 and keep `.env` (compare `Get-FileHash` before/after). `-EnableLan` needs the user (UAC) |
| `client/setup-client.ps1` | run against copies in the scratchpad with `-UserSettings <copy>` and `-Project <copy dir>`; compare with Node: every key except `env` identical, no BOM. Never against the real files unless the user asked |
| `*.sh` | `wsl -d Ubuntu -- bash -n <path>.sh` |
| `linux-server-tools/*.sh` | run it when harmless (`backup.sh dump` is; `restore` appends — only on an empty stack) |
| `setup-server.sh` | `wsl -d Ubuntu -- bash setup-server.sh` — must exit 0; without `--lan`/`--local-only` every `.env` key reports `kept`. Never `--update` (runs `git pull`) unless the user asks |
| `client/setup-client.sh` | `--dry-run`, or against copies in the scratchpad with `--user-settings <copy>` and `--project <copy dir>`; same comparison as for `setup-client.ps1`. Never against the real files unless the user asked |

A live check covers only the ClickHouse version the stack runs (`server-state.local.md`), not
every supported tag.

**SQL:** write the query into a scratchpad file, then
`Get-Content <file> | wsl -d Ubuntu -- bash linux-server-tools/ch.sh` on Windows or
`cat <file> | bash linux-server-tools/ch.sh` on Linux (password stays inside the script).

**Dashboard check:** `node claude-context/scripts/check-dashboard.js` — runs every variable and
panel query through Grafana's `/api/ds/query` with all variables = All (or
`--project <p> --session <id>`), prints `ok`/`FAIL` per query; all must be `ok`. It checks SQL and
macros, not the visual layout — say so when layout changed. It needs Node; a Linux PC may have
none (`command -v node`) — then say "dashboard check not run: no Node" and ask the user to
install it (`sudo apt install nodejs`) or run the check from a Windows PC.

The stack is not running → say "not verified on the live stack" and why.

**Raw events without the server** (what a Claude Code version sends). The user `settings.json`
env overrides process env, so skip user settings (from a scratchpad folder). PowerShell:
`$env:CLAUDE_CODE_ENABLE_TELEMETRY="1"; $env:OTEL_LOGS_EXPORTER="console"; $env:OTEL_METRICS_EXPORTER="none"; $env:OTEL_LOG_TOOL_DETAILS="1"; claude -p "<task>" --setting-sources local --model haiku *> "<scratchpad>\otel-console.log"`
bash:
`CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_LOGS_EXPORTER=console OTEL_METRICS_EXPORTER=none OTEL_LOG_TOOL_DETAILS=1 claude -p "<task>" --setting-sources local --model haiku > "<scratchpad>/otel-console.log" 2>&1`
(add `OTEL_LOG_USER_PROMPTS=1` to see prompt/response text). One short paid request.
