---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the **fastapi-tutorial** FastAPI/Uvicorn application from the `main` branch of `https://github.com/dibanez/fastapi_tutorial.git` to `/opt/fastapi-tutorial`. It installs Python, Git, and PostgreSQL packages; creates a Python virtual environment; installs application requirements; provisions PostgreSQL database **fastapi_db** and role **fastapi**; writes an application `.env` file and systemd unit; and enables and starts PostgreSQL and the FastAPI service. The application listens on TCP port **8000** on `0.0.0.0`; PostgreSQL uses its package-default listener configuration, normally TCP port **5432**.

## Service Type and Instances

**Service Type**: Application Server with PostgreSQL Database dependency

**Configured Instances**:
- **fastapi-tutorial**: FastAPI/Uvicorn application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Run user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Startup command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Key Config: `Restart=always`; `PATH=/opt/fastapi-tutorial/venv/bin`

- **postgresql**: PostgreSQL database service used by the FastAPI application
  - Location/Path: Package-default PostgreSQL data and configuration paths
  - Port/Socket: Package-default TCP port `5432` on `localhost`; no Unix socket path is explicitly configured
  - Key Config: Database `fastapi_db`; role and owner `fastapi`; role receives `ALL PRIVILEGES ON DATABASE fastapi_db`; application connection URL is `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

## File Structure

**Recipes:**
```text
recipes/default.rb
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

The cookbook uses inline `file` resources rather than ERB templates or deployed static cookbook files.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following system packages through one `package` resource:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - No package versions are specified. The migration must install the distribution-default versions from enabled repositories. On CentOS/RHEL-family systems, package availability and PostgreSQL service naming must be verified because names may differ by release or repository.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the Python virtual environment by running `python3 -m venv /opt/fastapi-tutorial/venv` only when `/opt/fastapi-tutorial/venv` does not already exist.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using `/opt/fastapi-tutorial/venv/bin/pip`. The Chef resource runs on every convergence and relies on pip to determine whether changes are needed.
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi` with the password `fastapi_password`, creates database `fastapi_db` owned by `fastapi`, and grants `ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi`.
   - The original database commands use `|| true`, suppressing both expected already-exists errors and unexpected provisioning failures. The migration should use idempotent PostgreSQL modules, execute as the local `postgres` operating-system account, and install a PostgreSQL Python driver such as `python3-psycopg2` when required.
   - Writes `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and Chef mode `0644`. Its content is:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - The migration should source the database password from AAP credentials or Ansible Vault, mark secret-handling tasks `no_log: true`, and use mode `0600` for `/opt/fastapi-tutorial/.env`. The service runs as `root`, so `root:root` ownership remains compatible.
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`. Its content is:
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
   - Immediately runs `systemctl daemon-reload` only when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts the `fastapi-tutorial` service.
   - The unit ordering `After=network.target postgresql.service` does not guarantee PostgreSQL is ready for database connections. The migration must explicitly wait for PostgreSQL readiness before starting `fastapi-tutorial`.
   - Iterations: None. There are no collection attributes or Chef `.each` loops in the execution tree.

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
- PostgreSQL Python driver for Ansible database modules, typically `python3-psycopg2` or a platform-equivalent package

**Service dependencies**:
- `postgresql` must be enabled, started, and accepting local connections before provisioning `fastapi`, `fastapi_db`, and database privileges.
- `fastapi-tutorial` depends on `postgresql` and `network.target` through its systemd unit ordering.
- `fastapi-tutorial` must be restarted when the Git checkout, Python dependencies, `.env`, or systemd unit changes.

## Credentials

**Detection Summary**: 1 credential value detected in 1 file, used in 2 configuration contexts.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### FastAPI PostgreSQL Password
- **Variable(s)**:
  - Literal password: `fastapi_password`
  - Connection value: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the `execute[create_db_user]` SQL commands and inline `file[/opt/fastapi-tutorial/.env]` content.
- **Usage context**:
  - Sets the password for PostgreSQL role `fastapi`.
  - Authenticates the FastAPI application to PostgreSQL database `fastapi_db` through `DATABASE_URL`.

The migration must store this value as `fastapi_database_password` in an AAP credential or Ansible Vault-encrypted variable. It must not retain `fastapi_password` in plaintext Git repositories, inventory, playbooks, task output, or CI logs. PostgreSQL user creation and `.env` deployment tasks must use `no_log: true`.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk/Conjur integration, environment-variable secret references, or TLS certificate/key references were detected.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**: TCP port `8000`, bound to `0.0.0.0`
- **postgresql**: Package-default TCP port `5432`, normally on `localhost`
- No Unix socket path is explicitly configured by this cookbook.

**Templates rendered**:
- No ERB templates are rendered.
- Inline content is written once to `/opt/fastapi-tutorial/.env`.
- Inline content is written once to `/etc/systemd/system/fastapi-tutorial.service`.

## Pre-flight checks:
```bash
# Confirm the expected application checkout and virtual environment exist.
test -d /opt/fastapi-tutorial && echo "Application directory exists"
test -d /opt/fastapi-tutorial/venv && echo "Virtual environment exists"
test -f /opt/fastapi-tutorial/requirements.txt && echo "Requirements file exists"
test -x /opt/fastapi-tutorial/venv/bin/uvicorn && echo "Uvicorn executable exists"

# Confirm required system packages on Debian/Ubuntu systems.
dpkg-query -W -f='${binary:Package} ${Version}\n' \
  python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# PostgreSQL instance: service status and process.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager
ps -ef | grep '[p]ostgres'

# PostgreSQL instance: readiness on the package-default TCP port.
pg_isready -h localhost -p 5432 -d fastapi_db -U fastapi

# PostgreSQL database: confirm fastapi_db exists and is owned by fastapi.
sudo -u postgres psql -d postgres -tAc \
  "SELECT datname || ':' || pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

# PostgreSQL role: confirm fastapi exists.
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"

# PostgreSQL application connectivity.
PGPASSWORD="${FASTAPI_DATABASE_PASSWORD}" psql \
  -h localhost -p 5432 -U fastapi -d fastapi_db \
  -c 'SELECT current_database(), current_user;'

# Confirm non-secret FastAPI environment configuration.
grep -E '^PROJECT_NAME="FastAPI Tutorial"$' /opt/fastapi-tutorial/.env
grep -E '^API_VERSION=1\.0\.0$' /opt/fastapi-tutorial/.env
grep -E '^DATABASE_URL=postgresql://fastapi:' /opt/fastapi-tutorial/.env

# Inspect file ownership and permissions.
stat -c '%a %U:%G %n' /opt/fastapi-tutorial/.env
stat -c '%a %U:%G %n' /etc/systemd/system/fastapi-tutorial.service

# Validate the fastapi-tutorial systemd unit.
systemctl daemon-reload
systemctl cat fastapi-tutorial
systemctl show fastapi-tutorial \
  -p User -p WorkingDirectory -p ExecStart -p Restart -p ActiveState -p SubState
systemctl show fastapi-tutorial -p LoadState -p FragmentPath

# fastapi-tutorial instance: service status and process.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager
ps -ef | grep '[u]vicorn app.main:app'

# fastapi-tutorial instance: confirm the explicit listener and local HTTP reachability.
ss -ltnp | grep ':8000'
curl -sS -I --max-time 10 http://127.0.0.1:8000/

# Review service journals and check for FastAPI startup failures.
journalctl -u postgresql -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager | grep -Ei 'traceback|error|failed' || true
```