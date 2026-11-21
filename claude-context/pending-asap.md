# Pending ASAP — rpi4-optimization

Found while testing the branch `rpi4-optimization` (11f7d2f) on the dev PC (WSL, native Docker
Engine), upgrade ClickHouse 22.3.20.29 → 25.8.33.6 with `setup-server.sh --update --local-only
--clickhouse-version 25.8`, on 2026-11-21. **Not fixed**: each entry has a suggested fix.
Severity: **H** data loss / broken setup, **M** wrong result or behaviour, **L** cosmetic, trap,
hint; `?` = cause not confirmed.

## Bugs

## Small things and hints

## Test log (dev PC, ClickHouse 25.8)

- `--update` 22.3 → 25.8: exit 0; dump, pull (no change), keys written: `CLICKHOUSE_VERSION=25.8`,
  `RETENTION_DAYS=365`, `CLICKHOUSE_LIMITS=none`, `CLICKHOUSE_CPUS=0`; data check: 27 653 /
  9 171 rows before and after.
- Limits: `NanoCpus=0`, `CpuQuota=0`; `max_threads` auto, `max_memory_usage` 0,
  `background_pool_size` 16, server caches and memory at the image defaults.
- TTL 365 days on `otel_logs`, every `otel_metrics_*` and `cc.events_t` (partitioned by day).
- `cc.events_t` = 27 623 = the `claude-code` rows of `otel_logs`, 0 duplicates.
- Then the skip-index corruption above; the ClickHouse volume was recreated from a dump.

### Real update path: develop → branch on 25.8 (dev PC, 2026-11-21)

- `develop` installed from scratch on 25.8.33.6 (`setup-server.sh --local-only`), dump restored
  (27 653 / 9 171 rows). Baseline `check-dashboard.js`: all ok, EN and RU (123 queries + 8
  provisioning checks each).
- Switched to `rpi4-optimization` (11f7d2f), `RETENTION_DAYS`, `CLICKHOUSE_LIMITS`,
  `CLICKHOUSE_CPUS` removed from `.env` first. `--update --local-only`: exit 0; the keys written as
  365 / `none` / `0`; data check 27 653 / 9 171 before and after.
- `clickhouse`: `NanoCpus=0`, `CpuQuota=0`, `Memory=0`; `max_threads` auto, `max_memory_usage` 0,
  `background_pool_size` 16, caches and `max_server_memory_usage` at the image defaults.
- TTL 365 days on `otel_logs`, every `otel_metrics_*` and `cc.events_t`; `cc.events_t`
  partitioned by day. The parts rewritten by `MODIFY TTL` (`_8`) read fine: no `CORRUPTED_DATA`.
- `cc.events_t` = 27 623 = the `claude-code` rows, 0 duplicates; `views-init` run again: nothing
  added. `cc-refresh`: `refresh ok`; `cc.session_project_t` 14 rows (one per session), `cc.tips_t`
  15 rows.
- `check-dashboard.js` after the update: all ok, EN and RU (123 queries + 8 provisioning checks).
- System logs since the restart on the branch config: only `processors_profile_log` (27 338 rows in
  2 minutes of checks) and `error_log` (1 row) are written; the other leftovers of develop stay
  (`text_log` 6.8 MiB, `trace_log`, `metric_log`, `query_log`, `query_metric_log`, ...), and
  `--update` reports only `query_log`.
- The collector kept the develop config after the update (entry above); restarted by hand for
  the test.
- Not verified: a live event through the MV after the update (no client sends to the dev stack
  now; a short session with the `~/.claude-guest` config would check it), `setup-server.ps1`, the
  dashboard layout (only the SQL is checked).
