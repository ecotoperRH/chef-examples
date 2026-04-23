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
  - Owner/user: `fastapi`
  - Password: `fastapi_password` (hardcoded)
  - Host: `localhost` (socket/loopback)

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
  - `git` — required for cloning the repository
  - `postgresql` — PostgreSQL database server
  - `postgresql-contrib` — PostgreSQL extension modules
  - `libpq-dev` — PostgreSQL C client library headers (required to compile `psycopg2`)

- **Creates application directory** `/opt/fastapi-tutorial`:
  - owner: `root`, group: `root`, mode: `0755`, recursive: `true`

- **Clones Git repository** into `/opt/fastapi-tutorial`:
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision/branch: `main`
  - Action: `sync` (pulls latest on every Chef run)

- **Creates Python virtual environment** (`execute[create_venv]`):
  - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
  - Guard: `creates '/opt/fastapi-tutorial/venv'` — only runs if the venv directory does not yet exist

- **Installs Python dependencies** (`execute[install_dependencies]`):
  - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
  - Working directory: `/opt/fastapi-tutorial`
  - Action: `:run` (runs on every Chef run — no idempotency guard)

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
  - Mode: `0644`, owner: `root`, group: `root`
  - Inline content (heredoc):
    ```
    PROJECT_NAME="FastAPI Tutorial"
    API_VERSION=1.0.0
    DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```

- **Writes systemd unit file** (`file[/etc/systemd/system/fastapi-tutorial.service]`):
  - Destination: `/etc/systemd/system/fastapi-tutorial.service`
  - Mode: `0644`, owner: `root`, group: `root`
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

- **Reloads systemd** (`execute[systemd_reload]`):
  - Command: `systemctl daemon-reload`
  - Action: `:nothing` — only runs when notified by the service file resource above

- **Enables and starts the fastapi-tutorial service** (`service[fastapi-tutorial]`):
  - Actions: `enable`, `start`

- **Resources total**: `package` (1, multi-package), `directory` (1), `git` (1), `execute` (4), `service` (2), `file` (2)

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `python3` — Python 3 interpreter
- `python3-pip` — pip package manager
- `python3-venv` — Python virtual environment support
- `git` — source code checkout
- `postgresql` — PostgreSQL RDBMS server
- `postgresql-contrib` — PostgreSQL additional modules
- `libpq-dev` — PostgreSQL development headers (for psycopg2 compilation)

**Service dependencies**:
- `postgresql.service` — must be running before the FastAPI app starts (declared in systemd `After=` directive)
- `fastapi-tutorial.service` — the application service managed by systemd

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

- **Variable(s)**: `fastapi_password` (literal string, not a node attribute)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — appears in two places:
  1. In the `execute[create_db_user]` SQL command: `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`
  2. In the `file[/opt/fastapi-tutorial/.env]` content: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Usage context**: PostgreSQL authentication password for the `fastapi` database user. Used both to create the DB user and to construct the application's database connection string embedded in the `.env` file.

### DATABASE_URL (Connection String with Embedded Credentials)

- **Variable(s)**: `DATABASE_URL` (environment variable written to `/opt/fastapi-tutorial/.env`)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded — full connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db` is written inline in the recipe
- **Usage context**: Read by the FastAPI application at runtime (via `python-dotenv` or similar) to connect to the PostgreSQL database. The `.env` file is placed at `/opt/fastapi-tutorial/.env` with mode `0644` (world-readable — a security concern to flag for the Solutions Architect).

> ⚠️ **Security Note for Solutions Architect**: The password `fastapi_password` is hardcoded in plain text in the recipe and written to a world-readable `.env` file (`mode 0644`). In the Ansible migration, this credential MUST be stored in Ansible Vault or AAP Credential Store and injected at runtime. The `.env` file permissions should be tightened to `0600` or `0640`.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/` — application root directory (owner: root, mode: 0755)
- `/opt/fastapi-tutorial/venv/` — Python virtual environment directory
- `/opt/fastapi-tutorial/venv/bin/uvicorn` — uvicorn binary (confirms pip install succeeded)
- `/opt/fastapi-tutorial/requirements.txt` — cloned from git (confirms sync succeeded)
- `/opt/fastapi-tutorial/.env` — environment configuration file (mode: 0644)
- `/etc/systemd/system/fastapi-tutorial.service` — systemd unit file (mode: 0644)
- `/var/log/postgresql/` — PostgreSQL logs (Ubuntu default location)

**Service endpoints to check**:
- `8000` — fastapi-tutorial / uvicorn (binds to `0.0.0.0:8000`)
- `5432` — PostgreSQL (binds to `127.0.0.1:5432`)
- `/var/run/postgresql/.s.PGSQL.5432` — PostgreSQL Unix domain socket

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
# Expected: directory exists, owner root, permissions drwxr-xr-x

