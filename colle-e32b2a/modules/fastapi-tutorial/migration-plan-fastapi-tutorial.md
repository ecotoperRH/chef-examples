---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` FastAPI application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main`. It installs Python, PostgreSQL, Git, and PostgreSQL development packages; creates a Python virtual environment; installs dependencies from `requirements.txt`; creates the PostgreSQL `fastapi` role and `fastapi_db` database; writes an environment file; and manages a systemd service running Uvicorn on port `8000`. The cookbook contains one recipe, one application instance, no loops, no external cookbook dependencies, no templates, and one hardcoded PostgreSQL credential.

## Service Type and Instances

**Service Type**: Application Server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application served by Uvicorn
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Dependency file: `/opt/fastapi-tutorial/requirements.txt`
  - Application entry point: `app.main:app`
  - Port/Socket: `0.0.0.0:8000`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Systemd service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Environment path: `/opt/fastapi-tutorial/venv/bin`
  - Restart policy: `Restart=always`
  - Service dependencies: `network.target` and `postgresql.service`

- **postgresql**: PostgreSQL database service used by the FastAPI application
  - Service name: `postgresql`
  - Managed actions: enable and start
  - Database role: `fastapi`
  - Database password: `fastapi_password`
  - Database name: `fastapi_db`
  - Database owner: `fastapi`
  - Connection host: `localhost`
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Local administration user: operating-system user `postgres`

The cookbook has no collection attributes and no `.each` iterations.

## File Structure

Only files participating in the analyzed execution flow are listed.

**Recipes:**

