---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user (`fastapi`/`fastapi_db`), writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000.

---

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI, backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Python venv: `/opt/fastapi-tutorial/venv`
  - ASGI server: `uvicorn`, entry point `app.main:app`
  - Run as user: `root`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Database: `fastapi_db` on `localhost`, owned by PostgreSQL user `fastapi`

---

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: (none)

**Templates**: (none — configuration files are written inline via Chef `file` resources)

**Attributes**: (none — no attributes/default.rb file present)

**Files**: (none — no static `cookbook_file` resources)

---

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

   - **Installs system packages** (single `package` resource, all at once):
     - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

   - **Creates application directory** `/opt/fastapi-tutorial`:
     - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

   - **Clones Git repository** into `/opt/fastapi-tutorial`:
     - Source: `https://github.com/dibanez/fastapi_tutorial.git`
     - Branch/revision: `main`
     - Action: `sync` (updates on every Chef run if changed)

   - **Creates Python virtual environment** via `execute[create_venv]`:
     - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
     - Idempotent guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)

   - **Installs Python dependencies** via `execute[install_dependencies]`:
     - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
     - Working directory: `/opt/fastapi-tutorial`
     - Action: `:run` (runs on every Chef run — no idempotency guard)

   - **Enables and starts PostgreSQL service** via `service[postgresql]`:
     - Actions: `enable`, `start`

   - **Provisions PostgreSQL database and user** via `execute[create_db_user]`:
     - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
       1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';` (idempotent via `|| true`)
       2. `CREATE DATABASE fastapi_db OWNER fastapi;` (idempotent via `|| true`)
       3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;` (idempotent via `|| true`)
     - Action: `:run` (runs on every Chef run)

   - **Writes `.env` file** to `/opt/fastapi-tutorial/.env`:
     - Content (inline heredoc):
       ```
       PROJECT_NAME="FastAPI Tutorial"
       API_VERSION=1.0.0
       DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
       ```
     - Owner: `root`, Group: `root`, Mode: `0644`

   - **Writes systemd unit file** to `/etc/systemd/system/fastapi-tutorial.service`:
     - Content (inline heredoc):
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
     - **Notifies**: triggers `execute[systemd_reload]` immediately when file changes

   - **Reloads systemd** via `execute[systemd_reload]`:
     - Command: `systemctl daemon-reload`
     - Action: `:nothing` (only runs when notified by the service file resource above)

   - **Enables and starts the fastapi-tutorial service** via `service[fastapi-tutorial]`:
     - Actions: `enable`, `start`

   - **Resources summary**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — required for cloning the application repository
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL additional extensions
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (enforced via systemd `After=postgresql.service`)
- `fastapi-tutorial.service` — the application service managed by this cookbook

**Supported platforms**: Ubuntu >= 18.04, CentOS >= 7.0

---

## Credentials

**Detection Summary**: 2 credentials detected across 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe source code

### PostgreSQL Application User Password

- **Variable(s)**: `'fastapi_password'` (literal string, appears twice)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — plain-text string literal in the recipe
- **Usage context**:
  1. Used in the `execute[create_db_user]` resource to create the PostgreSQL role: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. Used in the `file[/opt/fastapi-tutorial/.env]` resource to write the `DATABASE_URL` environment variable: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`

  > ⚠️ **Security risk**: This password is stored in plain text in the recipe, in the `.env` file on disk (mode `0644`, readable by all users), and embedded in the database connection string. During Ansible migration, this credential **must** be moved to Ansible Vault, AAP Credentials, or an external secrets manager.

### DATABASE_URL Connection String

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written to `/opt/fastapi-tutorial/.env`)
- **Current storage**: Hardcoded — written inline as file content in the recipe; stored on disk at `/opt/fastapi-tutorial/.env` with mode `0644`
- **Usage context**: Read by the FastAPI application at runtime to connect to the PostgreSQL database. The `.env` file is loaded by the application (likely via `python-dotenv` or similar). Contains the full connection string including host, database name, username, and password.

  > ⚠️ **Security risk**: The `.env` file is world-readable (`0644`). During Ansible migration, the file permissions should be tightened to `0600` or `0640`, and the password should be injected from a vault rather than hardcoded.

---

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
- Unix sockets: none
- Network interfaces: FastAPI binds to all interfaces (`0.0.0.0:8000`)

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (single application instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single application instance)

---

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
# 2. Application directory and git repository
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owned by root:root, mode drwxr-xr-x

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/
# Expected: directory exists with bin/, lib/, include/ subdirectories

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x (same as system python3)

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|sqlalchemy|psycopg2|pydantic'
# Expected: fastapi, uvicorn, and other dependencies listed with version numbers

/opt/fastapi-tutorial/venv/bin/pip check
# Expected: No broken requirements

# ─────────────────────────────────────────────
# 4. Environment configuration file
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'PROJECT_NAME' /opt/fastapi-tutorial/.env
# Expected: PROJECT_NAME="FastAPI Tutorial"

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ─────────────────────────────────────────────
# 5. Systemd unit file
# ─────────────────────────────────────────────
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... /etc/systemd/system/fastapi-tutorial.service

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
# Expected: no output (no errors)

# ─────────────────────────────────────────────
# 6. PostgreSQL service status
# ─────────────────────────────────────────────
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432 with postgres process

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN <pid>/postgres

# ─────────────────────────────────────────────
# 7. PostgreSQL database and user provisioning
# ─────────────────────────────────────────────
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

# ─────────────────────────────────────────────
# 8. FastAPI application service status (fastapi-tutorial)
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
# 9. Network port verification (fastapi-tutorial on 8000)
# ─────────────────────────────────────────────
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000 with uvicorn process

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN <pid>/uvicorn

lsof -i :8000
# Expected: uvicorn process listed

# ─────────────────────────────────────────────
# 10. Application HTTP health checks (fastapi-tutorial)
# ─────────────────────────────────────────────
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 307 redirect depending on app routing)

curl -s http://localhost:8000/docs | grep -i 'swagger\|fastapi'
# Expected: HTML content containing Swagger UI or FastAPI references

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307), server: uvicorn

# ─────────────────────────────────────────────
# 11. Application logs (fastapi-tutorial)
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial --no-pager -n 50
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial --no-pager -n 100 | grep -iE 'error|critical|traceback'
# Expected: no output (no errors)

journalctl -u fastapi-tutorial --no-pager -n 5
# Expected: "Application startup complete." or similar uvicorn startup message

journalctl -u postgresql --no-pager -n 20
# Expected: PostgreSQL startup messages, no errors

# ─────────────────────────────────────────────
# 12. Resource usage (fastapi-tutorial)
# ─────────────────────────────────────────────
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: VmRSS in MB range, Threads >= 1
```