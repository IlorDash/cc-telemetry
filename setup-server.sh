#!/bin/bash
# Sets up the cc-telemetry server on this Linux PC (the counterpart of setup-server.ps1).
#
#  1. Docker: Docker Engine + compose plugin present and answering (offers to install on Debian/Ubuntu).
#  2. .env with random passwords (an existing .env is kept) and the bind addresses
#     OTLP_BIND (port 4317) and GRAFANA_BIND (Grafana), the Grafana host port GRAFANA_PORT (default
#     3000) and, on ARM CPUs too old for current ClickHouse (Raspberry Pi 4), CLICKHOUSE_VERSION.
#  3. Starts the stack and waits until the cc.* views are created.
#  4. Checks Grafana and the OTLP port (:4317) on this PC; checks that Docker starts at boot.
#  5. LAN (the default, Linux servers are usually headless): 4317 and Grafana are published on all
#     interfaces and opened in ufw / firewalld; prints the server address and the client commands.
#     --local-only keeps both ports on this PC.
#
# Safe to re-run: every step checks what is already done. A re-run without --lan / --local-only
# keeps the exposure already written to .env.
#
# Update (--update): safety dump + row counts, git pull --ff-only, then this script runs again from
# the updated file, and the row counts are compared at the end. See --help.
#
# Usage: bash setup-server.sh [--local-only | --lan] [--lan-ip <address>] [--grafana-port <n>]
#                             [--clickhouse-version <tag>] [--update] [--yes] [--help]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE=""        # "" = keep .env (new keys: LAN), lan, local
LAN_IP=""
GRAFANA_PORT_FLAG=""
CH_VERSION_FLAG=""
YES=0
UPDATE=0
PASS=("$@")    # the arguments for the re-run after an update
UPDATE_DIR=""    # set by the update's re-run: the folder with the safety dump
UPDATE_PREV=""   # commit before the pull
# Only the update's own re-exec (CCT_UPDATE=1) passes these; stale variables in a shell are ignored.
# The folder must exist under backup/ (relative to this folder, or the same path made absolute).
if [ "${CCT_UPDATE:-}" = 1 ] && [ -n "${CCT_UPDATE_DIR:-}" ]; then
  case "$CCT_UPDATE_DIR" in
    *..*) ;;
    backup/*|"$ROOT"/backup/*)
      if [ -d "$CCT_UPDATE_DIR" ]; then UPDATE_DIR="$CCT_UPDATE_DIR"; UPDATE_PREV="${CCT_UPDATE_PREV:-}"; fi ;;
  esac
fi
unset CCT_UPDATE CCT_UPDATE_DIR CCT_UPDATE_PREV
UPD_DIR="$UPDATE_DIR"   # while set, a failing run prints the dump folder (and the rollback command, if UPD_PREV)
UPD_PREV="$UPDATE_PREV"
OLD_CH_TAG=23.3.22.3   # last release of ClickHouse 23.3, the newest line that runs on ARMv8.0 (Raspberry Pi 4)

usage() {
  cat <<'EOF'
Usage: bash setup-server.sh [options]

By default the server is reachable from other PCs of the LAN: OTLP port 4317 (clients) and
Grafana (port 3000, admin login) are published on all interfaces and opened in ufw / firewalld
(asks before using sudo). Plain HTTP and unauthenticated OTLP: trusted networks only.

  --local-only       publish 4317 and Grafana on this PC only (OTLP_BIND / GRAFANA_BIND = 127.0.0.1)
  --lan              switch back to all interfaces (0.0.0.0) after an earlier --local-only
                     (--enable-lan is the same)
  --lan-ip <addr>    the LAN address to report (when detected wrong)
  --grafana-port <n> host port of Grafana (1-65535, default 3000), kept as GRAFANA_PORT in .env;
                     use it when 3000 is taken by another program
  --clickhouse-version <tag>
                     ClickHouse image tag (CLICKHOUSE_VERSION in .env, default 25.8). On an ARM CPU
                     without lrcpc (Raspberry Pi 4) a missing key is set to 23.3.22.3 automatically
  --update           update a running server after a new version is published: stop Claude Code
                     sessions first, run this, start them again. It checks that ClickHouse answers and
                     that the git working tree has no local changes, dumps all data to
                     backup/pre-update-<time>/ (earlier dumps stay), records the row count per table,
                     runs `git pull --ff-only` (skipped with a warning when there is no upstream), runs
                     this script again from the updated file with your other options, and finally
                     checks that no table has fewer rows than before. Nothing is ever removed
                     (no `down -v`, volumes stay). Rollback: git checkout <previous commit>, then
                     bash setup-server.sh
  --yes              do not ask before installing Docker, using sudo or enabling the docker service
  --help             this text

Without --local-only / --lan an existing .env keeps its OTLP_BIND and GRAFANA_BIND; a missing
OTLP_BIND becomes 0.0.0.0, a missing GRAFANA_BIND copies OTLP_BIND (0.0.0.0 if that is missing too).
Any bind other than 127.0.0.1 / localhost counts as reachable from the LAN. Firewall rules added
earlier are not removed by --local-only.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local-only) [ "$MODE" != lan ] || { echo "--local-only and --lan exclude each other" >&2; exit 2; }; MODE=local ;;
    --lan|--enable-lan) [ "$MODE" != local ] || { echo "--local-only and --lan exclude each other" >&2; exit 2; }; MODE=lan ;;
    --lan-ip) [ $# -ge 2 ] || { echo "--lan-ip needs a value" >&2; exit 2; }; LAN_IP="$2"; shift
      [[ "$LAN_IP" =~ ^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]] \
        || { echo "--lan-ip '$LAN_IP' is not an IPv4 address (like 192.168.1.10)" >&2; exit 2; } ;;
    --grafana-port) [ $# -ge 2 ] || { echo "--grafana-port needs a value" >&2; exit 2; }; GRAFANA_PORT_FLAG="$2"; shift
      [[ "$GRAFANA_PORT_FLAG" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$GRAFANA_PORT_FLAG" -le 65535 ] \
        || { echo "--grafana-port '$GRAFANA_PORT_FLAG' is not a port number (1-65535)" >&2; exit 2; } ;;
    --clickhouse-version) [ $# -ge 2 ] || { echo "--clickhouse-version needs a value" >&2; exit 2; }; CH_VERSION_FLAG="$2"; shift
      [[ "$CH_VERSION_FLAG" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
        || { echo "--clickhouse-version '$CH_VERSION_FLAG' is not an image tag (like 25.8 or 23.3.22.3)" >&2; exit 2; } ;;
    --update) UPDATE=1 ;;
    --yes|-y) YES=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   OK   %s\n' "$1"; }
warn() { printf '   WARN %s\n' "$1"; }
fail() { printf '   FAIL %s\n' "$1" >&2; exit 1; }

# In update mode any failing exit (fail, or an unexpected command error under set -e) says where the
# safety dump is and how to go back.
update_exit_note() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$UPD_DIR" ]; then
    {
      echo
      echo "   The update did not finish. The safety dump from before it is in: $UPD_DIR"
      [ -z "$UPD_PREV" ] || echo "   To return to the previous version: git checkout $UPD_PREV && bash setup-server.sh"
    } >&2
  fi
}
trap update_exit_note EXIT

# Asks a yes/no question (default yes). --yes answers yes; no terminal answers no.
confirm() {
  [ "$YES" -eq 1 ] && return 0
  if [ ! -t 0 ]; then
    warn "no terminal to ask: $1 (re-run with --yes to agree)"
    return 1
  fi
  local answer
  read -r -p "   $1 [Y/n] " answer
  case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# Runs a command as root: directly when already root, else through sudo.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else fail "root rights are needed for: $* (install sudo or run this script as root)"
  fi
}

tcp_open() { # host port
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null
  else
    bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null
  fi
}

http_ok() { # url host port (host and port only for the fallback without curl / wget)
  if command -v curl >/dev/null 2>&1; then curl -fsS -m 3 -o /dev/null "$1" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then wget -q -T 3 -O /dev/null "$1" 2>/dev/null
  else tcp_open "$2" "$3"
  fi
}

# Is something listening on this TCP port (any address)? Uses ss; without it only loopback is probed.
port_busy() { # port
  if command -v ss >/dev/null 2>&1; then
    [ -n "$(ss -H -ltn "sport = :$1" 2>/dev/null || true)" ]
  else
    tcp_open 127.0.0.1 "$1"
  fi
}

# Host port our own container already publishes (empty when it is not running).
own_port() { # service container-port
  compose port "$1" "$2" 2>/dev/null | head -n 1 | sed 's/.*://' || true
}

# A bind of 127.0.0.1 / localhost keeps the port on this PC; anything else is reachable from the LAN.
is_local_bind() { [ "$1" = 127.0.0.1 ] || [ "$1" = localhost ]; }

# Address to probe on this PC for a bind: the bind itself, or loopback when it is 0.0.0.0 / localhost.
probe_addr() {
  case "$1" in 0.0.0.0|localhost) printf '127.0.0.1\n' ;; *) printf '%s\n' "$1" ;; esac
}

# ARM CPU without lrcpc (Load-Acquire RCpc, ARMv8.2-A+): current ClickHouse builds die there with
# "Illegal instruction" (Raspberry Pi 4 = Cortex-A72, ARMv8.0). No Features line = unknown = not old.
old_arm() {
  [ "$(uname -m)" = aarch64 ] && [ -r /proc/cpuinfo ] || return 1
  local feat
  feat="$(grep -m1 '^Features' /proc/cpuinfo || true)"
  [ -n "$feat" ] && ! printf '%s\n' "$feat" | grep -qw lrcpc
}

get_lan_ip() {
  if [ -n "$LAN_IP" ]; then printf '%s\n' "$LAN_IP"; return; fi
  command -v ip >/dev/null 2>&1 || return 0
  # Source address of the default route: the interface the PC reaches the LAN through.
  ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1 || true
}

# ---------------------------------------------------------------- 1. Docker
step 'Docker'
D=()   # the docker command: (docker) or (sudo docker)

# Sets D when the daemon answers; returns 1 otherwise and sets DOCKER_PROBLEM.
detect_docker() {
  D=(); DOCKER_PROBLEM=''
  command -v docker >/dev/null 2>&1 || { DOCKER_PROBLEM='missing'; return 1; }
  local err
  if err="$(docker info --format '{{.ServerVersion}}' 2>&1 >/dev/null)"; then D=(docker)
  elif printf '%s' "$err" | grep -qi 'permission denied'; then
    # Not in the docker group (yet): use sudo for this run.
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
      D=(sudo docker)
    else DOCKER_PROBLEM='permission'; return 1
    fi
  else DOCKER_PROBLEM='daemon'; return 1
  fi
  "${D[@]}" compose version >/dev/null 2>&1 || { DOCKER_PROBLEM='compose'; return 1; }
}

if ! detect_docker; then
  case "$DOCKER_PROBLEM" in
    daemon) fail "Docker is installed but does not answer. Start it: sudo systemctl start docker, then run this script again." ;;
    permission) fail "No permission to use Docker and sudo is not available. Add yourself to the docker group (sudo usermod -aG docker \$USER), log in again and re-run." ;;
  esac
  # missing docker or compose plugin
  [ -r /etc/os-release ] || fail 'Docker (with the compose plugin) is missing and the distribution is unknown. Install Docker Engine: https://docs.docker.com/engine/install/'
  # shellcheck disable=SC1091
  distro="$(. /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}")"
  case " $distro " in
    *" ubuntu "*|*" debian "*) ;;
    *) fail "Docker (with the compose plugin) is missing. Install Docker Engine and the compose plugin for your distribution (https://docs.docker.com/engine/install/), then run this script again." ;;
  esac
  confirm 'Docker Engine with the compose plugin is missing. Install it from download.docker.com now (uses sudo; also enables the docker service at boot and adds your user to the docker group)?' || fail 'Docker is required.'
  as_root bash "$ROOT/linux-server-tools/install-docker.sh" "$(id -un)" || fail 'Docker installation failed, see the output above.'
  detect_docker || fail 'Docker was installed but does not answer. Run: sudo docker info'
fi
ok "Docker Engine $("${D[@]}" info --format '{{.ServerVersion}}'), compose $("${D[@]}" compose version --short)"
if [ "${D[0]}" = sudo ]; then
  warn 'your user is not in the docker group: this run uses sudo for docker.'
  warn '  To use docker without sudo: sudo usermod -aG docker $USER  and log in again.'
fi
compose() { "${D[@]}" compose "$@"; }

# ---------------------------------------------------------------- update (--update)
# Runs a helper script as the docker user: tool [VAR=value ...] bash <script> [args]
tool() { if [ "${D[0]}" = sudo ]; then sudo env "$@"; else env "$@"; fi; }

# "<table><TAB><rows>" for every otel.* table.
row_counts() {
  local tables t n
  tables="$(echo 'SHOW TABLES FROM otel' | tool bash "$ROOT/linux-server-tools/ch.sh")" || return 1
  for t in $tables; do
    n="$(echo "SELECT count() FROM otel.$t" | tool bash "$ROOT/linux-server-tools/ch.sh")" || return 1
    printf '%s\t%s\n' "$t" "$n"
  done
}

# bash reads a script while it runs, and git pull rewrites this file: everything after the pull is in
# this one function, which ends with exec (nothing of the old file is read afterwards).
run_update() {
  local dir prev now up repass=() a
  step 'Update: checks'
  [ -f .env ] || fail '.env not found: this folder is not a configured server yet. Run: bash setup-server.sh'
  echo 'SELECT 1' | tool bash "$ROOT/linux-server-tools/ch.sh" >/dev/null 2>&1 \
    || fail 'ClickHouse does not answer, so no safety dump is possible. Start the stack (docker compose up -d), wait until it is healthy and run --update again.'
  ok 'ClickHouse answers'
  prev=''; up=''
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      git status --short --untracked-files=no >&2
      fail 'The git working tree has local changes (listed above): the pull could fail or merge them. Commit, stash or revert them (git stash), then run --update again.'
    fi
    ok 'git working tree is clean (.env and backup/ are git-ignored)'
    prev="$(git rev-parse --short HEAD)"
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || up=''
  else
    warn 'this folder is not a git repository'
  fi

  step 'Update: safety dump'
  dir="backup/pre-update-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir" || fail "Cannot create $dir. If backup/ belongs to root (made by an earlier sudo run): sudo chown -R $(id -un) backup  and run --update again."
  # The dump is Native format (uncompressed), so compare the free space with the uncompressed size of
  # the active parts. Stop when it is less than that; warn below 1.5 times that (the data may grow).
  local need avail
  need="$(echo "SELECT sum(data_uncompressed_bytes) FROM system.parts WHERE database = 'otel' AND active" | tool bash "$ROOT/linux-server-tools/ch.sh" 2>/dev/null | tr -d '[:space:]')" || need=''
  avail="$(df -Pk "$dir" 2>/dev/null | awk 'NR == 2 { print $4 }')" || avail=''
  if [[ "$need" =~ ^[0-9]+$ ]] && [[ "$avail" =~ ^[0-9]+$ ]]; then
    avail=$((avail * 1024))
    if [ "$avail" -lt "$need" ]; then
      rmdir "$dir" 2>/dev/null || true
      fail "Not enough free disk space for the safety dump: the data is about $((need / 1048576)) MB uncompressed (the dump is that large), $((avail / 1048576)) MB are free where backup/ is. Free some space (or delete old backup/pre-update-* folders) and run --update again. Nothing was changed."
    elif [ "$avail" -lt $((need + need / 2)) ]; then
      warn "free disk space is tight: about $((avail / 1048576)) MB free for a dump of about $((need / 1048576)) MB (safety margin: 1.5 times)."
    else
      ok "free disk space: $((avail / 1048576)) MB for a dump of about $((need / 1048576)) MB"
    fi
  else
    warn 'could not compare free disk space with the data size: continuing without that check.'
  fi
  UPD_DIR="$dir"
  tool BACKUP_DIR="$dir" bash "$ROOT/linux-server-tools/backup.sh" dump || fail 'The safety dump failed (see above). Nothing was changed.'
  row_counts > "$dir/rowcounts.tsv" || fail 'Could not count the rows. Nothing was changed.'
  ok "dump and row counts saved in $dir (earlier dumps are kept)"
  [ "${D[0]}" != sudo ] || ok "docker runs through sudo, so the dump files in $dir belong to root (read or delete them with sudo)"

  step 'Update: code'
  if [ -n "$up" ]; then
    git pull --ff-only || fail 'git pull --ff-only failed (a diverged branch or no network). The stack was not touched.'
    now="$(git rev-parse --short HEAD)"
    UPD_PREV="$prev"
    if [ "$now" = "$prev" ]; then ok "already up to date ($now)"
    else ok "updated $prev -> $now. Rollback: git checkout $prev && bash setup-server.sh"
    fi
  elif [ -n "$prev" ]; then
    warn 'the current branch has no upstream: nothing is pulled, continuing with the files as they are.'
  else
    warn 'no git repository: continuing with the files as they are.'
  fi

  for a in "${PASS[@]+"${PASS[@]}"}"; do [ "$a" = --update ] || repass+=("$a"); done
  step 'Update: running setup-server.sh from the updated file'
  CCT_UPDATE=1 CCT_UPDATE_DIR="$dir" CCT_UPDATE_PREV="$prev" exec bash "$ROOT/setup-server.sh" "${repass[@]+"${repass[@]}"}"
  fail 'could not start setup-server.sh again'
}

# Last step of the re-run: no table has fewer rows than before the update.
finish_update() {
  local post t n now bad=0 restore="BACKUP_DIR=$UPDATE_DIR"
  # sudo resets the environment: the variable must go through env, after sudo
  [ "${D[0]}" != sudo ] || restore="sudo env BACKUP_DIR=$UPDATE_DIR"
  step 'Update: data check'
  if [ ! -s "$UPDATE_DIR/rowcounts.tsv" ]; then
    warn "no row counts in $UPDATE_DIR (empty stack before the update?): nothing to compare"
  else
    post="$(row_counts)" || fail 'could not count the rows after the update.'
    while IFS=$'\t' read -r t n; do
      [ -n "$t" ] || continue
      now="$(printf '%s\n' "$post" | awk -F'\t' -v t="$t" '$1 == t { print $2 }')"
      if ! [[ "$n" =~ ^[0-9]+$ ]]; then bad=1; printf '   FAIL %s: the row count before the update is not a number (%s), cannot compare\n' "$t" "$n" >&2
      elif [ -z "$now" ]; then bad=1; printf '   LOST %s: %s rows before, table missing now\n' "$t" "$n" >&2
      elif ! [[ "$now" =~ ^[0-9]+$ ]]; then bad=1; printf '   FAIL %s: the row count now is not a number (%s), cannot compare\n' "$t" "$now" >&2
      elif [ "$now" -lt "$n" ]; then bad=1; printf '   LOST %s: %s rows before, %s now\n' "$t" "$n" "$now" >&2
      else printf '   OK   %s: %s rows before, %s now\n' "$t" "$n" "$now"
      fi
    done < "$UPDATE_DIR/rowcounts.tsv"
    if [ "$bad" -eq 1 ]; then
      {
        echo
        echo '   ######## FAIL: DATA MAY HAVE BEEN LOST DURING THE UPDATE ########'
        echo "   The dump from before the update is in: $UPDATE_DIR"
        echo '   Restore appends rows: restore only into tables that are empty now. Check the row counts first;'
        echo "   a table that is only partly filled would get duplicates. Restore: $restore bash linux-server-tools/backup.sh restore [table]"
        [ -z "$UPDATE_PREV" ] || echo "   To return to the previous version: git checkout $UPDATE_PREV && bash setup-server.sh"
      } >&2
      UPD_DIR=''   # this banner already says it
      exit 1
    fi
    ok "update finished, no data lost (dump kept in $UPDATE_DIR; delete it when you no longer need it)"
  fi
  echo '   Restart your Claude Code sessions on the clients (sessions started before the update may not reconnect to the restarted collector).'
  [ -z "$UPDATE_PREV" ] || echo "   Rollback if something is wrong: git checkout $UPDATE_PREV && bash setup-server.sh"
}

if [ "$UPDATE" -eq 1 ]; then run_update; fi

# ---------------------------------------------------------------- 2. .env
step '.env'
if [ -f .env ]; then
  ok '.env exists, kept as is'
else
  secret() { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
  ( umask 077; printf 'CLICKHOUSE_PASSWORD=%s\nGRAFANA_ADMIN_PASSWORD=%s\n' "$(secret)" "$(secret)" > .env )
  ok '.env created with random passwords (Grafana login: admin / GRAFANA_ADMIN_PASSWORD from .env)'
fi

# OTLP_BIND decides where Docker publishes 4317. On Linux Docker's own iptables rules bypass ufw/firewalld,
# so the firewall cannot hide a port: the bind address is the real switch. GRAFANA_BIND does the same for
# 3000; 4318 is always local. Only these two lines of .env are read or written.
get_env() { # KEY -> value (CR stripped); empty when the key is missing
  grep "^$1=" .env | tail -n 1 | cut -d= -f2- | tr -d '\r' || true
}
set_env() { # KEY value
  # A .env with CRLF endings (edited on Windows) keeps them: no mixed line endings.
  local cr=''
  if grep -q $'\r' .env; then cr=$'\r'; fi
  if grep -q "^$1=" .env; then
    sed -i "s/^$1=.*/$1=$2$cr/" .env
  else
    # keep the last line of .env terminated before appending
    if [ -s .env ] && [ -n "$(tail -c 1 .env)" ]; then printf '%s\n' "$cr" >> .env; fi
    printf '%s=%s%s\n' "$1" "$2" "$cr" >> .env
  fi
}

