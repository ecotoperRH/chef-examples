---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook provisions two cache services on one host: the Memcached instance `memcached` and the Redis instance `6379`. Memcached listens on TCP and UDP port `11211` on all interfaces and is configured with 64 MB of memory, 1024 maximum connections, and a 1 MB maximum object size. Redis listens on TCP port `6379`, uses `/var/lib/redis` for data, and requires a configured authentication password. Redis is installed, configured, and enabled through the `redisio` dependency. A Ruby block removes selected replication-related directives from `/etc/redis/6379.conf` after configuration and before the Redis service is enabled.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **`memcached`**: Memcached cache service
  - Location/Path: Service-managed configuration; the Memcached custom-resource implementation is not included in the analyzed provider files
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: 64 MB memory, 1024 maximum connections, 1 MB maximum object size, `service_user`, ulimit `1024`, empty experimental and additional CLI options, value of `node['memcached']['threads']` for threads
  - Actions: Start and enable the service
  - Provider status: `memcached_instance` implementation is external or unavailable in the supplied analysis; only the resource arguments and actions are verified

- **`6379`**: Redis server instance
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID directory `/var/run/redis/6379`; logs use syslog by default
  - Port/Socket: TCP `6379`; no Unix socket; TLS port unset
  - Service: `redis@6379` under systemd, or `redis6379` under init.d, upstart, or rcinit
  - Key Config: `requirepass` set to the configured Redis password, 16 databases, 10,000 maximum clients, RDB persistence defaults, `notice` log level, syslog enabled with facility `local0`, cluster disabled, no replication master, and no ACL file
  - Redis user and group: `redis`
  - Redis descriptor limit: `10032`, calculated from `maxclients 10000 + 32`
  - Actions: Start and enable the service

## File Structure

**MANDATORY: Preserve this section from the original plan.**

Only executable Ruby files shown in the supplied execution tree are included below. Files listed in the directory listing but not present in the execution tree are intentionally excluded.

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

**Templates:**

The execution tree contains no template file entries. The Redis configure provider references conditional templates, but those template files are not included in the required executable Ruby-file structure listing.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

**Files:**

No static files are listed in the supplied execution tree. However, `redisio::ulimit` conditionally deploys `/etc/pam.d/sudo` with a `cookbook_file` resource on Debian-family platforms when its dynamic source and cookbook attributes are configured. The source filename and source cookbook are not available in the analyzed file structure. The same recipe renders `/etc/pam.d/su` from a dynamically selected template on Debian-family platforms.

The supplied file structure lists 12 files: 9 recipes, 2 providers, and 2 attribute files, with `cookbooks/cache/recipes/default.rb` included among the recipes. No additional analyzed files are enumerated here.

## Module Explanation

