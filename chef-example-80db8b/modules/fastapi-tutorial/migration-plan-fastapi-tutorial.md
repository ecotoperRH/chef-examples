---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user (`fastapi`/`fastapi_db`), writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000.

---

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI, backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn` (`app.main:app`)
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Run as user: `root`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Database owner/user: `fastapi`
  - Password: `fastapi_password` (**hardcoded**)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

---

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
```

**Recipes:**
```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers:**
```
(none)
```

**Templates:**
```
(none — configuration files are written inline via Chef file resources)
```

**Attributes:**
```
(none — no attributes/default.rb file present)
```

**Files:**
```
(none — no static cookbook_file resources)
```

---

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, all at once):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — virtual environment support
  - `git` — required for repository cloning
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (needed for `psycopg2` compilation)

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Source: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/revision: `main`
  - Action: `sync` (pulls latest on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Idempotent guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — **not idempotent**)

- **Enables and starts PostgreSQL service** (`service[postgresql]`):
  - Actions: `enable`, `start`

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if the user/database already exists (idempotency workaround)

- **Writes `.env` file** to `/opt/fastapi-tutorial/.env`:
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (hardcoded):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content:
    ```ini
    [Unit]
    Description=FastAPI Tutorial Service
    After=network.target postgresql.service

    [Service]
    Type=simple
    User=root
    WorkingDirectory=/opt/fastapi-tutorial
    Environment="PATH=/opt/fastapi-tutorial/venv/bin"
    ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
    Restart=always

    [Install]
    WantedBy=multi-user.target
    ```
  - **Notifies** `execute[systemd_reload]` to run immediately when this file changes

- **Reloads systemd** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only triggered by the notification from the service file resource above

- **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

**Resources summary**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment module
- `git` — source code checkout
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL contrib extensions
- `libpq-dev` — PostgreSQL development headers (for psycopg2 build)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (declared in systemd `After=` directive)
- `fastapi-tutorial.service` — the application service managed by systemd

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: **Hardcoded** — appears in three places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication for the `fastapi` database user; also embedded in the application's `DATABASE_URL` environment variable used at runtime by the FastAPI application to connect to `fastapi_db`

### DATABASE_URL Connection String

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: **Hardcoded** — written inline as file content in the `file[/opt/fastapi-tutorial/.env]` resource
- **Usage context**: Full PostgreSQL connection string (`postgresql://fastapi:fastapi_password@localhost/fastapi_db`) loaded by the FastAPI application at startup to establish database connectivity; the `.env` file is readable by all users (mode `0644`) which exposes the password

> ⚠️ **Security Note for Migration**: Both credentials are hardcoded in plain text in the recipe and written to a world-readable file (`0644`). During Ansible migration, these MUST be stored in Ansible Vault, AAP Credentials, or an external secrets manager. The `.env` file permissions should be tightened to `0600` or `0640`.

---

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git
- `/opt/fastapi-tutorial/app/main.py` — main application module (entry point)
- `/opt/fastapi-tutorial/.env` — environment configuration (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` (TCP) — uvicorn / fastapi-tutorial application
- `127.0.0.1:5432` or `0.0.0.0:5432` (TCP) — PostgreSQL
- Unix sockets: None configured

**Templates rendered**:
- No `.erb` templates — configuration is written inline via `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES
# ============================================================
# Verify all required packages are installed
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: all 7 packages listed with status 'ii' (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ============================================================
# 2. APPLICATION DIRECTORY AND GIT REPOSITORY
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode drwxr-xr-x

# Verify git repository is cloned and on correct branch
git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch
# Expected: * main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip show uvicorn
# Expected: Name: uvicorn, Version: x.x.x

/opt/fastapi-tutorial/venv/bin/pip show fastapi
# Expected: Name: fastapi, Version: x.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'uvicorn|fastapi|psycopg2|sqlalchemy'
# Expected: all application dependencies listed

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres master process and worker processes visible

# Verify PostgreSQL is listening on port 5432
ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or 0.0.0.0:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN

# Verify database user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi | ... | {}

# Verify database 'fastapi_db' exists and is owned by 'fastapi'
sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

# Verify privileges on fastapi_db
sudo -u postgres psql -c "\dp" fastapi_db
# Expected: fastapi user has ALL privileges

# Test application user can connect to the database
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 5. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env (mode 0644)

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
# 6. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections as defined in recipe

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart=' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

# Verify systemd has loaded the unit (daemon-reload was run)
systemctl cat fastapi-tutorial.service
# Expected: unit file content displayed without errors

# ============================================================
# 7. FASTAPI-TUTORIAL SERVICE
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running), enabled, no failed state

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 8. APPLICATION HEALTH AND PORT
# ============================================================
# Verify uvicorn is listening on port 8000
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN

lsof -i :8000
# Expected: uvicorn process listed

# HTTP health check — FastAPI root endpoint
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — but no 5xx errors)

# FastAPI automatic docs endpoint (always present in FastAPI apps)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs
# Expected: 200

curl -s http://localhost:8000/docs | grep -i "swagger\|fastapi"
# Expected: HTML content referencing Swagger UI or FastAPI

# OpenAPI schema endpoint
curl -s http://localhost:8000/openapi.json | python3 -m json.tool | head -20
# Expected: valid JSON with "openapi", "info", "paths" keys

# ============================================================
# 9. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 10 --no-pager | grep -i "error\|exception\|traceback"
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL errors

# ============================================================
# 10. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```