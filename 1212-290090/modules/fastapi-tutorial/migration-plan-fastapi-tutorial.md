---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` under `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, and PostgreSQL development packages; creates a Python virtual environment; installs application dependencies; configures the `postgresql` service with the `fastapi` role and `fastapi_db` database; writes an environment file containing the database connection string; and manages a systemd service named `fastapi-tutorial` that runs Uvicorn on port `8000`.

## Service Type and Instances

**Service Type**: Application Server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application served by Uvicorn
  - Location/Path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Repository revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - WSGI/ASGI application: `app.main:app`
  - Application server: Uvicorn
  - Bind address: `0.0.0.0`
  - Port/Socket: TCP `8000`
  - Service user: `root`
  - Working directory: `/opt/fastapi-tutorial`
  - Restart policy: `Restart=always`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`

- **postgresql**: PostgreSQL database service used by the FastAPI application
  - Managed service: `postgresql`
  - Database user: `fastapi`
  - Database: `fastapi_db`
  - Database owner: `fastapi`
  - Database connection host: `localhost`
  - Database port: `5432` by default
  - Database connection string: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

There are no collection attributes or `.each` iterations in the execution tree.

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

The cookbook does not use custom resources, provider files, ERB templates, attribute files, or deployed static files.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the seven system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev` without version pinning.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` into `/opt/fastapi-tutorial` at revision `main`.
   - Creates the virtual environment with `python3 -m venv /opt/fastapi-tutorial/venv`, guarded by the existence of `/opt/fastapi-tutorial/venv`.
   - Installs dependencies from `/opt/fastapi-tutorial/requirements.txt` into `/opt/fastapi-tutorial/venv`.
   - Enables and starts the `postgresql` service.
   - Creates the PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates the PostgreSQL database `fastapi_db` owned by `fastapi`.
   - Grants all privileges on `fastapi_db` to `fastapi`.
   - Preserves the original shell-command behavior, where database creation commands use `|| true`; the Ansible migration should use native PostgreSQL modules for stronger idempotence.
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
   - Immediately notifies `systemd_reload` when the systemd unit changes.
   - Runs `systemctl daemon-reload` only when notified by the changed unit file.
   - Enables and starts the `fastapi-tutorial` service after the repository, virtual environment, dependencies, PostgreSQL service, database objects, `.env` file, and systemd unit are ready.
   - Iterations: none.

**Ansible implementation requirements**:

- Use `ansible.builtin.package` with the seven exact package names and `state: present`.
- Use `ansible.builtin.file` for `/opt/fastapi-tutorial`.
- Use `ansible.builtin.git` for the repository checkout.
- Use `ansible.builtin.command` with `creates: /opt/fastapi-tutorial/venv` for virtual-environment creation.
- Use `ansible.builtin.pip` with the requirements file and virtual environment, or preserve the exact command behavior with `ansible.builtin.command`.
- Use `ansible.builtin.service` for `postgresql`.
- Use `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_privs` for PostgreSQL configuration.
- Use an Ansible Vault variable for `fastapi_password` when creating the database role and rendering `DATABASE_URL`.
- Use `ansible.builtin.copy` or `ansible.builtin.template` for `.env` and the systemd unit.
- Notify a handler using `ansible.builtin.systemd` with `daemon_reload: true` only when the systemd unit changes.
- Enable and start `fastapi-tutorial` after the daemon reload and all application and database prerequisites are complete.

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

**Application source dependency**:

- Repository: `https://github.com/dibanez/fastapi_tutorial.git`
- Revision: `main`

**Ansible collection dependency**:

- `community.postgresql`

## Credentials

**Detection Summary**: 2 credential references detected in 2 source locations, representing the same PostgreSQL credential. The PostgreSQL username is also a hardcoded configuration value.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: No secret-management URL detected
- **Path**: No Vault, CyberArk, AWS Secrets Manager, data bag, or encrypted data bag path detected

### PostgreSQL database password

- **Variable(s)**:
  - Inline password: `fastapi_password`
  - Database URL: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded in the recipe and repeated in `/opt/fastapi-tutorial/.env`
- **Usage context**:
  - Creates PostgreSQL user `fastapi`
  - Authenticates the application to `fastapi_db`
  - Supplies the password in `/opt/fastapi-tutorial/.env`
