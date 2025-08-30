#!/usr/bin/env bash
set -euo pipefail

# Sync configs/environment_details.json with live Confluent Cloud metadata.
# - Uses CONFLUENT_CLOUD_API_KEY/CONFLUENT_CLOUD_API_SECRET for auth.
# - Fills environment_id (if missing), cluster_id (if missing), and always refreshes:
#   kafka_bootstrap_endpoint, http_endpoint, region, cloud, availability.
# - Writes an artifact summary under artifacts/sessions/<TEST_SESSION_ID>/config_sync.json

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
LOGS_DIR="${ARTIFACTS_DIR}/logs"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"

mkdir -p "${LOGS_DIR}" "${SESSIONS_DIR}"

# Session
if [[ -z "${TEST_SESSION_ID:-}" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    TEST_SESSION_ID=$(uuidgen | tr 'A-Z' 'a-z')
  else
    TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM
  fi
  export TEST_SESSION_ID
fi
export LOG_FILE="${LOGS_DIR}/run-${TEST_SESSION_ID}.log"

. "${UTILS_DIR}/logging.sh"

API_BASE="${CONFLUENT_API_BASE:-https://api.confluent.cloud}"
CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  log_error "config file not found" script=sync-config.sh config_path="$CONFIG_PATH"
  exit 1
fi

if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then
  log_warn "sync skipped (missing credentials)" script=sync-config.sh
  echo "Credentials missing; set CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET" >&2
  exit 0
fi

log_info "sync started" script=sync-config.sh api_base="$API_BASE" config="$CONFIG_PATH"

read_json() { jq -r "$1 // empty" "$CONFIG_PATH" 2>/dev/null || true; }
write_json() {
  local jq_expr="$1"; shift || true
  local tmp
  tmp=$(mktemp)
  if ! jq "$jq_expr" "$CONFIG_PATH" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$CONFIG_PATH"
}

ENV_ID=$(read_json '.environment_id')
CLUSTER_ID=$(read_json '.cluster_id')

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT_FILE="${SESSION_DIR}/config_sync.json"

json_escape() { jq -Rs . <<<"${1:-}"; }

# Discover environment if missing
ENV_DISCOVERY_ENDPOINT="${API_BASE}/org/v2/environments?page_size=1"
ENV_HTTP=""
if [[ -z "$ENV_ID" ]]; then
  BODY=$(mktemp)
  ENV_HTTP=$(curl -sS -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
    -H "Accept: application/json" -o "$BODY" -w "%{http_code}" \
    "$ENV_DISCOVERY_ENDPOINT" || true)
  if [[ "$ENV_HTTP" == "200" ]]; then
    ENV_ID=$(jq -r '.data[0].id // empty' "$BODY" 2>/dev/null || true)
    if [[ -n "$ENV_ID" ]]; then
      write_json ".environment_id=\"$ENV_ID\"" || true
      log_info "environment discovered" env_id="$ENV_ID"
    fi
  fi
  rm -f "$BODY"
fi

# Discover cluster if missing
CL_DISCOVERY_ENDPOINT="${API_BASE}/cmk/v2/clusters?environment=${ENV_ID}"
CL_HTTP=""
if [[ -n "$ENV_ID" && -z "$CLUSTER_ID" ]]; then
  BODY=$(mktemp)
  CL_HTTP=$(curl -sS -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
    -H "Accept: application/json" -o "$BODY" -w "%{http_code}" \
    "$CL_DISCOVERY_ENDPOINT" || true)
  if [[ "$CL_HTTP" == "200" ]]; then
    CLUSTER_ID=$(jq -r '.data[0].id // empty' "$BODY" 2>/dev/null || true)
    if [[ -n "$CLUSTER_ID" ]]; then
      write_json ".cluster_id=\"$CLUSTER_ID\"" || true
      log_info "cluster discovered" cluster_id="$CLUSTER_ID"
    fi
  fi
  rm -f "$BODY"
fi

# Fetch cluster details and update endpoints/region/cloud/availability
DETAILS_HTTP=""
DETAILS_ENDPOINT="${API_BASE}/cmk/v2/clusters/${CLUSTER_ID}?environment=${ENV_ID}"
KAFKA_EP=""; HTTP_EP=""; REGION=""; CLOUD=""; AVAIL=""; NAME=""
if [[ -n "$ENV_ID" && -n "$CLUSTER_ID" ]]; then
  BODY=$(mktemp)
  DETAILS_HTTP=$(curl -sS -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
    -H "Accept: application/json" -o "$BODY" -w "%{http_code}" \
    "$DETAILS_ENDPOINT" || true)
  if [[ "$DETAILS_HTTP" == "200" ]]; then
    KAFKA_EP=$(jq -r '.spec.kafka_bootstrap_endpoint // empty' "$BODY" 2>/dev/null || true)
    HTTP_EP=$(jq -r '.spec.http_endpoint // empty' "$BODY" 2>/dev/null || true)
    REGION=$(jq -r '.spec.region // empty' "$BODY" 2>/dev/null || true)
    CLOUD=$(jq -r '.spec.cloud // empty' "$BODY" 2>/dev/null || true)
    AVAIL=$(jq -r '.spec.availability // empty' "$BODY" 2>/dev/null || true)
    NAME=$(jq -r '.spec.display_name // empty' "$BODY" 2>/dev/null || true)
    # Persist fields when present
    [[ -n "$KAFKA_EP" ]] && write_json ".kafka_bootstrap_endpoint=\"$KAFKA_EP\"" || true
    [[ -n "$HTTP_EP"  ]] && write_json ".http_endpoint=\"$HTTP_EP\"" || true
    [[ -n "$REGION"   ]] && write_json ".region=\"$REGION\"" || true
    [[ -n "$CLOUD"    ]] && write_json ".cloud=\"$CLOUD\"" || true
    [[ -n "$AVAIL"    ]] && write_json ".availability=\"$AVAIL\"" || true
  fi
  rm -f "$BODY"
fi

# Write artifact summary
{
  echo "{";
  echo "  \"test_session_id\": \"${TEST_SESSION_ID}\",";
  echo "  \"config_path\": \"${CONFIG_PATH}\",";
  echo "  \"api_base\": \"${API_BASE}\",";
  echo "  \"env_lookup\": {\"endpoint\": $(json_escape "$ENV_DISCOVERY_ENDPOINT"), \"http_code\": ${ENV_HTTP:-0}},";
  echo "  \"cluster_list\": {\"endpoint\": $(json_escape "$CL_DISCOVERY_ENDPOINT"), \"http_code\": ${CL_HTTP:-0}},";
  echo "  \"cluster_details\": {\"endpoint\": $(json_escape "$DETAILS_ENDPOINT"), \"http_code\": ${DETAILS_HTTP:-0}},";
  echo "  \"final_config\": "; jq . "$CONFIG_PATH"; echo;
  echo "}";
} >"$OUT_FILE"

log_info "sync finished" script=sync-config.sh config="$CONFIG_PATH" env_id="${ENV_ID:-}" cluster_id="${CLUSTER_ID:-}" kafka_ep="${KAFKA_EP:-}" region="${REGION:-}"

echo "Sync complete. Updated: $CONFIG_PATH" >&2