The cookbook performs operations in this order. Circular includes already visited during execution are not repeated.

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets the keyed Redis server collection entry `node['redisio']['servers']['6379']` with:
     - `port`: `6379`
     - `requirepass`: configured Redis password
     - `replicaservestaledata`: `nil`
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]`.
   - Includes `redisio::enable`.
   - The Ruby block modifies `/etc/redis/6379.conf` when it exists and removes complete lines matching:
     - `replica-serve-stale-data`
     - `replica-read-only`
     - `repl-ping-replica-period`
     - `client-output-buffer-limit`
     - `replica-priority`
   - The cleanup occurs after `redisio::default` configures Redis and before `redisio::enable` starts and enables Redis.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates the custom resource `memcached_instance[memcached]`.
   - Configures `memory` from `node['memcached']['memory']`, default `64`.
   - Configures TCP `port` from `node['memcached']['port']`, default `11211`.
   - Configures UDP `udp_port` from `node['memcached']['udp_port']`, default `11211`.
   - Binds to `node['memcached']['listen']`, default `0.0.0.0`.
   - Sets `maxconn` to `node['memcached']['maxconn']`, default `1024`.
   - Sets user to `service_user`.
   - Sets `max_object_size` to `node['memcached']['max_object_size']`, default `1m`.
   - Sets `threads` from `node['memcached']['threads']`; no analyzed default is defined.
   - Uses empty default values for `experimental_options` and `extra_cli_options`.
   - Sets ulimit to `1024`.
   - Starts and enables the Memcached service.
   - The external `memcached_instance` provider is not present in the supplied provider list, so its package, configuration-file, and service-artifact implementation cannot be independently verified.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Evaluates `node['redisio']['package_install']`.
   - When package installation is disabled, includes `redisio::_install_prereqs` and runs `build_essential[install build deps]`.
   - Evaluates `node['redisio']['bypass_setup']`.
   - When bypass is disabled, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Default `bypass_setup` is `false`.
   - Default `package_install` is `false` on Debian, RHEL, and Fedora, and `true` on FreeBSD.
   - Default job control is `systemd` on systemd hosts, `rcinit` on FreeBSD, and `initd` on other platforms.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Calculates `packages_to_install` from the platform family.
   - On Debian, RHEL, and Fedora, the collection contains exactly `tar`.
   - Iterates once over `tar` on those supported Linux platforms.
   - Creates `package[tar]` with action `install`.
   - On unsupported platform families, the package collection is empty.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Selects exactly one installation path based on `node['redisio']['package_install']`.
   - In package mode:
     - Installs `redis-server` on Debian.
     - Installs `redis` on RHEL, Fedora, and FreeBSD.
     - Uses `node['redisio']['version']` when set; the default package version is unset.
   - In source mode:
     - Includes `redisio::_install_prereqs`.
     - Runs `build_essential[install build deps]`.
     - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
     - Creates an extraction directory and extracts the archive with `tar zxf`.
     - Runs `make clean && make`.
     - Runs `make install`.
     - Uses `PREFIX=<install_dir>` when a custom installation directory is configured.
     - Uses the custom resource `redisio_install[redis-installation]`.
   - Includes `redisio::ulimit`.
   - The source-install defaults are mirror `http://download.redis.io/releases/`, base name `redis-`, version `3.2.11`, artifact type `tar.gz`, safe installation enabled, and no custom installation directory.
   - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Package and source branches are mutually exclusive.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family platforms, renders `/etc/pam.d/su` using the dynamically selected `node['ulimit']['pam_su_template_cookbook']`.
   - On Debian-family platforms, conditionally deploys `/etc/pam.d/sudo` using `cookbook_file`.
   - The `/etc/pam.d/sudo` source filename and source cookbook are supplied by:
     - `node['ulimit']['ulimit_overriding_sudo_file_name]`
     - `node['ulimit']['ulimit_overriding_sudo_file_cookbook]`
   - The `/etc/pam.d/sudo` file uses mode `0644`.
   - The analyzed default `node['ulimit']['users']` is an empty `Mash`, so no user-specific `user_ulimit[user]` resources are created by default.
   - If users are supplied, the loop creates one `user_ulimit[user]` resource for each explicitly supplied user.
   - The `user_ulimit` provider is external or unavailable in the supplied provider list; no provider-specific behavior is assumed.
   - The Redis configure provider separately creates `user_ulimit[redis]`.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Determines the distribution Redis service name.
   - Uses `redis-server` on Debian.
   - Uses `redis` on RHEL and Fedora.
   - Creates `service[service_name]` only when a service name is determined.
   - Stops and disables the operating-system default Redis service before managing instance `6379`.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - References `redisio::default` and `redisio::ulimit`; both are circular includes already visited in this execution.
   - Sets `redis_instances` to the Redis server collection.
   - Iterates exactly once over the keyed instance `6379`.
   - The `6379` entry has port `6379`, the configured password, and `replicaservestaledata: nil`.
   - Creates `redisio_configure[redis-servers]`.
   - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Manages the `redis` system user with comment `Redis service account`, home `/var/lib/redis`, managed home enabled, and system-user behavior enabled. The shell is `/bin/false` on Debian and `/bin/sh` on RHEL, Fedora, and FreeBSD.
   - Creates `/etc/redis` recursively with owner `root`, Linux group `redis`, and mode `0775`.
   - Creates `/var/lib/redis` recursively with owner and group `redis`, mode `0775`.
   - Creates `/var/run/redis/6379` recursively with owner and group `redis`, mode `0755`.
   - The provider creates a separate log directory only when a non-stdout logfile is configured. With the analyzed default logfile `nil`, `/var/log/redis` is created by `cache::default`.
   - Creates `user_ulimit[redis]` with descriptor limit `10032`, calculated from `maxclients 10000 + 32` because the configured ulimit is `0`.
   - Renders `/etc/redis/6379.conf` from the selected `redis.conf.erb` template source.
   - The configuration includes port `6379`, the Redis password, data and PID directories, 16 databases, `notice` log level, enabled syslog with facility `local0`, maximum clients `10000`, RDB defaults, replication defaults, AOF defaults, disabled cluster mode, disabled TLS, no Unix socket, no replica master, and no ACL file.
   - Creates `/etc/redis/6379.conf.breadcrumb` containing:
     `This file prevents the chef cookbook from overwritting the redis config more than once`
   - Does not overwrite the configuration template when the breadcrumb already exists.
   - On systemd hosts:
     - Renders `/etc/tmpfiles.d/redis@6379.conf` to create `/var/run/redis/6379`.
     - Defines `execute[systemd reload]` with command `systemctl daemon-reload`.
     - Triggers the reload immediately when the systemd service template changes.
     - Renders `/lib/systemd/system/redis@6379.service` with the Redis binary, user `redis`, group `redis`, and file descriptor limit `10032`.
   - On init.d hosts, renders `/etc/init.d/redis6379` with mode `0755`.
   - On upstart hosts, renders `/etc/init/redis6379.conf` with mode `0644`.
   - On rcinit hosts, renders `/usr/local/etc/rc.d/redis6379` with mode `0755`.
   - Creates one service resource for instance `6379`:
     - systemd: `service[redis@6379]`
     - init.d, upstart, or rcinit: `service[redis6379]`
   - Service actions support start, stop, restart, and status according to the selected service provider.

9. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Reads the Redis server collection.
   - Iterates exactly once over instance `6379`.
   - Looks up `service[redis@6379]` on systemd or `service[redis6379]` on other job-control modes.
   - Mutates the existing service resource to include `start` and `enable`.
   - Starts Redis instance `6379` and enables it at boot.

## Dependencies

**External cookbook dependencies**: `memcached`, `redisio`; `build_essential` and the external ulimit-related custom resources are referenced by dependency cookbooks.

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora source-install paths
- `redis-server` on Debian package-install paths
- `redis` on RHEL, Fedora, and FreeBSD package-install paths
- Compiler and build packages supplied by `build_essential` in source-install mode
- Memcached package dependencies managed by the external `memcached_instance[memcached]` resource

**Service dependencies**:
- Distribution Redis service stopped and disabled:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`
- Managed Redis instance started and enabled:
  - systemd: `redis@6379`
  - init.d/upstart/rcinit: `redis6379`
- Memcached instance `memcached` started and enabled

## Credentials

**Detection Summary**: 1 active hardcoded credential detected in 1 file. An inactive optional Chef data-bag credential mechanism is also present in the Redis provider.

**Source**:
- **Provider**: Hardcoded in the wrapper recipe
- **URL**: None detected
- **Path**: None detected
- **Additional mechanism**: Optional Chef data-bag lookup in the Redis configure provider

### Redis authentication password

- **Variable**: `requirepass` field of the keyed Redis server entry `node['redisio']['servers']['6379']['requirepass']`
- **Source file**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext value
- **Value**: `redis_secure_password_123`
- **Usage context**: Sets Redis authentication for instance `6379` and is passed to the Redis configuration template as `requirepass`.
- **Migration handling**: Replace the plaintext value with an Ansible Vault variable, such as `redis_password`. Do not store the plaintext password in group variables, templates, or task files.

### Optional Redis data-bag password mechanism

- **Variables**: `data_bag_name`, `data_bag_item`, `data_bag_key`, `requirepass`, and `masterauth`
- **Source file**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Chef data bag when all three data-bag attributes are populated
- **Usage context**: The provider retrieves a value from the data bag and assigns it to Redis `requirepass` and `masterauth`.
- **Active status**: Inactive; the analyzed server configuration does not set `data_bag_name`, `data_bag_item`, or `data_bag_key`.

No `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, CyberArk data bag, or environment-variable secret references were detected.

