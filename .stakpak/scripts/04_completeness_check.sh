#!/bin/bash
# Step 4: Completeness Validation - tables + row counts
set -euo pipefail

source /root/.stakpak/.env

MYSQL_CMD="mysql -u $DB_USER -p$DB_PASSWORD"
FAIL=0

echo "[04] Running completeness validation..."
echo "[04] Source: ${DB_NAME} | Staging: ${STAGING_DB_NAME}"

# Get table lists
SOURCE_TABLES=$($MYSQL_CMD -se "SELECT table_name FROM information_schema.tables WHERE table_schema='${DB_NAME}' ORDER BY table_name;")
STAGING_TABLES=$($MYSQL_CMD -se "SELECT table_name FROM information_schema.tables WHERE table_schema='${STAGING_DB_NAME}' ORDER BY table_name;")

# Compare table lists
if [ "$SOURCE_TABLES" != "$STAGING_TABLES" ]; then
  echo "[04] FAIL: Table list mismatch."
  echo "  Source tables:  $SOURCE_TABLES"
  echo "  Staging tables: $STAGING_TABLES"
  FAIL=1
else
  echo "[04] Table list matches: OK"
fi

# Compare row counts per table
echo "[04] Comparing row counts per table..."
echo "-----------------------------------------------"
printf "  %-30s %10s %10s %s\n" "TABLE" "SOURCE" "STAGING" "STATUS"
echo "-----------------------------------------------"

for TABLE in $SOURCE_TABLES; do
  SOURCE_COUNT=$($MYSQL_CMD -se "SELECT COUNT(*) FROM \`${DB_NAME}\`.\`${TABLE}\`;")
  STAGING_COUNT=$($MYSQL_CMD -se "SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`${TABLE}\`;")

  if [ "$SOURCE_COUNT" -eq "$STAGING_COUNT" ]; then
    STATUS="OK"
  else
    STATUS="MISMATCH"
    FAIL=1
  fi

  printf "  %-30s %10s %10s %s\n" "$TABLE" "$SOURCE_COUNT" "$STAGING_COUNT" "$STATUS"
done

echo "-----------------------------------------------"

if [ "$FAIL" -eq 1 ]; then
  echo "[04] FAIL: Completeness validation failed."
  exit 1
fi

echo "[04] PASS: All tables and row counts match."
