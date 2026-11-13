# Dashboard — `cc-usage.json`

The single Grafana dashboard: variables, rows, panels and the drill-down links between them.

## Files

| Path | Role |
| --- | --- |
| `grafana/dashboards/cc-usage.json` | uid `cc-usage`, title "Claude Code usage", refresh 10 s, default range 7 d; Grafana home page |

Grafana re-reads the file every 30 s — edit the file, never save over it from the UI. Queries use
the ClickHouse plugin's SQL editor (`editorType: sql`); `format` 1 = table, 0 = time series.

## Variables (nested, `__all` = All)

| Variable | Query source | Filter |
| --- | --- | --- |
| `project` | `DISTINCT project FROM cc.events` | — |
| `session` | `cc.sessions`, newest first, ≤ 300 | project; `prompts > 0 OR tokens > 0` (hides empty sessions) |
| `actor` | `DISTINCT actor FROM cc.api_requests` | project, session |
| `skill` | `DISTINCT skill FROM cc.api_requests`, non-empty | project, session |

Queries are plain strings (`"query": "SELECT ..."`) — the plugin supports that. Every panel filters
with `('${v}' = '__all' OR col = '${v}')` per variable and `$__timeFilter(ts)` (or
`$__fromTime`/`$__toTime`); the plugin expands macros server-side, Grafana substitutes `${v}`.

## Rows and panels (panel id: title)

| Row | Panels |
| --- | --- |
| Summary (all variables) | 2 Cost, 3 Tokens, 4 Sessions (`uniqExact(session_id)` of `cc.api_requests`), 5 Tool calls |
| Sessions | 7 Sessions table (`session_id` first, empty sessions hidden, `session_id` link sets `var-session`), 8 Prompts in the selected session |
| Tokens and cost | 10 Tokens by actor (bar), 11 Cost over time by actor (time series, `$__timeInterval`) |
| Agents and skills | 13 Agents, 14 Skills (links set `var-actor` / `var-skill`) |
| Tools | 16 Tool calls by tool, 17 Tools × actor × skill, 18 Bash commands, 19 Rejected tool calls |
| Files | 21 Top files, 22 Accesses by area, 23 Top directories, 24 Files re-read within one session |
| Hooks overhead | 26 Hook time |

Drill-down links rebuild the URL `/d/cc-usage/claude-code-usage?var-…&${__url_time_range}`.

## Known limits
- Panel 7 shows `first_prompt` (≤ 120 chars) as the session title: real titles are not in telemetry.
- Summary "Sessions" counts sessions with a model request; panel 7 also keeps sessions with a
  prompt but no request (rare).
- Prompt text exists only when the client sets `OTEL_LOG_USER_PROMPTS`; otherwise `<REDACTED>`.
