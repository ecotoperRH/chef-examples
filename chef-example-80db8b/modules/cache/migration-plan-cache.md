---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services on a single host: **Memcached** (a single instance on port 11211 using the `memcached_instance` custom resource) and **Redis** (a single instance on port 6379 built from source tarball version 3.2.11, with password authentication `redis_secure_password_123` hardcoded in the recipe). Redis is installed via the `redisio` community cookbook which compiles Redis from source, writes a configuration file to `/etc/redis/6379.conf`, sets up a systemd unit (`redis@6379`), and applies a post-install Ruby hack to strip several deprecated replication directives from the config file. Memcached is installed as a system package and managed via systemd.

## Service Type and Instances

**Service Type**: Cache (dual-service: Memcached + Redis)

**Configured Instances**:

- **memcached** (Memcached instance):
  - Location/Path: Package install; config managed by `memcached_instance` custom resource
  - Port/Socket: TCP 11211, UDP 11211
  - Key Config:
    - `memory`: 64 MB
    - `listen`: `0.0.0.0`
    - `maxconn`: 1024
    - `max_object_size`: 1m
    - `ulimit`: 1024
    - `threads`: default (not explicitly set in attributes)
    - Log directory: `/var/log/memcached`
    - Run directory: `/var/run/memcached`
    - Service actions: `:start`, `:enable`

- **redis / 6379** (Redis instance, name derived from port):
  - Location/Path: Source-compiled from tarball; binary at `/usr/local/bin/redis-server`; config at `/etc/redis/6379.conf`
  - Port/Socket: TCP 6379
  - Key Config:
    - `version`: 3.2.11 (compiled from source; download URL: `http://download.redis.io/releases/redis-3.2.11.tar.gz`)
    - `requirepass`: `redis_secure_password_123` (hardcoded in `recipes/default.rb`)
    - `replicaservestaledata`: `nil` (explicitly set to nil in recipe, then stripped from config by ruby_block hack)
    - `user`/`group`: `redis`
    - `datadir`: `/var/lib/redis`
    - `configdir`: `/etc/redis`
    - `base_piddir`: `/var/run/redis`
    - `loglevel`: `notice`
    - `syslogenabled`: `yes`
    - `maxclients`: 10000
    - `backuptype`: `rdb` (default saves: 900 1, 300 10, 60 10000)
    - `appendfsync`: `everysec`
    - `job_control`: `systemd` (on systemd-enabled hosts)
    - Systemd unit: `redis@6379.service` → `/lib/systemd/system/redis@6379.service`
    - Tmpfiles entry: `/etc/tmpfiles.d/redis@6379.conf`
    - Breadcrumb file: `/etc/redis/6379.conf.breadcrumb` (prevents config overwrite on re-runs)
    - Post-install hack: strips `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` lines from `/etc/redis/6379.conf`

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
- Entry point. Sets `node['redisio']['servers']` to a single-element array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Calls `include_recipe 'memcached'` (triggers the full Memcached setup)
- Creates directory `/var/log/redis` with owner `redis`, group `redis`, mode `0755`, recursive
- Calls `include_recipe 'redisio'` (triggers the full Redis setup)
- Defines `ruby_block['fix_redis_config']` which post-processes `/etc/redis/6379.conf` by stripping the following lines using regex substitution:
  - `replica-serve-stale-data ...`
  - `replica-read-only ...`
  - `repl-ping-replica-period ...`
  - `client-output-buffer-limit ...`
  - `replica-priority ...`
