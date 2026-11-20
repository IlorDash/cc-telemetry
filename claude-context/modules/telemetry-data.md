# Telemetry data — what Claude Code sends and the cc.* views

Events and attributes as they arrive (verified on Claude Code 2.1.323 on Windows; Claude Code
2.1.x on Linux sends the same events, reported 2026-11-15), and how the views turn them into
rows the dashboard reads.

## Files

| Path | Role |
| --- | --- |
| `clickhouse/views.sql` | `CREATE DATABASE cc` + twelve `CREATE OR REPLACE VIEW` (order matters: a view must exist before one reading it) |
| `clickhouse/init-views.sh` | waits up to 10 min for `otel.otel_logs`, then applies `views.sql` |
| `client/user-settings.env.json`, `client/project-settings.local.env.json` | the client env keys (templates) |

## Client env → what is sent

| Key | Effect |
| --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY=1` | telemetry on |
| `OTEL_LOGS_EXPORTER` / `OTEL_METRICS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`, `OTEL_EXPORTER_OTLP_ENDPOINT` | where to |
| `OTEL_LOG_USER_PROMPTS=1` | prompt text **and** Claude's reply text (no separate switch); else both `<REDACTED>` |
| `OTEL_LOG_TOOL_DETAILS=1` | `tool_input` / `tool_parameters`: paths, patterns, Bash commands (never file contents or tool output); also the input of project inference |
| `OTEL_LOGS_EXPORT_INTERVAL=2000` | client batches ≤ 2 s |
| `OTEL_RESOURCE_ATTRIBUTES=project=…,host=…` | the only source of `host` and of the explicit project label; project file value replaces the user one entirely |

Settings are read at session start: running sessions must be restarted. The user `settings.json`
env overrides process env; `--settings <file>` with `env` did not override it in a test.
Claude Code does not send its working directory, session title or git branch: the client hook
does (next section).

## Session meta (client hook, not Claude Code)

One OTLP log record per changed session, posted by `<settings dir>/cc-telemetry/session-meta.{ps1,sh}`
(written by the client scripts, `modules/setup-scripts.md`) to `:4318/v1/logs`.

| Field | Value |
| --- | --- |
| resource | `service.name=cc-session-meta`, `host=<PcName>` |
| `event.name` / body | `session_meta` |
| `session.id` | session JSONL file name without `.jsonl` |
| `title`, `title_source` | last `customTitle` (`custom`) over last `aiTitle` (`ai`), else `''` |
| `git_branch` | last `gitBranch` in the file |
| `cwd` | first `cwd` in the file |
| `cc_version` | last `version` (digits and dots); not part of the change hash |

Observed on Claude Code 2.1.323 CLI and 2.1.325 VS Code extension, 2026-11-16:
- JSONL file name = telemetry `session.id`; JSONL `requestId` = telemetry `request_id`.
- `ai-title` lines are written repeatedly with the same value; `custom-title` appears after
  `/rename`; `gitBranch` and `cwd` sit on user/assistant lines. The title exists only after the
  first answer.
- `UserPromptSubmit` stdin: `session_id`, `transcript_path`, `cwd`, `prompt_id`, `prompt`,
  `permission_mode`, `hook_event_name`. `SessionStart` has `source` `startup` / `resume`.
- `"async": true` works. `settings.json` `env` reaches hooks, but `OTEL_*` variables are stripped
  (hence server and PC name as hook arguments).
- `/rename` does not fire `UserPromptSubmit`, and no hook event exists for title changes: a rename
  arrives with the next prompt (confirmed end to end on a test client).

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
| `tool_result` | `tool_name`, `success`, `duration_ms`, `tool_input` (JSON: `file_path`/`notebook_path`/`path`/`pattern`/`command`), `tool_parameters` (`bash_command`: first word only, e.g. `git`; reported 2026-11-15), `tool_result_size_bytes`, `request_id`, `tool_use_id`, `agent_id` |
| `tool_decision` | `decision`, `source` (config/hook/user), `tool_name`, `permission_mode` |
| `at_mention` | `mention_type`, `success`; **no path**: an `@` file is inlined without a tool call, so it never feeds project inference |
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
cc.events_raw ─┬─ cc.path_roots ─► cc.session_project   (+ explicit labels from events_raw)
cc.session_meta┘ (cwd)
cc.events_raw ─┬─ cc.events  = events_raw LEFT JOIN session_project (effective project)
               ├─ cc.agents    (agent_id → name)
               └─ cc.requests  (request_id → skill)
cc.events ─┬─ cc.api_requests  (events + agents)
           ├─ cc.tool_calls    (events + agents + requests)
           ├─ cc.sessions      (+ LEFT JOIN cc.session_meta)
           └─ cc.prompts
cc.tips ◄── cc.api_requests, cc.tool_calls, cc.events, cc.events_raw   (last 7 days)
```
- `ServiceName` is filtered in exactly two views: `cc.events_raw` (`claude-code`) and
  `cc.session_meta` (`cc-session-meta`); every other view reads one of them.
- `cc.events_raw`: one row per Claude Code event; `project_label` lower-cased, `unknown` when
  missing; attributes flattened to typed
  columns (`toUInt64OrZero` etc.); last two `result_bytes` (`tool_result_size_bytes`) and
  `ttft_ms`, passed on to `cc.events` via `e.*`.
- `cc.session_meta` (defined right after `events_raw`, because `path_roots` reads it): per
  `session_id` the latest value (`argMax(…, Timestamp)`) of `title`, `title_source`, `git_branch`,
  `cwd`, `host`, `cc_version`, plus `updated`; only `event.name = 'session_meta'`, non-empty id.