stat -c "%a %U %G" /opt/fastapi-tutorial
# Expected: 755 root root

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
# Expected: python3, pip, uvicorn binaries present

/opt/fastapi-tutorial/venv/bin/python --version
# Expected: Python 3.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i uvicorn
# Expected: uvicorn  x.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i fastapi
# Expected: fastapi  x.x.x

/opt/fastapi-tutorial/venv/bin/pip list | grep -i psycopg2
# Expected: psycopg2 or psycopg2-binary  x.x.x

ls -lh /opt/fastapi-tutorial/venv/bin/uvicorn
# Expected: file exists and is executable

# ============================================================
# 4. POSTGRESQL SERVICE
# ============================================================
systemctl status postgresql
# Expected: active (running), enabled

systemctl is-enabled postgresql
# Expected: enabled

systemctl is-active postgresql
# Expected: active

ss -tlnp | grep 5432
# Expected: LISTEN  0  ...  127.0.0.1:5432  or  *:5432  (postgres process)

netstat -tulpn | grep 5432
# Expected: tcp  0  0  127.0.0.1:5432  0.0.0.0:*  LISTEN  (postgres)

ls -lah /var/run/postgresql/.s.PGSQL.5432
# Expected: socket file exists

# ============================================================
# 5. POSTGRESQL DATABASE AND USER (fastapi_db)
# ============================================================
sudo -u postgres psql -c "\du fastapi"
# Expected: fastapi | ... | {}  (user listed)

sudo -u postgres psql -c "\l fastapi_db"
# Expected: fastapi_db | fastapi | UTF8 | ...

sudo -u postgres psql -d fastapi_db -c "\dp"
# Expected: fastapi has ALL privileges

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
# Expected: current_user=fastapi, current_database=fastapi_db

PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
# Expected: PostgreSQL version string

# ============================================================
# 6. ENVIRONMENT FILE
# ============================================================
ls -lah /opt/fastapi-tutorial/.env
# Expected: -rw-r--r-- 1 root root ... /opt/fastapi-tutorial/.env  (mode 0644)

stat -c "%a %U %G" /opt/fastapi-tutorial/.env
# Expected: 644 root root

cat /opt/fastapi-tutorial/.env | grep PROJECT_NAME
# Expected: PROJECT_NAME="FastAPI Tutorial"

cat /opt/fastapi-tutorial/.env | grep API_VERSION
# Expected: API_VERSION=1.0.0

cat /opt/fastapi-tutorial/.env | grep DATABASE_URL
# Expected: DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# ============================================================
# 7. SYSTEMD UNIT FILE
# ============================================================
ls -lah /etc/systemd/system/fastapi-tutorial.service
# Expected: -rw-r--r-- 1 root root ... (mode 0644)

stat -c "%a %U %G" /etc/systemd/system/fastapi-tutorial.service
# Expected: 644 root root

cat /etc/systemd/system/fastapi-tutorial.service | grep ExecStart
# Expected: ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

cat /etc/systemd/system/fastapi-tutorial.service | grep -E 'After|Restart|User|WorkingDirectory'
# Expected:
#   After=network.target postgresql.service
#   User=root
#   WorkingDirectory=/opt/fastapi-tutorial
#   Restart=always

systemctl cat fastapi-tutorial
# Expected: full unit file content as written by the recipe

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
# Expected: root  ...  /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

# ============================================================
# 9. NETWORK / PORT VERIFICATION
# ============================================================
ss -tlnp | grep 8000
# Expected: LISTEN  0  ...  0.0.0.0:8000  (uvicorn process)

netstat -tulpn | grep 8000
# Expected: tcp  0  0  0.0.0.0:8000  0.0.0.0:*  LISTEN

lsof -i :8000
# Expected: uvicorn process listed

# ============================================================
# 10. APPLICATION HEALTH CHECK
# ============================================================
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/
# Expected: 200 (or 307 redirect depending on app routing)

curl -s http://localhost:8000/docs | grep -i "swagger\|openapi\|fastapi"
# Expected: FastAPI auto-generated OpenAPI docs page content

curl -s http://localhost:8000/openapi.json | python3 -m json.tool | grep '"title"'
# Expected: "title": "FastAPI Tutorial"

curl -I http://localhost:8000/
# Expected: HTTP/1.1 200 OK (or 307), server: uvicorn

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
# Expected: connection accepted messages, no ERROR lines

# ============================================================
# 12. SYSTEMD DAEMON RELOAD VERIFICATION
# ============================================================
systemctl daemon-reload
systemctl show fastapi-tutorial | grep -E 'LoadState|ActiveState|SubState'
# Expected: LoadState=loaded, ActiveState=active, SubState=running
```