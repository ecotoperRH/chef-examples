---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the FastAPI application from `https://github.com/dibanez/fastapi_tutorial.git` at revision `main`. It installs Python, PostgreSQL, Git, and PostgreSQL development packages; creates the application directory and Python virtual environment; installs dependencies from `requirements.txt`; creates the PostgreSQL role and database; writes the application `.env` file; creates and manages the `fastapi-tutorial` systemd service; and serves Uvicorn on `0.0.0.0:8000`.

## Service Type and Instances

**Service Type**: Application Server

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application served by Uvicorn
  - Location/Path: `/opt/fastapi-tutorial`
  - Repository: `https://github.com/dibanez/fastapi_tutorial.git`
  - Revision: `main`
  - Python virtual environment: `/opt/fastapi-tutorial/venv`
  - Port/Socket: `0.0.0.0:8000`
  - Application command: `/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Working directory: `/opt/fastapi-tutorial`
  - Runtime user: `root`
  - Restart policy: `always`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Dependency: `postgresql.service`

- **postgresql**: Local PostgreSQL database service
  - Location/Path: Local PostgreSQL installation managed by the `postgresql` service
  - Port/Socket: No explicit TCP port or Unix socket path is configured by this cookbook
  - Database role: `fastapi`
  - Database: `fastapi_db`
  - Host: `localhost`
  - Connection URL: `postgresql://fastapi:fastapi_password@localhost/fastapi_db`
  - Dependency: Required by `fastapi-tutorial`

There are no collection iterations or `.each` loops.

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

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, and `libpq-dev`.
   - Creates `/opt/fastapi-tutorial` recursively with owner `root`, group `root`, and mode `0755`.
   - Synchronizes `https://github.com/dibanez/fastapi_tutorial.git` at revision `main` into `/opt/fastapi-tutorial`.
   - Creates `/opt/fastapi-tutorial/venv` only when the path does not already exist, using:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
     The command runs with `/opt/fastapi-tutorial` as its working directory.
   - Enables and starts the `postgresql` service.
   - Creates the PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates the PostgreSQL database `fastapi_db` owned by `fastapi`.
   - Grants all privileges on `fastapi_db` to `fastapi`.
   - Executes the database commands as the PostgreSQL administrative operating-system user, normally `postgres`.
   - Preserves the original command behavior, including `|| true` on each database command. The commands therefore tolerate existing roles and databases but are not fully idempotent.
   - Creates `/opt/fastapi-tutorial/.env` with owner `root`, group `root`, and mode `0644`, containing:
     ```dotenv
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```
   - Creates `/etc/systemd/system/fastapi-tutorial.service` with owner `root`, group `root`, and mode `0644`, containing:
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
   - Notifies the `systemd_reload` execute resource immediately when the systemd unit changes.
   - Defines `systemd_reload`, which runs `systemctl daemon-reload` only when notified.
   - Enables and starts the `fastapi-tutorial` service after the unit has been deployed and systemd has been reloaded.
   - Uses no custom resources, providers, recipe inclusions, templates, static files, or iterations.

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

The recipe metadata supports Ubuntu `>= 18.04` and CentOS `>= 7.0`; package names may require platform-specific handling during migration.

**Service dependencies**:

- `postgresql`
- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`
- `fastapi-tutorial`
- `network.target`

The application unit declares:

```ini
After=network.target postgresql.service
```

For an idempotent Ansible migration, use `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_privs` for PostgreSQL setup.

## Credentials

**Detection Summary**: 1 database credential detected in `cookbooks/fastapi-tutorial/recipes/default.rb`. The credential is used in both the PostgreSQL role creation command and the generated `.env` file.

**Source**:

- **Provider**: Hardcoded in the Chef recipe
- **URL**: No secret-management URL detected
- **Path**: No Vault path, Chef data bag, Chef Vault item, CyberArk path, or external secret path detected

### PostgreSQL password

- **Variable(s)**: No named Chef attribute variable; literal password is `fastapi_password`
- **Source file(s)**:
  - `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext in the recipe and generated `.env` file
- **Usage context**:
  - PostgreSQL role creation:
    ```sql
    CREATE USER fastapi WITH PASSWORD 'fastapi_password';
    ```
  - Application database URL:
    ```text
    postgresql://fastapi:fastapi_password@localhost/fastapi_db
    ```
  - File containing the connection URL:
    `/opt/fastapi-tutorial/.env`

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, CyberArk data bag, Vault attribute namespace, environment-variable secret lookup, TLS certificate reference, or API token was detected.

