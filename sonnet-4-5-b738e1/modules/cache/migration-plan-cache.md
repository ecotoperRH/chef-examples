---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two caching services on a single host: **Memcached** (in-memory object cache on port 11211) and **Redis** (key-value store on port 6379 with password authentication). Memcached is deployed via the `memcached` community cookbook using its `memcached_instance` custom resource, while Redis is deployed via the `redisio` community cookbook which compiles Redis 3.2.11 from source tarball (on Debian/RHEL non-FreeBSD systems), writes a full configuration to `/etc/redis/6379.conf`, and manages the service via systemd (or init.d/upstart depending on the platform). A post-configuration `ruby_block` hack strips several incompatible directives from the Redis config file after it is written. The cookbook supports Ubuntu ≥ 18.04 and CentOS ≥ 7.0.

## Service Type and Instances

**Service Type**: Cache (dual-service: Memcached + Redis)

**Configured Instances**:

- **memcached** (single instance, name: `memcached`):
  - Location/Path: `/var/log/memcached` (log), `/var/run/memcached` (PID/socket)
  - Port/Socket: TCP 11211, UDP 11211
  - Key Config: memory=64 MB, maxconn=1024, listen=0.0.0.0, max_object_size=1m, ulimit=1024, threads=default

- **redis** (single instance, name derived from port: `6379`):
  - Location/Path: config `/etc/redis/6379.conf`, data `/var/lib/redis`, PID `/var/run/redis/6379/redis_6379.pid`
  - Port/Socket: TCP 6379
  - Key Config: requirepass=`redis_secure_password_123` (hardcoded), version=3.2.11 (source build), backuptype=rdb, maxclients=10000, loglevel=notice, syslog-enabled=yes, `replicaservestaledata` directive stripped post-config

## File Structure

