---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI Python web application on a single server. It installs Python 3 and PostgreSQL system packages, clones the application source from GitHub, sets up a Python virtual environment, configures a PostgreSQL database with a dedicated user, writes a `.env` configuration file with database credentials, and registers the application as a systemd service (`fastapi-tutorial`) listening on port 8000.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI web application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (bound to `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - ASGI Server: `uvicorn`, entry point `app.main:app`
  - Git Source: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Environment File: `/opt/fastapi-tutorial/.env`
  - Systemd Unit: `/etc/systemd/system/fastapi-tutorial.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

No providers, templates, or attributes files are present. All values are hardcoded inline in the recipe.

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, multi-package array):
  - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/Revision: `main`
  - Action: `sync` (pulls latest on every run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Idempotency guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef execution — no idempotency guard)

- **Enables and starts PostgreSQL service** (`service[postgresql]`):
  - Actions: `enable`, `start`

- **Creates PostgreSQL database user and database** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors on re-runs (idempotent by convention)
  - Action: `:run` (runs on every Chef execution)

- **Writes `.env` file** to `/opt/fastapi-tutorial/.env`:
  - Mode: `0644`, Owner: `root`, Group: `root`
  - Inline content:
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
  - Mode: `0644`, Owner: `root`, Group: `root`
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

- **Reloads systemd** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` by default — only runs when notified by the service file resource above

- **Enables and starts the fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

- **Resources summary**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **No iterations / no `.each` loops** — single instance deployment

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata; no `include_recipe` calls)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment support
- `git` — required for the `git` resource to clone the repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required to build `psycopg2` or similar Python packages)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via `After=postgresql.service` in the systemd unit)
- `fastapi-tutorial.service` — the application service managed by systemd

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no Vault, no data bags, no Chef Vault, no CyberArk integration detected)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe source code

### PostgreSQL User Password

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. The `execute[create_db_user]` command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. The `.env` file content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user; also embedded in the application's database connection URL written to `/opt/fastapi-tutorial/.env`

### DATABASE_URL (Connection String with Embedded Credentials)

- **Variable(s)**: `DATABASE_URL` (written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — full connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db` is written inline in the recipe
- **Usage context**: Read by the FastAPI application at runtime to connect to PostgreSQL; the `.env` file is loaded by the application (likely via `python-dotenv` or similar)

> ⚠️ **Security Note**: Both credentials are currently hardcoded in plain text in the recipe. During Ansible migration, these MUST be moved to Ansible Vault (`ansible-vault`), AAP Credentials, or an external secrets manager. The `.env` file should be templated and the password variable sourced from a vault-encrypted variable or AAP credential injection.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git (confirms sync succeeded)
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` — uvicorn / FastAPI application (all interfaces)
- `127.0.0.1:5432` — PostgreSQL database (localhost)

**Templates rendered**:
- No `.erb` templates — both configuration files use inline content in the recipe:
  - `/opt/fastapi-tutorial/.env` — rendered once (inline `file` resource)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (inline `file` resource)

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES - verify all 7 packages are installed
# ============================================================
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: 7 lines, all starting with "ii" (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ============================================================
# 2. APPLICATION DIRECTORY AND GIT REPOSITORY
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode drwxr-xr-x

stat -c "%a %U %G" /opt/fastapi-tutorial
# Expected: 755 root root

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: last 3 commits from the main branch

ls /opt/fastapi-tutorial/requirements.txt
# Expected: file exists (confirms git clone succeeded)

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg2'
# Expected: fastapi, uvicorn, and database driver packages listed

ls -lh /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: file exists and is executable

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres master process and worker processes visible

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or 0.0.0.0:5432

# Verify database user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: role "fastapi" listed

# Verify database 'fastapi_db' exists and is owned by 'fastapi'
sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

# Verify privileges on fastapi_db
sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi user has ALL privileges

# Test connection as fastapi user
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 5. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

stat -c "%a %U %G" /opt/fastapi-tutorial/.env
# Expected: 644 root root

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 6. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

stat -c "%a %U %G" /etc/systemd/system/fastapi-tutorial.service
# Expected: 644 root root

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections with uvicorn on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

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
# Expected: uvicorn process running as root from /opt/fastapi-tutorial/venv/bin/uvicorn

# ============================================================
# 8. NETWORK - PORT 8000
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 with uvicorn/python process

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN <pid>/python3

lsof -i :8000
# Expected: python3/uvicorn process listed

# ============================================================
# 9. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — but NOT 502/503/connection refused)

curl -s http://localhost:8000/docs | grep -i "swagger\|fastapi"
# Expected: FastAPI auto-generated Swagger UI HTML

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ============================================================
# 10. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -i error
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL lines

# ============================================================
# 11. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```