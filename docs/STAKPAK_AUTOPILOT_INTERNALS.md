# STAKPAK AUTOPILOT INTERNALS — How Everything Works Together

> **Terminal:** `root@stakpak-agent:~# cat STAKPAK_AUTOPILOT_INTERNALS.txt`

---

## 1. AUTOPILOT CORE COMPONENTS

### AUTOPILOT (Main Service) — What It Does

- Listens to `/root/.stakpak/autopilot.toml` (config file)
- Starts 4 background processes:
  - `scheduler` → Watches cron jobs, fires them on schedule
  - `server` → HTTP API (localhost:4096) for webhooks + status
  - `gateway` → Slack/Discord/Telegram integration layer
  - `warden` (optional) → Sandbox container isolation

- Runs as systemd service:

```bash
$ systemctl status stakpak-autopilot
$ ps aux | grep stakpak-autopilot
```

- Config stored in SQLite database: `~/.stakpak/autopilot/autopilot.db`

- Logs written to `~/.stakpak/autopilot/logs/`:

```
└─ scheduler.log, server.log, gateway.log, stderr.log
```

---

## 2. SCHEDULER — How Cron Works

**Flow:** Reads TOML → Parses Cron → Waits → Fires → Creates Session

**Step-by-step:**

### a) READ CONFIGURATION

- File: `/root/.stakpak/autopilot.toml`
- Parses all `[[schedules]]` sections
- Each schedule has: `name`, `cron`, `prompt`, `sandbox`, `channel`

### b) PARSE CRON EXPRESSION

Example: `"0 2 * * *"` (every day at 2 AM)

**Cron Format:** Minute Hour Day Month DayOfWeek

```
┌─────────────────────┐
│ 0 2 * * *           │
├─────────────────────┤
│ 0    = minute 0     │
│ 2    = hour 2       │
│ *    = any day      │
│ *    = any month    │
│ *    = any weekday  │
└─────────────────────┘
```

### c) WATCH FOR TRIGGER TIME

- Scheduler runs continuous loop
- Checks every 60 seconds: "Is it time to fire?"
- When time matches cron → FIRE

### d) FIRE THE SCHEDULE

**Event:** `daily-backup-validation` cron fired at `2026-04-08 02:00:00`

**Action:**

```
├─ Check if previous run is still running
│  └─ If yes → Skip (don't overlap runs)
├─ Create new Session
├─ Log: "Schedule fired" → scheduler.log
└─ Proceed to STEP 3 (Create Session)
```

### e) DATABASE TRACKING

All runs stored in SQLite: `~/.stakpak/autopilot/autopilot.db`

**Columns per run:**

```
├─ id           (Run ID)
├─ schedule_id  (Which schedule)
├─ status       (running/completed/failed)
├─ started_at   (timestamp)
├─ finished_at  (timestamp)
├─ session_id   (linked session ID)
└─ error        (if failed)
```

---

## 3. SESSION CREATION — Spinning Up the Agent

**What is a Session?**

- A temporary agent instance that runs the task
- Has unique `session_id` (UUID)
- Gets assigned specific tools + memory + context

**Flow:**

### a) INITIALIZE SESSION

- Generate `session_id`: `1ccb75fe-a042-4311-a3b1-33f7dbb853f0`
- Create session directory: `~/.stakpak/sessions/{session_id}/`
- Load profile from `config.toml` (e.g., `"default"`)
- Determine which LLM to use

### b) SET PERMISSIONS (Warden Guardrails)

Based on profile + `approval_mode`:

**Example permissions for backup-validation:**

```
├─ ✅ run_command        (allowed → bash scripts)
├─ ✅ stakpak__view      (allowed → read files)
├─ ✅ stakpak__create    (allowed → create backups)
├─ ✅ mysql CLI access   (allowed → database)
├─ ✅ docker access      (allowed → containers)
├─ ⚠️ delete_data        (forbidden → dangerous)
└─ ⚠️ aws_delete_bucket  (forbidden → dangerous)
```

### c) LOAD CONTEXT INTO SESSION

**What gets passed to the agent:**

```
├─ Prompt (from [[schedules]])
│  "Run the full database backup validation pipeline..."
│
├─ System Instructions
│  "You are Stakpak. Analyze problems, propose solutions..."
│
├─ Available Skills (Rulebooks)
│  ├─ backup-validation.md (local)
│  ├─ 12-factor-app.md (remote)
│  └─ ... (other paks)
│
├─ File System Access
│  /root/.stakpak/
│  /root/.stakpak/scripts/
│  /root/.stakpak/rulebooks/
│
├─ Environment Variables
│  DB_USER, DB_PASSWORD, DB_NAME, etc.
│
└─ Tools to use
   run_command, view, create, str_replace, etc.
```

### d) APPROVAL MODE SETUP

From `[gateway]` in `autopilot.toml`:

```toml
approval_mode = "allow_all"
```

```
└─ All tool calls auto-approved
└─ No "Allow" button in Slack needed
└─ Agent executes immediately
```

### e) RECORD SESSION START

Logged to: `~/.stakpak/autopilot/autopilot.db`

```
└─ session table: id, status='running', started_at
```

---

## 4. AGENT EXECUTION — What the Agent Actually Does

**The agent (Claude) receives:**

**INPUT:**

```
┌─────────────────────────────────────────────────────────────┐
│ Prompt: "Run the full database backup validation pipeline.."│
│ Tools: [run_command, view, create, str_replace, ...]        │
│ Memory: Previous knowledge about backups                    │
│ Context: Rulebook, skills, available functions              │
└─────────────────────────────────────────────────────────────┘
```

**AGENT THINKS:**

1. "I need to run a backup validation"
2. "There's a rulebook at `/root/.stakpak/rulebooks/backup-validation.md`"
3. "I should read it first"
4. "Then execute the `run_validation.sh` script"
5. "Check logs and report results"

**AGENT ACTS:**

```
├─ Call 1: stakpak__view
│  └─ Read /root/.stakpak/rulebooks/backup-validation.md
│
├─ Call 2: stakpak__run_command
│  └─ bash /root/.stakpak/scripts/run_validation.sh
│
├─ Call 3: stakpak__view (reads output/logs)
│  └─ Read /root/.stakpak/logs/validation-*.log
│
└─ Call 4: Report generation
   └─ Send results to Slack channel
```

**EXECUTION FLOW:**

```
┌─────────────────────────────────┐
│ Agent generates tool calls      │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Check approval_mode             │
│ "allow_all" → auto-approve      │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Check Warden Guardrails         │
│ Is this tool allowed?           │
│ Is this a safe operation?       │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Execute Tool Call               │
│ run_command, view, etc.         │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Return Result to Agent          │
│ (stdout, file contents,         │
│  error messages, etc.)          │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Agent Receives Result           │
│ Continues reasoning             │
│ Decides next step               │
└──────────────┬──────────────────┘
               ▼
┌─────────────────────────────────┐
│ Repeat until task done          │
│ or max_steps reached            │
└─────────────────────────────────┘
```

---

## 5. WARDEN — Sandbox Isolation (Optional)

**What is Warden?**

- Security layer that isolates agent execution
- Can optionally run agent inside Docker container
- Provides "Guardrails" — restrictions on what agent can do

**Configuration:**

In `~/.stakpak/autopilot.toml`:

```toml
[server]
sandbox_mode = "ephemeral"
# OR
sandbox_mode = "persistent"
```

- `ephemeral` = New container per session (safest, slower)
- `persistent` = One container per day (faster, less safe)
- `disabled` = No sandbox (fastest, requires trust)

In `[[schedules]]`:

```toml
sandbox = true   # → Use container
sandbox = false  # → Run on host
```

**Warden Guardrails — What Gets Blocked:**

```
├─ Filesystem Access
│  ├─ ✅ Read /root/.stakpak/ (allowed)
│  ├─ ✅ Write to /tmp/ (allowed)
│  ├─ ❌ Read /etc/passwd (denied)
│  └─ ❌ Write to /root/ directly (denied)
│
├─ Network Access
│  ├─ ✅ Localhost (127.0.0.1) allowed
│  ├─ ✅ Database connections allowed
│  └─ ❌ Random internet access blocked
│
├─ Process Control
│  ├─ ✅ Run bash scripts (allowed)
│  ├─ ✅ Docker commands (allowed)
│  └─ ❌ Kill system processes (denied)
│
└─ Secret Management
   ├─ ✅ Read secrets from ~/.stakpak/session/secrets.json
   ├─ ✅ Pass to tools via environment
   └─ ❌ Log secrets to stdout
```

**Warden Container Setup:**

When `sandbox = true`:

**1. Warden spawns ephemeral Docker container:**

```bash
docker run --rm \
  --name stakpak-sandbox-{session_id} \
  --network isolated \
  --memory 512m \
  --cpus 1 \
  -v /root/.stakpak:/agent/.stakpak:ro \
  -v /tmp:/tmp:rw \
  ghcr.io/stakpak/agent:v0.3.73
```

**2. Agent runs inside container with:**

```
├─ Limited CPU (1 core)
├─ Limited RAM (512MB)
├─ No internet access
├─ /root/.stakpak mounted as read-only
├─ /tmp mounted as read-write
└─ No sudo access
```

**3. Container is destroyed when task ends**

```
└─ No persistent state (clean slate next time)
```

---

## 6. APPROVAL GATEWAY — Slack Integration & Tool Approval

**What is Gateway?**

- HTTP server (`localhost:4096`) that bridges Slack ↔ Autopilot
- Handles tool approval (Allow/Reject buttons)
- Manages approval timeouts

