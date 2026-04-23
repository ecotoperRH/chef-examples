# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application repository, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000. There are no iterations — this is a single-instance deployment.

---

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI web application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (bound to `0.0.0.0`)
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - ASGI Server: `uvicorn`, entry point `app.main:app`
  - Systemd Unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment File: `/opt/fastapi-tutorial/.env`
  - Key Config: `Type=simple`, `User=root`, `Restart=always`, `After=network.target postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

---

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
cookbooks/fastapi-tutorial/metadata.rb
```

---

## Module Explanation

The cookbook performs all operations in a single recipe in this order:

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
  - Owner: `root`, Group: `root`, Mode: `0755`, `recursive: true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/Branch: `main`
  - Action: `sync` (keeps the directory up to date on each Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if the venv directory does not yet exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef converge — no idempotency guard)

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
  - Inline content (three variables):
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

- **Enables and starts the fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

- **Resources total**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **No iterations** — single instance, no `.each` loops

---

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
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (enforced via `After=` in the unit file)
- `fastapi-tutorial.service` — the application systemd unit

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no Vault, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in the recipe source code

### PostgreSQL User Password

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in three places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user; also embedded in the application's database connection URL

### Database Connection URL (Composite Secret)

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written to `/opt/fastapi-tutorial/.env`)
- **Current storage**: Hardcoded — written inline as file content in the recipe
- **Usage context**: Full PostgreSQL connection string consumed by the FastAPI application at runtime via the `.env` file; contains both the username and password in plaintext

> ⚠️ **Security Note for Solutions Architect**: Both credentials are currently hardcoded in the recipe. During Ansible migration, these MUST be moved to Ansible Vault (`ansible-vault`), AAP Credentials, or an external secrets manager (e.g., HashiCorp Vault). The `.env` file task should use a Jinja2 template with variables sourced from a vault-encrypted vars file. The `mode: '0644'` on the `.env` file also exposes the password to all local users — consider tightening to `0600` and changing the `User` in the systemd unit away from `root`.

---

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/requirements.txt` — pip requirements (cloned from git)
- `/opt/fastapi-tutorial/.env` — environment configuration with `DATABASE_URL`
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file

**Service endpoints to check**:
- Port `8000` (uvicorn, bound to `0.0.0.0`)
- PostgreSQL: `5432` (localhost only, default PostgreSQL port)
- Unix sockets: none explicitly configured
- Network interfaces: `0.0.0.0:8000` (all interfaces)

**Templates rendered**:
- No `.erb` templates — all file content is inline in the recipe
- `file[/opt/fastapi-tutorial/.env]` — rendered once (single instance)
- `file[/etc/systemd/system/fastapi-tutorial.service]` — rendered once (single instance)

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES - verify all 7 packages are installed
# ============================================================
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev \
  | grep -E '^ii' | awk '{print $2, $3}'
# Expected: 7 lines, all showing 'ii' (installed) status

python3 --version
# Expected: Python 3.x.x

git --version
# Expected: git version 2.x.x

# ============================================================
# 2. APPLICATION DIRECTORY AND GIT REPOSITORY
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode 0755

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn executables present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

/opt/fastapi-tutorial/venv/bin/pip check
# Expected: No broken requirements

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running)

systemctl is-enabled postgresql
# Expected: enabled

# Verify PostgreSQL is listening on port 5432
ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

# Verify database user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: Role name 'fastapi' listed

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
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env (mode 0644)

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

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: [Unit], [Service], [Install] sections present

grep -E 'ExecStart|User|WorkingDirectory|Restart|After' /etc/systemd/system/fastapi-tutorial.service
# Expected:
# After=network.target postgresql.service
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

systemctl cat fastapi-tutorial
# Expected: shows the unit file content as loaded by systemd

# ============================================================
# 7. FASTAPI-TUTORIAL SERVICE
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

# Verify uvicorn process is running
ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 8. NETWORK - PORT 8000
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN ... uvicorn

lsof -i :8000
# Expected: uvicorn process listed

# ============================================================
# 9. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or application-defined status code, e.g., 200, 307)

curl -s http://localhost:8000/docs | grep -i "swagger\|fastapi"
# Expected: FastAPI auto-generated Swagger UI HTML

curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or redirect), server: uvicorn

# ============================================================
# 10. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -n 10 --no-pager | grep -i 'started\|running\|uvicorn'
# Expected: "Application startup complete." or "Uvicorn running on http://0.0.0.0:8000"

journalctl -u postgresql -n 20 --no-pager | grep -i 'error\|fatal'
# Expected: no output (no errors)

# ============================================================
# 11. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```