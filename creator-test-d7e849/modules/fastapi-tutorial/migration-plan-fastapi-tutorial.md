---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI application server named **fastapi-tutorial** and a local PostgreSQL database. It installs Python, Git, PostgreSQL, and PostgreSQL development dependencies; clones the application into `/opt/fastapi-tutorial`; creates a Python virtual environment; installs Python requirements; creates PostgreSQL user `fastapi` and database `fastapi_db`; writes a hardcoded `.env` database connection string; and enables a systemd-managed Uvicorn service listening on TCP port **8000**.

## Service Type and Instances

**Service Type**: Application Server with local Database dependency

**Configured Instances**:
- **fastapi-tutorial**: FastAPI/Uvicorn application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Network binding: `0.0.0.0`
  - Port: `8000`
  - Process user: `root`
  - Restart policy: `always`
  - Environment file written by Chef: `/opt/fastapi-tutorial/.env`

- **postgresql**: Local PostgreSQL database service
  - Service name: `postgresql`
  - Database: `fastapi_db`
  - Database owner: `fastapi`
  - Database user: `fastapi`
  - Database host used by the application: `localhost`
  - Default PostgreSQL port expected by the connection URL: `5432`
  - Privilege: `fastapi` receives `ALL PRIVILEGES ON DATABASE fastapi_db`

## File Structure

**Recipes:**
```text
recipes/default.rb
```

**Providers:**
```text
None.
```

**Templates:**
```text
None. The cookbook uses inline content in file resources rather than ERB templates.
```

**Attributes:**
```text
None.
```

**Files:**
```text
None.
```

## Module Explanation

The cookbook performs operations in this order. There are no `include_recipe` calls, Chef attribute files, collection attributes, or `.each` loops; all work is performed by the entry recipe.

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following system packages using one Chef `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - No package versions are pinned by Chef.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the Python virtual environment with:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
     The command runs only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs Python dependencies on every Chef convergence using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi`, database `fastapi_db`, and grants `ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi` by running the following commands as operating-system user `postgres`:
     ```bash
     sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true
     sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true
     sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true
     ```
     The `|| true` suffix suppresses all failures and should not be reproduced during migration; use PostgreSQL-aware automation with explicit idempotency and error handling.
   - Creates `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and Chef mode `0644`. Its inline content is:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
     Migration should protect the database credential and deploy this file with mode `0600`.
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`. Its inline content is:
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
   - Declares a `systemctl daemon-reload` execute resource with action `:nothing`. The systemd unit file notifies this resource immediately when the unit changes.
   - Enables and starts the `fastapi-tutorial` systemd service.
   - Resources: package (1), directory (1), git (1), execute (3), file (2), service (2).

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
- `postgresql` must be enabled and started before PostgreSQL role and database initialization.
- `fastapi-tutorial` is enabled and started after its systemd unit is deployed and systemd is reloaded.
- The `fastapi-tutorial` unit declares `After=network.target postgresql.service`; this provides startup ordering but does not require PostgreSQL to be active.
- Supported platforms declared by metadata:
  - Ubuntu `>= 18.04`
  - CentOS `>= 7.0`

## Credentials

**Detection Summary**: 1 logical credential detected across 1 file. The same hardcoded PostgreSQL password is used in both database-role creation and the application connection URL.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### PostgreSQL Password for `fastapi`
- **Variable(s)**:
  - Literal password: `fastapi_password`
  - Connection setting: `DATABASE_URL`
  - Database URL value: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded inline in the Chef recipe.
- **Usage context**:
  - Creates PostgreSQL role `fastapi` using `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`.
  - Authenticates the FastAPI application to database `fastapi_db` through `/opt/fastapi-tutorial/.env`.
