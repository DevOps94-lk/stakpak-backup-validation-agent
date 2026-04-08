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
┌─────────────────────────────────────────────┐
│           STAKPAK AUTOPILOT                  │
│   Cron: 0 2 * * *  →  daily-backup-validation│
│   Cron: 0 */6 * * * → quick-integrity-check  │
└─────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│         BASH SCRIPT ORCHESTRATOR             │
│    /root/.stakpak/scripts/run_validation.sh  │
└─────────────────────────────────────────────┘
                      │
     ┌────────┬────────┬────────┬────────┬────────┬──────┐
     ▼        ▼        ▼        ▼        ▼        ▼      ▼
  Step 1   Step 2   Step 3   Step 4   Step 5   Step 6  Step 7
  Backup  Integrity Restore Complete Consistency Staging Report
  Create   Check    to DB    Check    Check    App Test
                      │
                      ▼
┌─────────────────────────────────────────────┐
│              SLACK NOTIFICATION              │
│   Channel: #stakpak-agent-database           │
│   Full PASS/FAIL report posted automatically │
└─────────────────────────────────────────────┘
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
# Check run history
stakpak autopilot schedule history daily-backup-validation

# Check autopilot status
stakpak autopilot status

# Test Slack connection
stakpak autopilot channel test

# View validation logs
ls /root/.stakpak/logs/
cat /root/.stakpak/logs/validation-YYYYMMDD_HHMMSS.log
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
