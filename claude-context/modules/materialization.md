# Materialization — `cc.events_t`, backfill, refresh

How Claude Code events are flattened once into tables the `cc.*` views read, how history is
backfilled, and how the two derived tables are rebuilt. Views and tip rules: `modules/telemetry-data.md`.

## Files

| Path | Role |
| --- | --- |
| `clickhouse/schema.sql` | `CREATE DATABASE cc`; tables `cc.events_t`, `cc.session_project_t`, `cc.tips_t`; `cc.events_mv`; all `IF NOT EXISTS` |
| `clickhouse/backfill.sql` | `INSERT INTO cc.events_t` of `otel.otel_logs` rows it lacks, for one range (`{lo}`, `{hi}`, `{guard}` query parameters) |
| `clickhouse/views.sql` | the twelve views, applied last (`modules/telemetry-data.md`) |
| `clickhouse/refresh.sql` | rebuilds `cc.session_project_t` and `cc.tips_t` |
| `clickhouse/init-views.sh` | entrypoint of the one-shot `views-init` |
| `clickhouse/refresh-loop.sh` | entrypoint of the `cc-refresh` service |

## Objects

```
otel.otel_logs ──(insert, ServiceName = 'claude-code')── cc.events_mv ──► cc.events_t
cc.path_roots, cc.events_raw ──refresh.sql──► cc.session_project_t   (read by cc.session_project)
cc.api_requests, cc.tool_calls, cc.events, cc.events_raw ──refresh.sql──► cc.tips_t   (read by cc.tips)
```

