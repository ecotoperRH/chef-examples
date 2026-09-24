---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook provisions a single FastAPI web‑API service. It installs system packages (Python 3, PostgreSQL, Git, etc.), creates a Python virtual environment, pulls the tutorial source from GitHub, sets up a PostgreSQL user/database, writes an `.env` file with DB credentials, installs a systemd unit, and starts the FastAPI service on port 8000.

## Service Type and Instances

**Service Type**: Application Server (FastAPI web API)

**Configured Instances**:
- **fastapi-tutorial**: FastAPI application instance managed by systemd.
  - Location/Path: `/opt/fastapi-tutorial`
  - Virtualenv: `/opt/fastapi-tutorial/venv`
  - Systemd unit: `/etc/systemd/system/fastapi-tutorial.service`
  - Port/Socket: `8000` (exposed by `uvicorn`)

## File Structure

**MANDATORY: Preserve this section from the original plan.**
```
cookbooks/fastapi-tutorial/recipes/default.rb

Providers: (none)

Templates: (none – file resources embed content directly)

Attributes: (none – no attribute files in this cookbook)

Files: (none – no static files deployed via `cookbook_file` or `remote_file`)
```

## Module Explanation

The cookbook executes the resources in the exact order shown below. All steps are defined in `cookbooks/fastapi-tutorial/recipes/default.rb`.

1. **Package Installation** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs system packages `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.

2. **Create Application Directory** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial` owned by `root` with mode `0755`.

3. **Clone FastAPI Tutorial Repository** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Clones `https://github.com/dibanez/fastapi_tutorial.git` into `/opt/fastapi-tutorial`.

4. **Create Python Virtual Environment** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Runs `python3 -m venv /opt/fastapi-tutorial/venv`.

5. **Install Python Dependencies** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Executes `/opt/fastapi-tutorial/venv/bin/pip install -r /opt/fastapi-tutorial/requirements.txt`.

6. **Enable & Start PostgreSQL Service** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Enables and starts the `postgresql` service.

7. **Create PostgreSQL User & Database** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Runs SQL commands to create user `fastapi` with password `fastapi_password`, create database `fastapi_db` owned by `fastapi`, and grant all privileges.

8. **Write `.env` Configuration File** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Creates `/opt/fastapi-tutorial/.env` containing:
     ```
     PROJECT_NAME="FastAPI Tutorial"
     API_VERSION=1.0.0
     DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
     ```

9. **Create Systemd Service Unit** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Writes `/etc/systemd/system/fastapi-tutorial.service` with:
     ```
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

10. **Reload systemd daemon** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Executes `systemctl daemon-reload` (triggered by the file resource).

11. **Enable & Start FastAPI Service** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
    - Enables and starts the `fastapi-tutorial` systemd service.

## Dependencies

- **External cookbook dependencies**: None
- **System package dependencies**: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
- **Service dependencies**: PostgreSQL must be running before the FastAPI service starts (`After=postgresql.service` in the systemd unit)

## Credentials

**Detection Summary**: 1 credential detected across 2 files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

### PostgreSQL User Password
- **Variable(s)**: `'fastapi_password'` (hard‑coded)
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb` (execute `create_db_user` command) and the generated `.env` file
- **Current storage**: Hardcoded in recipe and written in plain‑text `.env` file
- **Usage context**: Used to create PostgreSQL user `fastapi` and embedded in `DATABASE_URL` for the FastAPI application

## Checks for the Migration

**Files to verify**:
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`
- `/opt/fastapi-tutorial/venv/` (virtual environment directory)
- PostgreSQL data directory (default, e.g., `/var/lib/postgresql/12/main`)

**Service endpoints to check**:
- **FastAPI**: TCP `8000` (listening on all interfaces)
- **PostgreSQL**: TCP `5432` (default)

**Templates rendered**:
- None (inline `file` resources). All content is embedded directly in the cookbook.

## Pre‑flight Checks:
```bash
# 1. Verify required system packages are installed
dpkg -l | grep -E 'python3|python3-pip|python3-venv|git|postgresql|libpq-dev'

# 2. Verify PostgreSQL service status
systemctl status postgresql
ps aux | grep postgres

# 3. Verify FastAPI systemd unit exists and is enabled
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial

# 4. Verify the virtual environment was created
[ -d /opt/fastapi-tutorial/venv ] && echo "venv present" || echo "venv missing"

# 5. Verify Python dependencies installed in the virtualenv
/opt/fastapi-tutorial/venv/bin/pip list | grep -E 'fastapi|uvicorn|psycopg2'

# 6. Verify .env file content (redact password if needed)
cat /opt/fastapi-tutorial/.env | grep -E 'PROJECT_NAME|API_VERSION|DATABASE_URL'

# 7. Verify PostgreSQL user and database existence
sudo -u postgres psql -c "\du" | grep fastapi
sudo -u postgres psql -c "\l" | grep fastapi_db

# 8. Test DB connectivity using the connection string from .env
export DATABASE_URL=$(grep DATABASE_URL /opt/fastapi-tutorial/.env | cut -d'=' -f2- | tr -d '"')
psql "$DATABASE_URL" -c "SELECT version();"

# 9. Verify FastAPI is listening on port 8000
ss -tlnp | grep ':8000' || netstat -tulpn | grep ':8000'

# 10. Perform a health‑check request
curl -I http://127.0.0.1:8000/health || echo "Health endpoint not reachable"

# 11. Verify systemd daemon was reloaded after unit creation
systemctl daemon-reload && systemctl restart fastapi-tutorial

# 12. Tail logs for both services (run in background)
journalctl -u postgresql -f &
journalctl -u fastapi-tutorial -f &
```