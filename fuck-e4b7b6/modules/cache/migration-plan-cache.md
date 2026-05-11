---
source-path: cookbooks/cache
---

# Migration Plan: nginx-multisite-policy

**TLDR**: This Chef Solo repository manages three cookbooks — `nginx-multisite`, `cache`, and `fastapi-tutorial` — on Ubuntu 22.04 LTS. The `nginx-multisite` cookbook configures nginx with three virtual hosts (`test`, `ci`, `status`), each with self-signed SSL, security hardening (fail2ban, ufw, sysctl), and static document roots under `/var/www/<site>`. The `cache` cookbook installs memcached and Redis (via the `redisio` community cookbook) with a password-protected Redis instance. The `fastapi-tutorial` cookbook deploys a Python FastAPI application with PostgreSQL, a systemd unit, and a `.env` file containing secrets. Migration order is: `cache` → `nginx-multisite` → `fastapi-tutorial`. Two secrets require Ansible Vault treatment: the Redis `requirepass` password and the PostgreSQL application password.

---

## Service Type and Instances

**Service Type**: Web Server / Cache / Application Server

**Configured Instances**:

- **test**: nginx virtual host
  - Location/Path: `/var/www/test`
  - Port/Socket: 80 (HTTP), 443 (HTTPS)
  - Key Config: SSL enabled, self-signed cert, static `index.html`

- **ci**: nginx virtual host
  - Location/Path: `/var/www/ci`
  - Port/Socket: 80 (HTTP), 443 (HTTPS)
  - Key Config: SSL enabled, self-signed cert, static `index.html`

- **status**: nginx virtual host
  - Location/Path: `/var/www/status`
  - Port/Socket: 80 (HTTP), 443 (HTTPS)
  - Key Config: SSL enabled, self-signed cert, static `index.html`

- **memcached**: memcached instance (via `memcached_instance` custom resource)
  - Location/Path: N/A (in-memory)
  - Port/Socket: 11211
  - Key Config: 64MB memory, listen `0.0.0.0`, maxconn 1024

- **redis (default instance)**: Redis server managed by `redisio`
  - Location/Path: `/var/log/redis`
  - Port/Socket: 6379
  - Key Config: `requirepass` set (password-protected), version 3.2.11, systemd-managed

- **fastapi**: Python FastAPI application
  - Location/Path: git clone target directory
  - Port/Socket: application port (defined in `.env`)
  - Key Config: Python venv, PostgreSQL backend, systemd unit, `.env` secrets file

---

## File Structure

```
nginx-multisite-policy/
├── Berksfile
├── Policyfile.rb
├── solo.json
├── Vagrantfile
├── cookbooks/
│   ├── nginx-multisite/
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   ├── files/
│   │   │   └── default/
│   │   │       ├── test/
│   │   │       │   └── index.html
│   │   │       ├── ci/
│   │   │       │   └── index.html
│   │   │       └── status/
│   │   │           └── index.html
│   │   ├── recipes/
│   │   │   ├── default.rb
│   │   │   ├── security.rb
│   │   │   ├── nginx.rb
│   │   │   ├── ssl.rb
│   │   │   └── sites.rb
│   │   └── templates/
│   │       └── default/
│   │           ├── nginx.conf.erb
│   │           ├── security.conf.erb
│   │           ├── site.conf.erb
│   │           ├── fail2ban.jail.local.erb
│   │           └── sysctl-security.conf.erb
│   ├── cache/
│   │   └── recipes/
│   │       └── default.rb
│   └── fastapi-tutorial/
│       └── recipes/
│           └── default.rb
└── vendor/cookbooks/
    ├── redisio/
    │   ├── attributes/
    │   │   └── default.rb
    │   └── recipes/
    │       ├── default.rb
    │       ├── configure.rb
    │       ├── install.rb
    │       └── enable.rb
    └── memcached/
        └── attributes/
            └── default.rb
```

---

## Module Explanation

The cookbook performs operations in this order (per `solo.json` run list): `cache::default` → `nginx-multisite::default` → `fastapi-tutorial::default`.

---

### 1. **cache::default** (`cookbooks/cache/recipes/default.rb`)

