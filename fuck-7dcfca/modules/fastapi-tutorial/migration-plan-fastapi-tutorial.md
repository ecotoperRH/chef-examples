---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from the `main` branch of `https://github.com/dibanez/fastapi_tutorial.git` to `/opt/fastapi-tutorial`. It installs Python, Git, PostgreSQL, and PostgreSQL development packages; creates a Python virtual environment; installs application requirements; creates the `fastapi` PostgreSQL role and `fastapi_db` database; writes an environment file containing the database URL; and manages the `fastapi-tutorial` systemd service on `0.0.0.0:8000`.

## Service Type and Instances

**Service Type**: Application Server with a local PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application server
  - Application path: `/opt/fastapi-tutorial`
  - Source repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Repository revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Application command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app`
  - Listen address: `0.0.0.0`
  - Port: `8000`
  - Working directory: `/opt/fastapi-tutorial`
  - Runtime user: `root`
  - Restart policy: `Restart=always`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`

- **fastapi_db**: PostgreSQL database used by the FastAPI application
  - PostgreSQL owner: `fastapi`
  - Database user: `fastapi`
  - Database host: `localhost`
  - Database URL: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`

No collection attributes or `.each` iterations are present in the execution tree.

## File Structure

Only the recipe file is executed by this cookbook. No provider, template, attribute, or static deployed file is referenced by the execution tree.

```text
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
├── providers/
│   └── None
├── templates/
│   └── None
├── attributes/
│   └── None
└── files/
    └── None
```

The cookbook writes the `.env` file and systemd unit with inline Chef `file` resources rather than `.erb` templates or static files.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the seven system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates `/opt/fastapi-tutorial/venv` with `python3 -m venv /opt/fastapi-tutorial/venv`; the `creates` guard skips this command when the path exists.
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using `/opt/fastapi-tutorial/venv/bin/pip` with `/opt/fastapi-tutorial` as the working directory.
   - Enables and starts the `postgresql` service.
   - Creates the PostgreSQL role `fastapi` with password `fastapi_password`, creates the `fastapi_db` database owned by `fastapi`, and grants all privileges on `fastapi_db` to `fastapi`.
   - Writes `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`.
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`.
   - Immediately notifies `execute[systemd_reload]` when the systemd unit changes; the notification runs `systemctl daemon-reload`.
   - Enables and starts the `fastapi-tutorial` service.
   - No `.each` loops or repeated resource iterations require expansion.

   **Resources and execution order**:
   - `package` — installs `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - `directory[/opt/fastapi-tutorial]` — creates the application directory.
   - `git[/opt/fastapi-tutorial]` — synchronizes the application repository at `main`.
   - `execute[create_venv]` — creates `/opt/fastapi-tutorial/venv`.
   - `execute[install_dependencies]` — installs `/opt/fastapi-tutorial/requirements.txt`.
   - `service[postgresql]` — enables and starts PostgreSQL.
   - `execute[create_db_user]` — creates the PostgreSQL role, database, and grants.
   - `file[/opt/fastapi-tutorial/.env]` — writes the application environment file.
   - `file[/etc/systemd/system/fastapi-tutorial.service]` — writes the systemd unit.
   - `execute[systemd_reload]` — runs `systemctl daemon-reload` when the unit changes.
   - `service[fastapi-tutorial]` — enables and starts the FastAPI application.

   **Application environment file**:
   ```dotenv
   PROJECT_NAME="FastAPI Tutorial"
   API_VERSION=1.0.0
   DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
   ```

   **Systemd unit**:
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

   The migration should preserve the repository, revision, paths, service ordering, runtime user, Uvicorn command, port, bind address, and restart behavior. PostgreSQL package and service names should be verified for the target distribution. The original database shell commands use `|| true`; an Ansible migration should preferably use PostgreSQL-specific idempotent modules.

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

**Runtime dependency relationship**:
- `fastapi-tutorial.service` starts after `network.target` and `postgresql.service`.
- The application connects to PostgreSQL at `localhost`.
- PostgreSQL must be enabled and started before database initialization.
- The `fastapi` role and `fastapi_db` database must exist before the FastAPI service starts.

## Credentials

**Detection Summary**: 1 hardcoded database credential detected in 1 source file. The same credential is used in the PostgreSQL creation command and the application database URL.

**Source**:
- **Provider**: Hardcoded in the Chef recipe
- **URL**: None
- **Path**: `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL `fastapi` User Password