**Configuration:**

In `~/.stakpak/autopilot.toml`:

```toml
[gateway]
approval_mode = "allow_all"     # ← Auto-approve all
# OR
approval_mode = "pause_on_tool" # ← Ask for each tool

delivery_context_ttl_hours = 4  # ← Approval expires
```

**Flow (`approval_mode = "pause_on_tool"`):**

```
1. Agent generates tool call: run_command("bash backup.sh")
                       ▼
2. Gateway intercepts it (before execution)
                       ▼
3. Gateway posts to Slack:
   "Agent wants to run: bash backup.sh
    [Allow] [Reject]"
                       ▼
4. User clicks [Allow] in Slack thread
                       ▼
5. Slack → Gateway API call: approve_tool(call_id=123)
                       ▼
6. Gateway unblocks agent: "Tool approved, continue"
                       ▼
7. Agent executes: bash backup.sh
                       ▼
8. Result returned to agent
                       ▼
9. Gateway posts to Slack: "Backup completed successfully"
```

**OUR SETUP (`approval_mode = "allow_all"`):**

```
Step 1: Agent generates tool call
                 ▼
        (gateway auto-approves without asking)
                 ▼
        Step 2: Execute immediately
                 ▼
        Step 3: Result returned
```

- → No "Allow" button needed
- → No 4-hour timeout issues
- → Fully autonomous

---

## 7. RULEBOOK — How It Guides the Agent

**File:** `/root/.stakpak/rulebooks/backup-validation.md`

**What is a Rulebook?**

- Standard Operating Procedure (SOP) document
- Written in Markdown with YAML metadata
- Agent reads it to understand the procedure
- Defines success/failure criteria

**Structure:**

```
┌──────────────────────────────────────┐
│ METADATA (YAML front matter)         │
├──────────────────────────────────────┤
│ uri: stakpak://stakpak-agent/...     │
│ description: Full backup validation  │
│ version: 1.0                         │
│ tags: [backup, validation, mysql]    │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ PROCEDURE (Markdown content)         │
├──────────────────────────────────────┤
│ ## Step 1 — Create Backup            │
│ Run: bash /root/.stakpak/scripts/... │
│ Expected: File created, size > 0     │
│ On Fail: Report FAIL and stop        │
│                                      │
│ ## Step 2 — Integrity Check          │
│ Run: bash /root/.stakpak/scripts/... │
│ Expected: Checksum matches           │
│ On Fail: FAIL: INTEGRITY             │
│                                      │
│ ... (steps 3-7)                      │
└──────────────────────────────────────┘
```

**How Agent Uses It:**

1. Agent reads prompt: `"Run the full database backup validation pipeline"`

2. Agent thinks: `"I need a rulebook for this task"`

3. Agent searches available skills/rulebooks:

```bash
$ find /root/.stakpak/rulebooks -name "*backup*"
/root/.stakpak/rulebooks/backup-validation.md
```

4. Agent loads rulebook:

```bash
$ stakpak load_skill "backup-validation.md"
```

Reads entire procedure (178 lines). Understands: 7 steps, order, success criteria.

5. Agent follows rulebook step-by-step:

```
For each step:
├─ Read expected inputs
├─ Execute the command
├─ Check outputs against criteria
└─ If fails → stop + report FAIL
```

6. Rulebook acts as the "instruction manual":
   - → Agent doesn't have to guess
   - → Agent knows exact steps to run
   - → Agent knows success/failure criteria

**Rulebook vs Scripts:**

| RULEBOOK (Markdown) | SCRIPTS (Bash) |
|---------------------|----------------|
| Human-readable procedure | Actual execution code |
| Documents the "why" | Executes the "what" |
| Guides agent decisions | Does the work |
| Defines success criteria | Reports results |
| Can reference multiple scripts | Focused on one task |

---

## 8. SLACK INTEGRATION — Reports & Communication

**Configuration:**

```toml
[channels.slack]
app_token = "xapp-..."   # ← Socket Mode token
bot_token = "xoxb-..."   # ← Bot OAuth token
profile = "default"

[notifications]
channel = "slack"
chat_id = "stakpak-agent-database"  # ← Target channel
gateway_url = "http://127.0.0.1:4096"
```

**What Gets Sent to Slack:**

### 1. SCHEDULE FIRED

```
┌────────────────────────────────────────┐
│ Stakpak Autopilot                      │
│ Schedule: daily-backup-validation      │
│ Fired at: 2026-04-08 02:00:00 UTC      │
│ Session: 1ccb75fe-a042-4311-a3b1...    │
│                                        │
│ Starting: Full database backup         │
│ validation pipeline for stakpak_agent_db
│                                        │
│ [View Details]                         │
└────────────────────────────────────────┘
```

### 2. TOOL APPROVAL REQUESTS (if `approval_mode != "allow_all"`)

