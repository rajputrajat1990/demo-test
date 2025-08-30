#!/usr/bin/env bash
set -euo pipefail

# Generate a Kafka API key/secret using the confluent_api_key Terraform resource.
# Requirements:
# - CONFLUENT_CLOUD_API_KEY / CONFLUENT_CLOUD_API_SECRET set for provider auth
# - configs/environment_details.json must contain environment_id and cluster_id
# - SERVICE_ACCOUNT_ID (sa-xxxxx) must be provided to own the key
#
# Outputs:
# - artifacts/sessions/<TEST_SESSION_ID>/kafka_api_key.json (sensitive; stored locally, not checked in)

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
LOGS_DIR="${ARTIFACTS_DIR}/logs"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"

mkdir -p "${LOGS_DIR}" "${SESSIONS_DIR}"

if [[ -z "${TEST_SESSION_ID:-}" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then TEST_SESSION_ID=$(uuidgen | tr 'A-Z' 'a-z'); else TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM; fi
  export TEST_SESSION_ID
fi
export LOG_FILE="${LOGS_DIR}/run-${TEST_SESSION_ID}.log"
. "${UTILS_DIR}/logging.sh"

CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"
if [[ ! -f "$CONFIG_PATH" ]]; then
  log_error "keygen: config file not found" script=generate-kafka-api-key.sh config_path="$CONFIG_PATH"
  exit 1
fi

if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then
  log_error "keygen: missing Confluent Cloud API credentials for provider auth" script=generate-kafka-api-key.sh
  echo "CONFLUENT_CLOUD_API_KEY/SECRET are required for provider auth" >&2
  exit 1
fi

if [[ -z "${SERVICE_ACCOUNT_ID:-}" ]]; then
  log_error "keygen: missing SERVICE_ACCOUNT_ID (sa-xxxxx)" script=generate-kafka-api-key.sh
  echo "SERVICE_ACCOUNT_ID env var is required (sa-xxxxx)" >&2
  exit 1
fi

ENV_ID=$(jq -r '.environment_id // empty' "$CONFIG_PATH")
CLUSTER_ID=$(jq -r '.cluster_id // empty' "$CONFIG_PATH")
if [[ -z "$ENV_ID" || -z "$CLUSTER_ID" ]]; then
  log_error "keygen: missing environment_id or cluster_id in config" env_id="$ENV_ID" cluster_id="$CLUSTER_ID"
  exit 1
fi

WORK_DIR="${ROOT_DIR}/.external/keygen-${TEST_SESSION_ID}"
mkdir -p "$WORK_DIR"
cat >"$WORK_DIR/main.tf" <<'TF'
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = ">= 2.0.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.cloud_api_key
  cloud_api_secret = var.cloud_api_secret
}

variable "environment_id" { type = string }
variable "kafka_cluster_id" { type = string }
variable "owner_service_account_id" { type = string }
variable "cloud_api_key" { type = string }
variable "cloud_api_secret" { type = string }

module "keygen" {
  source                   = "../../terraform/keygen"
  environment_id           = var.environment_id
  kafka_cluster_id         = var.kafka_cluster_id
  owner_service_account_id = var.owner_service_account_id
}

output "api_key" {
  value     = module.keygen.api_key
  sensitive = true
}
output "api_secret" {
  value     = module.keygen.api_secret
  sensitive = true
}
TF

pushd "$WORK_DIR" >/dev/null

export TF_IN_AUTOMATION=1
echo "Initializing Terraform..." >&2
terraform init -input=false -no-color >/dev/null

KEYGEN_TIMEOUT_SEC=${KEYGEN_TIMEOUT_SEC:-120}
KEYGEN_RETRIES=${KEYGEN_RETRIES:-1}

apply_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${secs}s" "$@"
    return $?
  else
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null || true ) &
    local killer=$!
    wait "$pid" 2>/dev/null; local rc=$?
    kill -TERM "$killer" 2>/dev/null || true
    return $rc
  fi
}

