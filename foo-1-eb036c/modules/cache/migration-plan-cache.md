---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache instances: a Memcached instance named **memcached** and a Redis instance named **6379**. Memcached listens on TCP and UDP port 11211 and is started and enabled. Redis 3.2.11 is installed from source by default on Ubuntu/CentOS, configured at `/etc/redis/6379.conf`, and managed as `redis@6379` on systemd hosts. Redis authentication is enabled with a currently hardcoded password in the wrapper recipe. After configuration, the wrapper removes five Redis replication/client-buffer directives from the generated configuration.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache service managed by `memcached_instance[memcached]`.
  - Location/Path: Log path `/var/log/memcached`
  - Port/Socket: TCP `11211`; UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory `64 MB`; maximum connections `1024`; maximum object size `1m`; file-descriptor limit `1024`; started and enabled.

- **6379**: Redis cache instance named from its configured port.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11` source installation by default; RDB persistence with `save 900 1`, `save 300 10`, and `save 60 10000`; `requirepass` configured; no explicit `bind` directive; systemd service `redis@6379` started and enabled. The wrapper removes `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from the final configuration.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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

**Templates:**

**Attributes:**
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to one Redis instance named **6379** with port `6379`, `requirepass` set, and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` when the file exists.
     - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the modified configuration back to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `directory` (1), `ruby_block` (1), `include_recipe` (3).

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]` to configure the named Memcached instance **memcached**.
   - Configures memory `64 MB`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, file-descriptor limit `1024`, no experimental options, and no additional CLI options.
   - Applies `start` and `enable` actions.
   - The custom-resource implementation was not included in the supplied execution tree; preserve the documented effective instance settings during migration.
   - Resources: `memcached_instance` custom resource (1).

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - On the default Ubuntu/CentOS source-install path, includes `redisio::_install_prereqs` and uses `build_essential[install build deps]`.
   - Because `node['redisio']['bypass_setup']` is `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Resources: `apt_update` (1), `build_essential` custom resource (1), and `include_recipe` (5 across conditional paths).

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Ubuntu/Debian and CentOS/RHEL/Fedora, installs the explicit package **tar**.
   - Resources: `package[tar]` (1).

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses the default source-install path because `node['redisio']['package_install']` is `false` on Ubuntu and CentOS.
   - Re-includes `redisio::_install_prereqs`; Chef does not repeatedly converge an already included recipe during the same run.
   - Uses `build_essential[install build deps]` and `redisio_install[redis-installation]`.
   - Installs Redis version `3.2.11` from `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - The expected source-install workflow downloads the archive, extracts it using `tar`, runs `make clean && make`, runs `make install`, and places binaries in `/usr/local/bin`.
   - Safe-install behavior retains an existing Redis binary when replacement cannot be performed safely.
   - Alternative package-install branch, only when `package_install` is set to `true`:
     - Installs `redis-server` on Debian-family hosts.
     - Installs `redis` on RHEL/Fedora hosts.
   - Includes `redisio::ulimit`.
   - Resources in the active Ubuntu/CentOS default path: `build_essential` custom resource (1), `redisio_install` custom resource (1), and `include_recipe` (2).
   - The `redisio_install` custom-resource implementation was not included in the Providers inventory and was not independently analyzed.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders a PAM template to `/etc/pam.d/su`.
   - On Debian-family systems, deploys the cookbook file `sudo` to `/etc/pam.d/sudo` with mode `0644`.
   - `node['ulimit']['users']` defaults to an empty hash; no named `user_ulimit` resources are created.
   - Iterations: `user_ulimit` runs **0 times** because the user collection is empty.
   - Resources on Debian-family systems: `template` (1), `cookbook_file` (1), and `user_ulimit` (0).

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the operating-system Redis service to prevent conflicts with the cookbook-managed Redis instance:
     - Ubuntu/Debian: `redis-server`
     - CentOS/RHEL/Fedora: `redis`
   - Resources: `service` (1) with `stop` and `disable` actions.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - References `redisio::default` and `redisio::ulimit`, which are already traversed in this execution flow.
   - Uses `redisio_configure[redis-servers]` for the Redis server collection.
   - Iterations: runs **1 time** for Redis instance **6379**.
   - Produces `/etc/redis/6379.conf` from the Redis configuration template for instance **6379**.
   - Ensures the Redis service account `redis` and expected paths:
     - `/etc/redis`, owner `root`, group `redis`, mode `0775`
     - `/var/lib/redis`, owner `redis`, group `redis`, mode `0775`
     - `/var/run/redis/6379`, owner `redis`, group `redis`, mode `0755`
   - Creates or manages `/var/lib/redis/dump-6379.rdb` permissions when that RDB file exists.
   - Creates `/etc/redis/6379.conf.breadcrumb` when absent to prevent later Chef runs from overwriting the generated Redis configuration. The wrapper’s `fix_redis_config` block still modifies `/etc/redis/6379.conf` on every run.
   - On systemd hosts:
     - Creates `/etc/tmpfiles.d/redis@6379.conf`.
     - Renders `/lib/systemd/system/redis@6379.service`.
     - Notifies `systemctl daemon-reload` when the service unit changes.
     - Creates service resource `redis@6379`.
   - Init-system alternatives:
     - `initd`: `/etc/init.d/redis6379`
     - `upstart`: `/etc/init/redis6379.conf`
     - `rcinit`: `/usr/local/etc/rc.d/redis6379`
   - The `redisio_configure` custom-resource implementation was not included in the Providers inventory and was not independently analyzed.

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs **1 time** for Redis instance **6379**.
   - Appends `start` and `enable` actions to the service resource created during configuration:
     - Systemd: `redis@6379`
     - Non-systemd Linux: `redis6379`
   - On systemd hosts, the resulting service state is `redis@6379` started and enabled.
   - Resources: modifies the existing service resource; no separate service resource is declared.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar`
- Build tools and compiler prerequisites required for `make`
- Alternative Redis package branch only:
  - `redis-server` on Debian-family platforms
  - `redis` on RHEL/Fedora platforms

**Service dependencies**:
- Memcached service for instance **memcached**
- Redis service `redis@6379` on systemd hosts
- OS-provided Redis service must be stopped and disabled:
  - `redis-server` on Debian-family systems
  - `redis` on RHEL/Fedora systems

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded cookbook attribute override
- **Usage context**: Rendered into `/etc/redis/6379.conf` as Redis `requirepass`; Redis clients must authenticate with `AUTH` before issuing normal commands.

Redisio supports optional unencrypted Chef data-bag retrieval when `data_bag_name`, `data_bag_item`, and `data_bag_key` are configured, but those attributes are not configured by this wrapper cookbook. No Chef Vault, encrypted data bag, external secret manager, environment-variable secret, TLS certificate path, or TLS private-key path is configured.

For migration, store the Redis password in an Ansible Automation Platform credential, external secret-manager lookup, or encrypted Ansible Vault variable. Use `no_log: true` for tasks that render the password and do not retain the hardcoded password in playbook source.

## Checks for the Migration

**Files to verify**:
- `/var/log/memcached`
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb` if reproducing Chef’s one-time configuration-template behavior
- `/var/lib/redis`
- `/var/lib/redis/dump-6379.rdb` if Redis has created an RDB snapshot
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/pam.d/su` on Debian-family hosts
- `/etc/pam.d/sudo` on Debian-family hosts

**Service endpoints to check**:
- **memcached**:
  - TCP port `11211`
  - UDP port `11211`
  - Bind address `0.0.0.0`
- **6379**:
  - Redis TCP port `6379`
  - No Unix socket configured
  - No explicit Redis bind address configured

**Templates rendered**:
- Redis configuration template → `/etc/redis/6379.conf`: renders **1 time** for instance **6379**.
- Redis systemd service template → `/lib/systemd/system/redis@6379.service`: renders **1 time** on systemd hosts for instance **6379**.
- PAM `su` template → `/etc/pam.d/su`: renders **1 time** on Debian-family hosts.
- Cookbook file `sudo` → `/etc/pam.d/sudo`: deployed **1 time** on Debian-family hosts.
- The Redis configuration template contains an internal three-item client-buffer list before the wrapper removes the `client-output-buffer-limit` lines:
  - `normal 0 0 0`
  - `replica 256mb 64mb 60`
  - `pubsub 32mb 8mb 60`

## Pre-flight checks:
```bash
# Memcached instance: memcached
# Confirm the service is active. Service-unit naming is platform/package dependent.
systemctl status memcached
pgrep -a memcached