| Object | Engine / key | Content |
| --- | --- | --- |
| `cc.events_t` | MergeTree, `PARTITION BY toDate(ts)`, `ORDER BY (event, ts)`, `TTL toDateTime(ts) + INTERVAL __RETENTION_DAYS__ DAY` (placeholder replaced with `RETENTION_DAYS`, below), `ttl_only_drop_parts = 1` (whole days dropped) | the 39 columns of `cc.events_raw` (low-cardinality text as `LowCardinality(String)`, `tool_input`/`tool_parameters`/`prompt`/`error` `ZSTD(1)`) + `seq`, `abs_path`, `path_cand`, `bash_cmd`; no `project` column. Column order: the 36 older columns, the four computed ones, then `account_uuid`, `status_code`, `error` (= order of the `backfill.sql` SELECT: inserted by position) |
| `cc.session_project_t` | MergeTree `ORDER BY session_id` | `session_id`, `project` (inferred) |
| `cc.tips_t` | MergeTree `ORDER BY tuple()` | the `cc.tips` columns; `affected`, `cost_usd` added to an older table by `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in `schema.sql` |

Insert-time columns (`tool_result` only, else `''`):

| Column | Value |
| --- | --- |
| `seq` | `event.sequence`; `(session_id, seq, ts)` identifies an event — `(session_id, seq)` alone is not unique |
| `abs_path` | `file_path` → `notebook_path` → `path` of `tool_input`, lower case, `\` → `/`, `/c/` → `c:/` |
| `path_cand` | candidate project folder of that path (rules: `cc.path_roots` in `modules/telemetry-data.md`) |
| `bash_cmd` | `tool_parameters.bash_command` (first word only) |

**Keep in step — written more than once:**
- MV expressions: `schema.sql` (`cc.events_mv`) and `backfill.sql`.
- Path regex, `IN` stop list, trailing-slash rule: `cc.events_mv`, `backfill.sql`, and the `cwd`
  half of `cc.path_roots` (`views.sql`).

**Do not** edit `cc.events_mv` expressions or `cc.events_t` columns and expect views-init to apply
them: `IF NOT EXISTS` skips the change and stored rows keep the old values. Needs a migration by
hand (header of `schema.sql`): dump → `DROP VIEW cc.events_mv` → new table filled from
`otel.otel_logs` + `EXCHANGE TABLES` → new MV → backfill for rows that arrived in between.

No script migrates `cc.events_t` (the earlier layout and column migrations were removed); only its
TTL is changed, by `setup-server.sh` `apply_retention` (`modules/server-update.md`).
- One `INSERT` over > 100 daily partitions is refused (`max_partitions_per_insert_block`):
  copies into `cc.events_t` go per month.

## views-init (`init-views.sh`, `set -euo pipefail`)

```
RETENTION_DAYS from env (compose: ${RETENTION_DAYS:-365}), not ^[1-9][0-9]*$ → exit 1
wait ≤ 10 min for otel.otel_logs
wait ≤ 60 s for ≥ 5 otel.otel_metrics_* tables, then go on with what exists
otel.otel_logs, otel.otel_metrics_* without ' TTL ' in engine_full:
  no row older than RETENTION_DAYS → ALTER MODIFY TTL <col> + toIntervalDay(RETENTION_DAYS)
  else → message, left as it is (deleting is the user's decision: setup-server.sh asks)
sed s/__RETENTION_DAYS__/RETENTION_DAYS/ schema.sql | clickhouse-client --multiquery
months = DISTINCT toStartOfMonth(TimestampTime) of claude-code rows (from the data: wrong client clocks covered)
  per month: backfill.sql  lo = month, hi = next month, guard 30      (a failed month fails views-init)
missing = last-hour claude-code rows not in cc.events_t
  ≠ 0 → sleep 35 → backfill.sql lo = now - 1 h, hi = 2100-01-01, guard 5
views.sql                                                             → "cc.* views are ready"
```
- `backfill.sql`: anti-join on `(session_id, seq, ts)` restricted to `[lo, hi)`, so the key set
  stays per month (1.5 GB per-query limit). Rows within `guard` s of `now()` are left to the MV;
  rows further ahead (fast client clock) are copied. Idempotent: a re-run inserts nothing.
- An existing TTL is never changed here (also not the one of `cc.events_t`: `IF NOT EXISTS`); a
  changed `RETENTION_DAYS` reaches existing tables only through `apply_retention`
  (`modules/server-update.md`). A metrics table created after the 60 s wait gets its TTL on the next run.
- Views are applied last, so a view never reads a half-filled table. views-init never runs
  `refresh.sql`.
- Live check (2026-11-21, ClickHouse 22.3.20.29): `cc.events_t` count = `claude-code` rows of
  `otel.otel_logs`, no duplicate `(session_id, seq, ts)`. Same on 25.8.33.6 (2026-11-21, after
  `--update`): count equal, 0 duplicates, a second views-init added nothing, `cc-refresh`
  `refresh ok` (`cc.session_project_t` one row per session, `cc.tips_t` filled).

## cc-refresh (`refresh-loop.sh`, `refresh.sql`)

```
wait until cc.session_project_t and cc.tips_t exist (after a reboot views-init does not run again)
loop: refresh.sql (--max_threads 1) → "refresh ok" | "refresh FAILED" (stderr) ; sleep 300
refresh.sql, per table:
  DROP IF EXISTS cc.<name>_new → CREATE AS cc.<name>_t → INSERT
  [session_project only] throwIf(count() != uniqExact(session_id))   (overlapping run guard)
  EXCHANGE TABLES cc.<name>_t AND cc.<name>_new → DROP cc.<name>_new
```
- A failed step stops the client before the swap: the old content stays; the next run drops the
  leftover `_new`. No `set -e` in the loop: a failure never stops it.
- `cc-refresh` is the only runner of `refresh.sql` (fixed `_new` names): **never run it by hand
  while `cc-refresh` is up**.
- Lag: the inferred project of a new unlabelled session (`unknown` until then) and the tips are
  ≤ 5 min old. The log also prints `0` per run (the `throwIf` result).

## Cost

Reported 2026-11-18 on a Raspberry Pi 4, ClickHouse 22.3.20.29, ~17k events: dashboard panel
queries median ~0.08 s, max < 1 s (before: ~2 s / 12 s with plain views over `otel.otel_logs`).

## Health checks (read-only)

| Check | How |
| --- | --- |
| refresh runs | `docker compose logs --tail 5 cc-refresh` → `refresh ok` every ~5 min |
| nothing missing | `SELECT count() FROM otel.otel_logs WHERE ServiceName = 'claude-code'` = `SELECT count() FROM cc.events_t` |
| no duplicates | `SELECT count() - uniqExact(session_id, seq, ts) FROM cc.events_t` = 0 |
| refreshed tables | `SELECT count(), uniqExact(session_id) FROM cc.session_project_t` (equal) |

Open questions: `pending-bugs.md` (materialization).
