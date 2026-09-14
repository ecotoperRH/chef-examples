---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two caching services on a single host: **Memcached** (in-memory object cache, port 11211) and **Redis** (persistent key-value store, port 6379 with password authentication). Memcached is deployed via the `memcached_instance` custom resource with default settings (64 MB RAM, 1024 max connections). Redis is installed from source (version 3.2.11 by default, or via OS package on FreeBSD), configured with a hardcoded password (`redis_secure_password_123`), and managed via a systemd/init.d service. A post-configuration `ruby_block` hack strips several incompatible directives from the generated Redis config file (`/etc/redis/6379.conf`) to work around version compatibility issues.

## Service Type and Instances

**Service Type**: Cache (Dual: Memcached + Redis)

**Configured Instances**:

- **memcached** (single instance, name: `memcached`):
  - Location/Path: `/var/log/memcached` (log), `/var/run/memcached` (PID)
  - Port/Socket: TCP 11211 (also UDP 11211), bound to `0.0.0.0`
  - Key Config: memory=64 MB, maxconn=1024, max_object_size=1m, ulimit=1024, threads=default, no authentication
  - Service user: `memcached` (system user, shell `/bin/false`)

- **redis** (single instance, server name: `6379`):
  - Location/Path: Config `/etc/redis/6379.conf`, data `/var/lib/redis`, PID `/var/run/redis/6379/`, log via syslog (facility `local0`)
  - Port/Socket: TCP 6379, bound to all interfaces (no `bind` directive set)
  - Key Config: requirepass=`redis_secure_password_123` (hardcoded), backuptype=rdb, maxclients=10000, loglevel=notice, syslog-enabled=yes, databases=16, no replication configured
  - Service user: `redis` (system user)
  - Post-config hack: strips `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` lines from `/etc/redis/6379.conf` after generation

## File Structure

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. cache::default** (`cookbooks/cache/recipes/default.rb`):
- Sets `node['redisio']['servers']` to a single-element array: port `6379`, requirepass `redis_secure_password_123`, replicaservestaledata `nil`
- Calls `include_recipe 'memcached'` (triggers memcached setup)
- Creates directory `/var/log/redis` (owner: redis, group: redis, mode: 0755, recursive: true)
- Calls `include_recipe 'redisio'` (triggers Redis install + configure)
- Executes `ruby_block['fix_redis_config']`: reads `/etc/redis/6379.conf` and strips 5 directive patterns: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
- Calls `include_recipe 'redisio::enable'` (starts and enables the Redis service)
- Resources: directory (1), ruby_block (1), include_recipe (3)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with action `[:start, :enable]`
  - Internally calls `_package.rb` which:
    - Installs package `memcached` (version: nil = latest)
    - Creates system group `memcached`
    - Creates system user `memcached` (shell: `/bin/false`, home: `/nonexistent`, locked)
    - Creates directory `/var/log/memcached` (owner: memcached, group: memcached, mode: 0755)
    - Creates directory `/var/run/memcached` (owner: memcached, group: memcached, mode: 0755)
  - Configures instance with: memory=64 MB, port=11211, udp_port=11211, listen=0.0.0.0, maxconn=1024, max_object_size=1m, ulimit=1024
  - Starts and enables the memcached service
- Resources: memcached_instance (1) → internally: package (1), group (1), user (1), directory (2), service (1)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (updates APT cache on Debian/Ubuntu)
- **Conditional** — unless `node['redisio']['package_install']` is true (default: false on Debian/Ubuntu, true on FreeBSD):
  - Calls `redisio::_install_prereqs` (installs `tar` package on Debian/RHEL)
  - Uses custom resource `build_essential['install build deps']` (installs gcc, make, etc.)
- **Conditional** — unless `node['redisio']['bypass_setup']` is true (default: false):
  - Calls `redisio::install`
  - Calls `redisio::disable_os_default`
  - Calls `redisio::configure`
- Resources: apt_update (1), build_essential (1), include_recipe (3)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Installs prerequisite packages based on platform family:
  - On Debian/Ubuntu: installs **tar**
  - On RHEL/Fedora: installs **tar**
  - On other platforms: installs nothing
- Iteration: Runs 1 time for package: **tar**
- Resources: package (1)

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- **Conditional** — if `node['redisio']['package_install']` is true:
  - Installs OS package `redis-server` (Debian) or `redis` (RHEL) at version specified (nil = latest)
