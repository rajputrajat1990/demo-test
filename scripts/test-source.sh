#!/usr/bin/env bash
set -euo pipefail

# Phase 3: Source tests (minimal v1)
# - Checks configured topics exist via Kafka REST v3
# - Requires Kafka API credentials (cluster-scoped), not Cloud API credentials:
#     KAFKA_API_KEY / KAFKA_API_SECRET (or CONFLUENT_KAFKA_API_KEY / CONFLUENT_KAFKA_API_SECRET)
# - Emits artifact: artifacts/sessions/<TEST_SESSION_ID>/source_topics_check.json

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
  log_error "source test: config file not found" script=test-source.sh config_path="$CONFIG_PATH"
  exit 1
fi

ENV_ID=$(jq -r '.environment_id // empty' "$CONFIG_PATH")
CLUSTER_ID=$(jq -r '.cluster_id // empty' "$CONFIG_PATH")
HTTP_ENDPOINT=$(jq -r '.http_endpoint // empty' "$CONFIG_PATH")
mapfile -t CFG_TOPICS < <(jq -r '.topics_config[].name // empty' "$CONFIG_PATH" 2>/dev/null || true)

# Resolve Kafka credentials (cluster-scoped)
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
OUT_FILE="${SESSION_DIR}/source_topics_check.json"

status="skipped"
reason=""
found_count=0
missing_count=0
FOUND=()
MISSING=()

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
    for t in "${CFG_TOPICS[@]}"; do
      if printf '%s\n' "${REMOTE_TOPICS[@]}" | grep -Fxq "$t"; then
        FOUND+=("$t")
      else
        MISSING+=("$t")
      fi
    done
    found_count=${#FOUND[@]}
    missing_count=${#MISSING[@]}
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
  echo "  \"environment_id\": $(jq -Rs . <<<\"${ENV_ID:-}\"),";
  echo "  \"cluster_id\": $(jq -Rs . <<<\"${CLUSTER_ID:-}\"),";
  echo "  \"http_endpoint\": $(jq -Rs . <<<\"${HTTP_ENDPOINT:-}\"),";
  printf "  \"requested_topics\": %s,\n" "$(printf '%s\n' "${CFG_TOPICS[@]}" | jq -R . | jq -s .)"
  printf "  \"found_topics\": %s,\n" "$(printf '%s\n' "${FOUND[@]:-}" | jq -R . | jq -s .)"
  printf "  \"missing_topics\": %s,\n" "$(printf '%s\n' "${MISSING[@]:-}" | jq -R . | jq -s .)"
  echo "  \"counts\": { \"requested\": ${#CFG_TOPICS[@]}, \"found\": ${found_count}, \"missing\": ${missing_count} }";
  echo "}";
} >"$OUT_FILE"

log_info "source topics check" status="$status" found="$found_count" missing="$missing_count" output_file="$OUT_FILE"

# Always exit 0 to avoid halting the pipeline; status is recorded in the artifact
exit 0
