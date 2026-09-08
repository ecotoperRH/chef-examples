---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two caching services on a single host: **Memcached** (in-memory object cache, port 11211) and **Redis** (persistent key-value store, port 6379). Memcached is installed via the `memcached` community cookbook using its `memcached_instance` custom resource. Redis is installed from source (tarball v3.2.11 by default on non-package-install platforms) via the `redisio` community cookbook, configured with password authentication (`redis_secure_password_123`), and managed as a systemd service (`redis@6379`). A post-configuration `ruby_block` hack strips several deprecated replica-related directives from the generated `/etc/redis/6379.conf` to ensure compatibility with the installed Redis version.

## Service Type and Instances

**Service Type**: Cache (dual-service: Memcached + Redis)

**Configured Instances**:

- **memcached** (instance name: `memcached`):
  - Location/Path: Config managed by `memcached_instance` custom resource; log directory `/var/log/memcached`; PID directory `/var/run/memcached`
  - Port/Socket: TCP port **11211**, UDP port **11211**
  - Key Config: memory=64MB, maxconn=1024, listen=0.0.0.0, max_object_size=1m, ulimit=1024, threads=default (not set), no experimental or extra CLI options

- **redis** (server name: `6379`, derived from port):
  - Location/Path: Config file `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`; log directory `/var/log/redis`
  - Port/Socket: TCP port **6379**
  - Key Config: requirepass=`redis_secure_password_123`, backuptype=rdb, maxclients=10000, loglevel=notice, syslog-enabled=yes, syslog-facility=local0, databases=16, replicaservestaledata=nil (stripped by ruby_block hack), managed via systemd as `redis@6379`

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
- Sets `node['redisio']['servers']` to a single-element array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Includes `memcached::default` (installs and starts Memcached)
- Creates directory `/var/log/redis` with owner `redis`, group `redis`, mode `0755`, recursive
- Includes `redisio::default` (installs and configures Redis)
- Executes `ruby_block['fix_redis_config']`: reads `/etc/redis/6379.conf` and strips the following lines using regex substitution:
  - Lines matching `^replica-serve-stale-data.*$`
  - Lines matching `^replica-read-only.*$`
  - Lines matching `^repl-ping-replica-period.*$`
  - Lines matching `^client-output-buffer-limit.*$`
  - Lines matching `^replica-priority.*$`
- Includes `redisio::enable` (starts and enables the Redis systemd service)
- Resources: include_recipe (3), directory (1), ruby_block (1)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with action `[:start, :enable]`
  - This custom resource internally calls `memcached::_package` to install the `memcached` package and set up the user/group/directories, then configures and starts the service
  - memory: 64 (MB)
  - port: 11211
  - udp_port: 11211
  - listen: 0.0.0.0
  - maxconn: 1024
  - max_object_size: 1m
  - ulimit: 1024
  - experimental_options: [] (none)
  - extra_cli_options: [] (none)
- Resources: memcached_instance (1 custom resource)

**3. memcached::_package** (called internally by `memcached_instance` custom resource — `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb`):
- Installs package `memcached` (version from `node['memcached']['version']`, which defaults to `nil` meaning latest)
- Creates system group `memcached` (only if user does not already exist)
- Creates system user `memcached` with shell `/bin/false`, home `/nonexistent`, no managed home, action `[:create, :lock]`
- Creates directory `/var/log/memcached` with owner `memcached`, group `memcached`, mode `0755`
- Creates directory `/var/run/memcached` with owner `memcached`, group `memcached`, mode `0755`
- Resources: package (1), group (1), user (1), directory (2)

**4. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (updates APT cache on Debian/Ubuntu)
- **Conditional** — because `node['redisio']['package_install']` is `false` (default on Debian/Ubuntu):
  - Includes `redisio::_install_prereqs` (installs prerequisite packages)
  - Uses custom resource `build_essential['install build deps']` (installs gcc, make, etc.)
- **Conditional** — because `node['redisio']['bypass_setup']` is `false` (default):
  - Includes `redisio::install`
  - Includes `redisio::disable_os_default`
  - Includes `redisio::configure`
- Resources: apt_update (1), build_essential (1 custom resource), include_recipe (3)

