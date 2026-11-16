#!/bin/bash
# Connects this PC's Claude Code to the cc-telemetry server (the counterpart of setup-client.ps1).
#
# Merges the telemetry keys into the "env" section of ~/.claude/settings.json and, for every --project
# folder, of <project>/.claude/settings.local.json. Other keys are left untouched; each file is backed up
# to <file>.bak before the first change. Per user: no sudo, nothing outside your home and the projects.
# Needs python3 or jq 1.6+. Everything is checked before the first file is written.
# The session-meta hook script (Linux only) needs bash 4+ (associative arrays) and GNU find
# (-newermt), plus python3 or jq, and curl or python3.
#
# Usage: bash setup-client.sh --server-ip <address> [--project <dir>]... [--pc-name <name>]
#                             [--settings-dir <dir>] [--user-settings <file>] [--no-session-meta]
#                             [--import-history] [--dry-run] [--help]
#
# Also installs a small hook (UserPromptSubmit, async) that sends each session's title, git branch and
# working directory to the server (OTLP/JSON, port 4318). The hook script is written next to the user
# settings (<settings folder>/cc-telemetry/session-meta.sh) and registered under "hooks"; other hooks are
# kept. --no-session-meta skips it (and removes it on a re-run). --import-history sends the sessions that
# are already on this PC once (<settings folder>/projects; only title, branch and folder are read).
set -euo pipefail

SERVER_IP=""
PC_NAME=""
PROJECTS=()
SETTINGS_DIR=".claude"
USER_SETTINGS="$HOME/.claude/settings.json"
DRY_RUN=0
NO_META=0
IMPORT=0

