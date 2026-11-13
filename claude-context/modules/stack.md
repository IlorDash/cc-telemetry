# Stack — containers, collector, storage, Grafana provisioning

The Docker services, how data moves between them, what is exposed and where it is stored.

## Files

| Path | Role |
| --- | --- |
| `docker-compose.yml` | services `clickhouse`, `otel-collector`, `views-init`, `grafana`; volumes `clickhouse-data`, `grafana-data` |
| `otel-collector.yaml` | OTLP receivers, processors, clickhouse exporter, pipelines |
| `.env.example` → `.env` | `CLICKHOUSE_PASSWORD`, `GRAFANA_ADMIN_PASSWORD` (`.env` git-ignored, created by `setup-server.ps1`) |
| `grafana/provisioning/datasources/clickhouse.yaml` | datasource uid `clickhouse`, native `clickhouse:9000`, user `otel`, db `cc`, password from env |
| `grafana/provisioning/dashboards/dashboards.yaml` | file provider, `updateIntervalSeconds: 30`, `allowUiUpdates: true` |
| `clickhouse/init-views.sh`, `clickhouse/views.sql` | see `modules/telemetry-data.md` |

## Services

| Service | Image | Ports | Notes |
| --- | --- | --- | --- |
| `clickhouse` | `clickhouse/clickhouse-server:25.8` | none published | db `otel`, user `otel`; healthcheck `SELECT 1`; `ulimits nofile 262144` |
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.135.0` | `4317` gRPC, `4318` HTTP | starts after clickhouse is healthy |
| `views-init` | `clickhouse/clickhouse-server:25.8` | — | one-shot, `restart: "no"`; `bash /init/init-views.sh`; `docker compose ps -a` shows `Exited (0)` when fine |
| `grafana` | `grafana/grafana:12.1.0` | `3000` | plugin via `GF_PLUGINS_PREINSTALL_SYNC=grafana-clickhouse-datasource` (4.23.5 at first install); home dashboard = `cc-usage.json` |

All services but `views-init` are `restart: unless-stopped`; in wsl mode they come up when the
docker service starts with the distro.

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
  No TTL: kept indefinitely in volume `clickhouse-data`.
- In wsl mode the volumes live inside the distro: `wsl --unregister` deletes all data — dump first
  (`wsl/backup.sh dump`, `modules/setup-scripts.md`).
- `grafana-data` holds only Grafana's own DB; datasource and dashboard come from files.

## Exposure

| Port | Where | Who reaches it |
| --- | --- | --- |
| 3000 | host `localhost` | the server PC only |
| 4317 | host `localhost`; LAN only via firewall rule (+ portproxy in wsl mode) | clients |
| 4318 | host `localhost` | unused by clients |
| 9000/8123 | container network only | collector, grafana, views-init |

Do not publish ClickHouse ports or open 3000/4318 on the LAN without the user asking.
