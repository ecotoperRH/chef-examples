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
  - ASGI server: `uvicorn` (`app.main:app`)
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Run as user: `root`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Database owner/user: `fastapi`
  - Password: `fastapi_password` (hardcoded — see Credentials section)
  - Host: `localhost`
  - PostgreSQL service: managed by systemd (`postgresql`)

---

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
```

**Recipes:**
```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers:**
```
(none)
```

**Templates:**
```
(none — configuration files are written inline via Chef file resources)
```

**Attributes:**
```
(none — no attributes/default.rb file present)
```

**Files:**
```
(none — no static cookbook_file resources)
```

---

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (single `package` resource, all at once):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — virtual environment support
  - `git` — required for repository cloning
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (needed for `psycopg2` compilation)
  - Resources: package (1)

- **Creates application directory** `/opt/fastapi-tutorial`:
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`
  - Resources: directory (1)

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Branch/revision: `main`
  - Action: `sync` (pulls latest changes on each Chef run)
  - Resources: git (1)

- **Creates Python virtual environment** at `/opt/fastapi-tutorial/venv`:
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Idempotent guard: `creates '/opt/fastapi-tutorial/venv'` (skips if venv already exists)
  - Resources: execute (1)

- **Installs Python dependencies** from `requirements.txt`:
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — no idempotency guard)
  - Resources: execute (1)

- **Enables and starts PostgreSQL service**:
  - Service name: `postgresql`
  - Actions: `enable`, `start`
  - Resources: service (1)

- **Provisions PostgreSQL database and user** (idempotent via `|| true`):
  - Command runs three `psql` statements as the `postgres` OS user:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each statement uses `|| true` to suppress errors if objects already exist
  - Resources: execute (1)

- **Writes `.env` configuration file** to `/opt/fastapi-tutorial/.env`:
  - Content (inline heredoc):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```
  - Owner: `root`, Group: `root`, Mode: `0644`
  - Resources: file (1)

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
  - **Notifies**: triggers `execute[systemd_reload]` immediately on file change
  - Resources: file (1)

- **Reloads systemd daemon** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only runs when notified by the service file resource above
  - Resources: execute (1, conditional)

- **Enables and starts fastapi-tutorial service**:
  - Service name: `fastapi-tutorial`
  - Actions: `enable`, `start`
  - Resources: service (1)

**Total resources in recipe**: package (1), directory (1), git (1), execute (4), service (2), file (2) = **11 resources**

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment module
- `git` — source code cloning
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL contrib extensions
- `libpq-dev` — PostgreSQL development headers (for psycopg2 build)

**Service dependencies**:
- `postgresql.service` — must be running before FastAPI app starts (declared in systemd `After=` directive)
- `fastapi-tutorial.service` — the application service itself

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in recipe source code

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a variable)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both to create the DB user and to construct the application's database connection string written to `/opt/fastapi-tutorial/.env`.

> ⚠️ **Migration Note for Solutions Architect**: This password is hardcoded in plain text in the recipe. During Ansible migration, this credential MUST be moved to Ansible Vault, AAP Credentials, or an external secrets manager (HashiCorp Vault, CyberArk, AWS Secrets Manager). The `.env` file should be templated with a variable reference, and the PostgreSQL provisioning task should use the same variable. The `.env` file is also written with mode `0644` (world-readable) — consider tightening to `0600` or `0640` during migration.

---

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)

**Service endpoints to check**:
- `0.0.0.0:8000` (TCP) — fastapi-tutorial / uvicorn
- `127.0.0.1:5432` or `0.0.0.0:5432` (TCP) — PostgreSQL
- Unix sockets: None

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources:
  - `/opt/fastapi-tutorial/.env` — rendered once (inline heredoc)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (inline heredoc)

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SYSTEM PACKAGES - verify all 7 packages are installed
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
# 2. APPLICATION DIRECTORY AND GIT REPOSITORY
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owner root, mode drwxr-xr-x

stat -c "%a %U %G" /opt/fastapi-tutorial
# Expected: 755 root root

git -C /opt/fastapi-tutorial remote -v
# Expected: origin https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from the main branch

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip --version
# Expected: pip x.x.x from /opt/fastapi-tutorial/venv/...

/opt/fastapi-tutorial/venv/bin/uvicorn --version
# Expected: Running uvicorn x.x.x with CPython x.x.x on Linux

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

# ============================================================
# 4. POSTGRESQL SERVICE AND DATABASE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

# Verify port 5432 is listening
ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or 0.0.0.0:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN ... postgres

# Verify database user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi | ... | {}

# Verify database 'fastapi_db' exists and is owned by 'fastapi'
sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

# Verify privileges on fastapi_db
sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi user has ALL privileges

# Test connection as fastapi user to fastapi_db
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 5. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env (mode 0644)

stat -c "%a %U %G" /opt/fastapi-tutorial/.env
# Expected: 644 root root

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
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

stat -c "%a %U %G" /etc/systemd/system/fastapi-tutorial.service
# Expected: 644 root root

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000, After=postgresql.service

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart=' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

# Verify systemd has loaded the unit (daemon-reload was run)
systemctl cat fastapi-tutorial
# Expected: unit file content displayed without errors

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
# Expected: root ... /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 8. NETWORK - PORT 8000 LISTENING
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN ... uvicorn

lsof -i :8000
# Expected: uvicorn process listed on port 8000

# ============================================================
# 9. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 404 if no root route — check /docs instead)

curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/docs
# Expected: 200 (FastAPI auto-generated Swagger UI)

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

curl -I http://localhost:8000/docs
# Expected: HTTP/1.1 200 OK, content-type: text/html

# ============================================================
# 10. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, "Application startup complete", no ERROR lines

journalctl -u fastapi-tutorial -n 10 --no-pager | grep -i 'started\|running\|startup complete'
# Expected: "Application startup complete." or "Started FastAPI Tutorial Service."

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, "database system is ready to accept connections"

journalctl -u fastapi-tutorial --since "5 minutes ago" --no-pager | grep -i error
# Expected: no output (no errors in last 5 minutes)

# ============================================================
# 11. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```