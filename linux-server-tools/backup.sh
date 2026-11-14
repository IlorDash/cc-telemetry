#!/bin/bash
# Dumps or restores all otel.* tables (ClickHouse Native format) to/from ./backup/<table>.native.
# Usage (from the cc-telemetry folder):  wsl -d Ubuntu -- bash linux-server-tools/backup.sh dump|restore [table]
# restore appends rows, so run it on an empty stack (fresh install), after setup-server.ps1.
set -euo pipefail
cd "$(dirname "$0")/.."
CH=(bash linux-server-tools/ch.sh)
mkdir -p backup
case "${1:-}" in
  dump)
    for t in $(echo "SHOW TABLES FROM otel" | "${CH[@]}"); do
      echo "SELECT * FROM otel.$t FORMAT Native" | "${CH[@]}" > "backup/$t.native"
      echo "$t: $(echo "SELECT count() FROM otel.$t" | "${CH[@]}") rows -> backup/$t.native ($(stat -c %s "backup/$t.native") bytes)"
    done ;;
  restore)   # optional 2nd argument: one table name
    for f in backup/${2:-*}.native; do
      t=$(basename "$f" .native)
      if [ ! -s "$f" ]; then echo "$t: empty, skipped"; continue; fi
      if [ "$(echo "EXISTS TABLE otel.$t" | "${CH[@]}")" != "1" ]; then echo "$t: no such table yet, skipped"; continue; fi
      "${CH[@]}" -q "INSERT INTO otel.$t FORMAT Native" < "$f"
      echo "$t: now $(echo "SELECT count() FROM otel.$t" | "${CH[@]}") rows"
    done ;;
  *) echo "usage: $0 dump|restore" >&2; exit 2 ;;
esac
