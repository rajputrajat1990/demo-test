#!/usr/bin/env bash
set -euo pipefail

# Create a Kafka API key/secret via Confluent Cloud REST API (iam/v2/api-keys)
# Inputs: CONFLUENT_CLOUD_API_KEY/SECRET, SERVICE_ACCOUNT_ID, config for env/cluster

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"
LOGS_DIR="${ARTIFACTS_DIR}/logs"

mkdir -p "$SESSIONS_DIR" "$LOGS_DIR"
if [[ -z "${TEST_SESSION_ID:-}" ]]; then TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM; export TEST_SESSION_ID; fi
export LOG_FILE="${LOGS_DIR}/run-${TEST_SESSION_ID}.log"
. "${UTILS_DIR}/logging.sh"

API_BASE="${CONFLUENT_API_BASE:-https://api.confluent.cloud}"
CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"
if [[ ! -f "$CONFIG_PATH" ]]; then log_error "rest-keygen: config missing"; exit 1; fi
if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then log_error "rest-keygen: missing cloud creds"; exit 1; fi
if [[ -z "${SERVICE_ACCOUNT_ID:-}" ]]; then log_error "rest-keygen: missing SERVICE_ACCOUNT_ID"; exit 1; fi

ENV_ID=$(jq -r '.environment_id' "$CONFIG_PATH")
CLUSTER_ID=$(jq -r '.cluster_id' "$CONFIG_PATH")

PAYLOAD=$(jq -n --arg sa "$SERVICE_ACCOUNT_ID" --arg env "$ENV_ID" --arg lkc "$CLUSTER_ID" '{
  spec: {
    display_name: "generated-by-rest",
    description: "Kafka API key via REST",
    owner: { id: $sa, api_version: "iam/v2", kind: "ServiceAccount" },
    resource: { id: $lkc, api_version: "cmk/v2", kind: "Cluster", environment: $env }
  }
}')

TMP=$(mktemp)
HTTP=$(curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -o "$TMP" -w '%{http_code}' -X POST "$API_BASE/iam/v2/api-keys" -d "$PAYLOAD" || true)

# The API may return 202 Accepted with the key and secret in the body
if [[ "$HTTP" != "201" && "$HTTP" != "200" && "$HTTP" != "202" ]]; then
  head -c 1024 "$TMP" >&2
  log_error "rest-keygen failed" http_code="$HTTP"
  rm -f "$TMP"
  exit 1
fi

KEY=$(jq -r '.id // .spec.id // empty' "$TMP" 2>/dev/null || true)
SECRET=$(jq -r '.secret // .spec.secret // empty' "$TMP" 2>/dev/null || true)
rm -f "$TMP"
if [[ -z "$KEY" || -z "$SECRET" ]]; then
  log_error "rest-keygen: missing key/secret in response"
  exit 1
fi

SECRETS_PATH="${KAFKA_SECRETS_PATH:-${ROOT_DIR}/configs/kafka-secrets.local.json}"
umask 077
{
  printf '{"environment_id":%s,"cluster_id":%s,"kafka_api_key":%s,"kafka_api_secret":%s}\n' \
    "$(jq -Rs . <<<"$ENV_ID")" "$(jq -Rs . <<<"$CLUSTER_ID")" "$(jq -Rs . <<<"$KEY")" "$(jq -Rs . <<<"$SECRET")"
} >"$SECRETS_PATH"
chmod 600 "$SECRETS_PATH"
log_info "rest keygen success" secrets_path="$SECRETS_PATH"
echo "Saved Kafka key to $SECRETS_PATH" >&2