# Dashboards — `grafana/dashboards/*.json`

Seven file-provisioned Grafana dashboards and their generated Russian copies: shared variables,
the side rail, panels per dashboard, fixed panel ids, drill-down links, the RU build, the query
check script. Look of panels (sizes, fonts, titles, colours, grid): `guides/grafana-style.md` —
not repeated here.

## Files

| Path | uid | Title | Content |
| --- | --- | --- | --- |
| `grafana/dashboards/overview.json` | `cc-usage` (kept from the old single dashboard: old bookmarks open it) | Overview | Grafana home page; totals, daily tokens, projects, models, rhythm, tools, recent sessions |
| `grafana/dashboards/cc-sessions.json` | `cc-sessions` | Sessions | sessions table; header, tiles, timeline, cumulative cost and prompts of one session |
| `grafana/dashboards/cc-prompts.json` | `cc-prompts` | Prompts | most expensive prompts (`cc.prompts`), cost buckets, cost per model |
| `grafana/dashboards/cc-efficiency.json` | `cc-efficiency` | Efficiency | Tips (`cc.tips`), where cost goes (work phases), cache; replaced the Tips dashboard (`cc-tips`, deleted) |
| `grafana/dashboards/cc-agents.json` | `cc-agents` | Agents & skills | subagent types, skills, biggest runs |
| `grafana/dashboards/cc-tools.json` | `cc-tools` | Tools & files | calls, rejections, re-reads, big results, Bash, edits |
| `grafana/dashboards/cc-health.json` | `cc-health` | Health | TTFT, hook time, API errors, request duration |
| `grafana/rail/rail.json` | — | — | source of the side rail (not provisioned: Grafana would load any `.json` under `grafana/dashboards/`) |
| `grafana/rail/sync-rail.js` | — | — | copies the rail into every dashboard file, keeps the RU switch link; `--check` writes nothing, exit 1 if any differs |
| `grafana/dashboards/ru/<file>.json` | `<uid>-ru` | Russian title | generated Russian copy of each English file (never edit by hand); Grafana folder `ru` |
| `grafana/i18n/build-ru.js` | — | — | builds `ru/*.json` from the English files + `ru.json`; `--check` writes nothing, exit 1 if any differs |
| `grafana/i18n/ru.json` | — | — | dictionary: `files`, `strings`, `sql.literals`, `sql.fragments` |
| `claude-context/scripts/check-dashboard.js` | — | — | runs every query of every dashboard file + provisioning checks |

Home page: `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` in `docker-compose.yml` → `overview.json`
(English; there is no Russian home).

## Common to all seven

| Key | Value |
| --- | --- |
| `tags` | `cc`, `claude-code`, `otel` |
| `schemaVersion` | 39 |
| `refresh` / `time` | 5 m / `now-24h` → `now` in every file, `ru/` copies too (Grafana refuses intervals below 1 m: `GF_DASHBOARDS_MIN_REFRESH_INTERVAL`) |
| `templating` | the five shared variables below, identical in every file; Sessions adds `extra_cols`, `shown_cols`, `session_header` |
| `timepicker.refresh_intervals` | `1m`, `5m`, `15m`, `1h` (nothing below the 1 m minimum) |
| `timepicker.quick_ranges` | Last 5 minutes, 1 hour, 24 hours, 7 days, 30 days, All (`now-10y`) |
| `links` | only the language switch (`RU` → `/d/<uid>-ru`; the RU copy has `EN` → `/d/<uid>`), `keepTime`, `includeVars` — navigation is the rail; hand-added links are kept |
| layout | rail x0 w3 (ids 300–399); content x3 w21; no `row` panels (section headers are h1 text panels); only Full HD (1920 px) and wider is supported |

- A custom `quick_ranges` list **replaces** Grafana's default one, so every wanted range (short
  ones too) must be listed (observed on Grafana 12.1, 2026-11-15).
