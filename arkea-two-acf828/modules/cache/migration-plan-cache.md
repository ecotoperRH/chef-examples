---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two cache services: a Memcached instance named **memcached** and an authenticated Redis instance named **6379**. Memcached listens on TCP and UDP port **11211** using dependency cookbook defaults. Redis is installed from source by default at version **3.2.11**, uses `/etc/redis/6379.conf`, is managed as `redis@6379` on systemd hosts, and listens on TCP port **6379**. The Redis password is hardcoded in the wrapper recipe and must be migrated to an Ansible Automation Platform credential, external secret manager, or Ansible Vault-encrypted variable.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache daemon.
  - Location/Path: Log path attribute `/var/log/memcached`
  - Port/Socket: TCP `11211`; UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory allocation `64 MB`; maximum connections `1024`; maximum object size `1m`; file-descriptor limit `1024`; started and enabled through `memcached_instance['memcached']`.

- **6379**: Redis cache instance.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data and home directory `/var/lib/redis`; PID directory `/var/run/redis/6379`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis version `3.2.11` by default through source installation; user/group `redis:redis`; `requirepass` is configured; 16 databases; TCP backlog `511`; `maxclients` `10000`; RDB persistence; syslog enabled with facility `local0`; systemd service `redis@6379`; systemd unit `/lib/systemd/system/redis@6379.service`; tmpfiles entry `/etc/tmpfiles.d/redis@6379.conf`.
  - The wrapper removes these obsolete or incompatible directives from `/etc/redis/6379.conf` after Redis configuration:
    - `replica-serve-stale-data`
    - `replica-read-only`
    - `repl-ping-replica-period`
    - `client-output-buffer-limit`
    - `replica-priority`

## File Structure

Only recipe and provider Ruby files that are part of the supplied execution tree are listed below. The supplied execution tree does not identify a Memcached provider file, so none is listed.

**Recipes:**
```text
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
```

**Templates:**

