# Stack — containers, collector, storage, Grafana provisioning

The Docker services, how data moves between them, what is exposed and where it is stored.

## Files

| Path | Role |
| --- | --- |
| `docker-compose.yml` | services `clickhouse`, `otel-collector`, `views-init`, `cc-refresh`, `grafana`; volumes `clickhouse-data`, `grafana-data` |
| `otel-collector.yaml` | OTLP receivers, processors, clickhouse exporter, pipelines |
| `.env.example` → `.env` | `CLICKHOUSE_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`; optional `OTLP_BIND`, `GRAFANA_BIND`, `GRAFANA_PORT`, `CLICKHOUSE_VERSION`, `RETENTION_DAYS` (365), `CLICKHOUSE_LIMITS` (`small`\|`none`, default `none`), `CLICKHOUSE_CPUS` (0 = no limit) (`.env` git-ignored, created by `setup-server.ps1` / `setup-server.sh`; only the `.sh` writes the optional keys — Windows runs on the compose defaults) |
| `grafana/provisioning/datasources/clickhouse.yaml` | datasource uid `clickhouse`, native `clickhouse:9000`, user `otel`, db `cc`, password from env |
| `grafana/provisioning/dashboards/dashboards.yaml` | file provider, `updateIntervalSeconds: 30`, `allowUiUpdates: true`, `foldersFromFilesStructure: true` (root files → General, `ru/` → folder `ru`) |
| `clickhouse/init-views.sh`, `clickhouse/refresh-loop.sh`, `clickhouse/{schema,backfill,views,refresh}.sql` | see `modules/telemetry-data.md` |
| `clickhouse/config.d/common.xml` | always on, mounted as `config.d/cc-common.xml`: text log, system logs removed (below) |
| `clickhouse/users.d/common.xml` | always on, mounted as `users.d/cc-common.xml`: `default` profile `log_queries` / `log_query_views` 0 |
| `clickhouse/limits/{small,none}/{config,users}.xml` | `CLICKHOUSE_LIMITS` picks the folder, mounted as `config.d/cc-limits.xml` / `users.d/cc-limits.xml`; `small`: memory, caches, merge pool thresholds, threads, per-query memory, profilers, background pool (below); `none`: empty `<clickhouse/>` |

## Services

