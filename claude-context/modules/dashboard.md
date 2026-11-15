# Dashboards — `grafana/dashboards/*.json`

Seven file-provisioned Grafana dashboards: shared variables and links bar, panels per dashboard,
reserved placeholder ids, drill-down links, the query check script.

## Files

| Path | uid | Title | Content |
| --- | --- | --- | --- |
| `grafana/dashboards/overview.json` | `cc-usage` (kept from the old single dashboard: old bookmarks open it) | Overview | Grafana home page; summary, tokens and cost, placeholders for the upcoming cards |
| `grafana/dashboards/cc-sessions.json` | `cc-sessions` | Sessions | sessions table, prompts of one session |
| `grafana/dashboards/cc-agents.json` | `cc-agents` | Agents & skills | agents, skills |
| `grafana/dashboards/cc-tools.json` | `cc-tools` | Tools & files | tools, files |
| `grafana/dashboards/cc-health.json` | `cc-health` | Health | hook time |
| `grafana/dashboards/cc-prompts.json` | `cc-prompts` | Prompts | placeholder only |
| `grafana/dashboards/cc-tips.json` | `cc-tips` | Tips | placeholder only (`cc.tips` not shown yet) |
| `claude-context/scripts/check-dashboard.js` | — | — | runs every query of every dashboard file + provisioning checks |

Home page: `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` in `docker-compose.yml` → `overview.json`.

## Common to all seven

| Key | Value |
| --- | --- |
| `tags` | `cc`, `claude-code`, `otel` |
| `schemaVersion` | 39 |
| `refresh` / `time` | 10 s / `now-7d` → `now` |
| `templating` | identical in every file (variables below) |
| `timepicker.quick_ranges` | Last 5 minutes, 1 hour, 24 hours, 7 days, 30 days, All (`now-10y`) |
| `links` | one `type: dashboards` link, `tags: ["cc"]`, `keepTime`, `includeVars`, not a dropdown |

- A custom `quick_ranges` list **replaces** Grafana's default one, so every wanted range (short
  ones too) must be listed (observed on Grafana 12.1, 2026-11-15).
- The links bar lists every dashboard tagged `cc` (the current one too) with buttons sorted
  alphabetically by title — Overview is not first (observed on Grafana 12.1, 2026-11-15).
- Changing variables or the time picker → change all seven files the same way.

Grafana re-reads the folder every 30 s (new files too) — edit the files, never save over them from
the UI. Queries use the ClickHouse plugin's SQL editor (`editorType: sql`); `format` 1 = table,
0 = time series.

## Variables (nested, `__all` = All)

| Variable | Query source | Filter |
| --- | --- | --- |
| `project` | `DISTINCT project FROM cc.events` (effective: label, else inferred) | — |
| `session` | `cc.sessions`, newest first, ≤ 300 | project; `prompts > 0 OR tokens > 0` (hides empty sessions) |
| `actor` | `DISTINCT actor FROM cc.api_requests` | project, session |
| `skill` | `DISTINCT skill FROM cc.api_requests`, non-empty | project, session |

Queries are plain strings (`"query": "SELECT ..."`) — the plugin supports that. Every panel filters
with `('${v}' = '__all' OR col = '${v}')` per variable and `$__timeFilter(ts)` (or
`$__fromTime`/`$__toTime`); the plugin expands macros server-side, Grafana substitutes `${v}`.

## Panels per dashboard (panel id: title)

| Dashboard | Rows and panels |
| --- | --- |
| Overview | row 1 Summary (all variables): 2 Cost, 3 Tokens, 4 Sessions (`uniqExact(session_id)` of `cc.api_requests`), 5 Tool calls; row 9 Tokens and cost: 10 Tokens by actor (bar), 11 Cost over time by actor (time series, `$__timeInterval`) |
| Sessions | 7 Sessions table (`session_id` first, empty sessions hidden), 8 Prompts in the selected session |
| Agents & skills | 13 Agents, 14 Skills |
| Tools & files | row 15 Tools: 16 Tool calls by tool, 17 Tools × actor × skill, 18 Bash commands, 19 Rejected tool calls; row 20 Files: 21 Top files, 22 Accesses by area, 23 Top directories, 24 Files re-read within one session |
| Health | 26 Hook time |
| Prompts | 1 text placeholder "Most expensive prompts" |
| Tips | 1 text placeholder "Tips" |

Ids are unique across the seven files. Ids 6, 12, 25 (old section rows) are retired — do not reuse.
Panel 14 joins its two subqueries with `ON` (ClickHouse 22.3/23.3 reject several `USING` joins in
one query); panel 13 has a single `USING` join.

## Overview placeholders (empty `text` panels, fixed id and `gridPos`)

Reserved for the next cards: replace each in place, keep id and position.

| id | Card | gridPos x,y,w,h |
| --- | --- | --- |
| 30 | KPI row | 0,5,24,4 |
| 31 | Daily work | 0,9,12,8 |
| 32 | Daily cache reads | 12,9,12,8 |
| 33 | Cache hit rate | 0,17,12,7 |
| 34 | Tokens by project | 12,17,12,7 |
| 35 | Model share (donut) | 0,24,8,9 |
| 36 | Top tools | 8,24,16,9 |
| 37 | Recent sessions | 0,33,24,9 |
| — | row 9 + panels 10, 11 | y 42–51 |
| 38 | Active sessions | 0,52,12,7 |
| 39 | Coding rhythm (heatmap) | 12,52,12,7 |
| 40 | Cost vs subscription | 0,59,12,6 |
| 41 | Tips counter | 12,59,12,6 |
| 42 | row "What do these numbers mean?", collapsed | 0,65,24,1 |
| 43 | its content (inside row 42) | 0,66,24,8 |

## Drill-down links (no slug; carry all `var-*` and `${__url_time_range}`)

| From | To |
| --- | --- |
| 7 `session_id` | `/d/cc-sessions?var-project=${__data.fields.project}&var-session=${__value.raw}&var-actor=$__all&var-skill=$__all` |
| 13 agent | `/d/cc-agents?…&var-actor=${__value.raw}` (other vars kept) |
| 14 skill | `/d/cc-agents?…&var-skill=${__value.raw}` (other vars kept) |

`cc.tips.link` targets: `modules/telemetry-data.md`.

## Check script — `claude-context/scripts/check-dashboard.js`

```
node claude-context/scripts/check-dashboard.js [--project p] [--session id] [--actor a] [--skill s]
     [--from now-24h] [--url http://localhost:3000]        (repo root; reads the Grafana password from .env)
  provisioning: /api/dashboards/uid/<uid> for every file; /api/dashboards/home uid = cc-usage
  queries:      every query variable + panel target of every file via /api/ds/query, named "<uid> ..."
  last line:    "all ok (<n> queries + <m> provisioning checks)" or "<k> FAILED (of ...)"; exit 0 / 1
```

## Not used (decided 2026-11-15)
- Grafana 12.1 tabs / dynamic dashboards: experimental, need schema v2 (Kubernetes format) — new
  views go into more panels or a separate dashboard file, not tabs.
- Business Text plugin: built-in Stat/Table suffice; its 6.2.3+ needs Grafana ≥ 12.3.

## Known limits
- Panel 7 shows `first_prompt` (≤ 120 chars) as the session title: real titles are not in telemetry.
- Summary "Sessions" counts sessions with a model request; panel 7 also keeps sessions with a
  prompt but no request (rare).
- Prompt text exists only when the client sets `OTEL_LOG_USER_PROMPTS`; otherwise `<REDACTED>`.