- **Conditional** — else (default path on Debian/Ubuntu — source install):
  - Calls `redisio::_install_prereqs` again (idempotent)
  - Uses custom resource `build_essential['install build deps']`
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - Downloads tarball from `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - Extracts, runs `make clean && make`, then `make install` to `/usr/local/bin`
    - Skips if Redis binary already exists and `safe_install=true` (default)
    - Installs binaries to `/usr/local/bin` (redis-server, redis-cli, etc.)
- Calls `redisio::ulimit`
- Resources: package (conditional, 1) OR build_essential (1) + redisio_install (1), include_recipe (1)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- **Conditional** — if platform is Debian family:
  - Deploys template `/etc/pam.d/su` (from `pam_su_template_cookbook`, default: nil = uses built-in)
  - Deploys `cookbook_file[/etc/pam.d/sudo]` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `sudo`, mode: 0644)
- **Conditional** — if `node['ulimit']['users']` key exists (default: empty Mash — no users configured):
  - Iteration over `ulimit['users']` hash: **no users configured by default**, so this loop does not execute
- Resources: template (1, conditional), cookbook_file (1, conditional), user_ulimit (0 by default)

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines OS default Redis service name:
  - Debian/Ubuntu: `redis-server`
  - RHEL/Fedora: `redis`
- Stops and disables the OS-default Redis service (action: `[:stop, :disable]`) to prevent conflicts with the redisio-managed instance
- Resources: service (1)

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - Iteration: Runs **1 time** for server: **6379**
    - Creates system user `redis` (home: `/var/lib/redis`, shell: `/bin/false` on Debian)
    - Creates directory `/etc/redis` (owner: root, group: redis, mode: 0775)
    - Creates directory `/var/lib/redis` (owner: redis, group: redis, mode: 0775)
    - Creates directory `/var/run/redis/6379` (owner: redis, group: redis, mode: 0755)
    - Sets ulimit for user `redis`: filehandle_limit = maxclients(10000) + 32 = **10032**
    - Renders template `redis.conf.erb` → `/etc/redis/6379.conf` (owner: redis, group: redis, mode: 0644)
      - Key variables: port=6379, requirepass=redis_secure_password_123, backuptype=rdb, maxclients=10000, loglevel=notice, syslogenabled=yes, syslogfacility=local0, databases=16, save=[900 1, 300 10, 60 10000], appendfsync=everysec, replicaservestaledata=yes (then stripped by ruby_block hack), replicareadonly=yes (then stripped), replpingreplicaperiod=10 (then stripped), replicapriority=100 (then stripped), clientoutputbufferlimit=[normal 0 0 0, replica 256mb 64mb 60, pubsub 32mb 8mb 60] (then stripped)
      - Protected by breadcrumb file: will NOT overwrite if `/etc/redis/6379.conf.breadcrumb` exists
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb` (create_if_missing)
    - **Conditional on init system** (systemd on modern Ubuntu/CentOS):
      - If **systemd** (default on Ubuntu 18.04+, CentOS 7+):
        - Creates `/etc/tmpfiles.d/redis@6379.conf` (content: `d /var/run/redis/6379 0755 redis redis`)
        - Renders template `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`
          - Variables: bin_path=/usr/local/bin, user=redis, group=redis, limit_nofile=10032
        - Executes `systemctl daemon-reload` (notified immediately after template)
      - If **initd** (older systems):
        - Renders template `redis.init.erb` → `/etc/init.d/redis6379` (mode: 0755)
      - If **upstart**:
        - Renders template `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`
      - If **rcinit** (FreeBSD):
        - Renders template `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`
- Creates service resource `service[redis@6379]` (systemd) or `service[redis6379]` (initd/upstart/rcinit)
- Resources: redisio_configure (1) → internally: user (1), directory (3), user_ulimit (1), template (1 config + 1 service unit), file (2 breadcrumb + tmpfiles), execute (1)

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iteration: Runs **1 time** for server: **6379**
  - Looks up the previously-created service resource by name:
    - systemd: `service[redis@6379]`
    - other: `service[redis6379]`
  - Appends actions `[:start, :enable]` to the service resource
- Resources: service action modification (1)

## Dependencies

**External cookbook dependencies** (from `metadata.rb`):
- `memcached ~> 6.0`
- `redisio` (no version pin)

**System package dependencies**:
- `memcached` (OS package, latest)
- `tar` (build prerequisite for Redis source install)
- Build tools via `build_essential`: `gcc`, `g++`, `make`, `binutils`, `autoconf`, `automake`, `libtool`, `m4` (Debian: `build-essential`; RHEL: `gcc`, `gcc-c++`, `make`, etc.)
- Redis 3.2.11 compiled from source tarball (downloaded from `http://download.redis.io/releases/redis-3.2.11.tar.gz`) — binaries installed to `/usr/local/bin`

**Service dependencies** (systemd services managed):
- `memcached.service` — started and enabled
- `redis@6379.service` (systemd) or `redis6379` (initd) — started and enabled
- `redis-server` (Debian) or `redis` (RHEL) OS default service — stopped and disabled

## Credentials

