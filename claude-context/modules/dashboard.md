# Dashboards — `grafana/dashboards/*.json`

Seven file-provisioned Grafana dashboards: shared variables and links bar, panels per dashboard,
fixed panel ids, drill-down links, the query check script.

## Files

| Path | uid | Title | Content |
| --- | --- | --- | --- |
| `grafana/dashboards/overview.json` | `cc-usage` (kept from the old single dashboard: old bookmarks open it) | Overview | Grafana home page; KPIs, daily tokens, cache, projects, models, tools, recent/active sessions, rhythm, plan, tips tiles |
| `grafana/dashboards/cc-sessions.json` | `cc-sessions` | Sessions | sessions table, prompts, timeline and cumulative cost/tokens of one session |
| `grafana/dashboards/cc-agents.json` | `cc-agents` | Agents & skills | agents, skills, main vs subagents, subagent outliers |
| `grafana/dashboards/cc-tools.json` | `cc-tools` | Tools & files | tools, files, results and errors |
| `grafana/dashboards/cc-health.json` | `cc-health` | Health | hook time, API latency, tool duration and errors |
| `grafana/dashboards/cc-prompts.json` | `cc-prompts` | Prompts | most expensive prompts (`cc.prompts`), one prompt in detail |
| `grafana/dashboards/cc-tips.json` | `cc-tips` | Tips | `cc.tips` counts and table |
| `claude-context/scripts/check-dashboard.js` | — | — | runs every query of every dashboard file + provisioning checks |

Home page: `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` in `docker-compose.yml` → `overview.json`.

## Common to all seven

| Key | Value |
| --- | --- |
| `tags` | `cc`, `claude-code`, `otel` |
| `schemaVersion` | 39 |
| `refresh` / `time` | 5 m / `now-24h` → `now` (Grafana refuses intervals below 1 m: `GF_DASHBOARDS_MIN_REFRESH_INTERVAL`) |
| `templating` | the four shared variables below, identical in every file; Overview adds `plan_monthly`, Prompts adds `prompt` |
| `timepicker.quick_ranges` | Last 5 minutes, 1 hour, 24 hours, 7 days, 30 days, All (`now-10y`) |
| `links` | one `type: dashboards` link, `tags: ["cc"]`, `keepTime`, `includeVars`, not a dropdown |

- A custom `quick_ranges` list **replaces** Grafana's default one, so every wanted range (short
  ones too) must be listed (observed on Grafana 12.1, 2026-11-15).
- The links bar lists every dashboard tagged `cc` (the current one too) with buttons sorted
  alphabetically by title — Overview is not first (observed on Grafana 12.1, 2026-11-15).
- Changing the shared variables or the time picker → change all seven files the same way.

Grafana re-reads the folder every 30 s (new files too) — edit the files, never save over them from
the UI. Queries use the ClickHouse plugin's SQL editor (`editorType: sql`); `format` 1 = table,
0 = time series.

## Variables (nested, `__all` = All)

| Variable | Query source | Filter |
| --- | --- | --- |
| `project` | `DISTINCT project FROM cc.events` (effective: label, else inferred) | — |
| `session` | `cc.sessions`, newest first, ≤ 300; two columns: `session_id` (value), `"<title ≤ 60> (<id 8>)"` or the id (text) | project; `requests > 0` (hides empty sessions) |
| `actor` | `DISTINCT actor FROM cc.api_requests` | project, session |
| `skill` | `DISTINCT skill FROM cc.api_requests`, non-empty | project, session |
| `plan_monthly` (Overview) | custom `0,20,100,200`, label "Plan, USD/month" | — |
| `prompt` (Prompts) | `cc.prompts` by cost, ≤ 300; `__text` = cost + prompt start (or `prompt <id 8>`), `__value` = `prompt_id` | project, session |

- A two-column variable query: the plugin (4.23.5) takes the first column as value and the second
  as text.
- Queries are plain strings (`"query": "SELECT ..."`) — the plugin supports that. Every panel
  filters with `('${v}' = '__all' OR col = '${v}')` per variable and `$__timeFilter(ts)` (or
  `$__fromTime`/`$__toTime`); the plugin expands macros server-side, Grafana substitutes `${v}`.
- Displayed text is cut with `leftUTF8` (never `left`/`substring`, which split a Cyrillic
  character); `left` only on ASCII ids.

## Panels per dashboard (panel id: title)

