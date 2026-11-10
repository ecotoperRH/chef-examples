---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` FastAPI/Uvicorn application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` to `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, and PostgreSQL development packages; creates a Python virtual environment; installs application dependencies; provisions the local PostgreSQL database `fastapi_db` and role `fastapi`; creates an application `.env` file; and runs Uvicorn as a root-owned systemd service listening on TCP port `8000`.

## Service Type and Instances

**Service Type**: Application Server (FastAPI/Uvicorn) with a local PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI Tutorial application systemd service
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Source revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Port/Socket: TCP `8000`, bound to `0.0.0.0`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Key Config: Runs as `root`, uses `Restart=always`, and starts after `network.target` and `postgresql.service`.

- **postgresql**: Local PostgreSQL service used by `fastapi-tutorial`
  - Location/Path: Platform PostgreSQL package configuration and data directories
  - Port/Socket: Not explicitly configured by the cookbook; validate the platform package default listener, normally TCP `5432`
  - Database: `fastapi_db`
  - Database role: `fastapi`
  - Database owner: `fastapi`
  - Connection URL configured for the application: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Key Config: Service is enabled and started before database provisioning and FastAPI service startup.

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
   - No package versions are pinned; installed versions are supplied by the configured operating-system repositories.
   - Creates `/opt/fastapi-tutorial` with owner `root`, group `root`, mode `0755`, and `recursive true`.
   - Synchronizes the Git repository `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial` using Chef action `sync`.
   - Creates the Python virtual environment with `execute[create_venv]`.
     - Command: `python3 -m venv /opt/fastapi-tutorial/venv`
     - Guard: Runs only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs application dependencies with `execute[install_dependencies]`.
     - Working directory: `/opt/fastapi-tutorial`
     - Command: `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`
     - The command runs during every Chef converge.
   - Enables and starts `service[postgresql]`.
   - Provisions PostgreSQL with `execute[create_db_user]`.
     - Creates PostgreSQL role `fastapi` with password `fastapi_password`.
     - Creates database `fastapi_db` owned by `fastapi`.
     - Grants all privileges on database `fastapi_db` to role `fastapi`.
     - The Chef commands use `|| true`, suppressing both duplicate-object errors and genuine provisioning failures.
   - Creates `/opt/fastapi-tutorial/.env` using `file[/opt/fastapi-tutorial/.env]`.
     - Owner: `root`
     - Group: `root`
     - Mode: `0644`
     - Content:
       ```dotenv
       PROJECT_NAME="FastAPI Tutorial"
       API_VERSION=1.0.0
       DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
       ```
   - Creates `/etc/systemd/system/fastapi-tutorial.service` using `file[/etc/systemd/system/fastapi-tutorial.service]`.
     - Owner: `root`
     - Group: `root`
     - Mode: `0644`
     - Content:
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
   - Reloads systemd with `execute[systemd_reload]`.
     - Command: `systemctl daemon-reload`
     - Default action: `nothing`
     - Trigger: Runs immediately when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Enables and starts `service[fastapi-tutorial]`.
   - A unit-file change triggers only a systemd daemon reload; it does not restart the running `fastapi-tutorial` service.
   - Iterations: None. There are no Chef collection attributes or `.each` loops in this cookbook.
   - Resources: package (1), directory (1), git (1), execute (4), file (2), service (2).

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
- `postgresql`
- `fastapi-tutorial`
- `systemd`
- `network.target`
- `postgresql.service`

**External source dependency**:
- Git repository: `https://github.com/dibanez/fastapi_tutorial.git`
- Revision: `main`

**Supported platforms from metadata**:
- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

## Credentials

**Detection Summary**: 1 hardcoded database credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### PostgreSQL Application Role Password

- **Variable(s)**:
  - PostgreSQL role: `fastapi`
  - Password value: `fastapi_password`
  - Connection setting: `DATABASE_URL`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded directly in the Chef recipe and embedded in `/opt/fastapi-tutorial/.env`.
