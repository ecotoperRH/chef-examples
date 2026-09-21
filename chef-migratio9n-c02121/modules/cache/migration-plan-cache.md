---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two in-memory caching services on a single host: **Memcached** (a single instance on port 11211) and **Redis** (a single instance on port 6379). Memcached is installed via the `memcached` community cookbook using its `memcached_instance` custom resource. Redis is installed from source (tarball, version 3.2.11 by default) via the `redisio` community cookbook, configured with password authentication (`redis_secure_password_123` hardcoded in the recipe), and managed as a systemd service (`redis@6379`). A post-configuration `ruby_block` hack strips several deprecated replica-related directives from the generated `/etc/redis/6379.conf` to prevent Redis startup errors.

## Service Type and Instances

**Service Type**: Cache (Memcached + Redis)

**Configured Instances**:

- **memcached** (single instance):
  - Location/Path: `/var/log/memcached` (log directory), `/var/run/memcached` (PID directory)
  - Port/Socket: TCP 11211, UDP 11211
  - Key Config: memory=64MB, maxconn=1024, listen=0.0.0.0, max_object_size=1m, ulimit=1024, threads=default

- **redis (port 6379)** (single instance):
  - Location/Path: Config `/etc/redis/6379.conf`, data `/var/lib/redis`, PID `/var/run/redis/6379/`
  - Port/Socket: TCP 6379
  - Key Config: requirepass=`redis_secure_password_123` (hardcoded), backuptype=rdb, loglevel=notice, maxclients=10000, syslogenabled=yes, syslogfacility=local0, databases=16, job_control=systemd (on modern Linux), version=3.2.11 (source build)

## File Structure

**Recipes:**
```
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
```

**Templates:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
```

**Attributes:**
```
cookbooks/cache/attributes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. cache::default** (`cookbooks/cache/recipes/default.rb`):
- Entry point. Sets `node['redisio']['servers']` to a single-element array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Calls `include_recipe 'memcached'` (triggers the full memcached setup)
- Creates directory `/var/log/redis` (owner: redis, group: redis, mode: 0755, recursive: true)
- Calls `include_recipe 'redisio'` (triggers the full Redis install/configure chain)
- Executes `ruby_block 'fix_redis_config'`: reads `/etc/redis/6379.conf` and strips the following lines using regex substitution:
  - Lines matching `^replica-serve-stale-data.*$`
  - Lines matching `^replica-read-only.*$`
  - Lines matching `^repl-ping-replica-period.*$`
  - Lines matching `^client-output-buffer-limit.*$`
  - Lines matching `^replica-priority.*$`
- Calls `include_recipe 'redisio::enable'` (starts and enables the Redis service)
- Resources: include_recipe (3), directory (1), ruby_block (1)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with action `[:start, :enable]`
  - This custom resource internally calls `_package.rb` to install the `memcached` package, create the system user/group, and set up directories
  - memory: 64 (MB)
  - port: 11211
  - udp_port: 11211
  - listen: `0.0.0.0`
  - maxconn: 1024
  - max_object_size: `1m`
  - ulimit: 1024
  - experimental_options: `[]`
  - extra_cli_options: `[]`
  - user: `service_user` (resolved to `memcache` on Debian/Ubuntu, `memcached` on RHEL)
- Resources: memcached_instance (1)

**2a. memcached::_package** (called internally by `memcached_instance` custom resource — `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb`):
- Installs package `memcached` (version: nil = latest)
- Creates system group `service_group` (e.g., `memcache` on Debian)
- Creates system user `service_user` (e.g., `memcache` on Debian), shell `/bin/false`, home `/nonexistent`, locked
- Creates directory `/var/log/memcached` (owner: service_user, group: service_group, mode: 0755)
- Creates directory `/var/run/memcached` (owner: service_user, group: service_group, mode: 0755)
- Resources: package (1), group (1), user (1), directory (2)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (updates APT cache on Debian/Ubuntu)
- Conditional: **unless** `node['redisio']['package_install']` is true (default is `false` on Debian/Ubuntu, so this branch IS taken):
  - Calls `include_recipe 'redisio::_install_prereqs'`
  - Calls `build_essential 'install build deps'` (installs gcc, make, etc.)
- Conditional: **unless** `node['redisio']['bypass_setup']` is true (default is `false`, so this branch IS taken):
  - Calls `include_recipe 'redisio::install'`
  - Calls `include_recipe 'redisio::disable_os_default'`
  - Calls `include_recipe 'redisio::configure'`
