---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI Tutorial application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` under `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, and PostgreSQL development packages; creates a Python virtual environment; installs the application requirements; creates the PostgreSQL role `fastapi` and database `fastapi_db`; writes `/opt/fastapi-tutorial/.env`; and manages the `fastapi-tutorial.service` systemd unit. The application listens on `0.0.0.0:8000` and uses PostgreSQL on `localhost`.

## Service Type and Instances

**Service Type**: Application Server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application server
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Location/Path: `/opt/fastapi-tutorial`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Port/Socket: TCP `0.0.0.0:8000`
  - Startup command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - systemd unit: `fastapi-tutorial.service`
  - systemd user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Restart policy: `Restart=always`
  - Service ordering: After `network.target` and `postgresql.service`

- **postgresql**: PostgreSQL database service
  - Service name: `postgresql`
  - Service action: enabled and started
  - Database role: `fastapi`
  - Database name: `fastapi_db`
  - Database owner: `fastapi`
  - Database privilege: `ALL`
  - Application connection host: `localhost`

The cookbook declares these seven packages:

- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

## File Structure

```text
cookbooks/fastapi-tutorial/
└── recipes/
    └── default.rb
```

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

The cookbook creates `/opt/fastapi-tutorial/.env` and `/etc/systemd/system/fastapi-tutorial.service` inline through Chef `file` resources. It does not deploy Chef templates or static cookbook files.

## Module Explanation

The cookbook has one recipe, with no `include_recipe` calls. The execution order is as follows.

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the operating-system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Supports Ubuntu `>= 18.04` and CentOS `>= 7.0`; package-manager selection is required for the target distribution.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes the Git repository `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates the virtual environment by running `python3 -m venv /opt/fastapi-tutorial/venv` only when `/opt/fastapi-tutorial/venv` does not exist.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` into `/opt/fastapi-tutorial/venv` using `/opt/fastapi-tutorial/venv/bin/pip`.
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates database `fastapi_db` owned by `fastapi`.
   - Grants all privileges on database `fastapi_db` to `fastapi`.
   - The original Chef SQL commands use `|| true`, causing repeated executions to ignore errors such as an already-existing role or database. Native Ansible PostgreSQL modules are preferred for idempotent behavior.
   - Creates `/opt/fastapi-tutorial/.env` with:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - Sets the environment file owner to `root`, group to `root`, and mode to `0644`.
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`.
   - The systemd unit:
     - Describes the service as `FastAPI Tutorial Service`.
     - Starts after `network.target` and `postgresql.service`.
     - Runs as `root`.
     - Uses `/opt/fastapi-tutorial` as its working directory.
     - Sets `PATH` to `/opt/fastapi-tutorial/venv/bin`.
     - Executes `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`.
     - Uses `Restart=always`.
     - Is installed in `multi-user.target`.
   - Notifies the systemd reload resource immediately when `/etc/systemd/system/fastapi-tutorial.service` changes.
   - Runs `systemctl daemon-reload` only when notified by the unit-file resource.
   - Enables and starts `fastapi-tutorial.service`.

   **Iterations**:
   - No `.each` loops or iterable service-instance collections are present.
   - The package declaration contains the seven explicit package names: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.

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

**Application dependencies**:

- `/opt/fastapi-tutorial/requirements.txt`
- Python dependencies installed into `/opt/fastapi-tutorial/venv`

**Ansible-specific dependencies**:

- `community.postgresql` collection
- Python PostgreSQL driver required by the selected `community.postgresql` modules

**Service dependencies**:

- `postgresql.service` must be enabled and started before database setup.
- `fastapi-tutorial.service` starts after `network.target`.
- `fastapi-tutorial.service` starts after `postgresql.service`.
- The FastAPI service starts after its unit file is deployed and systemd has been reloaded.

## Credentials

**Detection Summary**: 1 credential detected across 2 source locations in `cookbooks/fastapi-tutorial/recipes/default.rb`.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: None
- **Path**: None

### PostgreSQL application password

- **Variable(s)**:
  - PostgreSQL password: `fastapi_password`
  - Embedded connection string: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext
- **Usage context**:
  - Creates PostgreSQL role `fastapi`.
  - Is written to `/opt/fastapi-tutorial/.env`.
  - Authenticates the FastAPI application to database `fastapi_db` on `localhost`.
- **Migration recommendation**:
  - Store the password in Ansible Vault.
  - Use the vaulted value for the PostgreSQL role task.
  - Generate `DATABASE_URL` from the same vaulted variable.
  - Do not commit the plaintext password to the Ansible repository.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk integration, Conjur references, environment-variable secret lookups, TLS certificates, private keys, or external secret-manager URLs were detected.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- `/opt/fastapi-tutorial/venv`
- The repository application source providing `app.main:app`

**Services and instances to verify**:

- `postgresql.service`
- `fastapi-tutorial.service`

**Service endpoints to check**:

- FastAPI: TCP `0.0.0.0:8000`
- PostgreSQL: TCP-style application connection through host `localhost`
- No application Unix socket is configured.

**Templates rendered**:

- None. No Chef `.erb` templates exist.
- `/opt/fastapi-tutorial/.env` is created by an inline Chef `file` resource.
- `/etc/systemd/system/fastapi-tutorial.service` is created by an inline Chef `file` resource.

## Pre-flight checks

Run the following checks on the target after the Ansible migration.

### Required packages and application instance `fastapi-tutorial`

```bash
# Verify required packages
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev 2>/dev/null || \
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Verify the application directory
ls -ld /opt/fastapi-tutorial
ls -la /opt/fastapi-tutorial

