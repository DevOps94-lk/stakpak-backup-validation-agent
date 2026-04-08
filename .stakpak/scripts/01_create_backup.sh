#!/bin/bash
# Step 1: Create MySQL backup with SHA256 checksum
set -euo pipefail

source /root/.stakpak/.env

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backup_${DB_NAME}_${TIMESTAMP}.sql.gz"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

mkdir -p "$BACKUP_DIR"

echo "[01] Creating backup of ${DB_NAME}..."

mysqldump \
  -u "$DB_USER" \
  -p"$DB_PASSWORD" \
  --single-transaction \
  --routines \
  --triggers \
  --hex-blob \
  "$DB_NAME" | gzip > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
  echo "[01] FAIL: Backup file is empty or missing."
  exit 1
fi

# Generate SHA256 checksum
sha256sum "$BACKUP_FILE" > "$CHECKSUM_FILE"

FILESIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "[01] PASS: Backup created → ${BACKUP_FILE} (${FILESIZE})"
echo "[01] Checksum → $(cat $CHECKSUM_FILE)"

# Save latest backup path for other scripts
echo "$BACKUP_FILE" > "${BACKUP_DIR}/latest.txt"
