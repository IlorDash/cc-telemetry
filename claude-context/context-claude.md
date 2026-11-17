# cc-telemetry — navigation hub

Local Claude Code usage statistics: clients export OTLP events, the server stores them in
ClickHouse and shows them in Grafana. Everything stays on the LAN. Single branch `main`, remote `origin`.

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
| actor | who made a model request / tool call: `main`, an agent name, or `aux:<query_source>` |
| skill attribution | tool call → skill via `tool_result.request_id` → `api_request.skill.name` |
| keepalive | hidden `wsl.exe --exec sleep infinity` that keeps the WSL distro (and Docker) running |
| empty session | startup-only `session.id` from a VS Code extension process: no prompt, no request; hidden on the dashboard |
| update | `setup-server.sh --update`: safety dump + row counts, `git pull --ff-only`, re-run, restart of collector/Grafana when their config changed, row-count check |
| old ARM | `aarch64` without `lrcpc` (Raspberry Pi 4): only ClickHouse ≤ 22.3 runs → `CLICKHOUSE_VERSION=22.3.20.29` |

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
cc.tips (usage tips, last 7 days; Tips dashboard + Overview tiles) ← the views above
   │ grafana-clickhouse-datasource (uid clickhouse, native :9000, user otel)
   ▼
Grafana :3000 (host port GRAFANA_PORT)  7 dashboards, shared variables + links bar:
   Overview (uid cc-usage, home page), cc-sessions, cc-agents, cc-tools, cc-health,
   cc-prompts, cc-tips
```

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
- The README is public: no personal data, no experience specific to the user's PCs.

## Module map

| Module file | Covers |
| --- | --- |
| `modules/stack.md` | `docker-compose.yml`, `otel-collector.yaml`, `.env`, ClickHouse tables, versions and resource limits (`clickhouse/{config,users}.d/`), Grafana provisioning, ports |
| `modules/telemetry-data.md` | events and attributes Claude Code sends, session-meta records of the client hook, `clickhouse/views.sql` (incl. `cc.tips` rules), `clickhouse/init-views.sh` |
| `modules/dashboard.md` | `grafana/dashboards/*.json` (7 dashboards): uids, shared variables and links bar, panels, fixed panel ids, drill-down links, `check-dashboard.js` |
| `modules/setup-scripts.md` | `setup-server.ps1`, `setup-server.sh` (incl. `--update`), `client/setup-client.{ps1,sh}` (incl. the session-meta hook), `client/*.json`, `linux-server-tools/*.sh`, keepalive, LAN access |

## Key conventions (details in `guides/`, index in CLAUDE.md)

- Views are plain, not materialized: editing `views.sql` and re-running
  `docker compose run --rm views-init` recomputes all history; no migrations.
- Dashboards are file-provisioned: Grafana re-reads `grafana/dashboards/` every 30 s; edit the files, not the UI.
- Views and dashboard queries must run on ClickHouse 22.3 through 25.8: no multiple `USING` joins.
- Scripts run on stock Windows PowerShell 5.1: ASCII only, `setup-server.ps1` uses
  `$ErrorActionPreference = 'Continue'` + `$LASTEXITCODE` checks, JSON written without BOM.
  Bash scripts: `set -euo pipefail`.
- `.sh/.sql/.yaml` are LF (`.gitattributes`); they run inside Linux containers.
- Every change is checked on the live stack (`guides/verification.md`) before it is reported done.

## Ledger

`pending-bugs.md` — suspected bugs and unverified behaviour, grouped by area. reviewer adds,
developer removes what it fixes, context-auditor prunes on a requested audit.