- Calls `include_recipe 'redisio::enable'` (starts and enables the Redis service)
- Resources: directory (1), ruby_block (1), include_recipe (3)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` with the following parameters drawn from `node['memcached']` attributes:
  - `memory`: 64 (MB)
  - `port`: 11211
  - `udp_port`: 11211
  - `listen`: `0.0.0.0`
  - `maxconn`: 1024
  - `user`: `service_user` (resolved to `memcache` on Debian/Ubuntu, `memcached` on RHEL)
  - `max_object_size`: `1m`
  - `ulimit`: 1024
  - `experimental_options`: `[]`
  - `extra_cli_options`: `[]`
  - Actions: `:start`, `:enable`
- The `memcached_instance` custom resource internally (via `_package.rb`):
  - Installs package `memcached` (version: nil = latest)
  - Creates system group `memcache`/`memcached`
  - Creates system user `memcache`/`memcached` (shell `/bin/false`, home `/nonexistent`, locked)
  - Creates directory `/var/log/memcached` (owner: service_user, mode `0755`)
  - Creates directory `/var/run/memcached` (owner: service_user, mode `0755`)
  - Starts and enables the `memcached` systemd service
- Resources (inside custom resource): package (1), group (1), user (1), directory (2), service (1)

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (updates APT cache on Debian/Ubuntu)
- **Conditional branch** — `unless node['redisio']['package_install']` (default: `false` on Debian/Ubuntu, so this branch IS taken):
  - Calls `include_recipe 'redisio::_install_prereqs'`
  - Calls `build_essential['install build deps']` (installs gcc, make, etc.)
- **Conditional branch** — `unless node['redisio']['bypass_setup']` (default: `false`, so this branch IS taken):
  - Calls `include_recipe 'redisio::install'`
  - Calls `include_recipe 'redisio::disable_os_default'`
  - Calls `include_recipe 'redisio::configure'`
- Resources: apt_update (1), build_essential (1), include_recipe (3)

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Installs prerequisite packages needed for source compilation
- **On Debian/Ubuntu**: installs package `tar`
- **On RHEL/Fedora**: installs package `tar`
- **On other platforms**: installs nothing
- Resources: package (1 — `tar`)

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- **Conditional branch** — `if node['redisio']['package_install']` (default: `false` on Debian/Ubuntu, so this branch is NOT taken)
- **Else branch** (source install — IS taken on Debian/Ubuntu):
  - Calls `include_recipe 'redisio::_install_prereqs'` (already visited, no-op)
  - Calls `build_essential['install build deps']` (already visited, no-op)
  - Uses custom resource `redisio_install['redis-installation']`:
    - `version`: `3.2.11`
    - `download_url`: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - `safe_install`: `true` (skips reinstall if binary already exists)
    - `install_dir`: `nil` (installs to default `/usr/local/bin`)
    - → Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - → Provider downloads tarball to a temp dir via `remote_file`
    - → Provider unpacks: `tar zxf redis-3.2.11.tar.gz --strip-components=1 -C redis-3.2.11`
    - → Provider builds: `cd redis-3.2.11 && make clean && make`
    - → Provider installs: `cd redis-3.2.11 && make install` (copies binaries to `/usr/local/bin`)
- Calls `include_recipe 'redisio::ulimit'`
- Resources: build_essential (1), redisio_install (1)

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- **Conditional branch** — `if platform_family?('debian')`:
  - Deploys template `/etc/pam.d/su` (cookbook: `nil` = uses default redisio template; controls PAM su limits)
  - Deploys `cookbook_file '/etc/pam.d/sudo'` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `'sudo'`; mode `0644`)
- **Conditional branch** — `if ulimit.key?('users')` (default: `node['ulimit']['users']` is an empty Mash, so this loop does NOT execute unless users are defined):
  - Iterates over `node['ulimit']['users']` hash; for each user creates a `user_ulimit` custom resource
  - With default attributes, no users are defined, so this block is skipped
- Resources: template (1, Debian only), cookbook_file (1, Debian only), user_ulimit (0 by default)

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines the OS-default Redis service name:
  - **Debian/Ubuntu**: `redis-server`
  - **RHEL/Fedora**: `redis`
- Stops and disables that OS-default service: `service['redis-server']` (Debian) or `service['redis']` (RHEL) with actions `[:stop, :disable]`
- This prevents the OS-packaged Redis from conflicting with the source-compiled one
- Resources: service (1)

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Calls `include_recipe 'redisio::default'` (circular — already visited, no-op)
- Calls `include_recipe 'redisio::ulimit'` (circular — already visited, no-op)
- Resolves `redis_instances` from `node['redisio']['servers']` — set in `cache::default` to: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Uses custom resource `redisio_configure['redis-servers']`:
  - `version`: `nil` (not set; provider will detect from binary)
  - `default_settings`: full hash from `node['redisio']['default_settings']`
  - `servers`: the single-element array above
  - `base_piddir`: `/var/run/redis`
  - → Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - → Provider iterates over 1 server (port **6379**):
    - Creates user `redis` (system user, home `/var/lib/redis`, shell `/bin/false` on Debian)
    - Creates directory `/etc/redis` (owner: root, group: redis, mode `0775`, recursive)
    - Creates directory `/var/lib/redis` (owner: redis, group: redis, mode `0775`, recursive)
    - Creates directory `/var/run/redis/6379` (owner: redis, group: redis, mode `0755`, recursive)
    - Renders template `/etc/redis/6379.conf` from `redis.conf.erb` with all configuration variables (only if `/etc/redis/6379.conf.breadcrumb` does NOT exist)
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb` (prevents future overwrites)
    - **Systemd branch** (default on systemd hosts):
      - Creates file `/etc/tmpfiles.d/redis@6379.conf` with content `d /var/run/redis/6379 0755 redis redis`
      - Defines `execute['redis@6379 systemd reload']` (runs `systemctl daemon-reload`, triggered by template change)
      - Renders template `/lib/systemd/system/redis@6379.service` from `redis@.service.erb`:
        - `ExecStart`: `/usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no`
        - `User`: `redis`
        - `Group`: `redis`
        - `LimitNOFILE`: 10032 (maxclients 10000 + 32)
        - Notifies `systemctl daemon-reload` immediately on change
    - Sets up `user_ulimit['redis']` with filehandle_limit = 10032 (via ulimit provider)