```text
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers:**

```text
```

No custom resources or provider files are used.

**Templates:**

```text
```

No ERB templates are rendered. The environment file and systemd unit are created using inline Chef `file` resources.

**Attributes:**

```text
```

No attribute files are used.

**Files:**

```text
```

No static files from `files/default/*` or `files/*` are deployed.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - The only executed recipe; it does not call `include_recipe`.
   - Installs the seven system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Does not specify package versions.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes the Git repository `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv` only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs Python dependencies using `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt` with `/opt/fastapi-tutorial` as the working directory.
   - Does not notify the application service when dependencies are installed.
   - Enables and starts the `postgresql` service before database initialization.
   - Creates the PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates the PostgreSQL database `fastapi_db` owned by `fastapi`.
   - Grants all privileges on `fastapi_db` to `fastapi`.
   - Performs database commands as operating-system user `postgres`.
   - Suppresses errors from the database shell commands with `|| true`; the migration should preferably use idempotent PostgreSQL modules instead.
   - Creates `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`.
   - Writes the following environment values:
     - `PROJECT_NAME="FastAPI Tutorial"`
     - `API_VERSION=1.0.0`
     - `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`.
   - Defines the `fastapi-tutorial` systemd service with:
     - `Type=simple`
     - `User=root`
     - `WorkingDirectory=/opt/fastapi-tutorial`
     - `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
     - `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
     - `Restart=always`
     - `After=network.target postgresql.service`
     - `WantedBy=multi-user.target`
   - Runs `systemctl daemon-reload` only when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service after the unit file is installed and systemd is reloaded.
   - Does not explicitly restart `fastapi-tutorial` when the repository or Python dependencies change.
   - Iterations: none.

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

**Application dependencies**:

- Python dependencies listed in `/opt/fastapi-tutorial/requirements.txt`
- Uvicorn at `/opt/fastapi-tutorial/venv/bin/uvicorn`
- Python application module `app.main:app`

**Service dependencies**:

- `postgresql`
- `network.target`

**Supported platforms from metadata**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

## Credentials

**Detection Summary**: 1 credential detected across 1 recipe file. The same credential is used in the PostgreSQL role creation command and the application database connection string.

**Source**:

- **Provider**: Hardcoded in Chef source
- **URL**: No external secret-manager URL detected
- **Path**: No data bag, Vault path, CyberArk path, or secret-manager path detected

### PostgreSQL password for the `fastapi` database role

- **Variable(s)**:
  - Password literal: `fastapi_password`
  - Database URL: `DATABASE_URL`
  - Connection value: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**:
  - Hardcoded in the `execute[create_db_user]` command
  - Hardcoded in the inline `.env` file content
- **Usage context**:
  - PostgreSQL role password for `fastapi`
  - Authentication by the FastAPI application when connecting to `fastapi_db`
- **Migration handling**:
  - Store the password in Ansible Vault or an approved secret backend.
  - Use the protected value when creating the PostgreSQL role.
  - Render the same protected value into `DATABASE_URL`.
  - Apply `no_log: true` to credential-handling tasks.
  - Review the current `.env` mode of `0644`, which makes the credential readable by all local users.

No other credentials, API keys, tokens, certificates, private keys, data bags, encrypted data bags, Chef Vault items, CyberArk integrations, Conjur variables, or secret-related attributes were detected.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/opt/fastapi-tutorial/venv`
- `/etc/systemd/system/fastapi-tutorial.service`

**Directories to verify**:

- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`

**Database objects to verify**:

- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`
- Owner of `fastapi_db`: `fastapi`
- All privileges on `fastapi_db` granted to `fastapi`

**Service endpoints to check**:

- `fastapi-tutorial`: TCP `0.0.0.0:8000`
- `postgresql`: local PostgreSQL service and platform-default local socket

**Templates rendered**:

- None; render count: `0`
- `/opt/fastapi-tutorial/.env` is created by an inline Chef `file` resource.
- `/etc/systemd/system/fastapi-tutorial.service` is created by an inline Chef `file` resource.

## Pre-flight checks

```bash
# Confirm required packages are installed.
dpkg-query -W python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Confirm the application directory and ownership.
stat -c '%A %U:%G %n' /opt/fastapi-tutorial
# Expected:
# drwxr-xr-x root:root /opt/fastapi-tutorial

# Confirm the repository and revision.
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD
git -C /opt/fastapi-tutorial status --short

# Confirm the virtual environment and dependency file.
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -f /opt/fastapi-tutorial/requirements.txt
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip list

# Confirm the PostgreSQL instance is enabled and active.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# Confirm the PostgreSQL role exists.
sudo -u postgres psql -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected:
# fastapi

# Confirm the PostgreSQL database exists.
sudo -u postgres psql -tAc \
  "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
# Expected:
# fastapi_db

# Confirm the database owner.
sudo -u postgres psql -tAc \
  "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected:
# fastapi

# Confirm the application role can connect.
PGPASSWORD='fastapi_password' \
  psql -h localhost -U fastapi -d fastapi_db -c "SELECT 1;"

# Confirm database privileges.
sudo -u postgres psql -d fastapi_db -c "\l+ fastapi_db"

# Confirm the environment file exists and has the expected ownership and mode.
test -f /opt/fastapi-tutorial/.env
stat -c '%A %U:%G %n' /opt/fastapi-tutorial/.env
# Expected:
# -rw-r--r-- root:root /opt/fastapi-tutorial/.env

# Confirm non-secret environment values.
grep -E '^(PROJECT_NAME|API_VERSION)=' /opt/fastapi-tutorial/.env

# Confirm the database URL without printing its password.
grep '^DATABASE_URL=' /opt/fastapi-tutorial/.env | \
  sed -E 's#(://[^:]+:)[^@]+@#\1****@#'

# Confirm the fastapi-tutorial unit exists.
test -f /etc/systemd/system/fastapi-tutorial.service

# Reload systemd and inspect the unit.
systemctl daemon-reload
systemctl cat fastapi-tutorial

# Validate the unit syntax.
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service

# Confirm important fastapi-tutorial settings.
systemctl show fastapi-tutorial \
  --property=User,WorkingDirectory,ExecStart,Restart,FragmentPath,ActiveState,SubState

# Confirm fastapi-tutorial is enabled and active.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

# Confirm the Uvicorn process.
pgrep -af '/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app'

# Confirm port 8000 is listening on all interfaces.
ss -tlnp | grep ':8000'
ss -tlnp | grep '0.0.0.0:8000'

# Verify the FastAPI application.
curl -i http://127.0.0.1:8000/
curl -i http://localhost:8000/

# Review FastAPI and PostgreSQL logs.
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u postgresql --no-pager -n 100

# Confirm the FastAPI service remains active.
systemctl is-active fastapi-tutorial
```

Expected `fastapi-tutorial` configuration includes:

- `User=root`
- `WorkingDirectory=/opt/fastapi-tutorial`
- Uvicorn executable `/opt/fastapi-tutorial/venv/bin/uvicorn`
- Application target `app.main:app`
- Bind address `0.0.0.0`
- Port `8000`
- `Restart=always`
- Startup ordering after `network.target` and `postgresql.service`

The cookbook does not define a dedicated health endpoint, so `/health` is not required unless the application repository provides one. The `fastapi-tutorial` systemd unit uses `Restart=always`; an unexpected Uvicorn exit should cause systemd to attempt a restart.