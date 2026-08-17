---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, sets up a Python virtual environment, configures a PostgreSQL database with a dedicated user and database, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd service unit, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance deployment.

---

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI, backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn` (entry point: `app.main:app`)
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Run as user: `root`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Database owner/user: `fastapi`
  - Password: `fastapi_password` (hardcoded — see Credentials section)
  - Host: `localhost`
  - PostgreSQL service managed by systemd: `postgresql`

---

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
└── metadata.rb
```

**Recipes**:
```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: None

**Templates**: None — configuration files are written inline using Chef `file` resources

**Attributes**: None — no `attributes/default.rb` file present; all values are hardcoded in the recipe

**Files**: None — no `cookbook_file` or `remote_file` resources used

---

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

   - **Step 1 — Install system packages**: Installs the following packages in a single `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Resources: `package` (1)

   - **Step 2 — Create application directory**: Creates `/opt/fastapi-tutorial` with owner `root`, group `root`, mode `0755`, recursive.
   - Resources: `directory` (1)

   - **Step 3 — Clone Git repository**: Syncs `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial`. Uses `action :sync` (clone + pull if already exists).
   - Resources: `git` (1)

   - **Step 4 — Create Python virtual environment**: Runs `python3 -m venv /opt/fastapi-tutorial/venv`. Uses `creates '/opt/fastapi-tutorial/venv'` guard — only runs if the venv directory does not already exist (idempotent).
   - Resources: `execute` (1)

   - **Step 5 — Install Python dependencies**: Runs `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt` with `cwd /opt/fastapi-tutorial`. Runs unconditionally on every Chef run (`action :run`).
   - Resources: `execute` (1)

   - **Step 6 — Enable and start PostgreSQL**: Enables and starts the `postgresql` systemd service.
   - Resources: `service` (1)

   - **Step 7 — Create PostgreSQL database user and database**: Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`). Each command uses `|| true` to suppress errors if the object already exists (idempotent workaround):
     1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
     2. `CREATE DATABASE fastapi_db OWNER fastapi;`
     3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
   - Resources: `execute` (1)

   - **Step 8 — Write `.env` file**: Creates `/opt/fastapi-tutorial/.env` with inline content, mode `0644`, owner `root`, group `root`. Content:
     ```
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - Resources: `file` (1)

   - **Step 9 — Write systemd service unit**: Creates `/etc/systemd/system/fastapi-tutorial.service` with inline content, mode `0644`, owner `root`, group `root`. Unit definition:
     - `Description`: FastAPI Tutorial Service
     - `After`: `network.target postgresql.service`
     - `Type`: simple
     - `User`: root
     - `WorkingDirectory`: `/opt/fastapi-tutorial`
     - `Environment`: `PATH=/opt/fastapi-tutorial/venv/bin`
     - `ExecStart`: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
     - `Restart`: always
     - `WantedBy`: multi-user.target
     - **Notifies**: triggers `execute[systemd_reload]` immediately when this file changes.
   - Resources: `file` (1)

   - **Step 10 — Reload systemd daemon**: Runs `systemctl daemon-reload`. Defined with `action :nothing` — only triggered by the notification from the service unit file resource above.
   - Resources: `execute` (1, triggered only)

   - **Step 11 — Enable and start fastapi-tutorial service**: Enables and starts the `fastapi-tutorial` systemd service.
   - Resources: `service` (1)

   **Total resources**: `package` (1), `directory` (1), `git` (1), `execute` (3), `service` (2), `file` (2)

   **No iterations / no loops** — single instance deployment.

---

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — required for cloning the repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL additional extensions
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` Python package compilation)

**Service dependencies**:
- `postgresql` — must be running before the FastAPI app starts (enforced via `After=postgresql.service` in the systemd unit)
- `fastapi-tutorial` — the application service managed by systemd

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file.

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a variable)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` resource: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` resource content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both at database creation time and at application runtime (via the `.env` file read by the FastAPI application to connect to `fastapi_db`).

> ⚠️ **Migration note for Solutions Architect**: This password is currently hardcoded in plain text in the recipe. During Ansible migration, this value **must** be stored in Ansible Vault, AAP Credentials, or an external secrets manager (e.g., HashiCorp Vault). It must be injected as a variable into both the PostgreSQL user creation task and the `.env` file template. Do **not** hardcode it in any Ansible playbook or variable file.

---

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git (confirms sync succeeded)
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` (TCP) — uvicorn / fastapi-tutorial application
- `127.0.0.1:5432` or `*:5432` (TCP) — PostgreSQL
- Unix sockets: None

**Templates rendered**:
- No `.erb` templates — configuration is written inline:
  - `/opt/fastapi-tutorial/.env` — rendered once (inline `file` resource)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (inline `file` resource)

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES — verify all 7 packages are installed
# ============================================================
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: all 7 packages listed with status 'ii' (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

psql --version
# Expected: psql (PostgreSQL) 1x.x

# ============================================================
# 2. APPLICATION DIRECTORY AND GIT REPOSITORY
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owner root, permissions drwxr-xr-x

stat -c "%a %U %G" /opt/fastapi-tutorial
# Expected: 755 root root

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

ls /opt/fastapi-tutorial/requirements.txt
# Expected: file exists (confirms git clone succeeded)

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database-related packages listed

ls -lh /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: uvicorn binary exists (confirms pip install -r requirements.txt succeeded)

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN

sudo -u postgres psql -c "\du fastapi"
# Expected: role 'fastapi' listed

sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi user has ALL privileges

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 5. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env (mode 0644)

stat -c "%a %U %G" /opt/fastapi-tutorial/.env
# Expected: 644 root root

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'PROJECT_NAME' /opt/fastapi-tutorial/.env
# Expected: PROJECT_NAME="FastAPI Tutorial"

grep 'API_VERSION' /opt/fastapi-tutorial/.env
# Expected: API_VERSION=1.0.0

# ============================================================
# 6. SYSTEMD SERVICE UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

stat -c "%a %U %G" /etc/systemd/system/fastapi-tutorial.service
# Expected: 644 root root

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections with uvicorn on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

systemctl cat fastapi-tutorial
# Expected: unit file content displayed without error (confirms daemon-reload was run)

# ============================================================
# 7. FASTAPI-TUTORIAL SERVICE STATUS
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 8. NETWORK — APPLICATION LISTENING ON PORT 8000
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN

lsof -i :8000
# Expected: uvicorn process listed

# ============================================================
# 9. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — but not 5xx or connection refused)

curl -s http://localhost:8000/docs
# Expected: HTML page for FastAPI Swagger UI (confirms app is running)

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ============================================================
# 10. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -i error
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no errors

# ============================================================
# 11. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```