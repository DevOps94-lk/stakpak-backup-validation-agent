# Stakpak Backup Validation Agent

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Stakpak Compatible](https://img.shields.io/badge/Stakpak-Compatible-blue)](https://stakpak.dev)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-orange)](https://mysql.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED)](https://docker.com)

A **fully automated MySQL database backup validation system** powered by [Stakpak Autopilot](https://stakpak.dev). Built on top of a React + Node.js + MySQL CRUD application deployed on DigitalOcean.

---

## Features

- **Automated Backups** — mysqldump on schedule with SHA256 checksums
- **Integrity Validation** — Verify backup is not corrupted
- **Staging Restore** — Test real database recovery process
- **Completeness Checks** — All tables present, row counts match
- **Consistency Checks** — NULL constraints, ENUMs, PKs, timestamps
- **API Testing** — Full CRUD tests on staging app with restored data
- **Slack Reports** — PASS/FAIL results posted automatically
- **Zero Manual Work** — Fully autonomous, runs 24/7 on schedule
- **Extensible** — Works with any MySQL database and application

---

## What It Does

Every day at **2:00 AM** (and a quick integrity check every 6 hours), the Stakpak AI agent automatically:

1. Creates a compressed MySQL backup with SHA256 checksum
2. Verifies the backup is not corrupted
3. Restores it into an isolated staging database
4. Confirms all tables and row counts match production
5. Checks data consistency (NULLs, ENUMs, PKs, timestamps)
6. Spins up a staging app and runs full API tests against the restored data
7. Sends a PASS/FAIL report to Slack

> **No human intervention required.** The system runs autonomously 24/7.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    STAKPAK AUTOPILOT                             │
│  Cron: 0 2 * * *   →  daily-backup-validation                   │
│  Cron: 0 */6 * * * →  quick-integrity-check                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              APPROVALS & GATEWAY (Slack Integration)             │
│  approval_mode = "allow_all"  ← Auto-approves all tool calls    │
│  sandbox = false              ← Runs on host, not in container  │
│  delivery_context_ttl = 4 hrs ← Approval timeout                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   BASH SCRIPT ORCHESTRATOR                       │
│            /root/.stakpak/scripts/run_validation.sh              │
│  (Master script that runs all 7 validation steps in order)       │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────┬─────────┬─────────┬─────────┬─────────┬──────┐
        ▼         ▼         ▼         ▼         ▼         ▼      ▼
    Step 1    Step 2    Step 3    Step 4    Step 5    Step 6  Step 7
    CREATE  INTEGRITY  RESTORE  COMPLETE CONSISTENCY  STAGING  REPORT
    BACKUP  VALIDATE   TO DB    CHECK    VALIDATE     APP TEST
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   EXTERNAL SYSTEMS                               │
├─────────────────────────────────────────────────────────────────┤
│ • MySQL Database (Production + Staging)                          │
│ • Docker Containers (Staging Backend on port 5001)               │
│ • Slack Channel (#stakpak-agent-database)                        │
│ • File System (/root/.stakpak/backups/, /root/.stakpak/logs/)    │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works — Full Workflow

### Scenario: Daily Backup Validation at 2 AM

```
1.  SCHEDULER FIRES
    └─ Autopilot cron triggers at 0 2 * * * (2 AM UTC)
    └─ Reads prompt: "Run the full database backup validation pipeline..."

2.  AUTOPILOT CREATES SESSION
    └─ Creates a new agent session
    └─ Sets approval_mode to "allow_all" (auto-approve tools)
    └─ Posts start message to Slack channel

3.  AGENT RUNS ORCHESTRATOR
    └─ Executes: bash /root/.stakpak/scripts/run_validation.sh
    └─ Master script runs steps 1–7 sequentially, stops on first failure

4.  STEP 1: CREATE BACKUP
    └─ mysqldump → gzip → SHA256 checksum
    └─ Output: /root/.stakpak/backups/backup_stakpak_agent_db_YYYYMMDD.sql.gz
    └─ Also writes: .sha256 file + latest.txt pointer

5.  STEP 2: INTEGRITY CHECK
    └─ Reads latest.txt to find backup filename
    └─ Verifies: SHA256 match + gzip OK + valid SQL structure
    └─ If FAIL → stops here, reports FAIL to Slack

6.  STEP 3: RESTORE TO STAGING
    └─ Drops old stakpak_staging_db, creates fresh one
    └─ zcat backup.sql.gz | mysql stakpak_staging_db
    └─ If FAIL → stops, reports FAIL

7.  STEP 4: COMPLETENESS CHECK
    └─ Queries information_schema.tables in both databases
    └─ Compares table list + row counts production vs staging
    └─ If ANY mismatch → FAIL

8.  STEP 5: CONSISTENCY CHECK (6 sub-checks)
    └─ NULL violations     (title IS NULL)
    └─ ENUM violations     (status NOT IN 'pending','in_progress','done')
    └─ Duplicate PKs       (GROUP BY id HAVING COUNT > 1)
    └─ Future timestamps   (created_at > NOW())
    └─ Bad ordering        (updated_at < created_at)
    └─ Empty titles        (TRIM(title) = '')
    └─ If ANY violation → FAIL

9.  STEP 6: STAGING APP TEST (7 API calls)
    └─ docker compose up -d (staging backend on port 5001)
    └─ Waits until GET /health returns 200
    └─ Runs: GET /health, GET /api/tasks, POST, GET, PUT, DELETE, GET (404)
    └─ docker compose down (clean up)
    └─ If ANY test returns wrong HTTP code → FAIL

10. STEP 7: GENERATE REPORT
    └─ Reads /tmp/stakpak_validation_results.txt
    └─ Builds formatted PASS/FAIL report
    └─ Saves to /root/.stakpak/logs/validation-YYYYMMDD_HHMMSS.log
    └─ Exits 0 (PASS) or 1 (FAIL)

11. SLACK RECEIVES REPORT
    └─ Autopilot gateway sends full report to #stakpak-agent-database
    └─ Shows OVERALL PASS ✅ or OVERALL FAIL ❌ with all step details

12. SESSION ENDS
    └─ Run marked "completed" in autopilot history
    └─ Next run scheduled for tomorrow at 2 AM
```

---

## Project Structure

```
stakpak-backup-validation-agent/
├── backend/                        # Node.js + Express API
│   ├── src/
│   │   ├── config/db.js            # MySQL connection pool
│   │   ├── controllers/            # CRUD logic
│   │   ├── routes/                 # Express routes + validation
│   │   └── middleware/             # Error handler
│   ├── server.js
│   └── Dockerfile                  # Multi-stage production build
│
├── frontend/                       # React + Vite app
│   ├── src/
│   │   ├── api/taskApi.js          # Axios API layer
│   │   ├── components/             # TaskForm, TaskCard, TaskList
│   │   └── pages/HomePage.jsx      # Main page with state
│   ├── nginx.conf                  # Hardened Nginx config
│   └── Dockerfile                  # Multi-stage production build
│
├── database/
│   └── schema.sql                  # MySQL table definitions
│
├── docker-compose.yml              # Production: frontend + backend
├── deploy.sh                       # One-command redeploy script
│
└── .stakpak/                       # All Stakpak agent files
    ├── autopilot.toml              # Schedules + Slack channel config
    ├── config.toml                 # LLM profile (Claude Sonnet)
    ├── .env.example                # Environment variable template
    ├── setup-agent.sh              # One-time droplet setup script
    ├── rulebooks/
    │   └── backup-validation.md    # 7-step SOP for the AI agent
    ├── scripts/
    │   ├── 01_create_backup.sh     # mysqldump + SHA256
    │   ├── 02_integrity_check.sh   # Checksum + decompress test
    │   ├── 03_restore_backup.sh    # Restore to staging DB
    │   ├── 04_completeness_check.sh# Table + row count comparison
    │   ├── 05_consistency_check.sh # NULL, ENUM, PK, timestamp checks
    │   ├── 06_staging_app_test.sh  # Spin up app + run API tests
    │   ├── 07_report.sh            # Generate final report
    │   └── run_validation.sh       # Master orchestrator
    └── staging/
        └── docker-compose.yml      # Staging backend (port 5001)
```

---

## Validation Pipeline — 7 Steps

| Step | Script | What It Checks | Pass Criteria |
|------|--------|---------------|---------------|
| 1 | `01_create_backup.sh` | Create backup | File exists, not empty, SHA256 generated |
| 2 | `02_integrity_check.sh` | Integrity | SHA256 matches, gzip OK, valid SQL structure |
| 3 | `03_restore_backup.sh` | Restore | Staging DB has ≥1 table after restore |
| 4 | `04_completeness_check.sh` | Completeness | Table list + row counts match production |
| 5 | `05_consistency_check.sh` | Consistency | 0 NULL violations, valid ENUMs, no duplicate PKs, valid timestamps |
| 6 | `06_staging_app_test.sh` | App usability | All 7 API endpoints return correct HTTP codes |
| 7 | `07_report.sh` | Final report | Compiles results + saves log + exits 0/1 |

### Detailed Step Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: CREATE BACKUP                                           │
│ Inputs:  stakpak_agent_db (MySQL)                               │
│ Process: mysqldump | gzip > backup.sql.gz                       │
│ Outputs: backup file + SHA256 checksum + latest.txt             │
│ Success: File exists, not zero bytes, checksum generated         │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: INTEGRITY CHECK                                         │
│ Checks:  SHA256 matches + gzip decompresses + valid SQL struct  │
│ Success: All checks pass                                        │
│ Failure: Corrupted backup → STOP                                │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: RESTORE TO STAGING                                      │
│ Process: DROP → CREATE stakpak_staging_db → restore backup      │
│ Success: Staging DB has ≥1 table                                │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: COMPLETENESS CHECK                                      │
│ Compares: Table list + row counts (production vs staging)       │
│ Success: All tables present, all row counts match               │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: CONSISTENCY CHECK (6 sub-checks)                        │
│ Check 1: NULL Violations       WHERE title IS NULL              │
│ Check 2: ENUM Violations       WHERE status NOT IN (...)        │
│ Check 3: Duplicate PKs         GROUP BY id HAVING COUNT > 1     │
│ Check 4: Future Timestamps     WHERE created_at > NOW()         │
│ Check 5: Bad Timestamp Order   WHERE updated_at < created_at    │
│ Check 6: Empty Titles          WHERE TRIM(title) = ''           │
│ Success: 0 violations across all 6 checks                       │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 6: STAGING APP TEST (7 API calls)                          │
│ Setup:   docker compose up -d (port 5001, staging DB)           │
│ Teardown: docker compose down (auto-cleanup on exit)            │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STEP 7: GENERATE REPORT                                         │
│ Reads:   /tmp/stakpak_validation_results.txt                    │
│ Saves:   /root/.stakpak/logs/validation-YYYYMMDD_HHMMSS.log    │
│ Exits:   0 = PASS, 1 = FAIL                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Step 6 API Tests (Staging App)

The staging backend starts on port `5001` and connects to the **restored backup data** — not production:

```
GET    /health          → 200 OK
GET    /api/tasks       → 200 OK (array with all restored tasks)
POST   /api/tasks       → 201 Created
GET    /api/tasks/:id   → 200 OK
PUT    /api/tasks/:id   → 200 OK
DELETE /api/tasks/:id   → 200 OK
GET    /api/tasks/:id   → 404 NOT FOUND (confirms deleted)
```

---

## Application Stack

| Layer | Technology | Port |
|-------|-----------|------|
| Frontend | React + Vite + Nginx | 80 |
| Backend | Node.js + Express | 5000 |
| Database | MySQL 8.0 (host) | 3306 |
| Staging Backend | Same image, staging DB | 5001 |

---

## Tech Stack

**Application:** React, Node.js, Express, MySQL, Axios, react-hot-toast

**Infrastructure:** Docker, Docker Compose, Nginx, DigitalOcean Droplet

**Agent:** Stakpak Autopilot, Claude Sonnet (Anthropic), Slack Socket Mode API

**Security:** Multi-stage Docker builds, non-root containers, dumb-init, security headers, gzip, static caching

---

## Requirements

| Tool | Version |
|------|---------|
| Stakpak CLI | v0.3.73+ |
| MySQL | 8.0+ |
| Docker | 20.10+ |
| bash | 4.0+ |
| curl | any |
| Node.js | 20 LTS |

## Prerequisites

- DigitalOcean droplet (Ubuntu 24.04)
- Docker + Docker Compose installed
- MySQL 8.0 installed on the host
- Stakpak CLI installed
- Anthropic API key
- Slack app with bot token + app token

---

## Deployment

### 1. Clone and configure

```bash
git clone https://github.com/0019-KDU/stakpak-backup-validation-agent.git
cd stakpak-backup-validation-agent
cp .env.example .env
nano .env   # Fill in DB credentials
```

### 2. Setup MySQL on host

```bash
mysql -u root -p
```

```sql
CREATE DATABASE stakpak_agent_db;
CREATE DATABASE stakpak_staging_db;
CREATE USER 'stakpak_user'@'%' IDENTIFIED BY 'YourPassword';
GRANT ALL PRIVILEGES ON stakpak_agent_db.* TO 'stakpak_user'@'%';
GRANT ALL PRIVILEGES ON stakpak_staging_db.* TO 'stakpak_user'@'%';
FLUSH PRIVILEGES;
SOURCE database/schema.sql;
EXIT;
```

### 3. Deploy the application

```bash
chmod +x deploy.sh
./deploy.sh
```

App available at `http://YOUR_DROPLET_IP`

### 4. Setup Stakpak agent

```bash
# Install Stakpak
curl -sSL https://stakpak.dev/install.sh | sh

# Login with Anthropic API key
stakpak auth login --provider anthropic --api-key YOUR_KEY

# Run setup script
chmod +x .stakpak/setup-agent.sh
bash .stakpak/setup-agent.sh
```

### 5. Configure Slack tokens

```bash
nano /root/.stakpak/.env
# Add: SLACK_BOT_TOKEN=xoxb-...
# Add: SLACK_APP_TOKEN=xapp-...
```

### 6. Start autopilot

```bash
stakpak up
stakpak autopilot status
```

---

## Usage

### Trigger validation manually

```bash
# Full validation (all 7 steps)
stakpak autopilot schedule trigger daily-backup-validation

# Quick integrity check only
stakpak autopilot schedule trigger quick-integrity-check
```

### Run scripts directly

```bash
# Full pipeline
bash /root/.stakpak/scripts/run_validation.sh

# Individual steps
bash /root/.stakpak/scripts/01_create_backup.sh
bash /root/.stakpak/scripts/02_integrity_check.sh
```

### Monitor runs

```bash
# Check autopilot status
stakpak autopilot status

# Check run history (last 5 runs)
stakpak autopilot schedule history daily-backup-validation --limit 5

# Test Slack connection
stakpak autopilot channel test

# View validation logs
ls /root/.stakpak/logs/
cat /root/.stakpak/logs/validation-YYYYMMDD_HHMMSS.log

# View latest backup info
cat /root/.stakpak/backups/latest.txt
ls -lah /root/.stakpak/backups/

# Stream autopilot service logs
stakpak autopilot logs -n 50 -c scheduler   # Scheduler activity
stakpak autopilot logs -n 50 -c server      # Gateway/approval activity

# Watch next scheduled run in real time
watch stakpak autopilot schedule history daily-backup-validation
```

### Redeploy after code changes

```bash
./deploy.sh
```

---

## Schedules

| Schedule | Cron | What Runs |
|----------|------|-----------|
| `daily-backup-validation` | `0 2 * * *` | Full 7-step pipeline |
| `quick-integrity-check` | `0 */6 * * *` | SHA256 checksum only |

---

## Integration Points

### File System Layout (on droplet)

```
/root/.stakpak/
├── backups/               ← Backup files stored here
│   ├── backup_*.sql.gz
│   ├── backup_*.sql.gz.sha256
│   └── latest.txt         ← Points to latest backup filename
├── logs/                  ← Validation reports saved here
│   └── validation-YYYYMMDD_HHMMSS.log
├── scripts/               ← 8 executable bash scripts
├── staging/               ← Staging compose file
│   └── docker-compose.yml
├── .env                   ← Database credentials + paths
├── autopilot.toml         ← Autopilot scheduling config
└── rulebooks/
    └── backup-validation.md  ← Procedure manual (SOP)
```

### Docker Stack Layout

```
Production Stack (always running):
  ├─ Frontend container  (port 80)
  ├─ Backend container   (port 5000)
  └─ MySQL               (on host, not in Docker)

Staging Stack (starts during Step 6, stops after):
  ├─ Backend container   (port 5001, same image)
  └─ MySQL staging DB    (on host, stakpak_staging_db)
```

### Slack Integration Flow

```
Stakpak Autopilot
    ↓  (App Token — Socket Mode)
Slack Bot connects to workspace
    ↓
Sends run start + final report to #stakpak-agent-database
    ↓
approval_mode = "allow_all" → no manual Allow click needed
```

---

## Slack Reports

Results are automatically posted to `#stakpak-agent-database`:

```
========================================
  BACKUP VALIDATION REPORT
  Date   : 2026-04-08 13:32:03
  Backup : backup_stakpak_agent_db_20260408_133149.sql.gz
  Source : stakpak_agent_db
  Staging: stakpak_staging_db
========================================
  [PASS] Step 1 - Create Backup
  [PASS] Step 2 - Integrity Check
  [PASS] Step 3 - Restore to Staging
  [PASS] Step 4 - Completeness Validation
  [PASS] Step 5 - Consistency Validation
  [PASS] Step 6 - Staging App Test
========================================
  OVERALL: PASS
========================================
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Run stuck in "running" | Autopilot crashed mid-run | `stakpak autopilot schedule clean` |
| No Slack reports | Missing `channel = "slack"` in schedule | Update `autopilot.toml` |
| Backup file empty | Wrong `BACKUP_DIR` path | Check `/root/.stakpak/.env` |
| Sandbox container failing | Known bug in v0.3.73 | Set `sandbox = false` in schedules |
| API test connection refused | Staging backend slow to start | Increase health check retries |
| MySQL access denied | Docker can't reach host MySQL | Grant `stakpak_user@'%'` and set `bind-address = 0.0.0.0` |
| MySQL restore fails | Disk full or staging DB permissions | See detailed fix below |

### Detailed Fixes

**Run stuck in "running"**
```bash
stakpak autopilot schedule clean
```

**Backup file missing or empty**
```bash
cat /root/.stakpak/.env | grep BACKUP_DIR
mkdir -p /root/.stakpak/backups && chmod 755 /root/.stakpak/backups
mysql -u stakpak_user -p -e "SELECT COUNT(*) FROM stakpak_agent_db.tasks;"
```

**MySQL restore fails**
```bash
# Check available disk space
df -h /root/.stakpak/backups/

# Check staging DB exists
mysql -u stakpak_user -p -e "SHOW DATABASES LIKE 'stakpak_staging%';"

# Try manual restore
zcat $(cat /root/.stakpak/backups/latest.txt) | \
  mysql -u stakpak_user -p stakpak_staging_db
```

**API test connection refused**
```bash
docker ps | grep stakpak_staging
docker logs stakpak_staging_backend
curl -v http://localhost:5001/health
```

**Slack not receiving reports**
```bash
stakpak autopilot channel test
# If fails: re-add channel with fresh tokens in autopilot.toml
```

---

## Security

- All credentials stored in `.env` — never hardcoded
- SHA256 checksums verify backup integrity before restore
- Staging database fully isolated from production
- All scripts use `set -euo pipefail` — fail fast on errors
- Docker containers run as non-root users
- Nginx security headers (CSP, X-Frame, nosniff)
- `.env` and backup files excluded from git via `.gitignore`

---

## Extending

### Add a different database
1. Copy `.stakpak/scripts/01_create_backup.sh`
2. Update the database name and credentials
3. Create a new rulebook in `.stakpak/rulebooks/`
4. Add a new schedule to `autopilot.toml`

### Support other databases
- **PostgreSQL** — replace `mysqldump` with `pg_dump`
- **MongoDB** — replace with `mongodump`
- **MariaDB** — works as-is (same CLI)

---

## System Status Summary

| Component | Purpose | Technology | Notes |
|-----------|---------|-----------|-------|
| **Autopilot** | Schedule tasks, manage approvals | Stakpak Scheduler (Systemd) | 2 active schedules |
| **Rulebook** | Document procedures & criteria | Markdown SOP | v1.0 |
| **Bash Scripts** | Execute validation steps | Shell + MySQL CLI | 8 scripts |
| **Database** | Store app data + backups | MySQL 8.0 (host) | Production + staging |
| **Docker** | Run staging app + tests | Docker Compose | Staging on port 5001 |
| **Slack** | Send reports, receive approvals | Slack Socket Mode API | Auto-approve mode |
| **File Storage** | Store backups & logs | Local filesystem | `/root/.stakpak/` |

---

## Contributing

Contributions welcome! Please:
1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a Pull Request

---

## GitHub Repository Settings

| Setting | Recommended Value |
|---------|------------------|
| Description | Automated MySQL backup validation with Stakpak Autopilot |
| Topics | `stakpak`, `backup`, `mysql`, `automation`, `devops`, `docker` |
| Visibility | Public |
| Branch Protection | Require PR reviews on main |

---

## License

MIT License — free to use, modify, and distribute.

---

## Live Demo

App: `http://157.230.221.18`

GitHub: `https://github.com/0019-KDU/stakpak-backup-validation-agent`

---

If this project helps you, please star the repo!
