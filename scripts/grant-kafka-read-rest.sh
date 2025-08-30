#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
. "${UTILS_DIR}/logging.sh"

API_BASE="${CONFLUENT_API_BASE:-https://api.confluent.cloud}"
CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"
if [[ ! -f "$CONFIG_PATH" ]]; then log_error "rest-rbac: config missing"; exit 1; fi
if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then log_error "rest-rbac: missing cloud creds"; exit 1; fi
if [[ -z "${SERVICE_ACCOUNT_ID:-}" ]]; then log_error "rest-rbac: missing SERVICE_ACCOUNT_ID"; exit 1; fi

ENV_ID=$(jq -r '.environment_id' "$CONFIG_PATH")
CLUSTER_ID=$(jq -r '.cluster_id' "$CONFIG_PATH")
ORG_ID=$(curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H 'Accept: application/json' "$API_BASE/iam/v2/organizations" | jq -r '.data[0].id // empty')
CRN="crn://confluent.cloud/organization=${ORG_ID}/environment=${ENV_ID}/kafka=${CLUSTER_ID}"

PAYLOAD=$(jq -n --arg principal "User:${SERVICE_ACCOUNT_ID}" --arg crn "$CRN" '{
  principal: $principal,
  role_name: "DeveloperRead",
  crn_pattern: $crn
}')

TMP=$(mktemp)
HTTP=$(curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -o "$TMP" -w '%{http_code}' -X POST "$API_BASE/iam/v2/role-bindings" -d "$PAYLOAD" || true)
echo "HTTP=$HTTP" >&2
head -c 512 "$TMP" >&2 || true
rm -f "$TMP"
if [[ "$HTTP" != "201" && "$HTTP" != "200" ]]; then exit 1; fi
echo "RBAC grant completed" >&2