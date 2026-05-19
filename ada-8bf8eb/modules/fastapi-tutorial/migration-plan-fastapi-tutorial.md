---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000.

## Service Type and Instances

**Service Type**: Application Server (Python/FastAPI web application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Systemd Unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment File: `/opt/fastapi-tutorial/.env`
  - Key Config: Runs as `root`, uvicorn ASGI server, `Restart=always`, depends on `postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`
  - Port: `5432` (TCP, localhost)
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
└── metadata.rb
```

**Providers**: None — no custom resources used

**Templates**: None — no `.erb` template files; configuration is written inline via Chef `file` resources

**Attributes**: None — no `attributes/default.rb` file; all values are hardcoded in the recipe

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, all installed together):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — venv module for virtual environments
  - `git` — required for cloning the repository
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Source: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/Revision: `main`
  - Action: `sync` (pulls latest changes on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if the venv directory does not yet exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` — runs on every Chef run (no idempotency guard)

- **Enables and starts PostgreSQL service** (`service[postgresql]`):
  - Actions: `enable` (systemd enable) + `start`

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors on re-runs (idempotency workaround)
  - Action: `:run` — executes on every Chef run

- **Writes `.env` configuration file** (`file[/opt/fastapi-tutorial/.env]`):
  - Destination: `/opt/fastapi-tutorial/.env`
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (hardcoded):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
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
  - **Notifies**: triggers `execute[systemd_reload]` immediately when the file changes

- **Reloads systemd daemon** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only runs when notified by the service file resource above

- **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable` (systemd enable) + `start`

**Resources summary**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

**No iterations / no `.each` loops** — single application instance, single database.

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies** (installed by the recipe):
- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

**Python package dependencies** (installed via pip from `requirements.txt` in the cloned repo — exact packages determined at runtime from the repository; expected to include at minimum `fastapi`, `uvicorn`, `psycopg2` or `asyncpg`):
- Resolved from `/opt/fastapi-tutorial/requirements.txt` at deploy time

**Service dependencies** (systemd):
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (declared in `[Unit] After=`)
- `fastapi-tutorial.service` — the application service managed by this cookbook

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

## Credentials

**Detection Summary**: 2 credentials detected in 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk/Conjur integration detected)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe source code

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a variable — appears in two places)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — plain-text string literal in the recipe
- **Usage context**:
  1. Used in the `execute[create_db_user]` resource to create the PostgreSQL role: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. Used in the `file[/opt/fastapi-tutorial/.env]` resource to write the `DATABASE_URL` environment variable: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - The `.env` file is written with mode `0644` (world-readable), meaning the password is readable by all users on the system — this is a **security risk** that should be remediated in the Ansible migration (use `0600` or `0640` and store the password in Ansible Vault).

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/venv/bin/pip` — pip binary inside venv
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git (confirms sync succeeded)
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` (TCP) — uvicorn / fastapi-tutorial application
- `127.0.0.1:5432` (TCP) — PostgreSQL database server
- Unix sockets: None configured

**Templates rendered**: No `.erb` templates — configuration is written inline:
- `file[/opt/fastapi-tutorial/.env]` — rendered once (single application instance)
- `file[/etc/systemd/system/fastapi-tutorial.service]` — rendered once (single application instance)

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

# Verify git repository was cloned and is on 'main' branch
git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

ls /opt/fastapi-tutorial/requirements.txt
# Expected: file exists

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x (same as system python3)

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg|asyncpg|sqlalchemy'
# Expected: fastapi, uvicorn listed; psycopg2 or asyncpg if DB driver is in requirements.txt

ls -lh /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: file exists and is executable

# ============================================================
# 4. ENVIRONMENT CONFIGURATION FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... (mode 0644, owner root)

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 5. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644, owner root)

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections present

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ============================================================
# 6. POSTGRESQL SERVICE AND DATABASE
# ============================================================
# Service status
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres processes visible

# Network listening on PostgreSQL port
ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or 0.0.0.0:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN

# Verify database 'fastapi_db' exists
sudo -u postgres psql -c "\l" | grep fastapi_db
# Expected: fastapi_db | fastapi | UTF8 | ...

# Verify user 'fastapi' exists
sudo -u postgres psql -c "\du" | grep fastapi
# Expected: fastapi | ... (role listed)

# Test connection as fastapi user to fastapi_db
psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_database(), current_user, version();"
# Expected: returns fastapi_db | fastapi | PostgreSQL x.x.x ...
# (will prompt for password: fastapi_password)

# Verify privileges on fastapi_db
sudo -u postgres psql -d fastapi_db -c "\dp" | head -20
# Expected: fastapi user has privileges listed

# ============================================================
# 7. FASTAPI-TUTORIAL SERVICE
# ============================================================
# Service status
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# Confirm uvicorn process owner (should be root per unit file)
ps aux | grep uvicorn | grep -v grep | awk '{print $1}'
# Expected: root

# Check process working directory
ls -lah /proc/$(pgrep -f uvicorn)/cwd
# Expected: symlink to /opt/fastapi-tutorial

# Confirm PATH environment in process
cat /proc/$(pgrep -f uvicorn)/environ | tr '\0' '\n' | grep PATH
# Expected: PATH=/opt/fastapi-tutorial/venv/bin

# ============================================================
# 8. APPLICATION HEALTH CHECK (PORT 8000)
# ============================================================
# Verify port 8000 is listening
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN

lsof -i :8000
# Expected: uvicorn process listed

# HTTP health check — FastAPI root endpoint
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — but connection must succeed, not refuse)

# FastAPI auto-generated OpenAPI docs (standard FastAPI feature)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs
# Expected: 200

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | head -20
# Expected: valid JSON with "openapi", "info", "paths" keys

# ============================================================
# 9. SERVICE LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -p err -n 20 --no-pager
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL/ERROR lines
```