**5. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- **Conditional** — on Debian/Ubuntu: installs package `tar`
- **Conditional** — on RHEL/Fedora: installs package `tar`
- Resources: package (1) — installs **tar**

**6. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- **Conditional** — because `node['redisio']['package_install']` is `false` (source install path):
  - Includes `redisio::_install_prereqs` (already visited — installs `tar`)
  - Uses custom resource `build_essential['install build deps']`
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - version: `3.2.11`
    - download_url: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - safe_install: `true` (skips reinstall if binary already exists)
    - install_dir: nil (installs to `/usr/local/bin`)
    - Provider actions: downloads tarball via `remote_file`, unpacks with `tar zxf`, builds with `make clean && make`, installs with `make install`
- Includes `redisio::ulimit`
- Resources: build_essential (1), redisio_install (1 custom resource), include_recipe (1)

**7. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- **Conditional** — on Debian/Ubuntu (`platform_family?('debian')`):
  - Deploys template `/etc/pam.d/su` (from `node['ulimit']['pam_su_template_cookbook']`, which defaults to `nil` — uses the redisio cookbook's own template)
  - Deploys `cookbook_file[/etc/pam.d/sudo]` from source `node['ulimit']['ulimit_overriding_sudo_file_name']` (default: `'sudo'`), mode `0644`
- **Conditional** — if `node['ulimit']['users']` has entries (defaults to empty `Mash.new`, so this block is skipped unless users are defined):
  - Iterates over each user and applies `user_ulimit` custom resource
- Resources: template (1, Debian only), cookbook_file (1, Debian only), user_ulimit (0 by default — no users configured)

**8. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines OS default Redis service name:
  - On Debian/Ubuntu: `redis-server`
  - On RHEL/Fedora: `redis`
- Stops and disables the OS-default Redis service: `service['redis-server']` (Debian) or `service['redis']` (RHEL) with action `[:stop, :disable]`
- Resources: service (1)

**9. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - version: `3.2.11`
  - default_settings: full hash from `node['redisio']['default_settings']`
  - servers: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
  - base_piddir: `/var/run/redis`
  - **Provider iterates once for server name `6379`**:
    - Creates system user `redis` (comment: 'Redis service account', manage_home: true, home: `/var/lib/redis`, shell: `/bin/false` on Debian, system: true)
    - Creates directory `/etc/redis` (owner: root, group: redis, mode: `0775`, recursive)
    - Creates directory `/var/lib/redis` (owner: redis, group: redis, mode: `0775`, recursive)
    - Creates directory `/var/run/redis/6379` (owner: redis, group: redis, mode: `0755`, recursive)
    - Sets up `user_ulimit['redis']` with filehandle_limit = maxclients(10000) + 32 = **10032** (since `ulimit` default is 0)
    - Renders template `redis.conf.erb` → `/etc/redis/6379.conf`:
      - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
      - Key variables: port=6379, requirepass=redis_secure_password_123, replicaservestaledata=nil, backuptype=rdb, datadir=/var/lib/redis, loglevel=notice, syslogenabled=yes, syslogfacility=local0, databases=16, maxclients=10000, appendfsync=everysec, hz=10, tcpbacklog=511, timeout=0, keepalive=0
      - **Note**: `not_if` guard: skips rendering if `/etc/redis/6379.conf.breadcrumb` already exists
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb` (action: create_if_missing, only if `breadcrumb == true`)
    - **Conditional** — because `node['redisio']['job_control']` is `'systemd'` (on systemd systems):
      - Creates file `/etc/tmpfiles.d/redis@6379.conf` with content `d /var/run/redis/6379 0755 redis redis\n`
      - Defines execute resource `redis@6379 systemd reload` (runs `systemctl daemon-reload`, action: nothing — triggered by template notify)
      - Renders template `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`:
        - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb`
        - Variables: bin_path=/usr/local/bin, user=redis, group=redis, limit_nofile=10032
        - Notifies: `execute[redis@6379 systemd reload]` immediately
- Creates service resource `service['redis@6379']` (provider: Chef::Provider::Service::Systemd)
- Resources: redisio_configure (1 custom resource), service (1)

**10. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates once over the single server `6379`:
  - Looks up existing service resource `service['redis@6379']` (systemd path)
  - Appends actions `[:start, :enable]` to the service resource
- This causes `redis@6379.service` to be started and enabled at boot
- Resources: (modifies existing service resource — no new resources created)

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0` (community cookbook — manages Memcached installation and service)
- `redisio` (community cookbook — manages Redis installation from source or package, configuration, and service)

**System package dependencies**:
- `memcached` (installed by memcached cookbook)
- `tar` (installed by redisio `_install_prereqs` recipe — required for tarball extraction)
- Build tools: `gcc`, `make`, `build-essential` / `Development Tools` (installed by `build_essential` custom resource — required for compiling Redis from source)

**Service dependencies**:
- `memcached.service` — managed by `memcached_instance` custom resource (started and enabled)
- `redis@6379.service` — systemd template unit, started and enabled by `redisio::enable`
- `redis-server.service` (Debian) or `redis.service` (RHEL) — OS default Redis service, **stopped and disabled** by `redisio::disable_os_default`

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe attribute assignment)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` — set inline in `cookbooks/cache/recipes/default.rb` as `'requirepass' => 'redis_secure_password_123'`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal in the recipe file
- **Usage context**: Written into `/etc/redis/6379.conf` as the `requirepass` directive. All Redis clients must authenticate with this password using the `AUTH` command before issuing any other commands. Also referenced in the `redis.init.erb` template as the `-a` flag for `redis-cli` shutdown commands (init.d path only; not applicable here since systemd is used).

> ⚠️ **Security Note for Solutions Architect**: This password (`redis_secure_password_123`) is stored in plaintext in the cookbook recipe. In the Ansible migration, this value **must** be moved to a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, or AAP Credential Store) and injected as an encrypted variable. Do **not** hardcode it in any Ansible variable file or playbook.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration file (rendered from `redis.conf.erb`)
- `/etc/redis/6379.conf.breadcrumb` — Breadcrumb sentinel file (prevents config overwrite on re-runs)
- `/lib/systemd/system/redis@6379.service` — Systemd unit file for Redis instance 6379
- `/etc/tmpfiles.d/redis@6379.conf` — tmpfiles.d entry for PID directory
- `/var/lib/redis/` — Redis data directory (RDB dump files: `dump-6379.rdb`)
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by cache cookbook)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached PID/socket directory
- `/etc/pam.d/su` — PAM su file (Debian only, modified by ulimit recipe)
- `/etc/pam.d/sudo` — PAM sudo file (Debian only, deployed by ulimit recipe)

