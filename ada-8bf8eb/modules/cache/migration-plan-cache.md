---
source-path: cookbooks/cache
---

# Migration Plan: nginx-multisite-policy

**TLDR**: This Chef policy manages a single node running three logical stacks: an Nginx multi-site web server with SSL and firewall hardening (`nginx-multisite`), a caching layer with Memcached and Redis (`cache`), and a FastAPI Python application backed by PostgreSQL (`fastapi-tutorial`). The run-list executes in order: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`. Migration produces a single Ansible playbook with Jinja2 templates replacing ERB, Chef attributes becoming Ansible vars, and all service management converted to systemd-aware Ansible modules.

---

## Service Type and Instances

**Service Type**: Web Server / Cache / Application Server / Database

**Configured Instances**:

- **test.cluster.local**: Nginx virtual host — test environment site
  - Location/Path: Document root `/opt/server/test`
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled; cert `/etc/ssl/certs/test.cluster.local.crt`; key `/etc/ssl/private/test.cluster.local.key`

- **ci.cluster.local**: Nginx virtual host — CI environment site
  - Location/Path: Document root `/opt/server/ci`
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled; cert `/etc/ssl/certs/ci.cluster.local.crt`; key `/etc/ssl/private/ci.cluster.local.key`

- **status.cluster.local**: Nginx virtual host — status/monitoring site
  - Location/Path: Document root `/opt/server/status`
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled; cert `/etc/ssl/certs/status.cluster.local.crt`; key `/etc/ssl/private/status.cluster.local.key`

- **memcached** (instance name: `memcached`): Memcached caching daemon
  - Location/Path: Systemd unit `/etc/systemd/system/memcached.service`
  - Port/Socket: 11211 (TCP, listen `0.0.0.0`)
  - Key Config: Memory 64 MB; max connections 1024; user `memcache`

- **redis6379** (instance name: `redis6379`): Redis caching daemon managed by `redisio`
  - Location/Path: Config `/etc/redis/6379.conf`; systemd unit `/etc/systemd/system/redis6379.service`
  - Port/Socket: 6379 (TCP)
  - Key Config: requirepass set; log `/var/log/redis/redis-6379.log`; data dir `/var/lib/redis/6379`

- **fastapi-tutorial**: FastAPI Python application
  - Location/Path: App dir `/opt/fastapi-tutorial`; systemd unit `/etc/systemd/system/fastapi-tutorial.service`
  - Port/Socket: 8000 (TCP, `0.0.0.0`)
  - Key Config: Runs as `root` (⚠ security concern); venv at `/opt/fastapi-tutorial/venv`; PostgreSQL backend

- **postgresql**: PostgreSQL database server
  - Location/Path: System default
  - Port/Socket: 5432 (TCP, localhost)
  - Key Config: Database `fastapi_db`; owner user `fastapi`

---

## File Structure

```
nginx-multisite-policy/
├── Policyfile.rb
├── Policyfile.lock.json
├── cookbooks/
│   ├── nginx-multisite/
│   │   ├── metadata.rb
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   ├── recipes/
│   │   │   ├── default.rb
│   │   │   ├── security.rb
│   │   │   ├── nginx.rb
│   │   │   ├── ssl.rb
│   │   │   └── sites.rb
│   │   ├── templates/
│   │   │   └── default/
│   │   │       ├── nginx.conf.erb
│   │   │       ├── site.conf.erb
│   │   │       ├── security.conf.erb
│   │   │       ├── fail2ban.jail.local.erb
│   │   │       └── sysctl-security.conf.erb
│   │   └── files/
│   │       └── default/
│   │           ├── test/
│   │           │   └── index.html
│   │           ├── ci/
│   │           │   └── index.html
│   │           └── status/
│   │               └── index.html
│   ├── cache/
│   │   ├── metadata.rb
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   └── recipes/
│   │       └── default.rb
│   ├── memcached/
│   │   ├── metadata.rb
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   ├── recipes/
│   │   │   └── default.rb
│   │   └── resources/
│   │       └── instance.rb
│   ├── redisio/
│   │   ├── metadata.rb
│   │   ├── attributes/
│   │   │   └── default.rb
│   │   ├── recipes/
│   │   │   ├── default.rb
│   │   │   ├── install.rb
│   │   │   ├── configure.rb
│   │   │   ├── enable.rb
│   │   │   ├── disable_os_default.rb
│   │   │   └── ulimit.rb
│   │   ├── resources/
│   │   │   ├── install.rb
│   │   │   └── configure.rb
│   │   └── templates/
│   │       └── default/
│   │           └── redis.conf.erb
│   └── fastapi-tutorial/
│       ├── metadata.rb
│       ├── attributes/
│       │   └── default.rb
│       └── recipes/
│           └── default.rb
└── ansible-migration/
    ├── site.yml
    └── templates/
        ├── nginx.conf.j2
        ├── site.conf.j2
        ├── security.conf.j2
        ├── fail2ban.jail.local.j2
        ├── sysctl-security.conf.j2
        ├── redis.conf.j2
        ├── redis.service.j2
        └── memcached.service.j2
