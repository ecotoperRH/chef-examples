---
source-path: cookbooks/cache
---

# Migration Plan: nginx-multisite, cache, fastapi-tutorial

**TLDR**: This migration covers three Chef Solo cookbooks — `nginx-multisite` (Nginx with three SSL virtual hosts and security hardening via UFW, Fail2Ban, SSH hardening, and sysctl tuning), `cache` (Memcached and Redis with a post-processing ruby_block hack to strip deprecated config directives), and `fastapi-tutorial` (Python FastAPI application with PostgreSQL and a systemd service unit). Two hardcoded credentials must be moved to Ansible Vault. The custom `lineinfile` LWRP must be dropped in favour of `ansible.builtin.lineinfile`. A document root inconsistency between `attributes/default.rb` (`/opt/server/`) and `solo.json` (`/var/www/`) is resolved in favour of `/var/www/`. The FastAPI process currently runs as root and must be migrated to a dedicated `fastapi` system user. Cross-platform gating on `ansible_os_family` is required due to divergence between the `apt-get`-based provisioning script and the `generic/fedora42` Vagrantfile target.

---

## Service Type and Instances

**Service Type**: Multi-service stack (Web Server / Cache / Application Server / Database)

**Configured Instances**:

- **nginx-multisite**: Nginx reverse proxy and static file server with SSL termination
  - Location/Path: `cookbooks/nginx-multisite/`
  - Port/Socket: 80 (HTTP), 443 (HTTPS)
  - Key Config: 3 SSL virtual hosts, UFW firewall, Fail2Ban, SSH hardening, sysctl tuning

- **memcached**: In-memory object cache (delegated to `memcached` community cookbook)
  - Location/Path: `cookbooks/cache/`
  - Port/Socket: 11211
  - Key Config: Managed via community cookbook attributes

- **redis**: In-memory data structure store (delegated to `redisio` community cookbook)
  - Location/Path: `cookbooks/cache/`
  - Port/Socket: 6379
  - Key Config: Hardcoded password `redis_secure_password_123`; deprecated directives stripped via `ruby_block` post-processing hack

- **fastapi-app**: Python FastAPI application served via systemd
  - Location/Path: `cookbooks/fastapi-tutorial/`
  - Port/Socket: Application port (defined in systemd unit)
  - Key Config: Git clone, Python venv, PostgreSQL backend, systemd unit; currently runs as root — must migrate to dedicated `fastapi` system user

- **postgresql**: Relational database backend for FastAPI
  - Location/Path: `cookbooks/fastapi-tutorial/recipes/default.rb`
  - Port/Socket: 5432
  - Key Config: Hardcoded password `fastapi_password` for database user

---

## File Structure

```
.
├── Vagrantfile
├── solo.json
├── cookbooks/
│   ├── nginx-multisite/
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   ├── files/
│   │   │   └── default/
│   │   │       ├── index.html          # static HTML for site 1
│   │   │       ├── site2.html          # static HTML for site 2
│   │   │       └── site3.html          # static HTML for site 3
│   │   ├── providers/
│   │   │   └── lineinfile.rb           # custom LWRP — drop in Ansible migration
│   │   ├── recipes/
│   │   │   ├── default.rb
│   │   │   ├── nginx.rb
│   │   │   ├── security.rb
│   │   │   ├── ssl.rb
│   │   │   └── sites.rb
│   │   ├── resources/
│   │   │   └── lineinfile.rb           # custom LWRP resource definition
│   │   └── templates/
│   │       └── default/
│   │           ├── nginx.conf.erb
│   │           ├── security_headers.conf.erb
│   │           ├── ssl_params.conf.erb
│   │           ├── vhost.conf.erb
│   │           └── fail2ban_jail.conf.erb
│   ├── cache/
│   │   └── recipes/
│   │       └── default.rb
│   └── fastapi-tutorial/
│       └── recipes/
│           └── default.rb
```

---

## Module Explanation

The cookbook performs operations in this order:

### Cookbook 1: nginx-multisite

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Orchestration entry point; includes all other recipes in order
- Calls: `nginx-multisite::nginx`, `nginx-multisite::security`, `nginx-multisite::ssl`, `nginx-multisite::sites`

**2. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs the `nginx` system package
- Deploys `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`
- Deploys `cookbooks/nginx-multisite/templates/default/security_headers.conf.erb` to `/etc/nginx/conf.d/security_headers.conf`
- Enables and starts the `nginx` service

**3. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs `ufw`, `fail2ban`, and openssh-server packages
- Applies sysctl hardening parameters via `sysctl` resources
- Deploys `cookbooks/nginx-multisite/templates/default/fail2ban_jail.conf.erb` to `/etc/fail2ban/jail.local`
- Hardens SSH configuration via the custom `lineinfile` LWRP (to be replaced with `ansible.builtin.lineinfile`)
- Enables UFW with rules for ports 22, 80, and 443
- Enables and starts `fail2ban` service

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Creates SSL certificate and key directories under `/etc/nginx/ssl/`
- Deploys `cookbooks/nginx-multisite/templates/default/ssl_params.conf.erb` to `/etc/nginx/conf.d/ssl_params.conf`
- Manages SSL certificates and keys for each of the three virtual hosts:
  - **site1**: certificate and key deployed to `/etc/nginx/ssl/site1/`
  - **site2**: certificate and key deployed to `/etc/nginx/ssl/site2/`
  - **site3**: certificate and key deployed to `/etc/nginx/ssl/site3/`

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterates over the three configured virtual hosts (`.each` loop expanded):
  - **site1**: renders `cookbooks/nginx-multisite/templates/default/vhost.conf.erb` → `/etc/nginx/sites-available/site1.conf`; creates symlink `/etc/nginx/sites-enabled/site1.conf`; deploys static `index.html` to document root `/var/www/site1/`
  - **site2**: renders `cookbooks/nginx-multisite/templates/default/vhost.conf.erb` → `/etc/nginx/sites-available/site2.conf`; creates symlink `/etc/nginx/sites-enabled/site2.conf`; deploys static `site2.html` to document root `/var/www/site2/`
  - **site3**: renders `cookbooks/nginx-multisite/templates/default/vhost.conf.erb` → `/etc/nginx/sites-available/site3.conf`; creates symlink `/etc/nginx/sites-enabled/site3.conf`; deploys static `site3.html` to document root `/var/www/site3/`
- Note: `sites-available`/`sites-enabled` symlink pattern is Debian convention; must adapt to `conf.d` drop-in on RHEL/Fedora, gated on `ansible_os_family`
- Document root resolved to `/var/www/` (overridden in `solo.json`; `attributes/default.rb` default of `/opt/server/` is superseded)
- Notifies `nginx` service to reload

---

### Cookbook 2: cache

**1. default** (`cookbooks/cache/recipes/default.rb`):
- Includes `memcached::default` from the `memcached` community cookbook — installs and configures Memcached on port 11211
- Includes `redisio::default` and `redisio::enable` from the `redisio` community cookbook — installs and configures Redis on port 6379 with password `redis_secure_password_123`
- Executes a `ruby_block` resource that post-processes the Redis configuration file to strip deprecated directives (e.g., `no-appendfsync-on-rewrite`, `auto-aof-rewrite-percentage`, `auto-aof-rewrite-min-size` or similar) that `redisio` writes but the installed Redis version rejects
- Migration note: Replace the `ruby_block` hack with a managed Jinja2 template for `redis.conf` or use `ansible.builtin.lineinfile` with `state: absent` for each deprecated directive

---

### Cookbook 3: fastapi-tutorial

**1. default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
- Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
- Clones the FastAPI application repository via `git` resource to a local directory (e.g., `/opt/fastapi-tutorial/`)
- Creates a Python virtual environment under the application directory
- Installs Python dependencies from `requirements.txt` into the venv via `pip`
- Creates PostgreSQL database user with password `fastapi_password` (hardcoded — must move to Ansible Vault)
- Creates PostgreSQL database and grants privileges to the application user
- Deploys a systemd unit file for the FastAPI application service
- Enables and starts the FastAPI systemd service
- Migration note: Application currently runs as root; Ansible migration must create a dedicated `fastapi` system user and run the service under that account

