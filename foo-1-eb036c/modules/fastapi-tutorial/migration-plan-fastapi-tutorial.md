---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI application server backed by a local PostgreSQL database. It installs seven unversioned system packages, clones the FastAPI tutorial repository into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs Python dependencies, creates the PostgreSQL role/database `fastapi`/`fastapi_db`, writes a hardcoded `.env` file and systemd unit, then enables and starts PostgreSQL and the `fastapi-tutorial` application service. The FastAPI process listens on TCP port `8000` on all interfaces (`0.0.0.0`).

## Service Type and Instances

**Service Type**: Application Server with PostgreSQL Database

**Configured Instances**:
- **fastapi-tutorial**: FastAPI/Uvicorn application systemd service.
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`, revision `main`
  - Service unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Key Config: Runs as `root`; working directory is `/opt/fastapi-tutorial`; `Restart=always`.

- **postgresql**: Local PostgreSQL system service.
  - Database: `fastapi_db`
  - Database owner: `fastapi`
  - Role: `fastapi`
  - Connection used by the application: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Port/Socket: No port or socket is configured by this cookbook. PostgreSQL commonly uses TCP `5432`; confirm the active platform package configuration before migration.
  - Key Config: The service is enabled and started before database role and database setup.

There are no collection attributes and no Chef iteration (`.each`) loops in this cookbook.

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
None. The cookbook writes `.env` and the systemd unit using Chef `file` resources with inline content.
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

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following unversioned operating-system packages:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`

2. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial`.
   - Sets ownership to `root:root`, mode to `0755`, and enables recursive directory creation.

3. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Synchronizes the Git checkout at `/opt/fastapi-tutorial`.
   - Uses repository `https://github.com/dibanez/fastapi_tutorial.git` at revision `main`.
   - Uses Chef action `:sync`, updating the working tree when the remote revision changes.

4. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates the Python virtual environment at `/opt/fastapi-tutorial/venv`.
   - Uses `execute[create_venv]` with command `python3 -m venv /opt/fastapi-tutorial/venv`.
   - Uses the guard `creates '/opt/fastapi-tutorial/venv'`, so the command does not run when the virtual-environment directory already exists.

5. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs Python dependencies into `/opt/fastapi-tutorial/venv`.
   - Uses `execute[install_dependencies]` in working directory `/opt/fastapi-tutorial`.
   - Runs `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.
   - Has no idempotency guard and runs during every Chef convergence.

6. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Enables and starts the `postgresql` system service.
   - Uses `service[postgresql]` with actions `enable` and `start`.
   - The cookbook explicitly uses the unit name `postgresql`; destination platforms may require a different PostgreSQL unit name.

7. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates PostgreSQL role `fastapi`, database `fastapi_db`, and grants database privileges.
   - Uses `execute[create_db_user]` to run the following commands as OS user `postgres`:
     ```bash
     sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true
     sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true
     sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true
     ```
   - Creates role `fastapi` with password `fastapi_password`.
   - Creates database `fastapi_db` owned by `fastapi`.
   - Grants `ALL PRIVILEGES` on database `fastapi_db` to role `fastapi`.
   - Runs during every Chef convergence. The `|| true` clauses suppress both expected already-exists errors and real SQL failures.

8. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Writes `/opt/fastapi-tutorial/.env` with ownership `root:root` and mode `0644`.
   - Writes the following inline content:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```

9. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with ownership `root:root` and mode `0644`.
   - Writes the following inline systemd unit:
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
   - Immediately notifies `execute[systemd_reload]` when the unit file changes.
   - A unit-file change triggers only a systemd daemon reload; it does not explicitly restart `fastapi-tutorial`.

10. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Defines `execute[systemd_reload]`.
    - Runs `systemctl daemon-reload`.
    - Has default action `nothing` and executes only when immediately notified by a change to `/etc/systemd/system/fastapi-tutorial.service`.

11. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Enables and starts the `fastapi-tutorial` systemd service.
    - Uses `service[fastapi-tutorial]` with actions `enable` and `start`.
    - Runs Uvicorn as `root` and exposes TCP port `8000` on `0.0.0.0`.

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
- `postgresql` is enabled and started before the PostgreSQL role and database setup commands.
- `fastapi-tutorial` depends on the deployed Git checkout, virtual environment, installed Python dependencies, `.env` file, and systemd unit.
- The `fastapi-tutorial` unit declares `After=network.target postgresql.service`.
- Supported operating systems from cookbook metadata are Ubuntu `>= 18.04` and CentOS `>= 7.0`.

