#!/bin/bash
# Step 7: Generate final validation report
set -euo pipefail

source /root/.stakpak/.env

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
BACKUP_FILE=$(cat "${BACKUP_DIR}/latest.txt" 2>/dev/null || echo "unknown")
LOG_DIR="/root/.stakpak/logs"
LOG_FILE="${LOG_DIR}/validation-$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

# Read step results (written by each script)
RESULTS_FILE="/tmp/stakpak_validation_results.txt"

print_report() {
  echo "========================================"
  echo "  BACKUP VALIDATION REPORT"
  echo "  Date   : ${TIMESTAMP}"
  echo "  Backup : $(basename $BACKUP_FILE)"
  echo "  Source : ${DB_NAME}"
  echo "  Staging: ${STAGING_DB_NAME}"
  echo "========================================"
  cat "$RESULTS_FILE" 2>/dev/null || echo "  No results recorded."
  echo "========================================"
}

OVERALL="PASS"
if grep -q "FAIL" "$RESULTS_FILE" 2>/dev/null; then
  OVERALL="FAIL"
fi

echo "  OVERALL: ${OVERALL}"
echo "========================================"

print_report | tee "$LOG_FILE"

echo ""
echo "Full log saved to: ${LOG_FILE}"

if [ "$OVERALL" = "FAIL" ]; then
  exit 1
fi
