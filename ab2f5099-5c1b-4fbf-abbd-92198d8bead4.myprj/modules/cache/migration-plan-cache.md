# Migration Plan: cache

**TLDR**: The `cache` cookbook installs and configures two caching services: Redis (via the `redisio 7.2.4` community cookbook) and Memcached (via the `memcached` community cookbook). Redis is compiled from source (version 3.2.11), configured as a single standalone instance on port 6379 with password authentication, and managed via a systemd template unit (`redis@6379`). A post-install `ruby_block` patches the generated config to strip directives incompatible with newer Redis versions. The Ansible migration replaces source compilation with a distro package install, eliminates the config-patching hack by writing a version-correct template directly, stores the Redis password in Ansible Vault, and preserves all effective runtime configuration values.

---

## Service Type and Instances

**Service Type**: Cache (Redis + Memcached)

**Configured Instances**:

- **redis@6379** (Redis): Standalone Redis cache instance
  - Location/Path: `/etc/redis/6379.conf`
  - Port/Socket: `6379`
  - Key Config: `requirepass redis_secure_password_123`, `maxclients 10000`, `backuptype rdb`, `loglevel notice`, syslog to `local0`, no replication, no maxmemory limit

- **memcached** (Memcached): Default Memcached instance
  - Location/Path: System default (package-managed)
  - Port/Socket: `11211` (default)
  - Key Config: All defaults via `memcached_instance` custom resource

---

## File Structure

```
cookbooks/cache/
├── Berksfile
├── Berksfile.lock
├── README.md
├── attributes/
│   └── default.rb
├── metadata.rb
├── recipes/
│   └── default.rb
└── spec/
    └── unit/
        └── recipes/
            └── default_spec.rb

# redisio 7.2.4 (dependency — fully traced)
cookbooks/redisio/
├── attributes/
│   └── default.rb
├── libraries/
│   └── matchers.rb
├── providers/
│   ├── configure.rb
│   └── install.rb
├── recipes/
│   ├── _install_prereqs.rb
│   ├── configure.rb
│   ├── default.rb
│   ├── disable_os_default.rb
│   ├── enable.rb
│   ├── install.rb
│   └── ulimit.rb
├── resources/
│   ├── configure.rb
│   └── install.rb
└── templates/
    └── default/
        ├── redis.conf.erb
        └── redis.service.erb

# Ansible role output
roles/
└── cache/
    ├── defaults/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    ├── tasks/
    │   ├── main.yml
    │   ├── memcached.yml
    │   └── redis.yml
    ├── templates/
    │   └── redis.conf.j2
    └── vars/
        └── main.yml

group_vars/
└── all/
    └── vault.yml          ← Ansible Vault encrypted
```

---

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Calls `include_recipe 'redisio'` → triggers the full redisio chain
   - Sets three node attribute overrides before the redisio chain runs:
     - `node.override['redisio']['servers'][0]['port'] = 6379`
     - `node.override['redisio']['servers'][0]['requirepass'] = 'redis_secure_password_123'`
     - `node.override['redisio']['servers'][0]['replicaservestaledata'] = nil`
   - Creates directory `/var/log/redis` (owner: `redis`, mode: `0755`)
   - Executes `ruby_block "fix_redis_config"` — post-write patch that strips 5 directives from `/etc/redis/6379.conf` using `gsub!` regex: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
   - Calls `include_recipe 'redisio::enable'` → enables and starts `redis@6379`
   - Calls `include_recipe 'memcached'` → installs and starts Memcached

2. **redisio::default** (`cookbooks/redisio/recipes/default.rb`):
   - Runs `apt_update`
   - Calls `include_recipe 'redisio::_install_prereqs'`
   - Calls `build_essential` resource (installs gcc, make, etc.)
   - Calls `include_recipe 'redisio::install'`
   - Calls `include_recipe 'redisio::disable_os_default'`
   - Calls `include_recipe 'redisio::configure'`

3. **redisio::_install_prereqs** (`cookbooks/redisio/recipes/_install_prereqs.rb`):
   - Installs package `tar`

