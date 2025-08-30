#!/usr/bin/env bash
set -euo pipefail

# Grants DeveloperRead role on the Kafka cluster to the given service account via Terraform.
# Inputs:
# - SERVICE_ACCOUNT_ID (sa-xxxxx)
# - Confluent Cloud provider creds: CONFLUENT_CLOUD_API_KEY/CONFLUENT_CLOUD_API_SECRET
# - environment_details.json for environment_id/cluster_id

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"
LOGS_DIR="${ARTIFACTS_DIR}/logs"

mkdir -p "$SESSIONS_DIR" "$LOGS_DIR"

if [[ -z "${TEST_SESSION_ID:-}" ]]; then
  TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM; export TEST_SESSION_ID
fi
export LOG_FILE="${LOGS_DIR}/run-${TEST_SESSION_ID}.log"
. "${UTILS_DIR}/logging.sh"

CONFIG_PATH="${CONFIG_PATH:-${ROOT_DIR}/configs/environment_details.json}"
if [[ ! -f "$CONFIG_PATH" ]]; then log_error "rbac: config missing"; exit 1; fi
if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then log_error "rbac: missing cloud creds"; exit 1; fi
if [[ -z "${SERVICE_ACCOUNT_ID:-}" ]]; then log_error "rbac: missing SERVICE_ACCOUNT_ID"; exit 1; fi

ENV_ID=$(jq -r '.environment_id' "$CONFIG_PATH")
CLUSTER_ID=$(jq -r '.cluster_id' "$CONFIG_PATH")
ORG_ID=$(curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H 'Accept: application/json' "https://api.confluent.cloud/iam/v2/organizations" | jq -r '.data[0].id // empty')
if [[ -z "$ORG_ID" ]]; then log_error "rbac: unable to fetch org id"; exit 1; fi
KAFKA_CRN="crn://confluent.cloud/organization=${ORG_ID}/environment=${ENV_ID}/kafka=${CLUSTER_ID}"
PRINCIPAL="User:${SERVICE_ACCOUNT_ID}"

WORK_DIR="${ROOT_DIR}/.external/rbac-${TEST_SESSION_ID}"
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

variable "principal"       { type = string }
variable "role_name"       { type = string }
variable "crn_pattern"     { type = string }
variable "cloud_api_key"   { type = string }
variable "cloud_api_secret"{ type = string }

module "rbac" {
  source      = "../../terraform/rbac"
  principal   = var.principal
  role_name   = var.role_name
  crn_pattern = var.crn_pattern
}

output "role_binding_id" { value = module.rbac.role_binding_id }
TF

pushd "$WORK_DIR" >/dev/null
terraform init -input=false -no-color >/dev/null
terraform apply -auto-approve -input=false -no-color \
  -var "principal=$PRINCIPAL" \
  -var "role_name=DeveloperRead" \
  -var "crn_pattern=$KAFKA_CRN" \
  -var "cloud_api_key=${CONFLUENT_CLOUD_API_KEY}" \
  -var "cloud_api_secret=${CONFLUENT_CLOUD_API_SECRET}" >/dev/null
RB_ID=$(terraform output -raw role_binding_id)
popd >/dev/null

SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
OUT="${SESSION_DIR}/rbac_grant.json"
printf '{"test_session_id":"%s","principal":"%s","role":"DeveloperRead","crn":"%s","role_binding_id":"%s"}\n' "$TEST_SESSION_ID" "$PRINCIPAL" "$KAFKA_CRN" "$RB_ID" >"$OUT"
log_info "rbac granted" principal="$PRINCIPAL" role="DeveloperRead" crn="$KAFKA_CRN" role_binding_id="$RB_ID" output_file="$OUT"
echo "RBAC granted: $OUT" >&2