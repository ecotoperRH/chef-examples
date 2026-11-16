---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures one Memcached instance named `memcached` on TCP/UDP port `11211` and one Redis instance named `6379` on TCP port `6379`. Memcached is started and enabled through `memcached_instance[memcached]`. Redis uses source installation by default on Debian, is configured and authenticated with a password currently hardcoded in the wrapper recipe, and is started and enabled as `redis@6379` under systemd or `redis6379` under non-systemd init systems. After Redis configuration, a Ruby block removes selected replication-related directives from `/etc/redis/6379.conf`. Attribute values and custom-resource provider internals are implementation assumptions because the supplied structured analysis does not include the attribute contents or provider paths.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Location/Path: Service-managed configuration; provider path is not supplied
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: `64` MB memory, `1024` maximum connections, `1m` maximum object size, `1024` ulimit, `service_user` service user, default `threads`, experimental options, and extra CLI options from Memcached attributes
  - Actions: Start and enable

- **6379**: Redis cache instance
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID `/var/run/redis`; logs `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis version `3.2.11` under source-install defaults, user `redis`, group `redis`, `16` databases, `notice` log level, syslog enabled, maximum clients `10000`, and authentication enabled with `requirepass`
  - Service: `redis@6379` under systemd; `redis6379` under non-systemd init systems
  - Actions: Start and enable
  - Validation status: Values originate from the plan and supplied execution context but are not independently confirmed because the attribute file contents were not supplied

## File Structure

```text
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

Provider Ruby files are not explicitly listed in the supplied execution tree. The tree identifies these custom resources without provider paths:

- `memcached_instance[memcached]`
- `redisio_install[redis-installation]`
- `redisio_configure[redis-servers]`
- `user_ulimit[user]`

Template and static-file source paths are also not identified. Runtime targets include `/etc/pam.d/su`, `/etc/pam.d/sudo`, and the Redis configuration generated internally by `redisio_configure`.

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Defines one Redis server entry named **6379**, with port `6379`, password `redis_secure_password_123`, and `replicaservestaledata=nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]`.
   - Includes `redisio::enable`.
   - The Ruby block checks `/etc/redis/6379.conf` and removes complete lines matching `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Invokes `memcached_instance[memcached]`.
   - Configures `64` MB memory, TCP and UDP port `11211`, bind address `0.0.0.0`, `1024` maximum connections, `1m` maximum object size, `service_user`, attribute-derived thread and option values, and ulimit `1024`.
   - Starts and enables the `memcached` instance.
   - The provider implementation is not available in the supplied execution tree.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - With `package_install=false`, includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]`.
   - With `bypass_setup=false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Uses source/tarball installation and Redis version `3.2.11` under the supplied Debian defaults.
   - Selects `systemd` when detected; otherwise selects `initd`.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs `package[tar]` on Debian.
   - Participates in installation of the platform-equivalent compiler and build dependencies represented by `build_essential[install build deps]`.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses the package branch only when `package_install=true`; Debian uses `redis-server`, and RHEL/Fedora uses `redis`.
   - Under the supplied Debian defaults, includes `redisio::_install_prereqs`, invokes `build_essential[install build deps]`, and downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Invokes `redisio_install[redis-installation]` with version `3.2.11`, safe installation enabled, and no configured installation directory.
   - Includes `redisio::ulimit`.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian, renders `/etc/pam.d/su` through a `template` resource.
   - On Debian, deploys `/etc/pam.d/sudo` through a `cookbook_file`, using default source filename `sudo` and mode `0644`.
   - Evaluates the `user_ulimit[user]` loop; it executes zero times because the supplied default user collection is empty.
   - Provider and source-template paths are not available in the supplied execution tree.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Selects `redis-server` on Debian and `redis` on RHEL/Fedora.
   - Stops and disables the selected operating-system Redis service before enabling instance **6379**.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - References `redisio::default` and `redisio::ulimit`; already-visited circular includes must not become recursive Ansible calls.
   - Invokes `redisio_configure[redis-servers]` once for the single server entry **6379**.
   - Generates the configuration for port `6379` using base PID directory `/var/run/redis`.
   - Applies user `redis`, group `redis`, mode `0644`, home/data directory `/var/lib/redis`, shell `/bin/false` on Debian, `16` databases, `notice` log level, syslog `yes`, maximum clients `10000`, `requirepass redis_secure_password_123`, and unset Unix socket and TLS settings.
   - Creates one service resource:
     - `service[redis@6379]` with systemd
     - `service[redis6379]` with initd, Upstart, or FreeBSD rcinit
   - The custom-resource provider and internal template path are not available in the supplied execution tree.

9. **`ruby_block[fix_redis_config]`** (`cookbooks/cache/recipes/default.rb`):
   - Runs after Redis configuration.
   - Modifies `/etc/redis/6379.conf` only when the file exists.
   - Removes the complete directives `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
   - Must be implemented as an idempotent Ansible cleanup task that tolerates a missing file.

10. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Expands once for the configured Redis instance **6379**.
    - Starts and enables `redis@6379` under systemd.
    - Starts and enables `redis6379` under non-systemd job control.
    - Runs after Redis configuration and `fix_redis_config`.

## Dependencies

**External cookbook dependencies**: `memcached`, `redisio`, `build_essential`, and `user_ulimit` custom resources.

**System package dependencies**: `tar`; platform-specific compiler and build packages represented by `build_essential`; `redis-server` on Debian when package installation is enabled; `redis` on RHEL/Fedora when package installation is enabled; and `apt_update` on Debian-family systems.

**Service dependencies**: Memcached on TCP/UDP port `11211`; Redis instance **6379** on TCP port `6379`; and the operating-system Redis service, which must be stopped and disabled (`redis-server` on Debian or `redis` on RHEL/Fedora).

## Credentials

**Detection Summary**: 1 credential identified by the migration plan in 1 file; independent credential-analysis output was not supplied.

**Source**:
  - **Provider**: Hardcoded in the wrapper recipe
  - **URL**: None
  - **Path**: None

### Redis authentication password

- **Variable**: `node.default['redisio']['servers'][0]['requirepass']`
- **Value**: `redis_secure_password_123` in the source plan; migrate this value to Ansible Vault
- **Source file**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef attribute value
- **Usage context**: Configures the `requirepass` authentication setting for Redis instance **6379**
- **Migration storage**: Ansible Vault variable such as `redis_requirepass`; do not expose it in task output, command arguments, shell history, or committed playbooks

Optional sensitive Redis attributes include `masterauth`, `tlskeyfilepass`, `tlsclientkeyfilepass`, `data_bag_name`, `data_bag_item`, and `data_bag_key`. No data bag, encrypted data bag, Chef Vault, CyberArk, Conjur, environment-variable secret, database connection string, or certificate/key deployment is explicitly used by the executed recipes.

## Checks for the Migration

**Files to verify**:

- `cookbooks/cache/recipes/default.rb`
- `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`
- `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`
- `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb`
- `/etc/redis/6379.conf`
- `/var/lib/redis`
- `/var/run/redis`
- `/var/log/redis`
- `/etc/pam.d/su`
- `/etc/pam.d/sudo`

**Service endpoints to check**: Memcached TCP `0.0.0.0:11211`; Memcached UDP `0.0.0.0:11211`; Redis instance **6379** TCP `*:6379`; no Redis Unix socket.

**Templates rendered**:

- Redis configuration for instance **6379**: 1 render
- `/etc/pam.d/su`: 1 conditional render on Debian-family systems
- `/etc/pam.d/sudo`: 1 conditional static-file deployment on Debian-family systems

## Pre-flight checks

```bash
# Verify Memcached instance memcached
systemctl status memcached --no-pager
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
printf "version\r\n" | nc -w 2 127.0.0.1 11211

# Verify Redis instance 6379
systemctl status redis@6379 --no-pager
ss -ltnp | grep ':6379'

# Use an injected protected variable; do not replace it with a literal password.
: "${REDISCLI_AUTH:?Set REDISCLI_AUTH from Ansible Vault without printing it}"
REDISCLI_AUTH="$REDISCLI_AUTH" redis-cli -h 127.0.0.1 -p 6379 PING
REDISCLI_AUTH="$REDISCLI_AUTH" redis-cli -h 127.0.0.1 -p 6379 INFO server
REDISCLI_AUTH="$REDISCLI_AUTH" redis-cli -h 127.0.0.1 -p 6379 SET migration_check success
REDISCLI_AUTH="$REDISCLI_AUTH" redis-cli -h 127.0.0.1 -p 6379 GET migration_check
REDISCLI_AUTH="$REDISCLI_AUTH" redis-cli -h 127.0.0.1 -p 6379 DEL migration_check

# Expected Redis results:
# PING: PONG
# SET: OK
# GET: success
# DEL: 1

# Verify Redis configuration and directories
test -f /etc/redis/6379.conf
grep -E '^[[:space:]]*requirepass[[:space:]]+' /etc/redis/6379.conf
test ! -e /etc/redis/6379.conf || ! grep -E '^[[:space:]]*(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
ls -ld /var/lib/redis
ls -ld /var/run/redis
ls -ld /var/log/redis

# Verify the disabled operating-system Redis service
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true

# Verify service logs
journalctl -u redis@6379 --no-pager -n 100
journalctl -u memcached --no-pager -n 100

# Verify Debian-family PAM files when applicable
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo
```