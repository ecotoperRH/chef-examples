---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services on a single host: **Memcached** (in-memory object cache) and **Redis** (persistent key-value store). Memcached is deployed as a single instance via the `memcached` community cookbook using a custom resource, listening on port 11211 with 64 MB memory and 1024 max connections. Redis is deployed as a single instance via the `redisio` community cookbook, built from source (version 3.2.11 by default, unless package install is enabled), listening on port 6379 with password authentication (`redis_secure_password_123`). A post-configuration `ruby_block` hack patches the generated `/etc/redis/6379.conf` to strip out several incompatible directives. The cookbook supports Ubuntu ≥ 18.04 and CentOS ≥ 7.0, and uses systemd for service management on modern Linux.

## Service Type and Instances

**Service Type**: Cache (dual: Memcached + Redis)

**Configured Instances**:

- **memcached** (Memcached instance named `memcached`):
  - Location/Path: Binary via OS package `memcached`; config managed by `memcached_instance` custom resource
  - Port/Socket: TCP 11211 (also UDP 11211), bound to `0.0.0.0`
  - Key Config: memory=64 MB, maxconn=1024, ulimit=1024, max_object_size=1m, threads=default, log path=/var/log/memcached, run dir=/var/run/memcached
  - Service: started and enabled (systemd unit managed by the `memcached_instance` custom resource)

- **redis / port 6379** (Redis instance, server name derived from port `6379`):
  - Location/Path: Built from source tarball (version 3.2.11) downloaded from `http://download.redis.io/releases/`; binaries installed to `/usr/local/bin`; config at `/etc/redis/6379.conf`
  - Port/Socket: TCP 6379
  - Key Config: requirepass=`redis_secure_password_123`, backuptype=rdb, datadir=/var/lib/redis, loglevel=notice, syslog-enabled=yes, maxclients=10000, no maxmemory set, replicaservestaledata=nil (stripped by ruby_block hack), job_control=systemd (on modern Linux)
  - Service: `redis@6379` (systemd), started and enabled
  - Post-config hack: `/etc/redis/6379.conf` is patched after generation to remove lines matching `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`

## File Structure

```
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. cache::default** (`cookbooks/cache/recipes/default.rb`):
- Sets `node['redisio']['servers']` to a single-element array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Includes `memcached::default` (installs and starts Memcached)
- Creates directory `/var/log/redis` (owner: redis, group: redis, mode: 0755, recursive: true)
- Includes `redisio::default` (installs and configures Redis)
- Executes `ruby_block['fix_redis_config']`: reads `/etc/redis/6379.conf` and strips the following directives using regex substitution:
  - Lines matching `^replica-serve-stale-data.*$`
  - Lines matching `^replica-read-only.*$`
  - Lines matching `^repl-ping-replica-period.*$`
  - Lines matching `^client-output-buffer-limit.*$`
  - Lines matching `^replica-priority.*$`
- Includes `redisio::enable` (starts and enables the Redis service)
- Resources: include_recipe (3), directory (1), ruby_block (1)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with the following parameters (from `node['memcached']` attributes):
  - `memory`: 64 (MB)
  - `port`: 11211
  - `udp_port`: 11211
  - `listen`: `0.0.0.0`
  - `maxconn`: 1024
  - `user`: service_user (system user created by `_package.rb`)
  - `max_object_size`: `1m`
  - `threads`: nil (default)
  - `experimental_options`: `[]`
  - `extra_cli_options`: `[]`
  - `ulimit`: 1024
  - `action`: `[:start, :enable]`
- The `memcached_instance` custom resource internally calls `_package.rb` logic to:
  - Install package `memcached` (version: nil = latest)
  - Create system group `memcached`
  - Create system user `memcached` (shell: /bin/false, home: /nonexistent, locked)
  - Create directory `/var/log/memcached` (owner: memcached, group: memcached, mode: 0755)
  - Create directory `/var/run/memcached` (owner: memcached, group: memcached, mode: 0755)
  - Start and enable the memcached service
- Resources: memcached_instance (1) → internally: package (1), group (1), user (1), directory (2), service (1)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (refreshes apt cache on Debian/Ubuntu)
- **Conditional** — unless `node['redisio']['package_install']` is true (default: false on Debian/Ubuntu, so this branch IS executed):
  - Includes `redisio::_install_prereqs` (installs prerequisite packages)
  - Uses custom resource `build_essential['install build deps']` (installs gcc, make, etc.)
- **Conditional** — unless `node['redisio']['bypass_setup']` is true (default: false, so this branch IS executed):
  - Includes `redisio::install`
  - Includes `redisio::disable_os_default`
  - Includes `redisio::configure`
- Resources: apt_update (1), build_essential (1), include_recipe (3)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Installs prerequisite packages based on platform family:
  - **Debian/Ubuntu**: installs package `tar`
  - **RHEL/Fedora**: installs package `tar`
  - **Other**: no packages installed
- Iterations: Runs 1 time for: **tar**
- Resources: package (1)

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- **Conditional** — if `node['redisio']['package_install']` is true: installs OS package `redis-server` (Debian) or `redis` (RHEL) at the configured version. **This branch is NOT taken on Debian/Ubuntu by default.**
- **Conditional** — else (source install, this IS the default path on Debian/Ubuntu):
  - Includes `redisio::_install_prereqs` again (idempotent)
  - Uses custom resource `build_essential['install build deps']`
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - Downloads tarball from `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - Extracts to a temp directory, runs `make clean && make`, then `make install`
    - Installs binaries to `/usr/local/bin` (redis-server, redis-cli, etc.)
    - `safe_install`: true (skips reinstall if binary already exists)
