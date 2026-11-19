# Verification — checking a change on the live stack

There are no unit tests: every change is checked against the running stack on the server PC
(wsl mode: `wsl -d Ubuntu -- ...`, run from PowerShell in the repo root). Report what ran and what
did not; never claim a check that did not run.

| Changed | Check |
| --- | --- |
| `clickhouse/views.sql` | `wsl -d Ubuntu -- docker compose run --rm views-init` (must print `cc.* views are ready`); then a `SELECT count()` per touched view and a sample of the changed columns through `linux-server-tools/ch.sh`; then the dashboard check |
| `grafana/dashboards/*.json` | `JSON.parse` every changed file with `node -e`; wait ≤ 30 s for Grafana to reload; dashboard check (`check-dashboard.js` runs every file's queries and checks that each uid is provisioned and home = `cc-usage`) |
| `otel-collector.yaml` | `wsl -d Ubuntu -- docker compose restart otel-collector`; log shows `Everything is ready`; a fresh event arrives (`SELECT max(Timestamp) FROM otel.otel_logs`) |
| `docker-compose.yml` | `wsl -d Ubuntu -- docker compose up -d`; `docker compose ps -a` all Up, `views-init` Exited (0) |
| `*.ps1` | parse: `[System.Management.Automation.Language.Parser]::ParseFile(...)` with 0 errors; no bytes > 127; run it (below) |
| `setup-server.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-server.ps1` — must exit 0 and keep `.env` (compare `Get-FileHash` before/after). `-EnableLan` needs the user (UAC) |
| `client/setup-client.ps1` | run against copies in the scratchpad with `-UserSettings <copy>` and `-Project <copy dir>`; compare with Node: every key except `env` identical, no BOM. Never against the real files unless the user asked |
| `*.sh` | `wsl -d Ubuntu -- bash -n <path>.sh` |
| `linux-server-tools/*.sh` | run it when harmless (`backup.sh dump` is; `restore` appends — only on an empty stack) |
| `setup-server.sh` | `wsl -d Ubuntu -- bash setup-server.sh` — must exit 0; without `--lan`/`--local-only` every `.env` key reports `kept`. Never `--update` (runs `git pull`) unless the user asks |
| `client/setup-client.sh` | `--dry-run`, or against copies in the scratchpad with `--user-settings <copy>` and `--project <copy dir>`; same comparison as for `setup-client.ps1`. Never against the real files unless the user asked |
| `docs/`, `mkdocs.yml`, `hooks/`, `VERSION` | `.venv/Scripts/python.exe -m mkdocs build --strict` exits 0 with no warnings (no `.venv`: `py -3 -m venv .venv`, then `.venv\Scripts\python.exe -m pip install -r docs/requirements.txt`); `bash ci/check-release-markers.sh docs`; `py -3 claude-context/skills/docs-update/scripts/check-readme.py --root . --file <page>` on changed pages and the README. Not on the live stack |
| screenshots (`docs/assets/`) | only from the demo stack: `wsl -d Ubuntu -- bash tools/docs-demo/demo.sh up`, `node tools/docs-demo/check.js --from now-30d` all `ok`, `screenshots.js` via a Playwright runner, then `demo.sh down` (`tools/docs-demo/README.md`). Never from the live Grafana |

A live check covers only the ClickHouse version the stack runs (`server-state.local.md`), not
every supported tag.

**SQL:** write the query into a scratchpad file, then
`Get-Content <file> | wsl -d Ubuntu -- bash linux-server-tools/ch.sh` (password stays inside the script).

**Dashboard check:** `node claude-context/scripts/check-dashboard.js` — runs every variable and
panel query through Grafana's `/api/ds/query` with all variables = All (or
`--project <p> --session <id>`), prints `ok`/`FAIL` per query; all must be `ok`. It checks SQL and
macros, not the visual layout — say so when layout changed.

The stack is not running → say "not verified on the live stack" and why.

**In a parallel-task worktree** (`cc-telemetry-<name>`, `skills/parallel-task`) there is no `.env`
and no stack: the live stack runs from the main folder `<main>` and serves its views and
dashboards. Never `docker compose` from the worktree (the hook blocks it). Use the main folder's
helpers on the worktree's files:

| Changed in `<wt>` | Check |
| --- | --- |
| `grafana/dashboards/*.json` | JSON parse; `node <main>/claude-context/scripts/check-dashboard.js --dashboards <wt>/grafana/dashboards` — queries run against the live views; a uid new in the worktree reports `not provisioned` (expected, say so). The live Grafana shows the main folder's files: layout is not visible until merge |
| `clickhouse/views.sql` | never applied from the worktree (the live stack holds one version of the views; the main folder's dashboards read them). Run the changed view's `SELECT` body (with `cc.` names of unchanged views) through `wsl -d Ubuntu -- bash <main as /mnt/c/...>/linux-server-tools/ch.sh`; panels that need the new columns: "verified after merge" |
| `docs/`, `mkdocs.yml` | strict build from `<wt>` with the main folder's interpreter: `<main>/.venv/Scripts/python.exe -m mkdocs build --strict -d <scratchpad>/site` |
| collector, compose, setup scripts | static checks only (parser, `bash -n`, client scripts on scratchpad copies); live run after merge |

Say which checks wait for the merge; after the merge they run in the main folder as above.

**Raw events without the server** (what a Claude Code version sends). The user `settings.json`
env overrides process env, so skip user settings (PowerShell, from a scratchpad folder):
`$env:CLAUDE_CODE_ENABLE_TELEMETRY="1"; $env:OTEL_LOGS_EXPORTER="console"; $env:OTEL_METRICS_EXPORTER="none"; $env:OTEL_LOG_TOOL_DETAILS="1"; claude -p "<task>" --setting-sources local --model haiku *> "<scratchpad>\otel-console.log"`
(add `$env:OTEL_LOG_USER_PROMPTS="1"` to see prompt/response text). One short paid request.