```
cookbooks/cache/recipes/default.rb
cookbooks/cache/metadata.rb
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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
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
- Sets `node['redisio']['servers']` to a single-element array: port=`6379`, requirepass=`redis_secure_password_123`, replicaservestaledata=`nil`
- Calls `include_recipe 'memcached'` (triggers the full memcached setup chain)
- Creates directory `/var/log/redis` with owner=redis, group=redis, mode=0755, recursive=true
- Calls `include_recipe 'redisio'` (triggers the full Redis setup chain)
- Executes `ruby_block['fix_redis_config']`: reads `/etc/redis/6379.conf` and strips 5 directives using regex substitution: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
- Calls `include_recipe 'redisio::enable'` (starts and enables the Redis service)
- Resources: include_recipe (3), directory (1), ruby_block (1)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with action `[:start, :enable]`
  - memory: 64 (MB)
  - port: 11211
  - udp_port: 11211
  - listen: `0.0.0.0`
  - maxconn: 1024
  - user: `service_user` (resolved at runtime, typically `memcache` on Debian or `memcached` on RHEL)
  - max_object_size: `1m`
  - ulimit: 1024
  - experimental_options: `[]`
  - extra_cli_options: `[]`
- The `memcached_instance` custom resource internally calls `memcached::_package` which:
  - Installs package `memcached` (version=nil → latest)
  - Creates system group `service_group` (memcache/memcached)
  - Creates system user `service_user` (memcache/memcached), shell=/bin/false, home=/nonexistent, locked
  - Creates directory `/var/log/memcached` (owner=service_user, group=service_group, mode=0755)
  - Creates directory `/var/run/memcached` (owner=service_user, group=service_group, mode=0755)
- Resources: memcached_instance (1) → internally: package (1), group (1), user (1), directory (2)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (updates APT cache on Debian systems)
- Conditional: **unless** `node['redisio']['package_install']` is true (default is `false` on Debian/RHEL, so this branch IS taken):
  - Calls `include_recipe 'redisio::_install_prereqs'`
  - Uses custom resource `build_essential['install build deps']` (installs gcc, make, etc.)
- Conditional: **unless** `node['redisio']['bypass_setup']` is true (default is `false`, so this branch IS taken):
  - Calls `include_recipe 'redisio::install'`
  - Calls `include_recipe 'redisio::disable_os_default'`
  - Calls `include_recipe 'redisio::configure'`
- Resources: apt_update (1), build_essential (1), include_recipe (3)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Conditional: On Debian or RHEL/Fedora platforms, installs prerequisite packages
  - Installs package: **tar** (action: install)
  - On other platforms: no packages installed
- Resources: package (1) — `tar`

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- Conditional: **if** `node['redisio']['package_install']` is true → installs OS package `redis-server` (Debian) or `redis` (RHEL). **This branch is NOT taken** (package_install=false on Debian/RHEL).
- Conditional: **else** (package_install=false, this branch IS taken):
  - Calls `include_recipe 'redisio::_install_prereqs'` (already visited, no-op)
  - Uses custom resource `build_essential['install build deps']`
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - version: `3.2.11`
    - download_url: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - safe_install: `true` (skips reinstall if binary already exists)
    - install_dir: nil (installs to `/usr/local/bin`)
    - Provider actions: downloads tarball to temp dir, extracts with `tar zxf`, runs `make clean && make`, runs `make install` → places `redis-server`, `redis-cli` etc. in `/usr/local/bin`
- Calls `include_recipe 'redisio::ulimit'`
- Resources: build_essential (1), redisio_install (1), include_recipe (1)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- Conditional: **if** `platform_family?('debian')`:
  - Deploys template `/etc/pam.d/su` (cookbook: `node['ulimit']['pam_su_template_cookbook']` = nil → uses redisio's own template)
  - Deploys `cookbook_file[/etc/pam.d/sudo]` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `sudo`, cookbook: nil)
- Conditional: **if** `ulimit.key?('users')`: `node['ulimit']['users']` defaults to an empty `Mash.new`, so this loop does NOT execute unless users are explicitly configured. No `user_ulimit` resources are created in the default configuration.
- Resources: template (1, Debian only), cookbook_file (1, Debian only), user_ulimit (0 by default)

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines OS default Redis service name:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`
- Stops and disables the OS default Redis service: `service[redis-server]` or `service[redis]` with action `[:stop, :disable]`
- This prevents the OS-packaged Redis from conflicting with the source-compiled one
- Resources: service (1)

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Resolves `redis_instances` from `node['redisio']['servers']` — set in `cache::default` to 1 server: port=`6379`, requirepass=`redis_secure_password_123`, replicaservestaledata=nil
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - version: `3.2.11`
  - default_settings: full hash from `node['redisio']['default_settings']`
  - servers: the 1-element array with port=6379
  - base_piddir: `/var/run/redis`
  - **Provider iterates once for the single server (port=6379, name=`6379`)**:
    - Creates user `redis` (comment='Redis service account', manage_home=true, home=/var/lib/redis, shell=/bin/false on Debian, systemuser=true)
    - Creates directory `/etc/redis` (owner=root, group=redis, mode=0775, recursive=true)
    - Creates directory `/var/lib/redis` (owner=redis, group=redis, mode=0775, recursive=true)
    - Creates directory `/var/run/redis/6379` (owner=redis, group=redis, mode=0755, recursive=true)
    - No log directory created (logfile=nil, syslog is used instead)
    - Sets up SELinux contexts if SELinux is enabled (selinux_fcontext for /etc/redis, /var/lib/redis, /var/run/redis/6379)
    - Sets `user_ulimit['redis']` with filehandle_limit = maxclients(10000) + 32 = **10032**
    - Renders template `redis.conf.erb` → `/etc/redis/6379.conf`:
      - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
      - Key variables: port=6379, requirepass=`redis_secure_password_123`, backuptype=rdb, maxclients=10000, loglevel=notice, syslogenabled=yes, syslogfacility=local0, databases=16, timeout=0, keepalive=0, appendfsync=everysec, hz=10, clusterenabled=no, tcpbacklog=511, replicaservestaledata=nil (will be stripped by ruby_block), replicareadonly=yes, replpingreplicaperiod=10, replicapriority=100, clientoutputbufferlimit=[normal 0 0 0, replica 256mb 64mb 60, pubsub 32mb 8mb 60]
      - **Note**: Template is protected by a breadcrumb file `/etc/redis/6379.conf.breadcrumb` — it will NOT be overwritten on subsequent Chef runs once the breadcrumb exists
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb`
    - Conditional on `node['redisio']['job_control']`:
      - **systemd** (default on modern Linux): renders `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`; creates tmpfiles.d entry `/etc/tmpfiles.d/redis@6379.conf`; runs `systemctl daemon-reload`
      - **initd**: renders `redis.init.erb` → `/etc/init.d/redis6379`
      - **upstart**: renders `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`
      - **rcinit** (FreeBSD): renders `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`
- After the `redisio_configure` custom resource, iterates once over redis_instances for port=`6379`:
  - **systemd**: creates `service[redis@6379]` resource (provider=Systemd, supports start/stop/restart/status)
  - **initd**: creates `service[redis6379]`
  - **upstart**: creates `service[redis6379]` (provider=Upstart)
  - **rcinit**: creates `service[redis6379]` (provider=Freebsd)
- Resources: redisio_configure (1), service (1)

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates once over `redis['servers']` for the single server with port=`6379`:
  - Looks up the already-declared service resource `service[redis@6379]` (systemd) or `service[redis6379]` (other)
  - Appends actions `[:start, :enable]` to the service resource
  - This causes Redis to be started and enabled at boot
- Resources: service action modification (1)

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0` (community cookbook, provides `memcached_instance` custom resource)
- `redisio` (community cookbook, provides `redisio_install`, `redisio_configure`, `user_ulimit` custom resources)

