# Plan: make cache rewrites visible on the dashboards

Status: done (2026-11-25). Approved 2026-11-24. All checks (dashboards, charts, new panels) run on
the local WSL stack only; the user updates the Raspberry Pi and checks it there after the PR is
merged.

## Goal

Make a cache rewrite visible from the dashboards without hand-written SQL. A cache rewrite is the
first request after a pause longer than the cache lifetime: it writes the whole context to the
cache again (`cache_creation_tokens`). In the case that started this plan, two resumed sessions
with 480k and 262k-token contexts spent $5.6 of $7.87 on their first requests, and no panel showed
it directly.

## Current state

| Where | What it does today | Problem |
| --- | --- | --- |
| Efficiency 225 "Pauses between requests" | `lagInFrame` per `session_id` over the requests **inside the time range**; buckets `<1m` … `>1h`, red past 5 min | The pause before the first request in the range is dropped. Subagent and main requests also share one partition, so their gaps mix |
| Overview 31 "Daily tokens & cache hit rate" | `toStartOfDay(ts)` buckets: input / output / cache_create bars + hit-rate line | A range of hours gives one bucket |
| Efficiency 223, Agents 475, Health 161 | per-day buckets (`toStartOfDay`) | Same as 31: a range of hours gives one bucket |
| Sessions 101 "Cumulative cost_usd & tokens" | A step per request; a rewrite shows as a jump | No token types, no pause |
| Sessions, any panel | — | No per-request view (time, pause, token types, cost) |
| Tips (`clickhouse/refresh.sql` → `cc.tips_t`) | `cache` fires on a hit rate below 40 % per project | A few rewrites inside a session with a 97 % hit rate never fire it |

- Money comes only from `api_request.cost_usd`: there is no price table (`refresh.sql` header).
  A per-token-type cost split is therefore **out of scope**. Panels show token types next to the
  request's `cost_usd`.
- Every tip category is listed by hand in these places:
  - `refresh.sql`;
  - the rail's most-frequent-category `multiIf` (`grafana/rail/rail.json`, synced into every
    dashboard by `sync-rail.js`);
  - Efficiency 221/222 value mappings and colours (`cc-efficiency.json`, around the
    `"agent-outlier"` entries);
  - the Efficiency 204 rule table;
  - `grafana/i18n/ru.json`;
  - `docs/tips.md` (+ `.ru.md`).
- Efficiency 221 "Affected tokens by category" is h8, sized for five token categories (the
  `grafana-style.md` exception, together with tiles 220/227). A sixth needs more height.

## Approach and decisions

1. **Pause = gap to the previous request of the same session and the same `agent_id`.** Partition
   by `(session_id, agent_id)`. Main and `aux:*` requests share `agent_id = ''` and the main prompt
   prefix: in the live data, `prompt_suggestion` reads the main cache. Each subagent has its own
   cache, and its first request has no previous row, so it is not a pause. The lag is computed over
   the **whole history** of the sessions that have a request in the range
   (`session_id IN (… $__timeFilter …) AND ts <= $__toTime`); only then are the rows kept whose
   `ts` lies in the range. Panel 225, the new Sessions table and the new tip use this same rule.
2. **Adaptive buckets.** Overview 31 uses `$__timeInterval(ts)` (ClickHouse plugin macro) with a
   panel `interval` minimum of `5m`; new title "Tokens & cache hit rate". Over a few hours the
   buckets are minutes, over 30 days hours. `maxDataPoints` 100 caps the bucket count (without it
   Grafana makes one bucket per pixel and the bars become hairlines). Each bar covers its bucket
   (`barAlignment` 1: it starts at the bucket time), and the panel title names the bucket length
   through `$__interval` ("Tokens & cache hit rate · per 5m"), so it is visible without hovering;
   the tooltip header is the bucket start. A tooltip row with the length was tried and dropped
   (hard to find among the series), and an end time cannot be shown: Grafana formats time units
   in the browser time zone, not the dashboard's. The same change goes to Efficiency 223,
   Agents 475 and Health 161 in a stage of its own (titles and descriptions lose "per day" /
   "by day").
3. **Sessions: new table "Requests in this session"** (id 445, x3 y30 w21, under 101/8). It needs
   one selected session (same rule as 440–444, 100, 101, 8) and follows actor/skill and the range.
   Columns: time, actor, model family, pause (s, red ≥ 300), input, output, cache read,
   cache create (gauge bar), `cost_usd`. Sorted by time, LIMIT 1000. Headers via `displayName`
   (RU build).
4. **New tip category `cache-rewrite`** in `refresh.sql`, per project over 7 days. A rewrite is a
   request with a pause ≥ 300 s (rule 1) and `cache_creation_tokens` ≥ 50k. The tip fires on at
   least 3 rewrites **or** a total `cost_usd` ≥ $2 (approved 2026-11-24).
   - `metric` = the count; `affected` = their cache-creation tokens; `cost_usd` = their
     `cost_usd`. That cost is the upper bound of the waste: a fresh session writes a cache too,
     only a smaller one.
   - Body: suggest `/compact` before a long break, or a new session instead of resuming a huge one.
   - Link: Sessions panel 445 for the session with the most expensive rewrite, zoomed to the
     session's activity span like `agent-outlier`.
   - Every category list above gets updated; 221 (and its row) grows to fit six bars.
