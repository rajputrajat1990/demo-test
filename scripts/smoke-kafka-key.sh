#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ART_DIR="${ROOT_DIR}/artifacts"
SESS_DIR="${ART_DIR}/sessions"
LOG_DIR="${ART_DIR}/logs"
mkdir -p "$SESS_DIR" "$LOG_DIR"

if [[ -z "${TEST_SESSION_ID:-}" ]]; then TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM; export TEST_SESSION_ID; fi
export LOG_FILE="${LOG_DIR}/run-${TEST_SESSION_ID}.log"
. "${UTILS_DIR}/logging.sh"

CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"

# Prepare session output path early
SD="${SESS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SD"
OUT="${SD}/smoke_kafka_key.json"

# Defaults
ERROR_MSG=""
SUCCESS=false
HTTP=""
BODY_PREVIEW=""
TOPICS_URL=""
ENV_ID=""; CLUSTER_ID=""; HTTP_ENDPOINT=""

# Validate inputs
if [[ ! -f "$CONFIG_PATH" ]]; then
  ERROR_MSG="missing config at ${CONFIG_PATH}"
else
  ENV_ID=$(jq -r '.environment_id // empty' "$CONFIG_PATH" 2>/dev/null || true)
  CLUSTER_ID=$(jq -r '.cluster_id // empty' "$CONFIG_PATH" 2>/dev/null || true)
  HTTP_ENDPOINT=$(jq -r '.http_endpoint // empty' "$CONFIG_PATH" 2>/dev/null || true)
fi
if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then
  ERROR_MSG="${ERROR_MSG:+$ERROR_MSG; }missing cloud creds"
fi
if [[ -z "${SERVICE_ACCOUNT_ID:-}" ]]; then
  ERROR_MSG="${ERROR_MSG:+$ERROR_MSG; }missing SERVICE_ACCOUNT_ID"
fi

# 1) Create Kafka key via REST
if [[ -z "$ERROR_MSG" ]]; then
  if ! scripts/create-kafka-api-key-rest.sh; then
    log_error "smoke: rest keygen failed"
    ERROR_MSG="${ERROR_MSG:+$ERROR_MSG; }keygen failed"
  fi
fi

# 2) Grant DeveloperRead via REST (best-effort)
scripts/grant-kafka-read-rest.sh || true

# 3) List topics using the generated key (retry for propagation)
if [[ -z "$ERROR_MSG" ]]; then
  SECRETS_PATH="${KAFKA_SECRETS_PATH:-${ROOT_DIR}/configs/kafka-secrets.local.json}"
  if [[ -f "$SECRETS_PATH" ]]; then
    KAFKA_KEY=$(jq -r '.kafka_api_key // empty' "$SECRETS_PATH")
    KAFKA_SECRET=$(jq -r '.kafka_api_secret // empty' "$SECRETS_PATH")
    if [[ -n "$KAFKA_KEY" && -n "$KAFKA_SECRET" && -n "$HTTP_ENDPOINT" && -n "$CLUSTER_ID" ]]; then
      TOPICS_URL="${HTTP_ENDPOINT%/}/kafka/v3/clusters/${CLUSTER_ID}/topics?limit=5"
      TMP=$(mktemp)
      for i in {1..6}; do
        HTTP=$(curl -sS -u "$KAFKA_KEY:$KAFKA_SECRET" -H 'Accept: application/json' -o "$TMP" -w '%{http_code}' "$TOPICS_URL" || true)
        BODY_PREVIEW=$(head -c 1024 "$TMP" | sed -e 's/\r//g')
        if [[ "$HTTP" == "200" ]]; then SUCCESS=true; break; fi
        log_info "smoke: topics list not yet 200" attempt="$i" http_code="$HTTP"
        sleep 5
      done
      rm -f "$TMP"
    else
      ERROR_MSG="${ERROR_MSG:+$ERROR_MSG; }incomplete data to query topics"
    fi
  else
    ERROR_MSG="${ERROR_MSG:+$ERROR_MSG; }missing secrets file ${SECRETS_PATH}"
  fi
fi

# 4) Write concise artifact and exit 0
{
  echo '{'
  printf '  "test_session_id": %s,\n' "$(jq -Rs . <<<"$TEST_SESSION_ID")"
  printf '  "environment_id": %s,\n' "$(jq -Rs . <<<"$ENV_ID")"
  printf '  "cluster_id": %s,\n' "$(jq -Rs . <<<"$CLUSTER_ID")"
  printf '  "http_endpoint": %s,\n' "$(jq -Rs . <<<"$HTTP_ENDPOINT")"
  printf '  "topics_url": %s,\n' "$(jq -Rs . <<<"$TOPICS_URL")"
  printf '  "http_code": %s,\n' "${HTTP:-0}"
  printf '  "success": %s,\n' "$SUCCESS"
  printf '  "error": %s,\n' "$(jq -Rs . <<<"$ERROR_MSG")"
  printf '  "body_preview": %s\n' "$(jq -Rs . <<<"$BODY_PREVIEW")"
  echo '}'
} >"$OUT"

log_info "smoke completed" http_code="$HTTP" success="$SUCCESS" output="$OUT"
echo "Smoke artifact: $OUT" >&2
exit 0
