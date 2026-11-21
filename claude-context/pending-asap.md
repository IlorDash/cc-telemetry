# Pending ASAP — rpi4-optimization

Found while testing the branch `rpi4-optimization` (11f7d2f) on the dev PC (WSL, native Docker
Engine), upgrade ClickHouse 22.3.20.29 → 25.8.33.6 with `setup-server.sh --update --local-only
--clickhouse-version 25.8`, on 2026-11-21. **Not fixed**: each entry has a suggested fix.
Severity: **H** data loss / broken setup, **M** wrong result or behaviour, **L** cosmetic, trap,
hint; `?` = cause not confirmed.

## Bugs

## Small things and hints

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
