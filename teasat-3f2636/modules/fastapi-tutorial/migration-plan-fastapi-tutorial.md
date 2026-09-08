---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user with hardcoded credentials, writes a `.env` configuration file with a hardcoded `DATABASE_URL`, creates a systemd service unit, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance deployment.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (bound to `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - Process Manager: systemd (`/etc/systemd/system/fastapi-tutorial.service`)
  - ASGI Server: `uvicorn`, entry point `app.main:app`
  - Git Source: `https://github.com/dibanez/fastapi_tutorial.git`, branch `main`
  - Key Config: `.env` file at `/opt/fastapi-tutorial/.env` with `DATABASE_URL`, `PROJECT_NAME`, `API_VERSION`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost` (socket/TCP)

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: (none)

**Templates**: (none — inline file content used instead of .erb templates)

**Attributes**: (none — no attributes/default.rb file present)

**Files**: (none — no cookbook_file or remote_file resources)

## Module Explanation

The cookbook performs all operations in a single recipe in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, 7 packages):
  - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`
  - Resource: `directory`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/Branch: `main`
  - Action: `sync` (pulls latest on every Chef run)
  - Resource: `git`

- **Creates Python virtual environment** at `/opt/fastapi-tutorial/venv`:
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Idempotent guard: `creates '/opt/fastapi-tutorial/venv'` (only runs if venv does not exist)
  - Resource: `execute[create_venv]`

- **Installs Python dependencies** from `requirements.txt`:
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `run` (runs on every Chef run — no idempotency guard)
  - Resource: `execute[install_dependencies]`

- **Enables and starts PostgreSQL service**:
  - Actions: `enable`, `start`
  - Resource: `service[postgresql]`

- **Creates PostgreSQL database user and database** (idempotent via `|| true`):
  - Runs 3 SQL statements as the `postgres` OS user:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Command uses `sudo -u postgres psql -c "..." || true` to suppress errors if objects already exist
  - Resource: `execute[create_db_user]`

- **Writes `.env` configuration file** to `/opt/fastapi-tutorial/.env`:
  - Inline content (no template file):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Resource: `file[/opt/fastapi-tutorial/.env]`

- **Writes systemd service unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
  - Inline content (no template file):
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
  - Owner: `root`, Group: `root`, Mode: `0644`
  - **Notifies**: triggers `execute[systemd_reload]` immediately on file change
  - Resource: `file[/etc/systemd/system/fastapi-tutorial.service]`

- **Reloads systemd daemon** (triggered only when service unit file changes):
  - Command: `systemctl daemon-reload`
  - Action: `nothing` (only runs when notified by the file resource above)
  - Resource: `execute[systemd_reload]`

- **Enables and starts the fastapi-tutorial service**:
  - Actions: `enable`, `start`
  - Resource: `service[fastapi-tutorial]`

- **Total resources**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2) = **11 resources**

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — required for cloning the repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL additional extensions
- `libpq-dev` — PostgreSQL client development headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via `After=postgresql.service` in the systemd unit)
- `fastapi-tutorial.service` — the application service managed by systemd

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

## Credentials

**Detection Summary**: 2 credentials detected in 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk/Conjur integration detected)
- **URL**: N/A
- **Path**: N/A

### PostgreSQL User Password

- **Variable(s)**: `'fastapi_password'` (literal string)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` inline content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both to create the DB user and to construct the application's database connection string. **This password is written in plaintext to `/opt/fastapi-tutorial/.env` on disk.**

### Database Connection URL (Composite Secret)

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — written inline as file content to `/opt/fastapi-tutorial/.env`
- **Usage context**: Full PostgreSQL connection string consumed by the FastAPI application at runtime. Contains embedded username and password. The `.env` file is read by the application (likely via `python-dotenv` or similar) to configure the database connection.

> ⚠️ **Security Note for Solutions Architect**: Both credentials are currently hardcoded in the recipe. During Ansible migration, these MUST be moved to Ansible Vault (`ansible-vault`), AAP Credentials, or an external secrets manager (HashiCorp Vault, CyberArk). The `.env` file should be templated with variables injected at deploy time, and the file permissions should be tightened from `0644` to `0600` to prevent world-readable secrets on disk.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/requirements.txt` — must exist after git clone
- `/opt/fastapi-tutorial/app/main.py` — FastAPI application entry point (must exist after git clone)
- `/opt/fastapi-tutorial/.env` — environment configuration file (owner: root, mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (owner: root, mode: 0644)

**Service endpoints to check**:
- Ports listening: `8000` (fastapi-tutorial uvicorn), `5432` (PostgreSQL)
- Unix sockets: `/var/run/postgresql/.s.PGSQL.5432` (PostgreSQL local socket)
- Network interfaces: `0.0.0.0:8000` (fastapi-tutorial binds all interfaces)

**Templates rendered**:
- No `.erb` templates — both configuration files use inline content written directly by `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES - verify all 7 packages are installed
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
# 2. APPLICATION DIRECTORY AND GIT CLONE
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode drwxr-xr-x

ls -lah /opt/fastapi-tutorial/app/main.py
# Expected: file exists (confirms git clone succeeded)

ls -lah /opt/fastapi-tutorial/requirements.txt
# Expected: file exists

cd /opt/fastapi-tutorial && git remote -v
# Expected: origin https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

cd /opt/fastapi-tutorial && git log --oneline -3
# Expected: recent commits from 'main' branch

cd /opt/fastapi-tutorial && git branch --show-current
# Expected: main

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/python3
# Expected: symlink or binary exists

/opt/fastapi-tutorial/venv/bin/python3 --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i uvicorn
# Expected: uvicorn  x.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i fastapi
# Expected: fastapi  x.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i psycopg2
# Expected: psycopg2 or psycopg2-binary  x.x.x

# ============================================================
# 4. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- root root (mode 0644)

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'PROJECT_NAME' /opt/fastapi-tutorial/.env
# Expected: PROJECT_NAME="FastAPI Tutorial"

grep 'API_VERSION' /opt/fastapi-tutorial/.env
# Expected: API_VERSION=1.0.0

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 5. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

# Verify PostgreSQL is listening on port 5432
ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or 0.0.0.0:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN ... postgres

# Verify the 'fastapi' database user exists
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi | ... (user listed)

# Verify the 'fastapi_db' database exists
sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ... (database listed with owner fastapi)

# Verify privileges on fastapi_db
sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi user has ALL privileges

# Test connection as fastapi user to fastapi_db
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 6. SYSTEMD SERVICE UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- root root (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: contains [Unit], [Service], [Install] sections

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart=' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

grep 'User=' /etc/systemd/system/fastapi-tutorial.service
# Expected: User=root

# Verify systemd has loaded the unit (daemon-reload was run)
systemctl cat fastapi-tutorial
# Expected: prints the unit file content without error

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
# 8. APPLICATION HEALTH AND PORT VERIFICATION
# ============================================================
# Verify port 8000 is listening
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN ... uvicorn

lsof -i :8000
# Expected: uvicorn process listed

# HTTP health check - FastAPI root endpoint
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route defined — check /docs instead)

# FastAPI auto-generated OpenAPI docs (always present in FastAPI apps)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs
# Expected: 200

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial" (or similar)

# Full response headers
curl -I http://localhost:8000/docs
# Expected: HTTP/1.1 200 OK, content-type: text/html

# ============================================================
# 9. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -f
# Expected: live log stream showing incoming requests

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no ERROR lines

# Check for startup errors specifically
journalctl -u fastapi-tutorial --since "10 minutes ago" | grep -iE 'error|critical|failed|exception'
# Expected: no output (no errors)

# ============================================================
# 10. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```