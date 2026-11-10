---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` FastAPI/Uvicorn application from the `main` branch of `https://github.com/dibanez/fastapi_tutorial.git` to `/opt/fastapi-tutorial`. It creates a Python virtual environment, installs Python dependencies, provisions a local PostgreSQL database named `fastapi_db` and role `fastapi`, writes an application `.env` file containing a database password, and enables a systemd service running Uvicorn on TCP port `8000`. PostgreSQL is both a required local database service and a systemd ordering dependency for the application.

## Service Type and Instances

**Service Type**: Application Server (FastAPI/Uvicorn), with a local PostgreSQL database dependency.

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application systemd service.
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Working directory: `/opt/fastapi-tutorial`
  - Command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Service user: `root`
  - Restart policy: `always`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Environment file: `/opt/fastapi-tutorial/.env`

- **postgresql**: Local PostgreSQL system service used by the FastAPI application.
  - Location/Path: Platform-default PostgreSQL installation and data directory; Fedora/RHEL initialization sentinel is `/var/lib/pgsql/data/PG_VERSION`
  - Port/Socket: Platform-default PostgreSQL listener; the cookbook does not explicitly configure a TCP port, socket path, bind address, or data directory.
  - Key Config: Database `fastapi_db`, owned by PostgreSQL role `fastapi`; application connection host is `localhost`.
  - Initialization on Fedora/RHEL: `postgresql-setup --initdb`

There are no collection attributes and no `.each` iterations in the executed recipe.

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
None. The cookbook writes inline content using Chef file resources rather than ERB templates.
```

**Attributes:**
```text
None.
```

**Files:**
```text
None. No cookbook_file or remote_file resource deploys static cookbook files.
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Selects package installation based on platform family:
     - On Fedora/RHEL, installs `python3`, `python3-pip`, `git`, `postgresql-server`, `postgresql-contrib`, and `libpq-devel`.
     - On non-Fedora/RHEL platforms, installs `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
     - Package versions are not pinned.
     - On Fedora/RHEL, runs `postgresql-setup --initdb` only when `/var/lib/pgsql/data/PG_VERSION` does not exist.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the Python virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv` only when `/opt/fastapi-tutorial/venv` does not already exist.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` into `/opt/fastapi-tutorial/venv` using `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.
     - This command has no Chef guard and runs during every Chef convergence.
   - Enables and starts the `postgresql` service.
   - Provisions PostgreSQL objects using commands run as the `postgres` operating-system user:
     - Creates role `fastapi` with its configured password.
     - Creates database `fastapi_db` owned by `fastapi`.
     - Grants all privileges on `fastapi_db` to `fastapi`.
     - Each command ends with `|| true`, suppressing both expected already-exists errors and unexpected provisioning failures.
   - Writes `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`.
     - The file contains `PROJECT_NAME`, `API_VERSION`, and `DATABASE_URL`.
     - The configured database URL connects role `fastapi` to database `fastapi_db` on `localhost`.
     - The current Chef mode makes the embedded database password world-readable.
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`.
     - The unit starts `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`.
     - The unit uses `WorkingDirectory=/opt/fastapi-tutorial`.
     - The unit sets `PATH=/opt/fastapi-tutorial/venv/bin`.
     - The unit declares `After=network.target postgresql.service`.
     - The service runs as `root` with `Restart=always`.
   - Reloads systemd with `systemctl daemon-reload` immediately when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service.
     - Changes to the Git checkout, Python dependencies, `/opt/fastapi-tutorial/.env`, and `/etc/systemd/system/fastapi-tutorial.service` do not explicitly restart an already-running FastAPI process in the Chef cookbook.
     - For Ansible migration, notify a restart handler when any of those resources change.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:

- Fedora/RHEL:
  - `python3`
  - `python3-pip`
  - `git`
  - `postgresql-server`
  - `postgresql-contrib`
  - `libpq-devel`

- Non-Fedora/RHEL:
  - `python3`
  - `python3-pip`
  - `python3-venv`
  - `git`
  - `postgresql`
  - `postgresql-contrib`
  - `libpq-dev`

- Python dependencies:
  - `/opt/fastapi-tutorial/requirements.txt`, installed into `/opt/fastapi-tutorial/venv`

- Ansible migration dependencies:
  - `community.postgresql` collection for PostgreSQL role, database, and privilege management.
  - A Python PostgreSQL driver required by the selected `community.postgresql` modules, installed where the module executes.

**Service dependencies**:

- `postgresql` must be enabled and started before provisioning role `fastapi` and database `fastapi_db`.
- `fastapi-tutorial` must be enabled and started after application deployment and systemd unit installation.
- The `fastapi-tutorial` systemd unit declares `After=network.target postgresql.service`.
- Confirm the `postgresql` service name matches the target platform’s PostgreSQL package and initialization layout before migration.

## Credentials

**Detection Summary**: 1 hardcoded credential detected across 1 file. The same password is used in PostgreSQL role creation and in the application database URL.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None detected
  - **Path**: None detected

### PostgreSQL Application Password

- **Variable(s)**:
  - PostgreSQL password literal: `fastapi_password`
  - PostgreSQL role: `fastapi`
  - Embedded connection value: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext in the Chef recipe.
- **Usage context**:
  - Creates PostgreSQL role `fastapi`.
  - Connects the FastAPI application to local database `fastapi_db` through `/opt/fastapi-tutorial/.env`.
- **Migration requirement**:
  - Store the password in an AAP encrypted credential, Ansible Vault-encrypted variable, or approved external secret-manager lookup.
  - Do not store the password in plaintext role defaults, playbooks, inventory, logs, or source control.
  - Use `no_log: true` on PostgreSQL user-password tasks.
  - Render `/opt/fastapi-tutorial/.env` with mode `0600` rather than the Chef mode of `0644`.

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/uvicorn`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- `/var/lib/pgsql/data/PG_VERSION` on Fedora/RHEL

