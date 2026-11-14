#!/bin/bash
# Connects this PC's Claude Code to the cc-telemetry server (the counterpart of setup-client.ps1).
#
# Merges the telemetry keys into the "env" section of ~/.claude/settings.json and, for every --project
# folder, of <project>/.claude/settings.local.json. Other keys are left untouched; each file is backed up
# to <file>.bak before the first change. Per user: no sudo, nothing outside your home and the projects.
# Needs python3 or jq 1.6+. Everything is checked before the first file is written.
#
# Usage: bash setup-client.sh --server-ip <address> [--project <dir>]... [--pc-name <name>]
#                             [--settings-dir <dir>] [--user-settings <file>] [--dry-run] [--help]
set -euo pipefail

SERVER_IP=""
PC_NAME=""
PROJECTS=()
SETTINGS_DIR=".claude"
USER_SETTINGS="$HOME/.claude/settings.json"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash setup-client.sh --server-ip <address> [options]

  --server-ip <addr>       the server's address (required); localhost on the server PC itself
  --project <dir>          a folder you open in Claude Code; repeat for more
  --pc-name <name>         name shown as "host" (default: hostname -s); letters, digits, . _ -
  --settings-dir <dir>     project settings folder (default: .claude)
  --user-settings <file>   user settings file (default: ~/.claude/settings.json)
  --dry-run                show the result, write nothing
  --help                   this text
EOF
}

die() { echo "ERROR: $1" >&2; exit 1; }

need_value() { [ "$2" -ge 2 ] || die "$1 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --server-ip) need_value "$1" $#; SERVER_IP="$2"; shift ;;
    --pc-name) need_value "$1" $#; PC_NAME="$2"; shift ;;
    --project) need_value "$1" $#; PROJECTS+=("$2"); shift ;;
    --settings-dir) need_value "$1" $#; SETTINGS_DIR="$2"; shift ;;
    --user-settings) need_value "$1" $#; USER_SETTINGS="$2"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$SERVER_IP" ] || { usage >&2; die '--server-ip is required'; }
[[ "$SERVER_IP" =~ ^[A-Za-z0-9._-]+$ ]] || die "--server-ip '$SERVER_IP' must be a host name or IPv4 address"
[ -n "$PC_NAME" ] || PC_NAME="$(hostname -s 2>/dev/null || hostname)"
[[ "$PC_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "--pc-name '$PC_NAME' may contain only letters, digits, . _ -"

# python3 is preferred; jq must be 1.6+ (needs $ARGS), older versions are not used.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then TOOL=python3
elif command -v jq >/dev/null 2>&1 && jq -n '$ARGS' >/dev/null 2>&1; then TOOL=jq
else die 'python3, or jq 1.6 or newer, is required to edit the JSON settings. Install one (for example: sudo apt install jq) and run again.'
fi

# merge_json <file> KEY=VALUE...  ->  prints the file's JSON with the pairs merged into "env".
# A missing, empty or whitespace-only file counts as {}. Fails when the file is not valid JSON or not an object.
merge_json() {
  local file="$1"; shift
  if [ "$TOOL" = jq ]; then
    local args=() pair
    for pair in "$@"; do args+=(--arg "${pair%%=*}" "${pair#*=}"); done
    local add
    add="$(jq -n '$ARGS.named' "${args[@]}")"
    if [ -s "$file" ] && grep -q '[^[:space:]]' "$file"; then
      jq --argjson add "$add" \
        'if type != "object" then error("top level is not a JSON object") else . end
         | if has("env") and (.env | type) != "object" then error("\"env\" is not an object") else . end
         | .env = ((.env // {}) + $add)' "$file"
    else
      jq -n --argjson add "$add" '{env: $add}'
    fi
  else
    python3 - "$file" "$@" <<'PY'
import json, os, sys
path, pairs = sys.argv[1], sys.argv[2:]
text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
try:
    obj = json.loads(text) if text.strip() else {}
except ValueError as e:
    sys.exit("invalid JSON: %s" % e)
if not isinstance(obj, dict):
    sys.exit("top level is not a JSON object")
env = obj.setdefault("env", {})
if not isinstance(env, dict):
    sys.exit('"env" is not an object')
for pair in pairs:
    key, _, value = pair.partition("=")
    env[key] = value
print(json.dumps(obj, indent=2, ensure_ascii=False))
PY
  fi
}

valid_json() { # file
  if [ "$TOOL" = jq ]; then jq -e 'type == "object"' "$1" >/dev/null
  else python3 -c 'import json,sys; assert isinstance(json.load(open(sys.argv[1], encoding="utf-8")), dict)' "$1"
  fi
}

# Two phases: prepare_settings merges everything in memory (any bad input stops the script before
# the first write), write_settings then writes the files.
TARGET_FILES=()
TARGET_JSON=()

# prepare_settings <file> KEY=VALUE...
prepare_settings() {
  local file="$1"; shift
  local json
  json="$(merge_json "$file" "$@")" || die "cannot merge into $file (is it valid JSON?)"
  [ -n "$json" ] || die "refusing to write an empty result for $file"
  TARGET_FILES+=("$file")
  TARGET_JSON+=("$json")
}

write_settings() {
  local i file json
  for i in "${!TARGET_FILES[@]}"; do
    file="${TARGET_FILES[$i]}"; json="${TARGET_JSON[$i]}"
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "--- $file (not written)"
      printf '%s\n' "$json"
      continue
    fi
    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ] && [ ! -e "$file.bak" ]; then cp -p "$file" "$file.bak"; fi
    # Plain redirection keeps the file's mode and follows a symlinked folder or file.
    printf '%s\n' "$json" > "$file"
    valid_json "$file" || die "$file is not valid JSON after the update; restore it from $file.bak"
    echo "updated $file"
  done
}

# Keep in step with client/user-settings.env.json and client/setup-client.ps1.
prepare_settings "$USER_SETTINGS" \
  "CLAUDE_CODE_ENABLE_TELEMETRY=1" \
  "OTEL_LOGS_EXPORTER=otlp" \
  "OTEL_METRICS_EXPORTER=otlp" \
  "OTEL_EXPORTER_OTLP_PROTOCOL=grpc" \
  "OTEL_EXPORTER_OTLP_ENDPOINT=http://${SERVER_IP}:4317" \
  "OTEL_LOG_TOOL_DETAILS=1" \
  "OTEL_LOG_USER_PROMPTS=1" \
  "OTEL_LOGS_EXPORT_INTERVAL=2000" \
  "OTEL_RESOURCE_ATTRIBUTES=project=unknown,host=${PC_NAME}"

for p in ${PROJECTS[@]+"${PROJECTS[@]}"}; do
  full="$(cd "$p" 2>/dev/null && pwd)" || die "project folder not found: $p"
  name="$(basename "$full" | tr '[:upper:]' '[:lower:]')"
  prepare_settings "$full/$SETTINGS_DIR/settings.local.json" \
    "OTEL_RESOURCE_ATTRIBUTES=project=${name},host=${PC_NAME}"
done
write_settings

reachable=False
if command -v timeout >/dev/null 2>&1; then
  timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$SERVER_IP" 4317 2>/dev/null && reachable=True
else
  bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$SERVER_IP" 4317 2>/dev/null && reachable=True
fi
echo "server ${SERVER_IP}:4317 reachable: ${reachable}"
echo 'Restart Claude Code sessions (VS Code: reload the window; CLI: claude -c) to start sending telemetry.'
