#!/usr/bin/env bash
# Phase 1: setup
# - Prompt or read ATTACH_MODE (existing_env | official_modules)
# - If existing_env: load and validate configs/environment_details.json
# - Else: clone official terraform provider repo
# - Clone internal test framework repo if provided
# - Init logging system with per-run TEST_SESSION_ID
# - Create artifacts directories and snapshot run context

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS_DIR="${ROOT_DIR}/scripts"
UTILS_DIR="${SCRIPTS_DIR}/utils"
CONFIGS_DIR="${ROOT_DIR}/configs"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
LOGS_DIR="${ARTIFACTS_DIR}/logs"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"

mkdir -p "${LOGS_DIR}" "${SESSIONS_DIR}"

# Generate per-run session id (uuid-like). Prefer uuidgen if present.
if command -v uuidgen >/dev/null 2>&1; then
  TEST_SESSION_ID=$(uuidgen | tr 'A-Z' 'a-z')
else
  TEST_SESSION_ID=$(date +%s)-$RANDOM-$RANDOM
fi
export TEST_SESSION_ID
export LOG_FILE="${LOGS_DIR}/run-${TEST_SESSION_ID}.log"

# shellcheck source=./utils/logging.sh
. "${UTILS_DIR}/logging.sh"

log_info "session started" session_script="setup.sh" root_dir="${ROOT_DIR}" log_file="${LOG_FILE}" \
  shell="${SHELL:-unknown}" os="$(uname -a | cut -d' ' -f1-3)"

ATTACH_MODE="${ATTACH_MODE:-}"
if [[ -z "${ATTACH_MODE}" ]]; then
  echo "Select attach mode:"
  select choice in existing_env official_modules; do
    case $choice in
      existing_env|official_modules)
        ATTACH_MODE=$choice; break ;;
      *) echo "Invalid choice";;
    esac
  done
fi

log_info "attach mode chosen" attach_mode="${ATTACH_MODE}"

# Validate attach mode
if [[ "${ATTACH_MODE}" != "existing_env" && "${ATTACH_MODE}" != "official_modules" ]]; then
  log_error "invalid ATTACH_MODE" value="${ATTACH_MODE}"
  echo "Error: ATTACH_MODE must be existing_env or official_modules" >&2
  exit 2
fi

# Function: validate environment_details.json structure minimally
validate_env_json() {
  local file="$1"
  if ! [[ -f "$file" ]]; then
    log_error "environment_details.json not found" path="$file"
    echo "Missing $file" >&2
    return 1
  fi
  # Try using jq if available for schema-ish checks
  if command -v jq >/dev/null 2>&1; then
    local required_keys='["environment_id","cluster_id","topics_config"]'
    local ok
    ok=$(jq -r --argjson keys "$required_keys" '($keys - (keys)) | length == 0' "$file" 2>/dev/null || echo "false")
    if [[ "$ok" != "true" ]]; then
      log_error "environment_details.json missing required keys" path="$file"
      echo "Invalid environment_details.json: missing required keys" >&2
      return 1
    fi
    # Validate topics_config is array
    local is_array
    is_array=$(jq -r '.topics_config | type == "array"' "$file" 2>/dev/null || echo "false")
    if [[ "$is_array" != "true" ]]; then
      log_error "topics_config must be an array" path="$file"
      echo "Invalid environment_details.json: topics_config must be array" >&2
      return 1
    fi
  else
    log_warn "jq not found; performing minimal presence checks only"
  fi
  return 0
}

# Clone helper function
clone_repo() {
  local url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    log_info "repo already present, fetching" dest="$dest"
    git -C "$dest" fetch --all --tags || true
  else
    log_info "cloning repo" url="$url" dest="$dest"
    git clone --depth 1 "$url" "$dest"
  fi
}

# Main branch
case "${ATTACH_MODE}" in
  existing_env)
    ENV_JSON="${CONFIGS_DIR}/environment_details.json"
    if validate_env_json "$ENV_JSON"; then
      log_info "environment details validated" path="$ENV_JSON"
    else
      log_error "environment details validation failed" path="$ENV_JSON"
      exit 3
    fi
    ;;
  official_modules)
    OFFICIAL_PROVIDER_REPO_URL="${OFFICIAL_PROVIDER_REPO_URL:-https://github.com/confluentinc/terraform-provider-confluent.git}"
    DEST_DIR="${ROOT_DIR}/.external/terraform-provider-confluent"
    mkdir -p "$(dirname "$DEST_DIR")"
    clone_repo "$OFFICIAL_PROVIDER_REPO_URL" "$DEST_DIR"
    ;;
esac

# Optionally clone internal framework repo if provided
if [[ -n "${INTERNAL_FRAMEWORK_REPO_URL:-}" ]]; then
  DEST_DIR2="${ROOT_DIR}/.external/internal-framework"
  mkdir -p "$(dirname "$DEST_DIR2")"
  clone_repo "$INTERNAL_FRAMEWORK_REPO_URL" "$DEST_DIR2"
fi

# Snapshot run context
SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
mkdir -p "$SESSION_DIR"
{
  echo "{"
  echo "  \"test_session_id\": \"${TEST_SESSION_ID}\","
  echo "  \"attach_mode\": \"${ATTACH_MODE}\","
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"hostname\": \"$(hostname)\""
  echo "}"
} > "${SESSION_DIR}/context.json"

log_info "session context persisted" session_dir="$SESSION_DIR"

# Final message
log_info "setup complete" attach_mode="${ATTACH_MODE}"
echo "Setup complete. Session: ${TEST_SESSION_ID}"