```

---

## Module Explanation

The cookbook performs operations in this order:

**1. nginx-multisite::default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point; includes four sub-recipes in order: `security`, `nginx`, `ssl`, `sites`

**2. nginx-multisite::security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts `fail2ban` service
- Deploys `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`
- Configures `ufw`: default deny, allow ssh/http/https, enable firewall
- Deploys `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`
- Hardens SSH via `sed` on `/etc/ssh/sshd_config`: disables root login, disables password authentication
- Notifies: `restart fail2ban`, `restart ssh`, `reload sysctl`

**3. nginx-multisite::nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`
- Deploys `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`
- Enables and starts `nginx` service
- Iterates over `nginx_sites` (3 sites) to create document root directories:
  - Creates `/opt/server/test` (owner `www-data`)
  - Creates `/opt/server/ci` (owner `www-data`)
  - Creates `/opt/server/status` (owner `www-data`)
- Iterates over `nginx_sites` (3 sites) to deploy `index.html` from cookbook files:
  - Deploys `cookbooks/nginx-multisite/files/default/test/index.html` → `/opt/server/test/index.html`
  - Deploys `cookbooks/nginx-multisite/files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Deploys `cookbooks/nginx-multisite/files/default/status/index.html` → `/opt/server/status/index.html`
- Notifies: `reload nginx`

**4. nginx-multisite::ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates directory `/etc/ssl/certs` (mode `0755`)
- Creates directory `/etc/ssl/private` (owner `root`, group `ssl-cert`, mode `0710`)
- Iterates over SSL-enabled sites (all 3) to generate self-signed certificates:
  - Generates `/etc/ssl/private/test.cluster.local.key` + `/etc/ssl/certs/test.cluster.local.crt` (guarded: `creates:`)
  - Generates `/etc/ssl/private/ci.cluster.local.key` + `/etc/ssl/certs/ci.cluster.local.crt` (guarded: `creates:`)
  - Generates `/etc/ssl/private/status.cluster.local.key` + `/etc/ssl/certs/status.cluster.local.crt` (guarded: `creates:`)
- Sets private key permissions (mode `0640`, group `ssl-cert`) for each key
- Notifies: `reload nginx`

**5. nginx-multisite::sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterates over `nginx_sites` (3 sites) to deploy vhost configs from `cookbooks/nginx-multisite/templates/default/site.conf.erb`:
  - Deploys → `/etc/nginx/sites-available/test.cluster.local`
  - Deploys → `/etc/nginx/sites-available/ci.cluster.local`
  - Deploys → `/etc/nginx/sites-available/status.cluster.local`
- Iterates over `nginx_sites` (3 sites) to symlink `sites-available` → `sites-enabled`:
  - Symlinks `/etc/nginx/sites-available/test.cluster.local` → `/etc/nginx/sites-enabled/test.cluster.local`
  - Symlinks `/etc/nginx/sites-available/ci.cluster.local` → `/etc/nginx/sites-enabled/ci.cluster.local`
  - Symlinks `/etc/nginx/sites-available/status.cluster.local` → `/etc/nginx/sites-enabled/status.cluster.local`
- Removes `/etc/nginx/sites-enabled/default`
- Notifies: `reload nginx`

**6. cache::default** (`cookbooks/cache/recipes/default.rb`):
- Calls `memcached::default` (via `include_recipe`)
- Calls `redisio::default` (via `include_recipe`)
- Contains `ruby_block "fix_redis_config"` that post-processes the Redis config to strip unsupported directives: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`

