---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook installs the required Python, Git, PostgreSQL, and PostgreSQL development packages; creates the `/opt/fastapi-tutorial` application directory; synchronizes the application repository; creates a Python virtual environment; installs dependencies from the application requirements file; starts PostgreSQL; creates the `fastapi` PostgreSQL user and `fastapi_db` database; writes an environment file; creates a systemd unit; reloads systemd when the unit changes; and enables and starts the `fastapi-tutorial` service. The analyzed recipe verifies the application path, service names, database names, and command resources. Repository metadata, file contents, and several systemd and environment-file properties are not present in the validated execution analysis.

## Service Type and Instances

**Service Type**: Application Server with a PostgreSQL database dependency

**Configured Instances**:

- **fastapi-tutorial**: FastAPI application service
  - Location/Path: `/opt/fastapi-tutorial`
  - Service unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Service user: Not verified in the structured analysis
  - Application command: Not verified in the structured analysis
  - Port/Socket: Not verified in the structured analysis
  - Environment file: `/opt/fastapi-tutorial/.env`
  - Service actions: Enable and start
  - Reload dependency: `systemd daemon-reload` is notified by changes to the service unit

- **postgresql**: Local PostgreSQL database service
  - Service name: `postgresql`
  - Database user: `fastapi`
  - Database: `fastapi_db`
  - Password: `fastapi_password`
  - Connection endpoint: Not verified in the structured analysis
  - Service actions: Enable and start

There are no collection attributes or `.each` iterations in the supplied execution tree.

## File Structure

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

The `.env` file and systemd unit are created using inline Chef `file` resources. No cookbook templates or static files are shown as used.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs the following packages:
     - `python3`
     - `python3-pip`
     - `python3-venv`
     - `git`
     - `postgresql`
     - `postgresql-contrib`
     - `libpq-dev`
   - Creates `/opt/fastapi-tutorial` as a directory.
   - Synchronizes a Git repository into `/opt/fastapi-tutorial`.
   - Runs `python3 -m venv /opt/fastapi-tutorial/venv`.
   - Runs `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.
   - Enables and starts the `postgresql` service.
   - Runs the database setup command that creates PostgreSQL user `fastapi`, creates database `fastapi_db`, and grants privileges on `fastapi_db` to `fastapi`.
   - Creates `/opt/fastapi-tutorial/.env`.
   - Creates `/etc/systemd/system/fastapi-tutorial.service`.
   - Defines `execute[systemd_reload]` to run `systemctl daemon-reload` when notified.
   - Enables and starts the `fastapi-tutorial` service.
   - Iterations: None. No `.each` loops or collection iterations are present.

### Execution resources

The recipe contains the following resources in execution order:

1. `package[['python3', 'python3-pip', 'python3-venv', 'git', 'postgresql', 'postgresql-contrib', 'libpq-dev']]`
2. `directory[/opt/fastapi-tutorial]`
3. `git[/opt/fastapi-tutorial]`
4. `execute[create_venv]`
5. `execute[install_dependencies]`
6. `service[postgresql]`
7. `execute[create_db_user]`
8. `file[/opt/fastapi-tutorial/.env]`
9. `file[/etc/systemd/system/fastapi-tutorial.service]`
10. `execute[systemd_reload]`
11. `service[fastapi-tutorial]`

The structured analysis verifies the resource names, resource types, paths, package list, and commands listed above. It does not verify the Git repository URL or revision, the virtual-environment guard, the dependency-install working directory, the `.env` contents or metadata, or the systemd unit contents and metadata.

## Dependencies

**External cookbook dependencies**: None identified.

**System package dependencies**:

- `python3`
- `python3-pip`
- `python3-venv`
- `git`
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`

**Application dependency source**:

```text
/opt/fastapi-tutorial/requirements.txt
```

**Application dependency installation target**:

```text
/opt/fastapi-tutorial/venv
```

**Service dependencies**:

- `postgresql`
- `fastapi-tutorial`

## Credentials

**Detection Summary**: 1 credential reference detected in 1 file.

