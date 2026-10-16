---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from the `main` branch of `https://github.com/dibanez/fastapi_tutorial.git` to `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, PostgreSQL development libraries, and application dependencies; creates a Python virtual environment; creates the PostgreSQL user `fastapi` and database `fastapi_db`; writes `/opt/fastapi-tutorial/.env`; and manages the `fastapi-tutorial.service` systemd unit. The application runs as `root` with Uvicorn on `0.0.0.0:8000` and uses PostgreSQL on `localhost:5432`.

## Service Type and Instances

**Service Type**: Application Server with PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application launched by Uvicorn
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Repository revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Application entry point: `app.main:app`
  - Process command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - systemd unit: `fastapi-tutorial.service`
  - Unit path: `/etc/systemd/system/fastapi-tutorial.service`
  - Runs as user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Restart policy: `Restart=always`
  - Listening address: `0.0.0.0`
  - Port: `8000`
  - Environment file: `/opt/fastapi-tutorial/.env`

- **postgresql**: PostgreSQL database service used by the FastAPI application
  - systemd service name: `postgresql`
  - Actions: enabled and started
  - Database user: `fastapi`
  - Database password: `fastapi_password`
  - Database: `fastapi_db`
  - Database owner: `fastapi`
  - Connection host: `localhost`
  - Connection port: `5432`, implied by PostgreSQL's default port because no port is specified in the connection URL

## File Structure

```text
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
├── providers/
├── templates/
├── attributes/
└── files/
```

**Recipes:**

```text
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers:**

```text
```

No custom resources or provider files are used.

**Templates:**

```text
```

No ERB templates are rendered. Configuration is written using inline Chef `file` resources.

**Attributes:**

```text
```

No attribute files are listed or used.

**Files:**

```text
```

No static files from `files/default/` or `files/` are deployed by `cookbook_file` or `remote_file`.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Uses one `package` resource containing seven package names.
   - The Ansible migration should use `ansible.builtin.package` with the same package names.

2. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial` recursively.
   - Sets owner `root`, group `root`, and mode `0755`.
   - Uses one `directory` resource.
   - The Ansible migration should use `ansible.builtin.file` with `state: directory`.

3. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` into `/opt/fastapi-tutorial`.
   - Checks out revision `main`.
   - Uses one `git` resource with action `sync`.
   - The repository is synchronized after directory creation and before virtual-environment and dependency installation.

4. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates the virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv`.
   - Uses `execute[create_venv]`.
   - Runs only when `/opt/fastapi-tutorial/venv` does not exist.
   - The Ansible equivalent should use `ansible.builtin.command` with `creates: /opt/fastapi-tutorial/venv`.

5. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs dependencies from `/opt/fastapi-tutorial/requirements.txt`.
   - Executes `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt` in `/opt/fastapi-tutorial`.
   - Uses `execute[install_dependencies]` with action `run`.
   - The task runs after repository synchronization and virtual-environment creation.

6. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Enables and starts the `postgresql` service.
   - Uses `service[postgresql]` with actions `enable` and `start`.
   - The service is started before database initialization.

7. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Runs the following commands as the PostgreSQL operating-system user:
     - `sudo -u postgres psql -c "CREATE USER fastapi WITH PASSWORD 'fastapi_password';" || true`
     - `sudo -u postgres psql -c "CREATE DATABASE fastapi_db OWNER fastapi;" || true`
     - `sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;" || true`
   - Creates or attempts to create role `fastapi`, database `fastapi_db`, and the database privileges.
   - Uses `execute[create_db_user]` with action `run`.
   - The `|| true` suffix intentionally suppresses errors, including errors caused by already-existing roles or databases.
   - The preferred Ansible implementation uses `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_privs` for idempotency.

8. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Writes `/opt/fastapi-tutorial/.env`.
   - Content:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - Sets owner `root`, group `root`, and mode `0644`.
   - Uses `file[/opt/fastapi-tutorial/.env]`.
   - The database password is exposed in the file and in the database URL.
   - The Ansible migration should use `ansible.builtin.copy` or `ansible.builtin.template`, preferably with the password supplied from Ansible Vault.

9. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Writes `/etc/systemd/system/fastapi-tutorial.service`.
   - Sets owner `root`, group `root`, and mode `0644`.
   - Unit contents:
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
   - Uses `file[/etc/systemd/system/fastapi-tutorial.service]`.
   - The unit starts after `network.target` and `postgresql.service`.
   - The file resource immediately notifies `execute[systemd_reload]`.

10. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Defines `execute[systemd_reload]` with command `systemctl daemon-reload`.
    - Uses action `nothing` by default.
    - Runs immediately only when `/etc/systemd/system/fastapi-tutorial.service` changes.
    - The Ansible equivalent is a handler using `ansible.builtin.systemd` with `daemon_reload: true`.

11. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Enables and starts the `fastapi-tutorial` service.
    - Uses `service[fastapi-tutorial]` with actions `enable` and `start`.
    - Runs after the systemd unit is installed and systemd has been reloaded.
    - The Ansible equivalent should use `ansible.builtin.systemd` with `name: fastapi-tutorial`, `enabled: true`, and `state: started`.