**7. memcached::default** (`cookbooks/memcached/recipes/default.rb`):
- Installs package: `memcached`
- Invokes `memcached_instance[memcached]` custom resource (provider: `cookbooks/memcached/resources/instance.rb`)
- Custom resource creates systemd unit at `/etc/systemd/system/memcached.service` with security directives (`PrivateTmp`, `ProtectSystem`, `NoNewPrivileges`, `PrivateDevices`, capability bounding set, restricted address families)
- Enables and starts `memcached` service

**8. redisio::default → redisio::install** (`cookbooks/redisio/recipes/install.rb`):
- Calls `redisio::ulimit` (manages `/etc/pam.d/su`, `/etc/pam.d/sudo` for Redis user ulimits on Debian family)
- When `node['redisio']['package_install']` is `true`: installs `redis-server` package
- When `node['redisio']['package_install']` is `false`: calls `redisio::_install_prereqs`, invokes `build_essential[install build deps]` custom resource, invokes `redisio_install[redis-installation]` custom resource for source compilation
- ⚠ **Migration note**: Ansible playbook implements package install path only; source-build path is not migrated

**9. redisio::disable_os_default** (`cookbooks/redisio/recipes/disable_os_default.rb`):
- Detects platform family (debian vs rhel/fedora)
- Stops and disables the OS default `redis-server` service to prevent port conflicts with the custom `redis6379` instance
- ⚠ **Migration note**: Ansible playbook adds explicit task to stop/disable `redis-server` before enabling `redis6379`

**10. redisio::default → redisio::configure** (`cookbooks/redisio/recipes/configure.rb`):
- Calls `redisio::ulimit` again
- Invokes `redisio_configure[redis-servers]` custom resource (provider: `cookbooks/redisio/resources/configure.rb`)
- Creates `/var/log/redis` directory (owner `redis`)
- Creates `/etc/redis` directory (owner `root`, group `redis`)
- Creates `/var/lib/redis/6379` data directory
- Deploys `cookbooks/redisio/templates/default/redis.conf.erb` → `/etc/redis/6379.conf` (owner `redis`, mode `0640`)
- Strips unsupported directives via `ruby_block "fix_redis_config"` (see `cache::default`)

**11. redisio::default → redisio::enable** (`cookbooks/redisio/recipes/enable.rb`):
- Iterates over `redis['servers']` (1 server: port 6379)
- When `job_control == 'systemd'`: deploys systemd unit → `/etc/systemd/system/redis6379.service`, reloads systemd daemon, enables and starts `redis6379` service
- ⚠ **Migration note**: Ansible playbook assumes `systemd` job control unconditionally; `initd`/`upstart`/`rcinit` paths are not migrated

**12. fastapi-tutorial::default** (`cookbooks/fastapi-tutorial/recipes/default.rb`):
- Installs packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
- Creates directory `/opt/fastapi-tutorial` (mode `0755`)
- Clones `https://github.com/dibanez/fastapi_tutorial.git` → `/opt/fastapi-tutorial` (revision `main`)
- Creates Python venv at `/opt/fastapi-tutorial/venv` (guarded: `creates:`)
- Installs pip dependencies from `/opt/fastapi-tutorial/requirements.txt` into venv
- Enables and starts `postgresql` service
- Creates PostgreSQL user `fastapi` with password (guarded: `'already exists'` check)
- Creates PostgreSQL database `fastapi_db` owned by `fastapi` (guarded: `'already exists'` check)
- Grants all privileges on `fastapi_db` to `fastapi`
- Deploys `.env` file → `/opt/fastapi-tutorial/.env` containing `DATABASE_URL`, `PROJECT_NAME`, `API_VERSION`
- Deploys systemd unit → `/etc/systemd/system/fastapi-tutorial.service` (User=root ⚠, ExecStart uses venv uvicorn, port 8000)
- Enables and starts `fastapi-tutorial` service