- Changing the shared variables or the time picker → change all seven English files the same way,
  then rebuild the RU copies.

Grafana re-reads the folder every 30 s (new files too) — edit the files, never save over them from
the UI. Queries use the ClickHouse plugin's SQL editor (`editorType: sql`); `format` 1 = table,
0 = time series.

## Side rail (`grafana/rail/`)

```
rail.json nav[] (uid, title, hint, idBase) + panels[] (idOffset, gridPos.h)
  └─ node grafana/rail/sync-rail.js   deletes every panel 300–399 of each file, injects the rail
     (x0, w3, stacked from y0), fails on a row panel or a content panel at x < 3, on a uid missing in nav
```

| idOffset | Panel | h | Content |
| --- | --- | --- | --- |
| +0 | text "Dashboards" | 12 | HTML links `/d/<uid>?${__url_time_range}&${__all_variables}`; current item baked in per file |
| +1 | bargauge "Usage · last 5 h" | 4 | per account: cost_usd of the last 5 h as % of its peak rolling 5-h cost in 30 days (10-min steps); accounts with no cost in 7 d hidden |
| +3 | stat "Tips · 7 d" | 3 | `count()` of `cc.tips` → link `/d/cc-efficiency?${__url_time_range}` |
| +2 | stat (no title) | 3 | most frequent `cc.tips` category (readable name, `(n)`, ties alphabetical) or `none`; same link |

- Blocks (`idBase`): Overview 300, Sessions 310, Prompts 320, Efficiency 330, Agents 340, Tools 350,
  Health 360; 370 was Tips — do not reuse. +4/+5 reserved. Panels stack in array order, not idOffset.
- Rail panels ignore the time range and variables (fixed windows in SQL). Edit `rail.json`, then run
  `node grafana/rail/sync-rail.js`; never edit the rail inside a dashboard file.

## Variables (nested, `__all` = All)

| Variable | Query source | Filter |
| --- | --- | --- |
| `account` | `cc.events`: `account_uuid` (value), latest `account` (text: e-mail, else uuid 8); multi, `allValue` `'__all'` (quoted) | — |
| `project` | `DISTINCT project FROM cc.events` (effective: label, else inferred) | account |
| `session` | `cc.sessions`, newest first, ≤ 300; `session_id` (value), `"<title ≤ 60> (<id 8>)"` or the id (text) | account, project; `requests > 0` |
| `actor` | `DISTINCT actor FROM cc.api_requests` | account, project, session |
| `skill` | `DISTINCT skill FROM cc.api_requests`, non-empty | account, project, session |
| `extra_cols` (Sessions, "Columns") | custom multi `none`, `id`, `started`, `account` | — |
| `shown_cols` (Sessions, hidden) | column names of panel 7 minus `session_id`/`started`/`account` unless picked in `extra_cols` | used by panel 7's `filterFieldsByName` |
| `session_header` (Sessions, hidden) | one line for the selected session (name + branch, project, model family, account, id 8, activity time, `LIVE` if last event < 10 min) or "No session selected" | text panel 422 = `$session_header` |

- Filter forms: `('__all' IN (${account:singlequote}) OR account_uuid IN (${account:singlequote}))`,
  `('${v}' = '__all' OR col = '${v}')` per other variable, plus `$__timeFilter(ts)` (or
  `$__fromTime`/`$__toTime`); the plugin expands macros server-side, Grafana substitutes `${v}`.
- A two-column variable query: the plugin (4.23.5) takes the first column as value, the second as text.
- Displayed text is cut with `leftUTF8` (never `left`/`substring`, which split a Cyrillic
  character); `left` only on ASCII ids.

## Panels per dashboard (panel id: title)

