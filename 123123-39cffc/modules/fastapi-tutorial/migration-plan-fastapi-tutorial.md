---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` under `/opt/fastapi-tutorial`. It installs Python, virtual-environment, Git, PostgreSQL, PostgreSQL development packages, and application dependencies; creates the `fastapi` PostgreSQL role and `fastapi_db` database; writes the application environment file; and manages the `fastapi-tutorial` systemd service on TCP port `8000`. The cookbook contains one application instance and one PostgreSQL dependency. The PostgreSQL password is hardcoded in the recipe and must be moved to Ansible Vault during migration.

## Service Type and Instances

**Service Type**: Application Server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application server
  - Location/Path: `/opt/fastapi-tutorial`
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Dependency file: `/opt/fastapi-tutorial/requirements.txt`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Startup command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Restart policy: `always`
  - Project name: `FastAPI Tutorial`
  - API version: `1.0.0`

- **postgresql**: PostgreSQL database service
  - Managed service name: `postgresql`
  - Action: enabled and started
  - Database: `fastapi_db`
  - Database owner: `fastapi`
  - Database user: `fastapi`
  - Database host: `localhost`
  - Port/Socket: Platform-default PostgreSQL port and Unix socket; no explicit socket path is configured

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

The cookbook writes configuration using inline Chef `file` resources rather than `.erb` templates or static cookbook files.

## Module Explanation

The cookbook performs operations in this order:

1. **Default recipe** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Executes the complete deployment flow; there are no `include_recipe` calls, custom resources, iterable collection attributes, or `.each` loops.
   - Installs the following seven system packages with one `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` into `/opt/fastapi-tutorial` at revision `main`.
   - Creates the Python virtual environment at `/opt/fastapi-tutorial/venv` with:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
     The command is guarded by the existence of `/opt/fastapi-tutorial/venv`.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using `/opt/fastapi-tutorial/venv/bin/pip`, with `/opt/fastapi-tutorial` as the working directory.
   - Enables and starts the `postgresql` service.
   - Creates the PostgreSQL role, database, and privileges through the `create_db_user` execute resource:
     - Role: `fastapi`
     - Password in the Chef source: `fastapi_password`
     - Database: `fastapi_db`
     - Owner: `fastapi`
     - Privileges: `ALL`
   - Writes `/opt/fastapi-tutorial/.env` with:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
     The source mode is `0644`; the Ansible migration should preferably use `0600` and an Ansible Vault password.
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with:
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
     The file is owned by `root:root` with mode `0644`.
   - Defines the `systemd_reload` execute resource with action `nothing`. It runs `systemctl daemon-reload` immediately when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service after the repository, virtual environment, dependencies, `.env` file, systemd unit, and PostgreSQL setup are complete.
   - Resource summary:
     - `package`: 1 resource containing 7 packages
     - `directory`: 1 resource
     - `git`: 1 resource
     - `execute`: 4 resources
       - `create_venv`
       - `install_dependencies`
       - `create_db_user`
       - `systemd_reload`
     - `service`: 2 resources
       - `postgresql`
       - `fastapi-tutorial`
     - `file`: 2 resources
       - `/opt/fastapi-tutorial/.env`
       - `/etc/systemd/system/fastapi-tutorial.service`

## Dependencies

**External cookbook dependencies**: None listed in `metadata.rb`.

**System package dependencies**:

- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

The package names may require platform-specific mapping for Ubuntu and CentOS. The cookbook metadata declares support for Ubuntu `>= 18.04` and CentOS `>= 7.0`; CentOS package equivalents must be validated before migration.

**Service dependencies**:

- `postgresql`
- `fastapi-tutorial`

**Application dependency source**:

- Git repository: `https://github.com/dibanez/fastapi_tutorial.git`
- Revision: `main`
- Python requirements file: `/opt/fastapi-tutorial/requirements.txt`

## Credentials

**Detection Summary**: 1 credential detected across 1 file, with the same password used in the PostgreSQL creation command and application connection string.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: No external vault or secret manager URL detected
- **Path**: No data bag, vault path, or secret-manager path detected

### PostgreSQL application password

- **Variable(s)**:
  - PostgreSQL password literal: `fastapi_password`
  - `DATABASE_URL`: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext
- **Usage context**:
  - Creates the PostgreSQL role `fastapi`
  - Connects the application to database `fastapi_db`
  - Is written to `/opt/fastapi-tutorial/.env`
