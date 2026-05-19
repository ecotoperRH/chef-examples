---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services on a single host: **Memcached** (in-memory object cache) and **Redis** (persistent key-value store). Memcached is deployed as a single named instance (`memcached`) via the `memcached_instance` custom resource, listening on TCP/UDP port 11211. Redis is deployed as a single instance on port 6379, built from source tarball (version 3.2.11 by default on non-package-install platforms), configured with password authentication (`redis_secure_password_123`), managed via systemd (on modern Linux), with a post-install `ruby_block` hack that strips several deprecated replication-related directives from the generated `/etc/redis/6379.conf`. The cookbook depends on the community `memcached` (~6.0) and `redisio` cookbooks.

## Service Type and Instances

**Service Type**: Cache (dual: in-memory object cache + persistent key-value store)

**Configured Instances**:

- **memcached** (Memcached instance name: `memcached`)
  - Location/Path: Binary via OS package `memcached`; config managed by `memcached_instance` custom resource
  - Port/Socket: TCP port **11211**, UDP port **11211**
  - Listen address: `0.0.0.0`
  - Key Config:
    - Memory: **64 MB**
    - Max connections: **1024**
    - Max object size: **1m**
    - Threads: default (not explicitly set in attributes)
    - ulimit: **1024**
    - Log directory: `/var/log/memcached`
    - Run directory: `/var/run/memcached`
    - System user/group: `memcached` (system account, shell `/bin/false`, home `/nonexistent`)

- **redis** (Redis instance name derived from port: `6379`)
  - Location/Path: Installed from source tarball (version **3.2.11**) to `/usr/local/bin`; config at `/etc/redis/6379.conf`
  - Port/Socket: TCP port **6379**
  - Key Config:
    - Password (`requirepass`): **`redis_secure_password_123`** (hardcoded in `default.rb`)
    - `replicaservestaledata`: explicitly set to `nil` (stripped by post-install hack)
    - Data directory: `/var/lib/redis`
    - PID directory: `/var/run/redis/6379`
    - Log: syslog enabled (`syslogenabled yes`, facility `local0`)
    - Max clients: **10000**
    - Backup type: **rdb** (dump file: `/var/lib/redis/dump-6379.rdb`)
    - Append-only: `appendfsync everysec`
    - Cluster: disabled
    - systemd service: `redis@6379`
    - Post-install config fixup: strips `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` lines from `/etc/redis/6379.conf`

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
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
- Entry point. Sets the Redis server list attribute to a single server on port 6379 with `requirepass = 'redis_secure_password_123'` and `replicaservestaledata = nil`.
- Calls `include_recipe 'memcached'` → triggers the full Memcached setup chain.
- Creates the Redis log directory `/var/log/redis` (owner: `redis`, group: `redis`, mode: `0755`, recursive).
- Calls `include_recipe 'redisio'` → triggers the full Redis setup chain.
- Executes `ruby_block 'fix_redis_config'`: reads `/etc/redis/6379.conf` and strips the following lines using regex substitution:
  - Lines matching `^replica-serve-stale-data.*$`
  - Lines matching `^replica-read-only.*$`
  - Lines matching `^repl-ping-replica-period.*$`
  - Lines matching `^client-output-buffer-limit.*$`
  - Lines matching `^replica-priority.*$`
  - Writes the cleaned content back to `/etc/redis/6379.conf`
- Calls `include_recipe 'redisio::enable'` → starts and enables the Redis systemd service.
- Resources: include_recipe (3), directory (1), ruby_block (1)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with the following parameters drawn from `node['memcached']` attributes:
  - `memory`: **64** (MB)
  - `port`: **11211**
  - `udp_port`: **11211**
  - `listen`: **`0.0.0.0`**
  - `maxconn`: **1024**
  - `user`: `service_user` (resolved to `memcached`)
  - `max_object_size`: **`1m`**
  - `ulimit`: **1024**
  - `experimental_options`: `[]`
  - `extra_cli_options`: `[]`
  - Actions: `[:start, :enable]`
- The `memcached_instance` custom resource internally (via `_package.rb`) performs:
  - Installs OS package `memcached` (version: `nil` = latest available)
  - Creates system group `memcached`
  - Creates system user `memcached` (shell: `/bin/false`, home: `/nonexistent`, locked)
  - Creates log directory `/var/log/memcached` (owner: `memcached`, group: `memcached`, mode: `0755`)
  - Creates run directory `/var/run/memcached` (owner: `memcached`, group: `memcached`, mode: `0755`)
  - Starts and enables the `memcached` service
