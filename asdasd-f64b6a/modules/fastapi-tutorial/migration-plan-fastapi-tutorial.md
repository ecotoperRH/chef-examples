---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, PostgreSQL), creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and credentials, creates a systemd service unit, and starts the `fastapi-tutorial` service listening on port 8000.

## Service Type and Instances

**Service Type**: Application Server (Python/FastAPI ASGI web application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Port/Socket: TCP port **8000** (bound to `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - Source Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Systemd Unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment File: `/opt/fastapi-tutorial/.env`
  - Key Config: Runs as `root`, ASGI server is `uvicorn`, restarts always on failure, depends on `postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (**hardcoded**)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: (none)

**Templates**: (none — configuration content is inlined directly in file resources)

**Attributes**: (none — no attributes/default.rb file present)

## Module Explanation

The cookbook performs all operations in a single recipe executed in this order:

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

- **Installs system packages** (`package` resource, 7 packages):
  - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

- **Creates application directory** (`directory` resource):
  - Path: `/opt/fastapi-tutorial`
  - Owner: `root`, Group: `root`, Mode: `0755`, recursive: `true`

- **Clones source repository** (`git` resource):
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/Branch: `main`
  - Destination: `/opt/fastapi-tutorial`
  - Action: `:sync` (pulls latest on every run)

- **Creates Python virtual environment** (`execute 'create_venv'`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` (idempotent — only runs if venv does not exist)

- **Installs Python dependencies** (`execute 'install_dependencies'`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef converge — no idempotency guard)

- **Enables and starts PostgreSQL** (`service 'postgresql'`):
  - Actions: `:enable`, `:start`

- **Provisions PostgreSQL database and user** (`execute 'create_db_user'`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres psql`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';` (with `|| true` to suppress duplicate errors)
    2. `CREATE DATABASE fastapi_db OWNER fastapi;` (with `|| true`)
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;` (with `|| true`)
  - Action: `:run` (runs on every Chef converge — no idempotency guard)

- **Writes `.env` configuration file** (`file '/opt/fastapi-tutorial/.env'`):
  - Destination: `/opt/fastapi-tutorial/.env`
  - Mode: `0644`, Owner: `root`, Group: `root`
  - Inline content:
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd service unit** (`file '/etc/systemd/system/fastapi-tutorial.service'`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
  - Mode: `0644`, Owner: `root`, Group: `root`
  - Key fields:
    - `Description`: FastAPI Tutorial Service
    - `After`: `network.target postgresql.service`
    - `Type`: `simple`
    - `User`: `root`
    - `WorkingDirectory`: `/opt/fastapi-tutorial`
    - `Environment`: `PATH=/opt/fastapi-tutorial/venv/bin`
    - `ExecStart`: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
    - `Restart`: `always`
  - **Notifies**: triggers `execute[systemd_reload]` immediately on file change

- **Reloads systemd** (`execute 'systemd_reload'`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` (only runs when notified by the service unit file resource above)

- **Enables and starts fastapi-tutorial service** (`service 'fastapi-tutorial'`):
  - Actions: `:enable`, `:start`

- **Resources total**: `package` (1), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2) = **11 resources**

## Dependencies

**External cookbook dependencies**: None declared in metadata.rb (no metadata.rb found)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — source code checkout
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (enforced via systemd `After=` directive)
- `fastapi-tutorial.service` — the application ASGI server managed by systemd

## Credentials

**Detection Summary**: 2 credentials detected in 1 file (`cookbooks/fastapi-tutorial/recipes/default.rb`)

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are embedded directly in recipe source code

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a variable)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: **Hardcoded** — appears in three locations within the same recipe:
  1. In the `execute 'create_db_user'` shell command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file '/opt/fastapi-tutorial/.env'` inline content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication for the `fastapi` database user connecting to `fastapi_db`. Also embedded in the application's runtime `DATABASE_URL` environment variable read by the FastAPI app via the `.env` file.

> ⚠️ **Security Risk**: This password is stored in plaintext in the recipe, in the `.env` file on disk (mode `0644`, world-readable), and in the PostgreSQL connection string. The Ansible migration MUST replace this with an Ansible Vault secret or an external secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager). The `.env` file permissions should also be tightened to `0600` and ownership changed from `root:root` to the service account.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory
- `/opt/fastapi-tutorial/venv/` — Python virtual environment
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — ASGI server binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git, must exist before pip install
- `/opt/fastapi-tutorial/app/main.py` — FastAPI application entry point (cloned from git)
- `/opt/fastapi-tutorial/.env` — environment configuration file
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file

**Service endpoints to check**:
- Ports listening: **8000** (uvicorn, bound to `0.0.0.0`)
- Unix sockets: None
- Network interfaces: All interfaces (`0.0.0.0`)

**Templates rendered**:
- No `.erb` templates — all file content is inlined in the recipe
- `file '/opt/fastapi-tutorial/.env'` — rendered once (inline content)
- `file '/etc/systemd/system/fastapi-tutorial.service'` — rendered once (inline content)

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
# 2. Application directory and source code
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owned by root:root, mode drwxr-xr-x

ls -lah /opt/fastapi-tutorial/app/main.py
# Expected: file exists (git clone succeeded)

ls -lah /opt/fastapi-tutorial/requirements.txt
# Expected: file exists (git clone succeeded)

git -C /opt/fastapi-tutorial remote -v
# Expected: origin https://github.com/dibanez/fastapi_tutorial.git (fetch/push)

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: recent commits from 'main' branch

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/bin/python3
# Expected: symlink or binary exists

/opt/fastapi-tutorial/venv/bin/python3 --version
# Expected: Python 3.x.x

ls -lah /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: uvicorn binary exists (pip install succeeded)

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

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
# 5. PostgreSQL database and user provisioning
# ─────────────────────────────────────────────
# Verify user 'fastapi' exists
sudo -u postgres psql -c "\du fastapi"
# Expected: role 'fastapi' listed

# Verify database 'fastapi_db' exists and is owned by 'fastapi'
sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

# Verify privileges
sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi has ALL privileges on fastapi_db

# Test application user connectivity
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

# ─────────────────────────────────────────────
# 6. Environment configuration file
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
# 7. Systemd service unit file
# ─────────────────────────────────────────────
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- root root (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service | grep -E 'ExecStart|User|WorkingDirectory|Restart|After'
# Expected:
# After=network.target postgresql.service
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

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
# Expected: process running as root with 'uvicorn app.main:app --host 0.0.0.0 --port 8000'

# ─────────────────────────────────────────────
# 9. Network port verification
# ─────────────────────────────────────────────
ss -tlnp | grep ':8000'
# Expected: LISTEN 0 ... 0.0.0.0:8000 ... users:(("uvicorn",...))

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN <pid>/uvicorn

lsof -i :8000
# Expected: uvicorn process listed on port 8000

# ─────────────────────────────────────────────
# 10. Application health check
# ─────────────────────────────────────────────
curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307 redirect to /docs)

curl -s http://localhost:8000/docs | grep -i 'fastapi'
# Expected: HTML containing FastAPI Swagger UI

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ─────────────────────────────────────────────
# 11. Logs
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -iE 'error|critical|traceback'
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL started successfully, no errors

# ─────────────────────────────────────────────
# 12. Resource usage
# ─────────────────────────────────────────────
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "RSS:", $6/1024 "MB"}'
# Expected: single uvicorn process with reasonable memory usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'Threads|VmRSS|VmSize'
# Expected: Threads: 1+, VmRSS: <500MB
```