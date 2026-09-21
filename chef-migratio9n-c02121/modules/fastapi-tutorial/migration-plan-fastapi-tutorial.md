---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user (`fastapi`/`fastapi_db`), writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI, backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn`, entry point `app.main:app`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Database: `fastapi_db` on `localhost`, owned by user `fastapi`

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: (none)

**Templates**: (none – configuration files are written inline via Chef `file` resources)

**Attributes**: (none – no attributes/default.rb file present)

**Files**: (none – no static `cookbook_file` resources)

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

   - **Installs system packages** (single `package` resource, 7 packages):
     - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

   - **Creates application directory** `/opt/fastapi-tutorial`:
     - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

   - **Clones Git repository** into `/opt/fastapi-tutorial`:
     - Source: `https://github.com/dibanez/fastapi_tutorial.git`
     - Branch/revision: `main`
     - Action: `sync` (updates if already cloned)

   - **Creates Python virtual environment** (`execute[create_venv]`):
     - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
     - Idempotent guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)

   - **Installs Python dependencies** (`execute[install_dependencies]`):
     - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
     - Working directory: `/opt/fastapi-tutorial`
     - Action: `:run` (runs every Chef converge)

   - **Enables and starts PostgreSQL service** (`service[postgresql]`):
     - Actions: `enable`, `start`

   - **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
     - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
       1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
       2. `CREATE DATABASE fastapi_db OWNER fastapi;`
       3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
     - Each command uses `|| true` to suppress errors if the object already exists (idempotency workaround)

   - **Writes `.env` file** to `/opt/fastapi-tutorial/.env`:
     - Owner: `root`, Group: `root`, Mode: `0644`
     - Inline content (three variables):
       - `PROJECT_NAME="FastAPI Tutorial"`
       - `API_VERSION=1.0.0`
       - `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

   - **Writes systemd unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
     - Owner: `root`, Group: `root`, Mode: `0644`
     - Inline content defines:
       - `Description=FastAPI Tutorial Service`
       - `After=network.target postgresql.service`
       - `Type=simple`, `User=root`
       - `WorkingDirectory=/opt/fastapi-tutorial`
       - `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
       - `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
       - `Restart=always`
     - **Notifies** `execute[systemd_reload]` to run immediately when this file changes

   - **Reloads systemd** (`execute[systemd_reload]`):
     - Command: `systemctl daemon-reload`
     - Action: `:nothing` (only triggered by the notification from the service file above)

   - **Enables and starts the fastapi-tutorial service** (`service[fastapi-tutorial]`):
     - Actions: `enable`, `start`

   - **Resources**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
   - **No iterations / no `.each` loops** — single instance, all resources run once

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment support
- `git` — source code checkout
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via systemd `After=` directive)
- `fastapi-tutorial.service` — the application service managed by this cookbook

## Credentials

**Detection Summary**: 2 credentials detected in 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (plaintext in recipe source code)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe, not retrieved from any secrets manager

### PostgreSQL Application User Password

- **Variable(s)**: `'fastapi_password'` (literal string, appears twice)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in:
  1. The `execute[create_db_user]` command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. The `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both to create the DB user and to construct the SQLAlchemy/asyncpg connection URL consumed by the FastAPI application at runtime.

### DATABASE_URL Connection String

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — full connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db` is written inline into the `.env` file
- **Usage context**: Read by the FastAPI application at startup (via `python-dotenv` or equivalent) to establish the database connection. Contains the embedded password from the credential above.

> ⚠️ **Security Note for Ansible Migration**: Both credentials must be migrated to Ansible Vault (`ansible-vault encrypt_string`) or an external secrets manager (HashiCorp Vault, AWS Secrets Manager, CyberArk). The `.env` file should be deployed with mode `0600` and owned by the service user rather than `root`/`0644`.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/requirements.txt` — pip requirements (cloned from git)
- `/opt/fastapi-tutorial/.env` — environment configuration file
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file
- `/var/log/` — application logs (via journald, no dedicated log file)

**Service endpoints to check**:
- `8000` (TCP, `0.0.0.0`, uvicorn/FastAPI)
- `5432` (TCP, PostgreSQL)
- Unix sockets: None
- Network interfaces: FastAPI binds to all interfaces (`0.0.0.0:8000`)

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

## Pre-flight Checks

```bash
# ─────────────────────────────────────────────
# 1. System packages
# ─────────────────────────────────────────────
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep '^ii'
# Expected: 7 lines starting with 'ii' (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ─────────────────────────────────────────────
# 2. Application directory and git clone
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owned by root:root, mode 0755

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/bin/python
# Expected: symlink or binary exists

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg2|asyncpg'
# Expected: fastapi, uvicorn, and database driver packages listed

# ─────────────────────────────────────────────
# 4. PostgreSQL service
# ─────────────────────────────────────────────
systemctl status postgresql
# Expected: active (running), enabled

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 0.0.0.0:5432 or 127.0.0.1:5432

# ─────────────────────────────────────────────
# 5. PostgreSQL database and user
# ─────────────────────────────────────────────
sudo -u postgres psql -c "\du fastapi"
# Expected: role 'fastapi' listed

sudo -u postgres psql -c "\l fastapi_db"
# Expected: database 'fastapi_db' listed with owner 'fastapi'

sudo -u postgres psql -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
# Expected: t (true)

psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: fastapi | fastapi_db
# (will prompt for password: fastapi_password)

# ─────────────────────────────────────────────
# 6. Environment file
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- root root (mode 0644)

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ─────────────────────────────────────────────
# 7. Systemd unit file
# ─────────────────────────────────────────────
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- root root (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service | grep -E 'ExecStart|User|WorkingDirectory|After|Restart'
# Expected:
# After=network.target postgresql.service
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ─────────────────────────────────────────────
# 8. fastapi-tutorial service
# ─────────────────────────────────────────────
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with 'uvicorn app.main:app --host 0.0.0.0 --port 8000'

# ─────────────────────────────────────────────
# 9. Network / port verification
# ─────────────────────────────────────────────
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 (uvicorn)

netstat -tulpn | grep 8000
# Expected: tcp 0.0.0.0:8000 LISTEN (uvicorn/python)

lsof -i :8000
# Expected: python3 or uvicorn process listed

# ─────────────────────────────────────────────
# 10. Application health check
# ─────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — not 500, not connection refused)

curl -s http://localhost:8000/docs | grep -i 'swagger\|openapi'
# Expected: FastAPI auto-generated Swagger UI HTML

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ─────────────────────────────────────────────
# 11. Logs
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial --no-pager -n 50
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial --no-pager | grep -iE 'error|traceback|exception' | tail -10
# Expected: no output (no errors)

journalctl -u postgresql --no-pager -n 20
# Expected: PostgreSQL started successfully, no FATAL lines

# ─────────────────────────────────────────────
# 12. Resource usage
# ─────────────────────────────────────────────
systemctl show fastapi-tutorial | grep -E 'MemoryCurrent|CPUUsageNSec'
# Expected: non-zero values indicating the process is alive

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|Threads'
# Expected: VmRSS in reasonable range (e.g., 50–200 MB), Threads >= 1
```