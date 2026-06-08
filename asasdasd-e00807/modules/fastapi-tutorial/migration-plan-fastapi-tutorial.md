---
source-path: cookbooks/fastapi-tutorial
---

# Migration Plan: fastapi-tutorial

**TLDR**: This cookbook deploys a FastAPI Python web application with a PostgreSQL database backend. It sets up a single instance of the application running on port 8000, with a dedicated database and systemd service.

## Service Type and Instances

**Service Type**: Application Server (Python FastAPI web application)

**Configured Instances**:

- **fastapi-tutorial**: Python FastAPI web application
  - Location/Path: /opt/fastapi-tutorial
  - Port/Socket: 8000
  - Key Config: 
    - Database: PostgreSQL (fastapi_db)
    - Database User: fastapi
    - Environment Variables: PROJECT_NAME, API_VERSION, DATABASE_URL

## File Structure

```
cookbooks/fastapi-tutorial/recipes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
   - Installs required system packages: python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev
   - Creates application directory: /opt/fastapi-tutorial
   - Clones FastAPI tutorial repository from https://github.com/dibanez/fastapi_tutorial.git (branch: main)
   - Creates Python virtual environment at /opt/fastapi-tutorial/venv
   - Installs Python dependencies from requirements.txt
   - Configures PostgreSQL service (enables and starts)
   - Creates database user 'fastapi' with password 'fastapi_password'
   - Creates database 'fastapi_db' owned by 'fastapi' user
   - Creates environment file (.env) with configuration variables:
     - PROJECT_NAME="FastAPI Tutorial"
     - API_VERSION=1.0.0
     - DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db
   - Creates systemd service file for the application
   - Reloads systemd daemon when service file changes
   - Enables and starts the fastapi-tutorial service
   - Resources: package (1), directory (1), git (1), execute (3), service (2), file (2)

## Dependencies

**External cookbook dependencies**: None specified in metadata.rb
**System package dependencies**: python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev
**Service dependencies**: postgresql.service (required for the FastAPI application to function)

## Credentials

**Detection Summary**: 1 credential detected across 2 files

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Database Password

- **Variable(s)**: 'fastapi_password'
- **Source file(s)**: 
  - cookbooks/fastapi-tutorial/recipes/default.rb (in create_db_user execute resource)
  - cookbooks/fastapi-tutorial/recipes/default.rb (in .env file content)
- **Current storage**: hardcoded
- **Usage context**: PostgreSQL database authentication for the FastAPI application

## Checks for the Migration

**Files to verify**:
- /opt/fastapi-tutorial/ (application directory)
- /opt/fastapi-tutorial/venv/ (Python virtual environment)
- /opt/fastapi-tutorial/.env (environment configuration)
- /etc/systemd/system/fastapi-tutorial.service (systemd service file)
- /opt/allowed_keys/ (organization's approved keys)

**Service endpoints to check**:
- Ports listening: 8000 (FastAPI application)
- Network interfaces: 0.0.0.0 (listens on all interfaces)

**Templates rendered**:
- No templates are used in this cookbook. Configuration is generated directly in file resources.

## Pre-flight checks:
```bash
# Service status
systemctl status fastapi-tutorial
systemctl status postgresql
ps aux | grep uvicorn

# Application health
curl -I http://localhost:8000/
curl -s http://localhost:8000/docs

# Database connectivity
sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname='fastapi_db';"
sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname='fastapi';"
sudo -u postgres psql -d fastapi_db -c "SELECT current_user, current_database();"

# Configuration validation
cat /opt/fastapi-tutorial/.env
cat /etc/systemd/system/fastapi-tutorial.service
ls -la /opt/fastapi-tutorial/venv/
ls -la /opt/allowed_keys/

# Python environment
/opt/fastapi-tutorial/venv/bin/python --version
/opt/fastapi-tutorial/venv/bin/pip list

# Logs
journalctl -u fastapi-tutorial -n 50
journalctl -u postgresql -n 20

# Network listening
netstat -tulpn | grep 8000
ss -tlnp | grep 8000
lsof -i :8000

# Process verification
ps aux | grep uvicorn
pgrep -f "uvicorn app.main:app"

# Resource usage
top -p $(pgrep -f "uvicorn app.main:app") -n 1
cat /proc/$(pgrep -f "uvicorn app.main:app")/status | grep -E 'VmRSS|VmSize'

# Authorized keys verification
ls -la /opt/allowed_keys/
cat /opt/allowed_keys/eloycoto.keys
```