# Server update and retention — `setup-server.sh`

`setup-server.sh --update` (safety dump, pull, re-run, config reload, row-count check) and
`apply_retention` (sets or changes the retention TTL of `otel.*` and `cc.events_t`).
`apply_retention` runs on **every** run of `setup-server.sh` after views-init exited 0, not only
under `--update`; the update re-run calls it like any other run. Linux only: `setup-server.ps1`
has neither. `reload_changed_config` also runs on every run (the `.ps1` has the same step). The
rest of the script (steps, `.env`, LAN, version-change refusal): `modules/setup-scripts.md`.

## Files

| Path | Role |
| --- | --- |
| `setup-server.sh` | `run_update`, `finish_update`, `reload_changed_config` (+ `newest_mtime`), EXIT trap `update_exit_note`; `apply_retention`, `apply_events_t_ttl`, `warn_old_system_logs`; helpers `row_counts`, `recent_row_counts`, `save_retention_baseline`, `ttl_col`, `ttl_state`, `ttl_tables`, `check_window_days`, `load_retention`, `events_ttl_expr` |
| `.env` | `RETENTION_DAYS`: the one source of the retention (`load_retention` in `run_update`, `resolve_key` in step 2; missing → 180 for a `22.3.*` tag, else 365) |
| `clickhouse/schema.sql` | the `TTL` line of `CREATE TABLE IF NOT EXISTS cc.events_t`, read by `events_ttl_expr` (`__RETENTION_DAYS__` replaced by `sed`); keep those two lines as written |
| `linux-server-tools/backup.sh` | the safety dump (`BACKUP_DIR=<dir> ... dump`) and the restore command printed on a loss |

## apply_retention (every run, after views-init exited 0)

```
RETENTION_DAYS = n from .env (step 2, validated ^[1-9][0-9]*$); WINDOW = n - 1
update re-run, no ttl-recent.tsv yet (update started from an older script) → save_retention_baseline, before any TTL
ttl_state per otel.otel_logs, otel.otel_metrics_*, cc.events_t (engine_full):
  ' TTL <col> + toIntervalDay(<d>)' → d;  no ' TTL ' → none;  anything else → other
  d = n → skip;  other → warn "TTL this script did not write", left as it is
todo = the rest (none, d < n lengthen, d > n shorten)
old  = rows older than WINDOW days of todo tables with none or d > n (lengthening asks nothing)
old > 0  update re-run → go on (the dump keeps them)
         terminal → ask [y/N] (default no); --yes does not count; no terminal → no
         no → warn (run --update, or dump + re-run in a terminal), warn_old_system_logs, return
apply_events_t_ttl: no cc.events_t → warn, return;  d = n → nothing;  other → warn, left;
  none / d ≠ n → ALTER MODIFY TTL <events_ttl_expr> (+ ttl_only_drop_parts = 1 only when there was none)
otel.* in todo → ALTER TABLE ... MODIFY TTL <col> + toIntervalDay(n)
warn_old_system_logs
```
- TTL column: `otel_logs` `TimestampTime`, `otel_metrics_*` `toDateTime(TimeUnix)`, `events_t` `toDateTime(ts)`.
- Re-run after success = no-op: every part reads its state from `system.tables`.
- A changed `RETENTION_DAYS` is applied here on the next run: longer at once, shorter under the
  old-rows question above. views-init only sets a TTL where there is none, never changes one.
- Check window: `check_window_days` = min(n, numeric TTLs the tables have now) - 1, called only by
  `save_retention_baseline` (before any TTL change) and stored as the `#cutoff` of `ttl-recent.tsv`;
  `finish_update` reads that cutoff. A shorter TTL still in place keeps deleting until changed, so
  the `--update` data check compares only rows younger than the shortest of the new and current TTLs.
- `warn_old_system_logs`: log names = the `<name remove="1"/>` lines of
  `clickhouse/config.d/common.xml` (keep one per line, no wildcard); tables `system.<name>` and
  rotated `<name>_<N>`. Per table the time column from `system.columns` (`event_time`, else
  `event_time_microseconds`, else `finish_time_us`; none → not tested, still listed): a row newer
  than the server start (`uptime()`) → warn `compose restart clickhouse` + re-run, list nothing.
  Else per table rows, size and `echo 'DROP TABLE system.<name> SYNC' | [sudo ]bash
  linux-server-tools/ch.sh`, then the total of ≥ 2 tables — never drops.
- No layout or column migration of `cc.events_t` (removed): a change to the MV / `cc.events_t`
  columns needs a manual migration (`modules/materialization.md`).
- `setup-server.ps1` has no retention step: on Windows views-init sets the TTL where there is none;
  a changed `RETENTION_DAYS` does not reach existing tables.

## ClickHouse version change (step 2, every run)

`check_ch_version_change` / `refuse_ch_version_change`, probes `ch_probe_version`, `ch_probe_rows`,
`ch_probe_volume`; run before `set_env CLICKHOUSE_VERSION`, skipped for the old-ARM auto-pick (the
replaced tag never ran there). Why: `modules/stack.md` "ClickHouse versions".