- Resources: memcached_instance (1) → internally: package (1), group (1), user (1), directory (2), service (1)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` to refresh APT package cache.
- **Conditional** (`unless node['redisio']['package_install']` — default is `false` on Debian/RHEL, so this branch IS taken on those platforms):
  - Calls `include_recipe 'redisio::_install_prereqs'`
  - Invokes `build_essential 'install build deps'` custom resource (installs gcc, make, etc.)
- **Conditional** (`unless node['redisio']['bypass_setup']` — default is `false`, so this branch IS taken):
  - Calls `include_recipe 'redisio::install'`
  - Calls `include_recipe 'redisio::disable_os_default'`
  - Calls `include_recipe 'redisio::configure'`
- Resources: apt_update (1), include_recipe (3), build_essential (1)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Determines packages to install based on platform family:
  - **Debian/Ubuntu**: installs package `tar`
  - **RHEL/Fedora**: installs package `tar`
  - **Other**: no packages
- Installs each package via `package` resource with action `:install`.
- Resources: package (1) — `tar`

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- **Conditional** (`if node['redisio']['package_install']` — default `false` on Debian/RHEL, so the **else** branch is taken):
  - Calls `include_recipe 'redisio::_install_prereqs'` (already visited)
  - Invokes `build_essential 'install build deps'`
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - `version`: **`3.2.11`**
    - `download_url`: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - `safe_install`: `true` (skips reinstall if binary already exists)
    - Provider actions (if not already installed):
      1. Downloads tarball via `remote_file` to download dir
      2. Unpacks: `tar zxf redis-3.2.11.tar.gz --strip-components=1 -C redis-3.2.11`
      3. Builds: `cd redis-3.2.11 && make clean && make`
      4. Installs: `cd redis-3.2.11 && make install` → binaries land in `/usr/local/bin`
- Calls `include_recipe 'redisio::ulimit'`
- Resources: build_essential (1), redisio_install (1) → internally: remote_file (1), execute (3)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- **Conditional** (`if platform_family?('debian')`):
  - Deploys template `/etc/pam.d/su` (cookbook: `node['ulimit']['pam_su_template_cookbook']` — default `nil`, uses redisio cookbook's own template)
  - Deploys `cookbook_file '/etc/pam.d/sudo'` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `'sudo'`)
- **Conditional** (`if ulimit.key?('users')`): `node['ulimit']['users']` defaults to an empty `Mash`, so this block is **not executed** unless users are explicitly configured. No `user_ulimit` resources are created in the default configuration.
- Resources (on Debian): template (1), cookbook_file (1)

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines the OS-default Redis service name:
  - **Debian/Ubuntu**: `redis-server`
  - **RHEL/Fedora**: `redis`
- Stops and disables that service: `service service_name do action [:stop, :disable] end`
- This prevents the OS-packaged Redis from conflicting with the source-built instance.
- Resources: service (1)

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - `version`: `3.2.11`
  - `default_settings`: full hash from `node['redisio']['default_settings']`
  - `servers`: the single-element array set in `cache::default` — `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
  - `base_piddir`: `/var/run/redis`
  - Provider iterates over the **1 server** (`port: 6379`) and performs:
    - Creates system user `redis` (home: `/var/lib/redis`, shell: `/bin/false` on Debian)
    - Creates config directory `/etc/redis` (owner: `root`, group: `redis`, mode: `0775`, recursive)
    - Creates data directory `/var/lib/redis` (owner: `redis`, group: `redis`, mode: `0775`, recursive)
    - Creates PID directory `/var/run/redis/6379` (owner: `redis`, group: `redis`, mode: `0755`, recursive)
    - Renders Redis config template → `/etc/redis/6379.conf` (source: `redis.conf.erb`, cookbook: `redisio`) with all variables including `requirepass: 'redis_secure_password_123'`; guarded by breadcrumb file `/etc/redis/6379.conf.breadcrumb` (only renders once)
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb`
    - **Systemd branch** (default on modern Linux — `node['redisio']['job_control'] == 'systemd'`):
      - Creates tmpfiles.d entry: `/etc/tmpfiles.d/redis@6379.conf` (content: `d /var/run/redis/6379 0755 redis redis`)
      - Renders systemd unit template: `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`
        - `ExecStart=/usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no`
        - `User=redis`, `Group=redis`, `LimitNOFILE=10032` (maxclients 10000 + 32)
        - Notifies `execute[redis@6379 systemd reload]` → runs `systemctl daemon-reload`
    - Sets up `user_ulimit` for `redis` user with filehandle limit `10032` (via `ulimit` cookbook resource)
- Creates service resource `service['redis@6379']` (provider: `Chef::Provider::Service::Systemd`)
- Resources: redisio_configure (1) → internally: user (1), directory (3), template (2), file (3), execute (1); service (1)

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates over the **1 Redis server** (`port: 6379`):
  - Looks up the already-declared service resource `service['redis@6379']`
  - Appends actions `[:start, :enable]` to it
- This causes the `redis@6379` systemd service to be started and enabled at boot.
- Resources: (modifies existing service resource — no new resources declared)

## Dependencies

**External cookbook dependencies** (from `metadata.rb`):
- `memcached` ~> 6.0
- `redisio` (no version pin)

**System package dependencies**:
- `memcached` (OS package, latest available)
- `tar` (prerequisite for Redis source build)
- Build tools via `build_essential`: `gcc`, `g++`, `make`, `binutils`, `autoconf`, `automake`, `libtool`, `pkg-config` (exact set depends on platform)

**Service dependencies** (systemd services managed):
- `memcached.service` — started and enabled
- `redis@6379.service` — started and enabled (source-built, systemd template unit)
- `redis-server.service` (Debian) or `redis.service` (RHEL) — stopped and disabled (OS default, conflicts with source build)

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe attribute assignment)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']` — value: `'redis_secure_password_123'`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal in the recipe file
- **Usage context**: Redis `requirepass` directive in `/etc/redis/6379.conf`. Any client connecting to Redis on port 6379 must authenticate with this password using `AUTH redis_secure_password_123`. The password is also passed as a variable to the `redis.conf.erb` template and to the `redis.init.erb` init script template (for `initd` job control). The `redisio` cookbook also supports loading this value from a Chef data bag (`data_bag_name`, `data_bag_item`, `data_bag_key` settings in `default_settings`) but that mechanism is **not used** here — the password is set directly in the recipe.