# Decides one key: a flag sets it; no flag keeps a present value; a missing value gets $3 (default).
# Sets the global BIND_RESULT.
resolve_bind() { # KEY what-it-publishes default
  local cur want
  cur="$(get_env "$1")"
  case "$MODE" in lan) want=0.0.0.0 ;; local) want=127.0.0.1 ;; *) want="$cur" ;; esac
  [ -n "$want" ] || want="$3"
  if [ "$want" != "$cur" ]; then
    set_env "$1" "$want"
    ok "$1=$want written to .env ($2)"
  else
    ok "$1=$cur kept ($2)"
  fi
  BIND_RESULT="$want"
}
otlp_was="$(get_env OTLP_BIND)"
grafana_was="$(get_env GRAFANA_BIND)"
resolve_bind OTLP_BIND 'port 4317' 0.0.0.0
otlp_bind="$BIND_RESULT"
# A missing GRAFANA_BIND follows OTLP_BIND (as just resolved), so an earlier choice of OTLP_BIND=127.0.0.1
# never turns Grafana into a LAN service on its own.
resolve_bind GRAFANA_BIND 'Grafana' "$otlp_bind"
grafana_bind="$BIND_RESULT"
if [ -z "$MODE" ] && [ -n "$otlp_was" ] && [ -z "$grafana_was" ] && ! is_local_bind "$grafana_bind"; then
  warn "GRAFANA_BIND was missing and OTLP_BIND=$otlp_bind: Grafana is now published on $grafana_bind, reachable from the LAN (it was local-only before). To keep it on this PC: re-run with --local-only."