---

## Dependencies

**External cookbook dependencies**:
- `memcached` (community cookbook) — used by `cache::default`
- `redisio` (community cookbook) — used by `cache::default`

**System package dependencies**:
- `nginx`
- `ufw`
- `fail2ban`
- `openssh-server`
- `python3`, `python3-pip`, `python3-venv`
- `git`
- `postgresql`, `postgresql-contrib`, `libpq-dev`

**Service dependencies**:
- `nginx` — depends on SSL certificates and virtual host configs being in place
- `fail2ban` — depends on `nginx` log paths existing
- `redis-server` — depends on `redisio` community cookbook
- `memcached` — depends on `memcached` community cookbook
- `postgresql` — must be running before FastAPI application starts
- FastAPI systemd service — depends on `postgresql` and Python venv being ready

---

## Credentials

**Detection Summary**: 2 credentials detected across 2 files

**Source**:
- **Provider**: Hardcoded plaintext in Chef recipe and attributes files
- **URL**: N/A
- **Path**: See individual entries below

### Redis Authentication Password
- **Variable(s)**: `redis_secure_password_123`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (passed as attribute to `redisio` community cookbook)
- **Current storage**: Hardcoded plaintext string literal in recipe
- **Usage context**: Redis `requirepass` directive; used for all client authentication against the Redis instance on port 6379

### PostgreSQL Application User Password
- **Variable(s)**: `fastapi_password`
- **Source file(s)**: `cookbooks/fastapi-tutorial/recipes/default.rb`
- **Current storage**: Hardcoded plaintext string literal in recipe
- **Usage context**: Password for the PostgreSQL application user created for the FastAPI service; used in database connection string at application runtime

---

## Checks for the Migration

**Files to verify**:
- `cookbooks/nginx-multisite/recipes/default.rb`
- `cookbooks/nginx-multisite/recipes/nginx.rb`
- `cookbooks/nginx-multisite/recipes/security.rb`
- `cookbooks/nginx-multisite/recipes/ssl.rb`
- `cookbooks/nginx-multisite/recipes/sites.rb`
- `cookbooks/nginx-multisite/attributes/default.rb`
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb`
- `cookbooks/nginx-multisite/templates/default/security_headers.conf.erb`
- `cookbooks/nginx-multisite/templates/default/ssl_params.conf.erb`
- `cookbooks/nginx-multisite/templates/default/vhost.conf.erb`
- `cookbooks/nginx-multisite/templates/default/fail2ban_jail.conf.erb`
- `cookbooks/nginx-multisite/resources/lineinfile.rb`
- `cookbooks/nginx-multisite/providers/lineinfile.rb`
- `cookbooks/nginx-multisite/files/default/index.html`
- `cookbooks/nginx-multisite/files/default/site2.html`
- `cookbooks/nginx-multisite/files/default/site3.html`
- `cookbooks/cache/recipes/default.rb`
- `cookbooks/fastapi-tutorial/recipes/default.rb`
- `solo.json`
- `Vagrantfile`

**Service endpoints to check**:
- Nginx HTTP: port 80
- Nginx HTTPS: port 443
- Memcached: port 11211
- Redis: port 6379
- PostgreSQL: port 5432
- FastAPI application: application port (confirm from systemd unit)

**Templates rendered**:
- `nginx.conf.erb` — rendered 1 time → `/etc/nginx/nginx.conf`
- `security_headers.conf.erb` — rendered 1 time → `/etc/nginx/conf.d/security_headers.conf`
- `ssl_params.conf.erb` — rendered 1 time → `/etc/nginx/conf.d/ssl_params.conf`
- `vhost.conf.erb` — rendered 3 times → `/etc/nginx/sites-available/site1.conf`, `/etc/nginx/sites-available/site2.conf`, `/etc/nginx/sites-available/site3.conf`
- `fail2ban_jail.conf.erb` — rendered 1 time → `/etc/fail2ban/jail.local`

---

## Pre-flight Checks

```bash
# ── Nginx ──────────────────────────────────────────────────────────────────
# Verify nginx is installed and configuration is valid
nginx -v
nginx -t

