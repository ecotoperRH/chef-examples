# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a single FastAPI Python web application (`fastapi_tutorial`) from GitHub onto a Linux host. It installs system packages (Python 3, pip, venv, git, PostgreSQL), clones the application source, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with a hardcoded database URL and password, creates a systemd unit file, and starts the `fastapi-tutorial` service on port 8000. There are no iterations or multiple instances — this is a single-instance deployment.

## Service Type and Instances

**Service Type**: Application Server (FastAPI / Python ASGI application backed by PostgreSQL)

**Configured Instances**:

- **fastapi-tutorial**: Single FastAPI application instance managed by systemd
  - Location/Path: `/opt/fastapi-tutorial`
  - Port: `8000` (TCP, all interfaces `0.0.0.0`)
  - ASGI Server: `uvicorn`, entry point `app.main:app`
  - Python venv: `/opt/fastapi-tutorial/venv`
  - Git source: `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`)
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Key Config: Runs as `root`, `Restart=always`, depends on `postgresql.service`

- **fastapi_db** (PostgreSQL database):
  - Database name: `fastapi_db`
  - Owner/user: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

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

- **Installs system packages** (`package` resource, multi-package array):
  - `python3` — Python 3 interpreter
  - `python3-pip` — pip package manager
  - `python3-venv` — venv module for virtual environments
  - `git` — required for cloning the repository
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL contrib extensions
  - `libpq-dev` — PostgreSQL C client library headers (required to compile `psycopg2`)

- **Creates application directory** (`directory` resource):
  - Path: `/opt/fastapi-tutorial`
  - Owner: `root`, Group: `root`, Mode: `0755`, `recursive: true`

- **Clones application source** (`git` resource):
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Destination: `/opt/fastapi-tutorial`
  - Revision/branch: `main`
  - Action: `:sync` (pulls latest on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if venv does not already exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` — runs on every Chef run (no idempotency guard)

- **Enables and starts PostgreSQL** (`service[postgresql]`):
  - Actions: `[:enable, :start]`
  - Enables the service at boot and starts it immediately

- **Provisions PostgreSQL database and user** (`execute[create_db_user]`):
  - Runs three `psql` commands as the `postgres` OS user via `sudo -u postgres`:
    1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
    2. `CREATE DATABASE fastapi_db OWNER fastapi;`
    3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`
  - Each command is suffixed with `|| true` to suppress errors if the user/database already exists (idempotency workaround)
  - Action: `:run` — runs on every Chef run

- **Writes `.env` configuration file** (`file[/opt/fastapi-tutorial/.env]`):
  - Destination: `/opt/fastapi-tutorial/.env`
  - Mode: `0644`, Owner: `root`, Group: `root`
  - Inline content (heredoc):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
  - Mode: `0644`, Owner: `root`, Group: `root`
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
  - **Notifies**: triggers `execute[systemd_reload]` immediately on file change

- **Reloads systemd daemon** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only runs when notified by the service file resource above

- **Enables and starts fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `[:enable, :start]`
  - Enables the systemd unit at boot and starts it immediately

- **Resources**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)
- **Total resources**: 11

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — virtual environment support
- `git` — source code cloning
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL additional modules
- `libpq-dev` — PostgreSQL development headers (for psycopg2 compilation)

**Service dependencies**:
- `postgresql.service` — must be running before `fastapi-tutorial.service` starts (enforced via `After=` in the unit file)
- `fastapi-tutorial.service` — the application systemd unit, managed by this cookbook

**Supported platforms** (from `metadata.rb`):
- Ubuntu >= 18.04
- CentOS >= 7.0

## Credentials

**Detection Summary**: 2 credentials detected in 1 file

**Source**:
- **Provider**: Hardcoded (no external secrets manager, no data bags, no Chef Vault, no CyberArk/Conjur integration detected)
- **URL**: N/A
- **Path**: N/A — credentials are written directly into the recipe and the `.env` file content

### PostgreSQL Application User Password

- **Variable(s)**: `fastapi_password` (literal string, not a variable — hardcoded in three places)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears as a plain-text string literal in:
  1. The `execute[create_db_user]` shell command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. The `file[/opt/fastapi-tutorial/.env]` heredoc content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both to create the DB user and to construct the application's database connection string embedded in the `.env` file.