| Dashboard | Panels (top to bottom) |
| --- | --- |
| Overview | 401 header; 30 cost_usd, 33 Cache hit rate, 52 Billable tokens, 53 Tool error rate (+ p95 API latency); 31 Daily tokens & cache hit rate; 34 Projects (LIMIT 50), 35 cost_usd by model (pie, families); 39 Work rhythm (weekday × 3-h block table), 36 Top tools (7); 37 Recent sessions (6, panel link "all →") |
| Sessions | 421 header; 430 Sessions, 431 Median length, 432 Median cost_usd, 433 Sessions with errors; 7 Sessions (≤ 500); 422 `$session_header`; 440 cost_usd, 441 Tokens, 442 Turns, 443 Cache hit rate, 444 Tool errors; 100 Timeline; 101 Cumulative cost_usd & tokens, 8 Prompts in this session |
| Prompts | 431 header; 450 Prompts, 451 Median cost_usd, 452 p95 cost_usd, 453 Requests per prompt; 180 Most expensive prompts (8); 460 Prompts by cost_usd (buckets), 461 Mean cost_usd per prompt by model |
| Efficiency | 412 header "Tips · fixed last 7 days"; 220 Tips · 7d (x3 w3 h8), 227 Affected · 7d (x6 w4 h8), 221 Affected tokens by category (x10 w14 h8); 222 Token tips; 228 Time and friction tips; 411 "Where cost goes"; 223 cost_usd per day by phase, 224 Phase summary; 413 "Cache"; 225 Pauses between requests, 226 Cache hit rate by project; 204 How tips are made (rule table) |
| Agents & skills | 470 header; 471 Subagent share, 472 Subagent runs, 473 Skills used, 474 Outlier runs; 13 Subagent types, 475 cost_usd per day by actor; 14 Skills (LIMIT 50), 476 Biggest subagent runs (5) |
| Tools & files | 480 header; 481 Tool calls, 482 Error rate, 483 Rejected, 484 Median result size; 485 Calls by tool (7), 19 Rejected tool calls (50); 24 Files re-read within one session (50), 140 Largest tool results (50); 486 Bash by first word (5), 487 Most edited files (5) |
| Health | 490 header; 491 TTFT mean, 492 API latency p95, 493 API errors, 494 Hook time; 161 Time to first token by day (3 s threshold line), 26 Hook time; 495 API errors (`api_error` by status and text, 50), 496 API request duration (buckets) |

- **Work phase** (223/224): per `request_id`, from the `tool_result` events of that response, first
  match of Edit (Edit/Write/MultiEdit/NotebookEdit) → Delegate (Task/Agent/SendMessage/
  SubagentHandback/TaskStop) → Run (Bash) → Explore (only Read/Grep/Glob/LS) → Other; no tool
  result = Talk. 225: gap between consecutive requests of a session, red past the 5-min cache TTL.
- Tips section (412, 220–222, 227, 228) reads `cc.tips`: fixed 7 days, no variables; 222 =
  `affected IS NOT NULL`, 228 = time tips (`affected IS NULL`). Their headers come from
  `displayName` overrides (Category, Title, Text, Scope, Metric) so the RU build can translate them;
  the overrides still match `byName` on the raw column names.
- Sessions: 430–433 and 7 follow the range (by `last_prompt`) and account/project/actor/skill but
  **not** the Session variable; 422, 440–444, 100, 101, 8 need one selected session
  (`'${session}' != '__all'`). 7 marks the selected row with `▶`.
- **Session length** (431, header) = activity time: union of `[ts − duration_ms, ts]` of its
  `api_request` and `tool_result` events, overlaps counted once, idle time not counted.
- **Timeline 100**: one cell per `$__interval_s` step, a bar covers the time an item ran (end
  minus `duration_ms`): lanes Prompts (only with Actor and Skill All), Main · API (actor `main`),
  Subagents (first to last request per `agent_id`), Tools (1 ok, 2 a failure in the step).
- Agents: 472/474/13/476 filter `subagent_completed` by `agent_type` for Actor and by `agent_id`
  of requests with the skill for Skill; 473/14 count `skill_activated` of the main session only
  (Actor = an agent → 0).