fi
lan_on=0
if ! is_local_bind "$otlp_bind" || ! is_local_bind "$grafana_bind"; then lan_on=1; fi

# Grafana host port: --grafana-port, else the value kept in .env, else 3000. The container port stays 3000.
gp_cur="$(get_env GRAFANA_PORT)"
if [ -n "$gp_cur" ] && { ! [[ "$gp_cur" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$gp_cur" -gt 65535 ]; }; then
  fail "GRAFANA_PORT=$gp_cur in .env is not a port number (1-65535). Fix it or pass --grafana-port <n>."
fi
grafana_port="${GRAFANA_PORT_FLAG:-${gp_cur:-3000}}"
if [ "$(own_port grafana 3000)" != "$grafana_port" ] && port_busy "$grafana_port"; then
  fail "TCP port $grafana_port is already in use by another program, so Grafana cannot publish it. Pick a free port, for example: bash setup-server.sh --grafana-port 3001"
fi
if [ "$grafana_port" != "$gp_cur" ]; then
  set_env GRAFANA_PORT "$grafana_port"
  ok "GRAFANA_PORT=$grafana_port written to .env"
else
  ok "GRAFANA_PORT=$grafana_port kept"
fi
# The OTLP ports are fixed in this stack: only report a conflict (docker compose up would fail on it).
for p in 4317 4318; do
  if [ "$(own_port otel-collector "$p")" != "$p" ] && port_busy "$p"; then
    warn "TCP port $p is already in use by another program: the collector cannot start until it is freed."
  fi
done

# ClickHouse image tag: --clickhouse-version wins; a missing key on an ARM CPU without lrcpc gets the
# old tag; anything else keeps .env (no key = the compose default).
ch_cur="$(get_env CLICKHOUSE_VERSION)"
ch_want="$CH_VERSION_FLAG"
ch_auto=0
if [ -z "$ch_want" ] && [ -z "$ch_cur" ] && old_arm; then ch_want="$OLD_CH_TAG"; ch_auto=1; fi
if [ -n "$ch_want" ] && [ "$ch_want" != "$ch_cur" ]; then
  set_env CLICKHOUSE_VERSION "$ch_want"
  if [ "$ch_auto" -eq 1 ]; then ok "ARM CPU without lrcpc detected (e.g. Raspberry Pi 4): CLICKHOUSE_VERSION=$ch_want written to .env"
  else ok "CLICKHOUSE_VERSION=$ch_want written to .env"
  fi
elif [ -n "$ch_cur" ]; then ok "CLICKHOUSE_VERSION=$ch_cur kept"
else ok 'ClickHouse image: default tag from docker-compose.yml'
fi
ch_ver="${ch_want:-$ch_cur}"
ch_major="${ch_ver%%.*}"
if [[ "$ch_major" =~ ^[0-9]+$ ]] && [ "$ch_major" -lt 24 ]; then
  warn "ClickHouse $ch_ver is out of support (no security fixes): run it on a trusted LAN only. A data volume written by a newer ClickHouse will not start with it."
fi

# ---------------------------------------------------------------- 3. stack
step 'Stack'
if [ "$lan_on" -eq 1 ]; then
  echo '   Note: LAN access is the default: the ports below are published for every PC that can reach this host.'
  is_local_bind "$otlp_bind" || echo "     OTLP 4317   on $otlp_bind"
  is_local_bind "$grafana_bind" || echo "     Grafana $grafana_port on $grafana_bind"
  echo '     Plain HTTP, OTLP without authentication. To keep them on this PC only: re-run with --local-only.'
fi
compose up -d || fail 'docker compose up failed, see the output above.'
state=''
for _ in $(seq 1 90); do
  state="$(compose ps -a views-init --format '{{.State}} {{.ExitCode}}' | head -n 1)" || state=''
  case "$state" in exited*) break ;; esac
  sleep 2
done
if [ "$state" = 'exited 0' ]; then ok 'cc.* views are ready'
else compose logs views-init || true; fail "views-init did not finish cleanly ($state)"
fi

# ---------------------------------------------------------------- 4. checks
step 'Checks'
grafana_ok=0
g_host="$(probe_addr "$grafana_bind")"
o_host="$(probe_addr "$otlp_bind")"
for _ in $(seq 1 45); do
  if http_ok "http://${g_host}:${grafana_port}/api/health" "$g_host" "$grafana_port"; then grafana_ok=1; break; fi
  sleep 2
done
if [ "$grafana_ok" -eq 1 ]; then ok "Grafana: http://${g_host}:${grafana_port}"
else warn 'Grafana does not answer yet; check: docker compose logs grafana'
fi
if tcp_open "$o_host" 4317; then ok "OTLP: ${o_host}:4317"
else warn "${o_host}:4317 is closed; check: docker compose logs otel-collector"
fi

# Containers use restart: unless-stopped, so they return when the docker service starts at boot.
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  if systemctl is-enabled docker >/dev/null 2>&1; then ok 'docker service starts at boot'
  elif confirm 'The docker service does not start at boot, so the stack would stay down after a restart. Enable it (sudo systemctl enable docker)?'; then
    as_root systemctl enable docker >/dev/null 2>&1 && ok 'docker service enabled at boot' || warn 'could not enable the docker service: sudo systemctl enable docker'
  else
    warn 'docker service is not enabled at boot; run: sudo systemctl enable docker'
  fi
else
  warn 'systemd not found: make sure the docker service starts at boot yourself.'
fi

# ---------------------------------------------------------------- 5. LAN
ip_addr=''
if [ "$lan_on" -eq 1 ]; then
  step 'LAN access'
  # Ports published on all interfaces: the firewall must let them in.
  lan_ports=()
  is_local_bind "$otlp_bind" || lan_ports+=(4317)
  is_local_bind "$grafana_bind" || lan_ports+=("$grafana_port")
  ip_addr="$(get_lan_ip)"
  if [ -n "$ip_addr" ]; then ok "LAN address: $ip_addr"
  else warn 'Could not find the LAN address. Re-run with --lan-ip <address> (the firewall rules below do not need it).'
  fi

  fw=''
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then fw=firewalld
  elif command -v ufw >/dev/null 2>&1; then fw=ufw
  fi
  ports_txt="${lan_ports[*]}"
  ports_txt="${ports_txt// /, }"
  case "$fw" in
    firewalld)
      if confirm "Add firewalld rules for TCP $ports_txt if missing (uses sudo)? This only adds rules; it does not limit who can connect (Docker bypasses the firewall, --local-only does)."; then
        for port in "${lan_ports[@]}"; do
          # runtime rule = works now; permanent rule = survives a reload or reboot
          rt=0; pm=0
          as_root firewall-cmd --query-port="$port/tcp" >/dev/null 2>&1 && rt=1
          as_root firewall-cmd --permanent --query-port="$port/tcp" >/dev/null 2>&1 && pm=1
          if [ "$rt" -eq 1 ] && [ "$pm" -eq 1 ]; then ok "firewalld: $port/tcp already open"
          else
            fw_ok=1
            if [ "$rt" -eq 0 ]; then as_root firewall-cmd --add-port="$port/tcp" >/dev/null || fw_ok=0; fi
            if [ "$pm" -eq 0 ]; then as_root firewall-cmd --permanent --add-port="$port/tcp" >/dev/null || fw_ok=0; fi
            if [ "$fw_ok" -eq 1 ]; then ok "firewalld: $port/tcp opened (now and permanently)"
            else warn "firewalld: could not open $port/tcp: sudo firewall-cmd --add-port=$port/tcp && sudo firewall-cmd --permanent --add-port=$port/tcp"
            fi
          fi
        done
      else
        for port in "${lan_ports[@]}"; do warn "firewalld rule not added: sudo firewall-cmd --add-port=$port/tcp && sudo firewall-cmd --permanent --add-port=$port/tcp"; done
      fi ;;
    ufw)
      if confirm "Add ufw rules for TCP $ports_txt if ufw is active (uses sudo)? This only adds rules; it does not limit who can connect (Docker bypasses the firewall, --local-only does)."; then
        ufw_status="$(as_root ufw status 2>/dev/null || true)"
        if ! printf '%s' "$ufw_status" | grep -q '^Status: active'; then ok 'ufw is not active: no firewall rule needed'
        else
          for port in "${lan_ports[@]}"; do
            if printf '%s' "$ufw_status" | grep -Eq "^$port/tcp +ALLOW"; then ok "ufw: $port/tcp already allowed"
            else as_root ufw allow "$port/tcp" >/dev/null && ok "ufw: $port/tcp allowed" || warn "ufw: could not allow $port/tcp"
            fi
          done
        fi
      else
        for port in "${lan_ports[@]}"; do warn "ufw rule not added: sudo ufw allow $port/tcp"; done
      fi ;;
    *) ok 'no ufw or firewalld found: no firewall rule added (check your firewall if clients cannot connect)' ;;
  esac
  warn "Docker publishes $ports_txt itself and bypasses ufw/firewalld rules: any PC that reaches this host can connect. Plain HTTP, OTLP without authentication: use a trusted network only."
  # The address other PCs use: this PC's LAN address for 0.0.0.0, or the hand-set bind itself.
  o_reach="$otlp_bind"; [ "$otlp_bind" != 0.0.0.0 ] || o_reach="$ip_addr"
  g_reach="$grafana_bind"; [ "$grafana_bind" != 0.0.0.0 ] || g_reach="$ip_addr"
  if ! is_local_bind "$otlp_bind" && [ -n "$o_reach" ]; then
    if tcp_open "$o_reach" 4317; then ok "${o_reach}:4317 is reachable"
    else warn "${o_reach}:4317 is not reachable yet"
    fi
  fi
  if ! is_local_bind "$grafana_bind" && [ -n "$g_reach" ]; then
    if tcp_open "$g_reach" "$grafana_port"; then ok "${g_reach}:${grafana_port} is reachable"
    else warn "${g_reach}:${grafana_port} is not reachable yet"
    fi
  fi