- Includes `redisio::ulimit`
- Resources: build_essential (1), redisio_install (1), include_recipe (2)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- **Conditional** — if platform_family is `debian`:
  - Deploys template `/etc/pam.d/su` (cookbook: nil = uses default redisio template for PAM su configuration)
  - Deploys `cookbook_file[/etc/pam.d/sudo]` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `'sudo'`, mode: 0644)
- **Conditional** — if `node['ulimit']['users']` key exists (default: empty Mash, so this loop does NOT execute unless users are defined):
  - Iterates over `node['ulimit']['users']` hash and creates `user_ulimit` resources per user
- Note: With default attributes, `node['ulimit']['users']` is an empty Mash, so no `user_ulimit` resources are created. The PAM files ARE deployed on Debian/Ubuntu.
- Resources: template (1, Debian only), cookbook_file (1, Debian only), user_ulimit (0 by default)

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines the OS-default Redis service name:
  - **Debian/Ubuntu**: `redis-server`
  - **RHEL/Fedora**: `redis`
- Stops and disables the OS-default Redis service to prevent conflicts with the custom-installed Redis
- Resources: service (1) with actions `[:stop, :disable]`

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - Passes `version`, `default_settings`, `servers` (the 1-element array with port 6379), and `base_piddir` (`/var/run/redis`)
  - **Provider iterates once for the single server: port 6379 (server_name = "6379")**:
    - Creates system user `redis` (home: /var/lib/redis, shell: /bin/false on Debian)
    - Creates directory `/etc/redis` (owner: root, group: redis, mode: 0775, recursive: true)
    - Creates directory `/var/lib/redis` (owner: redis, group: redis, mode: 0775, recursive: true)
    - Creates directory `/var/run/redis/6379` (owner: redis, group: redis, mode: 0755, recursive: true)
    - Sets up `user_ulimit['redis']` with filehandle_limit = maxclients(10000) + 32 = **10032**
    - Renders template `redis.conf.erb` → `/etc/redis/6379.conf`:
      - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
      - Key variables: port=6379, requirepass=`redis_secure_password_123`, backuptype=rdb, datadir=/var/lib/redis, loglevel=notice, syslogenabled=yes, syslogfacility=local0, maxclients=10000, tcpbacklog=511, timeout=0, keepalive=0, databases=16, replicaservestaledata=nil (will be stripped by ruby_block), appendfsync=everysec, hz=10, clusterenabled=no
      - Protected by breadcrumb file: `/etc/redis/6379.conf.breadcrumb` (config is only written once; subsequent Chef runs skip it)
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb`
    - **Conditional on job_control (systemd on modern Linux)**:
      - Creates tmpfiles.d entry `/etc/tmpfiles.d/redis@6379.conf` (content: `d /var/run/redis/6379 0755 redis redis`)
      - Renders template `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`:
        - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb`
        - Variables: bin_path=/usr/local/bin, user=redis, group=redis, limit_nofile=10032
        - Notifies: `execute['redis@6379 systemd reload']` → runs `systemctl daemon-reload`
      - **If initd**: renders `redis.init.erb` → `/etc/init.d/redis6379`
      - **If upstart**: renders `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`
      - **If rcinit**: renders `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`
- After the custom resource, iterates once for server **6379**:
  - **systemd**: creates service resource `service['redis@6379']` (provider: Systemd, supports start/stop/restart/status)
  - **initd**: creates service resource `service['redis6379']`
  - **upstart**: creates service resource `service['redis6379']` (provider: Upstart)
  - **rcinit**: creates service resource `service['redis6379']` (provider: Freebsd)
