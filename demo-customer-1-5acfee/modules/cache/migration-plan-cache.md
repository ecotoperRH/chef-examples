---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: a default Memcached instance named `memcached` and an authenticated Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` with 64 MB memory. Redis is installed from source by default as Redis `3.2.11`, listens on TCP port `6379`, is managed as `redis@6379` on systemd hosts, and uses a hardcoded `requirepass` value that must be migrated to secure Ansible Automation Platform credential storage.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached in-memory cache service.
  - Location/Path: Memcached package configuration and service definition are managed by the `memcached_instance[memcached]` dependency custom resource; its provider implementation is not present in the supplied execution tree.
  - Port/Socket: TCP `11211` and UDP `11211`, listening on `0.0.0.0`.
  - Key Config: 64 MB memory, maximum 1,024 connections, maximum item size `1m`, file-descriptor ulimit `1024`, no experimental or extra CLI options. The service is started and enabled.

- **6379**: Redis persistent key-value cache service.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`; log directory `/var/log/redis`.
  - Port/Socket: TCP `6379`; no Unix socket and no TLS listener.
  - Key Config: Redis `3.2.11` is installed from source by default; `requirepass` is configured; 16 databases; TCP backlog `511`; maximum clients `10000`; RDB persistence defaults; syslog enabled using facility `local0`. The wrapper removes selected replication directives after configuration rendering.
  - Service Name: `redis@6379` on systemd; `redis6379` on init.d, Upstart, and FreeBSD rcinit hosts.
  - Service State: Started and enabled by `redisio::enable`.

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
```

**Templates:**

No `.erb` file is listed here because the supplied execution-tree constraint permits only Ruby files. The execution behavior nevertheless renders the Redis configuration and, according to the selected job-control system, one service definition template as documented in the module explanation.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Replaces `node['redisio']['servers']` with one Redis instance named **6379**:
     - Port: `6379`
     - `requirepass`: configured hardcoded password
     - `replicaservestaledata`: `nil`
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Opens `/etc/redis/6379.conf` only if it exists.
     - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the modified content back to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: one `directory`, one `ruby_block`, and three `include_recipe` resources.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Starts and enables the explicitly named **memcached** service.
   - Configures the `memcached` instance with:
     - Memory: `64` MB.
     - TCP port: `11211`.
     - UDP port: `11211`.
     - Listen address: `0.0.0.0`.
     - Maximum connections: `1024`.
     - Maximum object size: `1m`.
     - Ulimit: `1024`.
     - Empty experimental and extra CLI option arrays.
   - The supplied execution tree does not include the custom-resource provider. Implement the effective settings using the target platform’s Memcached package, configuration format, and service unit.
   - Resources: one `memcached_instance` custom resource.

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `package_install` is `false` by default on Debian, RHEL, Fedora, and generic fallback platforms, uses the source-install branch.
   - Includes `redisio::_install_prereqs`.
   - Uses `build_essential[install build deps]`.
   - Because `bypass_setup` is `false`, includes the following recipes in order:
     1. `redisio::install`
     2. `redisio::disable_os_default`
     3. `redisio::configure`
   - Resources: one `apt_update`, one `build_essential`, and four `include_recipe` resources.

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Debian, RHEL, and Fedora, installs the `tar` package.
   - On unsupported platform families, no package resource runs.
   - Resources: one `package[tar]` on Debian, RHEL, and Fedora.

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Includes `redisio::_install_prereqs`, ensuring `tar` is installed.
   - Uses `build_essential[install build deps]` to install compiler and build requirements.
   - Uses `redisio_install[redis-installation]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Unpacks the archive, runs `make clean && make`, and runs `make install`.
   - Does not reinstall when the Redis binary already exists and `safe_install` is `true`.
   - If `package_install` is explicitly overridden to `true`, installs `redis-server` on Debian or `redis` on RHEL and Fedora.
   - Includes `redisio::ulimit`.
   - Resources in the default source-install path: one `build_essential`, one `redisio_install`, and two `include_recipe` resources.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian systems, renders `/etc/pam.d/su` using the configured PAM `su` template source.
   - On Debian systems, deploys the `sudo` cookbook file to `/etc/pam.d/sudo` with mode `0644`.
   - The `node['ulimit']['users']` collection is empty by default; no `user_ulimit` resources are created.
   - Resources on Debian: one `template[/etc/pam.d/su]` and one `cookbook_file[/etc/pam.d/sudo]`.

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the operating-system Redis service to prevent conflicts with the named Redis instance.
   - Disables `redis-server` on Debian.
   - Disables `redis` on RHEL and Fedora.
   - Resources: one `service` resource with `stop` and `disable` actions.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; these recipes have already been visited in the execution graph.
   - Uses `redisio_configure[redis-servers]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Iterations: runs once for Redis instance **6379**.
   - Creates or manages the `redis` user and group.
   - Creates `/etc/redis` with mode `0775`, owner `root`, and group `redis`.
   - Creates `/var/lib/redis` with mode `0775`, owner `redis`, and group `redis`.
   - Creates `/var/run/redis/6379` with mode `0755`, owner `redis`, and group `redis`.
   - Renders `redis.conf.erb` to `/etc/redis/6379.conf`, owned by `redis:redis` with mode `0644`.
     - Render count: 1.
   - Creates `/etc/redis/6379.conf.breadcrumb` when absent. This Chef breadcrumb prevents later converges from overwriting `/etc/redis/6379.conf`.
   - Configures the service definition according to the selected job-control system:
     - Systemd: creates `/etc/tmpfiles.d/redis@6379.conf`, renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`, and immediately runs `systemctl daemon-reload` when the unit changes.
     - Init.d: renders `redis.init.erb` to `/etc/init.d/redis6379`.
     - Upstart: renders `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`.
     - FreeBSD rcinit: renders `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`.
   - Defines `service[redis@6379]` on systemd or `service[redis6379]` on init.d, Upstart, and rcinit hosts.
   - Resources for **6379** on systemd: one `redisio_configure`, one `user`, three `directory`, two `template`, two `file`, one notified `execute`, and one `service`.

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs once for Redis instance **6379**.
   - Adds `start` and `enable` actions to the existing Redis service resource.
   - Enables and starts `redis@6379` on systemd.
   - Enables and starts `redis6379` on init.d, Upstart, and rcinit hosts.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora source-install paths.