# Confirm TCP and UDP listener configuration.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

# Verify Memcached responds on TCP port 11211.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
# Expected: a line beginning with "VERSION"

printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | head -n 5
# Expected: lines beginning with "STAT"

# Redis instance: 6379
systemctl status redis@6379
systemctl is-enabled redis@6379
# Expected: active/running and enabled.

pgrep -a redis-server
ss -ltnp | grep ':6379'
# Expected: redis-server listening on TCP port 6379.

# Validate Redis instance 6379 configuration.
test -f /etc/redis/6379.conf
grep -E '^port 6379$' /etc/redis/6379.conf
grep -E '^dir /var/lib/redis$' /etc/redis/6379.conf
grep -E '^pidfile /var/run/redis/6379/redis_6379.pid$' /etc/redis/6379.conf
grep -E '^requirepass ' /etc/redis/6379.conf

# Confirm Chef post-processing behavior was preserved.
! grep -qE '^replica-serve-stale-data' /etc/redis/6379.conf
! grep -qE '^replica-read-only' /etc/redis/6379.conf
! grep -qE '^repl-ping-replica-period' /etc/redis/6379.conf
! grep -qE '^client-output-buffer-limit' /etc/redis/6379.conf
! grep -qE '^replica-priority' /etc/redis/6379.conf

