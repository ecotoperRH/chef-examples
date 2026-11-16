---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` with 64 MB of memory. Redis `3.2.11` is built from the Redis tarball, configured at `/etc/redis/6379.conf`, stores data in `/var/lib/redis`, logs under `/var/log/redis`, and runs as `redis@6379` on systemd. The Redis password is currently hardcoded and must be migrated to an approved secret store. Preserve the execution order: Memcached setup, Redis log directory creation, Redis prerequisites and installation, Redis configuration, Redis cleanup, and service enablement.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Location/Path: Service configuration managed by the Memcached dependency
  - Port/Socket: TCP `11211`, UDP `11211`, listen address `0.0.0.0`
  - Key Config: 64 MB memory, maximum 1024 connections, maximum object size `1m`, default thread value, ulimit `1024`, empty experimental and extra-option lists
  - Service Action: Start and enable
  - Service User: Memcached cookbook `service_user` value

- **6379**: Redis cache service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; logs `/var/log/redis`; PID base `/var/run/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11`, user `redis`, group `redis`, 16 databases, log level `notice`, syslog enabled, maximum clients `10000`, AOF `appendfsync everysec`, default RDB persistence, and `replicaservestaledata` explicitly set to `nil`
  - Installation: Source tarball from `http://download.redis.io/releases/redis-3.2.11.tar.gz`
  - Service Name: `redis@6379` on systemd; `redis6379` on init.d, upstart, or rcinit
  - Service Action: Start and enable
  - Authentication: Redis `requirepass` currently set to `redis_secure_password_123`; migrate this value to Ansible Vault, AAP credential injection, or another approved secret store

## File Structure

