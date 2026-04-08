#!/bin/bash
# Step 6: Staging Application Test
# Spins up backend pointed at staging DB, runs full API test suite, tears down.
set -euo pipefail

source /root/.stakpak/.env

STAGING_URL="http://localhost:5001"
COMPOSE_FILE="/root/.stakpak/staging/docker-compose.yml"
FAIL=0
CREATED_ID=""

cleanup() {
  echo "[06] Stopping staging containers..."
  docker compose -f "$COMPOSE_FILE" --env-file /root/.stakpak/.env down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

echo "[06] Starting staging backend (pointing to ${STAGING_DB_NAME})..."
docker compose -f "$COMPOSE_FILE" --env-file /root/.stakpak/.env up -d

# Wait for healthy
echo "[06] Waiting for staging backend to be healthy..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' stakpak_staging_backend 2>/dev/null || echo "starting")
  if [ "$STATUS" = "healthy" ]; then
    echo "[06] Staging backend is healthy."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[06] FAIL: Staging backend did not become healthy in time."
    exit 1
  fi
  sleep 2
done

run_test() {
  local NAME="$1"
  local METHOD="$2"
  local ENDPOINT="$3"
  local DATA="$4"
  local EXPECTED_STATUS="$5"

  RESPONSE=$(curl -s -o /tmp/staging_resp.json -w "%{http_code}" \
    -X "$METHOD" \
    -H "Content-Type: application/json" \
    ${DATA:+-d "$DATA"} \
    "${STAGING_URL}${ENDPOINT}")

  if [ "$RESPONSE" -eq "$EXPECTED_STATUS" ]; then
    echo "[06]   PASS  ${METHOD} ${ENDPOINT} → ${RESPONSE}"
  else
    echo "[06]   FAIL  ${METHOD} ${ENDPOINT} → ${RESPONSE} (expected ${EXPECTED_STATUS})"
    FAIL=1
  fi

  cat /tmp/staging_resp.json
  echo ""
}

echo "[06] Running API tests against ${STAGING_URL}..."
echo "-----------------------------------------------"

# 1. Health check
run_test "Health Check" "GET" "/health" "" 200

# 2. Get all tasks (should return existing rows from backup)
run_test "Get All Tasks" "GET" "/api/tasks" "" 200

TASK_COUNT=$(cat /tmp/staging_resp.json | grep -o '"id"' | wc -l || echo 0)
echo "[06]   Tasks found in staging DB: ${TASK_COUNT}"

# 3. Create a new task
run_test "Create Task" "POST" "/api/tasks" \
  '{"title":"Staging Test Task","description":"Auto-created by backup validation","status":"pending"}' \
  201

CREATED_ID=$(cat /tmp/staging_resp.json | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)
echo "[06]   Created task ID: ${CREATED_ID}"

# 4. Get task by ID
if [ -n "$CREATED_ID" ]; then
  run_test "Get Task By ID" "GET" "/api/tasks/${CREATED_ID}" "" 200
fi

# 5. Update task
if [ -n "$CREATED_ID" ]; then
  run_test "Update Task" "PUT" "/api/tasks/${CREATED_ID}" \
    '{"title":"Staging Test Task Updated","description":"Updated by validation","status":"done"}' \
    200
fi

# 6. Delete task
if [ -n "$CREATED_ID" ]; then
  run_test "Delete Task" "DELETE" "/api/tasks/${CREATED_ID}" "" 200
fi

# 7. Confirm deleted (should 404)
if [ -n "$CREATED_ID" ]; then
  run_test "Confirm Delete" "GET" "/api/tasks/${CREATED_ID}" "" 404
fi

echo "-----------------------------------------------"

if [ "$FAIL" -eq 1 ]; then
  echo "[06] FAIL: One or more staging API tests failed."
  exit 1
fi

echo "[06] PASS: All staging application tests passed."
