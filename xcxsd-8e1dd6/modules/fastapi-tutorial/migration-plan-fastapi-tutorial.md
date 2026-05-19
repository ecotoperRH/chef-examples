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
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - ASGI Server: `uvicorn`, entry point `app.main:app`
  - Key Config: Runs as `root`, depends on `postgresql.service`, restarts always on failure

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: None — no custom resources used

**Templates**: None — file content is inline in the recipe, no `.erb` templates

**Attributes**: None — no attributes file present; all values are hardcoded in the recipe

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, multi-package array):
  - `python3`
  - `python3-pip`
  - `python3-venv`
  - `git`
  - `postgresql`
  - `postgresql-contrib`
  - `libpq-dev`

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/Revision: `main`
  - Action: `sync` (pulls latest on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Idempotency guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — no idempotency guard)

- **Enables and starts PostgreSQL** (`service[postgresql]`):
  - Actions: `enable`, `start`

- **Creates PostgreSQL database user and database** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if objects already exist (idempotency workaround)
  - Action: `:run` (runs on every Chef run)

- **Writes `.env` file** (`file[/opt/fastapi-tutorial/.env]`):
  - Destination: `/opt/fastapi-tutorial/.env`
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (three variables):
    - `PROJECT_NAME="FastAPI Tutorial"`
    - `API_VERSION=1.0.0`
    - `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

- **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (key directives):
    - `Description=FastAPI Tutorial Service`
    - `After=network.target postgresql.service`
    - `Type=simple`
    - `User=root`
    - `WorkingDirectory=/opt/fastapi-tutorial`
    - `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
    - `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
    - `Restart=always`
    - `WantedBy=multi-user.target`
  - **Notifies**: triggers `execute[systemd_reload]` immediately on file change

- **Reloads systemd** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` by default — only runs when notified by the service file resource above

- **Enables and starts the FastAPI service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

**Resources summary**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

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
- `postgresql.service` — must be running before the FastAPI app starts (declared in systemd `After=` directive)
- `fastapi-tutorial.service` — the application service managed by systemd

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL User Password

- **Variable(s)**: `'fastapi_password'` (literal string, used in three places)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — plaintext string literal in the recipe
- **Usage context**:
  1. Used in the `CREATE USER fastapi WITH PASSWORD 'fastapi_password';` SQL statement executed against PostgreSQL
  2. Embedded in the `DATABASE_URL` written to `/opt/fastapi-tutorial/.env`: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

> ⚠️ **Security Risk**: This password is stored in plaintext in the recipe source code, in the `.env` file on disk (mode `0644`, readable by all users), and in the PostgreSQL connection string. The Ansible migration **must** replace this with a secret stored in AAP Credential Manager, HashiCorp Vault, or an Ansible Vault-encrypted variable. The `.env` file permissions should also be tightened to `0600` and ownership changed from `root:root` to the service account.

### DATABASE_URL (Connection String)

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written inline to `/opt/fastapi-tutorial/.env`)
- **Current storage**: Hardcoded — written as inline file content in the recipe
- **Usage context**: Read by the FastAPI application at runtime to connect to PostgreSQL; the full connection string including username and password is written to `/opt/fastapi-tutorial/.env` in plaintext

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/requirements.txt` — dependency manifest (cloned from git)
- `/opt/fastapi-tutorial/.env` — environment configuration with `DATABASE_URL`
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file

**Service endpoints to check**:
- `0.0.0.0:8000` — FastAPI/uvicorn (all interfaces)
- `127.0.0.1:5432` — PostgreSQL (localhost)
- Unix sockets: None

**Templates rendered**:
- No `.erb` templates — all file content is written inline in the recipe
- `file[/opt/fastapi-tutorial/.env]` — rendered once (single instance)
- `file[/etc/systemd/system/fastapi-tutorial.service]` — rendered once (single instance)

## Pre-flight Checks

```bash
# ─────────────────────────────────────────────
# 1. System packages — verify all 7 are installed
# ─────────────────────────────────────────────
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: 7 lines, each starting with "ii"

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ─────────────────────────────────────────────
# 2. Application directory and git clone
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode 0755, contains app files

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: 3 most recent commits from the main branch

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn executables present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/pip check
# Expected: "No broken requirements" — no dependency conflicts

# ─────────────────────────────────────────────
# 4. PostgreSQL service
# ─────────────────────────────────────────────
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

# ─────────────────────────────────────────────
# 5. PostgreSQL database and user — fastapi_db / fastapi
# ─────────────────────────────────────────────
sudo -u postgres psql -c "\du fastapi"
# Expected: role "fastapi" listed

sudo -u postgres psql -c "\l fastapi_db"
# Expected: database "fastapi_db" listed with owner "fastapi"

sudo -u postgres psql -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
# Expected: t (true)

psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: fastapi | fastapi_db
# (will prompt for password: fastapi_password)

psql postgresql://fastapi:fastapi_password@localhost/fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

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

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections with uvicorn ExecStart on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ─────────────────────────────────────────────
# 8. FastAPI application service — fastapi-tutorial
# ─────────────────────────────────────────────
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

systemctl show fastapi-tutorial | grep -E 'Restart=|RestartSec='
# Expected: Restart=always

systemctl show fastapi-tutorial | grep 'After='
# Expected: After=network.target postgresql.service

# ─────────────────────────────────────────────
# 9. Network — port 8000 listening
# ─────────────────────────────────────────────
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0.0.0.0:8000 LISTEN uvicorn/python

lsof -i :8000
# Expected: python or uvicorn process listed

# ─────────────────────────────────────────────
# 10. Application HTTP health checks
# ─────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — check /docs instead)

curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs
# Expected: 200 (FastAPI auto-generated Swagger UI)

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ─────────────────────────────────────────────
# 11. Logs
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -i error
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL lines
```