**System package dependencies**:
- `memcached` (OS package, version=latest)
- `tar` (prerequisite for Redis source build)
- Build tools via `build_essential`: `gcc`, `g++`, `make`, `binutils`, `autoconf`, `automake`, `libtool`, `m4`, `pkg-config` (exact set depends on platform)

**Service dependencies**:
- `memcached.service` (systemd) — managed by memcached_instance custom resource, actions: start + enable
- `redis@6379.service` (systemd) — managed by redisio, actions: start + enable
- `redis-server.service` or `redis.service` (OS default) — explicitly stopped and disabled

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']` set to the string `redis_secure_password_123`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal in the recipe file
- **Usage context**: Written directly into `/etc/redis/6379.conf` as the `requirepass` directive. All Redis clients must supply this password via `AUTH redis_secure_password_123` before executing commands. Also passed as a variable to the `redis.init.erb` template (for init.d-based shutdown via `redis-cli -a`).

> ⚠️ **Security Note for Solutions Architect**: This password is committed in plaintext to the cookbook source. During Ansible migration, this credential MUST be moved to a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, or AAP Credential Store) and injected as an Ansible variable (e.g., `vault_redis_password`) rather than hardcoded in playbooks or variable files.

**Additional credential-adjacent note**: The `redisio` provider (`providers/configure.rb`) supports loading `requirepass` from a Chef data bag (`data_bag_name`, `data_bag_item`, `data_bag_key` per-server attributes). This mechanism is **not used** in the current cookbook — the password is hardcoded instead.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration file (rendered once, protected by breadcrumb)
- `/etc/redis/6379.conf.breadcrumb` — Breadcrumb sentinel file (prevents config overwrite)
- `/lib/systemd/system/redis@6379.service` — systemd unit file for Redis (systemd platforms)
- `/etc/tmpfiles.d/redis@6379.conf` — tmpfiles.d entry for PID directory (systemd platforms)
- `/etc/init.d/redis6379` — init.d script (non-systemd Debian/RHEL)
- `/etc/init/redis6379.conf` — Upstart config (Upstart platforms)
- `/etc/pam.d/su` — PAM su template (Debian only, from ulimit recipe)
- `/etc/pam.d/sudo` — PAM sudo cookbook_file (Debian only, from ulimit recipe)
- `/var/lib/redis/` — Redis data directory
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by cache::default)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached runtime directory
- `/usr/local/bin/redis-server` — Redis server binary (source install)
- `/usr/local/bin/redis-cli` — Redis CLI binary (source install)

