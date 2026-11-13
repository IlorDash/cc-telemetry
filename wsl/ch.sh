#!/bin/bash
# Runs SQL against the stack's ClickHouse with the password from .env (never printed).
# Usage (from the cc-telemetry folder):  echo "SELECT 1" | wsl -d Ubuntu -- bash wsl/ch.sh [extra clickhouse-client args]
set -euo pipefail
cd "$(dirname "$0")/.."
PW=$(grep '^CLICKHOUSE_PASSWORD=' .env | cut -d= -f2-)
exec docker compose exec -T clickhouse clickhouse-client --user otel --password "$PW" --multiquery "$@"