---

## Dependencies

**External cookbook dependencies**:
- `memcached` (community cookbook — provides `memcached_instance` custom resource)
- `redisio` (community cookbook — provides `redisio_install`, `redisio_configure` custom resources; manages `redisio::ulimit`, `redisio::disable_os_default`, `redisio::enable`)
- `build_essential` (community cookbook — used by `redisio` source-build path)

**System package dependencies**:
- `fail2ban`, `ufw` (security)
- `nginx` (web server)
- `openssl`, `ca-certificates` (SSL)
- `memcached` (cache)
- `redis-server` (cache — package install path)
- `python3`, `python3-pip`, `python3-venv`, `git` (FastAPI app)
- `postgresql`, `postgresql-contrib`, `libpq-dev` (database)

**Service dependencies**:
- `fail2ban` → depends on `ssh`
- `nginx` → depends on SSL certificates existing
- `redis6379` → depends on `redisio::disable_os_default` having stopped `redis-server`
- `fastapi-tutorial` → depends on `postgresql` running and `fastapi_db` database existing

---

## Credentials

**Detection Summary**: 2 credentials detected across 2 files

**Source**:
- **Provider**: Plaintext Chef cookbook attributes (no vault, no encrypted data bags, no Chef Vault)
- **URL**: N/A
- **Path**: Attribute files within cookbook directories

### Redis Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` / Ansible: `redis_requirepass`
- **Source file(s)**: `cookbooks/cache/attributes/default.rb` (set via `redisio` attribute namespace)
- **Current storage**: Plaintext in cookbook attribute file
- **Usage context**: Written into `/etc/redis/6379.conf` as `requirepass` directive; used by any client connecting to the Redis instance on port 6379
- **⚠ Action required**: Move to `ansible-vault` encrypted variable before production use

### FastAPI PostgreSQL Database Password
- **Variable(s)**: `node['fastapi-tutorial']['db_password']` / Ansible: `fastapi_db_password`
- **Source file(s)**: `cookbooks/fastapi-tutorial/attributes/default.rb`
- **Current storage**: Plaintext in cookbook attribute file
- **Usage context**: Used in `CREATE USER fastapi WITH PASSWORD '...'` psql command; written into `/opt/fastapi-tutorial/.env` as part of `DATABASE_URL=postgresql://fastapi:<password>@localhost/fastapi_db`
- **⚠ Action required**: Move to `ansible-vault` encrypted variable before production use

---

## Checks for the Migration

**Files to verify**:
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/etc/systemd/system/memcached.service`
- `/etc/redis/6379.conf`
- `/etc/systemd/system/redis6379.service`
- `/var/log/redis/redis-6379.log` (created at runtime)
- `/opt/fastapi-tutorial/.env`
- `/etc/systemd/system/fastapi-tutorial.service`

**Service endpoints to check**:
- `nginx` on port 80 (HTTP → HTTPS redirect for all three vhosts)
- `nginx` on port 443 (HTTPS) for `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
- `memcached` on port 11211 (TCP, `0.0.0.0`)
- `redis6379` on port 6379 (TCP)
- `postgresql` on port 5432 (TCP, localhost)
- `fastapi-tutorial` on port 8000 (TCP, `0.0.0.0`)

**Templates rendered**:
- `templates/fail2ban.jail.local.j2` → `/etc/fail2ban/jail.local` (1 render)
- `templates/sysctl-security.conf.j2` → `/etc/sysctl.d/99-security.conf` (1 render)
- `templates/nginx.conf.j2` → `/etc/nginx/nginx.conf` (1 render)
- `templates/security.conf.j2` → `/etc/nginx/conf.d/security.conf` (1 render)
- `templates/site.conf.j2` → `/etc/nginx/sites-available/test.cluster.local` (render 1 of 3)
- `templates/site.conf.j2` → `/etc/nginx/sites-available/ci.cluster.local` (render 2 of 3)
- `templates/site.conf.j2` → `/etc/nginx/sites-available/status.cluster.local` (render 3 of 3)
- `templates/memcached.service.j2` → `/etc/systemd/system/memcached.service` (1 render)
- `templates/redis.conf.j2` → `/etc/redis/6379.conf` (1 render)
- `templates/redis.service.j2` → `/etc/systemd/system/redis6379.service` (1 render)

