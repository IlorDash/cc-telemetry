# Telemetry data — what Claude Code sends and the cc.* views

Events and attributes as they arrive (verified on Claude Code 2.1.323), and how the views turn
them into rows the dashboard reads.

## Files

| Path | Role |
| --- | --- |
| `clickhouse/views.sql` | `CREATE DATABASE cc` + six `CREATE OR REPLACE VIEW` |
| `clickhouse/init-views.sh` | waits up to 10 min for `otel.otel_logs`, then applies `views.sql` |
| `client/user-settings.env.json`, `client/project-settings.local.env.json` | the client env keys (templates) |

## Client env → what is sent

| Key | Effect |
| --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY=1` | telemetry on |
| `OTEL_LOGS_EXPORTER` / `OTEL_METRICS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`, `OTEL_EXPORTER_OTLP_ENDPOINT` | where to |
| `OTEL_LOG_USER_PROMPTS=1` | prompt text **and** Claude's reply text (no separate switch); else both `<REDACTED>` |
| `OTEL_LOG_TOOL_DETAILS=1` | `tool_input` / `tool_parameters`: paths, patterns, Bash commands (never file contents or tool output) |
| `OTEL_LOGS_EXPORT_INTERVAL=2000` | client batches ≤ 2 s |
| `OTEL_RESOURCE_ATTRIBUTES=project=…,host=…` | the only source of `project`/`host`; project file value replaces the user one entirely |

Settings are read at session start: running sessions must be restarted. The user `settings.json`
env overrides process env; `--settings <file>` with `env` did not override it in a test.

## Events (`LogAttributes['event.name']`)

Claude Code ≥ 2.1.310 is required: older versions do not put `agent_id` on `tool_result`,
`tool_decision` and subagent hook events, so tool calls cannot be attributed to agents.

Every event: `session.id`, `prompt.id`, `user.email`, `user.account_uuid`, `user.id`,
`organization.id`, `anthropic.plan`, `terminal.type`, `event.sequence`. Subagent events share the
parent `session.id`.

| Event | Key attributes |
| --- | --- |
| `user_prompt` | `prompt`, `prompt_text`, `prompt_length`, `command_name` |
| `api_request` | `model`, `input/output/cache_read/cache_creation_tokens`, `cost_usd`, `duration_ms`, `ttft_ms`, `effort`, `query_source`, `request_id`, `agent_id`, `agent.name`, `skill.name` |
| `assistant_response` | `response` (dropped by the collector), `response_length`, `model`, `request_id` |
| `tool_result` | `tool_name`, `success`, `duration_ms`, `tool_input` (JSON: `file_path`/`notebook_path`/`path`/`pattern`/`command`), `tool_parameters` (`bash_command`), `tool_result_size_bytes`, `request_id`, `tool_use_id`, `agent_id` |
| `tool_decision` | `decision`, `source` (config/hook/user), `tool_name`, `permission_mode` |
| `subagent_completed` | `agent_type`, `agent_id`, `total_tokens`, `total_tool_uses`, `duration_ms`, `model` |
| `skill_activated` | `skill.name`, `skill.source`, `invocation_trigger` |
| `hook_execution_start/complete` | `hook_name`, `hook_event`, `total_duration_ms`, `num_*` |
| startup | `plugin_loaded`, `mcp_server_connection`, `hook_registered`, `managed_settings_resolved`, `retention_sweep` |

`query_source`: `sdk` = main session in the VS Code extension and `claude -p`; `agent:custom` /
`agent:builtin:<Name>` = subagents; others (e.g. `generate_session_title`) are auxiliary. The
interactive terminal CLI value is unverified (expected `repl_main_thread`, already counted as main).
Resource attributes add `service.name=claude-code`, `service.version`, `os.type`, `os.version`.
Metrics: `claude_code.{token.usage,cost.usage,lines_of_code.count,active_time.total,session.count,code_edit_tool.decision}`.

## Views (`cc.*`, plain, read `otel.otel_logs` on every query)

```
cc.events ─┬─ cc.agents    (agent_id → name)
           ├─ cc.requests  (request_id → skill)
           ├─ cc.api_requests  (events + agents)
           ├─ cc.tool_calls    (events + agents + requests)
           └─ cc.sessions
```
- `cc.events`: one row per event with `ServiceName = 'claude-code'`; `project` lower-cased,
  `unknown` when missing; attributes flattened to typed columns (`toUInt64OrZero` etc.).
- `cc.agents`: name = `agent_type` (at completion) → `agent.name` (first request) → `query_source`
  without `agent:<kind>:` → `agent?`.
- `cc.api_requests.actor`: agent name if `agent_id`; `main` if `query_source` is `sdk`, `main` or
  starts with `repl_main`; else `aux:<query_source>`.
- `cc.tool_calls`: `actor` (`main` / agent), `skill` via `request_id`, `op`
  (read/write/search/other), path normalisation: `\` → `/`, lower case, `/c/` → `c:/`; relative to
  the first `/<project>` in the path; worktree folders `<project>-<name>/` fold into the same
  relative path; `area` = first path segment, `claude-context` for `claude-context/` and
  `.claude/`, `external` outside the project.
- `cc.sessions`: per `session_id`: first prompt, prompt/tool/agent/skill counts, cost, tokens,
  start/last event. Empty sessions (prompts = 0, tokens = 0) exist and are filtered by the dashboard.

Apply changes: `wsl -d Ubuntu -- docker compose run --rm views-init`.