**Service endpoints to check**:
- **11211** (TCP) — Memcached
- **11211** (UDP) — Memcached
- **6379** (TCP) — Redis
- Unix sockets: None configured (both services use TCP)
- Network interfaces: Memcached binds to `0.0.0.0` (all interfaces); Redis binds to all interfaces by default (no `bind` directive set)

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` — rendered **once** for server `6379` (skipped on subsequent runs if breadcrumb exists)
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — rendered **once** for server `6379`
- `/etc/pam.d/su` template — rendered **once** on Debian/Ubuntu only
- `cookbook_file` for `/etc/pam.d/sudo` — deployed **once** on Debian/Ubuntu only

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED CHECKS
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on port 11211 (TCP)
ss -tlnp | grep 11211
netstat -tulpn | grep 11211
lsof -i :11211

# Verify memcached is listening on UDP 11211
ss -ulnp | grep 11211

# Functional test - memcached stats
echo "stats" | nc -q1 localhost 11211
echo "version" | nc -q1 localhost 11211
# Expected output: VERSION <version_string>

# Verify memcached configuration (memory, maxconn, listen)
ps aux | grep memcached | grep -v grep
# Expected: should show -m 64 -p 11211 -U 11211 -l 0.0.0.0 -c 1024

# Verify directories
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/
# Expected: both directories owned by memcached:memcached, mode 0755

# Verify user and group
id memcached
getent passwd memcached
getent group memcached
# Expected: system user with shell /bin/false, home /nonexistent

# Memcached logs
journalctl -u memcached -n 50 --no-pager
# Expected: no ERROR lines, service started successfully

# ============================================================
# REDIS CHECKS
# ============================================================

# Service status
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep

# Verify Redis is listening on port 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i :6379
# Expected: redis-server process listening on 0.0.0.0:6379

# Functional test - Redis connectivity WITH authentication
redis-cli -p 6379 -a 'redis_secure_password_123' PING
# Expected: PONG

redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep redis_version
# Expected: redis_version:3.2.11

redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep tcp_port
# Expected: tcp_port:6379

# Verify authentication is enforced (should fail without password)
redis-cli -p 6379 PING
# Expected: (error) NOAUTH Authentication required

# Verify Redis configuration file
ls -lah /etc/redis/6379.conf
cat /etc/redis/6379.conf | grep -E '^port'
# Expected: port 6379

cat /etc/redis/6379.conf | grep -E '^requirepass'
# Expected: requirepass redis_secure_password_123

cat /etc/redis/6379.conf | grep -E '^maxclients'
# Expected: maxclients 10000

cat /etc/redis/6379.conf | grep -E '^databases'
# Expected: databases 16

cat /etc/redis/6379.conf | grep -E '^loglevel'
# Expected: loglevel notice

cat /etc/redis/6379.conf | grep -E '^syslog-enabled'
# Expected: syslog-enabled yes

# Verify the ruby_block hack removed deprecated directives
grep 'replica-serve-stale-data' /etc/redis/6379.conf
# Expected: no output (line was removed)

grep 'replica-read-only' /etc/redis/6379.conf
# Expected: no output (line was removed)

grep 'repl-ping-replica-period' /etc/redis/6379.conf
# Expected: no output (line was removed)

grep 'client-output-buffer-limit' /etc/redis/6379.conf
# Expected: no output (line was removed)

grep 'replica-priority' /etc/redis/6379.conf
# Expected: no output (line was removed)

# Verify breadcrumb file exists
ls -lah /etc/redis/6379.conf.breadcrumb
# Expected: file exists (prevents config overwrite on re-runs)

# Verify systemd unit file
ls -lah /lib/systemd/system/redis@6379.service
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no
#           LimitNOFILE=10032

# Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify Redis binary (source-compiled)
ls -lah /usr/local/bin/redis-server
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 ...

# Verify Redis is enabled at boot
systemctl is-enabled redis@6379
# Expected: enabled

# Verify OS default Redis service is stopped and disabled
systemctl is-active redis-server 2>/dev/null || echo "redis-server not active (expected)"
systemctl is-enabled redis-server 2>/dev/null || echo "redis-server not enabled (expected)"
# On RHEL/Fedora:
systemctl is-active redis 2>/dev/null || echo "redis not active (expected)"
systemctl is-enabled redis 2>/dev/null || echo "redis not enabled (expected)"

# Verify Redis directories
ls -lah /var/lib/redis/
# Expected: owned by redis:redis, mode 0775

ls -lah /var/run/redis/6379/
# Expected: owned by redis:redis, mode 0755

ls -lah /var/log/redis/
# Expected: owned by redis:redis, mode 0755

# Verify Redis user and group
id redis
getent passwd redis
getent group redis
# Expected: system user, home /var/lib/redis, shell /bin/false (Debian)

# Verify ulimit for redis user
cat /etc/security/limits.d/redis.conf 2>/dev/null || echo "Check ulimit configuration"
# Expected: redis - nofile 10032

# Redis logs (syslog-based by default)
journalctl -u redis@6379 -n 50 --no-pager
# Expected: no ERROR lines, "Server started" message present

# Redis persistence check (RDB)
redis-cli -p 6379 -a 'redis_secure_password_123' LASTSAVE
# Expected: Unix timestamp of last successful RDB save

ls -lah /var/lib/redis/dump-6379.rdb 2>/dev/null || echo "RDB file not yet created (normal if no data written)"

# Redis memory and performance info
redis-cli -p 6379 -a 'redis_secure_password_123' INFO memory | grep -E 'used_memory_human|maxmemory_human'
redis-cli -p 6379 -a 'redis_secure_password_123' INFO clients | grep connected_clients

# PAM files (Debian/Ubuntu only)
ls -lah /etc/pam.d/su
ls -lah /etc/pam.d/sudo
```