> ⚠️ **Action Required for Solutions Architect**: This password must be migrated out of the recipe and stored in AAP's credential store (e.g., HashiCorp Vault, CyberArk, or Ansible Vault). The Ansible role should consume it as a variable injected at runtime, not hardcoded in a task file or variable file.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration (post-hack: must NOT contain `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` directives)
- `/etc/redis/6379.conf.breadcrumb` — breadcrumb sentinel file (prevents config overwrite on re-run)
- `/lib/systemd/system/redis@6379.service` — systemd unit file for Redis
- `/etc/tmpfiles.d/redis@6379.conf` — tmpfiles.d entry for PID directory
- `/var/lib/redis/` — Redis data directory
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by `cache::default`)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached run directory
- `/usr/local/bin/redis-server` — Redis server binary (source-built)
- `/usr/local/bin/redis-cli` — Redis CLI binary (source-built)
- `/etc/security/limits.d/redis.conf` — ulimit configuration for redis user (filehandle limit 10032)
- `/etc/pam.d/su` — PAM su template (Debian only, from ulimit recipe)
- `/etc/pam.d/sudo` — PAM sudo cookbook_file (Debian only, from ulimit recipe)

**Service endpoints to check**:
- **6379** — Redis (TCP, all interfaces by default)
- **11211** — Memcached (TCP, `0.0.0.0`)
- **11211** — Memcached (UDP, `0.0.0.0`)
- Unix sockets: None configured by default
- Network interfaces: Both services bind to all interfaces (`0.0.0.0`) by default

**Templates rendered**:
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — rendered **1 time** (for the single Redis instance on port 6379)
- `redis.conf.erb` → `/etc/redis/6379.conf` — rendered **1 time** (guarded by breadcrumb; will not re-render if breadcrumb exists)
- `/etc/pam.d/su` template — rendered **1 time** on Debian platforms only

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED - Instance: memcached (port 11211)
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on TCP 11211
ss -tlnp | grep 11211
netstat -tulpn | grep 11211
lsof -i TCP:11211