fi

# ---------------------------------------------------------------- summary
step 'Done'
g_show="$g_host"; [ "$g_host" != 127.0.0.1 ] || g_show=localhost
echo "   Grafana on this PC:  http://${g_show}:${grafana_port}   (admin / GRAFANA_ADMIN_PASSWORD from the .env file)"
echo '   This PC as a client:'
o_local="$o_host"; [ "$o_host" != 127.0.0.1 ] || o_local=localhost
echo "     bash client/setup-client.sh --server-ip ${o_local} --project <project folder>"
if ! is_local_bind "$grafana_bind"; then
  echo "   Grafana from other PCs:  http://${g_reach:-<server address>}:${grafana_port}   (same admin login; GRAFANA_BIND=${grafana_bind})"
else
  echo "   Grafana from other PCs: not reachable (GRAFANA_BIND=${grafana_bind}); re-run with --lan to open it."
fi
if ! is_local_bind "$otlp_bind"; then
  o_shown="${o_reach:-<server address>}"
  echo "   Other PCs as clients (OTLP_BIND=${otlp_bind}); copy the client script to the PC first:"
  echo "     Windows:  powershell -ExecutionPolicy Bypass -File .\\setup-client.ps1 -ServerIp ${o_shown} -Project <project folder>"
  echo "     Linux:    bash setup-client.sh --server-ip ${o_shown} --project <project folder>"
else
  echo "   Other PCs as clients: not reachable (OTLP_BIND=${otlp_bind}); re-run with --lan to open port 4317."
fi

if [ -n "$UPDATE_DIR" ]; then finish_update; fi
