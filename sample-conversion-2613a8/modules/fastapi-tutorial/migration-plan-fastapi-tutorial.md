---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI application server backed by a local PostgreSQL database. It installs required OS packages, checks out the `main` branch of the FastAPI tutorial repository into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application dependencies, creates the PostgreSQL role and database `fastapi` / `fastapi_db`, writes a plaintext `.env` file and systemd unit, then enables and starts PostgreSQL and the FastAPI service. The FastAPI application listens on TCP port `8000` on all interfaces (`0.0.0.0`).

## Service Type and Instances

**Service Type**: Application Server (FastAPI/Uvicorn) with a local PostgreSQL database dependency.

**Configured Instances**:

- **fastapi-tutorial**: FastAPI/Uvicorn systemd service.
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Key Config: Runs as `root`; uses `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`; restart policy is `always`; starts after `network.target` and `postgresql.service`.

- **postgresql**: Local PostgreSQL service managed by the distribution package.
  - Location/Path: Distribution-default PostgreSQL data, configuration, socket, and log locations.
  - Port/Socket: Not explicitly configured by the cookbook; discover installed distribution defaults on the target host.
  - Key Config: Database role `fastapi`; database `fastapi_db`; database owner `fastapi`; grants `ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi`; the application connects using `postgresql://fastapi:<managed-password>@localhost/fastapi_db`.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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

No Chef templates, custom-resource providers, attribute files, or static cookbook files are referenced by the execution tree.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following system packages using one Chef `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the Python virtual environment using:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
     The Chef `creates` guard is `/opt/fastapi-tutorial/venv`.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
     The command runs with `/opt/fastapi-tutorial` as its working directory.
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi`, creates database `fastapi_db` owned by `fastapi`, and grants the role all privileges on `fastapi_db`. The Chef commands run as the `postgres` operating-system user and suppress errors with `|| true`:
     ```bash
     sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true
     sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true
     sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true
     ```
     The Ansible migration should use idempotent PostgreSQL-aware modules or explicit existence checks rather than suppressing database, permissions, authentication, or server failures.
   - Writes `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
     During migration, construct `DATABASE_URL` from an externally managed secret and do not retain the password in plaintext Ansible content.
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
   - Notifies `execute[systemd_reload]` immediately when `/etc/systemd/system/fastapi-tutorial.service` is created or changed.
   - Declares `execute[systemd_reload]`, which runs:
     ```bash
     systemctl daemon-reload
     ```
     Its default action is `nothing`; it runs only when notified by the systemd unit file.
   - Enables and starts the `fastapi-tutorial` service.
   - No collection attributes or Chef `.each` loops are used.

## Dependencies

**External cookbook dependencies**: None declared in the available `metadata.rb`.

**System package dependencies**:
- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

**Service dependencies**:
- `postgresql` must be enabled and started before PostgreSQL role and database provisioning.
- `fastapi-tutorial` depends on `network.target` and `postgresql.service` through `After=network.target postgresql.service`.
- The Ansible implementation requires a PostgreSQL Python driver compatible with the selected `community.postgresql` module runtime if PostgreSQL-aware modules are used.

## Credentials

**Detection Summary**: 1 hardcoded credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### PostgreSQL Application Password
- **Variable(s)**: `fastapi_password`, `DATABASE_URL`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext in the Chef recipe and rendered into `/opt/fastapi-tutorial/.env`.
- **Usage context**: Creates PostgreSQL role `fastapi` and allows the FastAPI application to authenticate to local database `fastapi_db`.

The password must be stored in an AAP credential, Ansible Vault-encrypted variable, or approved external secret manager. Build `DATABASE_URL` from the protected value, and apply `no_log: true` to database-role creation and `.env` deployment tasks that expose the password.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk/Conjur calls, HashiCorp Vault references, AWS Secrets Manager references, TLS certificates, private keys, or environment-variable secret lookups were detected.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/.git`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**: TCP `8000` on `0.0.0.0`; validate `http://127.0.0.1:8000/` or a repository-confirmed application route.
- **postgresql**: The application uses `localhost`; verify the distribution-default PostgreSQL TCP port, socket directory, authentication behavior, and local database connectivity.

**Templates rendered**:
- None. Render count: `0`. The cookbook uses Chef `file` resources with inline content rather than templates.

## Pre-flight checks:
```bash
# Confirm required packages are installed.
# Debian/Ubuntu:
dpkg-query -W python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# RHEL/CentOS:
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Verify source checkout and revision for the fastapi-tutorial instance.
test -d /opt/fastapi-tutorial/.git
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
git -C /opt/fastapi-tutorial rev-parse HEAD

# Verify the FastAPI virtual environment and installed dependencies.
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip check
/opt/fastapi-tutorial/venv/bin/pip show uvicorn

# Verify the postgresql instance service.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# Verify PostgreSQL role fastapi.
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
# Expected output: fastapi

# Verify PostgreSQL database fastapi_db.
sudo -u postgres psql -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi_db

# Verify fastapi_db ownership.
sudo -u postgres psql -d postgres -tAc \
  "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
# Expected output: fastapi

# Verify application database connectivity without exposing the password in logs.
PGPASSWORD='<AAP-managed-fastapi-password>' \
  psql -h localhost -U fastapi -d fastapi_db \
  -c "SELECT current_database(), current_user;"
# Expected row contains: fastapi_db | fastapi

# Verify the deployed environment file without printing DATABASE_URL.
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
# Expected: root:root 644 /opt/fastapi-tutorial/.env
grep -E '^PROJECT_NAME="FastAPI Tutorial"$|^API_VERSION=1\.0\.0$' \
  /opt/fastapi-tutorial/.env
grep -q '^DATABASE_URL=postgresql://fastapi:' /opt/fastapi-tutorial/.env

# Verify the fastapi-tutorial systemd unit.
stat -c '%U:%G %a %n' /etc/systemd/system/fastapi-tutorial.service
# Expected: root:root 644 /etc/systemd/system/fastapi-tutorial.service
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
systemctl cat fastapi-tutorial
systemctl show fastapi-tutorial \
  -p User -p WorkingDirectory -p ExecStart -p Restart -p After

# Verify the fastapi-tutorial instance service.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager
ps -ef | grep '[u]vicorn app.main:app'
# Expected command includes: --host 0.0.0.0 --port 8000

# Verify the FastAPI application endpoint.
ss -ltnp | grep ':8000'
# Expected: a listening Uvicorn/Python process on 0.0.0.0:8000
curl -i --max-time 10 http://127.0.0.1:8000/
# Confirm the expected response status against routes in the checked-out repository.

# Inspect logs for both named service instances.
journalctl -u fastapi-tutorial -n 100 --no-pager
journalctl -u postgresql -n 100 --no-pager

# Confirm filesystem capacity for application operations.
df -h /opt/fastapi-tutorial
```