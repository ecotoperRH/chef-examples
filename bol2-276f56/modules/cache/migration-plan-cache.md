---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two cache services: the Memcached instance `memcached` and the Redis instance `6379`. Memcached uses 64 MB of memory, TCP/UDP port `11211`, listen address `0.0.0.0`, and 1,024 maximum connections. Redis `3.2.11` is installed from source on Debian-family systems, listens on port `6379`, uses `/etc/redis/6379.conf`, and is managed as `redis@6379` under systemd or `redis6379` under other supported service managers. Redis authentication is currently hardcoded as `redis_secure_password_123` and must be moved to Ansible Vault or an external secrets provider.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Location/Path: Memcached configuration path is supplied by the `memcached` dependency cookbook
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: 64 MB memory, maximum 1,024 connections, maximum object size `1m`, user `service_user`, ulimit `1024`, default thread count, no experimental or additional CLI options
  - Actions: Start and enable

- **6379**: Redis cache service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID directory `/var/run/redis/6379`; logs `/var/log/redis`
  - Port/Socket: TCP port `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11` source installation, 16 databases, maximum 10,000 clients, log level `notice`, syslog enabled with facility `local0`, RDB persistence, password authentication, Redis user and group `redis`
  - Download URL: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
  - RDB file: `/var/lib/redis/dump-6379.rdb`
  - AOF file if enabled: `/var/lib/redis/appendonly-6379.aof`
  - Breadcrumb: `/etc/redis/6379.conf.breadcrumb`
  - Systemd service: `redis@6379`
  - Init.d/upstart service: `redis6379`
  - Actions: Start and enable
  - Post-configuration changes: Remove `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` directives

There is one configured Redis server, named `6379` because no explicit instance name is set. There are no Redis replicas, Sentinel instances, or additional Redis ports.

## File Structure

```text
Recipes:
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb

Providers:
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb

Templates:
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb

Attributes:
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb

Files:
No static cookbook_file payload is deployed on the Ubuntu/default path. The conditional resources cookbook_file[/etc/pam.d/sudo] and template[/etc/pam.d/su] have unset source cookbook defaults.
```

## Module Explanation

The cookbook performs operations in this order. Circular includes from `redisio::configure` back to `redisio::default` and `redisio::ulimit` are listed once and are not recursively reproduced.

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to the single Redis instance `6379` with port `6379`, password `redis_secure_password_123`, and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` with owner and group `redis`, mode `0755`, and recursive creation.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration and removes five replication/client-buffer directives from `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Preserves the `redis` group before creating Redis-owned paths.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures 64 MB memory, TCP/UDP port `11211`, listen address `0.0.0.0`, maximum 1,024 connections, object size `1m`, user `service_user`, ulimit `1024`, default threads, and empty experimental/additional options.
   - Starts and enables the Memcached service.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update`.
   - Includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]`.
   - Because `package_install` is `false` and `bypass_setup` is `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs package `tar` on Debian-family systems.
   - Iteration: `package[pkg]` runs **1 time** for `tar`.
   - The parent recipe also invokes the dependency cookbook’s build-essential resource for compiling Redis `3.2.11`.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]` again.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Creates `redisio_install[redis-installation]` using `providers/install.rb`.
   - Extracts the `tar.gz`, runs `make clean && make`, and runs `make install` when Redis `3.2.11` is not already installed.
   - Uses safe source installation with the provider’s default installation directory.
   - Includes `redisio::ulimit`.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Declares conditional `/etc/pam.d/su` and `/etc/pam.d/sudo` resources, but both source cookbook defaults are `nil`.
   - The user ulimit loop runs **0 times** because `node['ulimit']['users']` is empty.
   - The Redis provider calculates a descriptor limit of `10032` for user `redis` from `maxclients + 32`; the configured Redis ulimit is `0`.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the distribution service `redis-server` on Debian-family systems.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Uses `redisio_configure[redis-servers]` and `providers/configure.rb`.
   - Iterates **1 time** for Redis instance `6379`.
   - Creates the system user `redis` with home `/var/lib/redis`, shell `/bin/false` on Debian, system-user status enabled, and managed home.
   - Creates `/etc/redis` as `root:redis`, mode `0775`.
   - Creates `/var/lib/redis` as `redis:redis`, mode `0775`.
   - Creates `/var/run/redis/6379` as `redis:redis`, mode `0755`.
   - Renders `redis.conf.erb` once to `/etc/redis/6379.conf` as `redis:redis`, mode `0644`, unless the breadcrumb already exists.
   - Creates `/etc/redis/6379.conf.breadcrumb`.
   - Under systemd, renders `/lib/systemd/system/redis@6379.service` once, creates `/etc/tmpfiles.d/redis@6379.conf`, and reloads systemd when the unit changes.
   - Under init.d, renders `/etc/init.d/redis6379` once.
   - Under upstart, renders `/etc/init/redis6379.conf` once.
   - Under rcinit, renders `/usr/local/etc/rc.d/redis6379` once.
   - Creates one service resource: `redis@6379` under systemd or `redis6379` under init.d, upstart, and rcinit. The service initially has no start action.

9. **`fix_redis_config`** (`cookbooks/cache/recipes/default.rb`):
   - Runs after `/etc/redis/6379.conf` is deployed.
   - Removes lines matching `^replica-serve-stale-data.*$`, `^replica-read-only.*$`, `^repl-ping-replica-period.*$`, `^client-output-buffer-limit.*$`, and `^replica-priority.*$`.
   - The Ansible implementation should use a controlled `replace` task or template transformation before service startup.

10. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Iterates **1 time** for Redis instance `6379`.
    - Starts and enables `redis@6379` under systemd.
    - Starts and enables `redis6379` under init.d, upstart, or rcinit.