```
old = running version() (ch_probe_version), else .env, empty = CH_DEFAULT_TAG 25.8;  new likewise
is_small_ch(old) = is_small_ch(new) → fine (25.8 → 26.3, 22.3.x → 22.3.y)
ClickHouse answers → ch_probe_rows (sum rows, active otel parts): 0 → fine; > 0 → refuse (data);
                     unreadable → refuse (unknown)
ClickHouse down    → ch_probe_volume finds <project>_clickhouse-data → refuse (unknown), else fine
                     (project = `compose config` name:, else the clickhouse container label; exact name)
refuse → steps: dump (under --update: this update's folder) → compose down (no -v) → volume rm
         (the user runs it) → setup with the new tag → restore; fail. No force flag; .env untouched.
```
- `setup-server.ps1` writes no tag and has no such check.

## --update

```
run_update   (all post-pull code is in this function, parsed before the pull; ends in exec)
  checks     .env exists; load_retention (RETENTION_DAYS from .env, missing → 180 for 22.3.*, else 365); ClickHouse answers (ch.sh SELECT 1);
             no tracked local changes (clean under `git -c core.autocrlf=true status` = only CRLF differs → treated as clean,
             git runs with that -c from here on); prev = HEAD; upstream?
  dump       backup/pre-update-<YYYYmmdd-HHMMSS>/; free space (df) vs sum(data_uncompressed_bytes)
             of active otel parts: less → fail, < 1.5× → warn; BACKUP_DIR=<dir> backup.sh dump; rowcounts.tsv;
             save_retention_baseline → ttl-recent.tsv: "#cutoff<TAB><now() - check_window_days>" (read once from
             ClickHouse), then per otel.* table with a ttl_col: rows with that time >= cutoff
  code       upstream → GIT_TERMINAL_PROMPT=0 git [-c core.autocrlf=true] pull --ff-only </dev/null (never waits for
             credentials; fail names diverged branch / network / credentials); no upstream / no repo → warn, files as they are
  exec       CCT_UPDATE=1 CCT_UPDATE_DIR=<dir> CCT_UPDATE_PREV=<prev> bash setup-server.sh <args minus --update>
re-run       steps 1–6 (`modules/setup-scripts.md`); step 2: a ClickHouse version change across 22.3 with data is refused
             (the message names this update's dump as step 1); step 3 after views-init exited 0 → apply_retention → reload_changed_config (below)
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
- `reload_changed_config` (**every** run, not only `--update`; no git): per service, `newest_mtime`
  of `otel-collector.yaml` → `otel-collector`, of every file under `grafana/provisioning/` →
  `grafana`; compared with the running container's `State.StartedAt` → newer → `compose restart`.
  So a `git pull` by hand before `--update` or a plain run is loaded too; a container `compose up
  -d` just created is newer than its files; a file only touched costs one restart. No container or
  not running → skipped; mtime or `StartedAt` unreadable → warn (restart by hand); restart fails →
  fail (EXIT trap prints dump folder + rollback). None restarted → "nothing to restart".
  `setup-server.ps1` step "Reload changed configuration" does the same after its views-init wait
  (1 s tolerance, `[DateTimeOffset]` parse).
- No reload needed: `clickhouse/` (views) — `compose up -d` starts the exited one-shot views-init
  again on every run (schema, backfill of missing rows, views); `grafana/dashboards/` — Grafana
  re-reads it every 30 s. `cc-refresh` re-reads `refresh.sql` on each run, but a changed
  `refresh-loop.sh` is not picked up until `cc-refresh` is restarted (not done by `--update`).
- Why the views-init log on a `compose up -d` failure: `cc-refresh` depends on views-init
  `service_completed_successfully`, so a failed views-init fails `compose up -d` itself.
- Dump and row-count check cover `otel.*` only; `cc.events_t` is refilled from `otel.otel_logs`
  (`modules/materialization.md`).
- Not handled: a pulled edit of `clickhouse/config.d/common.xml`, `clickhouse/users.d/common.xml`
  or `clickhouse/limits/*/*.xml` — `clickhouse` is not restarted (`pending-bugs.md`);
  `warn_old_system_logs` then says to restart it when a removed log is still written. A changed
  `CLICKHOUSE_LIMITS` / `CLICKHOUSE_CPUS` in `.env` is: `compose up -d` recreates the container.
- No volume is removed (no `down -v`); earlier dumps stay. Removed only through the TTL: rows
  older than the retention. With `sudo docker` the dump files belong to root.
- Verified (2026-11-21, ClickHouse 25.8.33.6, WSL native engine): `--update --local-only` from
  `develop` to the rpi4-optimization code with the three keys missing → exit 0, keys written 365 /
  `none` / `0`, TTL 365 days set on `otel_logs`, every `otel_metrics_*` and `cc.events_t` (parts
  rewritten by `MODIFY TTL` read fine), data check equal before and after; then `check-dashboard.js`
  all ok EN + RU. The reload step and the version-change refusal came after that run.