- Compiler and build dependencies installed through `build_essential[install build deps]`; exact package names are platform-dependent and are not enumerated in the supplied execution tree.
- `redis-server` on Debian only when `node['redisio']['package_install']` is overridden to `true`.
- `redis` on RHEL and Fedora only when `node['redisio']['package_install']` is overridden to `true`.
- Memcached package selection is encapsulated in the unavailable `memcached_instance` provider implementation.

**Service dependencies**:
- Memcached service represented by `memcached_instance[memcached]`.
- Redis instance service `redis@6379` on systemd.
- Redis instance service `redis6379` on init.d, Upstart, and FreeBSD rcinit.
- Disabled operating-system Redis service `redis-server` on Debian.
- Disabled operating-system Redis service `redis` on RHEL and Fedora.

## Credentials

**Detection Summary**: 1 active credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: Redis instance configuration for port 6379

### Redis Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef attribute override.
- **Usage context**: Rendered as Redis `requirepass` in `/etc/redis/6379.conf` and available to the init.d template for authenticated shutdown operations.
- **Migration requirement**: Store the password in an Ansible Automation Platform credential, approved external secret-manager lookup, or Ansible Vault. Mark tasks that render or pass the secret with `no_log: true`. Do not retain the literal password in playbooks, inventory, role defaults, or templates.

### Conditional Redis Data-Bag Password Capability
- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Conditional Chef `data_bag_item` capability.
- **Usage context**: If all three attributes were configured, the provider would retrieve a data-bag value and assign it to Redis `requirepass` and `masterauth`.
- **Active status**: Inactive. All three related attributes are `nil`; the wrapper supplies the active hardcoded `requirepass`.
- **Migration requirement**: Do not implement this inactive data-bag branch unless environment-specific Chef attributes demonstrate active use.

