# Verification — checking a change on the live stack

There are no unit tests: every change is checked against the running stack on the server PC
(wsl mode: `wsl -d Ubuntu -- ...`, run from PowerShell in the repo root). Report what ran and what
did not; never claim a check that did not run.

| Changed | Check |
| --- | --- |
| `clickhouse/views.sql` | `wsl -d Ubuntu -- docker compose run --rm views-init` (must print `cc.* views are ready`); then a `SELECT count()` per touched view and a sample of the changed columns through `linux-server-tools/ch.sh`; then the dashboard check |
| `grafana/dashboards/cc-usage.json` | `node -e "JSON.parse(require('fs').readFileSync('grafana/dashboards/cc-usage.json','utf8'))"`; wait ≤ 30 s for Grafana to reload (dashboard `version` grows in `/api/dashboards/uid/cc-usage`); dashboard check |
| `otel-collector.yaml` | `wsl -d Ubuntu -- docker compose restart otel-collector`; log shows `Everything is ready`; a fresh event arrives (`SELECT max(Timestamp) FROM otel.otel_logs`) |
| `docker-compose.yml` | `wsl -d Ubuntu -- docker compose up -d`; `docker compose ps -a` all Up, `views-init` Exited (0) |
| `*.ps1` | parse: `[System.Management.Automation.Language.Parser]::ParseFile(...)` with 0 errors; no bytes > 127; run it (below) |
| `setup-server.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-server.ps1` — must exit 0 and keep `.env` (compare `Get-FileHash` before/after). `-EnableLan` needs the user (UAC) |
| `client/setup-client.ps1` | run against copies in the scratchpad with `-UserSettings <copy>` and `-Project <copy dir>`; compare with Node: every key except `env` identical, no BOM. Never against the real files unless the user asked |
| `linux-server-tools/*.sh` | `wsl -d Ubuntu -- bash -n linux-server-tools/<file>.sh`; run it when harmless (`backup.sh dump` is; `restore` appends — only on an empty stack) |

**SQL:** write the query into a scratchpad file, then
`Get-Content <file> | wsl -d Ubuntu -- bash linux-server-tools/ch.sh` (password stays inside the script).

**Dashboard check:** `node claude-context/scripts/check-dashboard.js` — runs every variable and
panel query through Grafana's `/api/ds/query` with all variables = All (or
`--project <p> --session <id>`), prints `ok`/`FAIL` per query; all must be `ok`. It checks SQL and
macros, not the visual layout — say so when layout changed.

The stack is not running → say "not verified on the live stack" and why.

**Raw events without the server** (what a Claude Code version sends). The user `settings.json`
env overrides process env, so skip user settings (PowerShell, from a scratchpad folder):
`$env:CLAUDE_CODE_ENABLE_TELEMETRY="1"; $env:OTEL_LOGS_EXPORTER="console"; $env:OTEL_METRICS_EXPORTER="none"; $env:OTEL_LOG_TOOL_DETAILS="1"; claude -p "<task>" --setting-sources local --model haiku *> "<scratchpad>\otel-console.log"`
(add `$env:OTEL_LOG_USER_PROMPTS="1"` to see prompt/response text). One short paid request.
