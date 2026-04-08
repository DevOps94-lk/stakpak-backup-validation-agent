---
uri: stakpak://stakpak-agent/backup-validation.md
description: Full database backup validation pipeline for stakpak_agent_db
version: "1.0"
tags:
  - backup
  - validation
  - mysql
  - staging
---

# Database Backup Validation Rulebook

## Overview

This rulebook defines the standard operating procedure (SOP) for validating
MySQL database backups for the `stakpak_agent_db` database.

Run all steps in order. Stop and report FAIL immediately if any step fails.

---

## Environment Variables

Before running, confirm these are set in the environment:
- `DB_USER` — MySQL username (e.g. stakpak_user)
- `DB_PASSWORD` — MySQL password
- `DB_NAME` — Source database name (stakpak_agent_db)
- `STAGING_DB_NAME` — Staging database name (stakpak_staging_db)
- `BACKUP_DIR` — Directory to store backups (/root/.stakpak/backups)
- `APP_BACKEND_URL` — Staging backend URL for API tests

---

## Step 1 — Create Backup

Run the backup script:

```bash
bash /root/.stakpak/scripts/01_create_backup.sh
```

Expected outcome:
- A `.sql.gz` backup file created in `$BACKUP_DIR`
- A `.sha256` checksum file created alongside it
- Script exits with code 0

If script fails, report FAIL and stop.

---

## Step 2 — Integrity Validation

Run the integrity check:

```bash
bash /root/.stakpak/scripts/02_integrity_check.sh
```

This verifies:
- Backup file exists and is not zero bytes
- SHA256 checksum matches the stored `.sha256` file
- File can be decompressed without errors

If any check fails, report FAIL: INTEGRITY and stop.

---

## Step 3 — Restore Backup to Staging Database

Run the restore script:

```bash
bash /root/.stakpak/scripts/03_restore_backup.sh
```

This will:
- Drop and recreate the staging database (`stakpak_staging_db`)
- Restore the backup into the staging database
- Confirm restoration completed with no errors

If restore fails, report FAIL: RESTORE and stop.

---

## Step 4 — Completeness Validation

Run the completeness check:

```bash
bash /root/.stakpak/scripts/04_completeness_check.sh
```

This compares source vs staging:
- Table list must match exactly
- Row count per table must match exactly

If any table or row count mismatches, report FAIL: COMPLETENESS with details.

---

## Step 5 — Consistency Validation

Run the consistency check:

```bash
bash /root/.stakpak/scripts/05_consistency_check.sh
```

This checks the staging database for:
- NULL values in NOT NULL columns
- Orphaned foreign key references (broken relationships)
- Duplicate primary keys
- ENUM field values outside allowed set

If any inconsistency found, report FAIL: CONSISTENCY with details.

---

## Step 6 — Staging Application Test

Run the staging app test:

```bash
bash /root/.stakpak/scripts/06_staging_app_test.sh
```

This will:
- Start a staging backend container pointing to `stakpak_staging_db`
- Wait for it to become healthy
- Run API tests:
  - GET /health → must return 200
  - GET /api/tasks → must return 200 with data array
  - POST /api/tasks → must create a task successfully
  - GET /api/tasks/:id → must return the created task
  - PUT /api/tasks/:id → must update successfully
  - DELETE /api/tasks/:id → must delete successfully
- Stop and remove the staging container after tests

If any API test fails, report FAIL: STAGING APP TEST with which endpoint failed.

---

## Step 7 — Generate Final Report

Run the report script:

```bash
bash /root/.stakpak/scripts/07_report.sh
```

Print a clear summary:

```
========================================
  BACKUP VALIDATION REPORT
  Date: <timestamp>
  Backup: <filename>
========================================
  [PASS/FAIL] Step 1 - Backup Created
  [PASS/FAIL] Step 2 - Integrity Check
  [PASS/FAIL] Step 3 - Restore
  [PASS/FAIL] Step 4 - Completeness
  [PASS/FAIL] Step 5 - Consistency
  [PASS/FAIL] Step 6 - Staging App Test
========================================
  OVERALL: PASS / FAIL
========================================
```

---

## Failure Escalation

If OVERALL result is FAIL:
1. Log full details to `/root/.stakpak/logs/validation-<timestamp>.log`
2. Print clear error summary to stdout
3. Exit with code 1 so Stakpak autopilot marks this run as failed