| Service | Image | Ports | Notes |
| --- | --- | --- | --- |
| `clickhouse` | `clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.8}` | none published | db `otel`, user `otel`; healthcheck `SELECT 1` every 60 s (timeout 5 s, 3 retries; no `start_period`, so the first check — and the start of the services that wait for `service_healthy` — comes ~60 s after start); `ulimits nofile 262144`; `cpus: ${CLICKHOUSE_CPUS:-0}` (0 = no limit) |
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.135.0` | `${OTLP_BIND:-0.0.0.0}:4317` gRPC (Claude Code), `${OTLP_BIND:-0.0.0.0}:4318` HTTP (session-meta hook) | starts after clickhouse is healthy |
| `views-init` | `clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.8}` | — | one-shot, `restart: "no"`; `bash /init/init-views.sh`; env `RETENTION_DAYS: ${RETENTION_DAYS:-365}`; `docker compose ps -a` shows `Exited (0)` when fine |
| `cc-refresh` | `clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.8}` | — | `bash /init/refresh-loop.sh`: `refresh.sql` every 300 s, client `--max_threads 1`; logs `refresh ok` / `refresh FAILED` and keeps looping; `depends_on` clickhouse healthy + views-init `service_completed_successfully` (a failed views-init fails `compose up -d`); after a reboot views-init does not run again, the loop waits for its tables |
| `grafana` | `grafana/grafana:12.1.0` | `${GRAFANA_BIND:-127.0.0.1}:${GRAFANA_PORT:-3000}:3000` | plugin via `GF_PLUGINS_PREINSTALL_SYNC=grafana-clickhouse-datasource` (4.23.5 at first install); home dashboard = `overview.json` via `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`; `GF_DASHBOARDS_MIN_REFRESH_INTERVAL=1m` |

Bind mounts (read-only) — `compose up -d` recreates a container only when its service
definition changes, so an edited file is picked up as follows:

| Host path | Service | Picked up by |
| --- | --- | --- |
| `otel-collector.yaml` | `otel-collector` | restart (`setup-server.sh --update` does it when the file changed) |
| `grafana/provisioning/` | `grafana` | restart (same, for any file under it) |
| `grafana/dashboards/` | `grafana` | re-read every 30 s |
| `clickhouse/` | `views-init` | next views-init run (`compose up -d` starts it again; or `compose run --rm views-init`) |
| `clickhouse/` | `cc-refresh` | `refresh.sql`: next run (re-read each loop); `refresh-loop.sh`: only on a restart of `cc-refresh` — `--update` does not restart it |
| `clickhouse/config.d/common.xml`, `clickhouse/users.d/common.xml`, `clickhouse/limits/<CLICKHOUSE_LIMITS>/{config,users}.xml` (single files; the limits pair long syntax, `create_host_path: false`: a mistyped value fails instead of creating a directory) | `clickhouse` | edited file: `compose restart clickhouse` by hand, `setup-server.sh --update` does not restart it; a changed `CLICKHOUSE_LIMITS` / `CLICKHOUSE_CPUS` changes the service definition → `compose up -d` recreates `clickhouse` |

All services but `views-init` are `restart: unless-stopped`; in wsl mode they come up when the
docker service starts with the distro; on Linux `setup-server.sh` checks (and offers to enable)
the docker service at boot.

## ClickHouse versions

| Tag | Where |
| --- | --- |
| `25.8` | compose default |
| `22.3.20.29` | old ARM (`aarch64` without `lrcpc`, Raspberry Pi 4): ClickHouse needs ARMv8.2 since 22.10; 23.3 and 25.8 die there with `Illegal instruction`. Any `22.3.*` tag = small server for the `setup-server.sh` defaults (`RETENTION_DAYS=180`, `CLICKHOUSE_LIMITS=small`, `CLICKHOUSE_CPUS=2`; else 365 / `none` / 0) |

- The stack (collector schema, views, all dashboard queries) runs on 22.3.20.29, 23.3 and 25.8;
  the materialized layer (`schema.sql`, `backfill.sql`, `refresh.sql`, 2026-11-18) only on
  22.3.20.29 so far (`pending-bugs.md`). 22.3.20.29 is the tag picked for ARMv8.0 CPUs such as the Raspberry Pi 4. Verify on the
  version the servers in use run (`server-state.local.md`).
- A data volume written by a newer ClickHouse does not start with an older one: change the tag
  via `linux-server-tools/backup.sh dump` → empty volume (`down -v`: the user's "yes" only) →
  new tag → `restore`.

## ClickHouse config: always on (`common.xml`) and limits (`limits/small/`)

| File | Setting | Value |
| --- | --- | --- |
| `config.d/common.xml` | `logger`: `level` / `size` / `count` (merged into the image's `<logger>`, log paths kept) | `warning` / 10M / 2 (image default `trace` / 1000M / 10) |
| `config.d/common.xml` | `asynchronous_metric_log`, `metric_log`, `query_thread_log`, `part_log`, `session_log`, `trace_log`, `text_log`, `query_log`, `query_views_log` | `remove="1"` (not written) |
| `users.d/common.xml` | `log_queries`, `log_query_views` | 0 |
| `limits/small/config.xml` | `max_server_memory_usage` / `mark_cache_size` / `uncompressed_cache_size` | 3 GB / 256 MiB / 0 |
| `limits/small/config.xml` | `max_concurrent_queries` | 8 |
| `limits/small/config.xml` | `merge_tree`: `number_of_free_entries_in_pool_to_lower_max_size_of_merge`, `..._to_execute_mutation` | 2 (defaults 8 / 20 exceed the smaller pool) |
| `limits/small/users.xml` | `max_threads` / `max_memory_usage` (per query) | 3 / 1.5 GB |
| `limits/small/users.xml` | `query_profiler_real_time_period_ns`, `query_profiler_cpu_time_period_ns`, `log_query_threads` | 0 |
| `limits/small/users.xml` | `background_pool_size` | 2 (profile-level: see `pending-bugs.md`) |

`CLICKHOUSE_LIMITS=none` (compose default, Windows, every tag but 22.3 via `setup-server.sh`):
only the `common.xml` rows apply; `cpus` 0.

- On 22.3.20.29 all `users.d` values and both `merge_tree` thresholds show as changed in
  `system.settings` / `system.merge_tree_settings`, `trace_log` stays as an empty table
  (observed 2026-11-17); `log_queries` / `log_query_views` = 0 (observed 2026-11-19). The split
  into `common.xml` + `limits/small/` gave the same effective settings there (supplied by the
  orchestrating agent, 2026-11-20).
- Text log: the image default wrote ~135 MB/day to the SD card; with the `logger` override the
  preprocessed config shows it merged with the log paths kept, and `clickhouse-server.log` stopped
  growing after the restart (observed on 22.3.20.29, 2026-11-19). Errors also go to
  `clickhouse-server.err.log`.
- Leftover `system.query_log*` / `system.query_views_log*` tables of a server that logged queries
  before are not dropped by anything: `setup-server.sh` prints the `DROP` command (`modules/server-update.md`).
- With `small`, a dashboard query needing more than 1.5 GB fails instead of slowing the server
  down; the backfill runs per month of data for the same reason (on every server).

## Collector pipeline

```
logs:    otlp → memory_limiter(512 MiB) → attributes/drop_response → batch(30 s, 1000) → clickhouse
metrics: otlp → memory_limiter → batch → clickhouse
```
- `attributes/drop_response` deletes `response` (Claude's reply text, which clients send together
  with prompts under `OTEL_LOG_USER_PROMPTS=1`); `response_length` stays. Rows stored before it
  was added still carry the text.
- clickhouse exporter: `tcp://clickhouse:9000`, `create_schema: true` → creates `otel.otel_logs`
  and `otel.otel_metrics_{sum,gauge,histogram,exponential_histogram,summary}` at collector start;
  retry up to 300 s and a 10000-item queue, then data is dropped.