- Includes `memcached::default` to install and configure memcached
- Configures Redis attributes: sets `requirepass` to the Redis password secret
- Creates directory `/var/log/redis`
- Executes `ruby_block[fix_redis_config]`: patches the Redis configuration file in-place after `redisio` renders it (works around redisio attribute limitations; patches specific config keys — exact keys require inspection of block internals)
- Includes `redisio::install` → installs Redis 3.2.11 via package or tarball, invokes `build_essential` and `redisio_install` LWRP
- Includes `redisio::configure` → invokes `redisio_configure` LWRP, registers per-instance service resources
- Includes `redisio::enable` → enables and starts the Redis service via systemd (conditional systemd branch; enumerates `service` and `link` resources for the default Redis instance)

**Iterations (memcached)**: Single instance — `memcached_instance[memcached]`

**Iterations (redisio)**: Single Redis instance — default instance on port 6379

---

### 2. **nginx-multisite::default** (`cookbooks/nginx-multisite/recipes/default.rb`)

- Calls `nginx-multisite::security`
- Calls `nginx-multisite::nginx`
- Calls `nginx-multisite::ssl`
- Calls `nginx-multisite::sites`

---

### 3. **nginx-multisite::security** (`cookbooks/nginx-multisite/recipes/security.rb`)

- Installs `fail2ban` package
- Installs `ufw` package
- Renders template `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (static; 4 jails configured: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch)
- Renders template `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (static; 15+ kernel hardening parameters)
- Applies sysctl settings
- Configures ufw rules (SSH, HTTP, HTTPS)
- Applies SSH hardening configuration

---

### 4. **nginx-multisite::nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`)

- Installs `nginx` package
- Renders template `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf` (static; no ERB variables)
- Renders template `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf` (static; rate limiting, SSL settings)
- Creates document root directories:
  - `/var/www/test` (overridden by `solo.json` from default `/opt/server/test`)
  - `/var/www/ci` (overridden by `solo.json` from default `/opt/server/ci`)
  - `/var/www/status` (overridden by `solo.json` from default `/opt/server/status`)
- Deploys static files:
  - `cookbooks/nginx-multisite/files/default/test/index.html` → `/var/www/test/index.html`
  - `cookbooks/nginx-multisite/files/default/ci/index.html` → `/var/www/ci/index.html`
  - `cookbooks/nginx-multisite/files/default/status/index.html` → `/var/www/status/index.html`

---

### 5. **nginx-multisite::ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`)

- Ensures `ssl-cert` group exists
- Iterates over sites `[test, ci, status]` and for each:
  - Generates a self-signed OpenSSL certificate and key using `openssl` command
  - **test**: cert → `/etc/ssl/certs/test.crt`, key → `/etc/ssl/private/test.key`
  - **ci**: cert → `/etc/ssl/certs/ci.crt`, key → `/etc/ssl/private/ci.key`
  - **status**: cert → `/etc/ssl/certs/status.crt`, key → `/etc/ssl/private/status.key`

---

### 6. **nginx-multisite::sites** (`cookbooks/nginx-multisite/recipes/sites.rb`)

