---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance application deployment.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn`, entry point `app.main:app`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Key Config: `Type=simple`, `Restart=always`, `User=root`, `After=network.target postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Database owner/user: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: (none)

**Templates**: (none — configuration is written inline via Chef file resources)

**Attributes**: (none — no attributes/default.rb file present)

**Files**: (none — no cookbook_file or remote_file resources used)

## Module Explanation

The cookbook performs all operations in a single recipe in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, 7 packages):
  - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

- **Creates application directory** (`directory` resource):
  - Path: `/opt/fastapi-tutorial`
  - Owner: `root`, Group: `root`, Mode: `0755`, `recursive: true`

- **Clones Git repository** (`git` resource, action: `:sync`):
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Destination: `/opt/fastapi-tutorial`
  - Action `:sync` means it will update the repo if already cloned

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if venv does not already exist (idempotent)

- **Installs Python dependencies** (`execute[install_dependencies]`, action: `:run`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Note: Runs unconditionally on every Chef run (no `creates` guard)

- **Enables and starts PostgreSQL** (`service[postgresql]`):
  - Actions: `[:enable, :start]`
  - Manages the system PostgreSQL service

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`, action: `:run`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if the user/database already exists (idempotent)

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
  - **Notifies**: triggers `execute[systemd_reload]` immediately upon file change

- **Reloads systemd daemon** (`execute[systemd_reload]`, action: `:nothing`):
  - Command: `systemctl daemon-reload`
  - Only runs when notified by the service file resource above (not on every run)

- **Enables and starts the FastAPI service** (`service[fastapi-tutorial]`):
  - Actions: `[:enable, :start]`
  - Manages the `fastapi-tutorial` systemd unit

**Resources summary**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

**No iterations / no `.each` loops** — single instance deployment.

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — required for cloning the repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL additional modules
- `libpq-dev` — PostgreSQL client development headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (enforced via `After=` in unit file)
- `fastapi-tutorial.service` — the application systemd unit

## Credentials

**Detection Summary**: 2 credentials detected across 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk/Conjur integration detected)
- **URL**: N/A
- **Path**: N/A

### PostgreSQL User Password

- **Variable(s)**: `'fastapi_password'` (literal string, used in both the `execute[create_db_user]` SQL command and the `.env` file content)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — plaintext string literal embedded directly in the recipe
- **Usage context**: Used in two places:
  1. PostgreSQL `CREATE USER fastapi WITH PASSWORD 'fastapi_password';` SQL statement executed during database provisioning
  2. `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` written to `/opt/fastapi-tutorial/.env` for application runtime use

### DATABASE_URL (Connection String)

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — full connection string with embedded credentials written inline in the recipe
- **Usage context**: Read by the FastAPI application at runtime to connect to the PostgreSQL database. The `.env` file is loaded by the application (likely via `python-dotenv` or similar). File permissions are `0644` (world-readable — **security concern**).

> ⚠️ **Security Note for Solutions Architect**: Both credentials are currently hardcoded in plaintext in the recipe. During Ansible migration, these MUST be stored in Ansible Vault, AAP Credentials, or an external secrets manager. The `.env` file permissions should also be tightened to `0600` (owner-readable only) since it contains a database password.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` (TCP) — uvicorn / fastapi-tutorial application
- `127.0.0.1:5432` or `0.0.0.0:5432` (TCP) — PostgreSQL
- Unix sockets: None configured

**Templates rendered**:
- No `.erb` templates — configuration is written inline via `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

## Pre-flight Checks

```bash
# ============================================================
# 1. System packages verification
# ============================================================
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: all 7 packages listed with status 'ii' (installed)

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ============================================================
# 2. Application directory and git repository
# ============================================================
ls -lad /opt/fastapi-tutorial
# Expected: drwxr-xr-x ... root root ... /opt/fastapi-tutorial

ls -lah /opt/fastapi-tutorial/
# Expected: requirements.txt, app/, venv/, .env present

git -C /opt/fastapi-tutorial remote -v
# Expected: origin https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ============================================================
# 3. Python virtual environment
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/uvicorn --version
# Expected: Running uvicorn x.x.x with CPython x.x.x on Linux

# ============================================================
# 4. Environment configuration file
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

# ============================================================
# 5. Systemd unit file
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... /etc/systemd/system/fastapi-tutorial.service

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000

grep -E 'ExecStart|User|WorkingDirectory|Restart|After' /etc/systemd/system/fastapi-tutorial.service
# Expected:
# After=network.target postgresql.service
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ============================================================
# 6. PostgreSQL service status
# ============================================================
systemctl status postgresql
# Expected: active (running)

systemctl is-enabled postgresql
# Expected: enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres processes visible

ss -tlnp | grep 5432
# Expected: 127.0.0.1:5432 or 0.0.0.0:5432 LISTEN

# ============================================================
# 7. PostgreSQL database and user provisioning
# ============================================================
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi user listed with no special roles

sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db database listed with owner 'fastapi'

sudo -u postgres psql -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
# Expected: t (true)

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: fastapi | fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 8. FastAPI application service status
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running)

systemctl is-enabled fastapi-tutorial
# Expected: enabled

ps aux | grep uvicorn | grep -v grep
# Expected: uvicorn process running as root from /opt/fastapi-tutorial/venv/bin/uvicorn

# ============================================================
# 9. Application health and port verification
# ============================================================
ss -tlnp | grep 8000
# Expected: 0.0.0.0:8000 LISTEN (uvicorn)

lsof -i :8000
# Expected: uvicorn process listening on port 8000

curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 307 redirect depending on app routing)

curl -s http://localhost:8000/docs | grep -i 'swagger\|fastapi'
# Expected: FastAPI auto-generated Swagger UI HTML

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ============================================================
# 10. Application logs
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -n 100 --no-pager | grep -iE 'error|critical|traceback'
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no errors

# ============================================================
# 11. Service dependency ordering
# ============================================================
systemctl list-dependencies fastapi-tutorial
# Expected: postgresql.service listed as a dependency

systemctl show fastapi-tutorial | grep -E 'After=|Requires='
# Expected: After=network.target postgresql.service

# ============================================================
# 12. Resource usage
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "MEM%:", $4, "CPU%:", $3}'
# Expected: single uvicorn process with reasonable memory usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory and thread counts for the running process
```