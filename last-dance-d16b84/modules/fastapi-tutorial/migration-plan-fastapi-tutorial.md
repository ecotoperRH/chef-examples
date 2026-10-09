---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from the `main` branch of `https://github.com/dibanez/fastapi_tutorial.git` to `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, and PostgreSQL development packages; creates a Python virtual environment; installs application dependencies; creates the `fastapi` PostgreSQL role and `fastapi_db` database; writes an environment file and systemd unit; and enables and starts the `fastapi-tutorial` service on TCP port `8000`. The database password is currently hardcoded as `fastapi_password` in the recipe and generated environment file. The migration should store this value in Ansible Vault.

## Service Type and Instances

**Service Type**: Application server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Repository revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Application entry point: `app.main:app`
  - ASGI server: `/opt/fastapi-tutorial/venv/bin/uvicorn`
  - Listen address: `0.0.0.0`
  - Port/Socket: TCP `8000`
  - Service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Restart policy: `Restart=always`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`

- **postgresql**: PostgreSQL database service
  - Managed service name: `postgresql`
  - Service action: enabled and started
  - Database user: `fastapi`
  - Database name: `fastapi_db`
  - Database owner: `fastapi`
  - Connection host: `localhost`
  - Port/Socket: TCP `5432`; PostgreSQL may also create its distribution-default Unix socket
  - Privileges: `fastapi` receives all privileges on `fastapi_db`

There are no collection attributes or `.each` iterations. The cookbook configures exactly one FastAPI service and one PostgreSQL role/database pair.

## File Structure

Only the recipe file is executed or referenced by the supplied execution tree. No providers, templates, attribute files, or static deployed files are listed.

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

The `.env` file and systemd unit are generated using inline Chef `file` resources rather than cookbook template files.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following seven system packages with one package resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the virtual environment with:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
     The command is guarded by the existence of `/opt/fastapi-tutorial/venv`.
   - Installs dependencies from `/opt/fastapi-tutorial/requirements.txt` using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
     with `/opt/fastapi-tutorial` as the working directory.
   - Enables and starts `postgresql`.
   - Runs PostgreSQL initialization as the `postgres` operating-system user:
     ```bash
     sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true
     sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true
     sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true
     ```
     Existing-user, existing-database, and grant errors are suppressed by `|| true`. The Ansible migration should use idempotent `community.postgresql` modules instead.
   - Creates `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`. Its current content is:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
     The migrated version should source the password from Ansible Vault and preferably use mode `0600`.
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`. The unit contains:
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
   - Defines `execute[systemd_reload]`, running `systemctl daemon-reload` only when notified.
   - The systemd unit file notifies `execute[systemd_reload]` immediately when changed.
   - Enables and starts `fastapi-tutorial` after packages, the application directory, repository, virtual environment, dependencies, PostgreSQL, database role, database, `.env`, systemd unit, and systemd reload are complete.
   - No `.each` loops or collection iterations are present.

## Dependencies

**External cookbook dependencies**: None listed in the supplied metadata.

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

**Application source dependency**: `https://github.com/dibanez/fastapi_tutorial.git`

**Repository revision**: `main`

**Ansible collection dependency**:

- `community.postgresql` for PostgreSQL users, databases, and privileges

## Credentials

**Detection Summary**: 1 database credential detected across 1 file, with the same secret used in two locations.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: None
- **Path**: None
- **Current storage**: Plaintext recipe content and generated `.env` content

### PostgreSQL `fastapi` User Password

- **Variable(s)**:
  - Literal password: `fastapi_password`
  - Connection string: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Recommended Ansible variable: `fastapi_database_password`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the recipe and written to `/opt/fastapi-tutorial/.env`
- **Usage context**:
  - Used by `CREATE USER fastapi WITH PASSWORD 'fastapi_password'`.
  - Embedded in the `DATABASE_URL` written to `/opt/fastapi-tutorial/.env`.
  - The `.env` file uses mode `0644`, making the credential readable by local users with read access.
- **Migration recommendation**:
  - Store the password in Ansible Vault.
  - Use `fastapi_database_password` for both PostgreSQL user creation and the application connection string.
  - Prefer mode `0600` for `/opt/fastapi-tutorial/.env` unless exact Chef mode compatibility is required.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk/Conjur integrations, environment-variable secret references, TLS certificate references, API keys, or tokens were detected.

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`

**Service endpoints to check**:

- FastAPI: `0.0.0.0:8000`
- PostgreSQL: `localhost:5432`

**Service logs to check**:

- `journalctl -u fastapi-tutorial`
- `journalctl -u postgresql`

**Templates rendered**:

- None.
- Inline `.env` content: 1 render.
- Inline systemd unit content: 1 render.

No dedicated application log file or explicit application Unix socket is configured.

## Pre-flight checks

### Package and filesystem checks

```bash
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev
ls -ld /opt/fastapi-tutorial
ls -ld /opt/fastapi-tutorial/venv
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
```

On RPM-based systems:

```bash
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev
```

### PostgreSQL instance checks

```bash
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql
ss -tlnp | grep ':5432'
sudo -u postgres psql -h localhost -p 5432 -d fastapi_db -c "SELECT 1;"
```

Expected results:

- `postgresql` is enabled and active.
- PostgreSQL is listening on TCP port `5432`.
- The database query succeeds.

### PostgreSQL role checks

```bash
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
```

Expected result:

```text
fastapi
```

### PostgreSQL database and privilege checks

```bash
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -d fastapi_db -c "SELECT current_database(), current_user;"
sudo -u postgres psql -d fastapi_db -c "\l+ fastapi_db"
sudo -u postgres psql -d fastapi_db -c "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"
```

Expected results:

- The database query returns `fastapi_db`.
- The connection query succeeds.
- The privilege query returns `t`.

### FastAPI instance checks

```bash
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
pgrep -af '/opt/fastapi-tutorial/venv/bin/uvicorn'
ss -tlnp | grep ':8000'
curl -I http://127.0.0.1:8000/
curl -sS http://127.0.0.1:8000/
```

Expected results:

- `fastapi-tutorial` is enabled and active.
- The running process uses `/opt/fastapi-tutorial/venv/bin/uvicorn`.
- The command includes `--host 0.0.0.0 --port 8000`.
- The service listens on TCP port `8000`.
- The HTTP request reaches FastAPI. A `404` is acceptable if the application does not define a root route.

### Environment file checks

```bash
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env
```

Expected configuration keys:

```text
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:<vault-supplied-password>@localhost/fastapi_db
```

Do not print the actual password in shared logs or migration output.

### Systemd unit checks

```bash
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -E '^(Description|After|Type|User|WorkingDirectory|Environment|ExecStart|Restart|WantedBy)' \
  /etc/systemd/system/fastapi-tutorial.service
systemctl daemon-reload
```

Verify that the unit contains:

```text
After=network.target postgresql.service
User=root
WorkingDirectory=/opt/fastapi-tutorial
Environment="PATH=/opt/fastapi-tutorial/venv/bin"
ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
```

### Application process and log checks

```bash
ps aux | grep '[u]vicorn app.main:app'
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u postgresql --no-pager -n 100
```

Check for:

- Successful Uvicorn startup.
- Successful binding to `0.0.0.0:8000`.
- Successful PostgreSQL startup.
- No database authentication failures.
- No repeated application restart loop.

### Restart behavior checks

```bash
sudo systemctl restart fastapi-tutorial
systemctl is-active fastapi-tutorial
curl -I http://127.0.0.1:8000/
```

Expected result:

- `fastapi-tutorial` returns to the active state.
- The FastAPI endpoint becomes reachable again after restart.