---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application source, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance application deployment.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial** (single instance):
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn`, entry point `app.main:app`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Key Config: `PROJECT_NAME="FastAPI Tutorial"`, `API_VERSION=1.0.0`, `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

- **fastapi_db** (PostgreSQL database, local):
  - PostgreSQL user: `fastapi`, password: `fastapi_password` (hardcoded)
  - Database: `fastapi_db`, owner: `fastapi`
  - Privileges: `ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi`
  - Service: `postgresql` (enabled and started via systemd)

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
└── metadata.rb

Providers:    (none — no custom resources or providers used)
Templates:    (none — configuration files are written inline using Chef file resources with heredoc content)
Attributes:   (none — no attributes/default.rb file; all values are hardcoded in the recipe)
```

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
  - Repository URL: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/Revision: `main`
  - Action: `sync` (pulls latest on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if venv does not yet exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — no idempotency guard)

- **Enables and starts PostgreSQL service** (`service[postgresql]`):
  - Actions: `enable`, `start`

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors on re-runs (idempotency workaround)
  - Action: `:run`

- **Writes `.env` configuration file** (`file[/opt/fastapi-tutorial/.env]`):
  - Destination: `/opt/fastapi-tutorial/.env`
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (heredoc):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Inline content (heredoc):
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

- **Enables and starts the FastAPI service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

- **Resources summary**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **No iterations / no loops** — single instance deployment

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — source code checkout
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via systemd `After=postgresql.service`)
- `fastapi-tutorial.service` — the application's own systemd unit

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

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL database password for the `fastapi` application user. Used both to create the DB user and to construct the `DATABASE_URL` connection string consumed by the FastAPI application at runtime via the `.env` file.

### DATABASE_URL Connection String

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — full connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db` is written inline in the recipe heredoc
- **Usage context**: SQLAlchemy / asyncpg database connection string read by the FastAPI application at startup. Embeds both the username and password in plaintext in the `.env` file on disk (mode `0644` — world-readable).

> ⚠️ **Security note for the Solutions Architect**: The `.env` file is written with mode `0644` (world-readable). The password is hardcoded in the recipe. When migrating to Ansible, both the password and the `DATABASE_URL` must be stored in **Ansible Vault** (or AAP Credential objects) and the `.env` file should be deployed with mode `0600` or `0640` with a dedicated application user.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/requirements.txt` — pip requirements file (from git clone)
- `/opt/fastapi-tutorial/.env` — environment configuration (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- Port `8000` (TCP, `0.0.0.0`, uvicorn / fastapi-tutorial service)
- Port `5432` (TCP, PostgreSQL)
- Unix sockets: none explicitly configured

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources with heredoc content:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

## Pre-flight Checks

```bash
# ============================================================
# 1. System packages — verify all 7 packages are installed
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
# 2. Application directory and git clone
# ============================================================
ls -lad /opt/fastapi-tutorial
# Expected: drwxr-xr-x ... root root ... /opt/fastapi-tutorial

ls -lah /opt/fastapi-tutorial/
# Expected: app/, requirements.txt, .env, venv/ and other repo files present

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the 'main' branch

git -C /opt/fastapi-tutorial branch
# Expected: * main  (or detached HEAD at latest main commit)

# ============================================================
# 3. Python virtual environment
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg|asyncpg'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/pip check
# Expected: No broken requirements

# ============================================================
# 4. PostgreSQL service
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres master process and worker processes visible

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 0.0.0.0:5432 or 127.0.0.1:5432

# ============================================================
# 5. PostgreSQL database and user: fastapi / fastapi_db
# ============================================================
sudo -u postgres psql -c "\du fastapi"
# Expected: role 'fastapi' listed

sudo -u postgres psql -c "\l fastapi_db"
# Expected: database 'fastapi_db' listed with owner 'fastapi'

sudo -u postgres psql -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
# Expected: t (true)

sudo -u postgres psql -d fastapi_db -c "SELECT current_database(), current_user;"
# Expected: fastapi_db | postgres

# Test connection as fastapi user
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string returned without authentication error

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT 1 AS connectivity_check;"
# Expected: connectivity_check = 1

# ============================================================
# 6. Environment file
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env

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
# 7. Systemd unit file
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... /etc/systemd/system/fastapi-tutorial.service

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000, After=postgresql.service

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

# ============================================================
# 8. fastapi-tutorial service status
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
# 9. Network — port 8000 listening
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 with uvicorn/python process

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 ... LISTEN

lsof -i :8000
# Expected: python3 or uvicorn process listed

# ============================================================
# 10. Application health check — HTTP endpoint
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or application-defined redirect code, e.g. 307)

curl -s http://localhost:8000/docs | grep -i 'swagger\|fastapi\|openapi'
# Expected: FastAPI auto-generated Swagger UI HTML content

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ============================================================
# 11. Logs — verify no startup errors
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -i 'error\|exception\|traceback'
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager | grep -i 'error\|fatal'
# Expected: no output (no errors)

# ============================================================
# 12. Resource usage
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "RSS:", $6/1024 "MB"}'
# Expected: single uvicorn process with reasonable memory usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'Threads|VmRSS|VmSize'
# Expected: Threads: 1 (or more with async workers), VmRSS showing memory footprint
```