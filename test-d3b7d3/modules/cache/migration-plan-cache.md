---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures and enables one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` at `0.0.0.0`, uses 64 MB of memory and 1,024 maximum connections, and runs under `service_user`. Redis listens on port `6379`, uses `/etc/redis/6379.conf`, stores data under `/var/lib/redis`, and is enabled as `redis@6379` on systemd systems or `redis6379` on other supported init systems. Redis is installed through the tarball path by default on Debian-family systems, uses version `3.2.11`, and is configured with a password that must be moved to Ansible Vault or an AAP credential. The migration must also preserve the Redis configuration cleanup, Debian PAM handling, ulimit behavior, default Redis service disabling, and service enablement.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Resource: `memcached_instance[memcached]`
  - Memory: `64 MB`
  - TCP port: `11211`
  - UDP port: `11211`
  - Listen address: `0.0.0.0`
  - Maximum connections: `1024`
  - Maximum object size: `1m`
  - Threads: `node['memcached']['threads']`
  - User: `service_user`
  - Ulimit: `1024`
  - Experimental options: empty list
  - Additional CLI options: empty list
  - Actions: `start`, `enable`

- **6379**: Redis cache service
  - Redis port: `6379`
  - Redis password: `redis_secure_password_123`; store the migrated value in Ansible Vault or an AAP credential
  - `replicaservestaledata`: explicitly set to `nil`
  - Instance name: `6379`
  - Systemd service: `redis@6379`
  - Init.d, Upstart, and FreeBSD rcinit service: `redis6379`
  - Redis configuration path: `/etc/redis/6379.conf`
  - Redis data directory: `/var/lib/redis`
  - Redis PID directory base: `/var/run/redis`
  - Redis user/group: `redis`/`redis`
  - Redis log directory: `/var/log/redis`
  - Databases: `16`
  - TCP backlog: `511`
  - Timeout: `0`
  - Keepalive: `0`
  - Log level: `notice`
  - Syslog enabled: `yes`
  - Maximum clients: `10000`
  - RDB compression and checksum: enabled
  - Append fsync: `everysec`
  - Bind address: unset by default
  - TLS settings: unset
  - Data-bag settings: unset
  - Actions: `start`, `enable`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
```

The providers for `memcached_instance`, `build_essential`, and `user_ulimit` are supplied by dependency cookbooks and are not exposed as provider paths in the execution tree.

**Templates:**

```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
```

The Redis configuration template defaults to `redis.conf.erb`. The service template is selected by `node['redisio']['job_control']`.

**Attributes:**

```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

**Files:**

```text
```

The execution tree contains no static application `cookbook_file` or `remote_file` deployment. However, `redisio::ulimit` includes the Debian-specific resource `cookbook_file[/etc/pam.d/sudo]`, which must be preserved by the migration. It also renders `/etc/pam.d/su`.

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Defines the single Redis server item:
     ```ruby
     {
       'port' => '6379',
       'requirepass' => 'redis_secure_password_123',
       'replicaservestaledata' => nil
     }
     ```
   - Creates `directory[/var/log/redis]` with owner `redis`, group `redis`, mode `0755`, and recursive creation enabled.
   - Includes `redisio::default`.
   - Executes `ruby_block[fix_redis_config]`.
   - Includes `redisio::enable`.
   - `ruby_block[fix_redis_config]` checks `/etc/redis/6379.conf` and removes complete lines beginning with:
     - `replica-serve-stale-data`
     - `replica-read-only`
     - `repl-ping-replica-period`
     - `client-output-buffer-limit`
     - `replica-priority`
   - The configuration cleanup must be idempotent and notify the Redis instance only when the file changes.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, user `service_user`, and ulimit `1024`.
   - Passes through `node['memcached']['threads']`.
   - Uses empty experimental and additional CLI option lists.
   - Starts and enables the `memcached` service.
   - The exact dependency-resolved package name and service-unit implementation are not exposed in the execution tree.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Executes `apt_update[apt_update]`.
   - On Debian-family systems with `package_install` false, includes `redisio::_install_prereqs` and executes `build_essential[install build deps]`.
   - When `bypass_setup` is false, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Uses these platform defaults:
     - Debian/Ubuntu: package name `redis-server`; `package_install` false.
     - RHEL/Fedora: package name `redis`; `package_install` false.
     - FreeBSD: package name `redis`; `package_install` true.
     - Other platforms: package name `redis`; `package_install` false.
   - Uses Redis version `3.2.11` and URL `http://download.redis.io/releases/redis-3.2.11.tar.gz` when source installation is selected.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs every resolved item in `packages_to_install` through `package[pkg]`.
   - Is traversed from `redisio::default` and the source-install branch of `redisio::install`.
   - The Ansible implementation must install the prerequisite set once, idempotently, rather than duplicating the task block.
   - The execution tree does not expose the resolved prerequisite names; derive them from the actual Redis build requirements.

