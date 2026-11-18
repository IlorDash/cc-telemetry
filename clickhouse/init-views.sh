#!/bin/bash
# Waits for the collector to create otel.otel_logs, then builds the cc.* layer: tables and the
# materialized view (schema.sql), the backfill of cc.events_t (backfill.sql, one month at a time), the views
# (views.sql). The derived tables are filled by the cc-refresh service, which starts after this script.
set -euo pipefail

CH=(clickhouse-client --host clickhouse --user otel --password "$CLICKHOUSE_PASSWORD")

for i in $(seq 1 120); do
  if [ "$("${CH[@]}" -q "EXISTS TABLE otel.otel_logs" 2>/dev/null || true)" = "1" ]; then
    break
  fi
  echo "waiting for otel.otel_logs ($i/120)"
  sleep 5
done

"${CH[@]}" --multiquery < /init/schema.sql

# Backfill: one pass per month of data keeps the set of known keys small (per-query memory limit).
# Months are taken from the data itself, so rows with a wrong client clock are covered too. The list is read
# into a variable first: a failed query then stops the script (set -e ignores a failure inside <(...)).
months="$("${CH[@]}" -q "SELECT DISTINCT toStartOfMonth(toDate(TimestampTime)) AS m, addMonths(m, 1) FROM otel.otel_logs WHERE ServiceName = 'claude-code' ORDER BY m")"
if [ -n "$months" ]; then
  while IFS=$'\t' read -r lo hi; do
    [ -n "$lo" ] || continue
    "${CH[@]}" --multiquery --param_lo="$lo 00:00:00" --param_hi="$hi 00:00:00" --param_guard=30 < /init/backfill.sql
  done <<<"$months"
fi

# The backfill leaves the last 30 s to the materialized view. Events of those seconds that arrived before
# the view existed are missing: when there are any, wait until they are older than 30 s and copy them
# (guard 5 s: now the rows from before the view are all older than that, see backfill.sql).
# Not needed on an empty stack, nor when the view has been running.
recent_key="(LogAttributes['session.id'], toUInt64OrZero(LogAttributes['event.sequence']), Timestamp)"
missing="$("${CH[@]}" -q "SELECT count() FROM otel.otel_logs WHERE ServiceName = 'claude-code' AND Timestamp >= now() - INTERVAL 1 HOUR AND $recent_key NOT IN (SELECT session_id, seq, ts FROM cc.events_t WHERE ts >= now() - INTERVAL 1 HOUR)")"
if [ "$missing" != "0" ]; then
  echo "$missing recent events are not in cc.events_t yet: second pass in 35 s"
  sleep 35
  lo="$("${CH[@]}" -q "SELECT toString(now() - INTERVAL 1 HOUR)")"
  "${CH[@]}" --multiquery --param_lo="$lo" --param_hi="2100-01-01 00:00:00" --param_guard=5 < /init/backfill.sql
fi

"${CH[@]}" --multiquery < /init/views.sql
echo "cc.* views are ready"