For the Ansible migration, store the password in Ansible Vault, pass it to the PostgreSQL modules and `.env` task, and use `no_log: true` on tasks handling the secret. Consider mode `0600` for `.env` if application behavior permits.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/app/main.py`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- PostgreSQL role `fastapi`
- PostgreSQL database `fastapi_db`

**Service endpoints to check**:

- FastAPI: `0.0.0.0:8000`
- PostgreSQL: local PostgreSQL service at `localhost`; no explicit TCP port is configured
- Unix sockets: no explicit socket path is configured

**Templates rendered**: None. The `.env` file and systemd unit are created with inline Chef `file` resources. Render count: `0`.

## Pre-flight checks

Run these checks after applying the Ansible migration.

### `postgresql` instance

```bash
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql
sudo -u postgres psql -tAc "SELECT version();"
```

Expected results:

- The `postgresql` service is enabled.
- The `postgresql` service is active.
- PostgreSQL accepts administrative connections.

Validate the role and database:

```bash
sudo -u postgres psql -tAc "SELECT rolname FROM pg_roles WHERE rolname = 'fastapi';"
sudo -u postgres psql -tAc "SELECT datname, pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
```

Expected output includes:

```text
fastapi
fastapi_db|fastapi
```

Validate application connectivity:

```bash
PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT 1;"

PGPASSWORD='fastapi_password' psql \
  -h localhost \
  -U fastapi \
  -d fastapi_db \
  -c "SELECT current_user, current_database();"
```

Expected values are `fastapi` for `current_user` and `fastapi_db` for `current_database`.

### `fastapi-tutorial` instance

```bash
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl show fastapi-tutorial | grep -E 'ActiveState|UnitFileState|User|WorkingDirectory|ExecStart|Restart'
```

Expected results:

- The service is enabled and active.
- The service runs as `root`.
- The working directory is `/opt/fastapi-tutorial`.
- The process uses `/opt/fastapi-tutorial/venv/bin/uvicorn`.
- The restart policy is `always`.

Validate the virtual environment and dependencies:

```bash
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
test -x /opt/fastapi-tutorial/venv/bin/uvicorn
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version

cd /opt/fastapi-tutorial
/opt/fastapi-tutorial/venv/bin/pip check
```

Expected result from `pip check`:

```text
No broken requirements found.
```

Validate the repository:

```bash
git -C /opt/fastapi-tutorial remote -v
git -C /opt/fastapi-tutorial branch --show-current
test -f /opt/fastapi-tutorial/requirements.txt
test -f /opt/fastapi-tutorial/app/main.py
```

The repository should point to:

```text
https://github.com/dibanez/fastapi_tutorial.git
```

Validate the environment file:

```bash
stat -c '%U:%G %a %n' /opt/fastapi-tutorial/.env
grep -E '^(PROJECT_NAME|API_VERSION|DATABASE_URL)=' /opt/fastapi-tutorial/.env
```

Expected configuration:

```text
PROJECT_NAME="FastAPI Tutorial"
API_VERSION=1.0.0
DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
```

The file should match the Chef ownership and mode of `root:root` and `0644`, or use a stricter mode such as `0600` after the secret migration.

Validate the systemd unit and reload behavior:

```bash
systemctl cat fastapi-tutorial
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
```

Verify that the unit contains:

```text
User=root
WorkingDirectory=/opt/fastapi-tutorial
ExecStart=/opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
```

When the unit changes, the Ansible implementation must notify a handler that runs:

```bash
systemctl daemon-reload
```

Validate the HTTP endpoint and listener:

```bash
curl -I http://127.0.0.1:8000/
curl -sS -o /tmp/fastapi-response.txt -w '%{http_code}\n' http://127.0.0.1:8000/
cat /tmp/fastapi-response.txt

ss -ltnp | grep ':8000'
netstat -ltnp 2>/dev/null | grep ':8000'
lsof -nP -iTCP:8000 -sTCP:LISTEN
```

Expected results:

- A process associated with Uvicorn or `fastapi-tutorial` listens on `0.0.0.0:8000` or an equivalent wildcard IPv4 address.
- The TCP connection succeeds.
- The application returns an HTTP response. A `404` response on `/` still confirms that Uvicorn is serving requests.

Review logs:

```bash
journalctl -u fastapi-tutorial --no-pager -n 100
journalctl -u postgresql --no-pager -n 100
```

Check for Uvicorn startup messages, PostgreSQL connection failures, `app.main:app` import errors, missing Python dependencies, and permission errors under `/opt/fastapi-tutorial`.

After changing the unit file, verify the reload and service state:

```bash
systemctl daemon-reload
systemctl restart fastapi-tutorial
systemctl is-active fastapi-tutorial
```

The service must return to the active state after the reload and restart.