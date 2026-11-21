#!/bin/bash
# Rebuilds cc.session_project_t and cc.tips_t (refresh.sql) every 5 minutes. Started by the cc-refresh service
# after views-init has finished. The only place that runs refresh.sql (the staging tables have fixed names).
# A failed run is logged and repeated; nothing here may stop the loop (no set -e).
set -uo pipefail

# One thread: the refresh must not compete with the collector inserts and the dashboards.
CH=(clickhouse-client --host clickhouse --user otel --password "$CLICKHOUSE_PASSWORD" --max_threads 1)

# Normally views-init has finished (compose waits for it). After a reboot compose does not run it again, and
# the tables exist already; on a broken install wait for them rather than fail in a loop.
until [ "$("${CH[@]}" -q "EXISTS TABLE cc.session_project_t" 2>/dev/null)" = "1" ] \
   && [ "$("${CH[@]}" -q "EXISTS TABLE cc.tips_t" 2>/dev/null)" = "1" ]; do
  echo "waiting for cc.session_project_t and cc.tips_t"
  sleep 10
done

while true; do
  if "${CH[@]}" --multiquery < /init/refresh.sql; then
    echo "$(date -Is) refresh ok"
  else
    echo "$(date -Is) refresh FAILED, retrying in 300 s" >&2
  fi
  sleep 300
done
