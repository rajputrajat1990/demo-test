#!/usr/bin/env bash
set -euo pipefail

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
# Try modern first, then legacy paths as fallback
ENV_ENDPOINTS=(
  "${API_BASE}/org/v2/environments?page_size=1"
  "${API_BASE}/v2/environments?page_size=1"
  "${API_BASE}/iam/v2/environments?page_size=1"
)

if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then
  log_info "cloud check skipped (missing credentials)" session_script="confluent-check.sh"
  exit 0
fi

log_info "cloud check started" session_script="confluent-check.sh" api_base="$API_BASE"

TMP_BODY=$(mktemp)
TRIED_ENDPOINTS=()
USED_ENDPOINT=""
HTTP_CODE=0
SUCCESS=false
ENV_COUNT=null

for ep in "${ENV_ENDPOINTS[@]}"; do
  TRIED_ENDPOINTS+=("$ep")
  HTTP_CODE=$(curl -sS -u "${CONFLUENT_CLOUD_API_KEY}:${CONFLUENT_CLOUD_API_SECRET}" \
    -H "Accept: application/json" \
    -o "$TMP_BODY" -w "%{http_code}" \
    "$ep" || true)
  USED_ENDPOINT="$ep"
  # If we hit a valid route, we'll get 200/401/403; break on 200 success or 401/403 auth issues
  if [[ "$HTTP_CODE" == "200" ]]; then
    SUCCESS=true
    if command -v jq >/dev/null 2>&1; then
      ENV_COUNT=$(jq -r '.data | length' "$TMP_BODY" 2>/dev/null || echo null)
    fi
    break
  elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
    # Auth error means the route exists; no need to try legacy fallbacks
    break
  else
    # 404 or others — try next fallback
    continue
  fi
done

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT_FILE="${SESSION_DIR}/confluent_api_check.json"
BODY_PREVIEW=""
if command -v head >/dev/null 2>&1; then
  # Limit preview to 2KB to keep artifacts small
  BODY_PREVIEW=$(head -c 2048 "$TMP_BODY" | sed 's/\r//g' || true)
fi
{
  echo "{";
  echo "  \"test_session_id\": \"${TEST_SESSION_ID}\",";
  echo "  \"api_base\": \"${API_BASE}\",";
  echo "  \"endpoint\": \"${USED_ENDPOINT}\",";
  echo "  \"http_code\": ${HTTP_CODE:-0},";
  echo "  \"success\": ${SUCCESS},";
  echo "  \"environment_count\": ${ENV_COUNT},";
  echo "  \"tried_endpoints\": [";
  for i in "${!TRIED_ENDPOINTS[@]}"; do
    sep=","; [[ "$i" == "$((${#TRIED_ENDPOINTS[@]}-1))" ]] && sep="";
    printf "    \"%s\"%s\n" "${TRIED_ENDPOINTS[$i]}" "$sep";
  done
  echo "  ],";
  # Include a small preview of the response body for diagnostics (no secrets are ever echoed)
  printf "  \"body_preview\": %s,\n" "$(printf '%s' "$BODY_PREVIEW" | jq -Rs . 2>/dev/null || echo 'null')";
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"";
  echo "}";
} > "$OUT_FILE"

log_info "cloud check finished" success="$SUCCESS" http_code="$HTTP_CODE" endpoint="$USED_ENDPOINT" output_file="$OUT_FILE"

rm -f "$TMP_BODY"

if [[ "$SUCCESS" != true ]]; then
  exit 1
fi