- Deletes `/etc/nginx/sites-enabled/default`
- Iterates over sites `[test, ci, status]` and for each renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` with per-site variables:
  - **test**: `@server_name=test`, `@document_root=/var/www/test`, `@ssl_enabled=true`, `@cert_file=/etc/ssl/certs/test.crt`, `@key_file=/etc/ssl/private/test.key` → `/etc/nginx/sites-available/test.conf`; symlink → `/etc/nginx/sites-enabled/test.conf`
  - **ci**: `@server_name=ci`, `@document_root=/var/www/ci`, `@ssl_enabled=true`, `@cert_file=/etc/ssl/certs/ci.crt`, `@key_file=/etc/ssl/private/ci.key` → `/etc/nginx/sites-available/ci.conf`; symlink → `/etc/nginx/sites-enabled/ci.conf`
  - **status**: `@server_name=status`, `@document_root=/var/www/status`, `@ssl_enabled=true`, `@cert_file=/etc/ssl/certs/status.crt`, `@key_file=/etc/ssl/private/status.key` → `/etc/nginx/sites-available/status.conf`; symlink → `/etc/nginx/sites-enabled/status.conf`

---

### 7. **fastapi-tutorial::default** (`cookbooks/fastapi-tutorial/recipes/default.rb`)

- Installs Python packages (python3, python3-pip, python3-venv, python3-dev)
- Installs PostgreSQL packages (postgresql, postgresql-contrib, libpq-dev)
- Clones application repository via `git`
- Creates Python virtual environment under application directory
- Runs `pip install -r requirements.txt` inside venv
- Configures PostgreSQL: creates database user and database via raw `psql` commands
- Renders `.env` file into application directory containing `vault_fastapi_db_password` and other runtime config
- Deploys systemd unit file for the FastAPI application
- Executes `systemctl daemon-reload`
- Enables and starts the FastAPI systemd service

---

## Dependencies

**External cookbook dependencies**:
- `redisio` (community) — Redis install/configure/enable LWRPs; version pinned to Redis 3.2.11
- `memcached` (community) — `memcached_instance` custom resource; port 11211, 64MB, listen `0.0.0.0`, maxconn 1024
- `build_essential` (community) — pulled in by `redisio::install`

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `memcached`
- `redis-server` (or tarball install via redisio)
- `python3`, `python3-pip`, `python3-venv`, `python3-dev`
- `postgresql`, `postgresql-contrib`, `libpq-dev`

**Service dependencies**:
- `nginx.service`
- `memcached.service`
- `redis.service` (systemd, managed by redisio::enable)
- `postgresql.service`
- FastAPI application systemd unit

---

## Credentials

**Detection Summary**: 2 credentials detected across 2 files

**Source**:
- **Provider**: Hardcoded attribute / inline assignment (no external secrets provider detected)
- **URL**: N/A
- **Path**: See per-credential entries below

---

### Redis Password

- **Variable(s)**: `vault_redis_password` (Ansible Vault target name); Chef attribute sets `requirepass` on the Redis instance
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Chef node attribute (set inline in recipe, value origin requires inspection of encrypted data bag or environment file)
- **Usage context**: Passed to `redisio` as the `requirepass` Redis configuration directive; also patched by `ruby_block[fix_redis_config]`. Must be stored in Ansible Vault as `vault_redis_password` and injected via Jinja2 Redis template, eliminating the ruby_block hack entirely.

---

### PostgreSQL Application Password

- **Variable(s)**: `vault_fastapi_db_password` (Ansible Vault target name); used in raw `psql` commands and written to `.env` file
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Inline in recipe (hardcoded or node attribute); written in plaintext to `.env` file on disk
- **Usage context**: Used to create the PostgreSQL application user and database, and written into the application `.env` file for runtime use. Must be stored in Ansible Vault as `vault_fastapi_db_password` and rendered via Ansible template task for the `.env` file.

---

## Checks for the Migration

**Files to verify**:
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.conf`
- `/etc/nginx/sites-available/ci.conf`
- `/etc/nginx/sites-available/status.conf`
- `/etc/nginx/sites-enabled/test.conf` (symlink)
- `/etc/nginx/sites-enabled/ci.conf` (symlink)
- `/etc/nginx/sites-enabled/status.conf` (symlink)
- `/var/www/test/index.html`
- `/var/www/ci/index.html`
- `/var/www/status/index.html`
- `/etc/ssl/certs/test.crt`
- `/etc/ssl/certs/ci.crt`
- `/etc/ssl/certs/status.crt`
- `/etc/ssl/private/test.key`
- `/etc/ssl/private/ci.key`
- `/etc/ssl/private/status.key`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/var/log/redis/` (directory)
- `/etc/redis/redis.conf` (or redisio-managed path)
- Application `.env` file
- FastAPI systemd unit file

**Service endpoints to check**:
- nginx HTTP: port 80
- nginx HTTPS: port 443 (sites: test, ci, status)
- memcached: port 11211
- Redis: port 6379
- PostgreSQL: port 5432
- FastAPI application: application port (from `.env`)

**Templates rendered**:
- `nginx.conf.erb` → 1 render (static)
- `security.conf.erb` → 1 render (static)
- `site.conf.erb` → 3 renders (test, ci, status)
- `fail2ban.jail.local.erb` → 1 render (static)
- `sysctl-security.conf.erb` → 1 render (static)
- FastAPI `.env` template → 1 render (contains secrets)
- Redis configuration template → 1 render (contains `requirepass`)

---

## Pre-flight Checks

```bash
# ── System ────────────────────────────────────────────────────────────────────
uname -a
lsb_release -a
systemctl --version

