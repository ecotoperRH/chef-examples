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

**Providers**: None — no custom resources used

**Templates**: None — file content is inline in the recipe; no `.erb` templates

**Attributes**: None — no attributes file present; all values are hardcoded in the recipe

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
  - Action: `run` (runs on every Chef execution — **no idempotency guard**)

- **Enables and starts PostgreSQL service** (`service[postgresql]`):
  - Actions: `enable`, `start`

- **Creates PostgreSQL database user and database** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` for idempotency (errors are silently ignored)
  - Action: `run` (runs on every Chef execution)

- **Writes `.env` file** to `/opt/fastapi-tutorial/.env`:
  - Inline content (no template file):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```
  - Owner: `root`, Group: `root`, Mode: `0644`

- **Writes systemd unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
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
  - **Notifies** `execute[systemd_reload]` immediately on file change

- **Reloads systemd** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `nothing` by default — only triggered by the `.service` file notification above

- **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

- **Resources summary**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **No iterations / no `.each` loops** — single instance deployment

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata; no `include_recipe` calls)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment support
- `git` — required for cloning the repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required to build `psycopg2`)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via systemd `After=postgresql.service`)
- `fastapi-tutorial.service` — the application service managed by this cookbook

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no Vault, no data bags, no Chef Vault, no CyberArk integration)
- **URL**: N/A
- **Path**: N/A — credentials are written directly into the recipe and the `.env` file

### PostgreSQL User Password

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` inline content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user; also embedded in the application's database connection URL

### Database Connection URL (Composite Secret)

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written to `/opt/fastapi-tutorial/.env`)
- **Current storage**: Hardcoded inline file content — written as plaintext to `/opt/fastapi-tutorial/.env` with mode `0644` (world-readable)
- **Usage context**: Full database connection string consumed by the FastAPI application at runtime via the `.env` file; includes embedded username and password

> ⚠️ **Security Note for Solutions Architect**: The password `fastapi_password` is hardcoded in the recipe and written to a world-readable file (`0644`). In the Ansible migration, this credential **must** be stored in Ansible Vault or retrieved from an external secrets manager (HashiCorp Vault, CyberArk, AWS Secrets Manager). The `.env` file permissions should be tightened to `0600` and ownership changed from `root:root` to the service user.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git
- `/opt/fastapi-tutorial/.env` — environment configuration file
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file

**Service endpoints to check**:
- `0.0.0.0:8000` — uvicorn / FastAPI application (all interfaces)
- `127.0.0.1:5432` — PostgreSQL
- Unix sockets: None

**Templates rendered**: No `.erb` templates — both files (`/opt/fastapi-tutorial/.env` and `/etc/systemd/system/fastapi-tutorial.service`) are written with inline content in the recipe. Each file is written exactly **once**.

## Pre-flight Checks

```bash
# ─────────────────────────────────────────────
# 1. System packages verification
# ─────────────────────────────────────────────
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: all 7 packages listed with status 'ii' (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ─────────────────────────────────────────────
# 2. Application directory and git clone
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owned by root:root, mode drwxr-xr-x

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the 'main' branch

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/uvicorn --version
# Expected: Running uvicorn x.x.x with CPython x.x.x on Linux

# ─────────────────────────────────────────────
# 4. PostgreSQL service status
# ─────────────────────────────────────────────
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

# ─────────────────────────────────────────────
# 5. PostgreSQL database and user verification (fastapi_db)
# ─────────────────────────────────────────────
# Verify user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: row showing role 'fastapi'

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

# ─────────────────────────────────────────────
# 6. Environment file verification
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env  (mode 0644)

cat /opt/fastapi-tutorial/.env | grep PROJECT_NAME
# Expected: PROJECT_NAME="FastAPI Tutorial"

cat /opt/fastapi-tutorial/.env | grep API_VERSION
# Expected: API_VERSION=1.0.0

cat /opt/fastapi-tutorial/.env | grep DATABASE_URL
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ─────────────────────────────────────────────
# 7. Systemd unit file verification
# ─────────────────────────────────────────────
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service | grep ExecStart
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

cat /etc/systemd/system/fastapi-tutorial.service | grep -E 'After|Restart|User|WorkingDirectory'
# Expected: After=network.target postgresql.service, Restart=always, User=root, WorkingDirectory=/opt/fastapi-tutorial

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ─────────────────────────────────────────────
# 8. fastapi-tutorial service status
# ─────────────────────────────────────────────
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ─────────────────────────────────────────────
# 9. Network port verification
# ─────────────────────────────────────────────
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 ... users:(("uvicorn",...))

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN <pid>/uvicorn

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 ... users:(("postgres",...))

lsof -i :8000
# Expected: uvicorn process listed

lsof -i :5432
# Expected: postgres process listed

# ─────────────────────────────────────────────
# 10. Application HTTP health check
# ─────────────────────────────────────────────
curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307 redirect to /docs)

curl -s http://localhost:8000/docs | grep -i "fastapi"
# Expected: HTML containing FastAPI Swagger UI

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ─────────────────────────────────────────────
# 11. Logs
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 10 --no-pager | grep -i "started\|startup\|running"
# Expected: "Application startup complete." or "Started FastAPI Tutorial Service."

journalctl -u postgresql -n 20 --no-pager | grep -i "ready\|started\|listening"
# Expected: "database system is ready to accept connections"

grep -i "error\|exception\|traceback" /var/log/syslog | grep fastapi | tail -20
# Expected: no output (no errors)
```