- **Variable(s)**:
  - Literal password: `fastapi_password`
  - Database URL: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded
- **Usage context**:
  - Used by `CREATE USER fastapi WITH PASSWORD 'fastapi_password'`
  - Embedded in `/opt/fastapi-tutorial/.env`
  - Used by the FastAPI application to connect to `fastapi_db`

No Chef data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, environment-variable secret lookups, TLS certificate references, API keys, or tokens were detected.

For Ansible, store the PostgreSQL password in Ansible Vault and construct the database URL from the vaulted value. Do not retain the plaintext password in the playbook repository.

## Checks for the Migration

**Files to verify**:
- `cookbooks/fastapi-tutorial/recipes/default.rb`
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
- `fastapi-tutorial`: TCP `0.0.0.0:8000`
- PostgreSQL: `localhost`

**Unix sockets**:
- PostgreSQL administrative commands may use the platform-default local Unix socket.
- The application connection string explicitly uses `localhost`.

**Templates rendered**:
- `/opt/fastapi-tutorial/.env`: inline `file` resource, rendered once
- `/etc/systemd/system/fastapi-tutorial.service`: inline `file` resource, rendered once
- `.erb` templates: none

## Pre-flight checks

### Package and Python checks

```bash
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev 2>/dev/null || \
rpm -q python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

python3 --version
python3 -m venv --help
git --version
```

### `fastapi-tutorial` application instance

```bash
test -d /opt/fastapi-tutorial
test -f /opt/fastapi-tutorial/requirements.txt
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -x /opt/fastapi-tutorial/venv/bin/uvicorn

git -C /opt/fastapi-tutorial status
git -C /opt/fastapi-tutorial branch --show-current

systemctl daemon-reload
systemctl enable fastapi-tutorial
systemctl start fastapi-tutorial
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial

ss -tlnp | grep ':8000'
curl -I http://127.0.0.1:8000/
curl -sS http://127.0.0.1:8000/
```

Verify that the repository is at `main`, the service is enabled and active, Uvicorn uses `/opt/fastapi-tutorial/venv/bin/uvicorn`, and the listener is bound to `0.0.0.0:8000`.

### `fastapi_db` database instance

```bash
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql

sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
sudo -u postgres psql -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"

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
```

Expected results:
- PostgreSQL is enabled and active.
- The role query returns `fastapi`.
- The database query returns `fastapi_db`.
- The owner query returns `fastapi`.
- The connectivity queries report database `fastapi_db` and user `fastapi`.

Do not expose the password in shell history in production. Use a protected environment or another secure authentication method.

### Environment file

```bash
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env
```

Expected content:

```text
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
```

Expected properties:

```text
root:root 644 /opt/fastapi-tutorial/.env
```

### Systemd unit

```bash
test -f /etc/systemd/system/fastapi-tutorial.service
systemctl cat fastapi-tutorial
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
grep -E '^(Description|After|Type|User|WorkingDirectory|Environment|ExecStart|Restart|WantedBy)=' \
  /etc/systemd/system/fastapi-tutorial.service
```

Verify that the unit contains:

- `After=network.target postgresql.service`
- `User=root`
- `WorkingDirectory=/opt/fastapi-tutorial`
- `Environment="PATH=/opt/fastapi-tutorial/venv/bin"`
- `ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
- `Restart=always`

### Logs and process validation

```bash
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u postgresql --no-pager -n 100
ps aux | grep '[u]vicorn app.main:app'
```

Check for successful Uvicorn startup, valid PostgreSQL authentication, installed Python dependencies, successful import of `app.main:app`, and the absence of a restart loop.