No Chef Vault, encrypted data bag, CyberArk, Conjur, HashiCorp Vault, AWS Secrets Manager, environment-variable secret lookup, or TLS certificate/key path is configured by the supplied cache wrapper.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/etc/redis`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb` — Chef-only behavior; absence is expected when intentionally not replicated in Ansible.
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts.
- `/lib/systemd/system/redis@6379.service` on systemd hosts.
- `/etc/init.d/redis6379` on init.d hosts.
- `/etc/init/redis6379.conf` on Upstart hosts.
- `/usr/local/etc/rc.d/redis6379` on FreeBSD rcinit hosts.
- `/etc/pam.d/su` and `/etc/pam.d/sudo` on Debian if ulimit compatibility behavior is retained.

**Service endpoints to check**:
- **memcached**:
  - TCP `11211`, bound to `0.0.0.0`.
  - UDP `11211`, bound to `0.0.0.0`.
- **6379**:
  - Redis TCP `6379`.
  - No Unix socket.
  - No TLS port.

**Templates rendered**:
- `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render.
- Systemd only: `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render.
- Init.d only: `redis.init.erb` to `/etc/init.d/redis6379`: 1 render.
- Upstart only: `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: 1 render.
- FreeBSD rcinit only: `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: 1 render.

## Pre-flight checks:
```bash
# ---- Memcached instance: memcached ----

# Verify service state on systemd hosts.
systemctl status memcached
systemctl is-enabled memcached

# Verify the TCP listener on port 11211.
ss -ltnp | grep ':11211'
# Expected: Memcached listening on 0.0.0.0:11211.

# Verify the UDP listener on port 11211.
ss -lunp | grep ':11211'
# Expected: Memcached listening on UDP 0.0.0.0:11211.

# Verify protocol responsiveness and memory configuration.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
# Expected: response beginning with VERSION.

printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | grep -E 'STAT (pid|uptime|curr_connections|limit_maxbytes)'
# Expected: STAT lines; limit_maxbytes should be 67108864.

# ---- Redis instance: 6379 ----

# Verify systemd service state.
systemctl status redis@6379
# Expected: active (running).

systemctl is-enabled redis@6379
# Expected: enabled.

# Verify the Redis TCP listener.
ss -ltnp | grep ':6379'
# Expected: redis-server listening on TCP port 6379.

# Verify authenticated Redis connectivity.
# Set REDIS_PASSWORD securely from an AAP credential or approved secret lookup.
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" PING
# Expected: PONG.

# Verify that unauthenticated access is rejected.
redis-cli -h 127.0.0.1 -p 6379 PING
# Expected: NOAUTH Authentication required.

# Verify required Redis configuration values.
grep -E '^(port|tcp-backlog|databases|syslog-enabled|syslog-facility|requirepass)' /etc/redis/6379.conf
# Expected:
# port 6379
# tcp-backlog 511
# databases 16
# syslog-enabled yes
# syslog-facility local0
# requirepass <configured secret>

# Verify Chef wrapper replication-directive removal if compatibility is retained.
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
# Expected: no output.

# Verify Redis directories and permissions.
stat -c '%U:%G %a %n' /var/lib/redis /var/run/redis/6379 /var/log/redis
# Expected:
# redis:redis 775 /var/lib/redis
# redis:redis 755 /var/run/redis/6379
# redis:redis 755 /var/log/redis

# Verify Redis runtime information and logical database count.
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" INFO server | grep -E '^(redis_version|process_id|tcp_port):'
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" INFO memory | grep '^used_memory:'
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" CONFIG GET databases
# Expected: databases followed by 16.

# Verify Redis logging on systemd hosts.
journalctl -u redis@6379 -n 100 --no-pager
# Expected: recent startup and runtime messages for Redis instance 6379.

# For init.d, Upstart, or FreeBSD rcinit hosts, use the platform-specific
# service-manager command to verify redis6379 instead of redis@6379.
```