# Verify memcached is listening on UDP 11211
ss -ulnp | grep 11211
netstat -tulpn | grep udp | grep 11211

# Functional test - memcached stats
echo "stats" | nc -q1 127.0.0.1 11211
echo "version" | nc -q1 127.0.0.1 11211
# Expected: STAT version 1.x.x

# Verify memory allocation (should show limit_maxbytes = 67108864 = 64MB)
echo "stats" | nc -q1 127.0.0.1 11211 | grep limit_maxbytes
# Expected: STAT limit_maxbytes 67108864

# Verify max connections
echo "stats settings" | nc -q1 127.0.0.1 11211 | grep maxconns
# Expected: STAT maxconns 1024

# Verify user and directories
id memcached
# Expected: uid=... gid=... groups=...
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/

# Logs
journalctl -u memcached -n 50 --no-pager
tail -f /var/log/memcached/memcached.log 2>/dev/null || journalctl -u memcached -f

# ============================================================
# REDIS - Instance: 6379 (port 6379)
# ============================================================

# Service status
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep
# Expected: redis-server /etc/redis/6379.conf --daemonize no

# Verify binary is source-built (version 3.2.11)
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 ...
ls -lh /usr/local/bin/redis-server
ls -lh /usr/local/bin/redis-cli

# Verify Redis is listening on TCP 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i TCP:6379

# Functional test - Redis ping (unauthenticated, should fail)
/usr/local/bin/redis-cli -p 6379 ping
# Expected: NOAUTH Authentication required

# Functional test - Redis ping with password
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' ping
# Expected: PONG

# Verify Redis server info
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' info server | grep -E 'redis_version|tcp_port|config_file'
# Expected: redis_version:3.2.11, tcp_port:6379, config_file:/etc/redis/6379.conf

# Verify requirepass is set in config
grep -E '^requirepass' /etc/redis/6379.conf
# Expected: requirepass redis_secure_password_123

# Verify post-install hack removed deprecated directives (all should return empty)
grep -E '^replica-serve-stale-data' /etc/redis/6379.conf
# Expected: (no output)
grep -E '^replica-read-only' /etc/redis/6379.conf
# Expected: (no output)
grep -E '^repl-ping-replica-period' /etc/redis/6379.conf
# Expected: (no output)
grep -E '^client-output-buffer-limit' /etc/redis/6379.conf
# Expected: (no output)
grep -E '^replica-priority' /etc/redis/6379.conf
# Expected: (no output)

# Verify breadcrumb file exists (prevents config overwrite)
ls -lah /etc/redis/6379.conf.breadcrumb
# Expected: file exists

# Verify systemd unit file
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no
grep -E 'LimitNOFILE' /lib/systemd/system/redis@6379.service
# Expected: LimitNOFILE=10032

# Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify directories and ownership
ls -lah /var/lib/redis/
# Expected: owned by redis:redis, mode 0775
ls -lah /var/run/redis/6379/
# Expected: owned by redis:redis, mode 0755
ls -lah /var/log/redis/
# Expected: owned by redis:redis, mode 0755
ls -lah /etc/redis/
# Expected: owned by root:redis, mode 0775

# Verify redis user
id redis
# Expected: uid=... gid=... groups=redis

# Verify ulimit for redis user
cat /etc/security/limits.d/redis.conf
# Expected: redis - nofile 10032

# Verify OS default Redis service is stopped and disabled
systemctl is-enabled redis-server 2>/dev/null || echo "redis-server not found (OK on RHEL)"
systemctl is-enabled redis 2>/dev/null || echo "redis not found (OK on Debian)"
# Expected: disabled or "not found"

# Verify data file
ls -lah /var/lib/redis/dump-6379.rdb 2>/dev/null || echo "RDB file not yet created (OK on fresh install)"

# Logs
journalctl -u redis@6379 -n 50 --no-pager
journalctl -u redis@6379 -f

# Verify service is enabled at boot
systemctl is-enabled redis@6379
# Expected: enabled

# ============================================================
# COMBINED HEALTH CHECK
# ============================================================

# Both services running
systemctl is-active memcached redis@6379
# Expected: active (x2)

# Port summary
ss -tlnp | grep -E '6379|11211'
# Expected: two entries, one for each port
```