- Resources: apt_update (1), include_recipe (4), build_essential (1)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Platform-conditional package installation:
  - On Debian/Ubuntu: installs package **tar**
  - On RHEL/Fedora: installs package **tar**
  - On other platforms: installs nothing
- Resources: package (1) — installs `tar`

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- Conditional: **if** `node['redisio']['package_install']` is true → installs package `redis-server` (Debian) or `redis` (RHEL). **This branch is NOT taken** (package_install=false on Debian/Ubuntu).
- Conditional: **else** (source install — **this branch IS taken**):
  - Calls `include_recipe 'redisio::_install_prereqs'` (installs `tar`)
  - Calls `build_essential 'install build deps'` (installs build tools)
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - version: `3.2.11`
    - download_url: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - safe_install: `true` (skips reinstall if redis-server binary already exists)
    - Downloads tarball to a temp directory
    - Unpacks: `tar zxf redis-3.2.11.tar.gz --strip-components=1`
    - Builds: `make clean && make`
    - Installs: `make install` → binaries land in `/usr/local/bin/` (redis-server, redis-cli, etc.)
- Calls `include_recipe 'redisio::ulimit'`
- Resources: include_recipe (2), build_essential (1), redisio_install (1)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- Conditional: **if** `platform_family?('debian')` (taken on Ubuntu/Debian):
  - Deploys template `/etc/pam.d/su` (from `pam_su_template_cookbook`, default nil = uses built-in)
  - Deploys `cookbook_file '/etc/pam.d/sudo'` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `'sudo'`, mode: 0644)
- Conditional: **if** `ulimit.key?('users')` — `node['ulimit']['users']` defaults to an empty `Mash`, so this loop body is **not executed** unless users are explicitly configured. No `user_ulimit` resources are created in the default configuration.
- Resources: template (1), cookbook_file (1) — on Debian/Ubuntu only

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines OS-default Redis service name:
  - Debian/Ubuntu: `redis-server`
  - RHEL/Fedora: `redis`
