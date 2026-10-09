---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` FastAPI application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, PostgreSQL development libraries, and application dependencies; creates a Python virtual environment; configures the PostgreSQL role `fastapi` and database `fastapi_db`; writes an environment file; and manages the `fastapi-tutorial` systemd service. The application runs as `root`, uses Uvicorn on `0.0.0.0:8000`, and depends on the local `postgresql` service. The database password is currently hardcoded and must be migrated to Ansible Vault.

## Service Type and Instances

**Service Type**: Application Server with PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application server
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Git revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Start command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Listening address: `0.0.0.0`
  - Port: `8000`
  - Restart behavior: `Restart=always`

- **fastapi_db**: PostgreSQL application database
  - Database owner: `fastapi`
  - Database user: `fastapi`
  - PostgreSQL service: `postgresql`
  - Connection host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Granted privilege: All privileges on `fastapi_db` to `fastapi`

There are no collection attributes or `.each` loops in the cookbook.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

**Recipes:**
```text
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers:**
```text
None
```

**Templates:**
```text
None
```

**Attributes:**
```text
None
```

**Files:**
```text
None
```

The `.env` file and systemd unit are created with inline `file` resources. They are not static cookbook files or templates.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the seven required system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv` only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs dependencies with `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt` from `/opt/fastapi-tutorial`.
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates PostgreSQL database `fastapi_db` owned by `fastapi`.
   - Grants all privileges on `fastapi_db` to `fastapi`.
   - Executes PostgreSQL administrative commands as the `postgres` operating-system user.
   - The original database commands use `|| true`; the migration should replace them with idempotent `community.postgresql` modules:
     - `community.postgresql.postgresql_user`
     - `community.postgresql.postgresql_db`
     - `community.postgresql.postgresql_privs`
   - Creates `/opt/fastapi-tutorial/.env` with:
     - `PROJECT_NAME="FastAPI Tutorial"`
     - `API_VERSION=1.0.0`
     - `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
   - Sets the `.env` owner and group to `root` and its original mode to `0644`; use `0600` for the migrated file unless world-readable compatibility is required.
   - Replaces the hardcoded database password in `DATABASE_URL` with an Ansible Vault variable.
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with:
     - Description `FastAPI Tutorial Service`
     - Dependency ordering after `network.target` and `postgresql.service`
     - `Type=simple`
     - `User=root`
     - `WorkingDirectory=/opt/fastapi-tutorial`
     - `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
     - `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
     - `Restart=always`
     - `WantedBy=multi-user.target`
   - Sets the systemd unit owner and group to `root` and its mode to `0644`.
   - Defines `systemctl daemon-reload` as `execute[systemd_reload]` with action `:nothing`.
   - Immediately notifies the systemd reload when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service after the unit is installed and systemd is reloaded.
   - Iterations: None; no `.each` loops are present.

## Dependencies

**External cookbook dependencies**: None declared in the supplied `metadata.rb`.

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

**Application dependency source**: `/opt/fastapi-tutorial/requirements.txt`

The requirements file is obtained from the Git repository and installed into `/opt/fastapi-tutorial/venv`. Package names may require distribution-specific equivalents on RPM-based systems; the supplied recipe does not define platform-specific package mappings.

## Credentials

**Detection Summary**: 1 credential detected in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env`.

**Source**:
  - **Provider**: Hardcoded in the Chef recipe
  - **URL**: None
  - **Path**: None
  - **Related database**: `fastapi_db`

### PostgreSQL database password

- **Variable(s)**: PostgreSQL user `fastapi`; password `fastapi_password`; `DATABASE_URL`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
  - Generated file: `/opt/fastapi-tutorial/.env`
- **Current storage**: Hardcoded plaintext in the Chef recipe and generated environment file
- **Usage context**:
  - PostgreSQL `CREATE USER` command
  - FastAPI database connection string
  - PostgreSQL database ownership and privilege configuration
- **Migration storage**: Store the password in Ansible Vault.
- **Migration usage**: Use the vaulted password in the PostgreSQL user task and generate `DATABASE_URL` from the vaulted variable.
- **Security requirement**: Avoid exposing the password through command-line arguments or world-readable files. Prefer mode `0600` for `/opt/fastapi-tutorial/.env`.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, environment-variable lookups, TLS certificates, API keys, or tokens were detected.

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Database objects to verify**:

- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`
- Database owner `fastapi`
- All privileges on `fastapi_db` granted to `fastapi`

**Service endpoints to check**:

- `fastapi-tutorial`: TCP listener on `0.0.0.0:8000`
- `fastapi_db`: PostgreSQL through the local `postgresql` service at `localhost`
- Unix sockets: No explicit socket path is configured

**Templates rendered**:

- None; zero templates are rendered.
- Inline configuration files created:
  - `/opt/fastapi-tutorial/.env`: 1 file
  - `/etc/systemd/system/fastapi-tutorial.service`: 1 file

**Generated configuration files**:

- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

## Pre-flight checks:

```bash
# Package verification
if command -v dpkg >/dev/null 2>&1; then
  dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev
else
  rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev
fi

# Application instance: fastapi-tutorial
ls -ld /opt/fastapi-tutorial
ls -ld /opt/fastapi-tutorial/venv
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
/opt/fastapi-tutorial/venv/bin/pip check

# Database instance: fastapi_db
systemctl status postgresql --no-pager
systemctl is-enabled postgresql
systemctl is-active postgresql
pg_isready -h localhost

sudo -u postgres psql -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"

sudo -u postgres psql -tAc \
  "SELECT datname, pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

sudo -u postgres psql -d fastapi_db -c "\l+ fastapi_db"

PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_user, current_database();"

# Application configuration
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' \
  /opt/fastapi-tutorial/.env

# Expected configuration values:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# Systemd unit for fastapi-tutorial
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
systemctl daemon-reload
systemctl cat fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

systemctl show fastapi-tutorial \
  --property=User,WorkingDirectory,ExecStart,Restart

# Expected service settings:
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# Restart=always
# ExecStart invokes /opt/fastapi-tutorial/venv/bin/uvicorn
# The command imports app.main:app
# The command binds to 0.0.0.0:8000

# FastAPI endpoint for fastapi-tutorial
ss -tlnp | grep ':8000'
curl -i http://127.0.0.1:8000/

# Process and version checks for fastapi-tutorial
ps aux | grep '[u]vicorn app.main:app'
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/uvicorn --version

# Application logs for fastapi-tutorial
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u fastapi-tutorial -f
```

Expected results:

- The `postgresql` service is enabled, active, and accepting connections.
- PostgreSQL role `fastapi` exists.
- PostgreSQL database `fastapi_db` exists and is owned by `fastapi`.
- The `fastapi` role can connect to `fastapi_db`.
- `/opt/fastapi-tutorial/.env` contains `PROJECT_NAME`, `API_VERSION`, and `DATABASE_URL`.
- The `fastapi-tutorial` unit passes systemd validation, is enabled, and is active.
- The FastAPI process listens on `0.0.0.0:8000`.
- The FastAPI process uses `/opt/fastapi-tutorial/venv/bin/uvicorn` and imports `app.main:app`.
- Logs show successful Uvicorn startup without PostgreSQL connection, import, dependency, or repeated-restart errors.