---

## Pre-flight Checks

```bash
# =============================================================================
# NGINX — service and vhost checks
# =============================================================================

# Verify nginx is running
systemctl status nginx

# Validate nginx configuration syntax
nginx -t

# Check all three vhosts are enabled (symlinks exist)
ls -la /etc/nginx/sites-enabled/test.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local

# Confirm default site is removed
test ! -f /etc/nginx/sites-enabled/default && echo "OK: default site absent" || echo "FAIL: default site still present"

# Check document roots exist and are owned by www-data
stat /opt/server/test
stat /opt/server/ci
stat /opt/server/status

# Check SSL certificates exist for each vhost
test -f /etc/ssl/certs/test.cluster.local.crt && echo "OK: test cert" || echo "MISSING: test cert"
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "OK: ci cert" || echo "MISSING: ci cert"
test -f /etc/ssl/certs/status.cluster.local.crt && echo "OK: status cert" || echo "MISSING: status cert"

# Check SSL private keys exist and have correct permissions
stat /etc/ssl/private/test.cluster.local.key
stat /etc/ssl/private/ci.cluster.local.key
stat /etc/ssl/private/status.cluster.local.key

# Test HTTP → HTTPS redirect for each vhost
curl -I -H "Host: test.cluster.local" http://localhost/ 2>/dev/null | head -5
curl -I -H "Host: ci.cluster.local" http://localhost/ 2>/dev/null | head -5
curl -I -H "Host: status.cluster.local" http://localhost/ 2>/dev/null | head -5

# Test HTTPS response for each vhost (self-signed, skip cert verify)
curl -k -I -H "Host: test.cluster.local" https://localhost/ 2>/dev/null | head -5
curl -k -I -H "Host: ci.cluster.local" https://localhost/ 2>/dev/null | head -5
curl -k -I -H "Host: status.cluster.local" https://localhost/ 2>/dev/null | head -5

# =============================================================================
# SECURITY — fail2ban, ufw, SSH hardening
# =============================================================================

# Verify fail2ban is running
systemctl status fail2ban

# Check jail.local deployed
test -f /etc/fail2ban/jail.local && echo "OK" || echo "MISSING: /etc/fail2ban/jail.local"

# Verify ufw is active
ufw status verbose

# Confirm SSH hardening applied
grep -E '^PermitRootLogin' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication' /etc/ssh/sshd_config

# Verify sysctl security settings loaded
sysctl -p /etc/sysctl.d/99-security.conf

# =============================================================================
# MEMCACHED — instance: memcached (port 11211)
# =============================================================================

# Verify memcached service is running
systemctl status memcached

# Check systemd unit file deployed
test -f /etc/systemd/system/memcached.service && echo "OK" || echo "MISSING: memcached.service"

# Confirm memcached is listening on port 11211
ss -tlnp | grep 11211

# Basic connectivity test
echo "stats" | nc -q1 localhost 11211 | head -5

# =============================================================================
# REDIS — instance: redis6379 (port 6379)
# =============================================================================

# Verify redis6379 service is running
systemctl status redis6379

# Confirm OS default redis-server is stopped and disabled (prevent port conflict)
systemctl is-active redis-server && echo "WARNING: default redis-server still active" || echo "OK: default redis-server inactive"
systemctl is-enabled redis-server && echo "WARNING: default redis-server still enabled" || echo "OK: default redis-server disabled"

# Check config file deployed
test -f /etc/redis/6379.conf && echo "OK" || echo "MISSING: /etc/redis/6379.conf"

# Check systemd unit deployed
test -f /etc/systemd/system/redis6379.service && echo "OK" || echo "MISSING: redis6379.service"

# Confirm redis6379 is listening on port 6379
ss -tlnp | grep 6379

# Test authenticated connection (replace password as appropriate)
redis-cli -p 6379 -a redis_secure_password_123 ping

# Verify unsupported directives were stripped from config
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf \
  && echo "WARNING: unsupported directives still present" || echo "OK: unsupported directives absent"

# =============================================================================
# POSTGRESQL — database: fastapi_db, user: fastapi
# =============================================================================

# Verify postgresql is running
systemctl status postgresql

# Confirm fastapi user exists
sudo -u postgres psql -c "\du fastapi"

# Confirm fastapi_db database exists and is owned by fastapi
sudo -u postgres psql -c "\l fastapi_db"

# Test connection as fastapi user
PGPASSWORD=fastapi_password psql -h localhost -U fastapi -d fastapi_db -c "SELECT 1;" 2>&1

# =============================================================================
# FASTAPI-TUTORIAL — service on port 8000
# =============================================================================

# Verify fastapi-tutorial service is running
systemctl status fastapi-tutorial

# Check app directory and venv exist
test -d /opt/fastapi-tutorial/venv && echo "OK: venv present" || echo "MISSING: venv"

# Check .env file deployed
test -f /opt/fastapi-tutorial/.env && echo "OK" || echo "MISSING: .env"

# Check systemd unit deployed
test -f /etc/systemd/system/fastapi-tutorial.service && echo "OK" || echo "MISSING: fastapi-tutorial.service"

# Confirm FastAPI is listening on port 8000
ss -tlnp | grep 8000

# Test HTTP response from FastAPI
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null

# Check service logs for startup errors
journalctl -u fastapi-tutorial --no-pager -n 50
```