- Iterates over 1 server (**6379**) to create service resources:
  - **Systemd branch**: `service['redis@6379']` (provider: `Chef::Provider::Service::Systemd`)
- Resources: redisio_configure (1), service (1)

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates over 1 server (**6379**):
  - Looks up the already-defined service resource `service['redis@6379']` (systemd)
  - Appends actions `:start` and `:enable` to that service resource
- This causes `redis@6379.service` to be started and enabled at boot
- Resources: (modifies existing service resource — no new resources created)

**10. cache::default — ruby_block['fix_redis_config']** (executes after redisio::enable):
- Reads `/etc/redis/6379.conf`
- Strips the following directives using `gsub!` regex replacement with empty string:
  - Lines matching `^replica-serve-stale-data.*$`
  - Lines matching `^replica-read-only.*$`
  - Lines matching `^repl-ping-replica-period.*$`
  - Lines matching `^client-output-buffer-limit.*$`
  - Lines matching `^replica-priority.*$`
- Writes the modified content back to `/etc/redis/6379.conf`
- **Note**: This is a workaround for an older Redis version (3.2.11) that does not support these newer directive names. The `replicaservestaledata` attribute was set to `nil` in the recipe to suppress template rendering of `replica-serve-stale-data`, but the other directives still render from defaults and must be stripped post-hoc.

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0` (artifact: `memcached-7992788f1a376defb902059063f5295e37d281cb`)
- `redisio` (artifact: `redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db`)

**System package dependencies**:
- `memcached` (installed via package manager)
- `tar` (prerequisite for Redis source build)
- `build-essential` / `gcc`, `make` (via `build_essential` resource for Redis source compilation)

**Service dependencies** (systemd services managed):
- `memcached.service` — started and enabled
- `redis@6379.service` — started and enabled (template-based systemd unit)
- `redis-server.service` (Debian) or `redis.service` (RHEL) — stopped and disabled (OS default)

## Credentials

**Detection Summary**: 1 credential detected in 1 file

**Source**:
- **Provider**: Hardcoded (plaintext in recipe file)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` — set inline as `'redis_secure_password_123'`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal in the recipe
- **Usage context**: Written into `/etc/redis/6379.conf` as the `requirepass` directive. All Redis clients must authenticate with this password using `AUTH redis_secure_password_123` before issuing commands. Also passed to the init.d script template (if used) as the `-a` flag for `redis-cli` shutdown commands.