- **Usage context**:
  - Creates PostgreSQL role `fastapi`.
  - Authenticates the FastAPI application to PostgreSQL database `fastapi_db`.
  - Forms the application connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db`.

**Migration handling**:
- Store the database password in an AAP credential, encrypted variable, or integrated enterprise secret manager.
- Use a protected variable such as `fastapi_db_password`.
- Build the PostgreSQL role password and `DATABASE_URL` from the protected value.
- Use `no_log: true` for tasks that process the password.
- Do not store the password in Git, plaintext inventory, playbook defaults, or rendered task output.
- Use mode `0600` for `/opt/fastapi-tutorial/.env` in the migration unless compatibility requires the Chef mode `0644`.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk/Conjur integration, HashiCorp Vault integration, AWS Secrets Manager integration, or TLS certificate/key references were detected.

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/.git`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- `/opt/fastapi-tutorial/venv/bin/uvicorn`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- **fastapi-tutorial**: HTTP listener on `0.0.0.0:8000`
  - `http://127.0.0.1:8000/openapi.json`
  - `http://127.0.0.1:8000/docs`
- **postgresql**: Effective local PostgreSQL listener and socket configuration
  - The cookbook does not explicitly configure a PostgreSQL port.
  - The application connects to `localhost`; validate the platform PostgreSQL package listener, normally TCP `5432`.

**Database objects to verify**:
- PostgreSQL role: `fastapi`
- PostgreSQL database: `fastapi_db`
- Database owner: `fastapi`
- Privilege grant: `fastapi` has privileges on `fastapi_db`

**Templates rendered**:
- None; 0 templates rendered. The cookbook uses Chef `file` resources with inline content.

## Pre-flight checks:
```bash
# Confirm installed package availability and versions.
python3 --version
git --version
psql --version
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version

# Verify the FastAPI application checkout and virtual environment.
test -d /opt/fastapi-tutorial
test -d /opt/fastapi-tutorial/.git
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
git -C /opt/fastapi-tutorial rev-parse HEAD
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/uvicorn

# Verify the PostgreSQL instance.
systemctl is-enabled postgresql
systemctl is-active postgresql
systemctl status postgresql --no-pager
journalctl -u postgresql -n 100 --no-pager
sudo -u postgres psql -d postgres -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
sudo -u postgres psql -d postgres -tAc \
  "SELECT datname || ':' || pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -d postgres -tAc \
  "SELECT has_database_privilege('fastapi', 'fastapi_db', 'CONNECT');"

# Verify fastapi can authenticate and connect to fastapi_db.
PGPASSWORD='<password from AAP credential>' \
psql -h localhost -U fastapi -d fastapi_db \
  -c "SELECT current_user, current_database();"

# Verify the application environment file without exposing its secret.
test -f /opt/fastapi-tutorial/.env
grep -E '^PROJECT_NAME="FastAPI Tutorial"$' /opt/fastapi-tutorial/.env
grep -E '^API_VERSION=1\.0\.0$' /opt/fastapi-tutorial/.env
grep -E '^DATABASE_URL=postgresql://fastapi:.*@localhost/fastapi_db$' \
  /opt/fastapi-tutorial/.env
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env

# Verify the fastapi-tutorial systemd unit.
test -f /etc/systemd/system/fastapi-tutorial.service
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'WorkingDirectory=/opt/fastapi-tutorial' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Environment="PATH=/opt/fastapi-tutorial/venv/bin"' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000' \
  /etc/systemd/system/fastapi-tutorial.service
grep -Fx 'Restart=always' /etc/systemd/system/fastapi-tutorial.service

# Verify the fastapi-tutorial instance.
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager
systemctl show fastapi-tutorial \
  --property=User,WorkingDirectory,ExecStart,Restart --no-pager
journalctl -u fastapi-tutorial -n 100 --no-pager

# Verify the exact configured Uvicorn listener.
ss -ltnp | grep ':8000'

# Verify FastAPI HTTP functionality.
curl --fail --silent --show-error \
  http://127.0.0.1:8000/openapi.json | python3 -m json.tool >/dev/null
curl --fail --silent --show-error --output /dev/null \
  --write-out '%{http_code}\n' http://127.0.0.1:8000/docs

# Verify automatic restart configuration.
systemctl show fastapi-tutorial --property=Restart --value
```