**Detection Summary**: 1 credential detected across 2 files (defined in recipe, consumed in template)

**Source**:
- **Provider**: Hardcoded (plaintext in recipe file)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` → rendered as `requirepass` directive in `/etc/redis/6379.conf`
- **Source file(s)**:
  - `cookbooks/cache/recipes/default.rb` — hardcoded value `redis_secure_password_123` set in the servers array
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb` — rendered as `requirepass <%= @requirepass %>` in the config file
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb` — also supports loading from a Chef data bag via `data_bag_item(current['data_bag_name'], current['data_bag_item'])` if `data_bag_name`, `data_bag_item`, and `data_bag_key` attributes are set (not used here)
- **Current storage**: Hardcoded plaintext string in recipe
- **Usage context**: Redis `requirepass` directive — all clients connecting to Redis on port 6379 must authenticate with this password using `AUTH redis_secure_password_123` before issuing commands. Also used as `masterauth` if replication is configured.

> ⚠️ **Security Note for Solutions Architect**: This password MUST be migrated to a secrets manager (HashiCorp Vault, CyberArk, or AAP Credential Store) before deploying the Ansible equivalent. The hardcoded value `redis_secure_password_123` in the Chef recipe is a security risk. In Ansible, use `ansible-vault` encrypted variables or an external secrets lookup plugin.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis main configuration file
- `/etc/redis/6379.conf.breadcrumb` — breadcrumb sentinel file (prevents config overwrite)
- `/lib/systemd/system/redis@6379.service` — systemd unit file (on systemd systems)
- `/etc/init.d/redis6379` — init.d script (on non-systemd systems)
- `/etc/tmpfiles.d/redis@6379.conf` — tmpfiles.d entry for PID directory (systemd only)
- `/var/lib/redis/` — Redis data directory (RDB dump files)
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by cache cookbook)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached PID/socket directory
- `/etc/pam.d/su` — PAM su file (modified on Debian for ulimit)
- `/etc/pam.d/sudo` — PAM sudo file (deployed on Debian for ulimit)

**Service endpoints to check**:
- Redis: TCP 6379 (all interfaces, `0.0.0.0:6379`)
- Memcached: TCP 11211 (all interfaces, `0.0.0.0:11211`)
- Memcached: UDP 11211 (all interfaces)
- Unix sockets: None configured (both services use TCP only)

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` — rendered **1 time** (for the single server instance `6379`); then post-processed by `ruby_block['fix_redis_config']` to strip 5 directive lines
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — rendered **1 time** (systemd systems only)
- `redis.init.erb` → `/etc/init.d/redis6379` — rendered **1 time** (initd systems only, mutually exclusive with systemd)
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf` — rendered **1 time** (upstart systems only, mutually exclusive)
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379` — rendered **1 time** (FreeBSD only, mutually exclusive)
- `/etc/pam.d/su` — rendered **1 time** (Debian family only, from ulimit recipe)

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED SERVICE CHECKS
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on TCP 11211
netstat -tulpn | grep 11211
ss -tlnp | grep 11211
lsof -i TCP:11211

# Verify memcached is listening on UDP 11211
ss -ulnp | grep 11211

# Memcached connectivity test (should return version string)
echo "version" | nc -q1 localhost 11211
# Expected output: VERSION x.x.x

# Memcached stats check
echo "stats" | nc -q1 localhost 11211 | grep -E 'uptime|curr_connections|limit_maxbytes|max_connections'
# Expected: limit_maxbytes should be 67108864 (64 MB)
# Expected: max_connections should be 1024

# Verify memcached configuration
cat /etc/memcached.conf 2>/dev/null || cat /etc/sysconfig/memcached 2>/dev/null

# Verify memcached user and directories
id memcached
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/

# Memcached log check
journalctl -u memcached -n 50 --no-pager
tail -f /var/log/memcached/memcached.log 2>/dev/null || journalctl -u memcached -f

# ============================================================
# REDIS SERVICE CHECKS
# ============================================================

# Service status (systemd)
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep

# Verify Redis binary location and version
ls -lh /usr/local/bin/redis-server
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 (or higher if package install)

# Verify Redis is listening on TCP 6379
netstat -tulpn | grep 6379
ss -tlnp | grep 6379
lsof -i TCP:6379

# Redis connectivity test WITH authentication (password required)
redis-cli -p 6379 -a 'redis_secure_password_123' PING
# Expected output: PONG

# Redis INFO check (authenticated)
redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep -E 'redis_version|tcp_port|config_file|uptime_in_seconds'
# Expected: tcp_port:6379, config_file:/etc/redis/6379.conf

# Verify authentication is enforced (should FAIL without password)
redis-cli -p 6379 PING
# Expected output: NOAUTH Authentication required

