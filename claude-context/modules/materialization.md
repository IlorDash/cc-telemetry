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
| `cc.events_t` | MergeTree, `PARTITION BY toDate(ts)`, `ORDER BY (event, ts)`, `TTL toDateTime(ts) + INTERVAL 180 DAY`, `ttl_only_drop_parts = 1` (whole days dropped) | the 36 columns of `cc.events_raw` (low-cardinality text as `LowCardinality(String)`, `tool_input`/`tool_parameters`/`prompt` `ZSTD(1)`) + `seq`, `abs_path`, `path_cand`, `bash_cmd`; no `project` column |
| `cc.session_project_t` | MergeTree `ORDER BY session_id` | `session_id`, `project` (inferred) |
| `cc.tips_t` | MergeTree `ORDER BY tuple()` | the `cc.tips` columns |

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

**Exception — layout only** (partition key, TTL; same columns): `setup-server.sh` `migrate_storage`
migrates an old-layout `cc.events_t` on every run after views-init (`modules/server-update.md`):
copy from the old table month by month (not from `otel.otel_logs`) into `cc.events_t_new` (DDL cut
from `schema.sql`) → `EXCHANGE TABLES` (`cc.events_mv` keeps writing to `cc.events_t` by name, no
MV rebuild) → anti-join top-up → per-month check → `DROP` old. Windows / other setups: by hand (README).
- One `INSERT` over > 100 daily partitions is refused (`max_partitions_per_insert_block`):
  copies into `cc.events_t` go per month.

## views-init (`init-views.sh`, `set -euo pipefail`)

```
wait ≤ 10 min for otel.otel_logs
schema.sql
months = DISTINCT toStartOfMonth(TimestampTime) of claude-code rows (from the data: wrong client clocks covered)
  per month: backfill.sql  lo = month, hi = next month, guard 30      (a failed month fails views-init)
missing = last-hour claude-code rows not in cc.events_t
  ≠ 0 → sleep 35 → backfill.sql lo = now - 1 h, hi = 2100-01-01, guard 5
views.sql                                                             → "cc.* views are ready"
```
- `backfill.sql`: anti-join on `(session_id, seq, ts)` restricted to `[lo, hi)`, so the key set
  stays per month (1.5 GB per-query limit). Rows within `guard` s of `now()` are left to the MV;
  rows further ahead (fast client clock) are copied. Idempotent: a re-run inserts nothing.
- Views are applied last, so a view never reads a half-filled table. views-init never runs
  `refresh.sql`.
- Live check (2026-11-18, ClickHouse 22.3.20.29): `cc.events_t` count = `claude-code` rows of
  `otel.otel_logs`, no duplicate `(session_id, seq, ts)`.

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
