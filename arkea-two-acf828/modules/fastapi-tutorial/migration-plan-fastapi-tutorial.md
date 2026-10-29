---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` FastAPI/Uvicorn web API application at `/opt/fastapi-tutorial` and a local PostgreSQL database named `fastapi_db`. It installs Python, Git, PostgreSQL, and required build/client packages; clones the application from GitHub; creates a Python virtual environment; installs Python requirements; creates the `fastapi` PostgreSQL role and `fastapi_db` database; writes a `.env` database connection string; and enables and starts both PostgreSQL and the `fastapi-tutorial` systemd service. The FastAPI process listens on `0.0.0.0:8000`.

## Service Type and Instances

**Service Type**: Application Server / Web API backed by PostgreSQL

**Configured Instances**:
- **fastapi-tutorial**: FastAPI/Uvicorn application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Runtime: Python 3 virtual environment at `/opt/fastapi-tutorial/venv`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Key Config: Systemd service `fastapi-tutorial.service`; runs as `root`; restart policy is `always`; command is `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`; PATH is `/opt/fastapi-tutorial/venv/bin`

- **PostgreSQL**: Local database service for the FastAPI application
  - Location/Path: PostgreSQL package/platform default data and configuration paths
  - Port/Socket: TCP `5432` by package default; the cookbook does not explicitly configure a PostgreSQL port or socket path
  - Key Config: Service `postgresql`; database `fastapi_db`; database role and owner `fastapi`; application endpoint `localhost`; application connection string is `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

**Recipes:**
```text
recipes/default.rb
```

**Providers:**
```text
```

**Templates:**
```text
```

**Attributes:**
```text
```

**Files:**
```text
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs system packages using one Chef `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Does not pin package versions.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes the application Git repository:
     - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
     - Destination: `/opt/fastapi-tutorial`
     - Revision: `main`
     - Chef action: `sync`
   - Creates the Python virtual environment using `execute[create_venv]`:
     - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
     - Guard: skips execution when `/opt/fastapi-tutorial/venv` already exists.
   - Installs application dependencies using `execute[install_dependencies]`:
     - Working directory: `/opt/fastapi-tutorial`
     - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
     - This command runs on every Chef converge.
   - Enables and starts the `postgresql` service using `service[postgresql]`.
   - Creates the PostgreSQL role, database, and privilege grant using `execute[create_db_user]`, in this exact order:
     1. Creates role `fastapi` with password `fastapi_password`.
     2. Creates database `fastapi_db` owned by `fastapi`.
     3. Grants `ALL PRIVILEGES` on database `fastapi_db` to `fastapi`.
     - Each SQL command uses `|| true`, which suppresses all errors. Ansible migration should use idempotent PostgreSQL modules rather than reproducing this behavior.
   - Writes `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`:
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
   - Reloads the systemd manager using `execute[systemd_reload]`:
     - Command: `systemctl daemon-reload`
     - Default action: `nothing`
     - Trigger: Immediate notification when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service using `service[fastapi-tutorial]`.
   - Resources: package (1), directory (1), git (1), execute (4), file (2), service (2).
   - Iterations: None.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

**Service dependencies**:
- `postgresql`
- `fastapi-tutorial`

**Application source dependency**:
- Git repository: `https://github.com/dibanez/fastapi_tutorial.git`
- Branch/revision: `main`

**Supported operating systems**:
- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

## Credentials

**Detection Summary**: 1 distinct hardcoded database credential detected in 1 file, used in two places.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: Not applicable
  - **Path**: Not applicable

### PostgreSQL Application Password

- **Variable(s)**:
  - SQL literal password: `fastapi_password`
  - Connection-string setting: `DATABASE_URL`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded directly in the Chef recipe.
- **Usage context**:
  - Creates PostgreSQL role `fastapi` with password `fastapi_password`.
  - Writes the same password into `/opt/fastapi-tutorial/.env` as part of `DATABASE_URL`.
  - The FastAPI application uses the connection URL to authenticate to database `fastapi_db` on `localhost`.

## Checks for the Migration

**Files to verify**:
- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/.git`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/uvicorn`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**: TCP `8000` on `0.0.0.0`
- **PostgreSQL**: TCP `5432` when using the standard package default; verify the actual active port because the cookbook does not configure one explicitly.
- **PostgreSQL Unix socket**: Package/platform default socket path; the cookbook does not configure a socket path.

**Templates rendered**:
- None; render count: `0`. The cookbook uses inline Chef `file` resource content rather than templates.

## Pre-flight checks:
```bash
# ----- PostgreSQL instance -----

# Verify that PostgreSQL is enabled and active.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# Verify that the PostgreSQL server process is running.
ps aux | grep '[p]ostgres'

# Confirm that PostgreSQL role fastapi exists.
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected output: fastapi

# Confirm that database fastapi_db exists and is owned by fastapi.
sudo -u postgres psql -tAc \
  "SELECT datname || ':' || pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi_db:fastapi

# Confirm that role fastapi can authenticate to database fastapi_db.
PGPASSWORD='fastapi_password' \
  psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_database(), current_user;"
# Expected output identifies fastapi_db and fastapi.

# Confirm PostgreSQL is listening on the expected default TCP port.
ss -tlnp | grep ':5432'

# Review PostgreSQL logs.
journalctl -u postgresql -n 100 --no-pager


# ----- fastapi-tutorial instance -----

# Verify application directory, Git checkout, requirements file, and virtual environment.
test -d /opt/fastapi-tutorial
test -d /opt/fastapi-tutorial/.git
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
/opt/fastapi-tutorial/venv/bin/python --version

# Confirm the expected source repository and branch.
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
# Expected branch: main

# Verify that the environment file exists and has secure expected ownership and permissions.
test -f /opt/fastapi-tutorial/.env
stat -c '%a %U:%G %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env \
  | sed -E 's#(postgresql://[^:]+:)[^@]+#\1REDACTED#'
# Chef-equivalent permissions are 644 root:root. A secure Ansible migration should use 600 root:root.

# Verify that the systemd unit exists, is enabled, and is active.
test -f /etc/systemd/system/fastapi-tutorial.service
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

# Verify the expected Uvicorn command and unit configuration.
systemctl show fastapi-tutorial --property=ExecStart --no-pager
grep -E '^(WorkingDirectory|User|Environment|ExecStart|Restart)=' \
  /etc/systemd/system/fastapi-tutorial.service
# Expected settings include:
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# Environment="PATH=/opt/fastapi-tutorial/venv/bin"
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

# Verify that the Uvicorn/FastAPI process is running and listening on TCP 8000.
ps aux | grep '[u]vicorn app.main:app'
ss -tlnp | grep ':8000'
lsof -nP -iTCP:8000 -sTCP:LISTEN
# Expected output: a listener on 0.0.0.0:8000 associated with the Uvicorn process.

# Verify application HTTP connectivity.
curl -i --max-time 10 http://127.0.0.1:8000/
curl -i --max-time 10 http://127.0.0.1:8000/docs
# Expected output: an HTTP response from the application. /docs should return HTTP 200 if FastAPI default documentation is enabled.

# Review application logs.
journalctl -u fastapi-tutorial -n 100 --no-pager
```