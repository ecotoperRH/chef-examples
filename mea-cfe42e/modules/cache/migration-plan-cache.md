---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services on the same host: Memcached instance `memcached` on TCP and UDP port `11211`, and Redis instance `6379` on TCP port `6379`. Memcached is started and enabled through the `memcached_instance` custom resource. Redis is installed either from packages or Redis source version `3.2.11`, then configured with directories, authentication, service units, ulimit handling, distribution-service disablement, configuration generation, and start/enable operations. The Redis password is hardcoded in `cookbooks/cache/recipes/default.rb` and must be migrated to Ansible Vault, an AAP credential, or another approved secret provider.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **`memcached`**: Memcached caching service
  - Location/Path: Service-managed configuration; exact dependency template paths are not included in the supplied execution tree
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: `64` MB memory, `1024` maximum connections, `1m` maximum object size, default worker-thread attribute, ulimit `1024`, empty experimental and extra-option lists, start and enable actions
  - Service user: Passed as `service_user`; the exact value is not defined in the analyzed files and must be resolved from the dependency or selected explicitly in Ansible

- **`6379`**: Redis caching service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID `/var/run/redis/6379`; logs `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket or TLS port configured
  - Key Config: Redis user and group `redis`; authentication via `requirepass`; source version `3.2.11`; source binary path `/usr/local/bin`; databases `16`; log level `notice`; syslog enabled; maximum clients `10000`; persistence mode `rdb`; protected mode and TLS settings unset
  - Authentication: Currently hardcoded as `redis_secure_password_123`; migrate to an approved secret store
  - Service name: `redis@6379` under systemd, or `redis6379` under initd, Upstart, and FreeBSD rcinit

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
```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
```

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

**Files:**

No static `cookbook_file` source file under `files/default/*` is listed as deployed by the analyzed execution flow. The Redis ulimit recipe references `/etc/pam.d/sudo` through `cookbook_file`, but its source file is not present in the supplied relevant-file list.

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`, which creates the `memcached_instance['memcached']` resource.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Sets the Redis server collection to exactly one instance, `6379`, with port `6379`, `requirepass` set to the configured password, and `replicaservestaledata` set to `nil`.
   - Includes `redisio::default`.
   - Executes `ruby_block[fix_redis_config]` after Redis configuration generation.
   - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from `/etc/redis/6379.conf` when the file exists.
   - Includes `redisio::enable`.
   - Direct resources: one `directory` and one `ruby_block`.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance['memcached']`.
   - Configures memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, and actions `start` and `enable`.
   - Passes the service user as `service_user`.
   - Uses `node['memcached']['threads']`, `node['memcached']['experimental_options']`, and `node['memcached']['extra_cli_options']`.
   - The Ansible implementation must install and configure Memcached before Redis and enable the Memcached service.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - When `node['redisio']['package_install']` is false, includes `redisio::_install_prereqs` and declares `build_essential[install build deps]`.
   - When `node['redisio']['bypass_setup']` is false, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure` in that order.
   - Preserve these conditions in Ansible variables such as `redisio_package_install` and `redisio_bypass_setup`.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Debian, RHEL, and Fedora, iterates over the single prerequisite `tar`.
   - Installs `package[tar]`.
   - The prerequisite list is empty on other platforms.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Package branch runs when `node['redisio']['package_install']` is true.
   - Installs `redis-server` on Debian/Ubuntu.
   - Installs `redis` on RHEL/CentOS/Fedora and FreeBSD.
   - Uses `node['redisio']['version']` when non-null; FreeBSD uses package installation without a forced version by default.
   - Source branch runs when `node['redisio']['package_install']` is false.
   - Includes `redisio::_install_prereqs` and declares `build_essential[install build deps]`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Creates `redisio_install['redis-installation']` using the install provider at `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Extracts `redis-3.2.11`, runs `make clean && make`, and runs `make install`.
   - Uses safe installation and skips rebuilding when the expected version is already installed.
   - Uses the default installation prefix, with the expected source binary path `/usr/local/bin`.
   - Includes `redisio::ulimit`.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, manages `/etc/pam.d/su` using the configured PAM template cookbook.
   - On Debian-family systems, manages `/etc/pam.d/sudo` using the configured cookbook-file source and mode `0644`.
   - The supplied cookbook source variables are unset by default; provide equivalent files in Ansible only after confirming they are required.
   - The default `users` collection is empty, so no user-specific entries are configured by default.
   - If user entries are supplied, the recipe creates one `user_ulimit[user]` resource for each actual configured user; no user names are present in the supplied configuration.
   - The Redis configure provider separately creates `user_ulimit[redis]` with a calculated descriptor limit of `10032`.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Selects `redis-server` as the distribution service on Debian/Ubuntu.
   - Selects `redis` as the distribution service on RHEL/CentOS/Fedora.
   - Stops and disables the selected distribution service.
   - The resource is created only when a supported service name is available.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; already-visited circular references must not be recursively reproduced in Ansible.
   - Resolves exactly one Redis instance: `6379`, port `6379`, no explicit name, configured authentication password, and `replicaservestaledata` set to `nil`.
   - Creates `redisio_configure['redis-servers']` using provider `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Uses base PID directory `/var/run/redis`, Redis version `3.2.11` for source installation, the default settings, and the one-item server collection.
   - Creates the Redis user `redis` with home `/var/lib/redis`, system-user status, managed home, and platform-specific shell: `/bin/false` on Debian/Ubuntu and `/bin/sh` on RHEL/CentOS/Fedora.
   - Creates `/etc/redis` with owner `root`, group `redis` except FreeBSD group `wheel`, mode `0775`, and recursive creation.
   - Creates `/var/lib/redis` with owner and group `redis`, mode `0775`, and recursive creation.
   - Creates `/var/run/redis/6379` with owner and group `redis`, mode `0755`, and recursive creation.
   - When SELinux is enabled, installs SELinux support and applies `redis_conf_t` to `/etc/redis(/.*)?`, `redis_var_lib_t` to `/var/lib/redis(/.*)?`, and `redis_var_run_t` to `/var/run/redis/6379(/.*)?`.
   - Manages `/var/lib/redis/appendonly-6379.aof` conditionally for AOF or existing backup files.
   - Manages `/var/lib/redis/dump-6379.rdb` conditionally for RDB or existing backup files, with owner and group `redis` and mode `0644`.
   - Creates the Redis descriptor limit with `user_ulimit[redis]`; the default calculated limit is `10032`.
   - Renders the Redis configuration once:
     - Source: `redis.conf.erb`
     - Destination: `/etc/redis/6379.conf`
     - Owner/group: `redis:redis`
     - Mode: `0644`
     - Protected by `/etc/redis/6379.conf.breadcrumb`
   - Creates `/etc/redis/6379.conf.breadcrumb` if missing with the cookbook breadcrumb text.
   - On `initd`, renders `redis.init.erb` once to `/etc/init.d/redis6379`, owner/group `root:root`, mode `0755`.
   - On `upstart`, renders `redis.upstart.conf.erb` once to `/etc/init/redis6379.conf`, owner/group `redis:redis`, mode `0644`.
   - On `rcinit`, renders `redis.rcinit.erb` once to `/usr/local/etc/rc.d/redis6379`, owner/group `redis:redis`, mode `0755`.
   - On `systemd`, renders `redis@.service.erb` once to `/lib/systemd/system/redis@6379.service`, owner/group `root:root`, mode `0644`.
   - On `systemd`, creates `/etc/tmpfiles.d/redis@6379.conf` with `d /var/run/redis/6379 0755 redis redis`, mode `0644`.
   - On `systemd`, defines `execute[redis@6379 systemd reload]` with command `systemctl daemon-reload`, initially disabled, and notifies it immediately when the unit template changes.
   - Creates service resource `redis@6379` under systemd and `redis6379` under initd, Upstart, or FreeBSD rcinit.
   - Uses `systemd` as the expected Ubuntu job-control branch when `systemd?` is true.

9. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Processes the single configured Redis instance `6379`.
   - Starts and enables `redis@6379` when job control is `systemd`.
   - Starts and enables `redis6379` under initd, Upstart, or FreeBSD rcinit.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, with no explicit version constraint
- Supported metadata platforms include Ubuntu `>= 18.04` and CentOS `>= 7.0`

**System package dependencies**:
- Memcached package, installed by the Memcached custom resource
- `redis-server` on Debian/Ubuntu when package installation is selected
- `redis` on RHEL/CentOS/Fedora and FreeBSD when package installation is selected
- `tar` for source installation on Debian/Ubuntu, RHEL/CentOS, and Fedora
- Build-essential tooling through `build_essential[install build deps]` for source installation

**Service dependencies**:
- Memcached service for instance `memcached`
- Distribution `redis-server` service on Debian/Ubuntu, stopped and disabled
- Distribution `redis` service on RHEL/CentOS/Fedora, stopped and disabled
- Managed Redis service `redis@6379` under systemd
- Managed Redis service `redis6379` under initd, Upstart, or FreeBSD rcinit

## Credentials

**Detection Summary**: 1 credential detected in 1 file.

**Source**:
- **Provider**: Hardcoded in Chef recipe
- **URL**: None
- **Path**: None

### Redis authentication password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext
- **Value currently configured**: `redis_secure_password_123`
- **Usage context**: Rendered as `requirepass` in `/etc/redis/6379.conf` for Redis instance `6379`
- **Migration storage**: Ansible Vault, an AAP credential, or an approved external secret provider
- **Migration requirements**: Do not place the plaintext value in `defaults/main.yml`, ordinary vars files, or generated logs. Use `no_log: true` on tasks that handle the password directly.

Redis attributes support data-bag-based password retrieval through `data_bag_name`, `data_bag_item`, and `data_bag_key`, but the configured instance does not use those attributes. No data bag item, encrypted data bag item, Chef Vault, CyberArk, Conjur, or environment-variable secret lookup is present. No TLS certificate or private-key paths are configured.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/redis` directory contents
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- `/etc/tmpfiles.d/redis@6379.conf` when systemd is used
- `/lib/systemd/system/redis@6379.service` when systemd is used
- `/etc/init.d/redis6379` when initd is used
- `/etc/init/redis6379.conf` when Upstart is used
- `/usr/local/etc/rc.d/redis6379` when FreeBSD rcinit is used
- `/etc/pam.d/su` on Debian-family systems
- `/etc/pam.d/sudo` on Debian-family systems when the ulimit source is configured
- `/usr/local/bin/redis-server` when source installation is selected

**Service endpoints to check**:
- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis TCP: `0.0.0.0:6379` or the configured Redis bind address
- Redis Unix socket: none
- Redis TLS port: none

**Templates rendered**:
- Memcached configuration and service files: rendered internally by `memcached_instance['memcached']`; exact paths unavailable; count determined by the dependency
- Redis configuration template `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render
- Redis systemd template `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render when `job_control == 'systemd'`
- Redis initd template `redis.init.erb` to `/etc/init.d/redis6379`: 1 render when `job_control == 'initd'`
- Redis Upstart template `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: 1 render when `job_control == 'upstart'`
- Redis FreeBSD template `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: 1 render when `job_control == 'rcinit'`

## Pre-flight checks

Run the instance-specific checks after migration.

### Memcached instance `memcached`

```bash
systemctl status memcached
systemctl is-enabled memcached

ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

printf "version\r\n" | nc -w 2 127.0.0.1 11211
nc -vz 127.0.0.1 11211
```

Expected results:
- The Memcached service is active and enabled.
- TCP port `11211` is listening.
- UDP port `11211` is listening when supported by the platform and implementation.
- The TCP request returns a Memcached version response.

### Redis instance `6379`

```bash
systemctl status redis@6379
systemctl is-enabled redis@6379

systemctl is-active redis-server || true
systemctl is-active redis || true

ss -ltnp | grep ':6379'

grep -E '^(port|dir|pidfile|dbfilename|maxclients|loglevel|syslog-enabled)' \
  /etc/redis/6379.conf

grep -E '^requirepass ' /etc/redis/6379.conf >/dev/null \
  && echo "Redis authentication directive is present"

ls -ld /var/lib/redis
ls -ld /var/run/redis/6379
ls -ld /var/log/redis

test -f /etc/redis/6379.conf.breadcrumb
test -f /lib/systemd/system/redis@6379.service
test -f /etc/tmpfiles.d/redis@6379.conf

redis-cli -h 127.0.0.1 -p 6379 -a '<retrieve-from-Ansible-Vault>' PING
redis-cli -h 127.0.0.1 -p 6379 -a '<retrieve-from-Ansible-Vault>' SET migration_check ok
redis-cli -h 127.0.0.1 -p 6379 -a '<retrieve-from-Ansible-Vault>' GET migration_check
redis-cli -h 127.0.0.1 -p 6379 -a '<retrieve-from-Ansible-Vault>' INFO server

grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf || true

journalctl -u redis@6379 --no-pager -n 100
ps aux | grep '[r]edis-server.*6379'
```

Expected results:
- `redis@6379` is active and enabled under systemd.
- The distribution-provided Redis service is stopped and disabled.
- TCP port `6379` is listening.
- Authenticated `PING` returns `PONG`.
- The write returns `OK` and the read returns `ok`.
- The removed replication and client-buffer directives are absent.
- The Redis process uses `/etc/redis/6379.conf`.

### Configuration and resource checks

```bash
systemctl show redis@6379 | grep -E 'LimitNOFILE|LimitNOFILESoft'

getent passwd redis
getent group redis

df -h /var/lib/redis
df -h /var/log/redis

stat -c '%A %U:%G %n' /var/log/redis
test -f /etc/redis/6379.conf.breadcrumb
```

### Debian-family ulimit files

Run only when the target is Debian or Ubuntu and the corresponding ulimit variables are configured:

```bash
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo
stat -c '%A %U:%G %n' /etc/pam.d/sudo
```

### Source installation checks

Run when `redisio_package_install` is false:

```bash
command -v tar
test -x /usr/local/bin/redis-server
/usr/local/bin/redis-server -v
/usr/local/bin/redis-server -v | grep '3.2.11'
readlink -f "$(command -v redis-server)"
```

The Ansible implementation should install `tar` and build-essential prerequisites before compiling Redis, download and verify the Redis `3.2.11` source archive, install the resulting binaries under `/usr/local/bin`, and verify that the managed Redis service uses the expected source-installed binary. It should preserve safe-install behavior by avoiding an unnecessary rebuild when Redis `3.2.11` is already installed, while still validating the binary version and service configuration after migration.