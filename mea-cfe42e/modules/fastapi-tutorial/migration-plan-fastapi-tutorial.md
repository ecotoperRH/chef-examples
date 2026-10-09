---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI tutorial application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main`. It installs Python, PostgreSQL, Git, and PostgreSQL development dependencies; creates a Python virtual environment; installs application requirements; creates the PostgreSQL user and database; writes an environment file containing the database connection string; and manages a systemd service named `fastapi-tutorial` listening on TCP port `8000`.

## Service Type and Instances

**Service Type**: Application Server

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application server managed by systemd
  - Application path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Python application entry point: `app.main:app`
  - Service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Listening address: `0.0.0.0`
  - Port/Socket: TCP `8000`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Restart policy: `Restart=always`
  - Unit file: `/etc/systemd/system/fastapi-tutorial.service`

- **postgresql**: PostgreSQL database service required by the FastAPI application
  - Service name: `postgresql`
  - Database user: `fastapi`
  - Database: `fastapi_db`
  - Host: `localhost`
  - Port/Socket: Default PostgreSQL port; no explicit Unix socket configured
  - Connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
cookbooks/fastapi-tutorial/
└── recipes/
    └── default.rb

Recipes:
recipes/default.rb

Providers:

Templates:

Attributes:

Files:
```

The `.env` file and systemd unit are generated directly by `file` resources in the recipe. They are not cookbook static files or ERB templates.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev` through one Chef `package` resource.
   - No package versions are pinned.
   - Supports Ubuntu `>= 18.04` and CentOS `>= 7.0`; package naming and PostgreSQL service behavior must be validated on each target platform.
   - Resources: `package` (one resource containing seven package names).

2. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial` recursively.
   - Sets owner and group to `root:root`.
   - Sets mode to `0755`.
   - Resource: `directory` (one resource).

3. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` into `/opt/fastapi-tutorial`.
   - Checks out revision `main`.
   - Uses the destination as the application working directory.
   - Resource: `git` (one resource).

4. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates the virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv`.
   - Uses `/opt/fastapi-tutorial/venv` as the `creates` guard, so the environment is not recreated when it already exists.
   - Resource: `execute[create_venv]`.

5. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt`.
   - Executes `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt` from `/opt/fastapi-tutorial`.
   - The Chef recipe does not notify or restart the application when dependencies change.
   - Resource: `execute[install_dependencies]`.

6. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Enables and starts the `postgresql` service.
   - This occurs before database creation.
   - Resource: `service[postgresql]`, actions `enable` and `start`.

7. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates the PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates the database `fastapi_db` owned by `fastapi`.
   - Grants `ALL` privileges on `fastapi_db` to `fastapi`.
   - The original Chef command runs these operations with `sudo -u postgres psql` and appends `|| true` to each command, suppressing both already-exists errors and unrelated PostgreSQL errors.
   - The preferred Ansible migration uses `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_privs` with `become_user: postgres` for idempotency.
   - Resource: `execute[create_db_user]`.

8. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial/.env`.
   - Sets owner and group to `root:root`.
   - Sets mode to `0644`.
   - Writes:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - The migrated implementation should obtain the database password from Ansible Vault, an AAP credential, or an approved secret-management system while preserving the complete `DATABASE_URL`.
   - Resource: `file[/opt/fastapi-tutorial/.env]`.

9. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/etc/systemd/system/fastapi-tutorial.service`.
   - Sets owner and group to `root:root`.
   - Sets mode to `0644`.
   - Deploys the following unit configuration:
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
   - Runs the application as `root`.
   - Starts Uvicorn with `app.main:app`.
   - Binds to all IPv4 interfaces on TCP port `8000`.
   - Restarts automatically when the process exits.
   - Orders startup after `network.target` and `postgresql.service`.
   - Resource: `file[/etc/systemd/system/fastapi-tutorial.service]`.

10. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Defines `systemctl daemon-reload` as `execute[systemd_reload]`.
    - Uses default action `nothing`.
    - The systemd unit file immediately notifies this resource when the unit changes.
    - No daemon reload occurs when the unit file is unchanged.
    - Resource: `execute[systemd_reload]`.

11. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Enables and starts the `fastapi-tutorial` service.
    - Starts the service after the unit file is deployed and any required systemd daemon reload has occurred.
    - Resource: `service[fastapi-tutorial]`, actions `enable` and `start`.

There are no included recipes, collection attributes, or `.each` loops. No instance expansion is required.

## Dependencies

**External cookbook dependencies**: None listed in the analyzed metadata.

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

- Repository: `https://github.com/dibanez/fastapi_tutorial.git`
- Revision: `main`

