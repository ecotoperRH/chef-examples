---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook provisions a FastAPI Python application on a single host. It installs required system packages, creates a virtual environment, pulls the application source from Git, installs Python dependencies, creates a PostgreSQL user/database, writes an `.env` file, installs a systemd unit for the FastAPI service, and ensures both PostgreSQL and the FastAPI service are enabled and started.

## Service Type and Instances

**Service Type**: Application Server (FastAPI web application) with an accompanying PostgreSQL database.

**Configured Instances**:
- **fastapi-tutorial**: FastAPI application service managed by systemd  
  - Location/Path: `/etc/systemd/system/fastapi-tutorial.service`  
  - Port/Socket: `8000`  
  - Key Config: Runs from virtualenv `/opt/fastapi-tutorial/venv`; reads environment from `/opt/fastapi-tutorial/.env`
- **postgresql**: Local PostgreSQL server  
  - Location/Path: Service `postgresql`  
  - Port/Socket: `5432`  
  - Key Config: Database `fastapi_db` owned by user `fastapi` with password `fastapi_password`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```
**Recipes**
```
cookbooks/fastapi-tutorial/recipes/default.rb
```

**Providers**
```
# (none – all resources are built‑in Chef resources)
```

**Templates**
```
# The `file` resources embed the template content directly; no separate .erb files exist.
```

**Attributes**
```
# No attribute files are used in this cookbook.
```

**Files**
```
# No static files are deployed via `cookbook_file` or `remote_file`.
```

## Module Explanation

The cookbook executes the resources in the exact order shown below.

1. **Package Installation** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - Installs OS packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.

2. **Application Directory** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `directory[/opt/fastapi-tutorial]` – creates the base directory with mode `0755`.

3. **Git Checkout** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `git[/opt/fastapi-tutorial]` – syncs the FastAPI source code into the directory (default branch, remote URL defined in the recipe).

4. **Virtual Environment Creation** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `execute[create_venv]` – runs `python3 -m venv /opt/fastapi-tutorial/venv`.

5. **Python Dependencies Installation** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `execute[install_dependencies]` – runs `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.

6. **PostgreSQL Service Enable/Start** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `service[postgresql]` – enables and starts the PostgreSQL daemon.

7. **Database/User Creation** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `execute[create_db_user]` – runs three `psql` commands (idempotent via `|| true`):  
     1. `CREATE USER fastapi WITH PASSWORD 'fastapi_password';`  
     2. `CREATE DATABASE fastapi_db OWNER fastapi;`  
     3. `GRANT ALL PRIVILEGES ON DATABASE fastapi_db TO fastapi;`

8. **Environment File** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `file[/opt/fastapi-tutorial/.env]` – writes an `.env` file (embedded content) with mode `0644`. Supplies the FastAPI process with DB connection strings and other secrets.

9. **Systemd Unit File** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
   - `file[/etc/systemd/system/fastapi-tutorial.service]` – writes the systemd unit (embedded content) with mode `0644`. The unit starts the FastAPI app via the virtualenv interpreter (typically using `uvicorn`).

10. **Systemd Daemon Reload** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
    - `execute[systemd_reload]` – runs `systemctl daemon-reload` **only** when the unit file changes (action `:nothing` by default, notified by the `file` resource).

11. **FastAPI Service Enable/Start** (`cookbooks/fastapi-tutorial/recipes/default.rb`)  
    - `service[fastapi-tutorial]` – enables and starts the FastAPI systemd service.

No loops or custom resources are used; each resource runs once.

## Dependencies

- **External cookbook dependencies**: None (metadata.rb only declares name/version).  
- **System package dependencies**: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.  
- **Service dependencies**: `postgresql` must be running before the FastAPI service starts (handled by ordering in the recipe).

## Credentials

**Detection Summary**: 2 hard‑coded credentials detected in 1 file.

**Source**:  
- **Provider**: None (credentials are hard‑coded directly in the recipe).  
- **Path**: `cookbooks/fastapi-tutorial/recipes/default.rb`

### PostgreSQL User Password
- **Variable(s)**: `'fastapi_password'` (inline in SQL command)  
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (`execute[create_db_user]`)  
- **Current storage**: Hard‑coded plain text in recipe  
- **Usage context**: Used to create PostgreSQL role `fastapi`; referenced by FastAPI via the `.env` DB connection string.

### Application Environment Secrets
- **Variable(s)**: Typical keys such as `DATABASE_URL`, `SECRET_KEY` (exact keys are embedded in the recipe’s `.env` content)  
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (`file[/opt/fastapi-tutorial/.env]`)  
- **Current storage**: Hard‑coded plain text within the `file` resource  
- **Usage context**: Written to `/opt/fastapi-tutorial/.env`; consumed by the FastAPI process at runtime for database connectivity and application secret handling.

*Recommendation*: Move both the PostgreSQL password and all application secrets out of the recipe into a secure store (e.g., Ansible Vault, HashiCorp Vault, or encrypted data bags) and generate the `.env` file from a template that pulls values from that store.

## Checks for the Migration

- **Files to verify**:  
  - `cookbooks/fastapi-tutorial/recipes/default.rb`  
  - `/opt/fastapi-tutorial/.env`  
  - `/etc/systemd/system/fastapi-tutorial.service`  
  - `/opt/fastapi-tutorial/venv/` (presence of virtualenv)  
  - `/opt/fastapi-tutorial/requirements.txt` (if present)

- **Service endpoints to check**:  
  - FastAPI: `8000` (TCP)  
  - PostgreSQL: `5432` (TCP)

- **Templates rendered**: None (all file resources embed content directly; no external `.erb` templates are used).

## Pre‑flight checks:
```bash
# Verify required OS packages are available
dpkg -l python3 python3-pip python3-venv git postgresql postgresql-contrib libpq-dev

# Ensure no leftover FastAPI processes are running
pgrep -f uvicorn || true

# Verify network ports are free before deployment
ss -tlnp | grep -E ':8000|:5432' || true

# Check that the target git repository is reachable (replace <repo-url> with actual URL)
git ls-remote <repo-url> || { echo "Git repo unreachable"; exit 1; }

# Validate that systemd is the init system
pidof systemd && echo "systemd present" || { echo "systemd not present"; exit 1; }

# Verify PostgreSQL service will start after installation
systemctl is-enabled postgresql || echo "PostgreSQL not enabled"

# Verify FastAPI service unit file will be created
test -f /etc/systemd/system/fastapi-tutorial.service || echo "Systemd unit file missing"
```

**Post‑migration verification (repeat the Checks for the Migration section after applying the Ansible playbook):**
```bash
# Directories
ls -ld /opt/fastapi-tutorial

# Virtual environment
ls -l /opt/fastapi-tutorial/venv/bin/python

# Git checkout
git -C /opt/fastapi-tutorial status

# Python dependencies
source /opt/fastapi-tutorial/venv/bin/activate && pip freeze

# PostgreSQL service
systemctl status postgresql
netstat -tulpn | grep 5432

# Database/user
sudo -u postgres psql -c "\du" | grep fastapi
sudo -u postgres psql -c "\l" | grep fastapi_db

# .env file
cat /opt/fastapi-tutorial/.env

# Systemd unit
cat /etc/systemd/system/fastapi-tutorial.service

# FastAPI service
systemctl status fastapi-tutorial
netstat -tulpn | grep 8000

# Logs
journalctl -u fastapi-tutorial -f
journalctl -u postgresql -f
```