```
┌────────────────────────────────────────┐
│ :wrench: Tool approval required        │
│                                        │
│ run_command                            │
│ bash /root/.stakpak/scripts/...        │
│                                        │
│ [Allow] [Reject]                       │
│                                        │
│ Context TTL: 4 hours                   │
└────────────────────────────────────────┘
```

### 3. VALIDATION PROGRESS (optional)

```
┌────────────────────────────────────────┐
│ ✅ Step 1: Create Backup               │
│ ⏳ Step 2: Integrity Check (in progress)│
│ ⏸️  Step 3: Restore to Staging (pending)│
└────────────────────────────────────────┘
```

### 4. FINAL REPORT

```
┌────────────────────────────────────────┐
│ ✅ BACKUP VALIDATION REPORT            │
│ Date: 2026-04-08 02:01:42 UTC          │
│ Backup: backup_stakpak_agent_db_...    │
│                                        │
│ ✅ [PASS] Step 1 - Create Backup       │
│ ✅ [PASS] Step 2 - Integrity Check     │
│ ✅ [PASS] Step 3 - Restore to Staging  │
│ ✅ [PASS] Step 4 - Completeness        │
│ ✅ [PASS] Step 5 - Consistency         │
│ ✅ [PASS] Step 6 - Staging App Test    │
│                                        │
│ 🎉 OVERALL: PASS ✅                    │
│                                        │
│ Log: /root/.stakpak/logs/validation... │
└────────────────────────────────────────┘
```

**How It Works Technically:**

```
┌──────────────────────────────────────┐
│ Agent completes task                 │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Agent formats report message         │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Gateway HTTP API receives report     │
│ POST http://localhost:4096/v1/...    │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Gateway connects to Slack via token  │
│ (app_token + bot_token auth)         │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Slack API call:                      │
│ chat.postMessage(                    │
│   channel="stakpak-agent-database",  │
│   text="BACKUP VALIDATION REPORT...",│
│   blocks=[...])                      │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Message appears in Slack channel     │
│ User sees full validation report     │
└──────────────────────────────────────┘
```

---

## 9. COMPLETE WORKFLOW — Start to Finish

**Timeline: Daily Backup Validation (`0 2 * * *`)**

```
2026-04-08 01:59:59 UTC
├─ Scheduler sleeping (checking every 60 seconds)

2026-04-08 02:00:00 UTC
├─ ⏰ CRON FIRES: "0 2 * * *" matches
├─ Scheduler: "Schedule fired: daily-backup-validation"
├─ Check previous run? → No (completed yesterday)
├─ Create Session: id=1ccb75fe-a042-4311-a3b1-33f7dbb853f0
├─ Load Rulebook: backup-validation.md
├─ Spawn Agent: Claude + tools
├─ Pass Prompt: "Run the full database backup validation..."
└─ Post to Slack: "Starting validation..."

2026-04-08 02:00:05 UTC
├─ Agent thinks: "I need a rulebook for backup validation"
├─ Agent calls: stakpak__view("/root/.stakpak/rulebooks/backup-validation.md")
├─ Agent reads entire procedure (178 lines)
├─ Agent: "Now I understand the 7-step process"
└─ Agent decides: "Run run_validation.sh"

2026-04-08 02:00:10 UTC
├─ Agent calls: stakpak__run_command("bash /root/.stakpak/scripts/run_validation.sh")
├─ Gateway checks: approval_mode = "allow_all" ✓
├─ Warden checks: Is bash allowed? Yes ✓
├─ Execute: bash script starts
├─ Agent waits for output
└─ Log: "Tool call: run_command [allowed] [executing]"

2026-04-08 02:00:15 → 02:01:45 (1m 30s)
├─ Script runs 7 steps sequentially:
│  ├─ Step 1: mysqldump → gzip → sha256
│  ├─ Step 2: Verify checksum + gzip integrity
│  ├─ Step 3: Drop staging DB → create fresh → restore
│  ├─ Step 4: Compare table lists + row counts
│  ├─ Step 5: Check NULL, ENUM, PKs, timestamps
│  ├─ Step 6: Start staging backend → run API tests → stop
│  └─ Step 7: Generate report → save to log file
├─ All outputs captured to stdout/stderr
└─ Script exits with code 0 (success)

2026-04-08 02:01:50 UTC
├─ Agent receives full script output
├─ Agent reads log file: cat /root/.stakpak/logs/validation-*.log
├─ Agent parses results:
│  [PASS] Step 1
│  [PASS] Step 2
│  [PASS] Step 3
│  [PASS] Step 4
│  [PASS] Step 5
│  [PASS] Step 6
│  OVERALL: PASS
├─ Agent formats report message
├─ Agent calls: gateway.post_to_slack(report)
└─ Log: "Sending report to Slack..."

2026-04-08 02:01:55 UTC
├─ Gateway receives report
├─ Gateway auth to Slack (app_token + bot_token)
├─ Gateway calls Slack API: chat.postMessage
├─ Slack receives message
├─ Message posted to channel: stakpak-agent-database
├─ Notification: "Stakpak - Daily Backup Validation completed"
└─ Users see full report in channel

2026-04-08 02:02:00 UTC
├─ Agent: "Task complete"
├─ Session: status = "completed"
├─ Database: Run #14 marked as completed
├─ Logs written: ~/.stakpak/logs/validation-20260408_020142.log
├─ Backups stored: /root/.stakpak/backups/backup_*.sql.gz
└─ Schedule ready for next day

2026-04-08 02:02:05 UTC
├─ Session cleaned up
├─ Agent memory cleared
├─ Warden container destroyed (if sandbox=true)
├─ Gateway removes approval context
└─ Scheduler resumes watching for next schedule
```

