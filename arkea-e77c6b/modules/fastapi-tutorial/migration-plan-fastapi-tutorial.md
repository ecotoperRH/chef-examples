---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI application backed by a local PostgreSQL database. It installs Python and PostgreSQL prerequisites, synchronizes the FastAPI tutorial repository into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application requirements, creates PostgreSQL role `fastapi` and database `fastapi_db`, writes the application environment file, and enables a root-run systemd service listening on TCP port `8000`.

## Service Type and Instances

**Service Type**: Application Server with PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI/Uvicorn application systemd service
  - Location/Path: `/opt/fastapi-tutorial`
  - Python environment: `/opt/fastapi-tutorial/venv`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Port/Socket: TCP `8000`
  - Bind address: `0.0.0.0`
  - Start command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Runs as: `root`
  - Restart policy: `always`
  - Database dependency: local PostgreSQL database `fastapi_db`, owned by PostgreSQL role `fastapi`

- **postgresql**: Local PostgreSQL server service
  - Location/Path: Local PostgreSQL server installation and data directory, distribution-managed
  - Port/Socket: Default local PostgreSQL TCP listener; the application connects through `localhost`
  - Key Config: Database `fastapi_db`; application role `fastapi`; application connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Service dependency: `fastapi-tutorial` starts after `postgresql.service`

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
   - Installs the required operating-system packages:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - No package versions are pinned by the cookbook.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Clones and synchronizes the application source:
     - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
     - Revision: `main`
     - Destination: `/opt/fastapi-tutorial`
     - Chef action: `sync`
   - Creates the Python virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv`.
     - The command runs only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` into `/opt/fastapi-tutorial/venv` using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
     - The Chef command runs during every converge.
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL application access as the `postgres` operating-system user:
     1. Creates PostgreSQL role `fastapi` with password `fastapi_password`.
     2. Creates database `fastapi_db` owned by `fastapi`.
     3. Grants all privileges on `fastapi_db` to `fastapi`.
     - Each SQL command ends with `|| true`, suppressing all command failures. The migration should use idempotent PostgreSQL modules rather than suppressing SQL errors.
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
   - Immediately notifies `execute[systemd_reload]` after writing the systemd unit:
     ```bash
     systemctl daemon-reload
     ```
   - Enables and starts the `fastapi-tutorial` service.
   - Iterations: None. The executed recipe contains no collection attributes or Chef `.each` loops.

**Resources**: package (1), directory (1), git (1), execute (4), service (2), file (2).

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

**Supported platforms declared by cookbook metadata**:
- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

**Migration portability note**: The recipe uses Debian/Ubuntu-oriented package names, particularly `libpq-dev` and `python3-venv`. Although the cookbook metadata declares CentOS support, the recipe does not provide OS-specific package mappings. The migrated role should define OS-family variables for PostgreSQL development and Python virtual-environment packages.

## Credentials

**Detection Summary**: 1 credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None detected
  - **Path**: None detected

### PostgreSQL Application Password
- **Variable(s)**:
  - PostgreSQL password literal: `fastapi_password`
  - PostgreSQL role: `fastapi`
  - Connection string: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded directly in the Chef recipe.
- **Usage context**:
  - Creates the PostgreSQL role `fastapi`.
  - Is embedded in the application database connection string written to `/opt/fastapi-tutorial/.env`.
  - Is used by the FastAPI application to connect to local database `fastapi_db`.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **postgresql**: Local PostgreSQL connectivity through `localhost` to database `fastapi_db` as role `fastapi`
- **fastapi-tutorial**: TCP listener on `0.0.0.0:8000`
- No Unix sockets are created or configured by this cookbook.

**Templates rendered**:
- No Chef template resources are rendered.
- Inline `.env` content written to `/opt/fastapi-tutorial/.env` — rendered once.
- Inline systemd unit content written to `/etc/systemd/system/fastapi-tutorial.service` — rendered once.

## Pre-flight checks:
```bash
# Confirm required packages are installed on Debian/Ubuntu.
dpkg-query -W -f='${binary:Package} ${Version}\n' \
  python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Confirm the deployed application directory, virtual environment, and files.
stat -c '%A %U:%G %n' /opt/fastapi-tutorial
stat -c '%A %U:%G %n' /opt/fastapi-tutorial/venv
stat -c '%A %U:%G %n' /opt/fastapi-tutorial/.env
stat -c '%A %U:%G %n' /etc/systemd/system/fastapi-tutorial.service

# Verify source checkout and expected Git revision.
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
git -C /opt/fastapi-tutorial rev-parse HEAD

# Verify the virtual environment and installed requirements.
test -x /opt/fastapi-tutorial/venv/bin/python
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip check
test -f /opt/fastapi-tutorial/requirements.txt

# Verify the postgresql instance individually.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# Verify PostgreSQL role and database individually.
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected output: fastapi

sudo -u postgres psql -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi_db

sudo -u postgres psql -d postgres -tAc \
  "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi

# Verify application-database connectivity using the configured application role.
PGPASSWORD='fastapi_password' psql \
  -h localhost -U fastapi -d fastapi_db \
  -c 'SELECT current_database(), current_user;'
# Expected output includes: fastapi_db | fastapi

# Validate exact application environment settings.
grep -Fx 'PROJECT_NAME="FastAPI Tutorial"' /opt/fastapi-tutorial/.env
grep -Fx 'API_VERSION=1.0.0' /opt/fastapi-tutorial/.env
grep -Fx 'DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db' \
  /opt/fastapi-tutorial/.env

# Validate critical systemd unit settings.
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'WorkingDirectory=/opt/fastapi-tutorial' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Environment="PATH=/opt/fastapi-tutorial/venv/bin"' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Restart=always' /etc/systemd/system/fastapi-tutorial.service

# Verify the fastapi-tutorial instance individually.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

# Verify the FastAPI process and its exact listener port.
ps -ef | grep '[u]vicorn app.main:app --host 0.0.0.0 --port 8000'
ss -ltnp | grep ':8000'
lsof -nP -iTCP:8000 -sTCP:LISTEN

# Verify FastAPI responds locally.
curl --fail --silent --show-error -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8000/docs
# Expected output: 200

curl --fail --silent --show-error http://127.0.0.1:8000/openapi.json

# Review service logs for both named instances.
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager
```