- Resources: redisio_configure (1) → internally: user (1), directory (3), user_ulimit (1), template (1 for redis.conf + 1 for service file), file (2 breadcrumb + tmpfiles), execute (1); service (1)

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates once over `node['redisio']['servers']` for server **6379**:
  - Looks up the already-declared service resource:
    - **systemd**: `service['redis@6379']`
    - **other**: `service['redis6379']`
  - Appends actions `[:start, :enable]` to the service resource (ensuring Redis starts and is enabled at boot)
- Resources: (modifies existing service resource, no new resources declared)

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0` (community cookbook, provides `memcached_instance` custom resource)
- `redisio` (community cookbook, provides `redisio_install`, `redisio_configure`, `user_ulimit` custom resources)

**System package dependencies**:
- `memcached` (OS package, latest version)
- `tar` (prerequisite for Redis source build)
- `build-essential` toolchain: `gcc`, `make`, `g++`, `binutils`, `autoconf`, `automake`, `libtool`, `bison` (via `build_essential` custom resource)

**Service dependencies**:
- `memcached` (systemd service, managed by `memcached_instance` custom resource)
- `redis@6379` (systemd template unit, managed by `redisio` cookbook)
- `redis-server` or `redis` (OS default service — explicitly **stopped and disabled** to avoid conflicts)

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` set inline as `'redis_secure_password_123'`; rendered into `/etc/redis/6379.conf` as `requirepass redis_secure_password_123`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`); also rendered via `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
- **Current storage**: Hardcoded plaintext in recipe attribute override
- **Usage context**: Redis `requirepass` directive — all clients connecting to Redis on port 6379 must authenticate with this password using `AUTH redis_secure_password_123` before issuing commands

> **Note for Solutions Architect**: The `redisio` cookbook also supports loading the Redis password from a Chef data bag (via `data_bag_name`, `data_bag_item`, `data_bag_key` server attributes), but this cookbook does **not** use that mechanism. In Ansible, this password must be stored in AAP Credential Store, HashiCorp Vault, or an Ansible Vault-encrypted variable, and injected as a variable at playbook runtime. **Do not hardcode it in Ansible playbooks or variable files.**

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration file (generated from template, then patched by ruby_block)
- `/etc/redis/6379.conf.breadcrumb` — Breadcrumb sentinel file (prevents config overwrite on re-runs)
- `/lib/systemd/system/redis@6379.service` — Systemd unit file for Redis (on systemd systems)
- `/etc/tmpfiles.d/redis@6379.conf` — Systemd tmpfiles entry for PID directory
- `/var/lib/redis/` — Redis data directory (RDB dump files: `dump-6379.rdb`)
- `/var/run/redis/6379/` — Redis PID directory (`redis_6379.pid`)
- `/var/log/redis/` — Redis log directory (created by cache::default; syslog is used by default, not a file)
- `/usr/local/bin/redis-server` — Redis server binary (source-built)
- `/usr/local/bin/redis-cli` — Redis CLI binary (source-built)
- `/etc/pam.d/su` — PAM su file (modified by ulimit recipe on Debian/Ubuntu)
- `/etc/pam.d/sudo` — PAM sudo file (deployed by ulimit recipe on Debian/Ubuntu)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached run directory

**Service endpoints to check**:
- TCP 6379 — Redis
- TCP 11211 — Memcached
- UDP 11211 — Memcached
- Unix sockets: None configured (both services use TCP)
- Network interfaces: Memcached binds to `0.0.0.0`; Redis binds to all interfaces (no `bind` directive set)

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf`: renders **1 time** (for the single server on port 6379); protected by breadcrumb after first render
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: renders **1 time** (systemd systems only)
- `/etc/pam.d/su` template: renders **1 time** (Debian/Ubuntu only)

## Pre-flight Checks

```bash
###############################################################################
# MEMCACHED CHECKS
###############################################################################

# 1. Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# 2. Verify memcached is listening on TCP 11211
ss -tlnp | grep 11211
netstat -tulpn | grep 11211
lsof -i :11211

# 3. Memcached connectivity test (requires netcat or telnet)
echo "stats" | nc -q1 localhost 11211 | grep -E 'STAT version|STAT curr_connections|STAT max_connections'
# Expected: STAT version <version>, STAT max_connections 1024

# 4. Memcached set/get test
echo -e "set testkey 0 60 5\r\nhello\r\nget testkey\r\nquit\r\n" | nc -q2 localhost 11211
# Expected: STORED, then VALUE testkey 0 5 / hello / END