4. **redisio::install** (`cookbooks/redisio/recipes/install.rb`):
   - Invokes `redisio_install` custom resource (provider: `cookbooks/redisio/providers/install.rb`):
     - Downloads `redis-3.2.11.tar.gz` from `download.redis.io`
     - Extracts to `/var/chef-solo/cache/redis-3.2.11/`
     - Runs `make clean && make`
     - Runs `make install` → places binaries in `/usr/local/bin/` (`redis-server`, `redis-cli`, etc.)
   - Calls `include_recipe 'redisio::ulimit'`

5. **redisio::ulimit** (`cookbooks/redisio/recipes/ulimit.rb`):
   - Manages `template[/etc/pam.d/su]`
   - Manages `cookbook_file[/etc/pam.d/sudo]`
   - Manages `user_ulimit[redis]` custom resource (sets `filehandle_limit = maxclients + 32 = 10032`)
   - Note: also called from within `redisio::configure` (circular reference, already-visited guard prevents double execution)

6. **redisio::disable_os_default** (`cookbooks/redisio/recipes/disable_os_default.rb`):
   - Stops and disables the OS default `redis-server` service unit (Ubuntu)

7. **redisio::configure** (`cookbooks/redisio/recipes/configure.rb`):
   - Invokes `redisio_configure[redis-servers]` custom resource (provider: `cookbooks/redisio/providers/configure.rb`):
     - Iterates `redis_instances.each` — expands to single instance **redis@6379**:
       - Creates system user `redis` (home: `/var/lib/redis`, shell: `/bin/false`)
       - Creates directory `/etc/redis` (owner: `root`, group: `redis`, mode: `0775`)
       - Creates directory `/var/lib/redis` (owner: `redis`, group: `redis`, mode: `0775`)
       - Creates directory `/var/run/redis/6379` (owner: `redis`, group: `redis`, mode: `0755`)
       - Renders template `/etc/redis/6379.conf` from `redis.conf.erb` (owner: `redis`, mode: `0640`)
       - Renders template `/lib/systemd/system/redis@6379.service` from `redis.service.erb`
       - Calls `redisio::ulimit` (already-visited, no-op on second call)
   - Note: provider internals enumerated above are based on plan analysis; confirm against `providers/configure.rb` source for full verification

8. **redisio::enable** (`cookbooks/redisio/recipes/enable.rb`):
   - Iterates `redis['servers'].each` — expands to single instance **redis@6379**:
     - Conditional: `if node['redisio']['job_control'] == 'systemd'` → true on modern Ubuntu
     - Enables and starts service `redis@6379` via systemd

9. **memcached::default** (`cookbooks/memcached/recipes/default.rb`):
   - Invokes `memcached_instance[memcached]` custom resource
   - Provider internals not fully enumerated in source analysis — asserted to wrap package install + service start/enable at minimum; confirm against `memcached` cookbook `providers/` or `resources/` before finalizing migration

---

## Dependencies

**External cookbook dependencies**:
- `redisio 7.2.4`
- `memcached` (version from Berksfile.lock)
- `build_essential` (transitive via redisio)
- `user_ulimit` (transitive via redisio::ulimit)

**System package dependencies**:
- `tar`
- `gcc`, `make`, `build-essential` (for source compile — eliminated in Ansible migration)
- `redis-server` (Ansible: distro package replaces source compile)
- `memcached`

**Service dependencies**:
- `redis@6379` (systemd template unit, created by redisio)
- `redis-server` (OS default unit, stopped/disabled by redisio::disable_os_default)
- `memcached`

