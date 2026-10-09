---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook provisions a cache layer with one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` on all interfaces with 64 MB allocated and a maximum of 1024 connections. Redis listens on port `6379`, uses the hardcoded password `redis_secure_password_123`, and is installed from source as Redis `3.2.11` when the default non-package installation path is active. Redis is managed through RedisIO, with systemd used by default on systemd platforms.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Custom resource: `memcached_instance[memcached]`
  - Location/Path: Service-managed Memcached configuration
  - Port/Socket: TCP and UDP `0.0.0.0:11211`
  - Key Config: 64 MB memory, maximum 1024 connections, maximum object size `1m`, ulimit `1024`, user `service_user`
  - Service actions: Start and enable

- **6379**: Redis cache service managed by RedisIO
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID directory `/var/run/redis/6379`
  - Port/Socket: TCP `6379`; no Unix socket or TLS port configured
  - Key Config: Redis `3.2.11` source installation by default on Debian, RHEL, and Fedora; 16 databases; maximum 10000 clients; RDB persistence; syslog enabled; password `redis_secure_password_123`
  - Redis user/group: `redis:redis`
  - Systemd service: `redis@6379`
  - init.d, upstart, or rcinit service: `redis6379`
  - `replicaservestaledata`: explicitly set to `nil`

## File Structure

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

No static `cookbook_file` artifact is configured. The `redisio::ulimit` recipe conditionally references `/etc/pam.d/sudo`, but its source cookbook is attribute-driven and defaults to `nil`.

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Configures the `memcached` instance with 64 MB memory, TCP and UDP port `11211`, listen address `0.0.0.0`, maximum 1024 connections, maximum object size `1m`, ulimit `1024`, and user `service_user`.
   - Sets the Redis server collection to exactly one item, port `6379`, with `requirepass` set to `redis_secure_password_123` and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]`, removing matching `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` lines from `/etc/redis/6379.conf` when the file exists.
   - Includes `redisio::enable`.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures TCP and UDP port `11211`, address `0.0.0.0`, memory `64`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, and user `service_user`.
   - Starts and enables the Memcached service.
   - The custom resource provider is external to the supplied cookbook artifact listing.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - When `node['redisio']['package_install']` is false, includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]`.
   - When `node['redisio']['bypass_setup']` is false, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - With supplied defaults, `bypass_setup` is false.
   - Debian, RHEL, and Fedora default to source installation; FreeBSD defaults to package installation.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs exactly one prerequisite package on Debian, RHEL, and Fedora:
     - `package[tar]`
   - The package collection is empty on other platforms.

5. **`build_essential[install build deps]`**:
   - Installs the platform build toolchain before source compilation.
   - Is invoked by `redisio::default` and again by `redisio::install` in the source-install path.
   - The exact package list is provider-dependent and is not defined in the supplied execution tree.

6. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - In the package-install branch, installs:
     - Debian: `redis-server`
     - RHEL, Fedora, and FreeBSD: `redis`
   - Package version is unspecified, so the platform package manager selects the current available version.
   - In the source-install branch, includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]`.
   - Downloads `http://download.redis.io/releases//redis-3.2.11.tar.gz`.
   - Invokes `redisio_install[redis-installation]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Extracts the source, runs `make clean && make`, then runs `make install`.
   - Installs Redis binaries under `/usr/local/bin` unless `install_dir` is overridden.
   - Includes `redisio::ulimit`.

7. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian, creates `template[/etc/pam.d/su]` using attribute-driven cookbook and source values.
   - On Debian, creates `cookbook_file[/etc/pam.d/sudo]` with source `sudo` and mode `0644` when a valid source cookbook is configured.
   - The default source cookbook is `nil`.
   - The supplied `users` collection is empty, so no `user_ulimit` resources are created by this recipe by default.

8. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Selects the distribution Redis service name:
     - Debian: `redis-server`
     - RHEL and Fedora: `redis`
   - Stops and disables the selected distribution service.
   - Prevents the distribution Redis service from competing with RedisIO instance `6379`.

9. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Revisits `redisio::default` and `redisio::ulimit`; both are already visited and are not executed again.
   - Processes exactly one Redis instance: `6379`.
   - Invokes `redisio_configure[redis-servers]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Creates the `redis` system user with home `/var/lib/redis`; on Debian its shell is `/bin/false`.
   - Creates `/etc/redis` recursively with owner `root`, group `redis`, and mode `0775`.
   - Creates `/var/lib/redis` recursively with owner and group `redis` and mode `0775`.
   - Creates `/var/run/redis/6379` recursively with owner and group `redis` and mode `0755`.
   - Does not create a separate log directory or log file because `logfile` is `nil`; `/var/log/redis` is created by `cache::default`.
   - Applies RDB file permissions to `/var/lib/redis/dump-6379.rdb` only if the file already exists.
   - Creates `user_ulimit[redis]` with a calculated descriptor limit of `10032`, based on `maxclients=10000` and default ulimit `0`.
   - Renders the Redis configuration once:
     - Source: `redis.conf.erb`
     - Destination: `/etc/redis/6379.conf`
     - Owner/group: `redis:redis`
     - Mode: `0644`
   - Creates `/etc/redis/6379.conf.breadcrumb` by default to prevent repeated configuration rendering.
   - On systemd, creates `/etc/tmpfiles.d/redis@6379.conf`, renders `/lib/systemd/system/redis@6379.service` from `redis@.service.erb`, and schedules `systemctl daemon-reload`.
   - On init.d, renders `/etc/init.d/redis6379` from `redis.init.erb`.
   - On upstart, renders `/etc/init/redis6379.conf` from `redis.upstart.conf.erb`.
   - On FreeBSD rcinit, renders `/usr/local/etc/rc.d/redis6379` from `redis.rcinit.erb`.
   - Creates exactly one Redis service resource:
     - systemd: `service[redis@6379]`
     - init.d, upstart, or rcinit: `service[redis6379]`

10. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Iterates over exactly one Redis instance, `6379`.
    - Starts and enables `redis@6379` on systemd.
    - Starts and enables `redis6379` on init.d, upstart, and rcinit.
    - This is the final service-start operation.

## Dependencies

**External cookbook dependencies**:

- `memcached`
- `redisio`
- `build_essential`
- `user_ulimit`
- Conditional SELinux resources used by the RedisIO configure provider when SELinux is enabled

**System package dependencies**:

- `tar` on Debian, RHEL, and Fedora source-install paths
- `redis-server` on Debian when package installation is enabled
- `redis` on RHEL, Fedora, and FreeBSD when package installation is enabled
- Platform build dependencies provided by `build_essential` for source installation
- Memcached package installation handled by the external `memcached_instance` provider

**Service dependencies**:

- Memcached service, started and enabled by `memcached_instance[memcached]`
- Debian distribution Redis service `redis-server`, stopped and disabled
- RHEL/Fedora distribution Redis service `redis`, stopped and disabled
- RedisIO-managed `redis@6379` on systemd, started and enabled
- RedisIO-managed `redis6379` on init.d, upstart, and rcinit, started and enabled

## Credentials

**Detection Summary**: 1 active credential detected in 1 file. RedisIO also contains an inactive data-bag credential mechanism and unused TLS credential attributes.

**Source**:

- **Provider**: Hardcoded in the wrapper recipe
- **URL**: None
- **Path**: Redis configuration for instance `6379`

### Redis authentication password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**:
  - `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext Chef attribute assignment
- **Usage context**: Passed to the RedisIO configure provider and rendered into `/etc/redis/6379.conf` as `requirepass`.
- **Configured value**: `redis_secure_password_123`
- **Migration guidance**: Store the password in Ansible Vault and provide it to the Redis configuration template through a secret variable. Do not commit the plaintext value to `group_vars`, `host_vars`, or templates.

### Inactive Redis data-bag credential mechanism

- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`, `requirepass`, `masterauth`
- **Source file(s)**:
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb`
- **Current storage**: Potential Chef data-bag lookup
- **Usage context**: If all data-bag attributes are populated, the provider uses the selected value for Redis `requirepass` and `masterauth`.
- **Current status**: Inactive. The configured Redis instance does not set `data_bag_name`, `data_bag_item`, or `data_bag_key`.

### TLS credentials

- **Variable(s)**: `tlscertfile`, `tlskeyfile`, `tlskeyfilepass`, `tlsclientcertfile`, `tlsclientkeyfile`, `tlsclientkeyfilepass`, `tlsdhparamsfile`, `tlscacertfile`, `tlscacertdir`
- **Source file(s)**:
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb`
  - RedisIO configuration provider
