# Stack — containers, collector, storage, Grafana provisioning

The Docker services, how data moves between them, what is exposed and where it is stored.

## Files

| Path | Role |
| --- | --- |
| `docker-compose.yml` | services `clickhouse`, `otel-collector`, `views-init`, `grafana`; volumes `clickhouse-data`, `grafana-data` |
| `otel-collector.yaml` | OTLP receivers, processors, clickhouse exporter, pipelines |
| `.env.example` → `.env` | `CLICKHOUSE_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`; optional `OTLP_BIND`, `GRAFANA_BIND`, `GRAFANA_PORT`, `CLICKHOUSE_VERSION` (`.env` git-ignored, created by `setup-server.ps1` / `setup-server.sh`; only the `.sh` writes the optional keys) |
| `grafana/provisioning/datasources/clickhouse.yaml` | datasource uid `clickhouse`, native `clickhouse:9000`, user `otel`, db `cc`, password from env |
| `grafana/provisioning/dashboards/dashboards.yaml` | file provider, `updateIntervalSeconds: 30`, `allowUiUpdates: true` |
| `clickhouse/init-views.sh`, `clickhouse/views.sql` | see `modules/telemetry-data.md` |

## Services

| Service | Image | Ports | Notes |
| --- | --- | --- | --- |
| `clickhouse` | `clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.8}` | none published | db `otel`, user `otel`; healthcheck `SELECT 1`; `ulimits nofile 262144` |
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.135.0` | `${OTLP_BIND:-0.0.0.0}:4317` gRPC (Claude Code), `${OTLP_BIND:-0.0.0.0}:4318` HTTP (session-meta hook) | starts after clickhouse is healthy |
| `views-init` | `clickhouse/clickhouse-server:${CLICKHOUSE_VERSION:-25.8}` | — | one-shot, `restart: "no"`; `bash /init/init-views.sh`; `docker compose ps -a` shows `Exited (0)` when fine |
| `grafana` | `grafana/grafana:12.1.0` | `${GRAFANA_BIND:-127.0.0.1}:${GRAFANA_PORT:-3000}:3000` | plugin via `GF_PLUGINS_PREINSTALL_SYNC=grafana-clickhouse-datasource` (4.23.5 at first install); home dashboard = `overview.json` via `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` |

Bind mounts (read-only) — `compose up -d` recreates a container only when its service
definition changes, so an edited file is picked up as follows:

| Host path | Service | Picked up by |
| --- | --- | --- |
| `otel-collector.yaml` | `otel-collector` | restart (`setup-server.sh --update` does it when the file changed) |
| `grafana/provisioning/` | `grafana` | restart (same, for any file under it) |
| `grafana/dashboards/` | `grafana` | re-read every 30 s |
| `clickhouse/` | `views-init` | next views-init run (`compose up -d` starts it again; or `compose run --rm views-init`) |

All services but `views-init` are `restart: unless-stopped`; in wsl mode they come up when the
docker service starts with the distro; on Linux `setup-server.sh` checks (and offers to enable)
the docker service at boot.

## ClickHouse versions

| Tag | Where |
| --- | --- |
| `25.8` | compose default |
| `22.3.20.29` | old ARM (`aarch64` without `lrcpc`, Raspberry Pi 4): ClickHouse needs ARMv8.2 since 22.10; 23.3 and 25.8 die there with `Illegal instruction` |

- The stack (collector schema, views, all dashboard queries) runs on 22.3.20.29, 23.3 and 25.8.
  22.3.20.29 is the tag picked for ARMv8.0 CPUs such as the Raspberry Pi 4. Verify on the
  version the servers in use run (`server-state.local.md`).
- A data volume written by a newer ClickHouse does not start with an older one: change the tag
  via `linux-server-tools/backup.sh dump` → empty volume (`down -v`: the user's "yes" only) →
  new tag → `restore`.

## Collector pipeline

```
logs:    otlp → memory_limiter(512 MiB) → attributes/drop_response → batch(2 s, 1000) → clickhouse
metrics: otlp → memory_limiter → batch → clickhouse
```
- `attributes/drop_response` deletes `response` (Claude's reply text, which clients send together
  with prompts under `OTEL_LOG_USER_PROMPTS=1`); `response_length` stays. Rows stored before it
  was added still carry the text.
- clickhouse exporter: `tcp://clickhouse:9000`, `create_schema: true` → creates `otel.otel_logs`
  and `otel.otel_metrics_{sum,gauge,histogram,exponential_histogram,summary}` at collector start;
  retry up to 300 s and a 10000-item queue, then data is dropped.
- Receivers have **no authentication**.

## Storage

- `otel.otel_logs`: `Timestamp DateTime64(9)`, `ServiceName LowCardinality(String)`,
  `ResourceAttributes` / `LogAttributes Map(LowCardinality(String), String)`, `Body`, `ScopeName`, …
  No TTL: kept indefinitely in volume `clickhouse-data`. `ServiceName` = `claude-code` (Claude
  Code events) or `cc-session-meta` (client hook); the views filter it.
- In wsl mode the volumes live inside the distro: `wsl --unregister` deletes all data — dump first
  (`linux-server-tools/backup.sh dump`, `modules/setup-scripts.md`).
- `grafana-data` holds only Grafana's own DB; datasource and dashboard come from files.

## Exposure

| Port | Where | Who reaches it |
| --- | --- | --- |
| Grafana (`GRAFANA_PORT`, 3000) | `GRAFANA_BIND` (unset → `127.0.0.1`); `setup-server.sh` writes `0.0.0.0` unless `--local-only` | Windows: the server PC only; Linux: the LAN by default |
| 4317, 4318 | both follow `OTLP_BIND` (unset → `0.0.0.0`). wsl mode: Windows `localhost`, LAN via one firewall rule + portproxy per port; Linux: `setup-server.sh` writes `0.0.0.0` or `127.0.0.1` (`--local-only`) | clients: 4317 Claude Code (gRPC), 4318 the session-meta hook (OTLP/JSON `POST /v1/logs`) |
| 9000/8123 | container network only | collector, grafana, views-init |

On Linux Docker's own iptables rules bypass ufw/firewalld: the bind address, not a firewall rule,
limits who connects. Do not publish ClickHouse ports, or change a bind in `.env`, without the
user asking. 4318 has the same trust as 4317: no authentication.