# Verify nginx service status
systemctl status nginx

# Verify virtual host configs exist
ls -la /etc/nginx/sites-available/site1.conf
ls -la /etc/nginx/sites-available/site2.conf
ls -la /etc/nginx/sites-available/site3.conf

# Verify symlinks are active
ls -la /etc/nginx/sites-enabled/site1.conf
ls -la /etc/nginx/sites-enabled/site2.conf
ls -la /etc/nginx/sites-enabled/site3.conf

# Verify document roots exist and contain static files
ls -la /var/www/site1/
ls -la /var/www/site2/
ls -la /var/www/site3/

# Verify SSL certificate directories
ls -la /etc/nginx/ssl/site1/
ls -la /etc/nginx/ssl/site2/
ls -la /etc/nginx/ssl/site3/

# Verify SSL params and security headers configs
ls -la /etc/nginx/conf.d/ssl_params.conf
ls -la /etc/nginx/conf.d/security_headers.conf

# Test HTTP and HTTPS reachability for each site
curl -I http://localhost
curl -Ik https://localhost

# ── Security Hardening ─────────────────────────────────────────────────────
# Verify UFW status and rules
ufw status verbose

# Verify fail2ban service and jail status
systemctl status fail2ban
fail2ban-client status
fail2ban-client status nginx-http-auth

# Verify fail2ban jail config deployed
ls -la /etc/fail2ban/jail.local

# Verify sysctl hardening applied
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.conf.all.rp_filter
sysctl kernel.randomize_va_space

# ── Memcached ──────────────────────────────────────────────────────────────
# Verify memcached service status
systemctl status memcached

# Verify memcached is listening on port 11211
ss -tlnp | grep 11211

# Basic connectivity check
echo "stats" | nc -q1 127.0.0.1 11211

# ── Redis ──────────────────────────────────────────────────────────────────
# Verify redis service status
systemctl status redis-server

# Verify redis is listening on port 6379
ss -tlnp | grep 6379

# Verify authentication is required (should return NOAUTH error without password)
redis-cli ping

# Verify authentication works with password
redis-cli -a redis_secure_password_123 ping

# Verify no deprecated directives remain in redis.conf
grep -E "no-appendfsync-on-rewrite|auto-aof-rewrite-percentage|auto-aof-rewrite-min-size" /etc/redis/redis.conf && echo "DEPRECATED DIRECTIVES FOUND — migration incomplete" || echo "OK: no deprecated directives"

# ── PostgreSQL ─────────────────────────────────────────────────────────────
# Verify postgresql service status
systemctl status postgresql

# Verify postgresql is listening on port 5432
ss -tlnp | grep 5432

# Verify fastapi database user exists
sudo -u postgres psql -c "\du" | grep fastapi

# Verify fastapi database exists
sudo -u postgres psql -c "\l" | grep fastapi

# Verify fastapi user can authenticate
PGPASSWORD=fastapi_password psql -U fastapi -h 127.0.0.1 -c "\conninfo"

# ── FastAPI Application ────────────────────────────────────────────────────
# Verify fastapi system user exists (post-migration requirement)
id fastapi

# Verify systemd unit is deployed and enabled
systemctl status fastapi-tutorial
systemctl is-enabled fastapi-tutorial

# Verify Python venv exists
ls -la /opt/fastapi-tutorial/

# Verify application is reachable
curl -I http://localhost:8000

# ── Cross-platform / OS family check ──────────────────────────────────────
# Confirm OS family for Ansible gating validation
cat /etc/os-release | grep -E "^ID|^ID_LIKE"
```