- **Migration handling**: Store the password in Ansible Vault and use the vaulted value for both PostgreSQL role creation and `DATABASE_URL`.

### PostgreSQL database username

- **Variable(s)**:
  - PostgreSQL role: `fastapi`
  - Database URL username: `fastapi`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded configuration value
- **Usage context**:
  - PostgreSQL role creation
  - Ownership of `fastapi_db`
  - Application database connection

### Credential mechanisms not detected

The cookbook contains no detected usage of:

- `data_bag_item`
- `encrypted_data_bag_item`
- `chef_vault_item`
- `ChefVault::Item`
- `conjur_variable`
- CyberArk data bags
- `node['vault']`
- `node['secrets']`
- Environment-variable secret lookups such as `ENV['PASSWORD']`
- TLS certificates, private keys, or certificate paths
- API keys or tokens

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Database objects to verify**:

- PostgreSQL role: `fastapi`
- PostgreSQL database: `fastapi_db`
- Database owner: `fastapi`

**Service endpoints to check**:

- `fastapi-tutorial`: TCP port `8000`
- `postgresql`: `localhost:5432` and the platform-default PostgreSQL Unix socket

**Templates rendered**:

- No ERB or Ansible templates are present in the cookbook.
- `/opt/fastapi-tutorial/.env`: inline Chef file content rendered once
- `/etc/systemd/system/fastapi-tutorial.service`: inline Chef file content rendered once

## Pre-flight checks

### Package and application checks for `fastapi-tutorial`

```bash
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev 2>/dev/null || \
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

test -d /opt/fastapi-tutorial
test -d /opt/fastapi-tutorial/venv
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -f /opt/fastapi-tutorial/.env
test -f /etc/systemd/system/fastapi-tutorial.service

git -C /opt/fastapi-tutorial rev-parse --abbrev-ref HEAD
git -C /opt/fastapi-tutorial rev-parse HEAD

/opt/fastapi-tutorial/venv/bin/pip check
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/uvicorn --version
```

The checked-out branch or revision must correspond to `main`.

### PostgreSQL checks for `postgresql`

```bash
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql

sudo -u postgres psql -tAc "SELECT 1;"
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname='fastapi';"
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname='fastapi_db';"
sudo -u postgres psql -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='fastapi_db';"
```

The database-owner query must return:

```text
fastapi
```

Test application credentials and database connectivity:

```bash
PGPASSWORD='fastapi_password' \
psql -h localhost -U fastapi -d fastapi_db -c "SELECT current_user, current_database();"
```

### Environment file validation for `fastapi-tutorial`

```bash
stat -c '%U %G %a %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env
```

Expected configuration keys:

```text
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
```

Do not print the complete `.env` file in routine CI logs because it contains a database password.

### Systemd validation for `fastapi-tutorial`

```bash
systemctl cat fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl show fastapi-tutorial --property=User,WorkingDirectory,ExecStart,Restart

grep -E '^(Description|After|Type|User|WorkingDirectory|Environment|ExecStart|Restart|WantedBy)=' \
  /etc/systemd/system/fastapi-tutorial.service
```

The unit must use:

```text
/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Endpoint and port validation for `fastapi-tutorial`

```bash
curl -i http://127.0.0.1:8000/
ss -tlnp | grep ':8000'
lsof -iTCP:8000 -sTCP:LISTEN
```

The service must accept TCP connections on port `8000`. The exact HTTP status for `/` depends on the checked-out tutorial application.

### Process and log validation for `fastapi-tutorial`

```bash
ps aux | grep '[u]vicorn app.main:app'
journalctl -u fastapi-tutorial --no-pager -n 50
```

The Uvicorn process must use:

```text
/opt/fastapi-tutorial/venv/bin/uvicorn
```

### PostgreSQL log validation for `postgresql`

```bash
journalctl -u postgresql --no-pager -n 50
```

Verify that the service is active and that no startup, authentication, or database-creation errors are present.

### Systemd reload behavior for `fastapi-tutorial`

After changing the systemd unit through Ansible, verify the handler behavior:

```bash
systemctl daemon-reload
systemctl restart fastapi-tutorial
systemctl status fastapi-tutorial
```

The Ansible implementation should normally use a notified handler rather than running `systemctl daemon-reload` unconditionally.