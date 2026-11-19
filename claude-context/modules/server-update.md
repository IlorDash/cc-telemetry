# Server update and storage migration — `setup-server.sh`

`setup-server.sh --update` (safety dump, pull, re-run, config reload, row-count check) and
`migrate_storage` (retention TTL + day partitions of an older install). `migrate_storage` runs on
**every** run of `setup-server.sh` after views-init exited 0, not only under `--update`; the
update re-run calls it like any other run. Linux only: `setup-server.ps1` has neither.
The rest of the script (steps, `.env`, LAN): `modules/setup-scripts.md`.

## Files

| Path | Role |
| --- | --- |
| `setup-server.sh` | `run_update`, `finish_update`, `reload_changed_config`, EXIT trap `update_exit_note`; `migrate_storage`, `migrate_events_t`, `warn_old_query_logs`; helpers `row_counts`, `old_row_counts`, `ttl_col` |
| `clickhouse/schema.sql` | source of `RETENTION_DAYS` (its `TTL` line) and of the `cc.events_t` DDL `migrate_events_t` creates as `cc.events_t_new` |
| `linux-server-tools/backup.sh` | the safety dump (`BACKUP_DIR=<dir> ... dump`) and the restore command printed on a loss |

## migrate_storage (every run, after views-init exited 0)

```
RETENTION_DAYS = days of the `TTL ... INTERVAL <n> DAY` line in schema.sql (else 180); WINDOW = n - 1
update re-run, no ttl-expected.tsv yet → write it (old_row_counts)
todo = otel.otel_logs, otel.otel_metrics_*, cc.events_t without ' TTL ' in engine_full
old  = rows of todo older than WINDOW days
old > 0  update re-run → go on (the dump keeps them)
         terminal → ask [y/N] (default no); --yes does not count; no terminal → no
         no → warn (run --update, or dump + re-run in a terminal), warn_old_query_logs, return
migrate_events_t (state from system.tables partition_key of cc.events_t / cc.events_t_new):
  key = schema.sql, no _new       → no TTL: ALTER MODIFY TTL + ttl_only_drop_parts = 1; else nothing
  old key, _new has new key       → copy interrupted: DROP _new, start again
  new key, _new has old key       → swap done: resume at the top-up
  anything else with _new         → fail (drop the leftover by hand)
  migrate: CREATE _new from schema.sql DDL (key reported ≠ schema.sql → DROP _new, fail)
           → INSERT per month → EXCHANGE TABLES cc.events_t_new AND cc.events_t
           → top-up per month: old rows NOT IN new by (session_id, seq, ts)
           → check per month, rows younger than WINDOW: count, sum of 4 token columns equal,
             sum(cost_usd) within 1e-9 relative → mismatch: fail, old table kept as _new
           → DROP TABLE cc.events_t_new SYNC
otel.* in todo → ALTER TABLE ... MODIFY TTL <col> + toIntervalDay(n)
warn_old_query_logs
```
- TTL column: `otel_logs` `TimestampTime`, `otel_metrics_*` `toDateTime(TimeUnix)`, `events_t` `toDateTime(ts)`.
- Re-run after success = no-op; every interrupted state continues or restarts by itself.
- `warn_old_query_logs`: `log_queries` = 1 → warn to `compose restart clickhouse` and re-run;
  else per `system.query_log*` / `system.query_views_log*` table prints rows, size and
  `echo 'DROP TABLE system.<name> SYNC' | [sudo ]bash linux-server-tools/ch.sh` — never drops.
- `setup-server.ps1` has no migration: Windows servers migrate by hand (README).

## --update

```
run_update   (all post-pull code is in this function, parsed before the pull; ends in exec)
  checks     .env exists; ClickHouse answers (ch.sh SELECT 1); no tracked local changes; prev = HEAD; upstream?
  dump       backup/pre-update-<YYYYmmdd-HHMMSS>/; free space (df) vs sum(data_uncompressed_bytes)
             of active otel parts: less → fail, < 1.5× → warn; BACKUP_DIR=<dir> backup.sh dump; rowcounts.tsv;
             ttl-expected.tsv (per otel.* table: rows older than RETENTION_DAYS - 1)
  code       upstream → git pull --ff-only; no upstream / no repo → warn, files as they are
  exec       CCT_UPDATE=1 CCT_UPDATE_DIR=<dir> CCT_UPDATE_PREV=<prev> bash setup-server.sh <args minus --update>
re-run       steps 2–6; in step 3 after views-init exited 0 → migrate_storage → reload_changed_config (below)
             then finish_update: every table rows now ≥ before − its ttl-expected.tsv count (missing file → 0),
             else LOST banner + restore command, exit 1; a drop within that count → OK "removed by the retention TTL"
             after a pull prints the rollback: git checkout <prev> && bash setup-server.sh
EXIT trap    failing exit once the dump folder is set → prints it (+ rollback command after a pull)
```
- `CCT_UPDATE_DIR` is honoured only with `CCT_UPDATE=1`, under `backup/`, without `..`, as an
  existing folder; the three variables are unset at start.
- `reload_changed_config` (only with dump folder + prev): `git diff --name-only <prev> HEAD` →
  `otel-collector.yaml` → `compose restart otel-collector`; `grafana/provisioning/*` →
  `compose restart grafana`; ok line per service, else "nothing to restart". git fails → warn
  (restart by hand), continue; restart fails → fail (EXIT trap prints dump folder + rollback).
- No reload needed: `clickhouse/` (views) — `compose up -d` starts the exited one-shot views-init
  again on every run (schema, backfill of missing rows, views); `grafana/dashboards/` — Grafana
  re-reads it every 30 s. `cc-refresh` re-reads `refresh.sql` on each run, but a changed
  `refresh-loop.sh` is not picked up until `cc-refresh` is restarted (not done by `--update`).
- Why the views-init log on a `compose up -d` failure: `cc-refresh` depends on views-init
  `service_completed_successfully`, so a failed views-init fails `compose up -d` itself.
- Dump and row-count check cover `otel.*` only; `cc.events_t` is refilled from `otel.otel_logs`
  (`modules/materialization.md`).
- Not handled: `clickhouse/config.d/*`, `clickhouse/users.d/*` — `clickhouse` is not restarted
  when they change (`pending-bugs.md`).
- No volume is removed (no `down -v`); earlier dumps stay. Removed only: the checked old copy
  `cc.events_t_new` (`migrate_storage`) and, through the TTL, rows older than the retention. With `sudo docker` the dump files belong to root.