No `.erb` file paths are listed here because the requested execution-tree constraint permits only `.rb` files shown in that tree. The used provider logic does render the Redis configuration source named by `node['redisio']['redis_config']['template_source']`—default `redis.conf.erb`—and, on systemd, `redis@.service.erb`. Their destinations are documented below.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Defines `node['redisio']['servers']` with the single Redis instance **6379**:
     - Port: `6379`
     - `requirepass`: hardcoded Redis password
     - `replicaservestaledata`: `nil`
   - Creates `/var/log/redis` recursively with owner/group `redis:redis` and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block['fix_redis_config']` after Redis configuration:
     - Reads `/etc/redis/6379.conf` when it exists.
     - Removes `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the modified configuration to `/etc/redis/6379.conf`.
     - Does not notify Redis to restart or reload; the Ansible implementation must notify a controlled restart when this configuration changes.
   - Includes `redisio::enable`.
   - Resources: `include_recipe` (3), `directory` (1), `ruby_block` (1).

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource `memcached_instance['memcached']`.
   - Configures instance **memcached** with memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, and ulimit `1024`.
   - Requests actions `start` and `enable`.
   - The supplied execution tree does not include the Memcached provider implementation. Implement the equivalent state in Ansible using the verified target-platform Memcached package, configuration, and enabled/started service.
   - Resources: `memcached_instance` (1 custom resource).

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update['apt_update']`.
   - Uses the default source-install path because `node['redisio']['package_install']` defaults to `false` on Debian and RHEL-family platforms.
   - Includes these four recipes directly:
     1. `redisio::_install_prereqs`
     2. `redisio::install`
     3. `redisio::disable_os_default`
     4. `redisio::configure`
   - Resources: `apt_update` (1), `build_essential` (1 custom resource), `include_recipe` (4 direct includes).

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Iterations: runs once for package **tar** on Debian, RHEL, and Fedora platform families.
   - Installs package `tar`.
   - This recipe is included again by the source-install branch of `redisio::install`; an Ansible role should install `tar` idempotently once.
   - Resources: `package` (1 on supported Linux platform families).

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Under the effective default source-install branch:
     - Includes `redisio::_install_prereqs`.
     - Uses `build_essential['install build deps']`.
     - Uses custom resource `redisio_install['redis-installation']`.
     - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
     - Extracts the archive, runs `make clean && make`, then runs `make install`.
     - Does not rebuild when Redis `3.2.11` is already installed, or when `safe_install` is true and `redis-server` already exists.
   - Includes `redisio::ulimit`.
   - If `redisio_package_install` is explicitly set to true instead:
     - Installs package `redis-server` on Debian.
     - Installs package `redis` on RHEL and Fedora.
     - Uses no package version pin by default.
   - Resources: `build_essential` (1 custom resource), `redisio_install` (1 custom resource), `include_recipe` (2 in the source-install branch).

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian hosts, renders a template to `/etc/pam.d/su`.
   - Deploys cookbook file content to `/etc/pam.d/sudo` from source `sudo`, mode `0644`.
   - The `node['ulimit']['users']` collection defaults to an empty hash.
   - Iterations: no `user_ulimit` resources are created with the supplied default attributes.
   - Resources on Debian: `template` (1), `cookbook_file` (1), `user_ulimit` (0).

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the OS-provided Redis service to prevent a conflict with Redis instance **6379**.
   - Debian service: `redis-server`.
   - RHEL and Fedora service: `redis`.
   - Resources: `service` (1; actions `stop`, `disable`).

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; these are already visited circular includes and do not create a second independent execution chain.
   - Uses custom resource `redisio_configure['redis-servers']` with Redis version `3.2.11`, the default settings hash, instance **6379**, and PID base path `/var/run/redis`.
   - Iterations: runs once for Redis instance **6379**.
     - Creates user `redis` with home `/var/lib/redis`.
     - Creates `/etc/redis` with owner/group `root:redis` and mode `0775`.
     - Creates `/var/lib/redis` with owner/group `redis:redis` and mode `0775`.
     - Creates `/var/run/redis/6379` with owner/group `redis:redis` and mode `0755`.
     - Renders `redis.conf.erb` to `/etc/redis/6379.conf` with owner/group `redis:redis` and mode `0644`.
     - Creates `/etc/redis/6379.conf.breadcrumb` once to prevent subsequent Chef overwrites of `/etc/redis/6379.conf`.
     - Does not configure a Unix socket, TLS files, or a dedicated Redis log file; Redis uses syslog and the wrapper separately creates `/var/log/redis`.
   - On systemd hosts:
     - Creates `/etc/tmpfiles.d/redis@6379.conf`.
     - Renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
     - Runs `systemctl daemon-reload` when the unit file changes.
     - Declares service `redis@6379`.
   - On `initd` hosts, renders `redis.init.erb` to `/etc/init.d/redis6379` and uses service `redis6379`.
   - On `upstart` hosts, renders `redis.upstart.conf.erb` to `/etc/init/redis6379.conf` and uses service `redis6379`.
   - On `rcinit` hosts, renders `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379` and uses service `redis6379`.
   - Resources for the effective systemd path: `redisio_configure` (1 custom resource), `user` (1), `directory` (3), `template` (2), `file` (2), `execute` (1 notified only), `service` (1).

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs once for Redis instance **6379**.
   - On systemd hosts, appends `start` and `enable` actions to `service[redis@6379]`.
   - On non-systemd hosts, appends `start` and `enable` actions to `service[redis6379]`.
   - Resources: modifies the service resource created by `redisio::configure`; no new service resource is created.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint specified

**System package dependencies**:
- `tar`
- Build-essential or development toolchain package set installed through `build_essential`
- Conditional package-install alternative:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`
- Memcached package name is not exposed by the supplied execution tree and must be verified for the target operating system before implementing the Ansible package task.

**Service dependencies**:
- Memcached service for instance `memcached`
- Debian OS Redis service `redis-server`, stopped and disabled before enabling Redis instance `6379`
- RHEL/Fedora OS Redis service `redis`, stopped and disabled before enabling Redis instance `6379`
- Systemd service `redis@6379` on systemd hosts

## Credentials

**Detection Summary**: 1 active credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Instance Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded attribute value
- **Usage context**: Redis `requirepass` authentication for Redis instance **6379**. The Redisio configuration provider renders this value into `/etc/redis/6379.conf`. The Redis init script also receives it when the `initd` branch is used.
- **Current value**: `redis_secure_password_123`
- **Migration requirement**: Store the password in an Ansible Automation Platform credential, external secret manager, or Ansible Vault-encrypted variable. Do not store it in inventory, unencrypted group variables, or playbooks. Use `no_log: true` for sensitive configuration tasks.

### Optional Redis Data-Bag Password Mechanism
- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Chef data bag, if configured
- **Usage context**: When all three values are configured, the provider reads the Chef data-bag item and uses the selected key as both `requirepass` and `masterauth`.
- **Effective status**: Not active. All three defaults are `nil`; the wrapper instead provides the hardcoded `requirepass`.

No Chef Vault, CyberArk, Conjur, encrypted data bag, environment-variable secret, or active TLS certificate/key reference is configured by this cookbook.

## Checks for the Migration