## Credentials

**Detection Summary**: 1 hardcoded database credential was detected in 1 file. It appears both as the PostgreSQL role password and embedded in the application database URL.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### PostgreSQL `fastapi` Role Password

- **Variable(s)**:
  - Literal PostgreSQL password: `fastapi_password`
  - Embedded connection setting: `DATABASE_URL`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded inline Chef resource content.
- **Usage context**:
  - Used in `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`.
  - Embedded in `/opt/fastapi-tutorial/.env` as `postgresql://fastapi:fastapi_password@localhost/fastapi_db`.
  - Authenticates the FastAPI application to local PostgreSQL database `fastapi_db`.
- **Migration guidance**:
  - Store the password in an AAP credential, Ansible Vault-encrypted variable, or approved external secret manager.
  - Construct `DATABASE_URL` from protected variables.
  - Mark database-password tasks with `no_log: true`.
  - Do not store the password in plaintext inventory, playbooks, or unencrypted variable files.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**: TCP `8000` bound to `0.0.0.0`.
- **postgresql**: No listener port is configured by the cookbook. Verify the active PostgreSQL configuration; TCP `5432` is the usual package default.
- **postgresql Unix socket**: No socket path is configured by the cookbook. Discover the active platform-default socket directory from the running PostgreSQL configuration.

**Templates rendered**:
- None. No Chef templates are used.
- Inline file content is written once to `/opt/fastapi-tutorial/.env`.
- Inline file content is written once to `/etc/systemd/system/fastapi-tutorial.service`.

## Pre-flight checks:
```bash
# PostgreSQL instance: service status and enablement
systemctl status postgresql --no-pager
systemctl is-enabled postgresql
systemctl is-active postgresql

# fastapi-tutorial instance: service status and enablement
systemctl status fastapi-tutorial --no-pager
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial

# Confirm the configured Git checkout and branch
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
git -C /opt/fastapi-tutorial rev-parse HEAD

# Confirm Python virtual environment and application dependencies
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -f /opt/fastapi-tutorial/requirements.txt
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip check

# Verify application environment settings.
# This command output exposes the hardcoded password; handle it as sensitive.
grep -Fx 'PROJECT_NAME="FastAPI Tutorial"' /opt/fastapi-tutorial/.env
grep -Fx 'API_VERSION=1.0.0' /opt/fastapi-tutorial/.env
grep -Fx 'DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db' \
  /opt/fastapi-tutorial/.env
stat -c '%a %U:%G %n' /opt/fastapi-tutorial/.env
# Chef-equivalent output: 644 root:root /opt/fastapi-tutorial/.env

# Validate the fastapi-tutorial systemd unit and Uvicorn listener configuration
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'WorkingDirectory=/opt/fastapi-tutorial' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'User=root' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Restart=always' /etc/systemd/system/fastapi-tutorial.service
stat -c '%a %U:%G %n' /etc/systemd/system/fastapi-tutorial.service
# Chef-equivalent output: 644 root:root /etc/systemd/system/fastapi-tutorial.service

# PostgreSQL instance: verify role fastapi
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected output: fastapi

# PostgreSQL instance: verify database fastapi_db and owner fastapi
sudo -u postgres psql -d postgres -tAc \
  "SELECT datname || ':' || pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi_db:fastapi

# PostgreSQL instance: test application database connectivity.
# Do not expose the hardcoded password in Ansible logs.
PGPASSWORD='fastapi_password' psql -h localhost -U fastapi -d fastapi_db \
  -c "SELECT current_database(), current_user;"

# fastapi-tutorial instance: verify configured Uvicorn process
pgrep -af '/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000'

# fastapi-tutorial instance: verify TCP listener on port 8000
ss -ltnp | grep ':8000'
# Expected: a LISTEN entry for the Uvicorn/Python process bound to 0.0.0.0:8000.

# fastapi-tutorial instance: verify HTTP reachability.
# The cookbook specifies no application health endpoint or expected response body.
curl --fail --show-error --silent --output /dev/null \
  --write-out 'FastAPI HTTP status: %{http_code}\n' \
  http://127.0.0.1:8000/

# PostgreSQL instance: verify TCP listener if configured by the platform package.
# TCP 5432 is common but is not explicitly configured by this cookbook.
ss -ltnp | grep ':5432' || true

# Service logs
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager

# Deployed application directory, ownership, and disk checks
ls -ld /opt/fastapi-tutorial /opt/fastapi-tutorial/venv
df -h /opt
```