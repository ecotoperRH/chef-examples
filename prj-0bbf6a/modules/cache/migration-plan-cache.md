---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` with 64 MB of memory, `0.0.0.0` binding, and 1,024 maximum connections. Redis `3.2.11` is compiled from source on Debian/Ubuntu because `redisio.package_install` defaults to `false`; it listens on port `6379`, requires the configured password, stores data under `/var/lib/redis`, and is managed as `redis@6379` on systemd hosts.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **`memcached`**: Memcached cache service
  - Resource: `memcached_instance[memcached]`
  - Memory: `64 MB`
  - TCP port: `11211`
  - UDP port: `11211`
  - Listen address: `0.0.0.0`
  - Maximum connections: `1024`
  - Maximum object size: `1m`
  - Threads: `node['memcached']['threads']` passed to the custom resource
  - User: `service_user`
  - Ulimit: `1024`
  - Experimental options: `[]`
  - Extra CLI options: `[]`
  - Actions: start and enable the Memcached service

- **`6379`**: Redis server instance
  - Port: `6379`
  - Authentication: `requirepass = redis_secure_password_123`
  - Data directory: `/var/lib/redis`
  - Configuration directory: `/etc/redis`
  - PID directory: `/var/run/redis/6379`
  - Redis user/group: `redis` / `redis`
  - Redis home: `/var/lib/redis`
  - Redis shell: `/bin/false` on Debian-family systems
  - Configuration file: `/etc/redis/6379.conf`
  - Configuration breadcrumb: `/etc/redis/6379.conf.breadcrumb`
  - Systemd service: `redis@6379`
  - Package installation: disabled by default
  - Source version: `3.2.11`
  - Source URL: `http://download.redis.io/releases/redis-3.2.11.tar.gz`
  - Log directory: `/var/log/redis`
  - Default databases: `16`
  - Maximum clients: `10000`
  - Persistence: Redis RDB defaults retained unless overridden
  - Replication: no replica configured; selected replica-related directives are removed by the post-configuration cleanup

**Loop expansions**:

- Redis configuration loop: one iteration for `6379`
- Redis service-resource loop: one iteration for `6379`
- Redis enable loop: one iteration for `6379`
- `ulimit['users']` loop: zero iterations because the default value is an empty `Mash`

## File Structure

The following files are relevant to the executed migration flow. Paths are relative to the cookbook root or the supplied migration-dependencies root.

**Recipes:**
```text
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
```

**Templates:**

The execution tree does not list template files as standalone execution items. The Redis configure provider references templates conditionally, as described in the module explanation below.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

**Files:**

No static file is directly deployed by the executed tree. The `cookbook_file` resource in `redisio::ulimit` is conditional on Debian-family execution and requires a configured `ulimit_overriding_sudo_file_cookbook`; no configured user-specific ulimit entries are present by default.

## Module Explanation