KEY=""; SECRET=""
attempt=0
while [[ $attempt -le $KEYGEN_RETRIES ]]; do
  attempt=$((attempt+1))
  echo "Applying to create API key (attempt ${attempt}) with ${KEYGEN_TIMEOUT_SEC}s timeout..." >&2
  set +e
  apply_with_timeout "$KEYGEN_TIMEOUT_SEC" terraform apply -auto-approve -input=false -no-color \
    -var "environment_id=$ENV_ID" \
    -var "kafka_cluster_id=$CLUSTER_ID" \
    -var "owner_service_account_id=$SERVICE_ACCOUNT_ID" \
    -var "cloud_api_key=${CONFLUENT_CLOUD_API_KEY}" \
    -var "cloud_api_secret=${CONFLUENT_CLOUD_API_SECRET}" >/dev/null
  rc=$?
  set -e
  # Try to fetch outputs regardless; may succeed if resource finished
  OUT_JSON=$(terraform output -json 2>/dev/null || true)
  KEY=$(jq -r 'try(.api_key.value) // empty' <<<"$OUT_JSON" 2>/dev/null || true)
  SECRET=$(jq -r 'try(.api_secret.value) // empty' <<<"$OUT_JSON" 2>/dev/null || true)
  if [[ -n "$KEY" && -n "$SECRET" ]]; then
    break
  fi
  if [[ $attempt -le $KEYGEN_RETRIES ]]; then
    echo "Retrying key creation shortly..." >&2
    sleep 3
  fi
done

popd >/dev/null

contains_ctrl(){ printf "%s" "$1" | grep -qP '[\x00-\x1F]'; }
if [[ -z "$KEY" || -z "$SECRET" ]] || contains_ctrl "$KEY" || contains_ctrl "$SECRET"; then
  log_error "kafka api key generation failed or timed out" service_account="$SERVICE_ACCOUNT_ID" timeout_sec="$KEYGEN_TIMEOUT_SEC" attempts="$((KEYGEN_RETRIES+1))"
  echo "Key generation failed or timed out. You can adjust KEYGEN_TIMEOUT_SEC or KEYGEN_RETRIES and try again." >&2
  exit 1
fi

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT_FILE="${SESSION_DIR}/kafka_api_key.json"
{
  echo "{";
  printf '  "test_session_id": %s,\n' "$(jq -Rs . <<<"${TEST_SESSION_ID}")";
  printf '  "environment_id": %s,\n' "$(jq -Rs . <<<"${ENV_ID}")";
  printf '  "cluster_id": %s,\n' "$(jq -Rs . <<<"${CLUSTER_ID}")";
  printf '  "owner_service_account_id": %s,\n' "$(jq -Rs . <<<"${SERVICE_ACCOUNT_ID}")";
  printf '  "kafka_api_key": %s,\n' "$(jq -Rs . <<<"${KEY}")";
  printf '  "kafka_api_secret": %s\n' "$(jq -Rs . <<<"${SECRET}")";
  echo "}";
} >"$OUT_FILE"

chmod 600 "$OUT_FILE"
log_info "kafka api key generated" output_file="$OUT_FILE" service_account="$SERVICE_ACCOUNT_ID"
echo "Kafka API key written to: $OUT_FILE (sensitive)" >&2

# Optionally persist local secrets for test scripts to consume automatically
KAFKA_SECRETS_PATH="${KAFKA_SECRETS_PATH:-${ROOT_DIR}/configs/kafka-secrets.local.json}"
if [[ "${DISABLE_LOCAL_SECRETS:-0}" != "1" ]]; then
  umask 077
  {
    echo "{";
    printf '  "environment_id": %s,\n' "$(jq -Rs . <<<"${ENV_ID}")";
    printf '  "cluster_id": %s,\n' "$(jq -Rs . <<<"${CLUSTER_ID}")";
    printf '  "kafka_api_key": %s,\n' "$(jq -Rs . <<<"${KEY}")";
    printf '  "kafka_api_secret": %s\n' "$(jq -Rs . <<<"${SECRET}")";
    echo "}";
  } >"$KAFKA_SECRETS_PATH"
  chmod 600 "$KAFKA_SECRETS_PATH"
  log_info "local kafka secrets saved" secrets_path="$KAFKA_SECRETS_PATH"
  echo "Local Kafka secrets saved to: $KAFKA_SECRETS_PATH (gitignored)" >&2
fi
