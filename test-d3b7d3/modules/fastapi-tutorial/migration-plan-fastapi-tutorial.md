---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys the `fastapi-tutorial` application to `/opt/fastapi-tutorial`, installs Python, Git, PostgreSQL, and PostgreSQL development dependencies, synchronizes application source from a Git repository, creates a Python virtual environment, installs dependencies from `requirements.txt`, provisions the PostgreSQL role `fastapi` and database `fastapi_db`, writes an application `.env` file, creates a systemd unit, and enables and starts PostgreSQL and the FastAPI service. The application port, bind address, repository details, environment contents, and systemd command must be obtained from the original recipe or deployed source because they are not present in the analyzed execution tree.

## Service Type and Instances

**Service Type**: Application Server

PostgreSQL is managed as the application database dependency.

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application instance
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtual environment: `/opt/fastapi-tutorial/venv`
  - Requirements file: `/opt/fastapi-tutorial/requirements.txt`
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Database: `fastapi_db`
  - Database user: `fastapi`
  - Database password: `fastapi_password`
  - Application port: Not specified; obtain it from the source repository, `.env`, or systemd unit.
  - Bind address: Not specified.
  - Process command: Not visible in the analyzed execution tree; preserve the command from the Chef-generated systemd unit.

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

**Templates:**
```text
```

**Attributes:**
```text
```

**Files:**
```text
```

No custom providers, attribute files, ERB templates, or static cookbook files are shown. Configuration is written using inline Chef `file` resources.

## Module Explanation

The cookbook performs operations in this order. The only analyzed recipe is `cookbooks/fastapi-tutorial/recipes/default.rb`; no `include_recipe` calls or `.each` loops are shown.

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following operating-system packages:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates the application directory `/opt/fastapi-tutorial`.
   - The analyzed execution tree does not confirm directory mode, owner, or group. Verify those values in the original recipe before migration.
   - Synchronizes the Git repository into `/opt/fastapi-tutorial` using `git[/opt/fastapi-tutorial]`.
   - The repository URL, branch, tag, revision, credentials, and update-trigger behavior are not present in the analyzed execution tree and must be obtained from the source.
   - Creates the virtual environment with:
     ```bash
     python3 -m venv /opt/fastapi-tutorial/venv
     ```
   - Installs Python dependencies from `/opt/fastapi-tutorial/requirements.txt` using:
     ```bash
     /opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt
     ```
   - Enables and starts the `postgresql` service.
   - Creates PostgreSQL role `fastapi` with password `fastapi_password`.
   - Creates database `fastapi_db` owned by `fastapi`.
   - Grants `ALL` privileges on `fastapi_db` to `fastapi`.
   - The original Chef command executes these database operations as the `postgres` operating-system user and suppresses errors with `|| true`. The Ansible migration should use idempotent PostgreSQL modules and report genuine failures.
   - Writes `/opt/fastapi-tutorial/.env` using inline content from `file[/opt/fastapi-tutorial/.env]`.
   - The analyzed execution tree does not confirm the `.env` file's mode, owner, group, or exact contents. Retrieve these from the original recipe. If the file contains secrets, store them in Ansible Vault; use mode `0600` only as an intentional security improvement rather than an assumed source behavior.
   - Creates `/etc/systemd/system/fastapi-tutorial.service` using inline content from `file[/etc/systemd/system/fastapi-tutorial.service]`.
   - The analyzed execution tree does not confirm the unit's mode, owner, group, or content. Preserve the source values for `ExecStart`, `WorkingDirectory`, `EnvironmentFile`, `User`, `Group`, `Restart`, `After`, `Requires`, resource limits, bind address, and port.
   - Defines `execute[systemd_reload]` with:
     ```bash
     systemctl daemon-reload
     ```
     and action `nothing`. No notification relationship is shown in the analyzed execution tree.
   - Enables and starts the service named `fastapi-tutorial`.
   - No explicit restart or reload relationship is shown for Git updates, `.env` changes, or unit changes. Handlers may be added during migration only as an intentional behavior change.

## Dependencies

**External cookbook dependencies**: None listed in the analyzed metadata.

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

**Application dependency source**:

- `/opt/fastapi-tutorial/requirements.txt`

## Credentials

**Detection Summary**: 1 explicit hardcoded credential detected in `cookbooks/fastapi-tutorial/recipes/default.rb`. The contents of `/opt/fastapi-tutorial/.env` are unavailable and may contain additional sensitive values.

**Source**:

- **Provider**: Hardcoded in Chef recipe
- **URL**: None detected
- **Path**: `execute[create_db_user]` in `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL password

- **Variable(s)**: No named Chef variable; literal value `fastapi_password`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded inline in the `execute[create_db_user]` command
- **Usage context**: Password for PostgreSQL role `fastapi`, which owns database `fastapi_db`
- **Migration handling**: Store the password in Ansible Vault and reference the vaulted variable from both the PostgreSQL user task and the application environment configuration.

### Application environment contents

- **Variable(s)**: Not available in the analyzed execution tree
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Inline content in `file[/opt/fastapi-tutorial/.env]`
- **Usage context**: Application environment configuration, potentially including database credentials or other secrets
- **Migration handling**: Inspect the original heredoc before migration. Move passwords, tokens, and connection strings into Ansible Vault rather than assuming that `fastapi_password` is the only secret.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk/Conjur calls, AWS Secrets Manager calls, TLS certificate references, or environment-variable secret references are shown.

## Checks for the Migration

**Files to verify**:

- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- `/opt/fastapi-tutorial/venv/bin/python`
- `/opt/fastapi-tutorial/venv/bin/pip`
- PostgreSQL data directory, platform-dependent
- PostgreSQL log location, platform-dependent

**Service endpoints to check**:

- `fastapi-tutorial`: TCP port not specified; obtain it from the installed unit or application configuration.
- `postgresql`: PostgreSQL port is not explicitly configured by this cookbook; verify the target PostgreSQL configuration.
- Unix sockets: Not specified.

**Templates rendered**:

- None. No templates are present; configuration is written through inline `file` resources.

**Inline files written**:

- `/opt/fastapi-tutorial/.env` — rendered once by `file[/opt/fastapi-tutorial/.env]`
- `/etc/systemd/system/fastapi-tutorial.service` — rendered once by `file[/etc/systemd/system/fastapi-tutorial.service]`

## Pre-flight checks

```bash
# Package checks; use the platform-equivalent command on RPM-based systems.
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Fastapi-tutorial instance: application directory and source
test -d /opt/fastapi-tutorial
test -f /opt/fastapi-tutorial/requirements.txt
git -C /opt/fastapi-tutorial status
git -C /opt/fastapi-tutorial rev-parse --is-inside-work-tree

# Fastapi-tutorial instance: virtual environment
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip --version

# PostgreSQL dependency instance
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql
pg_isready

# PostgreSQL role and database
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='fastapi';"
sudo -u postgres psql -tAc "SELECT datname, pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname='fastapi_db';"
sudo -u postgres psql -d fastapi_db -tAc "SELECT current_database();"

# Validate application database credentials without exposing them in shell history.
PGPASSWORD='<retrieve securely from Ansible Vault>' \
psql -h 127.0.0.1 -U fastapi -d fastapi_db -c "SELECT 1;"

# Fastapi-tutorial instance: environment file
test -f /opt/fastapi-tutorial/.env
stat -c '%a %U %G %n' /opt/fastapi-tutorial/.env
grep -E '^(APP_|DATABASE_|DB_|HOST|PORT|ENVIRONMENT)=' /opt/fastapi-tutorial/.env

# Fastapi-tutorial instance: systemd unit
test -f /etc/systemd/system/fastapi-tutorial.service
stat -c '%a %U %G %n' /etc/systemd/system/fastapi-tutorial.service
systemctl daemon-reload
systemctl cat fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl status fastapi-tutorial
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service

# Fastapi-tutorial instance: process and logs
systemctl show fastapi-tutorial --property=ExecStart,WorkingDirectory,EnvironmentFile,User,Group
journalctl -u fastapi-tutorial --no-pager -n 100
ps aux | grep '[f]astapi'

# Identify the configured application endpoint before testing it.
systemctl show fastapi-tutorial --property=ExecStart
grep -E '^(HOST|PORT|APP_PORT|UVICORN_|GUNICORN_)=' /opt/fastapi-tutorial/.env
ss -tlnp

# Test the application only after the actual port and health endpoint are confirmed
# from the systemd unit or application source.
# curl --fail http://<confirmed-bind-address>:<confirmed-port>/<confirmed-health-endpoint>

# Startup validation for the fastapi-tutorial instance
systemctl restart fastapi-tutorial
systemctl is-active fastapi-tutorial
journalctl -u fastapi-tutorial --since "5 minutes ago" --no-pager
```

Confirm that PostgreSQL is enabled and active, role `fastapi` exists, database `fastapi_db` is owned by `fastapi`, the virtual environment and dependency installation are functional, both inline files exist, the systemd unit passes validation, `fastapi-tutorial` is enabled and active, and the application listens on the port defined by the actual systemd unit or application configuration.