**Files to verify**:
- `/var/log/memcached`
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb` when preserving Chef one-time configuration behavior
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/pam.d/su` on Debian hosts
- `/etc/pam.d/sudo` on Debian hosts

**Service endpoints to check**:
- **memcached**:
  - TCP port `11211`
  - UDP port `11211`
  - Listen address `0.0.0.0`
- **6379**:
  - TCP port `6379`
  - Unix socket: none configured
  - Bind address: Redis default; no explicit bind address configured by this cookbook

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf`: 1 render attempt for instance **6379**. Chef skips replacement after `/etc/redis/6379.conf.breadcrumb` exists.
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: 1 render on systemd hosts.
- Debian PAM template → `/etc/pam.d/su`: 1 render on Debian hosts.
- `redis.init.erb` → `/etc/init.d/redis6379`: 1 render only on `initd` hosts.
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`: 1 render only on `upstart` hosts.
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`: 1 render only on `rcinit` hosts.

## Pre-flight checks:
```bash
# ===== Memcached instance: memcached =====

# Confirm the platform-specific Memcached service name before use.
systemctl status memcached
systemctl is-enabled memcached
pgrep -a memcached

# Verify TCP port 11211 responds.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
# Expected: a line beginning with "VERSION"

# Verify a basic cache operation on TCP port 11211.
printf 'set cache_migration_check 0 60 2\r\nok\r\nget cache_migration_check\r\n' \
  | nc -w 3 127.0.0.1 11211
# Expected: "VALUE cache_migration_check 0 2", followed by "ok" and "END"

# Verify TCP and UDP listeners on all IPv4 interfaces.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
# Expected: TCP and UDP listeners associated with memcached.

# Verify the configured Memcached log path.
ls -ld /var/log/memcached


# ===== Redis instance: 6379 =====

# Verify the systemd service and Redis process.
systemctl status redis@6379
systemctl is-enabled redis@6379
pgrep -a redis-server
# Expected: redis@6379 is active and enabled.

# Verify the OS-packaged Redis services are disabled to avoid port conflicts.
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true
# Expected on Debian: disabled and inactive when the unit exists.

systemctl is-enabled redis 2>/dev/null || true
systemctl is-active redis 2>/dev/null || true
# Expected on RHEL/Fedora: disabled and inactive when the unit exists.

# Authenticate using the migrated secret; do not place the secret in shell history.
REDISCLI_AUTH="$REDIS_6379_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 PING
# Expected: PONG

REDISCLI_AUTH="$REDIS_6379_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 SET cache_migration_check ok EX 60
# Expected: OK

REDISCLI_AUTH="$REDIS_6379_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 GET cache_migration_check
# Expected: ok

REDISCLI_AUTH="$REDIS_6379_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 INFO server | grep redis_version
# Expected: redis_version:3.2.11 for the default source-install configuration.

# Verify Redis authentication is required.
redis-cli -h 127.0.0.1 -p 6379 PING
# Expected: NOAUTH Authentication required.

# Verify the Redis TCP listener and absence of a configured Unix socket.
ss -ltnp | grep ':6379'
# Expected: a redis-server listener on TCP port 6379.

# Verify required Redis configuration and removed directives.
grep -E '^(port|requirepass|datadir|dir|dbfilename|appendfsync|maxclients|syslog-enabled)' /etc/redis/6379.conf
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf && exit 1 || true
# Expected: required settings are present and the five removed directives are absent.

# Verify ownership and modes.
stat -c '%U:%G %a %n' /var/log/redis /etc/redis /var/lib/redis /var/run/redis/6379
# Expected:
# /var/log/redis: redis:redis 755
# /etc/redis: root:redis 775
# /var/lib/redis: redis:redis 775
# /var/run/redis/6379: redis:redis 755

# Verify Redis configuration, breadcrumb, and systemd assets.
test -f /etc/redis/6379.conf
test -f /etc/redis/6379.conf.breadcrumb
test -f /etc/tmpfiles.d/redis@6379.conf
test -f /lib/systemd/system/redis@6379.service

# Verify the systemd unit and daemon-reload result.
systemd-analyze verify /lib/systemd/system/redis@6379.service
systemctl cat redis@6379
systemctl show redis@6379 -p LoadState -p ActiveState -p SubState

# Verify Redis persistence storage and logs.
ls -lah /var/lib/redis
df -h /var/lib/redis
journalctl -u redis@6379 -n 100 --no-pager

# Verify process ownership and open-file limits.
ps -o pid,user,group,cmd -C redis-server
cat /proc/$(pgrep -o redis-server)/limits | grep -i 'open files'
```