- Health: hook panels 494/26 ignore Skill (hook events carry no skill); 493/495 derive the actor of
  `api_error` like `cc.api_requests`. Tools 483/19 match actor/skill via `cc.agents`/`cc.requests`.

## Fixed panel ids

- Ids are unique **per file only** (431 is the Prompts header and the Sessions Median length).
  Ranges: 1–299 the dashboards' own panels, 300–399 the rail (`sync-rail.js` deletes them), 400–499
  headers and the redesign's panels.
- `cc.tips.link` opens panels via `viewPanel=panel-<id>` (`modules/telemetry-data.md`): cc-tools 19,
  24, 140; cc-health 26, 161; cc-efficiency 226; cc-prompts 180; cc-sessions 100 — never renumber them.
- Deleted in the redesign: Overview 1, 9, 10, 11, 32, 38, 40, 42, 43,
  51, 54–59; Sessions 102; Prompts 181–183; Agents 120, 121; Tools 15–18, 20–23, 141–143; Health
  160, 162–165; the Tips dashboard 200–202. Retired earlier: 6, 12, 25, 41.
- Every join in the dashboards uses `ON` (ClickHouse 22.3/23.3 reject several `USING` joins in one query).

## Drill-down links (no slug)

| From (field) | To |
| --- | --- |
| rail nav | `/d/<uid>?${__url_time_range}&${__all_variables}` |
| 34 `project` | `/d/cc-usage?${account:queryparam}&var-project=${__value.raw:percentencode}`, session/actor/skill `$__all`, time range |
| 37 `name` | `/d/cc-sessions?from=…from_ms&to=…to_ms`, account, `var-project` = row's project, `var-session`, actor/skill `$__all` |
| 37 panel link "all →" | `/d/cc-sessions?${__url_time_range}&${__all_variables}` |
| 7 `name` | `/d/cc-sessions?from/to`, account, project, `var-session=sid`, actor, skill, `extra_cols` kept |
| 8 `prompt` | `/d/cc-prompts?${__url_time_range}`, account, project, `var-session`, actor/skill `$__all` |
| 180 `prompt` | `/d/cc-sessions?from/to`, account, project, `var-session`, actor/skill `$__all` |
| 180 `project` | `/d/cc-prompts?…&var-project=${__value.raw:percentencode}`, account and session kept, actor/skill `$__all` |
| 13 `type` / 14 `skill` | `/d/cc-agents?…&var-actor=` / `&var-skill=${__value.raw:percentencode}`, other vars kept |
| 476 `session` | `/d/cc-sessions?from/to`, account, project, `var-session=sid`, actor/skill `$__all` |
| 222, 228 `title` | `${__data.fields.open}${__url_time_range}`; `open` = `cc.tips.link` + `&` (+ `var-project=%24__all&` for `/d/cc-sessions`) |
| rail tips tiles | `/d/cc-efficiency?${__url_time_range}` |