- **Required migration treatment**:
  - Store the password in Ansible Vault.
  - Use the vaulted value with `community.postgresql.postgresql_user`.
  - Generate `DATABASE_URL` from the vaulted value.
  - Use `no_log: true` for sensitive database and environment-file tasks.
  - Prefer mode `0600` for `/opt/fastapi-tutorial/.env`.

No data bags, encrypted data bags, Chef Vault items, Conjur variables, CyberArk integrations, environment-variable secret retrieval, TLS certificate references, API tokens, or other credentials were detected.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Database objects to verify**:

- PostgreSQL service `postgresql`
- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`
- Owner of `fastapi_db`: `fastapi`
- `ALL` privileges for `fastapi` on `fastapi_db`

**Service endpoints to check**:

- **fastapi-tutorial**: `0.0.0.0:8000`
- Expected local URL: `http://127.0.0.1:8000`
- Expected documentation URL: `http://127.0.0.1:8000/docs`
- Expected OpenAPI URL: `http://127.0.0.1:8000/openapi.json`
- **postgresql**: `localhost`, using the platform-default PostgreSQL port and Unix socket

**Templates rendered**:

- None; template render count: `0`
- `/opt/fastapi-tutorial/.env` is created by one inline Chef `file` resource.
- `/etc/systemd/system/fastapi-tutorial.service` is created by one inline Chef `file` resource.

## Pre-flight checks

```bash
# Verify system package prerequisites
python3 --version
pip3 --version
git --version
python3 -m venv --help >/dev/null
psql --version
```

```bash
# Verify the fastapi-tutorial application instance
test -d /opt/fastapi-tutorial
git -C /opt/fastapi-tutorial rev-parse --is-inside-work-tree
git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD
test -f /opt/fastapi-tutorial/requirements.txt
test -f /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
test -f /opt/fastapi-tutorial/.env
test -f /etc/systemd/system/fastapi-tutorial.service
```

```bash
# Verify the postgresql instance
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='fastapi';"
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname='fastapi_db';"
sudo -u postgres psql -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='fastapi_db';"
```

The role check should return `1`. The database owner check should return `fastapi`.

```bash
# Verify application environment configuration without exposing the password
stat -c '%A %U:%G %n' /opt/fastapi-tutorial/.env
grep '^PROJECT_NAME=' /opt/fastapi-tutorial/.env
grep '^API_VERSION=' /opt/fastapi-tutorial/.env
grep '^DATABASE_URL=' /opt/fastapi-tutorial/.env
```

Do not print the complete `.env` file because it contains the database password.

```bash
# Validate the fastapi-tutorial systemd unit
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep '^Description=' /etc/systemd/system/fastapi-tutorial.service
grep '^User=' /etc/systemd/system/fastapi-tutorial.service
grep '^WorkingDirectory=' /etc/systemd/system/fastapi-tutorial.service
grep '^ExecStart=' /etc/systemd/system/fastapi-tutorial.service
grep '^Restart=' /etc/systemd/system/fastapi-tutorial.service
```

Expected values include:

```text
User=root
WorkingDirectory=/opt/fastapi-tutorial
ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
```

```bash
# Reload and verify the fastapi-tutorial service
systemctl daemon-reload
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial
```

```bash
# Verify the FastAPI process and endpoint
ps aux | grep '[u]vicorn app.main:app'
systemctl show fastapi-tutorial --property=User,WorkingDirectory,ExecStart,Restart
ss -tlnp | grep ':8000'
curl -i http://127.0.0.1:8000/
curl -i http://127.0.0.1:8000/docs
curl -i http://127.0.0.1:8000/openapi.json
```

The application should listen on `0.0.0.0:8000` and return an HTTP response rather than a connection refusal.

```bash
# Verify PostgreSQL connectivity using the vaulted application password
PGPASSWORD='use-the-vaulted-fastapi-password-here' \
psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_database(), current_user;"
```

The query should report:

```text
current_database: fastapi_db
current_user: fastapi
```

```bash
# Review fastapi-tutorial service logs
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u fastapi-tutorial -p err --no-pager
```

```bash
# Review postgresql service logs
journalctl -u postgresql --no-pager -n 100
journalctl -u postgresql -p err --no-pager
```

```bash
# Verify fastapi-tutorial restart behavior
systemctl restart fastapi-tutorial
systemctl is-active fastapi-tutorial
curl -i http://127.0.0.1:8000/
```

The `fastapi-tutorial` service should return to the active state and TCP port `8000` should become available again.