**Source**:
  - **Provider**: Hardcoded in the Chef recipe
  - **URL**: None detected
  - **Path**: None detected

### PostgreSQL database password

- **Variable/value**: `fastapi_password`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded
- **Usage context**: Used by the database setup command to create PostgreSQL user `fastapi` with password `fastapi_password`.
- **Ansible migration recommendation**: Store the password in Ansible Vault and use the vaulted value in the PostgreSQL user task.

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, CyberArk, Conjur, environment-variable secret lookup, certificate, private key, API token, or external secret-manager integration was identified.

The validated analysis does not show a credential reference in the `.env` file.

## Checks for the Migration

**Files to verify**:

- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `/opt/fastapi-tutorial`
- `/opt/fastapi-tutorial/requirements.txt`
- `/opt/fastapi-tutorial/venv`
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Database objects to check**:

- PostgreSQL user `fastapi`
- PostgreSQL database `fastapi_db`
- Ownership and privileges for `fastapi_db`

**Service endpoints to check**:

- PostgreSQL endpoint: Not specified in the validated structured analysis
- FastAPI endpoint: Port and socket are not specified in the validated structured analysis

**Unix sockets**:

- No explicit Unix socket path is specified in the validated structured analysis.

**Templates rendered**:

- None. No cookbook templates are present or rendered.

## Pre-flight checks

### Recipe and file checks

```bash
test -f cookbooks/fastapi-tutorial/recipes/default.rb
test -d /opt/fastapi-tutorial
test -f /opt/fastapi-tutorial/requirements.txt
test -d /opt/fastapi-tutorial/venv
test -f /opt/fastapi-tutorial/.env
test -f /etc/systemd/system/fastapi-tutorial.service
```

### Package checks

```bash
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev
```

### PostgreSQL instance: `postgresql`

```bash
systemctl status postgresql
systemctl is-enabled postgresql
systemctl is-active postgresql
```

Verify the PostgreSQL user:

```bash
sudo -u postgres psql -tAc "SELECT usename FROM pg_catalog.pg_user WHERE usename = 'fastapi';"
```

Verify the database:

```bash
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname = 'fastapi_db';"
```

Verify the database owner:

```bash
sudo -u postgres psql -tAc "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'fastapi_db';"
```

### PostgreSQL database instance: `fastapi_db`

```bash
sudo -u postgres psql -d fastapi_db -tAc "SELECT current_database();"
sudo -u postgres psql -d fastapi_db -tAc "\dp"
```

Confirm that user `fastapi` exists and has the expected database privileges.

### FastAPI application instance: `fastapi-tutorial`

```bash
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial
systemctl is-active fastapi-tutorial
systemctl cat fastapi-tutorial
```

Validate the systemd unit syntax:

```bash
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
```

Check the application directory and virtual environment:

```bash
test -d /opt/fastapi-tutorial
test -x /opt/fastapi-tutorial/venv/bin/python
test -x /opt/fastapi-tutorial/venv/bin/pip
/opt/fastapi-tutorial/venv/bin/pip list
```

### Environment file instance: `/opt/fastapi-tutorial/.env`

```bash
test -f /opt/fastapi-tutorial/.env
stat /opt/fastapi-tutorial/.env
sed -n '1,120p' /opt/fastapi-tutorial/.env
```

The validated structured analysis does not provide the expected environment-file contents, owner, group, or mode. Verify those values against the source cookbook before migration.

### Systemd reload validation

```bash
systemctl daemon-reload
systemctl status fastapi-tutorial
```

Confirm that changes to `/etc/systemd/system/fastapi-tutorial.service` trigger the equivalent systemd reload handler.

### Application endpoint validation

The validated structured analysis does not specify an application port, socket, bind address, or executable command. Confirm the service unit contents before running endpoint-specific checks.

After the endpoint is confirmed, check the configured listener with:

```bash
ss -tlnp
```

Then test the verified application URL:

```bash
curl -i http://127.0.0.1:<verified-port>/
```

### Service logs

```bash
journalctl -u postgresql --no-pager -n 100
journalctl -u fastapi-tutorial --no-pager -n 100
```
