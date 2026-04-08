#!/bin/bash
# Step 3: Restore backup to staging database
set -euo pipefail

source /root/.stakpak/.env

BACKUP_FILE=$(cat "${BACKUP_DIR}/latest.txt")

echo "[03] Restoring backup to staging database: ${STAGING_DB_NAME}"

MYSQL_CMD="mysql -u $DB_USER -p$DB_PASSWORD"

# Drop and recreate staging DB for clean restore
echo "[03] Dropping and recreating staging database..."
$MYSQL_CMD -e "DROP DATABASE IF EXISTS \`${STAGING_DB_NAME}\`;"
$MYSQL_CMD -e "CREATE DATABASE \`${STAGING_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Restore backup
echo "[03] Restoring data..."
zcat "$BACKUP_FILE" | $MYSQL_CMD "$STAGING_DB_NAME"

# Verify staging DB has tables
TABLE_COUNT=$($MYSQL_CMD -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${STAGING_DB_NAME}';")

if [ "$TABLE_COUNT" -eq 0 ]; then
  echo "[03] FAIL: Staging database has no tables after restore."
  exit 1
fi

echo "[03] PASS: Restored successfully. Tables found: ${TABLE_COUNT}"
