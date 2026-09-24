---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI web application with PostgreSQL database backend. It installs Python 3 with pip and venv, clones the FastAPI tutorial repository from GitHub, creates a Python virtual environment, installs dependencies, configures PostgreSQL with a dedicated database user, creates environment configuration, and manages the application as a systemd service listening on port 8000.

## Service Type and Instances

**Service Type**: Application Server (Python FastAPI)

**Configured Instances**:
- **fastapi-tutorial**: Single FastAPI application instance
  - Location/Path: /opt/fastapi-tutorial
  - Port: 8000
  - Key Config:
    - Virtual environment: /opt/fastapi-tutorial/venv
    - Entry point: app.main:app
    - Database: PostgreSQL (fastapi_db)
    - Database user: fastapi
    - Service: fastapi-tutorial (systemd)

## File Structure

```
cookbooks/fastapi-tutorial/
├── recipes/
│   └── default.rb
└── metadata.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs system packages: python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev
   - Creates application directory: /opt/fastapi-tutorial (mode 0755, owner root, group root)
   - Clones FastAPI tutorial repository from https://github.com/dibanez/fastapi_tutorial.git (branch: main) to /opt/fastapi-tutorial
   - Creates Python virtual environment at /opt/fastapi-tutorial/venv using python3 -m venv
   - Installs Python dependencies from /opt/fastapi-tutorial/requirements.txt into the virtual environment using pip
   - Enables and starts PostgreSQL service
   - Creates PostgreSQL database user 'fastapi' with password 'fastapi_password'
   - Creates PostgreSQL database 'fastapi_db' owned by fastapi user
   - Grants ALL PRIVILEGES on fastapi_db to fastapi user
   - Deploys .env configuration file to /opt/fastapi-tutorial/.env with:
     - PROJECT_NAME="FastAPI Tutorial"
     - API_VERSION=1.0.0
     - DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
   - Deploys systemd service file to /etc/systemd/system/fastapi-tutorial.service with:
     - Type: simple
     - User: root
     - WorkingDirectory: /opt/fastapi-tutorial
     - ExecStart: /opt/fastapi-tutorial/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
     - Restart: always
     - After: network.target, postgresql.service
   - Reloads systemd daemon (triggered by service file creation)
   - Enables and starts fastapi-tutorial service
   - Resources: package (7), directory (1), git (1), execute (4), service (2), file (2)

## Dependencies

**External cookbook dependencies**: None

**System package dependencies**:
- python3
- python3-pip
- python3-venv
- git
- postgresql
- postgresql-contrib
- libpq-dev

**Service dependencies**:
- postgresql (must be running before FastAPI application starts)
- systemd (for service management)

**External repository dependencies**:
- GitHub: https://github.com/dibanez/fastapi_tutorial.git (main branch)

## Credentials

**Detection Summary**: 1 credential detected across 2 files

**Source**:
  - **Provider**: Hardcoded
  - **URL**: Not applicable
  - **Path**: Not applicable

### Database Password

- **Variable(s)**: `fastapi_password` (hardcoded in recipe and .env file)
- **Source file(s)**:
  - cookbooks/fastapi-tutorial/recipes/default.rb (create_db_user execute resource)
  - cookbooks/fastapi-tutorial/recipes/default.rb (.env file content)
- **Current storage**: Hardcoded in recipe and plaintext in .env file
- **Usage context**: PostgreSQL database user authentication for fastapi user connecting to fastapi_db database

**SECURITY WARNING**: The database password 'fastapi_password' is hardcoded in the recipe and stored in plaintext in the .env file. This is a security risk and should be migrated to use Ansible Vault or a secrets management system (HashiCorp Vault, CyberArk, AWS Secrets Manager) in the Ansible equivalent.

## Checks for the Migration

**Files to verify**:
- /opt/fastapi-tutorial/ (application directory)
- /opt/fastapi-tutorial/venv/ (Python virtual environment)
- /opt/fastapi-tutorial/.env (environment configuration)
- /opt/fastapi-tutorial/requirements.txt (Python dependencies list)
- /etc/systemd/system/fastapi-tutorial.service (systemd service file)
- /var/lib/postgresql/ (PostgreSQL data directory)

**Service endpoints to check**:
- Ports listening: 8000 (FastAPI application)
- Unix sockets: /var/run/postgresql/.s.PGSQL.5432 (PostgreSQL)
- Network interfaces: 0.0.0.0 (FastAPI listens on all interfaces)

**Templates rendered**:
- .env file: 1 render to /opt/fastapi-tutorial/.env
- systemd service file: 1 render to /etc/systemd/system/fastapi-tutorial.service

## Pre-flight checks:

```bash
# fastapi-tutorial instance - Service status
systemctl status fastapi-tutorial
ps aux | grep uvicorn

# fastapi-tutorial instance - Application health check
curl -I http://localhost:8000/
curl -s http://localhost:8000/docs
curl -s http://localhost:8000/openapi.json

# fastapi-tutorial instance - Port verification
netstat -tulpn | grep 8000
ss -tlnp | grep 8000
lsof -i :8000

# fastapi-tutorial instance - PostgreSQL service status
systemctl status postgresql
ps aux | grep postgres

# fastapi-tutorial instance - Database connectivity
psql -h localhost -U fastapi -d fastapi_db -c "SELECT version();"
psql -h localhost -U fastapi -d fastapi_db -c "SELECT 1;"

# fastapi-tutorial instance - Database user verification
sudo -u postgres psql -c "SELECT usename FROM pg_user WHERE usename='fastapi';"
sudo -u postgres psql -c "SELECT datname FROM pg_database WHERE datname='fastapi_db';"

# fastapi-tutorial instance - Configuration validation
cat /opt/fastapi-tutorial/.env
cat /etc/systemd/system/fastapi-tutorial.service
grep DATABASE_URL /opt/fastapi-tutorial/.env

# fastapi-tutorial instance - Virtual environment verification
ls -lah /opt/fastapi-tutorial/venv/
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip list | grep -i fastapi

# fastapi-tutorial instance - Application directory verification
ls -lah /opt/fastapi-tutorial/
cat /opt/fastapi-tutorial/requirements.txt
git -C /opt/fastapi-tutorial remote -v

# fastapi-tutorial instance - Logs
journalctl -u fastapi-tutorial -f
journalctl -u fastapi-tutorial --lines 50 --no-pager
tail -f /var/log/syslog | grep fastapi-tutorial

# fastapi-tutorial instance - Network listening
netstat -tulpn | grep -E '8000|5432'
ss -tlnp | grep -E 'uvicorn|postgres'

# fastapi-tutorial instance - Process resource usage
ps aux | grep uvicorn | grep -v grep
top -p $(pgrep -f uvicorn) -n 1

# fastapi-tutorial instance - Application startup verification
systemctl restart fastapi-tutorial
sleep 2
curl -s http://localhost:8000/docs | grep -q "FastAPI" && echo "Application is responding"

# fastapi-tutorial instance - Database connection from application
curl -s http://localhost:8000/api/health 2>/dev/null || echo "Health endpoint not available"

# fastapi-tutorial instance - Systemd service file validation
systemd-analyze verify /etc/systemd/system/fastapi-tutorial.service
```