**Service endpoints to check**:

- **fastapi-tutorial**:
  - TCP port `8000`
  - Bind address `0.0.0.0`
  - HTTP endpoint: `http://127.0.0.1:8000/`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`

- **postgresql**:
  - Local PostgreSQL connectivity as operating-system user `postgres`
  - Role `fastapi`
  - Database `fastapi_db`
  - Effective platform-default PostgreSQL port, socket, and listener configuration

**Templates rendered**:

- None. The cookbook does not use ERB templates.
- Inline Chef file content is rendered once to `/opt/fastapi-tutorial/.env`.
- Inline Chef file content is rendered once to `/etc/systemd/system/fastapi-tutorial.service`.

## Pre-flight checks:

```bash
# Verify required application files for the fastapi-tutorial instance.
test -d /opt/fastapi-tutorial && echo "PASS: fastapi-tutorial application directory exists"
test -d /opt/fastapi-tutorial/venv && echo "PASS: fastapi-tutorial virtual environment exists"
test -x /opt/fastapi-tutorial/venv/bin/python && echo "PASS: virtual-environment Python is executable"
test -x /opt/fastapi-tutorial/venv/bin/uvicorn && echo "PASS: Uvicorn is installed"
test -f /opt/fastapi-tutorial/requirements.txt && echo "PASS: requirements.txt exists"
test -f /opt/fastapi-tutorial/.env && echo "PASS: fastapi-tutorial environment file exists"
test -f /etc/systemd/system/fastapi-tutorial.service && echo "PASS: fastapi-tutorial systemd unit exists"

# Verify the fastapi-tutorial Git checkout.
git -C /opt/fastapi-tutorial branch --show-current
git -C /opt/fastapi-tutorial rev-parse --is-inside-work-tree
git -C /opt/fastapi-tutorial status --short

# Verify environment file permissions without exposing secret content.
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
# Chef-equivalent mode: root:root 644
# Recommended Ansible mode: root:root 600

# Verify the fastapi-tutorial systemd unit.
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'WorkingDirectory=/opt/fastapi-tutorial' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Environment="PATH=/opt/fastapi-tutorial/venv/bin"' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'After=network.target postgresql.service' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Restart=always' /etc/systemd/system/fastapi-tutorial.service

# Verify the postgresql instance service and database objects.
systemctl is-enabled postgresql
systemctl is-active postgresql
sudo -u postgres psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'fastapi';"
sudo -u postgres psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -d postgres -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -d fastapi_db -tAc "SELECT current_database();"
sudo -u postgres psql -d fastapi_db -tAc "SELECT current_user;"

# On Fedora/RHEL, verify PostgreSQL initialization completed.
test -f /var/lib/pgsql/data/PG_VERSION && echo "PASS: PostgreSQL initdb sentinel exists"

# Verify the fastapi-tutorial instance service and process.
systemctl daemon-reload
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager
ps -ef | grep '[u]vicorn app.main:app --host 0.0.0.0 --port 8000'

# Verify fastapi-tutorial TCP listener and HTTP reachability.
ss -ltnp '( sport = :8000 )'
lsof -nP -iTCP:8000 -sTCP:LISTEN
curl --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'HTTP status: %{http_code}\n' http://127.0.0.1:8000/

# Review logs for both named services.
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager
journalctl -u fastapi-tutorial --since "15 minutes ago" --no-pager | grep -Ei 'error|exception|traceback' || true
```