**Service endpoints to check**:
- Redis: TCP **6379** (all interfaces, 0.0.0.0 by default unless `address` is set)
- Memcached: TCP **11211** and UDP **11211** (listen=0.0.0.0)
- Unix sockets: None configured by default (unixsocket=nil)

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf`: rendered **once** for the single Redis instance (port 6379). Protected by breadcrumb — will not re-render on subsequent runs if breadcrumb exists.
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: rendered **once** (systemd platforms only)
- `redis.init.erb` → `/etc/init.d/redis6379`: rendered **once** (initd platforms only)
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`: rendered **once** (upstart platforms only)
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`: rendered **once** (FreeBSD only)

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED CHECKS
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on port 11211 (TCP and UDP)
ss -tlnp | grep 11211
ss -ulnp | grep 11211
netstat -tulpn | grep 11211

# Memcached connectivity test - send a stats command
echo "stats" | nc -q 1 127.0.0.1 11211
# Expected: lines starting with STAT, ending with END

# Verify memcached version
echo "version" | nc -q 1 127.0.0.1 11211
# Expected: VERSION x.x.x

# Verify memcached memory limit (should be 64 MB)
echo "stats" | nc -q 1 127.0.0.1 11211 | grep limit_maxbytes
# Expected: STAT limit_maxbytes 67108864  (64 * 1024 * 1024)

# Verify memcached max connections (should be 1024)
echo "stats" | nc -q 1 127.0.0.1 11211 | grep maxconns
# Expected: STAT maxconns 1024

# Verify memcached user and directories
id memcache 2>/dev/null || id memcached 2>/dev/null
# Expected: uid=... gid=... groups=...

ls -lah /var/log/memcached/
# Expected: directory owned by memcache/memcached, mode 0755

ls -lah /var/run/memcached/
# Expected: directory owned by memcache/memcached, mode 0755

# Memcached set/get test
printf "set testkey 0 60 5\r\nhello\r\n" | nc -q 1 127.0.0.1 11211
# Expected: STORED
printf "get testkey\r\n" | nc -q 1 127.0.0.1 11211
# Expected: VALUE testkey 0 5 / hello / END

# Logs
journalctl -u memcached -n 50 --no-pager
# Expected: no ERROR lines, service started successfully

# ============================================================
# REDIS (instance: 6379) CHECKS
# ============================================================

# Service status
systemctl status "redis@6379"
ps aux | grep redis-server | grep -v grep
# Expected: redis-server process running as user 'redis'

# Verify Redis binary (source-compiled, version 3.2.11)
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 sha=...

/usr/local/bin/redis-cli --version
# Expected: redis-cli 3.2.11

ls -lh /usr/local/bin/redis-server /usr/local/bin/redis-cli
# Expected: both files present, executable

# Verify Redis is listening on port 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i :6379
# Expected: redis-server listening on 0.0.0.0:6379

# Redis connectivity WITHOUT password (should fail)
/usr/local/bin/redis-cli -p 6379 PING
# Expected: (error) NOAUTH Authentication required

# Redis connectivity WITH password (should succeed)
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' PING
# Expected: PONG

# Redis server info
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep -E 'redis_version|tcp_port|config_file|os'
# Expected: redis_version:3.2.11, tcp_port:6379

# Verify Redis configuration file exists and key directives are present
ls -lah /etc/redis/6379.conf
# Expected: file present, owned by redis:redis, mode 0644

grep -E '^port|^requirepass|^loglevel|^maxclients|^syslog-enabled|^databases' /etc/redis/6379.conf
# Expected:
#   port 6379
#   requirepass redis_secure_password_123
#   loglevel notice
#   maxclients 10000
#   syslog-enabled yes
#   databases 16

# Verify the ruby_block hack removed the problematic directives
grep -E '^replica-serve-stale-data|^replica-read-only|^repl-ping-replica-period|^client-output-buffer-limit|^replica-priority' /etc/redis/6379.conf
# Expected: NO output (all 5 directives should be absent)

# Verify breadcrumb file exists (prevents config overwrite)
ls -lah /etc/redis/6379.conf.breadcrumb
# Expected: file present

# Verify systemd unit file
ls -lah /lib/systemd/system/redis@6379.service
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no

# Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify Redis data and PID directories
ls -lah /var/lib/redis/
# Expected: directory owned by redis:redis, mode 0775

ls -lah /var/run/redis/6379/
# Expected: directory owned by redis:redis, mode 0755

ls -lah /var/log/redis/
# Expected: directory owned by redis:redis, mode 0755

# Verify Redis user
id redis
# Expected: uid=... gid=... groups=redis

# Verify ulimit for redis user (should be 10032)
cat /etc/security/limits.d/redis.conf 2>/dev/null || echo "No limits file found"
# Expected: redis soft nofile 10032 / redis hard nofile 10032

# Redis persistence check (RDB mode)
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' CONFIG GET save
# Expected: save / 900 1 300 10 60 10000 (default RDB save points)

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' CONFIG GET appendonly
# Expected: appendonly / no  (RDB mode, not AOF)

# Redis set/get test
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' SET migration_test "ok"
# Expected: OK
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' GET migration_test
# Expected: "ok"
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' DEL migration_test
# Expected: (integer) 1

# Redis replication status (standalone, no replica configured)
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' INFO replication
# Expected: role:master, connected_slaves:0

# Redis memory info
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' INFO memory | grep -E 'used_memory_human|maxmemory_human'
# Expected: used_memory_human: <some value>, maxmemory_human: 0B (no limit set)

# Logs via syslog (syslogenabled=yes, syslogfacility=local0)
journalctl -u "redis@6379" -n 50 --no-pager
grep 'redis' /var/log/syslog 2>/dev/null | tail -20
grep 'redis' /var/log/messages 2>/dev/null | tail -20
# Expected: no ERROR or WARNING lines after startup

# Verify OS default Redis service is stopped and disabled
systemctl is-active redis-server 2>/dev/null && echo "WARNING: OS redis-server still active!" || echo "OK: redis-server inactive"
systemctl is-enabled redis-server 2>/dev/null && echo "WARNING: OS redis-server still enabled!" || echo "OK: redis-server disabled"
# On RHEL:
systemctl is-active redis 2>/dev/null && echo "WARNING: OS redis still active!" || echo "OK: redis inactive"
systemctl is-enabled redis 2>/dev/null && echo "WARNING: OS redis still enabled!" || echo "OK: redis disabled"

# ============================================================
# COMBINED HEALTH SUMMARY
# ============================================================

# Both services running
systemctl is-active memcached && echo "memcached: OK" || echo "memcached: FAILED"
systemctl is-active "redis@6379" && echo "redis@6379: OK" || echo "redis@6379: FAILED"

# Both services enabled at boot
systemctl is-enabled memcached && echo "memcached boot: OK" || echo "memcached boot: FAILED"
systemctl is-enabled "redis@6379" && echo "redis@6379 boot: OK" || echo "redis@6379 boot: FAILED"
```