```text
**Recipes:**
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb

**Providers:**
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb

**Templates:**
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.upstart.conf.erb

**Attributes:**
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb

**Files:**
No deployed static file under `files/default/*` or `files/*` is present in the supplied execution-tree file set. The `ulimit` recipe references a `cookbook_file` for `/etc/pam.d/sudo`, but the source static file is not included. Deploy it only when the referenced platform-specific source is available.
```

## Module Explanation

The cookbook performs operations in this order. Circular recipe inclusions are represented once and must not create recursive Ansible execution.

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Assigns the Redis server collection one item, `6379`, with port `6379`, password `redis_secure_password_123`, and `replicaservestaledata: nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]`.
   - Includes `redisio::enable`.
   - The cleanup block removes lines matching `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from `/etc/redis/6379.conf`.
   - The cleanup occurs after Redis configuration and before service enablement. No unverified restart notification is added.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Configures `memcached_instance[memcached]`.
   - Installs the platform-appropriate Memcached package.
   - Configures 64 MB memory, TCP and UDP port `11211`, listen address `0.0.0.0`, maximum 1024 connections, maximum object size `1m`, default thread value, ulimit `1024`, and empty experimental and extra CLI options.
   - Starts and enables the Memcached service.
   - No Memcached provider file is present in the supplied execution tree; use dependency-equivalent Ansible installation and configuration tasks without inventing a provider path.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `redisio.package_install` defaults to `false` outside FreeBSD, includes `redisio::_install_prereqs`.
   - Runs `build_essential[install build deps]`.
   - Includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Does not implement circular re-entry from `redisio::configure` as infinite recursion.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Expands one package iteration: `tar`.
   - Installs the `tar` package on Debian and RHEL/Fedora.
   - Installs the compiler and build dependencies represented by `build_essential[install build deps]`.
   - Uses no package iterations on platforms where the collection is empty.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Includes `redisio::_install_prereqs`.
   - Runs the build dependency installation.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Executes `redisio_install[redis-installation]` using `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Builds and installs Redis version `3.2.11` with `safe_install: true`.
   - Includes `redisio::ulimit`.
   - Preserves safe installation behavior by avoiding replacement of a working Redis binary until the new build succeeds.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian, conditionally renders `/etc/pam.d/su`.
   - On Debian, conditionally deploys `/etc/pam.d/sudo` from the referenced cookbook source with mode `0644`.
   - Does not execute any `user_ulimit` iterations because `node['ulimit']['users']` is empty.
   - Does not invent user-specific ulimit entries.
   - Deploys the `/etc/pam.d/sudo` source only when the platform-specific source content is available.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - On Debian, stops and disables `redis-server`.
   - On RHEL/Fedora, stops and disables `redis`.
   - Does not manage an OS-default Redis service on other platforms.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - References already-visited `redisio::default` and `redisio::ulimit` without recursively executing them.
   - Runs `redisio_configure[redis-servers]` using `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Configures one Redis server iteration: `6379`.
   - Renders the effective Redis configuration to `/etc/redis/6379.conf`.
   - Uses Redis version `3.2.11`, the default Redis settings, the server collection containing `6379`, and base PID directory `/var/run/redis`.
   - On systemd, defines service `redis@6379`; on init.d, upstart, or rcinit, defines service `redis6379`.
   - Sets the resolved one-item server collection as the Redis server configuration.

9. **`cache::default` Redis cleanup block** (`cookbooks/cache/recipes/default.rb`):
   - Runs after `redisio::configure`.
   - Removes the five unwanted directive classes from `/etc/redis/6379.conf`.
   - Does not add an unverified service restart.

10. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Expands one Redis server iteration: `6379`.
    - On systemd, starts and enables `redis@6379`.
    - On init.d, upstart, or rcinit, starts and enables `redis6379`.
    - The systemd Ansible equivalent is `name: redis@6379`, `enabled: true`, `state: started`.

## Dependencies

**External cookbook dependencies**: `memcached`, `redisio`; `selinux` files appear in the directory listing but are not part of the execution tree and are excluded. No additional metadata dependencies were confirmed.

**System package dependencies**: `tar`; compiler and build dependencies represented by `build_essential`; platform-managed Memcached package dependencies. Redis is built from source version `3.2.11` rather than installed through the Redis OS package path.

**Service dependencies**: Memcached service; OS-default `redis-server` on Debian or `redis` on RHEL/Fedora, stopped and disabled; custom Redis service `redis@6379` on systemd or `redis6379` on init.d, upstart, and rcinit.

## Credentials

**Detection Summary**: 1 credential detected in 1 file.

**Source**:
  - **Provider**: Hardcoded in Chef recipe
  - **URL**: None
  - **Path**: None

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Value currently assigned**: `redis_secure_password_123`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef node attribute
- **Usage context**: Redis `requirepass` authentication for instance `6379`
- **Migration requirement**: Store the password in Ansible Vault, AAP credential injection, or another approved secret store. Do not commit the literal password to the Ansible role or inventory.

Optional attributes such as `masterauth`, TLS key paths, TLS certificate paths, and data-bag fields are unset and do not represent active credentials. No data bag, Chef Vault, Conjur, CyberArk, or environment-variable secret references were detected.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/var/log/redis/`
- `/var/lib/redis/`
- `/var/run/redis/`
- `/etc/pam.d/su` when the Debian ulimit branch is active
- `/etc/pam.d/sudo` when the Debian ulimit branch and source file are available
- Redis installation artifacts and the installed Redis binary
- Memcached configuration and service definition

**Service endpoints to check**:

- Memcached instance `memcached`: TCP `0.0.0.0:11211`
- Memcached instance `memcached`: UDP `0.0.0.0:11211`
- Redis instance `6379`: TCP port `6379`
- Redis instance `6379`: no Unix socket

**Templates rendered**:

- Effective Redis server configuration source `redis.conf.erb` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}`: destination `/etc/redis/6379.conf`, render count `1`
- `redis@.service.erb`: systemd Redis instance unit location determined by the provider, render count conditional on `job_control == 'systemd'`
- `redis.init.erb`: rendered only for the init.d branch
- `redis.upstart.conf.erb`: rendered only for the upstart branch
- `redis.rcinit.erb`: rendered only for the FreeBSD rcinit branch
- Sentinel templates: render count `0`; Sentinel is not included in the execution tree

## Pre-flight checks

```bash
# Verify the Memcached instance named memcached
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached

# Verify Memcached TCP and UDP listeners for instance memcached
ss -tlnp | grep ':11211'
ss -ulnp | grep ':11211'

# Basic Memcached protocol check
printf "version\r\nquit\r\n" | nc -w 2 127.0.0.1 11211
# Expected output includes: VERSION

# Verify the Redis instance named 6379 on systemd
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Verify the Redis process and port
ps aux | grep '[r]edis-server'
ss -tlnp | grep ':6379'

# Supply REDIS_PASSWORD from the approved secret store.
export REDIS_PASSWORD='RETRIEVE_FROM_APPROVED_SECRET_STORE'

# Verify Redis authentication and version
redis-cli -p 6379 -a "$REDIS_PASSWORD" PING
# Expected output: PONG

redis-cli -p 6379 -a "$REDIS_PASSWORD" INFO server | grep -E 'redis_version|tcp_port'
# Expected:
# redis_version:3.2.11
# tcp_port:6379

# Verify Redis configuration and cleanup
test -f /etc/redis/6379.conf
grep -E '^(port|requirepass|dir|loglevel|databases|maxclients)' /etc/redis/6379.conf

grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf
# Expected: no matching lines

# Verify Redis data, runtime, and log paths for instance 6379
ls -ld /var/lib/redis
ls -ld /var/run/redis
ls -ld /var/log/redis
df -h /var/lib/redis
journalctl -u redis@6379 --no-pager -n 50

# Functional Redis read/write check for instance 6379
redis-cli -p 6379 -a "$REDIS_PASSWORD" SET migration_check ok
redis-cli -p 6379 -a "$REDIS_PASSWORD" GET migration_check
redis-cli -p 6379 -a "$REDIS_PASSWORD" DEL migration_check
# Expected GET output: ok

# Verify the disabled OS-default Redis service on Debian
systemctl is-enabled redis-server
systemctl is-active redis-server
# Expected: disabled and stopped

# Verify the disabled OS-default Redis service on RHEL/Fedora
systemctl is-enabled redis
systemctl is-active redis
# Expected: disabled and stopped

# Verify the Redis installation
command -v redis-server
redis-server --version
# Expected version: 3.2.11

# Verify Debian PAM and ulimit files when the Debian branch is active
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo
stat -c '%a %n' /etc/pam.d/sudo
# Expected mode: 0644

# No user_ulimit instances are expected because node['ulimit']['users'] is empty.
```