---

## 10. CONTRIBUTION FLOW — What Each Component Does

### AUTOPILOT

```
├─ Responsibility: Scheduling + orchestration
├─ Contributes: Fires at right time, creates session
├─ Tools: Cron parsing, database, systemd
└─ Config: autopilot.toml
```

### RULEBOOK

```
├─ Responsibility: Documents procedure + success criteria
├─ Contributes: Guides agent decisions, defines steps
├─ Format: Markdown + YAML
└─ Usage: Agent reads to understand task
```

### AGENT (Claude)

```
├─ Responsibility: Reasoning + decision making
├─ Contributes: Reads rulebook, executes scripts, interprets results
├─ Tools: view, run_command, create, etc.
└─ Output: Final report
```

### WARDEN (Sandbox)

```
├─ Responsibility: Security + isolation
├─ Contributes: Restricts dangerous operations, isolates execution
├─ Tech: Docker containers, guardrails
└─ Config: sandbox=true/false, approval_mode
```

### GATEWAY (Slack Bridge)

```
├─ Responsibility: Communication + approval flow
├─ Contributes: Posts updates to Slack, handles approvals
├─ Protocol: HTTP + Slack API
└─ Config: channels.slack, approval_mode
```

### SCRIPTS (Bash)

```
├─ Responsibility: Actual execution
├─ Contributes: Runs backups, validates, tests
├─ Tech: mysqldump, docker, bash
└─ Output: Success/failure status
```

### SCHEDULER (Cron)

```
├─ Responsibility: Timing
├─ Contributes: Fires at scheduled times
├─ Config: [[schedules]] cron expressions
└─ Tech: Cron parsing library
```

---

## 11. DATA FLOW — How Information Moves

### Config Files → Autopilot

```
┌──────────────────────────────────────┐
│ /root/.stakpak/autopilot.toml        │
│ (schedules, channels, gateway)       │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Autopilot reads config               │
│ Parses TOML → Registers schedules    │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ ~/.stakpak/autopilot/autopilot.db    │
│ (Stores parsed config + run history) │
└──────────────────────────────────────┘
```

### Environment → Scripts

```
┌──────────────────────────────────────┐
│ /root/.stakpak/.env                  │
│ (DB_USER, DB_PASSWORD, etc.)         │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Scripts source .env                  │
│ source /root/.stakpak/.env           │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Scripts access variables             │
│ mysql -u $DB_USER -p$DB_PASSWORD ... │
└──────────────────────────────────────┘
```

### Agent → Tools → Results

```
┌──────────────────────────────────────┐
│ Agent: "Run bash backup.sh"          │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Tool call: run_command("bash...")    │
│ (with approval_mode = "allow_all")   │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Bash script executes                 │
│ Captures stdout + stderr             │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Result returned to agent:            │
│ {status: 0, output: "...", ...}      │
└──────────┬───────────────────────────┘
           ▼
┌──────────────────────────────────────┐
│ Agent receives result                │
│ Continues reasoning                  │
└──────────────────────────────────────┘
```

---

## 12. KEY INSIGHTS — How It All Connects

- ✓ **AUTOPILOT** = Timing (when to run)
- ✓ **RULEBOOK** = Knowledge (what to do)
- ✓ **AGENT** = Intelligence (how to do it)
- ✓ **WARDEN** = Safety (security guardrails)
- ✓ **GATEWAY** = Communication (Slack updates)
- ✓ **SCRIPTS** = Execution (actual work)

**Why This Architecture?**

```
├─ Decoupled: Each part can be updated independently
├─ Scalable: Can have multiple schedules/agents
├─ Safe: Warden prevents dangerous operations
├─ Observable: All actions logged + reported
├─ Maintainable: Rulebook documents procedures
└─ Extensible: Easy to add new schedules/databases
```

**Approval Flow — Why `approval_mode = "allow_all"`?**

**Problem with `approval_mode = "pause_on_tool"`:**

