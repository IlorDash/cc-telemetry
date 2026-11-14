# cc-telemetry — navigation hub

Local Claude Code usage statistics: clients export OTLP events, the server stores them in
ClickHouse and shows them in Grafana. Everything stays on the LAN. Single branch `main`, no remote.

## Glossary

| Term | Meaning |
| --- | --- |
| client | a PC whose Claude Code sessions are recorded; configured per user by `client/setup-client.ps1` |
| server | the PC running the Docker stack; configured by `setup-server.ps1` |
| desktop / wsl mode | Docker Desktop vs Docker Engine inside a WSL2 distro (`setup-server.ps1 -Mode`) |
| event | one OTLP log record from Claude Code, `LogAttributes['event.name']` (`api_request`, `tool_result`, ...) |
| `project`, `host` | resource attributes the client sets via `OTEL_RESOURCE_ATTRIBUTES`; not sent by Claude Code itself |
| actor | who made a model request / tool call: `main`, an agent name, or `aux:<query_source>` |
| skill attribution | tool call → skill via `tool_result.request_id` → `api_request.skill.name` |
| keepalive | hidden `wsl.exe --exec sleep infinity` that keeps the WSL distro (and Docker) running |
| empty session | startup-only `session.id` from a VS Code extension process: no prompt, no request; hidden on the dashboard |

## Data flow

```
Claude Code (client, env from ~/.claude/settings.json + <project>/.claude/settings.local.json)
   │ OTLP gRPC :4317 (no auth; LAN only)            [wsl mode: portproxy <LAN_IP>:4317 → 127.0.0.1:4317]
   ▼
otel-collector  memory_limiter → attributes/drop_response → batch
   │ clickhouse exporter, create_schema: true
   ▼
ClickHouse  otel.otel_logs (events), otel.otel_metrics_* (metrics, unused by the dashboard)
   │ plain views (recomputed on every query), created by the one-shot views-init
   ▼
cc.events → cc.agents, cc.requests → cc.api_requests, cc.tool_calls, cc.sessions
   │ grafana-clickhouse-datasource (uid clickhouse, native :9000, user otel)
   ▼
Grafana :3000  dashboard uid cc-usage (home page)
```

## Boundaries

- Claude Code decides what is sent; the stack can only drop or reinterpret it. What arrives:
  `modules/telemetry-data.md`.
- Telemetry is live only: no backfill from `~/.claude/projects` transcripts; events produced while
  the server is unreachable are lost after a short client retry.
- Session titles (`/rename` → `custom-title`, `ai-title`) are not in telemetry.
- Ports exposed beyond `localhost`: 4317 only (with `-EnableLan`). 3000, 4318 and ClickHouse stay local.
- The README is public: no personal data, no experience specific to the user's PCs.

## Module map

| Module file | Covers |
| --- | --- |
| `modules/stack.md` | `docker-compose.yml`, `otel-collector.yaml`, `.env`, ClickHouse tables, Grafana provisioning, ports |
| `modules/telemetry-data.md` | events and attributes Claude Code sends, `clickhouse/views.sql`, `clickhouse/init-views.sh` |
| `modules/dashboard.md` | `grafana/dashboards/cc-usage.json`: variables, panels, drill-down links |
| `modules/setup-scripts.md` | `setup-server.ps1`, `client/setup-client.ps1`, `client/*.json`, `linux-server-tools/*.sh`, keepalive, LAN access |

## Key conventions (details in `guides/`, index in CLAUDE.md)

- Views are plain, not materialized: editing `views.sql` and re-running
  `docker compose run --rm views-init` recomputes all history; no migrations.
- Dashboard is file-provisioned: Grafana re-reads `cc-usage.json` every 30 s; edit the file, not the UI.
- Scripts run on stock Windows PowerShell 5.1: ASCII only, `$ErrorActionPreference = 'Continue'`
  + `$LASTEXITCODE` checks, JSON written without BOM.
- `.sh/.sql/.yaml` are LF (`.gitattributes`); they run inside Linux containers.
- Every change is checked on the live stack (`guides/verification.md`) before it is reported done.

## Ledger

`pending-bugs.md` — suspected bugs and unverified behaviour, grouped by area. reviewer adds,
developer removes what it fixes, context-auditor prunes on a requested audit.
