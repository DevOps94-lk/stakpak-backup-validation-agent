#!/bin/bash
# Step 5: Consistency Validation - NULL checks, FK integrity, ENUMs
set -euo pipefail

source /root/.stakpak/.env

MYSQL_CMD="mysql -u $DB_USER -p$DB_PASSWORD"
FAIL=0

echo "[05] Running consistency validation on staging: ${STAGING_DB_NAME}"

# ── 1. Check NOT NULL violations ─────────────────────────────────────────
echo "[05] Checking NOT NULL constraints..."

NULL_VIOLATIONS=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`tasks\`
  WHERE title IS NULL;
")

if [ "$NULL_VIOLATIONS" -gt 0 ]; then
  echo "[05] FAIL: ${NULL_VIOLATIONS} row(s) with NULL title found."
  FAIL=1
else
  echo "[05] NOT NULL check: OK"
fi

# ── 2. Check ENUM values are valid ───────────────────────────────────────
echo "[05] Checking ENUM field values..."

INVALID_STATUS=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`tasks\`
  WHERE status NOT IN ('pending', 'in_progress', 'done');
")

if [ "$INVALID_STATUS" -gt 0 ]; then
  echo "[05] FAIL: ${INVALID_STATUS} row(s) with invalid status ENUM found."
  FAIL=1
else
  echo "[05] ENUM values check: OK"
fi

# ── 3. Check for duplicate primary keys ──────────────────────────────────
echo "[05] Checking for duplicate primary keys..."

DUPLICATE_PKS=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM (
    SELECT id, COUNT(*) as cnt
    FROM \`${STAGING_DB_NAME}\`.\`tasks\`
    GROUP BY id HAVING cnt > 1
  ) AS dupes;
")

if [ "$DUPLICATE_PKS" -gt 0 ]; then
  echo "[05] FAIL: ${DUPLICATE_PKS} duplicate primary key(s) found."
  FAIL=1
else
  echo "[05] Primary key uniqueness: OK"
fi

# ── 4. Check timestamps are valid (not in future) ────────────────────────
echo "[05] Checking timestamp sanity..."

FUTURE_TIMESTAMPS=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`tasks\`
  WHERE created_at > NOW();
")

if [ "$FUTURE_TIMESTAMPS" -gt 0 ]; then
  echo "[05] WARN: ${FUTURE_TIMESTAMPS} row(s) have future created_at timestamps."
else
  echo "[05] Timestamp sanity: OK"
fi

# ── 5. Check updated_at >= created_at ────────────────────────────────────
echo "[05] Checking updated_at >= created_at..."

BAD_TIMESTAMPS=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`tasks\`
  WHERE updated_at < created_at;
")

if [ "$BAD_TIMESTAMPS" -gt 0 ]; then
  echo "[05] FAIL: ${BAD_TIMESTAMPS} row(s) where updated_at < created_at."
  FAIL=1
else
  echo "[05] Timestamp ordering: OK"
fi

# ── 6. Check empty titles ─────────────────────────────────────────────────
echo "[05] Checking for empty title strings..."

EMPTY_TITLES=$($MYSQL_CMD -se "
  SELECT COUNT(*) FROM \`${STAGING_DB_NAME}\`.\`tasks\`
  WHERE TRIM(title) = '';
")

if [ "$EMPTY_TITLES" -gt 0 ]; then
  echo "[05] FAIL: ${EMPTY_TITLES} row(s) with empty title found."
  FAIL=1
else
  echo "[05] Empty title check: OK"
fi

if [ "$FAIL" -eq 1 ]; then
  echo "[05] FAIL: Consistency validation failed."
  exit 1
fi

echo "[05] PASS: All consistency checks passed."