# Redis connectivity and basic operations
redis-cli -p 6379 -a 'redis_secure_password_123' SET migration_test "ok"
redis-cli -p 6379 -a 'redis_secure_password_123' GET migration_test
# Expected output: "ok"
redis-cli -p 6379 -a 'redis_secure_password_123' DEL migration_test

# Redis memory and client stats
redis-cli -p 6379 -a 'redis_secure_password_123' INFO memory | grep -E 'used_memory_human|maxmemory_human'
redis-cli -p 6379 -a 'redis_secure_password_123' INFO clients | grep -E 'connected_clients|maxclients'
# Expected: maxclients should be 10000

# ============================================================
# REDIS CONFIGURATION FILE CHECKS
# ============================================================

# Verify config file exists
ls -lah /etc/redis/6379.conf
ls -lah /etc/redis/6379.conf.breadcrumb

# Verify requirepass is set
grep '^requirepass' /etc/redis/6379.conf
# Expected: requirepass redis_secure_password_123

# Verify the ruby_block hack removed these directives (should return NO output)
grep '^replica-serve-stale-data' /etc/redis/6379.conf
# Expected: (empty - line was stripped)
grep '^replica-read-only' /etc/redis/6379.conf
# Expected: (empty - line was stripped)
grep '^repl-ping-replica-period' /etc/redis/6379.conf
# Expected: (empty - line was stripped)
grep '^client-output-buffer-limit' /etc/redis/6379.conf
# Expected: (empty - line was stripped)
grep '^replica-priority' /etc/redis/6379.conf
# Expected: (empty - line was stripped)

# Verify key config values
grep '^port' /etc/redis/6379.conf
# Expected: port 6379
grep '^maxclients' /etc/redis/6379.conf
# Expected: maxclients 10000
grep '^syslog-enabled' /etc/redis/6379.conf
# Expected: syslog-enabled yes
grep '^databases' /etc/redis/6379.conf
# Expected: databases 16

# ============================================================
# REDIS SYSTEMD UNIT FILE CHECKS
# ============================================================

# Verify systemd unit file exists and is correct
ls -lah /lib/systemd/system/redis@6379.service
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no
# Expected: User=redis, Group=redis, LimitNOFILE=10032

# Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify service is enabled
systemctl is-enabled redis@6379
# Expected: enabled

# ============================================================
# REDIS DIRECTORIES AND PERMISSIONS
# ============================================================

# Verify all Redis directories
ls -lah /var/lib/redis/
# Expected: owned by redis:redis, mode 0775
ls -lah /var/run/redis/6379/
# Expected: owned by redis:redis, mode 0755
ls -lah /var/log/redis/
# Expected: owned by redis:redis, mode 0755
ls -lah /etc/redis/
# Expected: owned by root:redis, mode 0775

# Verify redis user exists
id redis
getent passwd redis
# Expected: redis system user with home /var/lib/redis

# ============================================================
# OS DEFAULT REDIS SERVICE DISABLED CHECK
# ============================================================

# Verify the OS default Redis service is stopped and disabled (Debian/Ubuntu)
systemctl is-active redis-server 2>/dev/null
# Expected: inactive (or "Unit redis-server.service could not be found")
systemctl is-enabled redis-server 2>/dev/null
# Expected: disabled (or masked)

# Verify the OS default Redis service is stopped and disabled (RHEL/CentOS)
systemctl is-active redis 2>/dev/null
# Expected: inactive
systemctl is-enabled redis 2>/dev/null
# Expected: disabled

# ============================================================
# ULIMIT CHECKS (Debian/Ubuntu)
# ============================================================

# Verify PAM files were deployed
ls -lah /etc/pam.d/su
ls -lah /etc/pam.d/sudo
# Expected: /etc/pam.d/sudo mode 0644

# Verify Redis file descriptor limit
cat /proc/$(pgrep -f 'redis-server')/limits | grep 'Max open files'
# Expected: Max open files = 10032 (soft) and 10032 (hard)

# ============================================================
# LOGS
# ============================================================

# Redis logs via syslog (syslogenabled=yes, syslogfacility=local0)
journalctl -u redis@6379 -n 50 --no-pager
grep 'redis-6379' /var/log/syslog 2>/dev/null | tail -20
grep 'redis-6379' /var/log/messages 2>/dev/null | tail -20

# Memcached logs
journalctl -u memcached -n 50 --no-pager

# ============================================================
# NETWORK SUMMARY
# ============================================================

# All cache service ports at a glance
netstat -tulpn | grep -E '6379|11211'
ss -tlnp | grep -E '6379|11211'
# Expected:
#   tcp  0.0.0.0:6379   (redis)
#   tcp  0.0.0.0:11211  (memcached)
#   udp  0.0.0.0:11211  (memcached)
```