The cookbook performs operations in this order.

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Assigns one Redis server item named `6379` with port `6379`, password `redis_secure_password_123`, and `replicaservestaledata: nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Executes `ruby_block[fix_redis_config]`.
   - Includes `redisio::enable`.
   - Directly declares one `directory`, one `ruby_block`, and three `include_recipe` resources.
   - No separate `group[redis]` resource is present in the analyzed execution tree.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Applies the Memcached instance settings.
   - Starts and enables the Memcached service.
   - Installs and renders the Memcached service configuration internally through the custom resource.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `node['redisio']['package_install']` is `false`, includes `redisio::_install_prereqs`.
   - Runs `build_essential[install build deps]`.
   - Because `node['redisio']['bypass_setup']` is `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Effective Debian/Ubuntu order:
     1. `apt_update`
     2. `redisio::_install_prereqs`
     3. `build_essential[install build deps]`
     4. `redisio::install`
     5. `redisio::disable_os_default`
     6. `redisio::configure`

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs package `tar`.
   - The parent recipe installs the platform build-essential toolchain.
   - The configured package collection contains one item: `tar`.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses source installation because `redisio.package_install = false`.
   - Uses Redis version `3.2.11`, mirror `http://download.redis.io/releases/`, base name `redis-`, artifact type `tar.gz`, and `safe_install = true`.
   - Re-includes `redisio::_install_prereqs`.
   - Runs `build_essential[install build deps]`.
   - Executes `redisio_install[redis-installation]` using `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Extracts the source archive.
   - Runs `make clean && make`.
   - Runs `make install` using the default prefix because `install_dir` is `nil`.
   - Includes `redisio::ulimit`.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `/etc/pam.d/su`.
   - On Debian-family systems, conditionally deploys `/etc/pam.d/sudo`.
   - Creates no user-specific `user_ulimit` resources from the recipe loop because `ulimit['users'] = {}`.
   - The configure provider contains Redis-specific file-descriptor limit logic for user `redis`; provider-level resource creation is separate from the empty recipe loop and should be verified against the provider implementation during migration.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - On Debian-family systems, stops and disables `service[redis-server]`.
   - Prevents the distribution-provided Redis service from competing with `redis@6379`.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Resolves exactly one Redis server: `6379`.
   - Includes the already visited `redisio::default` and `redisio::ulimit` recipes.
   - Invokes `redisio_configure[redis-servers]`.
   - Uses `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Configures the `redis` service account with home `/var/lib/redis` and shell `/bin/false`.
   - Creates `/etc/redis`, `/var/lib/redis`, and `/var/run/redis/6379` with the configured ownership and permissions.
   - Applies SELinux contexts when SELinux is enabled.
   - Renders `redis.conf.erb` to `/etc/redis/6379.conf`.
   - Creates `/etc/redis/6379.conf.breadcrumb` when breadcrumb creation is enabled.
   - Does not overwrite `/etc/redis/6379.conf` when the breadcrumb exists.
   - On systemd hosts, creates `/etc/tmpfiles.d/redis@6379.conf` and `/lib/systemd/system/redis@6379.service`.
   - Uses `redis@.service.erb` for the systemd unit and runs `systemctl daemon-reload` when the unit changes.
   - On alternative init systems, conditionally renders:
     - `redis.init.erb` to `/etc/init.d/redis6379`
     - `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`
     - `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`

9. **Redis service-resource loop**:
   - Runs one iteration for `6379`.
   - On systemd, creates `service[redis@6379]`.
   - Supports start, stop, restart, and status operations.

10. **`ruby_block[fix_redis_config]`** (`cookbooks/cache/recipes/default.rb`):
    - Runs after Redis configuration.
    - Updates `/etc/redis/6379.conf` when the file exists.
    - Removes complete lines beginning with:
      - `replica-serve-stale-data`
      - `replica-read-only`
      - `repl-ping-replica-period`
      - `client-output-buffer-limit`
      - `replica-priority`

11. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Runs one iteration for `6379`.
    - Resolves `service[redis@6379]` on systemd.
    - Adds `start` and `enable` actions.
    - Final expected state: `redis@6379.service` is enabled and started.

## Dependencies

**External cookbook dependencies**:

- `memcached`, version `~> 6.0`
- `redisio`
- Build-essential, ulimit, and SELinux functionality referenced by Redis resources and providers

**System package dependencies**:

- `tar`
- Platform build-essential toolchain for Redis source compilation
- Memcached package dependencies installed by `memcached_instance[memcached]`

**Service dependencies**:

- `memcached`: started and enabled
- `redis-server`: stopped and disabled as the operating-system default service
- `redis@6379`: started and enabled as the managed Redis instance

## Credentials

**Detection Summary**: 1 credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded in a Chef recipe
  - **URL**: None
  - **Path**: None

### Redis authentication password

- **Variable**: `node['redisio']['servers'][0]['requirepass']`
- **Source file**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext Chef attribute value
- **Current value**: `redis_secure_password_123`
- **Usage context**: Redis `requirepass` authentication in `/etc/redis/6379.conf`
- **Additional behavior**: The Redis provider supports loading `requirepass` and `masterauth` from a Chef data bag when `data_bag_name`, `data_bag_item`, and `data_bag_key` are configured. Those attributes are `nil` by default and are not active in this cookbook.