```
├─ Agent calls tool → Gateway pauses
├─ Posts "Allow?" to Slack
├─ User clicks Allow (but 4-hour TTL expires)
├─ Approval lost → Run stuck forever
├─ Scheduler blocked → Next run skipped
```

**Solution with `approval_mode = "allow_all"`:**

```
├─ Agent calls tool → Gateway auto-approves
├─ No Slack interaction needed
├─ Tool executes immediately
├─ Run completes successfully
├─ Scheduler unblocked
├─ Next schedule fires on time
```

**BUT with Warden Guardrails:**

```
├─ Even with "allow_all", dangerous operations blocked
├─ Example: Agent tries to delete /etc/passwd
├─ Warden rejects: "Operation not allowed"
├─ Agent receives error, can't harm system
└─ Safe even with fully automatic approvals
```

---

## YOUR SYSTEM — LIVE INTERNALS (What's Running NOW)

**Service: `stakpak-autopilot` (PID 3412886)**

```
├─ Status: ✅ ACTIVE
├─ Memory: 587 MB
├─ CPU: 0.2%
├─ Uptime: 4+ hours
```

**Active Schedules:**

```
├─ daily-backup-validation (0 2 * * *)      → Next: 2026-04-09 02:00
├─ quick-integrity-check (0 */6 * * *)      → Next: 2026-04-09 00:00
```

**Slack Channel:**

```
├─ Channel: slack (configured)
├─ Target: stakpak-agent-database
├─ Status: enabled
```

**Gateway:**

```
├─ Approval Mode: allow_all (auto-approve)
├─ Listen: 127.0.0.1:4096
├─ TTL: 4 hours
```

**Sandbox:**

```
├─ Mode: ephemeral (new container per session)
├─ Status: disabled for schedules (sandbox = false)
```

**Databases:**

```
├─ autopilot.db (52 KB) → Stores run history
├─ gateway.db (28 KB) → Stores approval context
```

**Recent Runs:**

```
├─ Run #14: daily-backup-validation → PASSED ✅ (2026-04-08 13:30:49)
├─ Run #13: daily-backup-validation → FAILED ❌ (2026-04-08 13:21:09)
└─ Run #12: daily-backup-validation → FAILED ❌ (2026-04-08 13:10:38)
```

**Log Files:**

```
├─ stdout.log (latest)
├─ scheduler.log
├─ gateway.log
└─ server.log
```

**Backup Files:**

```
├─ /root/.stakpak/backups/ → Stored backups
├─ latest.txt → Points to current backup
└─ *.sql.gz + *.sha256 → Backup + checksum files
```

---

## COMPLETE WORKFLOW — How Each Component Contributes (Simplified View)