- **Session zoom** (7, 37, 180, 476 and the `agent-outlier` tip): `from_ms`/`to_ms` = the session's
  activity span (first start to last end of its prompts, requests, tool calls; a start =
  `ts − duration_ms`) ± max(3 %, 5 s); no such events → `started`..`last_event` (476: the run's end).
  The helper fields (`sid`, `session_id`, `from_ms`, `to_ms`, `open`) are hidden by `custom.hidden`.
- The `agent-outlier` link carries `from`/`to` and the dashboards append `${__url_time_range}`:
  Grafana uses the first pair (observed in the browser, Grafana 12.1, 2026-11-19).

## Russian copies (`grafana/i18n/`)

```
edit grafana/dashboards/<file>.json (English = the only source)
  └─ node grafana/rail/sync-rail.js   rail + the RU switch link (only if ru/<file> exists)
     └─ node grafana/i18n/build-ru.js  ru/<file>.json: uid <uid>-ru, same panel ids, links /d/<uid> → /d/<uid>-ru
        (both accept --check; "unchanged"/"DIFFERS" per file)
```

| Translated | Kept as is |
| --- | --- |
| dashboard title, quick-range `display`, variable `label` (not when label = name), custom-variable option texts, panel title/description, `displayName` (incl. `options.sortBy[].displayName`), `noValue`, value-mapping `text`, link titles, text-panel nodes (HTML by tag, markdown by line / table cell) | ids, values, `${...}`, markup, matched mapping values, Grafana's own UI (`All`, menus: Grafana is not localized) |
| SQL (`rawSql`, variable `query`/`definition`): `sql.fragments` (exact text, applied first: plurals, the `cc.tips.link` rewrite to `-ru`), then `sql.literals` (whole quoted literal) | any SQL literal not listed (filters, ids, event names) |

- Strict: a static English string missing from `strings` → exit 1 with the list, nothing written;
  an `sql` literal/fragment no RU file uses → exit 1; an unused `strings` entry → warning only.
- Every new static English text (incl. labels built in SQL) needs a `ru.json` entry, or the build stops.
- Column widths: a table override with `custom.width` is widened when its translated `displayName`
  (8 px per letter + 40) or a translated value-mapping text (8 px per letter + 25) needs more;
  rounded up to a multiple of 5, never narrowed.
- `isSwitch` (type `link`, title `RU`, url `/d/<uid>-ru`) is duplicated in `sync-rail.js` and
  `build-ru.js` — change both.
- Any English dashboard change, incl. merging `develop` into a dashboard branch → rerun both scripts;
  RU copies went stale once after a merge (bar-chart bucket labels missing on RU).
- Folder `ru` comes from `foldersFromFilesStructure: true` (`modules/stack.md`); a new RU file
  appears within 30 s, a provider change needs a Grafana restart.

## Check script — `claude-context/scripts/check-dashboard.js`

```
node claude-context/scripts/check-dashboard.js [--account uuid[,uuid]] [--project p] [--session id]
     [--actor a] [--skill s] [--from now-24h] [--url http://localhost:3000] [--dashboards <dir>]
     (repo root; reads the Grafana password from .env; --dashboards = another folder: a worktree
      copy, or grafana/dashboards/ru for the RU copies — the default reads only the top-level *.json)
  provisioning: /api/dashboards/uid/<uid> for every file; /api/dashboards/home uid = cc-usage
  queries:      every query variable + panel target of every file via /api/ds/query, named "<uid> ..."
                other variables (extra_cols, shown_cols, session_header) take their current value / All / first option
  last line:    "all ok (<n> queries + <m> provisioning checks)" or "<k> FAILED (of ...)"; exit 0 / 1
```

Rail drift: `node grafana/rail/sync-rail.js --check`; RU drift: `node grafana/i18n/build-ru.js --check`.

## Not used (decided 2026-11-15)

- Grafana 12.1 tabs / dynamic dashboards: experimental, need schema v2 (Kubernetes format) — new
  views go into more panels or a separate dashboard file, not tabs.
- Business Text plugin: built-in Stat/Table suffice; its 6.2.3+ needs Grafana ≥ 12.3.
- Library panels from files do not exist in Grafana: hence `sync-rail.js`.

## Known limits

- Session titles and branches exist only for clients with the session-meta hook, and only after
  the first answer; otherwise panels 7/37 and the Session dropdown fall back to the first prompt
  / the id. A `/rename` shows after the next prompt.
- Session lists and counts (Sessions, Overview 37, the Session variable) keep sessions with a model
  request (`requests > 0`); Prompts keeps prompts with one.
- Prompt text exists only when the client sets `OTEL_LOG_USER_PROMPTS`; otherwise `(text not logged)`.
- Tips (Efficiency Tips section, rail tiles) and the inferred project of unlabelled sessions
  (`project` variable and every per-project panel) come from tables `cc-refresh` rebuilds every
  300 s: up to 5 min behind the other panels (`modules/materialization.md`).