# 5. Verify memcached configuration parameters
ps aux | grep memcached | grep -v grep
# Expected: -m 64 (memory), -p 11211 (port), -U 11211 (udp), -l 0.0.0.0, -c 1024 (maxconn)

# 6. Verify memcached user and directories
id memcached
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/

# 7. Memcached logs
journalctl -u memcached -n 50 --no-pager

###############################################################################
# REDIS CHECKS
###############################################################################

# 8. Service status
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep

# 9. Verify Redis binary (source-built)
ls -lh /usr/local/bin/redis-server
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 (or higher if already installed)

ls -lh /usr/local/bin/redis-cli
/usr/local/bin/redis-cli --version

# 10. Verify Redis is listening on TCP 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i :6379

# 11. Redis authentication test (password required)
/usr/local/bin/redis-cli -p 6379 ping
# Expected: NOAUTH Authentication required (confirms auth is enforced)

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' ping
# Expected: PONG

# 12. Redis INFO check
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' info server | grep -E 'redis_version|tcp_port|config_file|os'
# Expected: redis_version:3.2.11, tcp_port:6379

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' info clients | grep -E 'connected_clients|maxclients'
# Expected: maxclients:10000

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' info persistence | grep -E 'rdb_bgsave_status|aof_enabled'
# Expected: rdb_bgsave_status:ok, aof_enabled:0

# 13. Redis configuration file validation
ls -lah /etc/redis/6379.conf
ls -lah /etc/redis/6379.conf.breadcrumb
cat /etc/redis/6379.conf | grep -E '^port|^requirepass|^maxclients|^loglevel|^syslog-enabled|^dir|^appendonly'
# Expected: port 6379, requirepass redis_secure_password_123, maxclients 10000, loglevel notice, syslog-enabled yes, dir /var/lib/redis, appendonly no

# 14. Verify the ruby_block hack removed incompatible directives
grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority' /etc/redis/6379.conf
# Expected: NO output (all these lines should have been stripped)

# 15. Verify Redis systemd unit file
ls -lah /lib/systemd/system/redis@6379.service
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no, User=redis, LimitNOFILE=10032

# 16. Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# 17. Verify Redis data and PID directories
ls -lah /var/lib/redis/
ls -lah /var/run/redis/6379/
ls -lah /var/log/redis/

# 18. Verify Redis user
id redis
# Expected: uid=<N>(redis) gid=<N>(redis) groups=<N>(redis)

# 19. Verify file descriptor limits for redis user
cat /proc/$(pgrep -f 'redis-server')/limits | grep -i 'open files'
# Expected: Max open files = 10032 (or higher)

# 20. Redis set/get functional test
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' set migration_test "ok"
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' get migration_test
# Expected: OK, then "ok"
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' del migration_test

# 21. Redis syslog check (syslog-enabled yes, facility local0)
journalctl -u redis@6379 -n 50 --no-pager
grep 'redis' /var/log/syslog 2>/dev/null | tail -20 || grep 'redis' /var/log/messages 2>/dev/null | tail -20

###############################################################################
# PAM / ULIMIT CHECKS (Debian/Ubuntu only)
###############################################################################

# 22. Verify PAM files were deployed
ls -lah /etc/pam.d/su
ls -lah /etc/pam.d/sudo
# Expected: both files exist and are owned by root

###############################################################################
# OS DEFAULT REDIS SERVICE DISABLED CHECK
###############################################################################

# 23. Verify OS default Redis service is stopped and disabled
# On Debian/Ubuntu:
systemctl is-active redis-server 2>/dev/null && echo "WARNING: redis-server is still active!" || echo "OK: redis-server is inactive"
systemctl is-enabled redis-server 2>/dev/null && echo "WARNING: redis-server is still enabled!" || echo "OK: redis-server is disabled"

# On RHEL/CentOS:
systemctl is-active redis 2>/dev/null && echo "WARNING: redis is still active!" || echo "OK: redis is inactive"
systemctl is-enabled redis 2>/dev/null && echo "WARNING: redis is still enabled!" || echo "OK: redis is disabled"

###############################################################################
# OVERALL RESOURCE SUMMARY
###############################################################################

# 24. Both services running
systemctl is-active memcached && echo "memcached: OK" || echo "memcached: FAILED"
systemctl is-active redis@6379 && echo "redis@6379: OK" || echo "redis@6379: FAILED"

# 25. Both ports open
ss -tlnp | grep -E '11211|6379'
# Expected: two lines — one for 11211 (memcached), one for 6379 (redis)
```