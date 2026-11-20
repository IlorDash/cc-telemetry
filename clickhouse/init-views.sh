#!/bin/bash
# Waits for the collector to create otel.otel_logs, sets the retention TTL of the otel.* tables that have none,
# then builds the cc.* layer: tables and the materialized view (schema.sql), the backfill of cc.events_t
# (backfill.sql, one month at a time), the views (views.sql). The derived tables are filled by the cc-refresh
# service, which starts after this script.
# RETENTION_DAYS (from .env through docker-compose.yml, default 365) is the retention of cc.events_t (the
# __RETENTION_DAYS__ placeholder of schema.sql) and of the otel.* tables created here.
set -euo pipefail

CH=(clickhouse-client --host clickhouse --user otel --password "$CLICKHOUSE_PASSWORD")

RETENTION_DAYS="${RETENTION_DAYS:-365}"
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || { echo "RETENTION_DAYS='$RETENTION_DAYS' is not a number of days (RETENTION_DAYS in .env)" >&2; exit 1; }

for i in $(seq 1 120); do
  if [ "$("${CH[@]}" -q "EXISTS TABLE otel.otel_logs" 2>/dev/null || true)" = "1" ]; then
    break
  fi
  echo "waiting for otel.otel_logs ($i/120)"
  sleep 5
done

# The collector creates the metrics tables at the same start as otel_logs: give them a minute, then go on with
# whatever exists (a table that comes later gets its TTL on the next run).
for i in $(seq 1 12); do
  [ "$("${CH[@]}" -q "SELECT count() FROM system.tables WHERE database = 'otel' AND startsWith(name, 'otel_metrics_')" 2>/dev/null || true)" -ge 5 ] 2>/dev/null && break
  sleep 5
done

# Retention of the otel.* tables: the collector creates them without a TTL. A table that has none gets it here,
# unless rows older than the retention exist (the TTL would delete them: that is a decision of the user, see
# README "Retention"; setup-server.sh asks). An existing TTL is never changed here.
tables="$("${CH[@]}" -q "SELECT name FROM system.tables WHERE database = 'otel' AND (name = 'otel_logs' OR startsWith(name, 'otel_metrics_')) AND position(engine_full, ' TTL ') = 0 ORDER BY name")"
for t in $tables; do
  if [ "$t" = otel_logs ]; then col=TimestampTime; else col='toDateTime(TimeUnix)'; fi
  old="$("${CH[@]}" -q "SELECT count() FROM otel.$t WHERE $col < now() - INTERVAL $RETENTION_DAYS DAY")"
  if [ "$old" = 0 ]; then
    "${CH[@]}" -q "ALTER TABLE otel.$t MODIFY TTL $col + toIntervalDay($RETENTION_DAYS)"
    echo "otel.$t: TTL $RETENTION_DAYS days set"
  else
    echo "otel.$t has no TTL and $old rows older than $RETENTION_DAYS days: left as it is (the TTL would delete them, see README, Retention)"
  fi
done

# Columns added to cc.events_t after it was first created (account_uuid, status_code, error). The materialized
# view fills them only for new events, so an older table is rebuilt once from otel.otel_logs: a copy with the
# same layout (partitions, TTL: setup-server.sh migrates the layout itself) plus the missing columns at the end
# (the column order of schema.sql and backfill.sql), filled month by month with backfill.sql, checked against
# the old table and swapped in. The old view is dropped first: schema.sql creates the new one, and the backfill
# below copies the events that arrived meanwhile. cc.events_t holds only a copy of otel.otel_logs.
# An interrupted run starts the copy again (cc.events_t still lacks the columns) or drops the checked old table.
col_n() { "${CH[@]}" -q "SELECT count() FROM system.columns WHERE database = 'cc' AND table = '$1' AND name = 'account_uuid'"; }
if [ "$("${CH[@]}" -q "EXISTS TABLE cc.events_t")" = 1 ] && [ "$(col_n events_t)" = 0 ]; then
  echo "cc.events_t has no account_uuid, status_code, error: rebuilding it from otel.otel_logs (once)"
  cutoff="$("${CH[@]}" -q "SELECT toString(now() - INTERVAL 1 MINUTE)")"
  "${CH[@]}" -q "DROP VIEW IF EXISTS cc.events_mv"
  "${CH[@]}" -q "DROP TABLE IF EXISTS cc.events_t_cols SYNC"
  "${CH[@]}" -q "CREATE TABLE cc.events_t_cols AS cc.events_t"
  "${CH[@]}" -q "ALTER TABLE cc.events_t_cols ADD COLUMN account_uuid LowCardinality(String), ADD COLUMN status_code UInt32, ADD COLUMN error String CODEC(ZSTD(1))"
  months="$("${CH[@]}" -q "SELECT DISTINCT toStartOfMonth(toDate(TimestampTime)) AS m, addMonths(m, 1) FROM otel.otel_logs WHERE ServiceName = 'claude-code' ORDER BY m")"
  while IFS=$'\t' read -r lo hi; do
    [ -n "$lo" ] || continue
    echo "  copy ${lo%-*}"
    sed 's/cc\.events_t\b/cc.events_t_cols/g' /init/backfill.sql \
      | "${CH[@]}" --multiquery --param_lo="$lo 00:00:00" --param_hi="$hi 00:00:00" --param_guard=30
  done <<<"$months"
  # Every row of the old table older than the start must be in the copy, with the same tokens and cost.
  # Month by month: the set of keys of one month stays within the per-query memory limit.
  cmp="SELECT count(), sum(input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens), round(sum(cost_usd), 4) FROM"
  old_months="$("${CH[@]}" -q "SELECT DISTINCT toStartOfMonth(toDate(ts)) AS m, addMonths(m, 1) FROM cc.events_t ORDER BY m")"
  while IFS=$'\t' read -r lo hi; do
    [ -n "$lo" ] || continue
    w="ts >= toDateTime64('$lo 00:00:00', 9) AND ts < toDateTime64('$hi 00:00:00', 9) AND ts < toDateTime64('$cutoff', 9)"
    old="$("${CH[@]}" -q "$cmp cc.events_t WHERE $w")"
    new="$("${CH[@]}" -q "$cmp cc.events_t_cols WHERE $w AND (session_id, seq, ts) IN (SELECT session_id, seq, ts FROM cc.events_t WHERE $w)")"
    if [ "$old" != "$new" ]; then
      echo "The rebuilt cc.events_t_cols does not match cc.events_t in ${lo%-*} (rows/tokens/cost: old $old, copy $new): nothing was swapped." >&2
      echo "cc.events_mv is dropped meanwhile: new events stay in otel.otel_logs and are copied on the next successful run." >&2
      exit 1
    fi
  done <<<"$old_months"
  "${CH[@]}" -q "EXCHANGE TABLES cc.events_t AND cc.events_t_cols"
  echo "cc.events_t rebuilt with the new columns (rows, tokens and cost checked month by month)"
fi
# The old table after a checked swap (also when a previous run stopped right after it).
if [ "$("${CH[@]}" -q "EXISTS TABLE cc.events_t_cols")" = 1 ] && [ "$(col_n events_t_cols)" = 0 ] && [ "$(col_n events_t)" = 1 ]; then
  "${CH[@]}" -q "DROP TABLE cc.events_t_cols SYNC"
fi

sed "s/__RETENTION_DAYS__/$RETENTION_DAYS/g" /init/schema.sql | "${CH[@]}" --multiquery

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
