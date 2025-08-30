#!/usr/bin/env bash
set -euo pipefail

# Phase 4: Flink tests (scaffold)
# - Validates Flink input/output topic bindings exist via Kafka REST v3
# - Uses same Kafka credentials as source tests (cluster-scoped)
# - Emits artifact: artifacts/sessions/<TEST_SESSION_ID>/flink_topics_check.json

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

CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"
if [[ ! -f "$CONFIG_PATH" ]]; then
  log_error "flink test: config file not found" script=test-flink.sh config_path="$CONFIG_PATH"
  exit 1
fi

CLUSTER_ID=$(jq -r '.cluster_id // empty' "$CONFIG_PATH")
HTTP_ENDPOINT=$(jq -r '.http_endpoint // empty' "$CONFIG_PATH")

# Pull input/output topic names from config
FLINK_INPUT=$(jq -r '.topics_config[] | select(.name=="flink_input_topic") | .name' "$CONFIG_PATH" 2>/dev/null || true)
FLINK_OUTPUT=$(jq -r '.topics_config[] | select(.name=="flink_output_topic") | .name' "$CONFIG_PATH" 2>/dev/null || true)

# If the config uses explicit names for input/output, allow override via env
FLINK_INPUT=${FLINK_INPUT:-${FLINK_INPUT_TOPIC:-flink_input_topic}}
FLINK_OUTPUT=${FLINK_OUTPUT:-${FLINK_OUTPUT_TOPIC:-flink_output_topic}}

# Kafka credentials
KAFKA_KEY="${KAFKA_API_KEY:-${CONFLUENT_KAFKA_API_KEY:-}}"
KAFKA_SECRET="${KAFKA_API_SECRET:-${CONFLUENT_KAFKA_API_SECRET:-}}"
# Fallback to local secrets file if env vars are absent
if [[ -z "$KAFKA_KEY" || -z "$KAFKA_SECRET" ]]; then
  SECRETS_FILE="${KAFKA_SECRETS_PATH:-${ROOT_DIR}/configs/kafka-secrets.local.json}"
  if [[ -f "$SECRETS_FILE" ]]; then
    KAFKA_KEY=${KAFKA_KEY:-$(jq -r '.kafka_api_key // empty' "$SECRETS_FILE" 2>/dev/null || true)}
    KAFKA_SECRET=${KAFKA_SECRET:-$(jq -r '.kafka_api_secret // empty' "$SECRETS_FILE" 2>/dev/null || true)}
  fi
fi

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT_FILE="${SESSION_DIR}/flink_topics_check.json"

status="skipped"
reason=""
found_input=false
found_output=false

if [[ -z "$KAFKA_KEY" || -z "$KAFKA_SECRET" ]]; then
  reason="missing Kafka API credentials"
elif [[ -z "$HTTP_ENDPOINT" || -z "$CLUSTER_ID" ]]; then
  reason="missing http_endpoint or cluster_id in config"
else
  BODY=$(mktemp)
  URL="${HTTP_ENDPOINT%/}/kafka/v3/clusters/${CLUSTER_ID}/topics?limit=1000"
  HTTP=$(curl -sS -u "$KAFKA_KEY:$KAFKA_SECRET" -H "Accept: application/json" -o "$BODY" -w "%{http_code}" "$URL" || true)
  if [[ "$HTTP" == "200" ]]; then
    status="passed"
    mapfile -t REMOTE_TOPICS < <(jq -r '.data[] | (.topic_name // .name // empty)' "$BODY" 2>/dev/null | sort -u)
    if printf '%s\n' "${REMOTE_TOPICS[@]}" | grep -Fxq "$FLINK_INPUT"; then found_input=true; fi
    if printf '%s\n' "${REMOTE_TOPICS[@]}" | grep -Fxq "$FLINK_OUTPUT"; then found_output=true; fi
    # If either is missing, mark as failed logically but keep exit 0
    if [[ "$found_input" != true || "$found_output" != true ]]; then
      status="failed"
      reason="missing topic(s): input=$FLINK_INPUT present=$found_input, output=$FLINK_OUTPUT present=$found_output"
    fi
  else
    status="blocked"
    reason="HTTP $HTTP from Kafka REST at $URL"
  fi
  rm -f "$BODY"
fi

# Write artifact summary
{
  echo "{";
  echo "  \"test_session_id\": \"${TEST_SESSION_ID}\",";
  echo "  \"status\": \"${status}\",";
  if [[ -n "$reason" ]]; then echo "  \"reason\": $(jq -Rs . <<<\"$reason\"),"; fi
  echo "  \"cluster_id\": $(jq -Rs . <<<\"${CLUSTER_ID:-}\"),";
  echo "  \"http_endpoint\": $(jq -Rs . <<<\"${HTTP_ENDPOINT:-}\"),";
  echo "  \"flink_input_topic\": $(jq -Rs . <<<\"$FLINK_INPUT\"),";
  echo "  \"flink_output_topic\": $(jq -Rs . <<<\"$FLINK_OUTPUT\"),";
  echo "  \"found\": { \"input\": ${found_input}, \"output\": ${found_output} }";
  echo "}";
} >"$OUT_FILE"

log_info "flink topics check" status="$status" input_present="$found_input" output_present="$found_output" output_file="$OUT_FILE"

# Non-blocking
exit 0