5. **`build_essential[install build deps]`** (dependency custom resource):
   - Installs compiler and build dependencies for source installation.
   - Must be implemented as an idempotent Ansible package task block.

6. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses exactly one installation branch.
   - Package branch:
     - Installs the platform-specific `node['redisio']['package_name']`.
     - Uses `node['redisio']['version']` when defined.
   - Tarball branch:
     - Includes `redisio::_install_prereqs`.
     - Executes `build_essential[install build deps]`.
     - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
     - Executes `redisio_install[redis-installation]` with version `3.2.11`, `safe_install: true`, and no custom installation directory unless configured.
     - Includes `redisio::ulimit`.
   - The Ansible role must not install both a distribution package and the tarball.

7. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `template[/etc/pam.d/su]`.
   - On Debian-family systems, deploys `cookbook_file[/etc/pam.d/sudo]`.
   - Preserves `/etc/security/limits.d` as the limits directory.
   - The configured `node['ulimit']['users']` collection is empty, so the `user_ulimit[user]` loop executes zero times.
   - Applies configured Redis user limits before service startup.
   - The Debian-specific PAM resources must be represented explicitly in Ansible.

8. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the distribution-provided default Redis service.
   - The resolved `service_name` is platform-dependent and must be obtained from the target distribution rather than replaced with a universal name.

9. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Traverses `redisio::default` and `redisio::ulimit` again as already-visited circular dependencies.
   - Executes `redisio_configure[redis-servers]` with one server item:
     - Name: `6379`
     - Port: `6379`
     - Password: `redis_secure_password_123`
     - `replicaservestaledata`: `nil`
     - Base PID directory: `/var/run/redis`
     - Default settings from `node['redisio']['default_settings']`
   - Configures `/etc/redis/6379.conf`, `/var/lib/redis`, user/group `redis`/`redis`, permissions `0644`, 16 databases, backlog `511`, timeout `0`, keepalive `0`, log level `notice`, syslog enabled, and maximum clients `10000`.
   - Uses the Redis configuration template selected by `node['redisio']['redis_config']['template_source']`, defaulting to `redis.conf.erb`.
   - Creates exactly one Redis service:
     - `redis6379` for `initd`, `upstart`, and `rcinit`.
     - `redis@6379` for `systemd`.
   - Unknown job-control values create no service and log an error.
   - Overrides `node['redisio']['servers']` with the resolved one-item collection.

10. **`ruby_block[fix_redis_config]`** (`cookbooks/cache/recipes/default.rb`):
    - Runs after Redis configuration and before `redisio::enable`.
    - Removes only the five specified replication-related directives from `/etc/redis/6379.conf`.
    - Does not independently restart or reload Redis.
    - Ansible must use an idempotent `replace` or `lineinfile` implementation and notify the selected Redis service only on change.

11. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Iterates over the resolved Redis collection once, for item **6379**.
    - Starts and enables `redis@6379` on systemd.
    - Starts and enables `redis6379` on init.d, Upstart, and FreeBSD rcinit.
    - The Ansible service task must target the selected instance-specific service.

## Dependencies

**External cookbook dependencies**:

- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint
- `selinux` files are present in the dependency directory but no SELinux recipe is included in this execution flow

**System package dependencies**:

- Memcached package installation is encapsulated by `memcached_instance[memcached]`; its resolved package name is not exposed in the execution tree.
- Debian/Ubuntu Redis package path: `redis-server`
- RHEL/Fedora Redis package path: `redis`
- FreeBSD Redis package path: `redis`
- Redis source installation prerequisites are resolved through `redisio::_install_prereqs` and `build_essential[install build deps]`.
- `apt_update[apt_update]` runs in the Redis default recipe.

**Service dependencies**:

- Memcached service `memcached`
- Redis instance service `redis@6379` on systemd
- Redis instance service `redis6379` on init.d, Upstart, and FreeBSD rcinit
- Distribution-provided default Redis service, which must be stopped and disabled before the instance-specific service is enabled

## Credentials

**Detection Summary**: 1 credential detected in 1 file.

**Source**:

- **Provider**: Hardcoded in the wrapper cookbook
- **URL**: None detected
- **Path**: None detected

### Redis authentication password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext value
- **Current value**: `redis_secure_password_123`
- **Usage context**: Configures the Redis `requirepass` authentication password for instance `6379`
- **Migration storage**: Ansible Vault or an AAP credential; do not retain the plaintext value in the role or playbook

