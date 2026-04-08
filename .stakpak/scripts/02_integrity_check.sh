#!/bin/bash
# Step 2: Integrity Validation - checksum + decompress test
set -euo pipefail

source /root/.stakpak/.env

BACKUP_FILE=$(cat "${BACKUP_DIR}/latest.txt")
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

echo "[02] Running integrity check on: ${BACKUP_FILE}"

# Check file exists and is not empty
if [ ! -s "$BACKUP_FILE" ]; then
  echo "[02] FAIL: Backup file missing or empty."
  exit 1
fi

# Verify SHA256 checksum
echo "[02] Verifying SHA256 checksum..."
if ! sha256sum --check "$CHECKSUM_FILE" --status; then
  echo "[02] FAIL: Checksum mismatch — backup may be corrupted."
  exit 1
fi
echo "[02] Checksum OK."

# Test decompression (don't write output, just verify)
echo "[02] Testing gzip decompression..."
if ! gzip --test "$BACKUP_FILE"; then
  echo "[02] FAIL: Backup file failed gzip integrity test."
  exit 1
fi
echo "[02] Decompression test OK."

# Check SQL content makes sense (has CREATE TABLE or INSERT)
echo "[02] Checking SQL content structure..."
SQL_PREVIEW=$(zcat "$BACKUP_FILE" | head -50)
if ! echo "$SQL_PREVIEW" | grep -q "MySQL dump\|MariaDB dump\|CREATE TABLE\|INSERT INTO"; then
  echo "[02] FAIL: Backup does not appear to contain valid SQL."
  exit 1
fi

echo "[02] PASS: Integrity validation complete."