> ⚠️ **Security Note for Solutions Architect**: This password is stored in plaintext in the Chef recipe. During Ansible migration, this credential MUST be moved to a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, or AAP Credential Store) and referenced via an Ansible vault variable or lookup plugin. Do NOT replicate the hardcoded value in Ansible playbooks or variable files committed to source control.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration file (rendered from template, then post-processed by ruby_block)
- `/etc/redis/6379.conf.breadcrumb` — Breadcrumb sentinel file (prevents config overwrite)
- `/lib/systemd/system/redis@6379.service` — Systemd unit file for Redis
- `/etc/tmpfiles.d/redis@6379.conf` — Tmpfiles entry for Redis PID directory
- `/var/lib/redis/` — Redis data directory (RDB dump files)
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by `cache::default`)
- `/usr/local/bin/redis-server` — Redis server binary (compiled from source)
- `/usr/local/bin/redis-cli` — Redis CLI binary (compiled from source)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached run directory

**Service endpoints to check**:
- `6379` — Redis TCP
- `11211` — Memcached TCP and UDP
- Unix sockets: None (not configured by default)
- Network interfaces: Both services bind to `0.0.0.0` (all interfaces) by default

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` — rendered **1 time** (for the single Redis instance on port 6379); then post-processed by `ruby_block['fix_redis_config']`
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — rendered **1 time** (systemd branch only)
- `/etc/pam.d/su` template — rendered **1 time** (Debian/Ubuntu only, via `redisio::ulimit`)
- `cookbook_file` `/etc/pam.d/sudo` — deployed **1 time** (Debian/Ubuntu only, via `redisio::ulimit`)

## Pre-flight Checks

```bash
# ============================================================
# REDIS SERVICE CHECKS (instance: 6379)
# ============================================================

# Service status
systemctl status redis@6379
systemctl is-enabled redis@6379  # should output: enabled
systemctl is-active redis@6379   # should output: active

# Process check
ps aux | grep redis-server | grep -v grep
# Expected: one redis-server process running /etc/redis/6379.conf

# Binary verification (source-compiled)
ls -lh /usr/local/bin/redis-server
ls -lh /usr/local/bin/redis-cli
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 sha=...

# Redis connectivity with authentication
/usr/local/bin/redis-cli -p 6379 AUTH redis_secure_password_123
# Expected: OK

/usr/local/bin/redis-cli -p 6379 -a redis_secure_password_123 PING
# Expected: PONG

/usr/local/bin/redis-cli -p 6379 -a redis_secure_password_123 INFO server | grep redis_version
# Expected: redis_version:3.2.11

/usr/local/bin/redis-cli -p 6379 -a redis_secure_password_123 INFO clients | grep connected_clients
# Expected: connected_clients:1 (or more)

# Verify unauthenticated access is rejected
/usr/local/bin/redis-cli -p 6379 PING
# Expected: NOAUTH Authentication required.

# Configuration file validation
ls -lh /etc/redis/6379.conf
ls -lh /etc/redis/6379.conf.breadcrumb  # must exist

# Verify the ruby_block hack removed deprecated directives
grep -c "^replica-serve-stale-data" /etc/redis/6379.conf
# Expected: 0 (line must NOT be present)

grep -c "^replica-read-only" /etc/redis/6379.conf
# Expected: 0 (line must NOT be present)

grep -c "^repl-ping-replica-period" /etc/redis/6379.conf
# Expected: 0 (line must NOT be present)

grep -c "^client-output-buffer-limit" /etc/redis/6379.conf
# Expected: 0 (line must NOT be present)

grep -c "^replica-priority" /etc/redis/6379.conf
# Expected: 0 (line must NOT be present)

# Verify key config values are present
grep "^requirepass" /etc/redis/6379.conf
# Expected: requirepass redis_secure_password_123

grep "^port" /etc/redis/6379.conf
# Expected: port 6379

grep "^loglevel" /etc/redis/6379.conf
# Expected: loglevel notice

grep "^maxclients" /etc/redis/6379.conf
# Expected: maxclients 10000

# Systemd unit file
cat /lib/systemd/system/redis@6379.service
grep "LimitNOFILE" /lib/systemd/system/redis@6379.service
# Expected: LimitNOFILE=10032

grep "ExecStart" /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no

# Tmpfiles entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Directory ownership and permissions
ls -lad /var/lib/redis
# Expected: drwxrwxr-x ... redis redis ...

ls -lad /var/run/redis/6379
# Expected: drwxr-xr-x ... redis redis ...

ls -lad /var/log/redis
# Expected: drwxr-xr-x ... redis redis ...