usage() {
  cat <<'EOF'
Usage: bash setup-client.sh --server-ip <address> [options]

  --server-ip <addr>       the server's address (required); localhost on the server PC itself
  --project <dir>          a folder you open in Claude Code; repeat for more
  --pc-name <name>         name shown as "host" (default: hostname -s); letters, digits, . _ -
  --settings-dir <dir>     project settings folder (default: .claude)
  --user-settings <file>   user settings file (default: ~/.claude/settings.json)
  --no-session-meta        do not install the session title/branch hook (removes it if installed)
  --import-history         send title/branch/folder of the sessions already on this PC, once
                           (the hook script needs bash 4+ and GNU find)
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
    --no-session-meta) NO_META=1 ;;
    --import-history) IMPORT=1 ;;
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
[ "$NO_META" -eq 0 ] || [ "$IMPORT" -eq 0 ] || die '--import-history cannot be combined with --no-session-meta'
case "$USER_SETTINGS" in /*) ;; *) USER_SETTINGS="$PWD/$USER_SETTINGS" ;; esac
CFG_DIR="$(dirname "$USER_SETTINGS")"
META_SCRIPT="$CFG_DIR/cc-telemetry/session-meta.sh"
HOOK_SERVER="$SERVER_IP"; [ "$HOOK_SERVER" != localhost ] || HOOK_SERVER=127.0.0.1
# Single-quote the path for the shell that runs the hook ('  ->  '\'' ).
quoted_path="'${META_SCRIPT//\'/\'\\\'\'}'"
HOOK_COMMAND="bash ${quoted_path} --server ${HOOK_SERVER} --pc-name ${PC_NAME}"

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

# hook_json <add|remove>  ->  settings JSON on stdin, printed with our UserPromptSubmit hook added/updated or
# removed. Our entry is the one whose command contains cc-telemetry/session-meta: updated in place, never
# duplicated; every other hook stays. Fails when "hooks" or its UserPromptSubmit list has the wrong type.
hook_json() {
  local mode="$1"
  if [ "$TOOL" = jq ]; then
    jq --arg cmd "$HOOK_COMMAND" --arg ev UserPromptSubmit --arg marker cc-telemetry/session-meta \
       --argjson remove "$([ "$mode" = remove ] && echo true || echo false)" '
      def ours: type == "object" and ((.command // "") | type == "string")
                and ((.command // "") | gsub("\\\\"; "/") | contains($marker));
      (if has("hooks") and (.hooks | type) != "object" then error("\"hooks\" is not an object") else . end)
      | (if ((.hooks // {}) | has($ev)) and ((.hooks[$ev] | type) != "array") then error("hooks list is not an array") else . end)
      | ((.hooks[$ev] // []) as $g0
         | (reduce $g0[] as $g ({groups: [], found: false};
             if ($g | type) == "object" and (($g.hooks // null) | type) == "array" then
               (reduce $g.hooks[] as $h ({inner: [], found: .found, touched: false};
                  if ($h | ours) then
                    if ($remove or .found) then .touched = true
                    else .touched = true | .found = true
                         | .inner += [({timeout: 60} + $h + {type: "command", command: $cmd, async: true})]
                    end
                  else .inner += [$h] end)) as $r
               | .found = $r.found
               | if ($r.touched and ($r.inner | length) == 0) then .
                 else .groups += [(if $r.touched then ($g | .hooks = $r.inner) else $g end)] end
             else .groups += [$g] end)) as $res
         | (if ($remove | not) and ($res.found | not)
              then $res.groups + [{hooks: [{type: "command", command: $cmd, async: true, timeout: 60}]}]
              else $res.groups end) as $groups
         | if ($groups | length) > 0 then .hooks = ((.hooks // {}) + {($ev): $groups})
           else del(.hooks[$ev]) | (if has("hooks") and .hooks == {} then del(.hooks) else . end) end)'
  else
    python3 -c '
import json, sys
mode, cmd = sys.argv[1], sys.argv[2]
EV, MARKER = "UserPromptSubmit", "cc-telemetry/session-meta"
obj = json.load(sys.stdin)
hooks = obj.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    sys.exit("\"hooks\" is not an object")
groups = hooks.get(EV, [])
if not isinstance(groups, list):
    sys.exit("hooks list is not an array")
found, new = False, []
for g in groups:
    if isinstance(g, dict) and isinstance(g.get("hooks"), list):
        inner, touched = [], False
        for h in g["hooks"]:
            ours = isinstance(h, dict) and isinstance(h.get("command"), str) and MARKER in h["command"].replace("\\", "/")
            if not ours:
                inner.append(h)
                continue
            touched = True
            if mode == "remove" or found:
                continue
            found = True
            h["type"], h["command"], h["async"] = "command", cmd, True
            h.setdefault("timeout", 60)
            inner.append(h)
        if touched and not inner:
            continue
        if touched:
            g["hooks"] = inner
    new.append(g)
if mode != "remove" and not found:
    new.append({"hooks": [{"type": "command", "command": cmd, "async": True, "timeout": 60}]})
if new:
    hooks[EV] = new
    obj["hooks"] = hooks
else:
    hooks.pop(EV, None)
    if hooks:
        obj["hooks"] = hooks
    else:
        obj.pop("hooks", None)
print(json.dumps(obj, indent=2, ensure_ascii=False))
' "$mode" "$HOOK_COMMAND"
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
hook_mode=add; [ "$NO_META" -eq 0 ] || hook_mode=remove
TARGET_JSON[0]="$(printf '%s\n' "${TARGET_JSON[0]}" | hook_json "$hook_mode")" \
  || die "cannot change the hooks in $USER_SETTINGS (unexpected \"hooks\" layout?)"

# The hook script, written next to the user settings; rewritten on every run so a re-run updates it.
write_hook_script() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "--- $META_SCRIPT (not written)"; return; fi
  mkdir -p "$(dirname "$META_SCRIPT")"
  cat > "$META_SCRIPT" <<'CCT_HOOK_EOF'
#!/bin/bash
# cc-telemetry session-meta hook. Written by setup-client.sh - edits are overwritten on the next run.
# Sends session title, git branch and working directory (never prompts or answers) to the server.
# Hook mode (stdin = UserPromptSubmit JSON): silent, always exit 0. --import-history: prints counts.
SERVER=""; PC=""; ROOT=""; IMPORT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --server) SERVER="${2:-}"; shift ;;
    --pc-name) PC="${2:-}"; shift ;;
    --projects-root) ROOT="${2:-}"; shift ;;
    --import-history) IMPORT=1 ;;
  esac
  shift
done
[ "$IMPORT" -eq 1 ] || exec >/dev/null
exec 2>/dev/null
[ "$SERVER" != localhost ] || SERVER=127.0.0.1
DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$DIR/session-meta.state"
KEY="$SERVER|$PC"
URL="http://$SERVER:4318/v1/logs"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then TOOL=python3
elif command -v jq >/dev/null 2>&1; then TOOL=jq
else exit 0
fi
if command -v curl >/dev/null 2>&1; then POST=curl
elif [ "$TOOL" = python3 ]; then POST=python3
else exit 0
fi
if command -v sha1sum >/dev/null 2>&1; then HASH=(sha1sum)
elif command -v md5sum >/dev/null 2>&1; then HASH=(md5sum)
else HASH=(cksum)
fi

PY_META='
import json, re, sys
path, sid = sys.argv[1], sys.argv[2]
ct = at = b = c = v = ""
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        if not ("custom-title" in line or "ai-title" in line or "gitBranch" in line or "cwd" in line):
            continue
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if not isinstance(o, dict):
            continue
        t = o.get("type")
        if t == "custom-title" and isinstance(o.get("customTitle"), str) and o["customTitle"]:
            ct = o["customTitle"]
        elif t == "ai-title" and isinstance(o.get("aiTitle"), str) and o["aiTitle"]:
            at = o["aiTitle"]
        if isinstance(o.get("gitBranch"), str) and o["gitBranch"]:
            b = o["gitBranch"]
        if not c and isinstance(o.get("cwd"), str) and o["cwd"]:
            c = o["cwd"]
        if isinstance(o.get("version"), str) and re.match(r"^[0-9]+(\.[0-9]+)+$", o["version"]):
            v = o["version"]
title = ct or at
src = "custom" if ct else ("ai" if at else "")
out = json.dumps({"sid": sid, "t": title, "ts": src, "b": b, "c": c, "v": v}, ensure_ascii=False, separators=(",", ":"))
sys.stdout.buffer.write((out + "\n").encode("utf-8", "replace"))
'
JQ_META='
reduce (inputs | fromjson? | select(type == "object")) as $l ({ct: "", at: "", b: "", c: "", v: ""};
    (if $l.type == "custom-title" and (($l.customTitle // "") | type == "string" and . != "") then .ct = $l.customTitle else . end)
  | (if $l.type == "ai-title" and (($l.aiTitle // "") | type == "string" and . != "") then .at = $l.aiTitle else . end)
  | (if (($l.gitBranch // "") | type == "string" and . != "") then .b = $l.gitBranch else . end)
  | (if .c == "" and (($l.cwd // "") | type == "string" and . != "") then .c = $l.cwd else . end)
  | (if (($l.version // "") | type == "string" and test("^[0-9]+(\\.[0-9]+)+$")) then .v = $l.version else . end))
| {sid: $sid, t: (if .ct != "" then .ct else .at end),
   ts: (if .ct != "" then "custom" elif .at != "" then "ai" else "" end), b: .b, c: .c, v: .v}'
PY_PAYLOAD='
import json, sys
host, now = sys.argv[1], sys.argv[2]
def a(k, v):
    return {"key": k, "value": {"stringValue": v}}
recs = []
for line in sys.stdin.buffer.read().decode("utf-8", "replace").splitlines():
    if not line.strip():
        continue
    m = json.loads(line)
    attrs = [a("event.name", "session_meta"), a("session.id", m["sid"]), a("title", m["t"]),
             a("title_source", m["ts"]), a("git_branch", m["b"]), a("cwd", m["c"])]
    if m["v"]:
        attrs.append(a("cc_version", m["v"]))
    recs.append({"timeUnixNano": now, "body": {"stringValue": "session_meta"}, "attributes": attrs})
doc = {"resourceLogs": [{"resource": {"attributes": [a("service.name", "cc-session-meta"), a("host", host)]},
       "scopeLogs": [{"scope": {"name": "cc-session-meta"}, "logRecords": recs}]}]}
sys.stdout.buffer.write(json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8", "replace"))
'
JQ_PAYLOAD='
def a($k; $v): {key: $k, value: {stringValue: $v}};
{resourceLogs: [{resource: {attributes: [a("service.name"; "cc-session-meta"), a("host"; $host)]},
  scopeLogs: [{scope: {name: "cc-session-meta"},
    logRecords: [.[] | {timeUnixNano: $now, body: {stringValue: "session_meta"},
      attributes: ([a("event.name"; "session_meta"), a("session.id"; .sid), a("title"; .t), a("title_source"; .ts),
                    a("git_branch"; .b), a("cwd"; .c)] + (if .v != "" then [a("cc_version"; .v)] else [] end))}]}]}]}'
PY_POST='
import sys, urllib.request
req = urllib.request.Request(sys.argv[1], data=sys.stdin.buffer.read(), headers={"Content-Type": "application/json"})
sys.exit(0 if urllib.request.urlopen(req, timeout=5).status == 200 else 1)
'
PY_TP='import json, sys; sys.stdout.buffer.write(json.loads(sys.stdin.buffer.read().decode("utf-8", "replace")).get("transcript_path", "").encode("utf-8", "replace"))'

meta_of() { # file sid -> one compact JSON line
  if [ "$TOOL" = python3 ]; then python3 -c "$PY_META" "$1" "$2"
  else grep -aE 'custom-title|ai-title|gitBranch|cwd' "$1" | jq -nRc --arg sid "$2" "$JQ_META"
  fi
}

send_lines() { # stdin = meta lines -> 0 when the server answered 200
  local now body
  now="$(date +%s)000000000"
  if [ "$TOOL" = python3 ]; then body="$(python3 -c "$PY_PAYLOAD" "$PC" "$now")"
  else body="$(jq -sc --arg host "$PC" --arg now "$now" "$JQ_PAYLOAD")"
  fi
  [ -n "$body" ] || return 1
  if [ "$POST" = curl ]; then
    [ "$(printf '%s' "$body" | curl -s -m 5 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$URL")" = 200 ]
  else
    printf '%s' "$body" | python3 -c "$PY_POST" "$URL"
  fi
}

declare -A ST
SCAN=0; FAIL=0
load_state() { # fills ST / SCAN from the state file when its key matches
  local head sid h rest
  ST=(); SCAN=0; FAIL=0
  [ -f "$STATE" ] || return 0
  IFS= read -r head < "$STATE" || return 0
  [ "${head%%$'\t'*}" = "#$KEY" ] || return 0
  rest="${head#*$'\t'}"   # header: #key <TAB> scan <TAB> time of the last failed send
  SCAN="${rest%%$'\t'*}"; [[ "$SCAN" =~ ^[0-9]+$ ]] || SCAN=0
  case "$rest" in *$'\t'*) FAIL="${rest#*$'\t'}" ;; esac; [[ "$FAIL" =~ ^[0-9]+$ ]] || FAIL=0
  while IFS=$'\t' read -r sid h; do
    case "$sid" in '#'*|'') continue ;; esac
    ST["$sid"]="$h"
  done < "$STATE"
}

save_state() { # scan fail  (SENT holds sid -> hash); merges into the file as it is now, then renames atomically
  local scan="$1" fail="$2" sid tmp
  load_state
  [ "$scan" -gt 0 ] && SCAN="$scan"
  for sid in "${!SENT[@]}"; do ST["$sid"]="${SENT[$sid]}"; done
  tmp="$(mktemp "$STATE.XXXXXX")" || return 0
  { printf '#%s\t%s\t%s\n' "$KEY" "$SCAN" "$fail"
    for sid in "${!ST[@]}"; do printf '%s\t%s\n' "$sid" "${ST[$sid]}"; done
  } > "$tmp" && mv -f "$tmp" "$STATE" || rm -f "$tmp"
}

declare -A SENT
FOUND=0; N_SENT=0; UNCHANGED=0; FAILED=0

main() {
  local start tp line f sid sig lines i n down chunk scan fail
  start="$(date +%s)"
  load_state
  # Back-off: after a failed send (server down) hook runs do nothing for 10 minutes - no 5 s wait on every
  # prompt, no re-parsing. Afterwards the next run retries; the unchanged scan time re-includes the files.
  if [ "$IMPORT" -eq 0 ] && [ "$FAIL" -gt 0 ] && [ $((start - FAIL)) -ge 0 ] && [ $((start - FAIL)) -lt 600 ]; then return 0; fi
  local files=()
  declare -A seen
  if [ "$IMPORT" -eq 0 ]; then
    tp="$(if [ "$TOOL" = python3 ]; then python3 -c "$PY_TP"; else jq -r '.transcript_path // empty'; fi)"
    [ -n "$tp" ] || return 0
    ROOT="$(dirname "$(dirname "$tp")")"
    if [ -f "$tp" ]; then files+=("$tp"); seen["$tp"]=1; fi
  fi
  [ -n "$ROOT" ] && [ -n "$SERVER" ] && [ -n "$PC" ] || return 0
  # Files changed since the last scan (a margin covers writes that raced with it); no scan yet = only this session.
  if [ -d "$ROOT" ] && { [ "$IMPORT" -eq 1 ] || [ "$SCAN" -gt 0 ]; }; then
    local find_args=(-mindepth 2 -maxdepth 2 -type f -name '*.jsonl' ! -name 'agent-*')
    [ "$IMPORT" -eq 1 ] || find_args+=(-newermt "@$((SCAN - 120))")
    while IFS= read -r -d '' f; do
      [ -z "${seen[$f]:-}" ] || continue
      files+=("$f"); seen["$f"]=1
    done < <(find "$ROOT" "${find_args[@]}" -print0)
  fi
  local p_sid=() p_sig=() p_line=()
  for f in ${files[@]+"${files[@]}"}; do
    FOUND=$((FOUND + 1))
    sid="$(basename "$f" .jsonl)"
    line="$(meta_of "$f" "$sid")"
    [ -n "$line" ] || { FAILED=$((FAILED + 1)); continue; }
    if [[ "$line" == *'"t":"","ts":"","b":"","c":""'* ]]; then UNCHANGED=$((UNCHANGED + 1)); continue; fi
    sig="$(printf '%s' "$line" | sed 's/,"v":"[^"]*"}$/}/' | "${HASH[@]}" | cut -d' ' -f1)"
    if [ "${ST[$sid]:-}" = "$sig" ]; then UNCHANGED=$((UNCHANGED + 1)); continue; fi
    p_sid+=("$sid"); p_sig+=("$sig"); p_line+=("$line")
  done
  n=${#p_sid[@]}; down=0
  for ((i = 0; i < n; i += 100)); do
    chunk=$((n - i < 100 ? n - i : 100))
    if [ "$down" -eq 0 ] && printf '%s\n' "${p_line[@]:i:chunk}" | send_lines; then
      N_SENT=$((N_SENT + chunk))
      for ((j = i; j < i + chunk; j++)); do SENT["${p_sid[$j]}"]="${p_sig[$j]}"; done
    else
      down=1; FAILED=$((FAILED + chunk))
    fi
  done
  # A failed send keeps the old scan time so the next run looks at those files again.
  scan=0; [ "$FAILED" -gt 0 ] || scan="$start"
  fail=0; [ "$down" -eq 0 ] || fail="$start"
  save_state "$scan" "$fail"
}

main || true
[ "$IMPORT" -eq 0 ] || echo "found $FOUND, sent $N_SENT, unchanged $UNCHANGED, failed $FAILED"
exit 0
CCT_HOOK_EOF
  chmod 700 "$META_SCRIPT"
  echo "updated $META_SCRIPT"
}

for p in ${PROJECTS[@]+"${PROJECTS[@]}"}; do
  full="$(cd "$p" 2>/dev/null && pwd)" || die "project folder not found: $p"
  name="$(basename "$full" | tr '[:upper:]' '[:lower:]')"
  prepare_settings "$full/$SETTINGS_DIR/settings.local.json" \
    "OTEL_RESOURCE_ATTRIBUTES=project=${name},host=${PC_NAME}"
done
[ "$NO_META" -eq 1 ] || write_hook_script   # the script file comes before the settings entry that points to it
write_settings
if [ "$NO_META" -eq 1 ]; then
  # Remove only our own files, then the folder if nothing else is in it.
  meta_dir="$(dirname "$META_SCRIPT")"
  for f in "$META_SCRIPT" "$meta_dir"/session-meta.state "$meta_dir"/session-meta.state.??????; do
    [ -f "$f" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then echo "would delete $f"; else rm -f "$f" && echo "deleted $f"; fi
  done
  [ "$DRY_RUN" -eq 1 ] || rmdir "$meta_dir" 2>/dev/null || true
fi

# tcp_ok <host> <port>  ->  prints True/False
tcp_ok() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null && echo True || echo False
  else
    bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null && echo True || echo False
  fi
}
echo "server ${SERVER_IP}:4317 reachable: $(tcp_ok "$SERVER_IP" 4317)"
if [ "$NO_META" -eq 0 ]; then
  meta_ok="$(tcp_ok "$HOOK_SERVER" 4318)"
  echo "server ${HOOK_SERVER}:4318 (session titles) reachable: ${meta_ok}"
  [ "$meta_ok" = True ] || echo 'Session titles are sent only once port 4318 is reachable (update and re-run the server setup).'
fi
if [ "$IMPORT" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then echo "import of $CFG_DIR/projects skipped (--dry-run)"
  else
    echo "importing session titles from $CFG_DIR/projects ..."
    bash "$META_SCRIPT" --server "$HOOK_SERVER" --pc-name "$PC_NAME" --import-history --projects-root "$CFG_DIR/projects"
  fi
fi
echo 'Restart Claude Code sessions (VS Code: reload the window; CLI: claude -c) to start sending telemetry.'