- Stops and disables the OS-default Redis service: `service['redis-server']` with action `[:stop, :disable]`
- This prevents the OS-packaged Redis from conflicting with the source-built one
- Resources: service (1)

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Calls `include_recipe 'redisio::default'` (circular guard — already visited, no-op)
- Calls `include_recipe 'redisio::ulimit'` (circular guard — already visited, no-op)
- Sets `redis_instances` to the servers array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - Iterates over 1 server instance: **port 6379**
  - For the **6379** instance, the provider performs:
    - Creates system user `redis` (comment: 'Redis service account', manage_home: true, home: `/var/lib/redis`, shell: `/bin/false` on Debian, system: true)
    - Creates directory `/etc/redis` (owner: root, group: redis, mode: 0775, recursive: true)
    - Creates directory `/var/lib/redis` (owner: redis, group: redis, mode: 0775, recursive: true)
    - Creates directory `/var/run/redis/6379` (owner: redis, group: redis, mode: 0755, recursive: true)
    - Sets up `user_ulimit 'redis'` with filehandle_limit = 10032 (maxclients 10000 + 32)
    - Renders template `/etc/redis/6379.conf` from `redis.conf.erb` (owner: redis, group: redis, mode: 0644):
      - Key variables: port=6379, requirepass=`redis_secure_password_123`, replicaservestaledata=nil (will be stripped by ruby_block hack), backuptype=rdb, loglevel=notice, syslogenabled=yes, syslogfacility=local0, databases=16, maxclients=10000, tcpbacklog=511, timeout=0, keepalive=0, appendfsync=everysec, hz=10, activerehasing=yes, clusterenabled=no
      - **Note**: `not_if { File.exist?('/etc/redis/6379.conf.breadcrumb') }` — config is only written once; subsequent Chef runs skip it if breadcrumb exists
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb` (action: create_if_missing)
    - Conditional on `node['redisio']['job_control']`:
      - **systemd** (default on modern Linux — **this branch IS taken**):
        - Creates file `/etc/tmpfiles.d/redis@6379.conf` with content `d /var/run/redis/6379 0755 redis redis`
        - Renders template `/lib/systemd/system/redis@6379.service` from `redis@.service.erb`:
          - bin_path: `/usr/local/bin`
          - user: `redis`
          - group: `redis`
          - limit_nofile: 10032
          - ExecStart: `/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no`
        - Executes `systemctl daemon-reload` (notified immediately after template render)
      - **initd** (if not systemd): Renders template `/etc/init.d/redis6379` from `redis.init.erb`
      - **upstart** (if upstart): Renders template `/etc/init/redis6379.conf` from `redis.upstart.conf.erb`
      - **rcinit** (FreeBSD): Renders template `/usr/local/etc/rc.d/redis6379` from `redis.rcinit.erb`
- After `redisio_configure`, creates service resource for the **6379** instance:
  - **systemd**: `service['redis@6379']` (provider: Chef::Provider::Service::Systemd)
- Iteration: Runs 1 time for server: **6379**
- Resources: redisio_configure (1), service (1)

**9. cache::default — ruby_block 'fix_redis_config'** (`cookbooks/cache/recipes/default.rb`):
- Reads `/etc/redis/6379.conf` at converge time
- Strips the following directives using `gsub!` (these are Redis 3.x directives that cause warnings/errors on some versions):
  - `replica-serve-stale-data` (entire line)
  - `replica-read-only` (entire line)
  - `repl-ping-replica-period` (entire line)
  - `client-output-buffer-limit` (entire line — **all occurrences**)
  - `replica-priority` (entire line)
- Writes the modified content back to `/etc/redis/6379.conf`
- Resources: ruby_block (1)

**10. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates over 1 server: **6379**
- For the **6379** instance:
  - Resolves the service resource name:
    - systemd: `service['redis@6379']`
    - other: `service['redis6379']`
  - Appends actions `[:start, :enable]` to the existing service resource
- This causes the `redis@6379` systemd service to be started and enabled at boot
- Resources: (modifies existing service resource — no new resources)

## Dependencies

**External cookbook dependencies** (from `metadata.rb`):
- `memcached` ~> 6.0
- `redisio` (no version pin)

**System package dependencies**:
- `memcached` (installed via package manager)
- `tar` (installed for Redis source build)
- Build tools via `build_essential`: `gcc`, `g++`, `make`, `binutils`, `autoconf`, `automake`, `libtool`, `pkg-config` (exact set depends on platform)

**Service dependencies** (systemd services managed):
- `memcached.service` — started and enabled by `memcached_instance` custom resource
- `redis@6379.service` — started and enabled by `redisio::enable`
- `redis-server.service` (Debian) or `redis.service` (RHEL) — **stopped and disabled** by `redisio::disable_os_default`

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe file)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` set to the literal string `'redis_secure_password_123'`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal in the recipe
- **Usage context**: Written into `/etc/redis/6379.conf` as the `requirepass` directive. Any client connecting to Redis on port 6379 must issue `AUTH redis_secure_password_123` before executing commands. Also passed to the init.d script template as the `-a` flag for `redis-cli shutdown`.

> ⚠️ **Security Note for Solutions Architect**: This password is committed in plaintext to the cookbook source. During Ansible migration, this credential **must** be moved to a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, or AAP Credential Store) and injected as an encrypted variable. Do **not** replicate the hardcoded value in Ansible playbooks or group_vars.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration (verify stripped directives are absent)
- `/etc/redis/6379.conf.breadcrumb` — breadcrumb sentinel file
- `/etc/tmpfiles.d/redis@6379.conf` — systemd tmpfiles entry for PID directory
- `/lib/systemd/system/redis@6379.service` — systemd unit file
- `/var/lib/redis/` — Redis data directory
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by cache::default)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached PID/socket directory
- `/etc/pam.d/su` — PAM su template (Debian/Ubuntu only)
- `/etc/pam.d/sudo` — PAM sudo cookbook_file (Debian/Ubuntu only)
- `/usr/local/bin/redis-server` — Redis binary (source install)
- `/usr/local/bin/redis-cli` — Redis CLI binary (source install)

**Service endpoints to check**:
- `11211` (TCP) — Memcached
- `11211` (UDP) — Memcached
- `6379` (TCP) — Redis
- Unix sockets: None configured by default
- Network interfaces: Both services bind to `0.0.0.0` (all interfaces) by default

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` — rendered **once** (guarded by breadcrumb; subsequent runs skip)
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — rendered **once** per Chef run
- `redis.init.erb` → `/etc/init.d/redis6379` — rendered only if `job_control == 'initd'` (not on systemd hosts)
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf` — rendered only if `job_control == 'upstart'`
- `/etc/pam.d/su` template — rendered once on Debian/Ubuntu

## Pre-flight Checks