- **Migration recommendation**:
  - Store the password in Ansible Automation Platform credentials, Ansible Vault, or an external secret manager.
  - Use one protected variable, such as `fastapi_db_password`, for both PostgreSQL user creation and `DATABASE_URL`.
  - Set `no_log: true` on database-user tasks and tasks that render `/opt/fastapi-tutorial/.env`.
  - Deploy `/opt/fastapi-tutorial/.env` with mode `0600` and owner/group `root`.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk/Conjur calls, HashiCorp Vault calls, AWS Secrets Manager calls, or TLS certificate/key references were detected.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**:
  - TCP port: `8000`
  - Bind address: `0.0.0.0`
  - Local validation URL: `http://127.0.0.1:8000/`
- **postgresql**:
  - Host used by application: `localhost`
  - TCP port implied by PostgreSQL connection URL: `5432`
  - Database: `fastapi_db`
  - Database role: `fastapi`

**Templates rendered**:
- None. Chef renders no ERB templates.
- Chef writes two files from inline content:
  - `/opt/fastapi-tutorial/.env` — one time.
  - `/etc/systemd/system/fastapi-tutorial.service` — one time.

## Pre-flight checks:
```bash
# Confirm required packages are installed.
# Ubuntu/Debian:
dpkg-query -W -f='${binary:Package} ${Version}\n' \
  python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# RHEL/CentOS:
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Verify the fastapi-tutorial application checkout and virtual environment.
test -d /opt/fastapi-tutorial
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version
test -f /opt/fastapi-tutorial/requirements.txt
/opt/fastapi-tutorial/venv/bin/pip freeze

# Verify the postgresql instance is enabled and active.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# Verify PostgreSQL role fastapi exists.
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected output: fastapi

# Verify database fastapi_db exists and is owned by fastapi.
sudo -u postgres psql -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi_db

sudo -u postgres psql -d postgres -tAc \
  "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi

# Validate direct authenticated PostgreSQL connectivity.
# Supply the password from the protected Ansible/AAP credential; do not place it in shell history.
PGPASSWORD="${FASTAPI_DB_PASSWORD}" \
  psql -h localhost -U fastapi -d fastapi_db -c \
  "SELECT current_database(), current_user;"
# Expected result: current_database = fastapi_db; current_user = fastapi

# Confirm PostgreSQL listens on port 5432.
ss -ltnp | grep ':5432'
# Expected: PostgreSQL listener on port 5432.

# Verify the fastapi-tutorial environment file.
test -f /opt/fastapi-tutorial/.env
stat -c '%a %U:%G %n' /opt/fastapi-tutorial/.env
# Recommended expected mode after migration: 600 root:root
grep -E '^(PROJECT_NAME|API_VERSION)=' /opt/fastapi-tutorial/.env
# Expected values:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0

# Confirm DATABASE_URL is configured without printing its embedded password.
grep -q '^DATABASE_URL=postgresql://' /opt/fastapi-tutorial/.env
echo "DATABASE_URL is present"

# Validate the fastapi-tutorial systemd unit.
test -f /etc/systemd/system/fastapi-tutorial.service
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
systemctl cat fastapi-tutorial
systemctl show fastapi-tutorial \
  --property=User,WorkingDirectory,ExecStart,Restart,After,WantedBy

# Verify the fastapi-tutorial instance is enabled and active.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

# Confirm Uvicorn listens on the exact configured port, 8000.
ss -ltnp | grep ':8000'
# Expected: a Uvicorn/Python listener on port 8000.

# Verify the FastAPI service accepts an HTTP connection.
# The cookbook does not define a dedicated health endpoint.
curl --connect-timeout 5 --max-time 10 -sS -o /dev/null \
  -w 'fastapi-tutorial HTTP status: %{http_code}\n' \
  http://127.0.0.1:8000/
# Expected: a non-000 HTTP status.

# Inspect logs for postgresql and fastapi-tutorial.
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager

# Confirm the FastAPI process command includes the configured application and port.
ps -ef | grep '[u]vicorn app.main:app --host 0.0.0.0 --port 8000'
```