| TIME | EVENT | COMPONENT | WHAT IT DOES |
|------|-------|-----------|--------------|
| 00:00 | Config loaded | **AUTOPILOT** | Reads `/root/.stakpak/autopilot.toml` |
| | └─ Parses 2 schedules | ↓ | Registers in SQLite database |
| | └─ Sets up Slack channel | **SCHEDULER** | Starts listening for cron events |
| | └─ Waits for first trigger | | |
| 02:00 | CRON MATCHES: `"0 2 * * *"` | **SCHEDULER** | Checks: "Is it 2 AM? YES → FIRE" |
| | └─ Schedule fired! | ↓ | Creates Session ID (UUID) |
| | └─ Session created | **SESSION MANAGER** | Allocates resources + memory |
| | └─ Load rulebook | | Links rulebook + tools + context |
| 02:00 | Agent initialized | **AGENT** | Receives prompt: "Run backup validation" |
| | └─ Reads rulebook | ↓ | Loads `/root/.stakpak/rulebooks/backup-validation.md` |
| | └─ Understands 7 steps | **RULEBOOK** | "I need to follow these 7 steps..." |
| | └─ Plans execution | **AGENT** | "I'll run run_validation.sh" |
| 02:00 | Tool call: `run_command` | **AGENT** | Calls: `bash /root/.stakpak/scripts/run_validation.sh` |
| | └─ Check approval | ↓ | Looks up `approval_mode = "allow_all"` |
| | └─ Auto-approved | **GATEWAY** | Approves automatically (no Slack delay) |
| | └─ Check Warden rules | **WARDEN** | Checks: Is bash allowed? YES ✓ |
| | └─ Execute! | **SCRIPT EXECUTOR** | Runs the 7 steps |
| 02:00–02:01 | Step 1: mysqldump | **SCRIPT 01** | Creates backup file |
| | └─ gzip + sha256 | ↓ | `/root/.stakpak/backups/backup_*.sql.gz` |
| 02:01 | Step 2: Integrity check | **SCRIPT 02** | Verifies SHA256 checksum |
| | └─ Verify not corrupted | ↓ | Tests gzip decompression |
| | └─ Check SQL structure | ↓ | Validates SQL content |
| 02:01 | Step 3: Restore to staging | **SCRIPT 03** | Drops old staging DB |
| | └─ Create fresh staging | ↓ | Creates new `stakpak_staging_db` |
| | └─ Restore backup | **MYSQL** | Restores backup into staging |
| 02:01 | Step 4: Completeness check | **SCRIPT 04** | Queries `information_schema` |
| | └─ Compare table lists | ↓ | source vs staging match? |
| | └─ Compare row counts | **MYSQL** | Each table has same row count? |
| 02:01 | Step 5: Consistency check | **SCRIPT 05** | Checks for NULL violations |
| | └─ Validate ENUMs | ↓ | Validates ENUM field values |
| | └─ Check PKs + timestamps | **MYSQL** | Ensures data integrity |
| 02:01 | Step 6: Staging app test | **SCRIPT 06** | Starts Docker backend container |
| | └─ Wait for healthy | **DOCKER** | Waits for `GET /health → 200 OK` |
| | └─ Run CRUD tests | ↓ | `POST /api/tasks` (create) |
| | └─ Verify API works | ↓ | `GET /api/tasks` (read) |
| | └─ Clean up container | **DOCKER** | Stops and removes staging container |
| 02:02 | Step 7: Generate report | **SCRIPT 07** | Reads all step results |
| | └─ Format output | ↓ | Combines into formatted report |
| | └─ Save to log file | **FILESYSTEM** | Writes to `/root/.stakpak/logs/validation-*.log` |
| 02:02 | Agent receives results | **AGENT** | Reads full log output |
| | └─ Parses success/failure | ↓ | Interprets: All steps PASSED ✓ |
| | └─ Formats report | ↓ | Prepares for Slack |
| 02:02 | Send to Slack | **AGENT** | Calls: `gateway.post_to_slack(report)` |
| | └─ Check authorization | **GATEWAY** | Authenticates with `app_token + bot_token` |
| | └─ Format message | ↓ | Uses Slack message blocks API |
| | └─ Post to channel | **SLACK** | Posts to `stakpak-agent-database` |
| 02:03 | Message in Slack | **SLACK** | ✅ BACKUP VALIDATION REPORT |
| | └─ Shows full report | ↓ | [PASS] Step 1 |
| | └─ User reads results | ↓ | [PASS] Step 2 |
| | └─ Everyone sees status | **USER** | ... (all 6 steps) → OVERALL: PASS ✅ |
| 02:03 | Cleanup | **SESSION MANAGER** | Clears agent memory |
| | └─ Session ends | | Marks session as "completed" |
| | └─ Warden cleans up | **WARDEN** | Destroys containers (if used) |
| | └─ Database records updated | **DB** | Stores run record in `autopilot.db` |
| | └─ Ready for next run | **SCHEDULER** | Goes back to sleep, waits for next |
| 02:03+ | Scheduler idle | **SCHEDULER** | Waits 6 hours for next schedule |
| | └─ Continuous monitoring | ↓ | (quick-integrity-check at 08:00) |
| | └─ Next daily at 02:00 | ↓ | Next full validation tomorrow |

---

## COMPONENT RESPONSIBILITIES & CONTRIBUTIONS

### 1. AUTOPILOT (Service)

**Responsibility:** Orchestration + Scheduling

**What it does:**

```
├─ Starts 4 child processes (scheduler, server, gateway, warden)
├─ Reads config file (autopilot.toml)
├─ Maintains SQLite database of runs (autopilot.db)
├─ Keeps running 24/7
└─ Logs all activity to ~/.stakpak/autopilot/logs/
```

> **Contribution: TIMING & LIFECYCLE**
> *"I run the task at the right time and manage its life cycle"*

---

### 2. SCHEDULER (Autopilot component)

**Responsibility:** Cron-based timing

**What it does:**

```
├─ Parses TOML [[schedules]] sections
├─ Runs event loop: check every 60s if any schedule should fire
├─ When cron matches → creates Session
├─ Logs "schedule fired" events
└─ Prevents overlapping runs
```

> **Contribution: TIMING ACCURACY**
> *"I know when to start the task based on cron expressions"*

---

### 3. RULEBOOK (`backup-validation.md`)

**Responsibility:** Documentation + Success Criteria

**What it does:**

```
├─ Documents 7-step procedure
├─ Defines expected inputs/outputs for each step
├─ Specifies success/failure criteria
├─ Acts as manual for agent to follow
└─ Stored as Markdown (human + agent readable)
```

> **Contribution: KNOWLEDGE BASE**
> *"I tell the agent exactly what to do and how to verify it works"*

---

### 4. AGENT (Claude LLM)

**Responsibility:** Reasoning + Decision Making

**What it does:**

```
├─ Receives prompt: "Run full backup validation"
├─ Reads rulebook to understand procedure
├─ Decides which tools to use (run_command, view, etc.)
├─ Calls tools sequentially
├─ Interprets results + decides next step
├─ Generates final report
└─ Explains reasoning throughout
```

