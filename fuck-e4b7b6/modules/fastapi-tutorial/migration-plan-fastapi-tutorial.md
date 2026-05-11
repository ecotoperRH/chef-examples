---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000.

---

## Service Type and Instances

**Service Type**: Application Server (Python/FastAPI web application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - Entry Point: `app.main:app` (uvicorn ASGI server)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Systemd Unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment File: `/opt/fastapi-tutorial/.env`
  - Key Config: `PROJECT_NAME="FastAPI Tutorial"`, `API_VERSION=1.0.0`, `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost` (socket/loopback)
  - Privileges: `ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi`

---

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: None — no custom resources used

**Templates**: None — file content is inlined directly in the recipe using heredoc strings

**Attributes**: None — no attributes/default.rb file; all values are hardcoded in the recipe

---

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, multi-package array):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — virtual environment support
  - `git` — required for repository cloning
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

- **Creates application directory** (`directory` resource):
  - Path: `/opt/fastapi-tutorial`
  - Owner: `root`, Group: `root`, Mode: `0755`, `recursive: true`

- **Clones application repository** (`git` resource):
  - Destination: `/opt/fastapi-tutorial`
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/Branch: `main`
  - Action: `:sync` (pulls latest changes on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if the venv directory does not yet exist (idempotent)

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` — runs on every Chef run (no idempotency guard; pip will no-op if already satisfied)

- **Enables and starts PostgreSQL** (`service[postgresql]`):
  - Actions: `:enable` (systemd enable) and `:start`

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if the user/database already exists (idempotent workaround)
  - Action: `:run` — runs on every Chef run

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
  - Actions: `:enable` (systemd enable) and `:start`

**Resources summary**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2) — **11 resources total**

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment module
- `git` — source code management
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL additional modules
- `libpq-dev` — PostgreSQL development headers (for psycopg2 build)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (declared in `After=` in the unit file)
- `fastapi-tutorial.service` — the application service managed by systemd

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk/Conjur integration detected)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe source code

### PostgreSQL Application User Password

- **Variable(s)**: `'fastapi_password'` (literal string, appears in three locations)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — plain-text string literal in the recipe
- **Usage context**:
  1. Used in the `CREATE USER fastapi WITH PASSWORD 'fastapi_password';` SQL statement executed via `execute[create_db_user]`
  2. Embedded in the `DATABASE_URL` value written to `/opt/fastapi-tutorial/.env`: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  3. The `.env` file is read at runtime by the FastAPI application to connect to PostgreSQL

> ⚠️ **Security Risk**: This password is stored in plain text in the recipe, in the `.env` file on disk (mode `0644`, world-readable), and in the systemd environment. The Solutions Architect **must** replace this with a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, or AAP Credential Store) before production deployment.

### DATABASE_URL Connection String

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written to `/opt/fastapi-tutorial/.env`)
- **Current storage**: Hardcoded — written as inline heredoc content in the recipe; persisted to `/opt/fastapi-tutorial/.env` on disk
- **Usage context**: Read by the FastAPI application at startup to establish the SQLAlchemy/asyncpg database connection. The full connection string including credentials is stored in a world-readable file (`0644`).

> ⚠️ **Security Risk**: The `.env` file mode is `0644` (world-readable). This should be changed to `0600` (owner-readable only) and the password should be injected from a vault at deploy time rather than hardcoded.

---

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git
- `/opt/fastapi-tutorial/app/main.py` — application entry point (cloned from git)
- `/opt/fastapi-tutorial/.env` — environment configuration file
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file

**Service endpoints to check**:
- `8000` (TCP, `0.0.0.0`, uvicorn/FastAPI)
- `5432` (TCP, PostgreSQL, localhost)
- Unix sockets: None configured

**Templates rendered**:
- No `.erb` templates — both configuration files use inline heredoc content in the recipe
- `file[/opt/fastapi-tutorial/.env]` — rendered once (single instance)
- `file[/etc/systemd/system/fastapi-tutorial.service]` — rendered once (single instance)

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES — verify all 7 packages are installed
# ============================================================
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: 7 lines, all starting with 'ii' (installed)

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
# Expected: directory owned by root:root, mode drwxr-xr-x

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: 3 most recent commits from the main branch

ls /opt/fastapi-tutorial/app/main.py
# Expected: file exists (application entry point)

ls /opt/fastapi-tutorial/requirements.txt
# Expected: file exists

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg2|asyncpg'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/uvicorn --version
# Expected: Running uvicorn x.x.x with CPython x.x.x on Linux

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres master process and worker processes visible

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

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
# Expected: -rw-r--r-- root root (mode 0644)

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
# Expected: -rw-r--r-- root root (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000, After=postgresql.service

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

systemctl cat fastapi-tutorial
# Expected: full unit file content as written by the recipe

# ============================================================
# 7. FASTAPI SERVICE STATUS
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: uvicorn process running as root with app.main:app

# ============================================================
# 8. NETWORK — PORT 8000 LISTENING
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 with uvicorn/python pid

netstat -tulpn | grep 8000
# Expected: tcp 0.0.0.0:8000 LISTEN (uvicorn)

lsof -i :8000
# Expected: python3/uvicorn process listed

# ============================================================
# 9. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — check docs endpoint instead)

curl -s http://localhost:8000/docs | grep -i 'swagger\|fastapi'
# Expected: HTML page containing Swagger UI / FastAPI docs

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or appropriate status), server: uvicorn

# ============================================================
# 10. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -f
# Expected: live log stream showing incoming requests

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL/ERROR lines

grep -i 'error\|exception\|traceback' /var/log/syslog | grep fastapi | tail -20
# Expected: no output (no errors)

# ============================================================
# 11. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```