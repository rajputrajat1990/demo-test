#!/usr/bin/env bash
# Phase 2 scaffold: Run terraform test if configs exist; otherwise log SKIP.
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UTILS_DIR="${ROOT_DIR}/scripts/utils"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
LOGS_DIR="${ARTIFACTS_DIR}/logs"
SESSIONS_DIR="${ARTIFACTS_DIR}/sessions"

mkdir -p "${LOGS_DIR}" "${SESSIONS_DIR}"

# Session handling: reuse existing or create new
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

log_info "validation started" session_script="validate.sh"

if [[ -d "${ROOT_DIR}/terraform" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    log_info "terraform test starting" dir="${ROOT_DIR}/terraform"
  TMP_OUT=$(mktemp)
  TMP_CLEAN=$(mktemp)
    (
      cd "${ROOT_DIR}/terraform"
      terraform init -input=false >/dev/null 2>&1 || true
      terraform test -test-directory=. | tee "$TMP_OUT" || true
    )
    # Strip ANSI escape codes for reliable parsing
    sed -r 's/\x1B\[[0-9;]*[mK]//g' "$TMP_OUT" > "$TMP_CLEAN" || cp "$TMP_OUT" "$TMP_CLEAN"

    # Prefer parsing Terraform's final summary line
    if grep -qE '^Success! [0-9]+ passed, [0-9]+ failed\.$' "$TMP_CLEAN"; then
      PASS_CNT=$(grep -E '^Success! [0-9]+ passed, [0-9]+ failed\.$' "$TMP_CLEAN" | tail -n1 | sed -E 's/^Success! ([0-9]+) passed, ([0-9]+) failed\.$/\1/')
      FAIL_CNT=$(grep -E '^Success! [0-9]+ passed, [0-9]+ failed\.$' "$TMP_CLEAN" | tail -n1 | sed -E 's/^Success! ([0-9]+) passed, ([0-9]+) failed\.$/\2/')
    else
      # Fallback: count per-run lines
      PASS_CNT=$(awk '/run ".*"\.\.\. pass($| )/ {c++} END {print c+0}' "$TMP_CLEAN")
      FAIL_CNT=$(awk '/run ".*"\.\.\. fail($| )/ {c++} END {print c+0}' "$TMP_CLEAN")
    fi
    SKIP_CNT=0
    TOTAL=$((PASS_CNT + FAIL_CNT + SKIP_CNT))

    SESSION_DIR="${SESSIONS_DIR}/${TEST_SESSION_ID}"
    mkdir -p "$SESSION_DIR"
    SUMMARY_FILE="${SESSION_DIR}/validation_summary.json"
    {
      echo "{";
      echo "  \"test_session_id\": \"${TEST_SESSION_ID}\",";
      echo "  \"totals\": {\"pass\": ${PASS_CNT}, \"fail\": ${FAIL_CNT}, \"skip\": ${SKIP_CNT}, \"total\": ${TOTAL}},";
      echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"";
      echo "}";
    } > "$SUMMARY_FILE"

    log_info "terraform test finished" pass_count="$PASS_CNT" fail_count="$FAIL_CNT" skip_count="$SKIP_CNT" summary_file="$SUMMARY_FILE"
    rm -f "$TMP_OUT"
  else
    log_warn "terraform CLI not found; skipping terraform test"
  fi
else
  log_info "no terraform directory found; validation skipped" reason="missing terraform configs"
fi

log_info "validation complete"
