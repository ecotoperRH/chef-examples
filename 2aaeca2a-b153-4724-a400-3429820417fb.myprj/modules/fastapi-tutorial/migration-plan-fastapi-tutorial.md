# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application source, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance deployment.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (bound to `0.0.0.0`)
  - ASGI Server: `uvicorn` (from virtualenv at `/opt/fastapi-tutorial/venv/bin/uvicorn`)
  - Entry point: `app.main:app`
  - Git source: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Key Config: `PROJECT_NAME="FastAPI Tutorial"`, `API_VERSION=1.0.0`, `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost` (socket/loopback)
  - Managed by: `postgresql` systemd service

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: None — no custom resources used

**Templates**: None — configuration files are written inline using Chef `file` resources with heredoc content

**Attributes**: None — no attributes/default.rb file; all values are hardcoded in the recipe

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, multi-package array):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — virtualenv support
  - `git` — required for source checkout
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

- **Creates application directory** (`directory[/opt/fastapi-tutorial]`):
  - Path: `/opt/fastapi-tutorial`
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones application source** (`git[/opt/fastapi-tutorial]`):
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/branch: `main`
  - Action: `sync` (pulls latest on every Chef run)
  - Destination: `/opt/fastapi-tutorial`

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if venv does not already exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — no idempotency guard)

- **Enables and starts PostgreSQL** (`service[postgresql]`):
  - Actions: `enable`, `start`
  - Ensures PostgreSQL is running before database provisioning

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if the user/database already exists (idempotency workaround)
  - Action: `:run` (runs on every Chef run)

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
  - **Notifies**: triggers `execute[systemd_reload]` immediately upon file change

- **Reloads systemd daemon** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only runs when notified by the service file resource above

- **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`
  - Depends on the systemd unit file being present and daemon reloaded

- **Resources**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **Total resources**: 11

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — Git SCM client
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL additional modules
- `libpq-dev` — PostgreSQL development headers (for psycopg2 build)

**Service dependencies**:
- `postgresql.service` — must be running before database provisioning and before `fastapi-tutorial.service` starts (declared in `After=` in the unit file)
- `fastapi-tutorial.service` — the application systemd unit, `Restart=always`

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

- **Variable(s)**: `fastapi_password` (literal string, not a variable — appears in three places)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: **Hardcoded** — the password string `'fastapi_password'` is embedded directly in:
  1. The `execute[create_db_user]` resource: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. The `file[/opt/fastapi-tutorial/.env]` resource content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication — used to create the `fastapi` database role and to construct the SQLAlchemy/asyncpg `DATABASE_URL` connection string consumed by the FastAPI application at runtime via the `.env` file.

> ⚠️ **Security Risk**: This password is stored in plaintext in the recipe, in the `.env` file on disk (mode `0644`, world-readable), and in the PostgreSQL connection URL. For the Ansible migration, this credential **must** be moved to Ansible Vault, AAP Credentials, or an external secrets manager (HashiCorp Vault, CyberArk, AWS Secrets Manager). The `.env` file permissions should also be tightened to `0600` and ownership changed from `root:root` to the service-running user.

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
- `0.0.0.0:8000` — uvicorn / FastAPI application (all interfaces)
- `127.0.0.1:5432` — PostgreSQL (loopback)
- `/var/run/postgresql/.s.PGSQL.5432` — PostgreSQL Unix socket (default on Ubuntu/Debian)

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources with heredoc content:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

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
# 2. APPLICATION DIRECTORY AND GIT CLONE
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned root:root, mode drwxr-xr-x

ls -lah /opt/fastapi-tutorial/app/main.py
# Expected: file exists (confirms git clone succeeded)

ls -lah /opt/fastapi-tutorial/requirements.txt
# Expected: file exists

cd /opt/fastapi-tutorial && git log --oneline -5
# Expected: recent commits from branch 'main' of https://github.com/dibanez/fastapi_tutorial.git

cd /opt/fastapi-tutorial && git remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

cd /opt/fastapi-tutorial && git branch --show-current
# Expected: main

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/python3
# Expected: symlink or binary exists

ls -lah /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: file exists (confirms pip install ran successfully)

/opt/fastapi-tutorial/venv/bin/python3 --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg2|pydantic'
# Expected: fastapi, uvicorn, and other dependencies listed with version numbers

/opt/fastapi-tutorial/venv/bin/pip check
# Expected: No broken requirements

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

ps aux | grep postgres | grep -v grep
# Expected: postgres master process and worker processes visible

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN

sudo -u postgres psql -c "\l" | grep fastapi_db
# Expected: fastapi_db | fastapi | UTF8 | ...

sudo -u postgres psql -c "\du" | grep fastapi
# Expected: fastapi | ... (role listed)

PGPASSWORD=fastapi_password psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_database(), current_user, version();"
# Expected: returns fastapi_db | fastapi | PostgreSQL 1x.x ...

PGPASSWORD=fastapi_password psql -h localhost -U fastapi -d fastapi_db -c "SELECT 1 AS connection_ok;"
# Expected: connection_ok = 1

sudo -u postgres psql -d fastapi_db -c "\dp" | head -20
# Expected: fastapi user has privileges on fastapi_db objects

# ============================================================
# 5. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... (mode 0644, owner root)

cat /opt/fastapi-tutorial/.env
# Expected exact content:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'PROJECT_NAME' /opt/fastapi-tutorial/.env
# Expected: PROJECT_NAME="FastAPI Tutorial"

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 6. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644, owner root)

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

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
# Expected: uvicorn process running as root from /opt/fastapi-tutorial/venv/bin/uvicorn

# ============================================================
# 8. NETWORK — FastAPI application on port 8000
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN

lsof -i :8000
# Expected: uvicorn process listed

# ============================================================
# 9. APPLICATION HEALTH CHECKS
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 307 redirect depending on app routing)

curl -s http://localhost:8000/docs | grep -i 'swagger\|openapi'
# Expected: FastAPI auto-generated Swagger UI HTML

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307), server: uvicorn

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
# Expected: memory usage and thread count visible
```