# ── nginx ─────────────────────────────────────────────────────────────────────
systemctl status nginx
nginx -t
nginx -v
ls -la /etc/nginx/sites-enabled/
ls -la /etc/nginx/sites-available/

# nginx virtual host: test
curl -sk https://test/index.html -o /dev/null -w "%{http_code}\n"
test -f /etc/nginx/sites-available/test.conf && echo "test.conf present" || echo "MISSING"
test -L /etc/nginx/sites-enabled/test.conf && echo "test symlink present" || echo "MISSING"
test -f /var/www/test/index.html && echo "test index.html present" || echo "MISSING"
test -f /etc/ssl/certs/test.crt && echo "test cert present" || echo "MISSING"
test -f /etc/ssl/private/test.key && echo "test key present" || echo "MISSING"
openssl x509 -in /etc/ssl/certs/test.crt -noout -subject -dates

# nginx virtual host: ci
curl -sk https://ci/index.html -o /dev/null -w "%{http_code}\n"
test -f /etc/nginx/sites-available/ci.conf && echo "ci.conf present" || echo "MISSING"
test -L /etc/nginx/sites-enabled/ci.conf && echo "ci symlink present" || echo "MISSING"
test -f /var/www/ci/index.html && echo "ci index.html present" || echo "MISSING"
test -f /etc/ssl/certs/ci.crt && echo "ci cert present" || echo "MISSING"
test -f /etc/ssl/private/ci.key && echo "ci key present" || echo "MISSING"
openssl x509 -in /etc/ssl/certs/ci.crt -noout -subject -dates

# nginx virtual host: status
curl -sk https://status/index.html -o /dev/null -w "%{http_code}\n"
test -f /etc/nginx/sites-available/status.conf && echo "status.conf present" || echo "MISSING"
test -L /etc/nginx/sites-enabled/status.conf && echo "status symlink present" || echo "MISSING"
test -f /var/www/status/index.html && echo "status index.html present" || echo "MISSING"
test -f /etc/ssl/certs/status.crt && echo "status cert present" || echo "MISSING"
test -f /etc/ssl/private/status.key && echo "status key present" || echo "MISSING"
openssl x509 -in /etc/ssl/certs/status.crt -noout -subject -dates

# default site removed
test ! -e /etc/nginx/sites-enabled/default && echo "default site removed" || echo "WARNING: default site still present"

# ── Security hardening ────────────────────────────────────────────────────────
systemctl status fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
test -f /etc/fail2ban/jail.local && echo "jail.local present" || echo "MISSING"

ufw status verbose
test -f /etc/sysctl.d/99-security.conf && echo "sysctl config present" || echo "MISSING"
sysctl --system 2>&1 | grep -i error || echo "sysctl OK"

# ── memcached ─────────────────────────────────────────────────────────────────
systemctl status memcached
echo "stats" | nc -q1 127.0.0.1 11211 | head -5
ss -tlnp | grep 11211

# ── Redis ─────────────────────────────────────────────────────────────────────
systemctl status redis
redis-cli -p 6379 ping
# (password required — use vault_redis_password)
redis-cli -p 6379 -a "${REDIS_PASSWORD}" ping
test -d /var/log/redis && echo "/var/log/redis present" || echo "MISSING"
ss -tlnp | grep 6379

# ── PostgreSQL ────────────────────────────────────────────────────────────────
systemctl status postgresql
psql --version
ss -tlnp | grep 5432
# Verify fastapi application database and user exist
sudo -u postgres psql -c "\du" | grep fastapi || echo "WARNING: fastapi db user not found"
sudo -u postgres psql -c "\l" | grep fastapi || echo "WARNING: fastapi database not found"

# ── FastAPI application ───────────────────────────────────────────────────────
systemctl status fastapi
# Verify .env file exists (do NOT cat — contains secrets)
test -f /path/to/app/.env && echo ".env present" || echo "MISSING"
# Verify venv
test -d /path/to/app/venv && echo "venv present" || echo "MISSING"
# Verify systemd unit
systemctl cat fastapi
# Check application is listening
ss -tlnp | grep <app_port>
```