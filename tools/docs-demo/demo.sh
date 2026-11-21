#!/bin/bash
# Throwaway demo stack for the guide screenshots: ClickHouse + Grafana filled with made-up telemetry
# (generate.py). It NEVER touches the main stack: its own containers (cc-demo-*), its own docker
# network (cc-demo-net), no volumes (ClickHouse data in tmpfs, Grafana in its container filesystem; both
# vanish with the container), Grafana on
# 127.0.0.1:13000 only, ClickHouse not published, nothing on 4317/4318. The passwords below are fixed
# throwaway ones: they protect nothing (no real data, localhost only).
#
# Usage (from the repo root, Docker inside WSL):
#   wsl -d Ubuntu -- bash tools/docs-demo/demo.sh up     # build, load, start (re-run = fresh start)
#   wsl -d Ubuntu -- bash tools/docs-demo/demo.sh down   # remove exactly the cc-demo-* containers and network
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
NET=cc-demo-net
CH=cc-demo-clickhouse
GF=cc-demo-grafana
CH_PASS=demo-clickhouse
GF_PASS=demo-grafana
GF_PORT=13000
CH_IMAGE=clickhouse/clickhouse-server:${CH_DEMO_VERSION:-25.8}   # default = tag of docker-compose.yml; override on old ARM (e.g. 22.3.20.29)
GF_IMAGE=grafana/grafana:12.1.0
PROV=/tmp/cc-demo-provisioning
DATA=/tmp/cc-demo-data

chq() { docker exec -i "$CH" bash -c 'clickhouse-client --user otel --password "$CLICKHOUSE_PASSWORD" "$@"' _ "$@"; }

down() {
  docker rm -f -v "$GF" "$CH" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$PROV" "$DATA"
  echo "demo stack removed"
}

up() {
  down
  docker network create "$NET" >/dev/null

  docker run -d --name "$CH" --network "$NET" \
    -e CLICKHOUSE_DB=otel -e CLICKHOUSE_USER=otel -e CLICKHOUSE_PASSWORD="$CH_PASS" \
    -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    --ulimit nofile=262144:262144 --tmpfs /var/lib/clickhouse \
    "$CH_IMAGE" >/dev/null
  for i in $(seq 1 60); do
    chq -q 'SELECT 1' >/dev/null 2>&1 && break
    [ "$i" = 60 ] && { echo "ClickHouse did not start" >&2; exit 1; }
    sleep 2
  done

  chq --multiquery < "$HERE/otel_logs.sql"
  # The cc layer in the order of clickhouse/init-views.sh. schema.sql comes BEFORE the rows are inserted:
  # the materialized view cc.events_mv then fills cc.events_t on insert, so no backfill.sql is needed
  # (the demo data is static). Retention 3650 days keeps every generated row. refresh.sql reads the
  # views, so it runs after views.sql; its stdout is only the "0" of a safety check (errors go to stderr).
  sed "s/__RETENTION_DAYS__/3650/g" "$REPO/clickhouse/schema.sql" | chq --multiquery
  mkdir -p "$DATA"
  python3 "$HERE/generate.py" > "$DATA/logs.jsonl"
  chq --query "INSERT INTO otel.otel_logs FORMAT JSONEachRow" < "$DATA/logs.jsonl"
  chq --multiquery < "$REPO/clickhouse/views.sql"
  chq --multiquery < "$REPO/clickhouse/refresh.sql" >/dev/null
  echo "rows loaded: $(chq -q 'SELECT count() FROM otel.otel_logs')," \
       "cc.events_t: $(chq -q 'SELECT count() FROM cc.events_t')"

  # provisioning copy: the repo's dashboards provider, a datasource pointed at the demo ClickHouse
  mkdir -p "$PROV/dashboards" "$PROV/datasources"
  cp "$REPO/grafana/provisioning/dashboards/dashboards.yaml" "$PROV/dashboards/"
  cat > "$PROV/datasources/clickhouse.yaml" <<EOF
apiVersion: 1
datasources:
  - name: ClickHouse
    uid: clickhouse
    type: grafana-clickhouse-datasource
    isDefault: true
    jsonData:
      host: $CH
      port: 9000
      protocol: native
      username: otel
      defaultDatabase: cc
    secureJsonData:
      password: $CH_PASS
EOF

  docker run -d --name "$GF" --network "$NET" -p "127.0.0.1:$GF_PORT:3000" \
    -e GF_SECURITY_ADMIN_PASSWORD="$GF_PASS" \
    -e GF_PLUGINS_PREINSTALL_SYNC=grafana-clickhouse-datasource \
    -e GF_DASHBOARDS_MIN_REFRESH_INTERVAL=5s \
    -e GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/overview.json \
    -v "$PROV:/etc/grafana/provisioning:ro" \
    -v "$REPO/grafana/dashboards:/var/lib/grafana/dashboards:ro" \
    "$GF_IMAGE" >/dev/null
  # Grafana installs the ClickHouse plugin in the background on a fresh container and only loads it
  # on the next start (the real stack keeps it in its volume): wait for the files, restart once
  # (the container filesystem survives a restart), then wait until the datasource answers.
  for i in $(seq 1 90); do
    docker exec "$GF" test -f /var/lib/grafana/plugins/grafana-clickhouse-datasource/plugin.json 2>/dev/null && break
    [ "$i" = 90 ] && { echo "the ClickHouse plugin was not installed (no internet?)" >&2; exit 1; }
    sleep 2
  done
  docker restart "$GF" >/dev/null
  for i in $(seq 1 90); do
    curl -fs -u "admin:$GF_PASS" "http://127.0.0.1:$GF_PORT/api/datasources/uid/clickhouse/health" >/dev/null 2>&1 && break
    [ "$i" = 90 ] && { echo "Grafana did not come up" >&2; exit 1; }
    sleep 2
  done
  echo "demo ready: http://localhost:$GF_PORT  (admin / $GF_PASS)"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: demo.sh up|down" >&2; exit 2 ;;
esac