- **Current storage**: Attribute-driven file paths and secrets
- **Usage context**: TLS certificate, key, password, and CA configuration if explicitly enabled.
- **Current status**: Inactive. All values default to `nil`; no active certificate or key path was detected.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/redis/`
- `/var/lib/redis/`
- `/var/run/redis/6379/`
- `/var/log/redis/`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd
- `/lib/systemd/system/redis@6379.service` on systemd
- `/etc/init.d/redis6379` on init.d
- `/etc/init/redis6379.conf` on upstart
- `/usr/local/etc/rc.d/redis6379` on FreeBSD rcinit
- `/etc/pam.d/su` on Debian
- `/etc/pam.d/sudo` on Debian when the conditional source is configured

**Service endpoints to check**:

- Memcached instance `memcached`: TCP `0.0.0.0:11211`
- Memcached instance `memcached`: UDP `0.0.0.0:11211`
- Redis instance `6379`: TCP `0.0.0.0:6379` unless the Redis address is overridden
- Redis instance `6379`: no Unix socket
- Redis instance `6379`: no TLS port

**Templates rendered**:

- Redis configuration:
  - Source: `redis.conf.erb`
  - Destination: `/etc/redis/6379.conf`
  - Render count: 1
- Systemd service:
  - Source: `redis@.service.erb`
  - Destination: `/lib/systemd/system/redis@6379.service`
  - Render count: 1 on systemd
- init.d service:
  - Source: `redis.init.erb`
  - Destination: `/etc/init.d/redis6379`
  - Render count: 1 on init.d
- Upstart service:
  - Source: `redis.upstart.conf.erb`
  - Destination: `/etc/init/redis6379.conf`
  - Render count: 1 on upstart
- FreeBSD rcinit service:
  - Source: `redis.rcinit.erb`
  - Destination: `/usr/local/etc/rc.d/redis6379`
  - Render count: 1 on FreeBSD rcinit

The service-manager templates are mutually exclusive; only the template for the selected job-control system is rendered.

## Pre-flight checks

```bash
# Memcached instance: memcached
systemctl status memcached --no-pager
systemctl is-enabled memcached
systemctl is-active memcached
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
lsof -nP -iTCP:11211 -sTCP:LISTEN
printf "stats\r\nquit\r\n" | nc 127.0.0.1 11211
ps aux | grep '[m]emcached'

# Redis instance: 6379
systemctl status redis@6379 --no-pager
systemctl is-enabled redis@6379
systemctl is-active redis@6379
ss -ltnp | grep ':6379'
lsof -nP -iTCP:6379 -sTCP:LISTEN
ps aux | grep '[r]edis-server'
redis-cli -p 6379 -a 'redis_secure_password_123' PING
redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | \
  grep -E 'redis_version|tcp_port|process_id'
redis-cli -p 6379 PING
grep -E '^(port|requirepass|databases|maxclients|dir|pidfile|loglevel|syslog-enabled)' \
  /etc/redis/6379.conf

# Redis instance: 6379 directories and service files
ls -ld /etc/redis
ls -ld /var/lib/redis
ls -ld /var/run/redis/6379
ls -ld /var/log/redis
cat /etc/tmpfiles.d/redis@6379.conf
cat /lib/systemd/system/redis@6379.service
systemctl daemon-reload
systemctl show redis@6379 --property=ActiveState,SubState,FragmentPath

# Redis instance: 6379 configuration cleanup
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf

# Distribution Redis service status on Debian
systemctl is-enabled redis-server || true
systemctl is-active redis-server || true

# Distribution Redis service status on RHEL/Fedora
systemctl is-enabled redis || true
systemctl is-active redis || true

# Service logs
journalctl -u redis@6379 --no-pager -n 100
journalctl -u memcached --no-pager -n 100
```

Expected results:

- Instance `memcached` is active and enabled.
- Instance `memcached` listens on TCP and UDP port `11211`.
- Memcached reports approximately 64 MB of memory and a maximum connection setting of 1024.
- Instance `6379` is active and enabled under the platform-specific service name.
- Redis listens on TCP port `6379` and runs as user `redis`.
- Authenticated Redis `PING` returns `PONG`.
- Unauthenticated `redis-cli -p 6379 PING` returns an authentication error.
- `/etc/redis/6379.conf` contains port `6379`, the configured password, and the expected directory, PID, database, client, logging, and persistence settings.
- No matching obsolete replication or client-buffer configuration lines remain after `fix_redis_config`.
- `/var/lib/redis` and `/var/run/redis/6379` have the expected `redis:redis` ownership.
- The distribution-provided Redis service is stopped and disabled.
- Only the RedisIO-managed instance `6379` provides the Redis listener on port `6379`.
- On non-systemd platforms, inspect the platform-specific Redis service and log locations instead of assuming systemd commands or journal entries are available.