---

## Migration Decisions & Known Gaps

### Explicit Assumptions
1. **Redis job_control**: The Ansible playbook assumes `systemd` job control for Redis unconditionally. The original `redisio::enable` recipe supported `initd`, `upstart`, `systemd`, and `rcinit`. If the target system does not use systemd, the Redis service tasks must be adapted.
2. **Redis install path**: The Ansible playbook implements the **package install path** (`redis-server` package) only. If the Chef policy was running with `node['redisio']['package_install'] = false` (source compilation via `redisio_install` custom resource), the migration is incomplete for that branch — build dependencies, compilation flags, and custom install prefix are not represented.

### Known Gaps Requiring Manual Review
3. **`redisio::ulimit` not migrated**: The original recipe managed `/etc/pam.d/su` and `/etc/pam.d/sudo` for Redis user ulimits on Debian family systems. No equivalent PAM tasks exist in the Ansible playbook. Add `ansible.builtin.lineinfile` tasks targeting `/etc/pam.d/su` if ulimit enforcement is required.
4. **`redisio::disable_os_default` partially migrated**: The playbook must stop and disable the distribution-default `redis-server` service before enabling `redis6379` to prevent port 6379 conflicts. Verify this is handled in the playbook task order.
5. **`memcached_instance` provider not fully analyzed**: The systemd unit parameters in `templates/memcached.service.j2` (capabilities, security directives, ExecStart flags) were derived from the migration plan but the provider source was not available for cross-validation. Verify the rendered unit matches the original Chef-managed unit on the source node.
6. **`redisio_configure`/`redisio_install` providers not fully analyzed**: The Redis configuration template (`templates/redis.conf.j2`) is a minimal representation. Compare against the actual `/etc/redis/6379.conf` on the source node before cutover.

### Security Recommendations
7. **Hardcoded credentials**: `redis_requirepass: "redis_secure_password_123"` and `fastapi_db_password: "fastapi_password"` are plaintext in playbook vars. **Migrate both to `ansible-vault` encrypted variables before production use.**
8. **FastAPI running as root**: The systemd unit sets `User=root`. Change to a dedicated non-privileged service account.
9. **Self-signed SSL certificates**: Replace with Let's Encrypt (`community.crypto.acme_certificate`) or deploy real certificates for production.
10. **`fix_redis_config` hack made explicit**: The original `ruby_block` silently stripped unsupported Redis config directives. The Ansible migration uses individual `lineinfile` tasks with `state: absent`, making the operation auditable and idempotent.
11. **PostgreSQL `|| true` guards replaced**: Original shell `|| true` suppression is