5. Site pages (`docs/dashboards.md`, `docs/tips.md`, EN + RU) are updated by the stage that changes
   them. Screenshots are refreshed in the last stage from the demo stack.

## Risks

- **Load:** rule 1 reads the full history of every session that has a request in the range, which
  under "All projects" over 30 days is most of `cc.api_requests`. Checked on the local stack; the
  Raspberry Pi with ClickHouse 22.3 is "verified after merge" (`lagInFrame` already runs there in
  panel 225).
- **Changed meaning of 225:** after the partition change, gaps between main and subagent requests
  are not counted. The description and `docs/dashboards.md` say so.
- **Demo data:** `tools/docs-demo/generate.py` may have no long pause with a big cache write; then
  panel 445 and the tip are empty on the screenshots, and stage 6 has to tweak the generator.
- **Tips rail:** a missing `multiIf` branch shows the raw category name. Edit `rail.json`, then run
  `sync-rail.js`.
- No data deletion, no schema change: `cc.tips_t` keeps its columns, and `refresh.sql` rebuilds it
  every 300 s.
- ClickHouse 22.3 through 25.8: no `GROUP BY ALL`, joins with `ON` only.

## Decisions on the open questions (2026-11-24)

1. Tip thresholds: as proposed (pause ≥ 5 min, cache create ≥ 50k; ≥ 3 rewrites or ≥ $2 in 7 days
   per project).
2. Efficiency 223, Agents 475, Health 161 get adaptive buckets too: stage 3.
3. Live checks run **only on the local WSL stack** of the dev PC. Its data spans
   2026-11-13 … 2026-11-19 UTC and holds 32 rewrites by rule 1 (≥ 300 s, ≥ 50k), the last on
   2026-11-19 17:06 UTC. Stage results use that data with an explicit range; the developer names
   the session and request it checked in the report, not in tracked files. The Raspberry Pi stack
   is not touched.

## Verification

Per stage, following `guides/verification.md`, on the local stack:

- Changed JSON parses.
- `node grafana/rail/sync-rail.js --check` and `node grafana/i18n/build-ru.js --check` exit 0.
- `node claude-context/scripts/check-dashboard.js` passes on the English files and with
  `--dashboards grafana/dashboards/ru`, plain and with `--project <p> --session <id>`, both with
  `--from now-30d` so the local data (2026-11-13 … 2026-11-19) is in range.
- The named SQL samples below run through `linux-server-tools/ch.sh`.
- `refresh.sql` changes: `cc-refresh` logs `refresh ok`.
- Site pages: `mkdocs build --strict` and `check-readme.py`.
- Layout at 1920 px is checked only on the demo stack (stage 6).

## Stages

1. **Pauses fix (Efficiency 225).** Apply rule 1 (whole session history, partition
   `(session_id, agent_id)`), update the description, `ru.json` and `docs/dashboards.md` (+ RU).
   Result: pick a local rewrite `R` (pause ≥ 1 h); with R's project and a range that starts a few
   minutes before R, the panel query returns a `>1h` bucket that counts R (before the fix the
   bucket is missing). Dashboard check all `ok` (EN + RU).
2. **Overview 31 adaptive buckets.** `$__timeInterval(ts)`, `interval` 5m, the new title,
   `ru.json`, docs. Result: for a 2-hour range around R the query returns several buckets, and the
   one holding R has `cache_create` ≥ R's `cache_creation_tokens`; over 2026-11-13 … 2026-11-20 it
   returns more than 7 buckets. Dashboard check all `ok`.
3. **Efficiency 223, Agents 475, Health 161 adaptive buckets.** Same macro and minimum interval,
   titles/descriptions without "per day", `ru.json`, docs. Result: over a 2-hour range each query
   returns more than one bucket; the sum of 223 / 475 `cost_usd` over 2026-11-13 … 2026-11-20 equals
   the sum before the change. Dashboard check all `ok`.
4. **Sessions 445 "Requests in this session".** New table with rule 1 for the pause, `ru.json`,
   docs. Result: for R's session the row of R shows the same pause, cache create and `cost_usd` as
   the stage-1 sample. Dashboard check all `ok` with `--session`.
5. **Tip `cache-rewrite`.** Rule in `refresh.sql`, rail `multiIf`, Efficiency 221/222 mappings and
   colours, 221 height for six bars, the 204 rule table, `ru.json`, `docs/tips.md` (+ RU).
   Result: `cc-refresh` logs `refresh ok`; the rule's SELECT run by hand returns the local projects
   with their rewrite counts and costs, and `cc.tips_t` holds a `cache-rewrite` row for each that
   meets the thresholds; the link opens panel 445 of the right session. Dashboard check all `ok`;
   sync and RU checks exit 0. The local rewrites leave the 7-day window after 2026-11-26: run this
   stage before that or on fresh rewrites.
6. **Screenshots.** Demo data with at least one long pause and a big cache write if missing;
   `demo.sh up`, `check.js` all `ok`, `screenshots.js` for overview, sessions, efficiency;
   `demo.sh down`. Result: the new images show the bucketed chart, table 445 and the tip, with
   made-up data only; `mkdocs build --strict` exits 0.