No data bag, encrypted data bag, Chef Vault, CyberArk, Conjur, environment-variable secret, API key, TLS key, TLS certificate, or database connection credential is configured in the executed flow. Store the Redis password in Ansible Vault or an external secret manager.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/tmpfiles.d/redis@6379.conf`
- `/lib/systemd/system/redis@6379.service`
- `/var/lib/redis/`
- `/var/run/redis/6379/`
- `/var/log/redis/`
- `/etc/pam.d/su`
- `/etc/pam.d/sudo`
- `/usr/local/bin/redis-server`
- `/usr/local/bin/redis-cli`

**Service endpoints to check**:

- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis TCP: `0.0.0.0:6379` or the configured Redis listen address
- Redis Unix socket: none configured by default

**Templates rendered**:

- Memcached configuration and service files: rendered internally by `memcached_instance[memcached]`; standalone template paths are not exposed
- `redis.conf.erb` → `/etc/redis/6379.conf`: rendered once
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: rendered once on systemd hosts
- Systemd tmpfiles content → `/etc/tmpfiles.d/redis@6379.conf`: created once
- Alternative templates are conditional and are not rendered on systemd hosts:
  - `redis.init.erb` → `/etc/init.d/redis6379`
  - `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`
  - `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`

## Pre-flight checks

```bash
# Redis instance 6379: service state
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Default operating-system Redis service
systemctl is-enabled redis-server || true
systemctl is-active redis-server || true

# Memcached instance memcached: service state
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached

# Redis 6379: source-installed binaries
/usr/local/bin/redis-server --version
/usr/local/bin/redis-cli --version

# Redis 6379: configuration and breadcrumb
test -f /etc/redis/6379.conf
test -f /etc/redis/6379.conf.breadcrumb
grep -E '^(port|requirepass|dir|pidfile|maxclients)' /etc/redis/6379.conf

# Redis 6379: post-configuration cleanup
! grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf

# Redis 6379: authenticated connectivity
redis-cli -p 6379 -a '<REDIS_PASSWORD_FROM_VAULT>' PING
redis-cli -p 6379 -a '<REDIS_PASSWORD_FROM_VAULT>' INFO server
redis-cli -p 6379 -a '<REDIS_PASSWORD_FROM_VAULT>' DBSIZE

# Redis 6379: runtime directories
stat -c '%U:%G %a %n' /var/lib/redis
stat -c '%U:%G %a %n' /var/run/redis/6379
ls -lah /var/lib/redis
ls -lah /var/run/redis/6379

# Redis 6379: listener
ss -tlnp | grep ':6379'
lsof -iTCP:6379 -sTCP:LISTEN

# Redis 6379: systemd unit and limits
systemctl cat redis@6379
systemctl show redis@6379 --property=ExecStart,User,Group,LimitNOFILE

# Memcached instance memcached: TCP connectivity
printf 'version\r\n' | nc -w 2 127.0.0.1 11211

# Memcached instance memcached: statistics
printf 'stats\r\nquit\r\n' | nc -w 2 127.0.0.1 11211

# Memcached instance memcached: TCP and UDP listeners
ss -tlnp | grep ':11211'
ss -ulnp | grep ':11211'
lsof -iTCP:11211
lsof -iUDP:11211

# Redis log directory
stat -c '%U:%G %a %n' /var/log/redis
ls -lah /var/log/redis

# Service logs
journalctl -u redis@6379 --no-pager -n 100
journalctl -u memcached --no-pager -n 100
```

Expected results:

- `redis@6379` is active and enabled.
- `redis-server` is inactive and disabled.
- `memcached` is active and enabled.
- Redis responds with `PONG` when authenticated.
- Redis listens on TCP port `6379`.
- Memcached accepts the `version` command on TCP port `11211`.
- Memcached has TCP and UDP listeners on port `11211`.
- Redis configuration does not contain the five directives removed by `fix_redis_config`.