# Verify Redis authentication and health for instance 6379.
REDISCLI_AUTH='<redis_password_from_AAP_secret>' redis-cli -h 127.0.0.1 -p 6379 PING
# Expected: PONG

REDISCLI_AUTH='<redis_password_from_AAP_secret>' redis-cli -h 127.0.0.1 -p 6379 INFO server | grep '^redis_version:'
# Expected: redis_version:3.2.11 for the default Chef source-install path.

REDISCLI_AUTH='<redis_password_from_AAP_secret>' redis-cli -h 127.0.0.1 -p 6379 INFO persistence | grep -E '^(rdb_last_save_time|rdb_changes_since_last_save):'
# Expected: Redis persistence metrics.

# Verify systemd assets for Redis instance 6379.
test -f /lib/systemd/system/redis@6379.service
test -f /etc/tmpfiles.d/redis@6379.conf
systemctl cat redis@6379
journalctl -u redis@6379 -n 100 --no-pager

# Verify Redis paths and ownership.
ls -ld /var/log/redis /etc/redis /var/lib/redis /var/run/redis/6379
# Expected: /var/log/redis is redis:redis mode 0755.
# Expected: /var/lib/redis is redis:redis.
# Expected: /var/run/redis/6379 is redis:redis mode 0755.

# Verify Debian-family PAM files when applicable.
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo
stat -c '%a %n' /etc/pam.d/sudo
# Expected: /etc/pam.d/sudo mode 0644.

# Verify the applicable OS-managed Redis service remains disabled and inactive.
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true
systemctl is-enabled redis 2>/dev/null || true
systemctl is-active redis 2>/dev/null || true
# Expected: the service applicable to the operating system is disabled and inactive.
```