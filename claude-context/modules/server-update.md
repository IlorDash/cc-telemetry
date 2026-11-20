# Server update and retention — `setup-server.sh`

`setup-server.sh --update` (safety dump, pull, re-run, config reload, row-count check) and
`apply_retention` (sets or changes the retention TTL of `otel.*` and `cc.events_t`).
`apply_retention` runs on **every** run of `setup-server.sh` after views-init exited 0, not only
under `--update`; the update re-run calls it like any other run. Linux only: `setup-server.ps1`
has neither. The rest of the script (steps, `.env`, LAN): `modules/setup-scripts.md`.

## Files

| Path | Role |
| --- | --- |
| `setup-server.sh` | `run_update`, `finish_update`, `reload_changed_config`, EXIT trap `update_exit_note`; `apply_retention`, `apply_events_t_ttl`, `warn_old_query_logs`; helpers `row_counts`, `recent_row_counts`, `save_retention_baseline`, `ttl_col`, `ttl_state`, `ttl_tables`, `check_window_days`, `load_retention`, `events_ttl_expr` |
| `.env` | `RETENTION_DAYS`: the one source of the retention (`load_retention` in `run_update`, `resolve_key` in step 2; missing → 180 for a `22.3.*` tag, else 365) |
| `clickhouse/schema.sql` | the `TTL` line of `CREATE TABLE IF NOT EXISTS cc.events_t`, read by `events_ttl_expr` (`__RETENTION_DAYS__` replaced by `sed`); keep those two lines as written |
| `linux-server-tools/backup.sh` | the safety dump (`BACKUP_DIR=<dir> ... dump`) and the restore command printed on a loss |

## apply_retention (every run, after views-init exited 0)

```
RETENTION_DAYS = n from .env (step 2, validated ^[1-9][0-9]*$); WINDOW = n - 1
update re-run, no ttl-recent.tsv yet (update started from an older script) → save_retention_baseline, before any TTL
CHECK_WINDOW = check_window_days = min(n, numeric TTLs the tables have now) - 1   (before any TTL change)
ttl_state per otel.otel_logs, otel.otel_metrics_*, cc.events_t (engine_full):
  ' TTL <col> + toIntervalDay(<d>)' → d;  no ' TTL ' → none;  anything else → other
  d = n → skip;  other → warn "TTL this script did not write", left as it is
todo = the rest (none, d < n lengthen, d > n shorten)
old  = rows older than WINDOW days of todo tables with none or d > n (lengthening asks nothing)
old > 0  update re-run → go on (the dump keeps them)
         terminal → ask [y/N] (default no); --yes does not count; no terminal → no
         no → warn (run --update, or dump + re-run in a terminal), warn_old_query_logs, return
apply_events_t_ttl: no cc.events_t → warn, return;  d = n → nothing;  other → warn, left;
  none / d ≠ n → ALTER MODIFY TTL <events_ttl_expr> (+ ttl_only_drop_parts = 1 only when there was none)
otel.* in todo → ALTER TABLE ... MODIFY TTL <col> + toIntervalDay(n)
warn_old_query_logs
```
- TTL column: `otel_logs` `TimestampTime`, `otel_metrics_*` `toDateTime(TimeUnix)`, `events_t` `toDateTime(ts)`.
- Re-run after success = no-op: every part reads its state from `system.tables`.
- A changed `RETENTION_DAYS` is applied here on the next run: longer at once, shorter under the
  old-rows question above. views-init only sets a TTL where there is none, never changes one.
- `CHECK_WINDOW`: a shorter TTL still in place keeps deleting until changed, so the `--update`
  data check compares only rows younger than the shortest of the new and the current TTLs.
- `warn_old_query_logs`: `log_queries` = 1 → warn to `compose restart clickhouse` and re-run;
  else per `system.query_log*` / `system.query_views_log*` table prints rows, size and
  `echo 'DROP TABLE system.<name> SYNC' | [sudo ]bash linux-server-tools/ch.sh` — never drops.
- No layout or column migration of `cc.events_t` (removed): a change to the MV / `cc.events_t`
  columns needs a manual migration (`modules/materialization.md`).
- `setup-server.ps1` has no retention step: on Windows views-init sets the TTL where there is none;
  a changed `RETENTION_DAYS` does not reach existing tables.

## --update

```
run_update   (all post-pull code is in this function, parsed before the pull; ends in exec)
  checks     .env exists; load_retention (RETENTION_DAYS from .env, missing → 180 for 22.3.*, else 365); ClickHouse answers (ch.sh SELECT 1); no tracked local changes; prev = HEAD; upstream?
  dump       backup/pre-update-<YYYYmmdd-HHMMSS>/; free space (df) vs sum(data_uncompressed_bytes)
             of active otel parts: less → fail, < 1.5× → warn; BACKUP_DIR=<dir> backup.sh dump; rowcounts.tsv;
             save_retention_baseline → ttl-recent.tsv: "#cutoff<TAB><now() - check_window_days>" (read once from
             ClickHouse), then per otel.* table with a ttl_col: rows with that time >= cutoff
  code       upstream → git pull --ff-only; no upstream / no repo → warn, files as they are
  exec       CCT_UPDATE=1 CCT_UPDATE_DIR=<dir> CCT_UPDATE_PREV=<prev> bash setup-server.sh <args minus --update>
re-run       steps 1–6 (`modules/setup-scripts.md`); in step 3 after views-init exited 0 → apply_retention → reload_changed_config (below)
             then finish_update: per rowcounts.tsv table, recount with the stored cutoff:
               in ttl-recent.tsv → recent rows now < before → LOST (exact); else OK, older rows that
                 shrank → OK with "<n> ... removed by the retention TTL" (informational)
               no ttl_col / no baseline → total now < before → LOST
             any LOST/FAIL → banner + restore command, exit 1
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
- Not handled: a pulled edit of `clickhouse/config.d/common.xml`, `clickhouse/users.d/common.xml`
  or `clickhouse/limits/*/*.xml` — `clickhouse` is not restarted (`pending-bugs.md`). A changed
  `CLICKHOUSE_LIMITS` / `CLICKHOUSE_CPUS` in `.env` is: `compose up -d` recreates the container.
- No volume is removed (no `down -v`); earlier dumps stay. Removed only through the TTL: rows
  older than the retention. With `sudo docker` the dump files belong to root.