| Dashboard | Rows and panels |
| --- | --- |
| Overview | row 1 Summary (all variables): 30 Sessions (`uniqExact(session_id)` of `cc.api_requests`), 51 Turns (actor `main`), 52 Input, 53 Output, 54 Cache read, 55 Cache create, 56 Cost; 31 Daily work, 32 Daily cache reads; 33 Cache hit rate, 57 Cache hit rate by project, 34 Tokens by project; 35 Model share (pie), 36 Top tools; 37 Recent sessions (10); row 9 Tokens and cost: 10 Tokens by actor (bar), 11 Cost over time by actor; 38 Active sessions (last 15 min, LIVE < 2 min / IDLE), 39 Coding rhythm (weekday × hour table); 40 Last 30 days: API equivalent vs plan (`${plan_monthly}`); 58 Tips (last 7 days), 59 Most frequent tip; row 42 "What do these numbers mean?" (collapsed) with text 43 |
| Sessions | 7 Sessions table, 8 Prompts in the selected session, 100 Session timeline (prompts, requests, tool calls), 101 Cumulative cost, 102 Cumulative tokens |
| Agents & skills | 13 Agents, 14 Skills, 120 Main vs subagents by tool, 121 Subagent outliers (max vs mean tokens) |
| Tools & files | row 15 Tools: 16 Tool calls by tool, 17 Tools × actor × skill, 18 Bash commands, 19 Rejected tool calls; row 20 Files: 21 Top files, 22 Accesses by area, 23 Top directories, 24 Files re-read within one session; row 143 Results and errors: 140 Largest tool results, 141 Error rate by tool, 142 Result size by tool |
| Health | 26 Hook time, 160 API latency by model, 161 Time to first token by day (p50/p95), 162 Request duration by day, 163 Tool duration and errors, 164 Tool errors by day, 165 Recent failed tool calls |
| Prompts | 180 Most expensive prompts, 181 Selected prompt, 182 Model requests of the selected prompt, 183 Tool calls of the selected prompt |
| Tips | 200 Tips right now, 201 Tips by category, 202 Usage tips table |

- Panels 7 and 37: `name` = `title` if set, else the first prompt (`leftUTF8`, 120 / 100 chars),
  plus `git_branch`; both keep `requests > 0` sessions started in the range.
- Panels 8, 100, 101, 102 need one selected session (`'${session}' != '__all'`); 101/102 show the
  `noValue` hint "Select a session in the Session variable above".
- Stats 58/59 read `cc.tips` (fixed last 7 days, no variables): 58 = count, 59 = most frequent
  category `(n)` or `none`; explicit text sizes (`titleSize`/`valueSize`); both one-click links
  to `/d/cc-tips`.

## Fixed panel ids

- Ids are unique across the seven files. Ids 6, 12, 25 (old section rows) and 41 (removed tips
  table) are retired — do not reuse.
- `cc.tips.link` opens panels 19, 24, 26, 57, 100, 140, 161, 180 via `viewPanel=panel-<id>`
  (`modules/telemetry-data.md`): never renumber them.
- Panel 14 joins its two subqueries with `ON` (ClickHouse 22.3/23.3 reject several `USING` joins in
  one query); panel 13 has a single `USING` join; every other join uses `ON`.

## Drill-down links (no slug; carry all `var-*` and `${__url_time_range}`)

| From | To |
| --- | --- |
| 7 `session_id`, 37 `session_id` (`:percentencode`) | `/d/cc-sessions?var-project=${__data.fields.project}&var-session=${__value.raw}&var-actor=$__all&var-skill=$__all` |
| 34 `project` | `/d/cc-usage?var-project=${__value.raw}`, other vars `$__all` |
| 13 agent | `/d/cc-agents?…&var-actor=${__value.raw}` (other vars kept) |
| 14 skill | `/d/cc-agents?…&var-skill=${__value.raw}` (other vars kept) |
| 180 `prompt_id` | `/d/cc-prompts?var-project=…&var-prompt=${__value.raw}`, session/actor/skill `$__all` |
| 180, 181 `session_id` | `/d/cc-sessions` as from panel 7 |
| 202 `title` | `${__data.fields.open}` = `cc.tips.link` + `&` (+ `var-project=%24__all&` for `/d/cc-sessions`) + time range |
| 58, 59 | `/d/cc-tips?${__url_time_range}` |

## Check script — `claude-context/scripts/check-dashboard.js`

```
node claude-context/scripts/check-dashboard.js [--project p] [--session id] [--actor a] [--skill s]
     [--from now-24h] [--url http://localhost:3000]        (repo root; reads the Grafana password from .env)
  provisioning: /api/dashboards/uid/<uid> for every file; /api/dashboards/home uid = cc-usage
  queries:      every query variable + panel target of every file via /api/ds/query, named "<uid> ..."
                other variables (plan_monthly, prompt) take their current value / All / first option
  last line:    "all ok (<n> queries + <m> provisioning checks)" or "<k> FAILED (of ...)"; exit 0 / 1
```

## Not used (decided 2026-11-15)
- Grafana 12.1 tabs / dynamic dashboards: experimental, need schema v2 (Kubernetes format) — new
  views go into more panels or a separate dashboard file, not tabs.
- Business Text plugin: built-in Stat/Table suffice; its 6.2.3+ needs Grafana ≥ 12.3.

## Known limits
- Session titles and branches exist only for clients with the session-meta hook, and only after
  the first answer; otherwise panels 7/37 and the Session dropdown fall back to the first prompt
  / the id. A `/rename` shows after the next prompt.
- Summary "Sessions" counts sessions with a model request; panels 7/37 and the Session variable
  use the same rule (`requests > 0`).
- Prompt text exists only when the client sets `OTEL_LOG_USER_PROMPTS`; otherwise `<REDACTED>`.
