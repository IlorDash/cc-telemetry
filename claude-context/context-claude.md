# cc-telemetry — navigation hub

Local Claude Code usage statistics: clients export OTLP events, the server stores them in
ClickHouse and shows them in Grafana. Everything stays on the LAN. Default branch `main`, remote `origin`.
Branch flow: feature branches → `develop` → `main`; the user guide site publishes from `main` only.

## Glossary

| Term | Meaning |
| --- | --- |
| client | a PC whose Claude Code sessions are recorded; configured per user by `client/setup-client.ps1` (Windows) or `client/setup-client.sh` (Linux) |
| server | the PC running the Docker stack; configured by `setup-server.ps1` (Windows) or `setup-server.sh` (Linux) |
| desktop / wsl mode | Windows only: Docker Desktop vs Docker Engine inside a WSL2 distro (`setup-server.ps1 -Mode`) |
| event | one OTLP log record from Claude Code, `LogAttributes['event.name']` (`api_request`, `tool_result`, ...) |
| `project`, `host` | resource attributes the client sets via `OTEL_RESOURCE_ATTRIBUTES`; not sent by Claude Code itself |
| project label / effective project | `project_label` = the explicit `project=` attribute; `project` = label, else inferred (`cc.session_project`: folder of the session's `cwd`, else tool-call paths), else `unknown` |
| session meta | title, git branch, first `cwd` of a session, read from the local session JSONL by the client hook and sent as OTLP/HTTP logs (`service.name=cc-session-meta`) → `cc.session_meta` |
| account | Claude account of an event: `account_uuid`, shown as `account` (`user.email`, else uuid 8); the Account variable filters by it |
| actor | who made a model request / tool call: `main`, an agent name, or `aux:<query_source>` |
| skill attribution | tool call → skill via `tool_result.request_id` → `api_request.skill.name` |
| keepalive | hidden `wsl.exe --exec sleep infinity` that keeps the WSL distro (and Docker) running |
| empty session | startup-only `session.id` from a VS Code extension process: no prompt, no request; hidden on the dashboard |
| update | `setup-server.sh --update`: safety dump + row counts, `git pull --ff-only`, re-run, restart of collector/Grafana when their config changed, row-count check |
| old ARM | `aarch64` without `lrcpc` (Raspberry Pi 4): only ClickHouse ≤ 22.3 runs → `CLICKHOUSE_VERSION=22.3.20.29` |
| site / guide | public bilingual MkDocs user guide (`docs/<page>.md` + `.ru.md` twin) on GitHub Pages; the detailed user docs (README is only a quick start) |
| version | `VERSION` at the repo root, stamped on the site by `hooks/app_version.py`; one release-notes page per version |
| unreleased marker | `<!-- unreleased` on a release-notes page still in preparation; blocks a PR into `main` (`ci/check-release-markers.sh`) |
| demo stack | `tools/docs-demo/`: throwaway `cc-demo-*` containers with made-up data, the only source of screenshots |

## Data flow

```
Claude Code (client, env from ~/.claude/settings.json + <project>/.claude/settings.local.json)
   │ OTLP gRPC :4317 (no auth; LAN only)            [wsl mode: portproxy <LAN_IP>:<port> → 127.0.0.1:<port>
   │                                                 for 4317 and 4318]
   │ + async UserPromptSubmit hook <settings dir>/cc-telemetry/session-meta.{ps1,sh}:
   │   OTLP/JSON POST :4318/v1/logs, service.name cc-session-meta (title, branch, cwd)
   │                                                [Linux: both published on OTLP_BIND from .env]
   ▼
otel-collector  memory_limiter → attributes/drop_response → batch
   │ clickhouse exporter, create_schema: true
   ▼
ClickHouse  otel.otel_logs (events), otel.otel_metrics_* (metrics, unused by the dashboard)
   │ plain views (recomputed on every query), created by the one-shot views-init
   ▼
cc.events_raw + cc.session_meta → cc.path_roots → cc.session_project → cc.events (effective project)
cc.events_raw → cc.agents, cc.requests;   cc.events → cc.api_requests, cc.tool_calls, cc.prompts,
                                          cc.sessions (+ cc.session_meta: title, branch, cwd)
cc.tips (usage tips, last 7 days; Efficiency Tips section + rail tiles) ← the views above
   │ grafana-clickhouse-datasource (uid clickhouse, native :9000, user otel)
   ▼
Grafana :3000 (host port GRAFANA_PORT)  7 dashboards, shared variables + side rail (grafana/rail/):
   Overview (uid cc-usage, home page), cc-sessions, cc-prompts, cc-efficiency, cc-agents,
   cc-tools, cc-health
```

Docs: `docs/*.md` + `mkdocs.yml` + `VERSION` → GitHub Actions (`.github/workflows/docs.yml`:
strict build on every PR, marker check on PRs into `main`) → GitHub Pages on push to `main`.
Details: `modules/docs-site.md`.

## Boundaries

- Claude Code decides what is sent; the stack can only drop or reinterpret it. What arrives:
  `modules/telemetry-data.md`.
- Telemetry is live only: no backfill of events from `~/.claude/projects` transcripts; events
  produced while the server is unreachable are lost after a short client retry. Only session meta
  can be backfilled (`-ImportHistory` / `--import-history` of the client scripts).
- Session titles (`/rename` → `custom-title`, `ai-title`), git branch and working directory are not
  in Claude Code telemetry: only the client hook sends them, from the session JSONL, with the next
  prompt (no hook event fires on `/rename`). Clients without the hook (manual setup,
  `-NoSessionMeta`) send none; their unlabelled sessions get a project from tool-call paths only.
- Ports beyond `localhost`: Windows — 4317 and 4318 (with `-EnableLan`), Grafana stays local.
  Linux (`setup-server.sh`) — 4317, 4318 and Grafana on the LAN by default, `--local-only` keeps
  them local. ClickHouse is never published beyond the host.
- The README and the site (`docs/`, incl. screenshots) are public: no personal data, no
  experience specific to the user's PCs; screenshots only from the demo stack.

## Module map

| Module file | Covers |
| --- | --- |
| `modules/stack.md` | `docker-compose.yml`, `otel-collector.yaml`, `.env`, ClickHouse tables and versions, Grafana provisioning, ports |
| `modules/telemetry-data.md` | events and attributes Claude Code sends, session-meta records of the client hook, `clickhouse/views.sql` (incl. `cc.tips` rules), `clickhouse/init-views.sh` |
| `modules/dashboard.md` | `grafana/dashboards/*.json` (7 dashboards): uids, shared variables, side rail (`grafana/rail/`), panels, fixed panel ids, drill-down links, `check-dashboard.js` |
| `modules/setup-scripts.md` | `setup-server.ps1`, `setup-server.sh` (incl. `--update`), `client/setup-client.{ps1,sh}` (incl. the session-meta hook), `client/*.json`, `linux-server-tools/*.sh`, keepalive, LAN access |
| `modules/docs-site.md` | `mkdocs.yml`, `docs/` (EN + RU pages, assets, css), `VERSION`, `hooks/app_version.py`, `ci/`, `.github/workflows/docs.yml`, `tools/docs-demo/`, the short `README.md`; page → source map |

## Key conventions (details in `guides/`, index in CLAUDE.md)

- Views are plain, not materialized: editing `views.sql` and re-running
  `docker compose run --rm views-init` recomputes all history; no migrations.
- Dashboards are file-provisioned: Grafana re-reads `grafana/dashboards/` every 30 s; edit the files, not the UI.
  The side rail is edited in `grafana/rail/rail.json` and copied by `node grafana/rail/sync-rail.js`.
  Panel look and grid (Full HD only): `guides/grafana-style.md`.
- Views and dashboard queries must run on ClickHouse 22.3 through 25.8: no multiple `USING` joins.
- Scripts run on stock Windows PowerShell 5.1: ASCII only, `setup-server.ps1` uses
  `$ErrorActionPreference = 'Continue'` + `$LASTEXITCODE` checks, JSON written without BOM.
  Bash scripts: `set -euo pipefail`.
- `.sh/.sql/.yaml` are LF (`.gitattributes`); they run inside Linux containers.
- Every change is checked on the live stack (`guides/verification.md`) before it is reported done.
- User docs live on the site: a behaviour change updates `docs/<page>.md` and its `.ru.md` twin
  (same headings, same order; Grafana titles and script messages stay English), `README.md` only
  when the quick start changes. `mkdocs build --strict` must exit 0 (`modules/docs-site.md`).
- README checks: `skills/docs-update/scripts/check-readme.py`; user-requested README update/audit →
  docs-auditor. Whole-branch review before a PR → mr-reviewer (PR review gate of the
  `mr-description` skill; drafts in git-ignored `pull-requests/`). Routing: CLAUDE.md; layout of
  agents/skills: `guides/context-repo.md`.

## Ledger

`pending-bugs.md` — suspected bugs and unverified behaviour, grouped by area. reviewer and
mr-reviewer add, developer removes what it fixes, context-auditor prunes on a requested audit.