**Platform support**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

## Credentials

**Detection Summary**: 1 hardcoded database credential detected in 1 recipe file.

**Source**:
  - **Provider**: Hardcoded / Internal
  - **URL**: No external vault or secret-manager URL detected
  - **Path**: No data bag, vault path, or secret-manager path detected

### PostgreSQL application password

- **Variable(s)**: PostgreSQL user `fastapi`; password literal `fastapi_password`; application variable `DATABASE_URL`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the Chef recipe
- **Usage context**:
  - Creates the PostgreSQL role `fastapi`.
  - Is embedded in `/opt/fastapi-tutorial/.env`.
  - Is included in `postgresql://fastapi:fastapi_password@localhost/fastapi_db`.
- **Migration requirement**:
  - Store the password in Ansible Vault, an AAP credential, or an approved external secret provider.
  - Use the same managed value for PostgreSQL user configuration and the `.env` file.
  - Consider changing `.env` mode from `0644` to `0600`; this is a security improvement and not an exact mode-preserving migration.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, environment-variable secret references, TLS certificates, private keys, API keys, or tokens were detected.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:

- `fastapi-tutorial`: `0.0.0.0:8000`
- `postgresql`: `localhost`, default PostgreSQL port unless host configuration specifies otherwise
- Unix socket: No explicit Unix socket path configured

**Database objects to verify**:

- PostgreSQL role: `fastapi`
- PostgreSQL database: `fastapi_db`
- Database owner: `fastapi`
- Database privileges: `ALL`

**Templates rendered**:

- None. No ERB or other cookbook templates are present.
- Direct file resources render `/opt/fastapi-tutorial/.env` once and `/etc/systemd/system/fastapi-tutorial.service` once.

**Service reload and restart behavior**:

- `/etc/systemd/system/fastapi-tutorial.service` immediately triggers `systemctl daemon-reload` when changed.
- `.env` and Python dependency changes do not trigger an explicit FastAPI service restart.
- `postgresql` is enabled and started before database creation.
- `fastapi-tutorial` is enabled and started at the end of the recipe.

## Pre-flight checks:

```bash
# Verify installed packages on Debian-family systems, or use the RPM command
# on Red Hat-family systems.
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev 2>/dev/null || \
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Verify the fastapi-tutorial application instance.
ls -ld /opt/fastapi-tutorial
ls -ld /opt/fastapi-tutorial/venv
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -f /opt/fastapi-tutorial/.env

# Verify the PostgreSQL instance.
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql

# Verify the PostgreSQL role and database.
sudo -u postgres psql -tAc "SELECT usename FROM pg_user WHERE usename = 'fastapi';"
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -tAc "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"

# Verify database connectivity without exposing the password in shared logs.
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT version();"

PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_database(), current_user;"

# Verify the environment configuration.
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env

# Expected values:
# PROJECT_NAME="FastAPI Tutorial"
# API_VERSION=1.0.0
# DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db

# Validate the fastapi-tutorial systemd instance.
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
systemctl cat fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial

grep -E '^(Description|After|Type|User|WorkingDirectory|Environment|ExecStart|Restart|WantedBy)=' \
  /etc/systemd/system/fastapi-tutorial.service

# Expected unit values include:
# User=root
# WorkingDirectory=/opt/fastapi-tutorial
# ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
# Restart=always

# Verify the FastAPI HTTP endpoint and listening socket.
systemctl status fastapi-tutorial
curl -I http://127.0.0.1:8000/
curl -sS http://127.0.0.1:8000/

ss -tlnp | grep ':8000'
netstat -tulpn 2>/dev/null | grep ':8000'
lsof -iTCP:8000 -sTCP:LISTEN

# Verify logs and the application process.
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u postgresql --no-pager -n 100
ps aux | grep '[u]vicorn'

# Expected Uvicorn command:
# /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Run the Ansible playbook a second time and verify that:

- The Git checkout remains at revision `main`.
- `/opt/fastapi-tutorial/venv` is not recreated.
- PostgreSQL role and database tasks report no changes after the first successful run.
- `/opt/fastapi-tutorial/.env` changes only when its intended content or managed secret changes.
- `/etc/systemd/system/fastapi-tutorial.service` changes only when its intended unit content changes.
- `systemctl daemon-reload` runs only when the systemd unit changes.
- The `postgresql` instance remains enabled and active.
- The `fastapi-tutorial` instance remains enabled and active.