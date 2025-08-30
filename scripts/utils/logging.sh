#!/usr/bin/env bash
# JSONL logger. Requires TEST_SESSION_ID to be set by caller.
# Usage: log_info "message" key=value ...
# Levels: INFO, WARN, ERROR, DEBUG

set -euo pipefail

_log_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# shellcheck disable=SC2120
log_json() {
  local level="${1:-INFO}"; shift || true
  local msg="${1:-}"; shift || true
  local ts shell_session_id host user kv
  ts=$(_log_now)
  shell_session_id="${TEST_SESSION_ID:-unknown}"
  host=$(hostname 2>/dev/null || echo "unknown")
  user=${USER:-unknown}

  kv=""
  while [[ $# -gt 0 ]]; do
    # Expect key=value pairs
    if [[ "$1" == *"="* ]]; then
      local k=${1%%=*}
      local v=${1#*=}
  # escape backslashes, then double quotes for JSON safety
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
      kv+="\n    \"$k\": \"$v\","
    fi
    shift
  done

  # trim trailing comma from kv if present
  kv=${kv%%,}

  local line
  line=$(cat <<JSON
{
  "timestamp": "${ts}",
  "level": "${level}",
  "test_session_id": "${shell_session_id}",
  "host": "${host}",
  "user": "${user}",
  "message": "${msg}"${kv:+,}${kv:+${kv}}
}
JSON
)

  echo -e "$line" | tee -a "${LOG_FILE:-/dev/stdout}" >/dev/null
}

log_info()  { log_json INFO  "$@"; }
log_warn()  { log_json WARN  "$@"; }
log_error() { log_json ERROR "$@"; }
log_debug() { [[ "${DEBUG:-}" == "1" ]] && log_json DEBUG "$@" || true; }
