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
  - Port: `8000` (bound to `0.0.0.0`)
  - Virtual Environment: `/opt/fastapi-tutorial/venv`
  - Entry Point: `app.main:app` via `uvicorn`
  - Git Repository: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Key Config: `Type=simple`, `Restart=always`, `After=network.target postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/User: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`

---

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**: none

**Templates**: none — configuration files are written inline using Chef `file` resources

**Attributes**: none — no `attributes/default.rb` file present

**Files**: none — no static `cookbook_file` resources

---

## Module Explanation

The cookbook performs all operations in a single recipe in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):

   - **Installs system packages** (`package` resource, 7 packages):
     - `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`

   - **Creates application directory** (`directory` resource):
     - Path: `/opt/fastapi-tutorial`
     - Owner: `root`, Group: `root`, Mode: `0755`, `recursive: true`

   - **Clones application repository** (`git` resource, action: `sync`):
     - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
     - Revision: `main`
     - Destination: `/opt/fastapi-tutorial`

   - **Creates Python virtual environment** (`execute[create_venv]`):
     - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
     - Guard: `creates '/opt/fastapi-tutorial/venv'` (idempotent — only runs if venv does not exist)

   - **Installs Python dependencies** (`execute[install_dependencies]`, action: `run`):
     - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
     - Working directory: `/opt/fastapi-tutorial`

   - **Enables and starts PostgreSQL** (`service[postgresql]`):
     - Actions: `enable`, `start`

   - **Provisions PostgreSQL database and user** (`execute[create_db_user]`, action: `run`):
     - Runs three `psql` commands as the `postgres` OS user (via `sudo -u postgres`):
       1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
       2. `CREATE DATABASE fastapi_db OWNER fastapi;`
       3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
     - Each command is suffixed with `|| true` to suppress errors on re-runs (idempotent workaround)

   - **Writes `.env` configuration file** (`file[/opt/fastapi-tutorial/.env]`):
     - Destination: `/opt/fastapi-tutorial/.env`
     - Owner: `root`, Group: `root`, Mode: `0644`
     - Inline content:
       ```
       PROJECT_NAME="FastAPI Tutorial"
       API_VERSION=1.0.0
       DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
       ```

   - **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
     - Destination: `/etc/systemd/system/fastapi-tutorial.service`
     - Owner: `root`, Group: `root`, Mode: `0644`
     - Inline content defines:
       - `Description=FastAPI Tutorial Service`
       - `After=network.target postgresql.service`
       - `Type=simple`, `User=root`
       - `WorkingDirectory=/opt/fastapi-tutorial`
       - `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
       - `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
       - `Restart=always`
       - `WantedBy=multi-user.target`
     - **Notifies**: triggers `execute[systemd_reload]` immediately on file change

   - **Reloads systemd daemon** (`execute[systemd_reload]`, action: `nothing` — triggered by notification):
     - Command: `systemctl daemon-reload`
     - Only runs when the service unit file changes (`:immediately` notification)

   - **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
     - Actions: `enable`, `start`

   - **Resources**: `package` (1, 7 packages), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
   - **No iterations / loops** — single application instance, no `.each` loops present

---

## Dependencies

**External cookbook dependencies**: None (no `depends` declarations in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — source code checkout
- `postgresql` — PostgreSQL database server
- `postgresql-contrib` — PostgreSQL extension modules
- `libpq-dev` — PostgreSQL C client library headers (required for `psycopg2` compilation)

**Service dependencies**:
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (enforced via `After=` in unit file)
- `fastapi-tutorial.service` — the application systemd unit

---

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk)
- **URL**: N/A
- **Path**: N/A — credentials are written directly into the recipe and the `.env` file

### Database Password

- **Variable(s)**: `fastapi_password` (literal string used in SQL commands and `.env` content)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears as a plain-text string literal in the recipe in two places:
  1. Inside the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. Inside the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication — used to create the `fastapi` database user and to configure the application's database connection string in the `.env` file

### Database Connection URL (composite secret)