ls -lad /etc/redis
# Expected: drwxrwxr-x ... root redis ...

# Network listening
ss -tlnp | grep 6379
# Expected: LISTEN 0 ... 0.0.0.0:6379 ...

netstat -tulpn | grep 6379
# Expected: tcp 0 0 0.0.0.0:6379 0.0.0.0:* LISTEN ... redis-server

lsof -i :6379
# Expected: redis-ser ... TCP *:6379 (LISTEN)

# Redis logs (syslog-enabled by default)
journalctl -u redis@6379 --no-pager -n 50
# Expected: no ERROR or FATAL lines; "Server started" message present

# Redis persistence (RDB)
ls -lh /var/lib/redis/dump-6379.rdb 2>/dev/null || echo "No RDB file yet (normal on fresh install)"

# ============================================================
# MEMCACHED SERVICE CHECKS (instance: memcached, port 11211)
# ============================================================

# Service status
systemctl status memcached
systemctl is-enabled memcached  # should output: enabled
systemctl is-active memcached   # should output: active

# Process check
ps aux | grep memcached | grep -v grep
# Expected: one memcached process listening on 0.0.0.0:11211

# Memcached connectivity
echo "stats" | nc -q1 localhost 11211 | head -20
# Expected: STAT pid ... STAT version ... STAT uptime ...

echo "version" | nc -q1 localhost 11211
# Expected: VERSION x.x.x

# Verify Memcached is accepting connections on TCP 11211
ss -tlnp | grep 11211
# Expected: LISTEN 0 ... 0.0.0.0:11211 ...

netstat -tulpn | grep 11211
# Expected: tcp 0 0 0.0.0.0:11211 0.0.0.0:* LISTEN ... memcached
# Expected: udp 0 0 0.0.0.0:11211 0.0.0.0:* ... memcached

lsof -i :11211
# Expected: memcached ... TCP *:11211 (LISTEN)

# Memcached basic set/get test
echo -e "set testkey 0 60 5\r\nhello\r\n" | nc -q1 localhost 11211
# Expected: STORED

echo -e "get testkey\r\n" | nc -q1 localhost 11211
# Expected: VALUE testkey 0 5 \r\nhello\r\nEND

# Directory ownership
ls -lad /var/log/memcached
# Expected: drwxr-xr-x ... memcache memcache ... (or memcached on RHEL)

ls -lad /var/run/memcached
# Expected: drwxr-xr-x ... memcache memcache ...

# User/group existence
id memcache 2>/dev/null || id memcached 2>/dev/null
# Expected: uid=... gid=... groups=...

getent passwd memcache 2>/dev/null || getent passwd memcached 2>/dev/null
# Expected: memcache:x:...:...:Memcached:/nonexistent:/bin/false

# Memcached logs
journalctl -u memcached --no-pager -n 50
# Expected: no ERROR lines; "server listening" message present

# ============================================================
# COMBINED SYSTEM CHECKS
# ============================================================

# Verify OS-default Redis service is stopped and disabled (Debian/Ubuntu)
systemctl is-active redis-server 2>/dev/null && echo "WARNING: OS redis-server is still active!" || echo "OK: OS redis-server is not active"
systemctl is-enabled redis-server 2>/dev/null && echo "WARNING: OS redis-server is still enabled!" || echo "OK: OS redis-server is not enabled"

# Verify OS-default Redis service is stopped and disabled (RHEL/CentOS)
systemctl is-active redis 2>/dev/null && echo "WARNING: OS redis is still active!" || echo "OK: OS redis is not active"
systemctl is-enabled redis 2>/dev/null && echo "WARNING: OS redis is still enabled!" || echo "OK: OS redis is not enabled"

# PAM ulimit files (Debian/Ubuntu only)
ls -lh /etc/pam.d/su
ls -lh /etc/pam.d/sudo
# Expected: both files exist with mode 0644

# Overall resource usage
ps aux | grep -E 'redis|memcache' | grep -v grep
# Expected: redis-server and memcached processes visible

# File descriptor limits for Redis process
cat /proc/$(pgrep -f "redis-server")/limits | grep "open files"
# Expected: Max open files = 10032 (soft) / 10032 (hard)
```