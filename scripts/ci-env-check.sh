#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
LOGS_DIR="${ARTIFACTS_DIR}/logs"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"

mkdir -p "${LOGS_DIR}" "${SESSIONS_DIR}"

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

log_info "secrets check started" session_script="ci-env-check.sh"

has_api_key=$([[ -n "${CONFLUENT_CLOUD_API_KEY:-}" ]] && echo true || echo false)
has_api_secret=$([[ -n "${CONFLUENT_CLOUD_API_SECRET:-}" ]] && echo true || echo false)

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT_FILE="${SESSION_DIR}/secrets_check.json"
{
  echo "{";
  echo "  \"test_session_id\": \"${TEST_SESSION_ID}\",";
  echo "  \"confluent\": {\"api_key_present\": ${has_api_key}, \"api_secret_present\": ${has_api_secret}},";
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"";
  echo "}";
} > "$OUT_FILE"

log_info "secrets check complete" api_key_present="$has_api_key" api_secret_present="$has_api_secret" output_file="$OUT_FILE"

if [[ "$has_api_key" != true || "$has_api_secret" != true ]]; then
  exit 1
fi