# Verify the repository checkout
git -C /opt/fastapi-tutorial status --short
git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD

# Verify the Python virtual environment
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/python --version

# Verify the requirements file
test -f /opt/fastapi-tutorial/requirements.txt
```

### PostgreSQL instance `postgresql`

```bash
# Verify PostgreSQL service state
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql

# Verify the PostgreSQL role
sudo -u postgres psql -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"

# Verify the database and owner
sudo -u postgres psql -tAc \
  "SELECT datname, pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

# Verify database privileges
sudo -u postgres psql -d fastapi_db -c "\l+ fastapi_db"

# Verify application-user connectivity
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_database(), current_user;"
```

Expected results:

- Role `fastapi` exists.
- Database `fastapi_db` exists.
- Database owner is `fastapi`.
- User `fastapi` can connect to database `fastapi_db`.

### Environment configuration for `fastapi-tutorial`

```bash
# Verify the environment file
test -f /opt/fastapi-tutorial/.env

# Verify non-secret keys
grep -E '^(PROJECT_NAME|API_VERSION)=' /opt/fastapi-tutorial/.env

# Verify database URL structure without exposing the password
grep '^DATABASE_URL=postgresql://fastapi:' /opt/fastapi-tutorial/.env

# Verify ownership and permissions
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
```

Expected values:

```text
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:<vaulted-password>@localhost/fastapi_db
```

### systemd instance `fastapi-tutorial`

```bash
# Verify the unit file
test -f /etc/systemd/system/fastapi-tutorial.service
cat /etc/systemd/system/fastapi-tutorial.service

# Verify important unit settings
grep -E '^(Description|After|Type|User|WorkingDirectory|Environment|ExecStart|Restart|WantedBy)=' \
  /etc/systemd/system/fastapi-tutorial.service

# Verify systemd syntax
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service

# Reload systemd after a unit change
systemctl daemon-reload

# Verify enablement and active state
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial
```

Expected service properties:

- Enabled at boot.
- Active and running.
- Executable:
  ```text
  /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
  ```
- Restart policy: `Restart=always`.

### FastAPI endpoint for `fastapi-tutorial`

```bash
# Verify the TCP listener
ss -tlnp | grep ':8000'
netstat -tlnp 2>/dev/null | grep ':8000'

# Request the application
curl -i http://127.0.0.1:8000/

# Verify the Uvicorn process
ps aux | grep '[u]vicorn app.main:app'
```

The listener should be bound to `0.0.0.0:8000`, and the HTTP request should return a response from the FastAPI application.

### Logs for `fastapi-tutorial` and `postgresql`

```bash
# FastAPI service logs
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u fastapi-tutorial -f

# PostgreSQL service logs
journalctl -u postgresql --no-pager -n 100
```

Verify the FastAPI logs for successful Uvicorn startup, successful application import, no database authentication failures, and no repeated restart loop. Verify the PostgreSQL logs for successful startup, no authentication failures for role `fastapi`, and no database availability errors.