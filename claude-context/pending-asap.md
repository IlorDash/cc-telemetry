# Pending ASAP — rpi4-optimization

Found while testing the branch `rpi4-optimization` (11f7d2f) on the dev PC (WSL, native Docker
Engine), upgrade ClickHouse 22.3.20.29 → 25.8.33.6 with `setup-server.sh --update --local-only
--clickhouse-version 25.8`, on 2026-11-21. **Not fixed**: each entry has a suggested fix.
Severity: **H** data loss / broken setup, **M** wrong result or behaviour, **L** cosmetic, trap,
hint; `?` = cause not confirmed.

## Bugs

- **H?** **Corrupted skip index after switching an existing volume from 22.3 to 25.8.** After the
  update, every query that uses the skip index `idx_log_attr_key` of `otel.otel_logs` fails:
  `Bad size of marks file '.../20261119_2731_3911_469_3913/skp_idx_idx_log_attr_key.mrk3': 48,
  must be: 24 (CORRUPTED_DATA)`. `CHECK TABLE` passes every part.
  - Effect: everything that reads `cc.session_meta` (`LogAttributes['session.id'] != ''`) fails:
    14 of 123 queries of `check-dashboard.js` (the `session` variable of every dashboard,
    Sessions panels 7, 430–433, Recent sessions 37); `cc-refresh` fails every run, so
    `cc.session_project_t` and `cc.tips_t` stay empty (projects `unknown`, no tips).
  - Cause, narrowed: every part of `otel_logs` got the mutation version `_3913` at 12:43:06,
    when `views-init` ran `ALTER TABLE ... MODIFY TTL` on 25.8 over parts written by 22.3. The
    same `MODIFY TTL` on parts written by 25.8 (develop → branch test below, parts `_8`) leaves
    them readable, so the trigger is the 22.3 parts: either the mutation keeps 22.3 index marks
    that 25.8 reads differently, or 25.8 fails on those parts anyway (not reproduced without the
    mutation).
  - Affects only a version change of an existing volume (22.3 → newer); the Pi stays on 22.3,
    fresh 25.8 installs and the develop → branch update on 25.8 are fine.
  - Fix: document that changing `CLICKHOUSE_VERSION` from 22.3 needs dump → new volume → restore
    (`docs/maintenance` + `.ru`, the `--clickhouse-version` help of `setup-server.sh`); or let
    `setup-server.sh` refuse / warn when the tag changes from 22.3 on a non-empty volume. Repair of
    a broken stack without data loss, to check: `ALTER TABLE otel.otel_logs MATERIALIZE INDEX
    idx_log_attr_key` (and the other skip indexes), then `docker compose restart cc-refresh`.
    On the dev PC it was repaired by dump → new volume → restore (see "Test log" below).

- **M** **ClickHouse 25.8 still writes two system logs.** `clickhouse/config.d/common.xml` removes
  nine logs but not `processors_profile_log` (one row set per query: grew 886 → 53 349 rows during
  one `check-dashboard.js` run) and `error_log`. The PR description says no system logs are
  written on every server. Fix: add `<processors_profile_log remove="1"/>` and
  `<error_log remove="1"/>` to `common.xml` (an unknown element is ignored by 22.3); check the
  list against `system.tables` of a fresh 25.8 after an hour (also `latency_log`,
  `query_metric_log`, `blob_storage_log`, `backup_log` if they appear).

## Small things and hints

- **M** **Leftover system logs are much bigger than `query_log`.** `warn_old_query_logs` reports
  only `system.query_log*` / `query_views_log*` (98 MiB here). The tables of the other removed
  logs stay too and are not mentioned: `query_thread_log` 887 MiB, `trace_log` 406 MiB,
  `asynchronous_metric_log` 309 MiB, `metric_log` 63 MiB, `session_log` 4.6 MiB, `part_log`
  0.6 MiB (dev PC, ~1 week of 22.3 with the image defaults; the Pi likely similar). Fix: list every
  `system.*_log*` table of a log that `common.xml` removes, with its size and the `DROP` command;
  same in the guide (maintenance, EN + RU).

- **L** **`--update` from WSL on a checkout made by Windows git fails at once.** WSL git (no
  `core.autocrlf`) sees every text file as modified (CRLF), so the clean-tree check stops with
  `The git working tree has local changes`. Only line endings differ (`git diff
  --ignore-cr-at-eol` is empty). Not new in this branch. Fix: compare with
  `git -c core.autocrlf=true status` when the tree has CRLF files, or say in the error that CRLF
  from a Windows checkout is the likely cause (`git config core.autocrlf true` in WSL); one line
  in troubleshooting.

- **L** **`git pull` of `--update` hangs on a private repo without credentials.** WSL git asked for
  a username on a terminal it did not have and waited (stdin from `/dev/null`) for 10 minutes; the
  script printed nothing after `== Update: code`. Fix: run the pull with
  `GIT_TERMINAL_PROMPT=0` (fails at once with `could not read Username`) and add to the error
  message "or no credentials for the remote". Not new in this branch.

- **L** **Docker Desktop's WSL integration hides the native engine.** With Docker Desktop
  installed, its WSL integration replaced `/var/run/docker.sock` in Ubuntu: `docker compose` saw
  an empty engine while the stack ran in the native one, and `setup-server.sh` stopped only at
  "port 3000 is already in use". Hint for troubleshooting (EN + RU): `docker version` shows
  `Docker Desktop` → turn off WSL integration for the distro, `sudo systemctl restart
  docker.socket docker`. Not new in this branch.

- **M** **`setup-server.ps1 -Mode auto` picks Docker Desktop although the stack runs in WSL.** On the
  dev PC (both Docker Desktop 4.44 and the native Docker Engine in WSL Ubuntu installed, the stack
  in WSL), a plain `setup-server.ps1` run (2026-11-21, stage 1 check) chose Docker Desktop's
  engine and started a second stack there: pulled images, created all five containers, started
  `clickhouse` on Docker Desktop's own `cc-telemetry_*` volumes. The run was cut off before
  the reload step; the WSL stack stayed intact. Fix: in auto mode, prefer the engine that already
  runs a `cc-telemetry` compose project (`docker compose ls` / `ps` in both), and stop with a
  message naming `-Mode wsl` / `-Mode desktop` when both have one or the choice is unclear.

- **L** **The defaults follow the image tag, not the hardware.** On an x86 PC whose `.env` still
  pins `CLICKHOUSE_VERSION=22.3.20.29` (as the dev PC did), `setup-server.sh` writes 180 days,
  `CLICKHOUSE_LIMITS=small` and `CLICKHOUSE_CPUS=2`. Intended per the comment, but worth one
  line in the guide: to get the defaults of a large server, change the tag first
  (`--clickhouse-version 25.8`, with the dump/restore of the first entry).

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
