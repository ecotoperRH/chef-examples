---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI Python web application with a PostgreSQL database backend. It sets up a single instance of the application running on port 8000, with features including Python virtual environment, Git repository deployment, and systemd service management.

## Service Type and Instances

**Service Type**: Application Server (Python FastAPI web application)

**Configured Instances**:

- **fastapi-tutorial**: Python FastAPI web application
  - Location/Path: /opt/fastapi-tutorial
  - Port/Socket: 8000
  - Key Config: 
    - Database URL: postgresql://fastapi:fastapi_password@localhost/fastapi_db
    - Project Name: "FastAPI Tutorial"
    - API Version: 1.0.0

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
cookbooks/fastapi-tutorial/metadata.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs Python 3 and required system packages: python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev
   - Creates application directory: /opt/fastapi-tutorial
   - Clones FastAPI tutorial repository from https://github.com/dibanez/fastapi_tutorial.git (branch: main)
   - Creates Python virtual environment at /opt/fastapi-tutorial/venv
   - Installs Python dependencies from requirements.txt
   - Configures PostgreSQL service (enable and start)
   - Creates database user 'fastapi' with password 'fastapi_password'
   - Creates database 'fastapi_db' owned by 'fastapi' user
   - Grants all privileges on database to 'fastapi' user
   - Creates environment configuration file at /opt/fastapi-tutorial/.env with:
     - PROJECT_NAME="FastAPI Tutorial"
     - API_VERSION=1.0.0
     - DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
   - Creates systemd service file at /etc/systemd/system/fastapi-tutorial.service
   - Reloads systemd configuration when service file changes
   - Enables and starts the fastapi-tutorial service
   - Resources: package (1), directory (1), git (1), execute (3), service (2), file (2)

## Dependencies

**External cookbook dependencies**: None specified in metadata.rb
**System package dependencies**: python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev
**Service dependencies**: postgresql.service (required before fastapi-tutorial.service)

## Credentials

**Detection Summary**: 1 credential detected across 2 files

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Database Password

- **Variable(s)**: 'fastapi_password'
- **Source file(s)**: cookbooks/fastapi-tutorial/recipes/default.rb
- **Current storage**: hardcoded
- **Usage context**: PostgreSQL database user password, used for database connection in the FastAPI application

## Checks for the Migration

**Files to verify**:
- /opt/fastapi-tutorial/ (application directory)
- /opt/fastapi-tutorial/venv/ (Python virtual environment)
- /opt/fastapi-tutorial/.env (environment configuration)
- /etc/systemd/system/fastapi-tutorial.service (systemd service file)
- /opt/allowed_keys/ (organization's approved keys)

**Service endpoints to check**:
- Ports listening: 8000
- Network interfaces: 0.0.0.0 (all interfaces)

**Templates rendered**:
- .env file (rendered once)
- fastapi-tutorial.service (rendered once)

## Pre-flight checks:
```bash
# Service status
systemctl status fastapi-tutorial
ps aux | grep uvicorn

# Application health
curl -I http://localhost:8000/
curl -s http://localhost:8000/docs

# Database connectivity
sudo -u postgres psql -c "\l" | grep fastapi_db
sudo -u postgres psql -c "\du" | grep fastapi
psql -U fastapi -h localhost -d fastapi_db -c "SELECT 1;"

# Configuration validation
cat /opt/fastapi-tutorial/.env
cat /etc/systemd/system/fastapi-tutorial.service

# Python environment
ls -la /opt/fastapi-tutorial/venv/bin/
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip list

# Git repository
cd /opt/fastapi-tutorial && git remote -v
cd /opt/fastapi-tutorial && git log -1

# Logs
journalctl -u fastapi-tutorial -n 100
journalctl -u fastapi-tutorial -f

# Network listening
netstat -tulpn | grep 8000
ss -tlnp | grep 8000
lsof -i :8000

# Process verification
ps aux | grep uvicorn
pgrep -f "uvicorn app.main:app"

# Organization's approved keys
ls -la /opt/allowed_keys/
cat /opt/allowed_keys/eloycoto.keys
```