- `cc.path_roots`: per `tool_result` with a path (`file_path` → `notebook_path` → `path`), plus
  per session with a `cc.session_meta.cwd` (`from_cwd = 1`, treated as a directory path):
  `session_id`, `cand` = candidate project folder, `from_cwd`. Path normalised (`\` → `/`, lower case,
  `/c/` → `c:/`, `/mnt/<d>/` accepted); `cand` = first segment after an optional home
  (`users/<u>/`, `home/<u>/`, `root/`) and any run of container folders (`documents`, `projects`,
  `src`, `dev`, `work`, `repos`, `github`, `desktop`, `downloads`, `onedrive`, `onedrive - *`, ...).
  Dropped: hidden folders, temp/system/AppData/`node_modules` names, files directly in a
  container. The regex and the `IN` stop list must stay in step.
- `cc.session_project`: per session the `cwd` folder if any, else the most frequent `cand` (ties:
  name order); so the effective project = label > cwd folder > path heuristic. A folder
  `<n>-<x>` (worktree) folds into the longest known `<n>` — known = any `cand` or explicit label.
  Limits: pending-bugs.md.
- `cc.events`: `cc.events_raw` minus `project_label`, plus `project` = label if not `unknown`,
  else `cc.session_project.project`, else `unknown` (`LEFT JOIN … ON session_id`). Computed per
  query, so old sessions get a project too.
- `cc.agents`, `cc.requests` read `cc.events_raw` (no project needed).
- `cc.agents`: name = `agent_type` (at completion) → `agent.name` (first request) → `query_source`
  without `agent:<kind>:` → `agent?`.
- `cc.api_requests.actor`: agent name if `agent_id`; `main` if `query_source` is `sdk`, `main` or
  starts with `repl_main`; else `aux:<query_source>`.
- `cc.tool_calls`: `actor` (`main` / agent), `skill` via `request_id`, `op`
  (read/write/search/other), path normalisation: `\` → `/`, lower case, `/c/` → `c:/`; relative to
  the first `/<project>` in the path; worktree folders `<project>-<name>/` fold into the same
  relative path; `area` = first path segment, `claude-context` for `claude-context/` and
  `.claude/`, `external` outside the project.
- `cc.sessions`: per `session_id`: first prompt, prompt/tool/agent/skill/`requests` counts, cost,
  tokens, start/last event; `title`, `title_source`, `git_branch`, `cwd` from `cc.session_meta`
  (`''` when the client sent none). Empty sessions (no request) exist; the dashboard keeps
  `requests > 0`.
- `cc.prompts`: per (`session_id`, `prompt_id`): the prompt text and everything it triggered
  (requests incl. subagent/aux, cost, input/output/cache tokens, tool calls, `max_result_bytes`,
  agents); rows without a prompt, request or tool result are dropped. Sums add up to `cc.sessions`.

## `cc.tips` — usage tips

`UNION ALL` of rules over `now() - INTERVAL 7 DAY` (fixed; ignores the dashboard range and
variables). Columns: `category`, `title`, `body`, `scope` (project / agent type / hook), `metric`
(Float64), `link` (relative, no slug, one evidence panel full-screen via `viewPanel=panel-<id>`,
variables preset; always has a query string — the dashboards append `&` + the time range).
Shown on the Tips dashboard and the Overview tiles 58/59 (`modules/dashboard.md`). Thresholds
are first guesses, meant to be tuned.

| category | link target |
| --- | --- |
| `cache` | `/d/cc-usage` panel 57, `var-project` |
| `repeated-read` | `/d/cc-tools` panel 24, `var-project` |
| `big-results` | `/d/cc-tools` panel 140, `var-project` |
| `short-opus` | `/d/cc-prompts` panel 180, `var-project` |
| `agent-outlier` | `/d/cc-sessions` panel 100, `var-session` (biggest run), `var-actor` |
| `denials` | `/d/cc-tools` panel 19, `var-project` |
| `slow-hook` | `/d/cc-health` panel 26 |
| `slow-ttft` | `/d/cc-health` panel 161, `var-project` |

These panel ids are fixed: renumbering one breaks its tip link.

| category | Source | Fires when (grouped by) | metric |
| --- | --- | --- | --- |
| `cache` | `cc.api_requests` | cache read / (read + input + creation) < 40 %, ≥ 20 requests (project) | hit % |
| `repeated-read` | `cc.tool_calls` | `op = 'read'`, same `path` > 10 times (project, path) | count |
| `big-results` | `cc.events` | ≥ 5 `tool_result` with `result_bytes` > 200000 (project) | count |
| `short-opus` | `cc.api_requests` | model contains `opus`: ≥ 20 answers < 500 output tokens and ≥ half of all (project) | their `cost_usd` |
| `agent-outlier` | `cc.events` | `subagent_completed`: max > 6 × mean and > 50k tokens, ≥ 3 runs (agent_type); link = session of the biggest run | max tokens |
| `denials` | `cc.events` | `tool_decision` `reject` ≥ 5 (project, tool); body names the top `decision_source` | count |
| `slow-hook` | `cc.events_raw` | `hook_execution_complete` mean > 500 ms, ≥ 10 runs (hook_name) | mean ms |
| `slow-ttft` | `cc.events` | `api_request` mean `ttft_ms` > 3000, ≥ 10 requests (project, model) | mean ms |

- Savings come from `cost_usd` only — no price table; the `short-opus` metric is an upper bound.
- **No repeated-Bash rule, on purpose:** `bash_cmd` holds only the first word (`cd`, `git`), so
  counting it is noise. Do not add one while Claude Code sends only that.

Apply changes: `wsl -d Ubuntu -- docker compose run --rm views-init`.