Optional data-bag fields are unset:

- `data_bag_name`
- `data_bag_item`
- `data_bag_key`

No data-bag, Chef Vault, Conjur, CyberArk, or external secret-manager call was detected. Optional TLS credential attributes exist but are unset, including `tlscertfile`, `tlskeyfile`, `tlskeyfilepass`, `tlsclientcertfile`, `tlsclientkeyfile`, `tlsclientkeyfilepass`, `tlsdhparamsfile`, `tlscacertfile`, and `tlscacertdir`.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/var/log/redis`
- `/var/lib/redis`
- `/var/run/redis`
- Memcached configuration file generated by the Ansible role
- Memcached service unit or init configuration
- Redis service definition selected for the host:
  - `/etc/systemd/system/redis@.service`, or
  - the applicable init.d, Upstart, or rcinit service definition
- `/etc/pam.d/su` on Debian-family systems
- `/etc/pam.d/sudo` on Debian-family systems
- Redis limits files under `/etc/security/limits.d`

**Service endpoints to check**:

- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis TCP: `0.0.0.0:6379` or the configured bind address
- Redis Unix socket: none configured

**Templates rendered**:

- Redis configuration template: one render for instance `6379`, selected through `redis.conf.erb`
- Redis service definition: one host-specific path:
  - `redis@.service.erb` on systemd
  - `redis.init.erb` on init.d
  - `redis.upstart.conf.erb` on Upstart
  - `redis.rcinit.erb` on FreeBSD rcinit
- `/etc/pam.d/su`: one Debian-family render when applicable
- `/etc/pam.d/sudo`: one Debian-family cookbook-file deployment when applicable
- No Sentinel templates are rendered

## Pre-flight checks

```bash
# Verify Memcached service state
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached

# Verify Memcached TCP and UDP listeners for instance memcached
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
printf "stats\r\nquit\r\n" | nc 127.0.0.1 11211

# Verify Memcached command-line configuration
systemctl cat memcached
ps aux | grep '[m]emcached'
# Confirm: 64 MB memory, TCP/UDP port 11211, 0.0.0.0 binding, and 1024 maximum connections

# Verify Redis instance 6379 on systemd hosts
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Verify Redis instance 6379 on non-systemd hosts
service redis6379 status

# Verify Redis process and port for instance 6379
ps aux | grep '[r]edis-server'
ss -ltnp | grep ':6379'

# Verify the distribution default Redis service is not competing
systemctl status redis
systemctl is-enabled redis
# The default service must be stopped and disabled where it exists.

# Verify Redis configuration and directories for instance 6379
grep -E '^(port|requirepass|dir|dbfilename|maxclients|loglevel|syslog-enabled)' /etc/redis/6379.conf
ls -ld /var/lib/redis /var/log/redis /var/run/redis

# Verify removed Redis directives
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
# Expected result: no matching active configuration lines.

# Verify Redis authentication for instance 6379
export REDISCLI_AUTH='<value from Ansible Vault or AAP credential>'
redis-cli -p 6379 PING
redis-cli -p 6379 INFO server
redis-cli -p 6379 CONFIG GET requirepass

# Verify unauthenticated access is rejected
env -u REDISCLI_AUTH redis-cli -p 6379 PING

# Verify service logs
journalctl -u redis@6379 --no-pager -n 100
journalctl -u memcached --no-pager -n 100
journalctl -u redis@6379 --no-pager | grep -Ei 'error|fatal|failed'
journalctl -u memcached --no-pager | grep -Ei 'error|fatal|failed'

# Verify convergence on systemd hosts
systemctl show redis@6379 | grep -E 'LoadState|ActiveState|SubState|UnitFileState'
systemctl show memcached | grep -E 'LoadState|ActiveState|SubState|UnitFileState'

# Verify Debian-specific PAM and limits handling where applicable
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo
find /etc/security/limits.d -maxdepth 1 -type f -print
```

Expected results:

- Instance `memcached` is active, enabled, and listening on TCP and UDP port `11211`.
- Instance `memcached` uses 64 MB memory, `0.0.0.0` binding, and 1,024 maximum connections.
- Redis instance `6379` is active, enabled, and listening on port `6379`.
- The Redis password is required and supplied from protected secret storage.
- The unwanted Redis directives are absent.
- Redis data, PID, and log directories are accessible to the `redis` user and group.
- On systemd hosts, the Redis service is specifically `redis@6379`.
- The distribution default Redis service is stopped and disabled.
- Debian-specific PAM files and limits behavior are present when applicable.