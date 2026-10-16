---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache service instances: Memcached instance **memcached** and Redis instance **6379**. Memcached uses its dependency cookbook defaults: 64 MB memory, TCP/UDP port 11211, and binding to `0.0.0.0`. Redis 3.2.11 is built from source by default on Debian and RHEL-family systems, listens on TCP port 6379, uses the systemd service `redis@6379` when systemd is present, stores its configuration at `/etc/redis/6379.conf`, and requires a hardcoded Redis password that must be migrated to an approved secret store.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached service instance created by `memcached_instance['memcached']`.
  - Location/Path: `/var/log/memcached`, `/var/run/memcached`
  - Port/Socket: TCP `11211` and UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory limit `64 MB`; maximum connections `1024`; maximum object size `1m`; file-descriptor ulimit `1024`; package version is unpinned (`nil`).

- **6379**: Sole Redis server entry in `node['redisio']['servers']`.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID directory `/var/run/redis/6379`; log directory `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11` is built from source by default; `requirepass` is configured; RDB snapshots are enabled at `900 1`, `300 10`, and `60 10000`; databases `16`; maximum clients `10000`; TCP backlog `511`; syslog enabled with facility `local0`; no explicit `bind` directive; no TLS port or certificate paths.
  - Service Name: `redis@6379` on systemd; `redis6379` on initd, upstart, or rcinit.
  - Post-configuration cleanup: The wrapper removes these Redis 3.2-era configuration directives from `/etc/redis/6379.conf`:
    - `slave-serve-stale-data`
    - `slave-read-only`
    - `repl-ping-slave-period`
    - `client-output-buffer-limit`
    - `slave-priority`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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

Attributes:
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Defines the sole Redis instance, **6379**, in `node['redisio']['servers']` with port `6379`, `requirepass`, and `replicaservestaledata` set to `null`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block['fix_redis_config']` after Redis configuration:
     - Reads `/etc/redis/6379.conf` only when it exists.
     - Removes the `slave-serve-stale-data`, `slave-read-only`, `repl-ping-slave-period`, `client-output-buffer-limit`, and `slave-priority` lines.
     - Writes the updated content to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `include_recipe` (3), `directory` (1), `ruby_block` (1).

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance['memcached']`.
   - Installs, starts, and enables the **memcached** service instance.
   - Configures **memcached** with memory `64 MB`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, and ulimit `1024`.
   - The custom-resource provider was not included in the supplied file structure; validate its exact package, service, and configuration-file implementation before reproducing it.
   - Resources: `memcached_instance` (1 custom resource).

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update['apt_update']`.
   - Because `node['redisio']['package_install']` is `false` by default on Debian, RHEL, and Fedora:
     - Includes `redisio::_install_prereqs`.
     - Uses `build_essential['install build deps']`.
   - Because `node['redisio']['bypass_setup']` is `false`:
     - Includes `redisio::install`.
     - Includes `redisio::disable_os_default`.
     - Includes `redisio::configure`.
   - Resources: `apt_update` (1), `build_essential` (1 custom resource), `include_recipe` (4).
   - Downstream recipes re-include `_install_prereqs`, `redisio::default`, and `redisio::ulimit`; Chef treats already visited recipes as circular re-inclusions.

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs the Redis source-install prerequisite package `tar`.
   - Iterations: runs 1 time for `tar`.
   - Resources: `package` (1).

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Re-includes `redisio::_install_prereqs`; it has already been visited.
   - Uses `build_essential['install build deps']`.
   - Uses `redisio_install['redis-installation']`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Unpacks Redis, runs `make clean && make`, and runs `make install`.
   - Includes `redisio::ulimit`.
   - If `package_install` is set to `true`, installs `redis-server` on Debian or `redis` on RHEL/Fedora instead of building from source.
   - Resources: `build_essential` (1 custom resource), `redisio_install` (1 custom resource), `include_recipe` (2).

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian, renders a template to `/etc/pam.d/su`.
   - On Debian, deploys cookbook file `sudo` to `/etc/pam.d/sudo` with mode `0644`.
   - `node['ulimit']['users']` defaults to an empty hash.
   - Iterations: no `user_ulimit` resources are created.
   - Resources on Debian: `template` (1), `cookbook_file` (1), `user_ulimit` (0).

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the operating-system Redis service to avoid conflict with Redis instance **6379**.
   - Stops and disables `redis-server` on Debian.
   - Stops and disables `redis` on RHEL and Fedora.
   - Resources: `service` (1).

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Re-includes `redisio::default` and `redisio::ulimit`; both are already visited.
   - Uses `redisio_configure['redis-servers']`.
   - Iterations: runs 1 time for Redis instance **6379**.
   - For Redis instance **6379**:
     - Creates and manages the `redis` system user.
     - Creates `/etc/redis`, `/var/lib/redis`, and `/var/run/redis/6379`.
     - Renders `redis.conf.erb` to `/etc/redis/6379.conf`.
     - Creates `/etc/redis/6379.conf.breadcrumb` if absent.
     - Creates the init-system service definition:
       - systemd: `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`, plus `/etc/tmpfiles.d/redis@6379.conf`, followed by `systemctl daemon-reload`
       - initd: `redis.init.erb` to `/etc/init.d/redis6379`
       - upstart: `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`
       - rcinit: `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`
     - Creates `service['redis@6379']` on systemd or `service['redis6379']` on initd, upstart, and rcinit.
   - Resources: `redisio_configure` (1 custom resource), `service` (1).

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs 1 time for Redis instance **6379**.
   - Locates the service resource created during configuration.
   - Enables and starts `redis@6379` on systemd.
   - Enables and starts `redis6379` on initd, upstart, and rcinit.
   - Resources: accesses the existing Redis service resource and appends `start` and `enable` actions.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora for the Redis source-install path
- Build toolchain installed through `build_essential['install build deps']`; exact operating-system package names are not enumerated in the supplied cookbook files
- `redis-server` on Debian when `package_install` is enabled
- `redis` on RHEL/Fedora when `package_install` is enabled
- `memcached` package is implied by the Memcached custom resource, but the provider implementation was not supplied for verification

**Service dependencies**:
- Memcached service instance `memcached`
- Redis service instance `redis@6379` on systemd or `redis6379` on initd, upstart, and rcinit
- Network availability before `redis@6379` starts through `network-online.target`

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Client Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded attribute value
- **Usage context**: The value `redis_secure_password_123` is assigned to Redis instance **6379**, rendered into `/etc/redis/6379.conf` as `requirepass`, and required by Redis clients before normal command execution.

The Redis password must not be copied into playbooks, inventory, templates, shell commands, or logs. Store the replacement value in Ansible Vault, an AAP credential, or an approved external secret manager. Mark secret-bearing Redis configuration tasks as `no_log: true`.

Optional Redisio `data_bag_item` secret support is present but unused: `data_bag_name`, `data_bag_item`, and `data_bag_key` are not configured for Redis instance **6379**.

## Checks for the Migration

**Files to verify**:
- `/var/log/memcached`
- `/var/run/memcached`
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb` if preserving Chef breadcrumb behavior
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd
- `/lib/systemd/system/redis@6379.service` on systemd
- `/etc/init.d/redis6379` on initd
- `/etc/init/redis6379.conf` on upstart
- `/usr/local/etc/rc.d/redis6379` on rcinit
- `/etc/pam.d/su` on Debian
- `/etc/pam.d/sudo` on Debian

