#!/bin/bash
# Dumps or restores all otel.* tables (ClickHouse Native format) to/from ./backup/<table>.native.
# Usage (from the cc-telemetry folder):  wsl -d Ubuntu -- bash linux-server-tools/backup.sh dump|restore [table]
# restore appends rows, so run it on an empty stack (fresh install), after setup-server.ps1.
# BACKUP_DIR=<folder> (default: backup) selects another folder for dump and restore, e.g. the
# backup/pre-update-<time> folder that  setup-server.sh --update  writes.
set -euo pipefail
cd "$(dirname "$0")/.."
CH=(bash linux-server-tools/ch.sh)
DIR="${BACKUP_DIR:-backup}"
mkdir -p "$DIR"
case "${1:-}" in
  dump)
    tables="$(echo "SHOW TABLES FROM otel" | "${CH[@]}")" || { echo "dump: could not list the otel tables (is the stack up?)" >&2; exit 1; }
    for t in $tables; do
      echo "SELECT * FROM otel.$t FORMAT Native" | "${CH[@]}" > "$DIR/$t.native"
      echo "$t: $(echo "SELECT count() FROM otel.$t" | "${CH[@]}") rows -> $DIR/$t.native ($(stat -c %s "$DIR/$t.native") bytes)"
    done ;;
  restore)   # optional 2nd argument: one table name
    for f in "$DIR"/${2:-*}.native; do
      t=$(basename "$f" .native)
      if [ ! -s "$f" ]; then echo "$t: empty, skipped"; continue; fi
      if [ "$(echo "EXISTS TABLE otel.$t" | "${CH[@]}")" != "1" ]; then echo "$t: no such table yet, skipped"; continue; fi
      "${CH[@]}" -q "INSERT INTO otel.$t FORMAT Native" < "$f"
      echo "$t: now $(echo "SELECT count() FROM otel.$t" | "${CH[@]}") rows"
    done ;;
  *) echo "usage: $0 dump|restore" >&2; exit 2 ;;
esac