There are no `.each` loops or collection attributes. The only configured application instance is `fastapi-tutorial`, and the only configured database service is `postgresql`.

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

**Service dependencies**:

- `postgresql`
- `fastapi-tutorial`

**Application dependency relationship**:

- `fastapi-tutorial.service` declares `After=postgresql.service`.
- The application connects to PostgreSQL at `localhost:5432`.
- The application uses database `fastapi_db` and role `fastapi`.
- The application starts through Uvicorn on port `8000`.

## Credentials

**Detection Summary**: 1 credential detected in 1 recipe file. The same credential is represented in the PostgreSQL role creation command and the application database URL.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: None
- **Path**: None

### PostgreSQL application password

- **Variable(s)**:
  - PostgreSQL password for user `fastapi`: `fastapi_password`
  - Embedded database URL: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the recipe and written to `/opt/fastapi-tutorial/.env`
- **Usage context**:
  - Used to create the PostgreSQL role `fastapi`
  - Used in the application's PostgreSQL connection string
- **Security concern**:
  - `/opt/fastapi-tutorial/.env` has mode `0644`, making the password readable by all local users.
  - The systemd unit runs the application as `root`, but the credential is stored in the application environment file rather than passed through systemd.
- **Ansible migration recommendation**:
  - Store the password in Ansible Vault.
  - Use the vaulted value in the PostgreSQL user task.
  - Use the same vaulted value when rendering `.env`.
  - Consider mode `0600` for `.env` if changing the Chef file permissions is acceptable.

No data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, cloud secret manager, environment-variable lookups, TLS certificates, private keys, or API tokens were detected.

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/opt/fastapi-tutorial/venv`
- `/etc/systemd/system/fastapi-tutorial.service`

**Application data directory**:

- `/opt/fastapi-tutorial`

**Database objects to verify**:

- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`
- Database owner `fastapi`

**Service endpoints to check**:

- FastAPI HTTP endpoint: `0.0.0.0:8000`
- PostgreSQL endpoint: `localhost:5432`

**Unix sockets**:

- No application Unix socket is configured.
- PostgreSQL socket path is not explicitly configured.

**Templates rendered**:

- ERB templates: 0
- `/opt/fastapi-tutorial/.env`: written once by an inline Chef `file` resource
- `/etc/systemd/system/fastapi-tutorial.service`: written once by an inline Chef `file` resource

## Pre-flight checks:

```bash
# Confirm required packages
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Confirm the fastapi-tutorial application directory
stat -c '%A %U:%G %n' /opt/fastapi-tutorial
test -d /opt/fastapi-tutorial
test -f /opt/fastapi-tutorial/requirements.txt

# Confirm the repository and main revision
git -C /opt/fastapi-tutorial status --short --branch
git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD
test "$(git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD)" = "main"

# Confirm the fastapi-tutorial virtual environment
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version
/opt/fastapi-tutorial/venv/bin/pip check

# Confirm the postgresql service
systemctl status postgresql --no-pager
systemctl is-enabled postgresql
systemctl is-active postgresql
ss -ltnp | grep ':5432'

# Confirm the fastapi PostgreSQL role
sudo -u postgres psql -tAc \
  "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"

# Confirm the fastapi_db database and owner
sudo -u postgres psql -tAc \
  "SELECT datname, pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

# Confirm fastapi can connect to fastapi_db
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_database(), current_user;"

# Confirm database privileges
sudo -u postgres psql -d fastapi_db -c "\l+ fastapi_db"

# Verify the FastAPI environment file
stat -c '%A %U:%G %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION)=' /opt/fastapi-tutorial/.env
sed 's#://[^:]*:[^@]*@#://***:***@#' /opt/fastapi-tutorial/.env | grep '^DATABASE_URL='

# Verify the fastapi-tutorial systemd unit
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
systemctl daemon-reload
systemctl cat fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial --no-pager
systemctl show fastapi-tutorial \
  --property=ExecStart,User,WorkingDirectory,Restart

# Confirm the FastAPI process and endpoint
ps aux | grep '[u]vicorn app.main:app'
ss -ltnp | grep ':8000'
curl -i http://127.0.0.1:8000/
curl -i http://127.0.0.1:8000/docs
curl -i http://127.0.0.1:8000/openapi.json

# Check service logs
journalctl -u postgresql --no-pager -n 100
journalctl -u fastapi-tutorial --no-pager -n 100
systemctl show fastapi-tutorial --property=Result,ExecMainStatus,ExecMainCode

# Verify the application database connection and service dependency
systemctl is-active postgresql
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT 1;"
systemctl is-active fastapi-tutorial
```

Expected values:

```text
Application instance: fastapi-tutorial
Database service: postgresql
PostgreSQL role: fastapi
PostgreSQL database: fastapi_db
Database owner: fastapi
FastAPI bind address: 0.0.0.0
FastAPI port: 8000
Database endpoint: localhost:5432
Environment project name: FastAPI Tutorial
Environment API version: 1.0.0
```