## Dependencies

**External cookbook dependencies**:

- `memcached`, version constraint `~> 6.0`
- `redisio`, without a version constraint
- Build-essential, SELinux, and ulimit functionality referenced by `redisio`

**System package dependencies**:

- `tar`
- Equivalent build-essential packages required to compile Redis `3.2.11`
- Memcached packages or installation artifacts managed by `memcached_instance[memcached]`
- No distribution Redis package in the default Debian source-install path

**Service dependencies**:

- Memcached service
- Managed Redis service `redis@6379` under systemd
- Managed Redis service `redis6379` under init.d, upstart, or rcinit
- Distribution service `redis-server`, which is stopped and disabled

## Credentials

**Detection Summary**: 1 credential detected across 1 file.

**Source**:

- **Provider**: Hardcoded in Chef recipe
- **URL**: None
- **Path**: None

### Redis authentication password

- **Variable**: `node['redisio']['servers'][0]['requirepass']`
- **Source file**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext value
- **Value**: `redis_secure_password_123`
- **Usage context**: Redis `requirepass` authentication for instance `6379`
- **Expected destination**: `/etc/redis/6379.conf`

The `redisio` provider supports Chef data bag retrieval through `data_bag_name`, `data_bag_item`, and `data_bag_key`, but all are `nil` and no data bag lookup is executed. No additional secrets, TLS keys, API tokens, database connection strings, Chef Vault, CyberArk, Conjur, or environment-variable lookups were detected.

The Ansible migration must store the password in Ansible Vault or an AAP/external secrets integration and must not place the plaintext value in role defaults or templates.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd
- `/lib/systemd/system/redis@6379.service` on systemd
- `/etc/init.d/redis6379` on init.d
- `/etc/init/redis6379.conf` on upstart
- `/usr/local/etc/rc.d/redis6379` on rcinit
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- Memcached configuration path supplied by the dependency cookbook
- Redis source installation path
- `/usr/local/bin/redis-server`

**Service endpoints to check**:

- Memcached TCP `0.0.0.0:11211`
- Memcached UDP `0.0.0.0:11211`
- Redis TCP `0.0.0.0:6379`, unless the rendered configuration changes the bind address
- No Unix sockets

**Templates rendered**:

- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb` to `/etc/redis/6379.conf`: **1 render**
- `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: **1 render when systemd is used**
- `redis.init.erb` to `/etc/init.d/redis6379`: **1 render when init.d is used**
- `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: **1 render when upstart is used**
- `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: **1 render when rcinit is used**
- `/etc/pam.d/su`: conditional; source cookbook unset by defaults
- `/etc/pam.d/sudo`: conditional; source cookbook unset by defaults

## Pre-flight checks

```bash
# Operating system and service manager
cat /etc/os-release
ps -p 1 -o comm=
```

### Memcached instance `memcached`

```bash
systemctl status memcached --no-pager || service memcached status
systemctl is-enabled memcached
ps aux | grep '[m]emcached'

ss -ltnp | grep ':11211'
nc -zv 127.0.0.1 11211

ss -lunp | grep ':11211'

echo stats | nc 127.0.0.1 11211 | grep -E 'maxbytes|maxconns'
```

Expected results:

- Memcached is active and enabled.
- TCP and UDP port `11211` are listening.
- Memcached reports approximately 64 MB maximum memory and 1,024 maximum connections.

### Redis instance `6379`

```bash
systemctl status redis@6379 --no-pager
systemctl is-enabled redis@6379
systemctl is-active redis@6379

ps aux | grep '[r]edis-server'
ss -ltnp | grep ':6379'
nc -zv 127.0.0.1 6379

ls -l /etc/redis/6379.conf
ls -l /etc/redis/6379.conf.breadcrumb
grep -E '^(port|requirepass|dir|pidfile|databases|maxclients)' /etc/redis/6379.conf

grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf
```

The final `grep` should return no matching directives.

```bash
# Distribution Redis must be stopped and disabled
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true

# Redis directories and ownership
ls -ld /var/lib/redis
ls -ld /var/run/redis/6379
ls -ld /var/log/redis

stat -c '%A %U:%G %n' \
  /etc/redis \
  /etc/redis/6379.conf \
  /etc/redis/6379.conf.breadcrumb

# Service logs and unit registration
journalctl -u redis@6379 --no-pager -n 100
systemctl cat redis@6379
systemctl show redis@6379 -p LoadState -p ActiveState -p SubState

# Verify the runtime PID directory and command line
test -d /var/run/redis/6379 && echo "PID directory exists"
ps -eo pid,args | grep '[r]edis-server'
```

Expected ownership:

- `/var/lib/redis`, `/var/run/redis/6379`, and Redis runtime files are owned by `redis:redis`.
- `/etc/redis` is owned by `root:redis`.
- `/etc/redis/6379.conf` is owned by `redis:redis` with mode `0644`.
- `/etc/redis/6379.conf.breadcrumb` exists.

### Redis authentication and runtime checks for instance `6379`

Use a protected environment variable or AAP credential; do not place the password directly in shell history.

```bash
export REDISCLI_AUTH='<retrieve-from-protected-secret-store>'

redis-cli -p 6379 PING
redis-cli -p 6379 INFO server | grep -E 'redis_version|tcp_port|process_id'
redis-cli -p 6379 INFO memory | grep -E 'used_memory|maxmemory'
redis-cli -p 6379 CONFIG GET maxclients
redis-cli -p 6379 CONFIG GET port

unset REDISCLI_AUTH
```

Expected results:

- `PING` returns `PONG`.
- Redis reports the intended source version.
- The configured port is `6379`.
- Redis accepts the protected password and rejects unauthenticated commands when authentication is enabled.