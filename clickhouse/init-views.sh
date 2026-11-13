#!/bin/bash
# Waits for the collector to create otel.otel_logs, then applies views.sql.
set -euo pipefail

CH=(clickhouse-client --host clickhouse --user otel --password "$CLICKHOUSE_PASSWORD")

for i in $(seq 1 120); do
  if [ "$("${CH[@]}" -q "EXISTS TABLE otel.otel_logs" 2>/dev/null || true)" = "1" ]; then
    break
  fi
  echo "waiting for otel.otel_logs ($i/120)"
  sleep 5
done

"${CH[@]}" --multiquery < /init/views.sql
echo "cc.* views are ready"