> **Contribution: INTELLIGENCE**
> *"I understand the task, read the rulebook, execute tools, and report"*

---

### 5. WARDEN (Sandbox + Guardrails)

**Responsibility:** Security + Isolation

**What it does:**

```
├─ Optionally spins up Docker container
├─ Sets resource limits (CPU, RAM, disk)
├─ Restricts filesystem access
├─ Blocks dangerous operations
├─ Isolates from host system
└─ Cleans up container after task
```

> **Contribution: SAFETY**
> *"I prevent the agent from doing dangerous things"*

**Current Status:** `sandbox = false` (disabled)

```
└─ Runs directly on host (approved because approval_mode = "allow_all")
```

---

### 6. GATEWAY (Slack Bridge + Approval Handler)

**Responsibility:** Communication + Approval Flow

**What it does:**

```
├─ Connects to Slack via bot_token + app_token
├─ Handles approval requests (if approval_mode != "allow_all")
├─ Posts updates to Slack channel
├─ Manages approval TTL (expires after 4 hours)
├─ Receives user clicks (Allow/Reject)
└─ Sends final report to channel
```

> **Contribution: COMMUNICATION**
> *"I keep humans in the loop and report results to Slack"*

**Current Mode:** `approval_mode = "allow_all"`

```
└─ Auto-approves all tools → No Slack delays
```

---

### 7. BASH SCRIPTS (Execution)

**Responsibility:** Actual work

**What they do:**

```
├─ 01_create_backup.sh     → mysqldump, gzip, sha256
├─ 02_integrity_check.sh   → verify backup uncorrupted
├─ 03_restore_backup.sh    → restore to staging DB
├─ 04_completeness_check.sh → compare source vs staging
├─ 05_consistency_check.sh → check data integrity
├─ 06_staging_app_test.sh  → test app with backup data
├─ 07_report.sh            → generate final report
└─ run_validation.sh       → orchestrate all 7 steps
```

> **Contribution: EXECUTION**
> *"I do the actual work: backup, validate, test, report"*

---

## FULL DEPENDENCY CHAIN (What Needs What)

**AGENT needs:**

```
├─ Rulebook (to understand procedure)
├─ Tools (to execute commands)
├─ Environment (DB credentials)
└─ Access to scripts (/root/.stakpak/scripts/)
```

**SCRIPTS need:**

```
├─ MySQL (for backup/restore)
├─ Docker (for staging app test)
├─ Filesystem access (to store backups)
└─ Environment variables (from .env)
```

**GATEWAY needs:**

```
├─ Slack tokens (app_token, bot_token)
├─ Channel configured (stakpak-agent-database)
└─ HTTP server running (localhost:4096)
```

**WARDEN needs:**

```
├─ Docker installed (for sandbox containers)
├─ Guardrail rules configured
└─ Resource limits set
```

**SCHEDULER needs:**

```
├─ Cron library (to parse expressions)
├─ SQLite database (to track runs)
└─ Session manager (to create sessions)
```

**AUTOPILOT needs:**

```
├─ Config file (autopilot.toml)
├─ All above components working
└─ Systemd (to run as service)
```

---

## SUMMARY: How It All Connects

**Timeline:**

```
Scheduler ← watches time ← fires at "0 2 * * *" (2 AM)
   ↓
Session Manager ← creates Session with unique ID
   ↓
Agent (Claude) ← receives rulebook + tools + prompt
   ↓
Agent reads Rulebook ← "Here are 7 steps to follow"
   ↓
Agent calls Tools (run_command, view, etc.)
   ↓
Gateway ← checks approval_mode = "allow_all"
   ↓
Gateway checks Warden ← "Is this operation allowed?"
   ↓
Scripts ← execute backup, validation, testing
   ↓
Results ← returned to Agent
   ↓
Agent ← interprets results, generates report
   ↓
Gateway ← sends report to Slack
   ↓
Slack ← users see full validation report
   ↓
Session ← marked as completed
   ↓
Scheduler ← goes back to sleep, waits for next trigger
```

**WHAT EACH COMPONENT CONTRIBUTES:**

| Component | Role |
|-----------|------|
| ✓ **AUTOPILOT** | Infrastructure (runs continuously) |
| ✓ **SCHEDULER** | Timing (when to run) |
| ✓ **AGENT** | Intelligence (what/how to do it) |
| ✓ **RULEBOOK** | Knowledge (procedure manual) |
| ✓ **WARDEN** | Safety (security/isolation) |
| ✓ **GATEWAY** | Communication (Slack updates) |
| ✓ **SCRIPTS** | Execution (actual work) |
| ✓ **MYSQL** | Data (backup/restore) |
| ✓ **DOCKER** | Staging (test environment) |

> **All working together = Fully autonomous backup validation pipeline ✅**

---

> `root@stakpak-agent:~#`