- No exporter `ttl` (hours cannot follow `RETENTION_DAYS` from `.env`): the exporter creates the
  tables without a TTL; views-init sets it on those that have none (`modules/materialization.md`),
  `setup-server.sh` `apply_retention` changes an existing one (`modules/server-update.md`).
- Batch 30 s: an event shows on the dashboard up to ~30 s late (fewer, larger inserts → fewer
  parts and merges on the SD card).
- Receivers have **no authentication**.

## Storage

- `otel.otel_logs`: `Timestamp DateTime64(9)`, `ServiceName LowCardinality(String)`,
  `ResourceAttributes` / `LogAttributes Map(LowCardinality(String), String)`, `Body`, `ScopeName`, …
  `PARTITION BY toDate(TimestampTime)`, `TTL TimestampTime + toIntervalDay(<RETENTION_DAYS>)`
  (metrics: `toDateTime(TimeUnix)`), in volume `clickhouse-data`. `ServiceName` = `claude-code`
  (Claude Code events) or `cc-session-meta` (client hook); the views filter it.
- Retention: one source, `RETENTION_DAYS` in `.env` (compose default 365; `setup-server.sh` writes
  180 for 22.3, else 365, once, then keeps it). `schema.sql` holds the placeholder
  `__RETENTION_DAYS__`, replaced by `init-views.sh` and `setup-server.sh` `events_ttl_expr` (`sed`):
  do not pipe `schema.sql` to `clickhouse-client` as it is.
- `cc.events_t` (MergeTree, `PARTITION BY toDate(ts)`, `ORDER BY (event, ts)`,
  `TTL toDateTime(ts) + INTERVAL __RETENTION_DAYS__ DAY`, `ttl_only_drop_parts = 1`): the `claude-code`
  rows again, flattened — data is stored twice. `cc.session_project_t`, `cc.tips_t`: small, rebuilt
  by `cc-refresh`. Columns and rules: `modules/telemetry-data.md`.
- `backup.sh` dumps only `otel.*`; `cc.events_t` holds nothing extra. A `restore` into
  `otel.otel_logs` after setup refills it through `cc.events_mv`, otherwise the next views-init
  backfill does (`pending-bugs.md`). `--update` row counts cover `otel.*` only.
- In wsl mode the volumes live inside the distro: `wsl --unregister` deletes all data — dump first
  (`linux-server-tools/backup.sh dump`, `modules/setup-scripts.md`).
- `grafana-data` holds only Grafana's own DB; datasource and dashboard come from files.

## Exposure

| Port | Where | Who reaches it |
| --- | --- | --- |
| Grafana (`GRAFANA_PORT`, 3000) | `GRAFANA_BIND` (unset → `127.0.0.1`); `setup-server.sh` writes `0.0.0.0` unless `--local-only` | Windows: the server PC only; Linux: the LAN by default |
| 4317, 4318 | both follow `OTLP_BIND` (unset → `0.0.0.0`). wsl mode: Windows `localhost`, LAN via one firewall rule + portproxy per port; Linux: `setup-server.sh` writes `0.0.0.0` or `127.0.0.1` (`--local-only`) | clients: 4317 Claude Code (gRPC), 4318 the session-meta hook (OTLP/JSON `POST /v1/logs`) |
| 9000/8123 | container network only | collector, grafana, views-init, cc-refresh |

On Linux Docker's own iptables rules bypass ufw/firewalld: the bind address, not a firewall rule,
limits who connects. Do not publish ClickHouse ports, or change a bind in `.env`, without the
user asking. 4318 has the same trust as 4317: no authentication.
