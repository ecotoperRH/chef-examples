---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a Python FastAPI application server backed by a local PostgreSQL database. It installs seven system packages, clones the FastAPI tutorial application into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application dependencies, provisions the PostgreSQL role/database pair `fastapi` and `fastapi_db`, writes an application `.env` file and systemd unit, and enables and starts PostgreSQL and the FastAPI service. Uvicorn listens on TCP port **8000** on all interfaces (`0.0.0.0`).

## Service Type and Instances

**Service Type**: Application Server, with a local PostgreSQL Database dependency

**Configured Instances**:
- **fastapi-tutorial**: FastAPI/Uvicorn application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Git repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Git revision: `main`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Port/Socket: TCP port `8000`, bound to `0.0.0.0`; no Unix socket is configured
  - Key Config: Runs as `root`, uses `/opt/fastapi-tutorial` as its working directory, has restart policy `always`, and starts after `network.target` and `postgresql.service`

- **postgresql**: Local PostgreSQL service used by the FastAPI application
  - Location/Path: Local PostgreSQL service managed as `postgresql`
  - Port/Socket: Application connects through `localhost`; no explicit PostgreSQL port or socket path is configured by the cookbook
  - Key Config: Database `fastapi_db`, owned by role `fastapi`; connection string written to the application `.env` file is `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

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
None.
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs required operating-system packages using one `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes the Git repository `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the Python virtual environment at `/opt/fastapi-tutorial/venv` with `python3 -m venv /opt/fastapi-tutorial/venv`, only when that path does not already exist.
   - Installs Python application dependencies from `/opt/fastapi-tutorial/requirements.txt` using `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.
   - Enables and starts the `postgresql` service.
   - Provisions PostgreSQL as operating-system user `postgres`:
     - Creates role `fastapi` with password `fastapi_password`.
     - Creates database `fastapi_db` owned by `fastapi`.
     - Grants all privileges on database `fastapi_db` to `fastapi`.
     - The Chef commands use `|| true`; an Ansible migration should instead use PostgreSQL-aware idempotent modules and report genuine failures.
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
   - Defines `execute[systemd_reload]`, which runs `systemctl daemon-reload` only when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` systemd service.
   - The systemd unit does not include `EnvironmentFile=/opt/fastapi-tutorial/.env`; the application itself must load the `.env` file for its values to affect runtime behavior.
   - Iterations: No Chef collection attributes or `.each` loops are used.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`. Chef compatibility declares Chef `>= 16.0`, Ubuntu `>= 18.04`, and CentOS `>= 7.0`.

**System package dependencies**:
- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

**Service dependencies**:
- `postgresql` must be enabled and started before provisioning role `fastapi` and database `fastapi_db`.
- `fastapi-tutorial` must be enabled and started after `/etc/systemd/system/fastapi-tutorial.service` is created.
- `fastapi-tutorial` declares `After=network.target postgresql.service`.
- `libpq-dev` is a Debian/Ubuntu package name; an Ansible implementation targeting CentOS must map it to the appropriate PostgreSQL client development package for that OS family.
- PostgreSQL-aware Ansible modules require the applicable Python PostgreSQL driver on the managed host.

## Credentials

**Detection Summary**: 1 hardcoded credential detected in 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### PostgreSQL Application Password
- **Variable(s)**: `fastapi_password`, PostgreSQL role `fastapi`, and connection setting `DATABASE_URL`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the Chef recipe.
- **Usage context**: Used to create PostgreSQL role `fastapi` and embedded in `/opt/fastapi-tutorial/.env` as `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk/Conjur integration, environment-sourced secrets, TLS certificates, private keys, or external secret-manager endpoints were detected.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/.git`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- `/opt/fastapi-tutorial/venv/bin/uvicorn`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **postgresql**: Local connection through `localhost` using database `fastapi_db` and role `fastapi`
- **fastapi-tutorial**: TCP port `8000` listening on `0.0.0.0`
- Unix sockets: No socket path is configured by the cookbook.

**Templates rendered**:
- No ERB templates are rendered.
- Inline content is written once to `/opt/fastapi-tutorial/.env`.
- Inline content is written once to `/etc/systemd/system/fastapi-tutorial.service`.

## Pre-flight checks:
```bash
# Package and Python runtime verification
python3 --version
git --version
psql --version
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version

# fastapi-tutorial application source and virtual environment
test -d /opt/fastapi-tutorial
test -d /opt/fastapi-tutorial/.git
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
test -f /opt/fastapi-tutorial/requirements.txt

# postgresql service status
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager

# postgresql role: fastapi
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"

# postgresql database: fastapi_db
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -tAc \
  "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

# PostgreSQL connectivity using role fastapi and database fastapi_db
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_database(), current_user;"

# Verify the database grant
sudo -u postgres psql -tAc \
  "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"

# Verify the fastapi-tutorial environment file
grep -Fx 'PROJECT_NAME="FastAPI Tutorial"' /opt/fastapi-tutorial/.env
grep -Fx 'API_VERSION=1.0.0' /opt/fastapi-tutorial/.env
grep -Fx 'DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db' \
  /opt/fastapi-tutorial/.env
stat -c '%a %U:%G %n' /opt/fastapi-tutorial/.env
# Chef baseline: 644 root:root /opt/fastapi-tutorial/.env

# Verify the fastapi-tutorial systemd unit
systemctl cat fastapi-tutorial
grep -Fx 'WorkingDirectory=/opt/fastapi-tutorial' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Environment="PATH=/opt/fastapi-tutorial/venv/bin"' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Restart=always' /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'After=network.target postgresql.service' \
  /etc/systemd/system/fastapi-tutorial.service

# Confirm EnvironmentFile is absent, matching Chef behavior
systemctl cat fastapi-tutorial | grep -F 'EnvironmentFile=' \
  && echo 'Unexpected EnvironmentFile setting found' \
  || echo 'No EnvironmentFile configured, matching Chef behavior'

# fastapi-tutorial service status
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager

# Confirm the Uvicorn process and listener
ps -ef | grep '[u]vicorn app.main:app --host 0.0.0.0 --port 8000'
ss -ltnp | grep ':8000'
lsof -nP -iTCP:8000 -sTCP:LISTEN

# Verify HTTP reachability
curl --verbose --max-time 10 http://127.0.0.1:8000/

# Review service logs and declared ordering
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager
journalctl -u fastapi-tutorial --since "15 minutes ago" --no-pager
systemctl show fastapi-tutorial -p After -p Wants -p Requires

# Storage checks
df -h /opt
du -sh /opt/fastapi-tutorial
```