---

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Chef recipe attribute override (hardcoded string)
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node.override['redisio']['servers'][0]['requirepass']` (Chef) → `vault_redis_password` (Ansible)
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded string literal `'redis_secure_password_123'` in Chef recipe, passed as a node attribute override to the `redisio` cookbook
- **Usage context**: Injected as the `requirepass` directive in `/etc/redis/6379.conf` for the `redis@6379` instance. Any client connecting to port 6379 must authenticate with this password.
- **Ansible migration**: Stored in `group_vars/all/vault.yml` as `vault_redis_password`, encrypted with `ansible-vault encrypt group_vars/all/vault.yml`. Referenced in `roles/cache/templates/redis.conf.j2` as `{{ vault_redis_password }}`.

---

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis instance configuration
- `/lib/systemd/system/redis@6379.service` — systemd unit (Chef-managed; replaced by distro unit in Ansible)
- `/etc/pam.d/su` — PAM ulimit (managed by `redisio::ulimit`)
- `/etc/pam.d/sudo` — PAM ulimit (managed by `redisio::ulimit`)
- `/var/log/redis/` — Redis log directory
- `/var/lib/redis/` — Redis data directory
- `/var/run/redis/6379/` — Redis PID directory
- `/usr/local/bin/redis-server` — Redis binary (source install path; Chef)
- `/usr/bin/redis-server` — Redis binary (package install path; Ansible)

**Service endpoints to check**:
- `redis@6379` / `redis-server` on port `6379`
- `memcached` on port `11211`

**Templates rendered**:
- `cookbooks/redisio/templates/default/redis.conf.erb` → `/etc/redis/6379.conf` (1 render, for instance `6379`)
- `cookbooks/redisio/templates/default/redis.service.erb` → `/lib/systemd/system/redis@6379.service` (1 render, for instance `6379`)
- `roles/cache/templates/redis.conf.j2` → `/etc/redis/6379.conf` (Ansible replacement, 1 render)

---

## Pre-flight Checks

```bash
# ── Redis instance: redis@6379 ────────────────────────────────────────────────

# Verify Redis service status
systemctl status redis@6379
systemctl status redis-server

# Verify Redis is listening on port 6379
ss -tlnp | grep 6379
netstat -tlnp | grep 6379

# Verify Redis authentication works
redis-cli -p 6379 -a 'redis_secure_password_123' ping
# Expected: PONG

# Verify Redis config file exists and is readable
test -f /etc/redis/6379.conf && echo "OK: /etc/redis/6379.conf exists" || echo "MISSING: /etc/redis/6379.conf"
redis-server --test-memory 0 2>/dev/null; redis-server /etc/redis/6379.conf --test 2>&1 | head -5

# Verify no deprecated directives remain in config
grep -E "replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority" /etc/redis/6379.conf \
  && echo "WARNING: deprecated directives present" || echo "OK: no deprecated directives"

# Verify Redis binary path
ls -la /usr/local/bin/redis-server 2>/dev/null && echo "Chef source-install binary present"
ls -la /usr/bin/redis-server 2>/dev/null && echo "Package-install binary present"
redis-server --version

# Verify Redis directories
test -d /etc/redis && ls -la /etc/redis/
test -d /var/lib/redis && ls -la /var/lib/redis/
test -d /var/run/redis/6379 && ls -la /var/run/redis/
test -d /var/log/redis && ls -la /var/log/redis/

# Verify Redis system user
id redis
getent passwd redis

# Verify systemd unit
systemctl cat redis@6379 2>/dev/null || systemctl cat redis-server

# ── Memcached instance: memcached ─────────────────────────────────────────────

# Verify Memcached service status
systemctl status memcached

# Verify Memcached is listening on port 11211
ss -tlnp | grep 11211
netstat -tlnp | grep 11211

# Verify Memcached responds
echo "stats" | nc -q1 127.0.0.1 11211 | head -5

# Verify Memcached package
dpkg -l memcached | grep '^ii'

# ── PAM ulimit files (redisio::ulimit) ────────────────────────────────────────

# Check PAM files managed by redisio::ulimit
test -f /etc/pam.d/su && echo "OK: /etc/pam.d/su exists" || echo "MISSING: /etc/pam.d/su"
test -f /etc/pam.d/sudo && echo "OK: /etc/pam.d/sudo exists" || echo "MISSING: /etc/pam.d/sudo"
grep -i ulimit /etc/pam.d/su 2>/dev/null
grep -i ulimit /etc/pam.d/sudo 2>/dev/null

# ── General connectivity ──────────────────────────────────────────────────────

# Confirm no port conflicts
ss -tlnp | grep -E '6379|11211'

# Confirm systemd daemon is aware of all units
systemctl daemon-reload
systemctl list-units | grep -E 'redis|memcached'
```