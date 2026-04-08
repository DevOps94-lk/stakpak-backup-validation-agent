#!/bin/bash
# Master backup validation orchestrator
# Called by Stakpak Autopilot cron schedule
set -uo pipefail

SCRIPTS_DIR="/root/.stakpak/scripts"
RESULTS_FILE="/tmp/stakpak_validation_results.txt"
> "$RESULTS_FILE"  # Clear results file

OVERALL_FAIL=0

run_step() {
  local STEP_NUM="$1"
  local STEP_NAME="$2"
  local SCRIPT="$3"

  echo ""
  echo "━━━ Step ${STEP_NUM}: ${STEP_NAME} ━━━━━━━━━━━━━━━━━━━━━━━━"

  if bash "$SCRIPT"; then
    echo "  [PASS] Step ${STEP_NUM} - ${STEP_NAME}" >> "$RESULTS_FILE"
  else
    echo "  [FAIL] Step ${STEP_NUM} - ${STEP_NAME}" >> "$RESULTS_FILE"
    OVERALL_FAIL=1
    return 1
  fi
}

echo "Starting backup validation pipeline at $(date)"

run_step 1 "Create Backup"           "${SCRIPTS_DIR}/01_create_backup.sh"      || true
run_step 2 "Integrity Check"         "${SCRIPTS_DIR}/02_integrity_check.sh"    || true
run_step 3 "Restore to Staging"      "${SCRIPTS_DIR}/03_restore_backup.sh"     || true
run_step 4 "Completeness Validation" "${SCRIPTS_DIR}/04_completeness_check.sh" || true
run_step 5 "Consistency Validation"  "${SCRIPTS_DIR}/05_consistency_check.sh"  || true
run_step 6 "Staging App Test"        "${SCRIPTS_DIR}/06_staging_app_test.sh"   || true

# Always generate report
bash "${SCRIPTS_DIR}/07_report.sh"

if [ "$OVERALL_FAIL" -eq 1 ]; then
  exit 1
fi

exit 0