```bash
###############################################################################
# MEMCACHED CHECKS
###############################################################################

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on port 11211 (TCP and UDP)
ss -tlnp | grep 11211
ss -ulnp | grep 11211
netstat -tulpn | grep 11211

# Verify memcached responds to commands
echo "stats" | nc -q 1 localhost 11211
echo "version" | nc -q 1 localhost 11211
# Expected output: "VERSION <x.y.z>"

# Verify memcached set/get works
echo -e "set testkey 0 60 5\r\nhello\r\n" | nc -q 1 localhost 11211
# Expected: STORED
echo -e "get testkey\r\n" | nc -q 1 localhost 11211
# Expected: VALUE testkey 0 5 / hello / END

# Verify memcached configuration (memory, maxconn, listen)
echo "stats settings" | nc -q 1 localhost 11211 | grep -E 'maxbytes|maxconns|binding_protocol'
# maxbytes should be 67108864 (64MB), maxconns should be 1024

# Verify memcached user and directories
id memcache 2>/dev/null || id memcached 2>/dev/null
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/

# Memcached logs
journalctl -u memcached -n 50 --no-pager
tail -f /var/log/memcached/memcached.log 2>/dev/null || echo "Logging to syslog/journal"

###############################################################################
# REDIS CHECKS
###############################################################################

# Service status
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep

# Verify Redis binary is from source install (not package)
which redis-server
ls -lh /usr/local/bin/redis-server
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 (or higher if safe_install skipped reinstall)

# Verify Redis is listening on port 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i :6379

# Verify Redis responds with authentication
redis-cli -p 6379 ping
# Expected: NOAUTH Authentication required (confirms auth is enforced)

redis-cli -p 6379 -a 'redis_secure_password_123' ping
# Expected: PONG

redis-cli -p 6379 -a 'redis_secure_password_123' info server | grep -E 'redis_version|tcp_port|config_file'
# Expected: redis_version:3.2.11, tcp_port:6379, config_file:/etc/redis/6379.conf

# Verify Redis set/get works
redis-cli -p 6379 -a 'redis_secure_password_123' set migration_test "ok"
# Expected: OK
redis-cli -p 6379 -a 'redis_secure_password_123' get migration_test
# Expected: "ok"
redis-cli -p 6379 -a 'redis_secure_password_123' del migration_test

# Verify config file exists and breadcrumb is present
ls -lh /etc/redis/6379.conf
ls -lh /etc/redis/6379.conf.breadcrumb
cat /etc/redis/6379.conf | grep requirepass
# Expected: requirepass redis_secure_password_123

# Verify the ruby_block hack removed deprecated directives
grep -c 'replica-serve-stale-data' /etc/redis/6379.conf
# Expected: 0 (line was stripped)
grep -c 'replica-read-only' /etc/redis/6379.conf
# Expected: 0 (line was stripped)
grep -c 'repl-ping-replica-period' /etc/redis/6379.conf
# Expected: 0 (line was stripped)
grep -c 'client-output-buffer-limit' /etc/redis/6379.conf
# Expected: 0 (all lines were stripped)
grep -c 'replica-priority' /etc/redis/6379.conf
# Expected: 0 (line was stripped)

# Verify key Redis config values
cat /etc/redis/6379.conf | grep -E '^port|^maxclients|^databases|^loglevel|^syslog-enabled|^syslog-facility'
# Expected: port 6379, maxclients 10000, databases 16, loglevel notice, syslog-enabled yes, syslog-facility local0

# Verify systemd unit file
ls -lh /lib/systemd/system/redis@6379.service
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no

# Verify tmpfiles entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify Redis data and PID directories
ls -lah /var/lib/redis/
ls -lah /var/run/redis/6379/
ls -lah /var/log/redis/

# Verify redis user exists
id redis
# Expected: uid=<N>(redis) gid=<N>(redis) groups=<N>(redis)

# Verify OS-default Redis service is stopped and disabled
systemctl is-active redis-server 2>/dev/null && echo "WARNING: redis-server still active!" || echo "OK: redis-server inactive"
systemctl is-enabled redis-server 2>/dev/null && echo "WARNING: redis-server still enabled!" || echo "OK: redis-server disabled"

# Verify ulimit for redis user
cat /etc/security/limits.d/redis.conf 2>/dev/null || echo "No limits.d file for redis"
# If present, should show nofile limit >= 10032

# Redis logs
journalctl -u redis@6379 -n 50 --no-pager
grep -i error /var/log/redis/*.log 2>/dev/null | tail -20 || echo "Redis logging to syslog"

# PAM files (Debian/Ubuntu only)
ls -lh /etc/pam.d/su /etc/pam.d/sudo
```