### Database Connection URL (Composite Secret)

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — the full connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db` is written verbatim into the `.env` file
- **Usage context**: Read by the FastAPI application at runtime (via `python-dotenv` or equivalent) to establish the SQLAlchemy/asyncpg database connection. Contains embedded username and password.

> ⚠️ **Security Note for Solutions Architect**: Both credentials are currently hardcoded in plain text in the recipe. During Ansible migration, these MUST be moved to Ansible Vault (`ansible-vault`), AAP Credentials, or an external secrets manager (HashiCorp Vault, CyberArk). The `.env` file should be templated with variables, and the `psql` provisioning commands should use Ansible's `no_log: true` to prevent password exposure in logs.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git (confirms sync succeeded)
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)
- `/var/log/postgresql/` — PostgreSQL log directory

**Service endpoints to check**:
- `0.0.0.0:8000` — fastapi-tutorial / uvicorn (binds all interfaces)
- `127.0.0.1:5432` — PostgreSQL TCP
- `/var/run/postgresql/.s.PGSQL.5432` — PostgreSQL local Unix socket

**Templates rendered**:
- No `.erb` templates — configuration is written inline via Chef `file` resources with heredoc content:
  - `/opt/fastapi-tutorial/.env` — rendered once (single instance)
  - `/etc/systemd/system/fastapi-tutorial.service` — rendered once (single instance)

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
# 2. APPLICATION DIRECTORY AND GIT CLONE
# ============================================================
ls -lah /opt/fastapi-tutorial/
# Expected: directory exists, owner root, mode drwxr-xr-x

git -C /opt/fastapi-tutorial remote -v
# Expected: origin  https://github.com/dibanez/fastapi_tutorial.git (fetch)

git -C /opt/fastapi-tutorial branch --show-current
# Expected: main

git -C /opt/fastapi-tutorial log --oneline -3
# Expected: last 3 commits from the main branch

ls /opt/fastapi-tutorial/requirements.txt
# Expected: file exists (confirms clone succeeded)

# ============================================================
# 3. PYTHON VIRTUAL ENVIRONMENT
# ============================================================
ls -lah /opt/fastapi-tutorial/venv/bin/
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x (matches system python3)

/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'uvicorn|fastapi|sqlalchemy|psycopg2'
# Expected: fastapi, uvicorn, and database driver packages listed

ls -lh /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: file exists — confirms pip install completed successfully

# ============================================================
# 4. ENVIRONMENT CONFIGURATION FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env

cat /opt/fastapi-tutorial/.env
# Expected output:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

grep 'PROJECT_NAME' /opt/fastapi-tutorial/.env
# Expected: PROJECT_NAME="FastAPI Tutorial"

grep 'API_VERSION' /opt/fastapi-tutorial/.env
# Expected: API_VERSION=1.0.0

grep 'DATABASE_URL' /opt/fastapi-tutorial/.env
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 5. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... /etc/systemd/system/fastapi-tutorial.service

cat /etc/systemd/system/fastapi-tutorial.service
# Expected: unit file with ExecStart uvicorn on port 8000

grep 'ExecStart' /etc/systemd/system/fastapi-tutorial.service
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

grep 'After=' /etc/systemd/system/fastapi-tutorial.service
# Expected: After=network.target postgresql.service

grep 'Restart=' /etc/systemd/system/fastapi-tutorial.service
# Expected: Restart=always

systemctl cat fastapi-tutorial
# Expected: full unit file content as written by the recipe

# ============================================================
# 6. POSTGRESQL SERVICE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

ss -tlnp | grep 5432
# Expected: LISTEN 0 ... 127.0.0.1:5432 or *:5432

netstat -tulpn | grep 5432
# Expected: tcp 0 0 127.0.0.1:5432 0.0.0.0:* LISTEN ... postgres

ls -lah /var/run/postgresql/.s.PGSQL.5432
# Expected: socket file exists

# ============================================================
# 7. POSTGRESQL DATABASE AND USER - fastapi_db / fastapi user
# ============================================================
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi | ... | {}  (user listed)

sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db
# (will prompt for password: fastapi_password)

sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi user has ALL privileges

# ============================================================
# 8. FASTAPI-TUTORIAL SERVICE
# ============================================================
systemctl status fastapi-tutorial
# Expected: active (running), enabled

systemctl is-enabled fastapi-tutorial
# Expected: enabled

systemctl is-active fastapi-tutorial
# Expected: active

ps aux | grep uvicorn | grep -v grep
# Expected: process running as root with /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 9. NETWORK - port 8000 listening
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN 0 ... 0.0.0.0:8000

netstat -tulpn | grep 8000
# Expected: tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN ... uvicorn

lsof -i :8000
# Expected: uvicorn process listed on port 8000

# ============================================================
# 10. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or application-defined root response code)

curl -s http://localhost:8000/docs
# Expected: HTML page for FastAPI Swagger UI (confirms app is running)

curl -I http://localhost:8000/openapi.json
# Expected: HTTP/1.1 200 OK with Content-Type: application/json

# ============================================================
# 11. LOGS
# ============================================================
journalctl -u fastapi-tutorial -n 50 --no-pager
# Expected: uvicorn startup messages, no ERROR or CRITICAL lines

journalctl -u fastapi-tutorial -f
# Expected: live log stream showing incoming requests

journalctl -u postgresql -n 20 --no-pager
# Expected: PostgreSQL startup messages, no FATAL lines

tail -f /var/log/postgresql/postgresql-*-main.log
# Expected: PostgreSQL activity log, no authentication failures for 'fastapi' user

# ============================================================
# 12. RESOURCE USAGE
# ============================================================
ps aux | grep uvicorn | grep -v grep | awk '{print "PID:", $2, "CPU:", $3"%", "MEM:", $4"%"}'
# Expected: single uvicorn process with reasonable CPU/MEM usage

cat /proc/$(pgrep -f uvicorn)/status | grep -E 'VmRSS|VmSize|Threads'
# Expected: memory usage and thread count for the uvicorn process
```