- **Variable(s)**: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (written to `/opt/fastapi-tutorial/.env` at runtime)
- **Current storage**: Hardcoded — embedded in the inline `file` resource content
- **Usage context**: Runtime environment variable consumed by the FastAPI application (via `python-dotenv` or similar) to connect to the PostgreSQL database

> ⚠️ **Security Note for Solutions Architect**: Both credentials are currently hardcoded in plain text. In the Ansible migration, these MUST be stored in Ansible Vault or an external secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager) and injected as variables. The `.env` file should be templated with `ansible.builtin.template` using a vaulted variable for the password.

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
- `0.0.0.0:8000` — uvicorn / FastAPI application (all interfaces)
- `127.0.0.1:5432` — PostgreSQL (localhost only)
- Unix sockets: none explicitly configured

**Templates rendered**:
- No `.erb` templates — configuration is written inline via `file` resources:
  - `/opt/fastapi-tutorial/.env` — written once by `file` resource
  - `/etc/systemd/system/fastapi-tutorial.service` — written once by `file` resource

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
# 2. Application directory and git clone
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/
# Expected: directory owned by root:root, mode drwxr-xr-x

ls -lah /opt/fastapi-tutorial/requirements.txt
# Expected: file present (confirms git clone succeeded)

cd /opt/fastapi-tutorial && git remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

cd /opt/fastapi-tutorial && git log --oneline -3
# Expected: recent commits from the 'main' branch

# ─────────────────────────────────────────────
# 3. Python virtual environment
# ─────────────────────────────────────────────
ls -lah /opt/fastapi-tutorial/venv/bin/python3
# Expected: symlink or binary present

ls -lah /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: uvicorn binary present (confirms pip install ran)

/opt/fastapi-tutorial/venv/bin/python3 --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2|sqlalchemy'
# Expected: fastapi, uvicorn, and database driver packages listed

# ─────────────────────────────────────────────
# 4. PostgreSQL service
# ─────────────────────────────────────────────
systemctl status postgresql
# Expected: active (running), enabled

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

# ─────────────────────────────────────────────
# 5. PostgreSQL database and user: fastapi / fastapi_db
# ─────────────────────────────────────────────
sudo -u postgres psql -c "\du fastapi"
# Expected: role 'fastapi' listed

sudo -u postgres psql -c "\l fastapi_db"
# Expected: database 'fastapi_db' listed with owner 'fastapi'

sudo -u postgres psql -c "\c fastapi_db; SELECT current_user, current_database();"
# Expected: current_database = fastapi_db

psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string returned (confirms password auth works)
# Note: will prompt for password 'fastapi_password'

sudo -u postgres psql -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
# Expected: t (true)

# ─────────────────────────────────────────────
# 6. .env configuration file
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
# 7. Systemd unit file: fastapi-tutorial.service
# ─────────────────────────────────────────────
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- root root (mode 0644)

cat /etc/systemd/system/fastapi-tutorial.service | grep -E 'ExecStart|Port|User|WorkingDirectory|Restart|After'
# Expected:
# After=network.target postgresql.service
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

systemctl cat fastapi-tutorial
# Expected: full unit file content as written by the recipe

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
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0.0.0.0:8000 LISTEN (uvicorn/python3)

lsof -i :8000
# Expected: python3 or uvicorn process listed

# ─────────────────────────────────────────────
# 10. Application HTTP health check
# ─────────────────────────────────────────────
curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307 redirect to /docs)

curl -s http://localhost:8000/docs | grep -i 'FastAPI'
# Expected: HTML containing 'FastAPI' (Swagger UI)

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

# ─────────────────────────────────────────────
# 11. Logs
# ─────────────────────────────────────────────
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -n 50 --no-pager | grep -i 'error\|critical\|traceback'
# Expected: no output (no errors)

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no errors

# ─────────────────────────────────────────────
# 12. Resource usage
# ─────────────────────────────────────────────
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "MEM%:", $4, "CPU%:", $3}'
# Expected: single process with reasonable memory usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: VmRSS in MB range, Threads: 1 (single-process uvicorn default)
```