TLS attributes exist but are unset, including `tlscertfile`, `tlskeyfile`, `tlskeyfilepass`, `tlsclientcertfile`, `tlsclientkeyfile`, `tlsclientkeyfilepass`, `tlsdhparamsfile`, `tlscacertfile`, and `tlscacertdir`.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/init.d/redis6379` on init.d hosts
- `/etc/init/redis6379.conf` on upstart hosts
- `/usr/local/etc/rc.d/redis6379` on rcinit hosts
- `/etc/pam.d/su` on Debian-family hosts
- `/etc/pam.d/sudo` on Debian-family hosts when the dynamic `cookbook_file` source is configured
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`

**Service endpoints to check**:
- Memcached instance `memcached`, TCP `0.0.0.0:11211`
- Memcached instance `memcached`, UDP `0.0.0.0:11211`
- Redis instance `6379`, TCP port `6379`
- Unix sockets: none
- Redis TLS port: none

**Templates rendered**:
- Memcached configuration and service artifacts: implementation unavailable or unverified because the external `memcached_instance[memcached]` provider is not included
- Redis configuration: 1 render for `/etc/redis/6379.conf`
- Redis breadcrumb file: 1 file for `/etc/redis/6379.conf.breadcrumb`
- Redis service-management template: 1 render for the selected manager:
  - `/lib/systemd/system/redis@6379.service`
  - `/etc/init.d/redis6379`
  - `/etc/init/redis6379.conf`
  - `/usr/local/etc/rc.d/redis6379`
- Systemd tmpfiles template: 1 render on systemd hosts
- `/etc/pam.d/su`: 1 render on Debian-family hosts
- `/etc/pam.d/sudo`: 1 conditional deployment on Debian-family hosts when its dynamic source and cookbook are configured

## Pre-flight checks:

```bash
# Verify Memcached instance memcached
systemctl status memcached
pgrep -a memcached
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
printf "version\r\n" | nc -w 2 127.0.0.1 11211
printf "stats\r\n" | nc -w 2 127.0.0.1 11211 | head -30

# Verify Redis instance 6379 on systemd
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379
pgrep -a -f 'redis-server.*6379'
ss -ltnp | grep ':6379'

# Verify Redis authentication for instance 6379.
# Supply the password through a protected variable rather than committing it.
redis-cli -p 6379 -a "$REDIS_PASSWORD" PING
redis-cli -p 6379 -a "$REDIS_PASSWORD" INFO server
redis-cli -p 6379 -a "$REDIS_PASSWORD" INFO persistence

# Verify the Redis instance configuration
grep -E '^[[:space:]]*port[[:space:]]+6379' /etc/redis/6379.conf
grep -E '^[[:space:]]*requirepass[[:space:]]+' /etc/redis/6379.conf
grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority' /etc/redis/6379.conf

# The preceding cleanup check should return no matching lines.
# Verify configuration and runtime directories
ls -l /etc/redis/6379.conf /etc/redis/6379.conf.breadcrumb
ls -ld /etc/redis /var/lib/redis /var/run/redis/6379 /var/log/redis
stat -c '%U:%G %a %n' /etc/redis /var/lib/redis /var/run/redis/6379

# Expected ownership:
# /etc/redis: root:redis on Linux
# /var/lib/redis: redis:redis
# /var/run/redis/6379: redis:redis

# Verify the Redis process file descriptor limit
redis_pid="$(pgrep -f 'redis-server.*6379' | head -1)"
test -n "$redis_pid" && cat "/proc/${redis_pid}/limits" | grep -i 'open files'
test -n "$redis_pid" && ps -fp "$redis_pid"

# Expected descriptor limit:
# maxclients 10000 + 32 = 10032

# Verify Redis logs and service startup
journalctl -u redis@6379 --no-pager -n 100
journalctl -u redis@6379 -f

# The default Redis logfile is nil and syslog is enabled, so do not
# require a dedicated Redis log file under /var/log/redis.

# Verify systemd artifacts on systemd hosts
cat /lib/systemd/system/redis@6379.service
cat /etc/tmpfiles.d/redis@6379.conf
systemctl daemon-reload
systemctl list-unit-files | grep 'redis@'
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Verify Debian-family PAM artifacts when configured
test ! -e /etc/pam.d/su || ls -l /etc/pam.d/su
test ! -e /etc/pam.d/sudo || ls -l /etc/pam.d/sudo
```