**Service endpoints to check**:
- Memcached instance **memcached** TCP endpoint: `0.0.0.0:11211`
- Memcached instance **memcached** UDP endpoint: `0.0.0.0:11211`
- Redis instance **6379** TCP endpoint: `*:6379` unless an explicit bind address is introduced during migration
- Redis instance **6379** Unix socket: none configured

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf`: 1 render
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: 1 render on systemd
- `redis.init.erb` → `/etc/init.d/redis6379`: 1 render on initd
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`: 1 render on upstart
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`: 1 render on rcinit
- Redis ulimit template → `/etc/pam.d/su`: 1 render on Debian

Only one Redis init-system-specific service template is rendered on a host.

## Pre-flight checks:
```bash
# Memcached instance: memcached
systemctl status memcached
ps -ef | grep '[m]emcached'

# Validate TCP and UDP listeners for memcached.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

# Validate Memcached protocol health.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | head

# Validate Memcached directories.
stat -c '%U:%G %a %n' /var/log/memcached /var/run/memcached

# Redis instance: 6379 on systemd
systemctl status redis@6379
ps -ef | grep '[r]edis-server.*6379.conf'

# Validate the Redis TCP listener.
ss -ltnp | grep ':6379'

# Supply REDISCLI_AUTH securely from AAP or Ansible Vault.
# Do not place the password in shell history.
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 PING
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 INFO server | grep '^redis_version:'
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 INFO persistence | \
  grep -E '^(rdb_last_bgsave_status|aof_enabled):'

# Validate non-secret Redis configuration values.
grep -E '^(port|tcp-backlog|databases|syslog-enabled|maxclients|appendonly) ' \
  /etc/redis/6379.conf

# Confirm wrapper cleanup removed the Redis 3.2 legacy directives.
if grep -E '^(slave-serve-stale-data|slave-read-only|repl-ping-slave-period|client-output-buffer-limit|slave-priority)' \
  /etc/redis/6379.conf; then
  echo "Unexpected Redis directives remain"
  exit 1
else
  echo "Redis cleanup checks passed"
fi

# Validate Redis instance directories.
stat -c '%U:%G %a %n' /etc/redis /var/lib/redis /var/run/redis/6379

# Validate the systemd service for Redis instance 6379.
systemctl cat redis@6379
systemctl is-enabled redis@6379
systemctl show redis@6379 -p User -p Group -p LimitNOFILE

# For non-systemd hosts, validate the applicable service name.
# service redis6379 status

# Review service logs.
journalctl -u memcached -n 100 --no-pager
journalctl -u redis@6379 -n 100 --no-pager

# Validate filesystem capacity.
df -h /var/lib/redis /var/log/redis /var/log/memcached
```