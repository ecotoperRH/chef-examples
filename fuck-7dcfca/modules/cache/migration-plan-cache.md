---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures one Memcached instance named `memcached` on TCP and UDP port `11211` and one Redis instance named `6379` on TCP port `6379`. Memcached is managed through the `memcached_instance` custom resource. Redis uses the `redisio` cookbook, installs Redis from source by default on Debian/RHEL-family systems, creates `/etc/redis/6379.conf` and the instance service resources, disables the operating system Redis service, and starts and enables the configured instance. The Redis authentication password is hardcoded in `cookbooks/cache/recipes/default.rb` and must be migrated to Ansible Vault or another secret-management system.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached caching service
  - Location/Path: Platform-specific Memcached configuration and log paths
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: `64` MB memory, `1024` maximum connections, `1m` maximum object size, default `node['memcached']['threads']` worker threads, file descriptor limit `1024`, service account `service_user`, empty experimental and additional CLI option lists, started and enabled

- **6379**: Redis caching service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID `/var/run/redis/6379`; configuration directory `/etc/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis user and group `redis`, configuration mode `0644`, `16` databases, `10000` maximum clients, RDB persistence, syslog enabled by default, authentication enabled, TLS and replication source not configured
  - Authentication: Password currently hardcoded as `redis_secure_password_123`
  - Service names: `redis@6379` under systemd; `redis6379` under init.d, Upstart, or rcinit
  - Redis shell: `/bin/false` on Debian-family systems; `/bin/sh` on RHEL/Fedora-family systems
  - Effective defaults reported by the cookbook: `tcpbacklog=511`, `timeout=0`, `keepalive=0`, `loglevel=notice`, `appendfsync=everysec`, `rdbcompression=yes`, `rdbchecksum=yes`, `replicaservestaledata=yes`, `replicareadonly=yes`, `replpingreplicaperiod=10`, `repltimeout=60`, `replbacklogsize=1mb`, `replbacklogttl=3600`, `replicapriority=100`, unset `maxmemory`, unset `maxmemorypolicy`, and unset `protected_mode`

## File Structure

Only Ruby files participating in the execution flow or defining used resources/defaults are listed below. Paths are relative to the repository root.

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

The execution tree does not list template files as executable Ruby files. The recipes and providers render the following template sources:

```text
redis.conf.erb
redis.init.erb
redis.upstart.conf.erb
redis.rcinit.erb
redis@.service.erb
```

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

**Files:**

No static `cookbook_file` source file is identified as an executable file in the provided flow. The `redisio::ulimit` recipe references `/etc/pam.d/sudo` through `cookbook_file`, but its source is controlled by `node['ulimit']['ulimit_overriding_sudo_file_cookbook']` and is not defined in the listed `cache` files.

## Module Explanation

The cookbook performs operations in the following execution order. Attribute-derived defaults below reflect the supplied migration plan; the contents of the two attribute files were not included in the structured validation results.

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to one Redis server with port `6379`, `requirepass` `redis_secure_password_123`, and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` owned by `redis:redis` with mode `0755`.
   - Includes `redisio::default`.
   - Creates `ruby_block['fix_redis_config']`, which removes `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` lines from `/etc/redis/6379.conf` when the file exists.
   - Includes `redisio::enable`.
   - Declares one `directory`, one `ruby_block`, and three `include_recipe` resources.
   - The cleanup block does not explicitly notify or restart Redis.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Invokes exactly one `memcached_instance['memcached']` custom resource.
   - Configures memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, service user `service_user`, maximum object size `1m`, default configured threads, empty experimental options, empty additional CLI options, and ulimit `1024`.
   - Applies `start` and `enable` actions.
   - The implementation details and provider of `memcached_instance` were not included in the supplied provider analysis.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update['apt_update']`.
   - On the reported Debian/RHEL defaults, where `package_install=false`, includes `_install_prereqs` and invokes `build_essential['install build deps']`.
   - Since `bypass_setup=false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - FreeBSD is reported to use `package_install=true`.
   - The exact `build_essential` package set was not included in the supplied analysis.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs the `tar` package on Debian-family and RHEL/Fedora-family systems.
   - May be reached from both `redisio::default` and `redisio::install`; Ansible should model this idempotently.

5. **`build_essential['install build deps']`**:
   - Invokes the external `build_essential` custom resource in the source-install path.
   - Installs platform-specific compiler and Redis build dependencies.
   - The custom resource provider and exact package list were not included in the supplied analysis.

6. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses a package-install branch when `node['redisio']['package_install']` is true.
   - The package branch uses `redis-server` on Debian-family systems and `redis` on RHEL/Fedora-family and FreeBSD systems.
   - With the reported Debian/RHEL defaults, uses the source-install branch.
   - Includes `_install_prereqs` and invokes `build_essential['install build deps']`.
   - Downloads `http://download.redis.io/releases//redis-3.2.11.tar.gz`.
   - Invokes `redisio_install['redis-installation']`, which downloads, extracts into `redis-3.2.11`, runs `make clean && make`, and runs `make install` under the default prefix.
   - Safe installation avoids reinstalling an already available requested version.
   - Includes `redisio::ulimit`.
   - Uses provider `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.

7. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `/etc/pam.d/su` and manages `/etc/pam.d/sudo`.
   - `/etc/pam.d/sudo` uses a source controlled by `node['ulimit']['ulimit_overriding_sudo_file_cookbook']` and defaults to source name `sudo`.
   - The reported `node['ulimit']['users']` collection is empty, so no named `user_ulimit` resources are created by default.
   - The external template and `cookbook_file` sources were not included in the listed files.

8. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables `redis-server` on Debian-family systems.
   - Stops and disables `redis` on RHEL/Fedora-family systems.
   - Skips the resource on unsupported platforms without a calculated service name.

9. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes already visited `redisio::default` and `redisio::ulimit`.
   - Expands the configured server collection once for Redis instance `6379`.
   - Invokes `redisio_configure['redis-servers']` with Redis version `3.2.11`, the default settings, the one-item server collection, and base PID directory `/var/run/redis`.
   - Creates or manages user `redis`, home `/var/lib/redis`, and the platform-specific shell.
   - Creates `/etc/redis` with mode `0775`, `/var/lib/redis` with mode `0775`, and `/var/run/redis/6379` with mode `0755`.
   - May create SELinux contexts when SELinux is enabled.
   - Manages conditional log, RDB, and AOF files.
   - Creates a `user_ulimit` resource for `redis` on non-FreeBSD systems, using `10032` when the configured ulimit is zero and otherwise the larger of the configured ulimit and `maxclients`.
   - Renders `redis.conf.erb` once to `/etc/redis/6379.conf`, owned by `redis:redis`, mode `0644`.
   - May create `/etc/redis/6379.conf.breadcrumb`; an existing breadcrumb prevents subsequent main configuration rendering.
   - On systemd, creates `/etc/tmpfiles.d/redis@6379.conf` and `/lib/systemd/system/redis@6379.service`, and declares `execute['redis@6379 systemd reload']`.
   - On init.d, renders `/etc/init.d/redis6379`.
   - On Upstart, renders `/etc/init/redis6379.conf`.
   - On FreeBSD rcinit, renders `/usr/local/etc/rc.d/redis6379`.
   - Uses provider `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - The supplied analysis confirms the Redis provider but does not independently verify the external `user_ulimit` or SELinux providers.

10. **Service-resource loop in `redisio::configure`**:
    - Expands once for instance `6379`.
    - Declares `service['redis@6379']` for systemd.
    - Declares `service['redis6379']` for init.d, Upstart, and rcinit.
    - Sets `node.override['redisio']['servers']` to preserve the one configured instance for the enable step.

11. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Expands once for Redis instance `6379`.
    - Adds `start` and `enable` actions to the previously declared service.
    - Enables `redis@6379` under systemd or `redis6379` under other supported service managers.

## Dependencies

**External cookbook dependencies**:

- `memcached`, version constraint `~> 6.0`
- `redisio`
- `build-essential` functionality through `build_essential`
- Ulimit functionality through `user_ulimit`
- SELinux resources when SELinux is enabled

The supplied analysis explicitly identifies the two `redisio` providers listed in the File Structure. Providers for `memcached_instance`, `build_essential`, and `user_ulimit` were not included in the analyzed provider results.

**System package dependencies**:

- `tar`
- Platform-specific Redis build dependencies supplied by `build_essential`
- `redis-server` on Debian-family systems when package installation is selected
- `redis` on RHEL/Fedora-family systems when package installation is selected
- Memcached packages installed by the `memcached_instance` custom resource

**Service dependencies**:

- Memcached service, instance name `memcached`
- Redis service, instance name `redis@6379` under systemd or `redis6379` under other supported service managers
- The OS-provided `redis-server` or `redis` service is stopped and disabled before the Redis instance is enabled

## Credentials

**Detection Summary**: 1 active credential detected in 1 file. Additional data-bag and TLS mechanisms are reported by the migration plan but were not independently verifiable from the supplied structured attribute/provider analysis.

**Source**:

- **Provider**: Hardcoded in Chef recipe
- **URL**: None
- **Path**: None

### Redis authentication password

- **Variable**: `node['redisio']['servers'][0]['requirepass']`
- **Source file**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext
- **Value currently configured**: `redis_secure_password_123`
- **Usage context**: Rendered as `requirepass` in `/etc/redis/6379.conf`, enabling client authentication on Redis port `6379`
- **Ansible migration**: Store as an Ansible Vault variable such as `redis_requirepass` and render it with controlled permissions. Do not commit the plaintext value to inventory or an ordinary variable file.

### Dormant Redis data-bag password mechanism

- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`
- **Source file**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Reported as a Chef data bag when all three values are configured
- **Usage context**: Reported to populate `requirepass` and `masterauth`
- **Status**: Reported inactive because the supplied plan states that all three values are unset; this status requires confirmation from the provider and attribute contents

### Dormant Redis TLS credential attributes

- **Variable(s)**: `tlscertfile`, `tlskeyfile`, `tlskeyfilepass`, `tlsclientcertfile`, `tlsclientkeyfile`, `tlsclientkeyfilepass`, `tlsdhparamsfile`, `tlscacertfile`, `tlscacertdir`
- **Source file**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb`
- **Current storage**: Reported as unset attribute values
- **Usage context**: Passed to the Redis configuration template when TLS is enabled
- **Status**: Reported inactive; no TLS certificate, key, or TLS password is configured in the supplied plan. This status requires confirmation from the attribute analysis.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/redis`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd systems
- `/lib/systemd/system/redis@6379.service` on systemd systems
- `/etc/init.d/redis6379` on init.d systems
- `/etc/init/redis6379.conf` on Upstart systems
- `/usr/local/etc/rc.d/redis6379` on FreeBSD systems
- `/var/lib/redis/dump-6379.rdb` when RDB persistence creates it
- `/var/lib/redis/appendonly-6379.aof` when AOF persistence is enabled
- Memcached platform-specific configuration and `/var/log/memcached`

**Service endpoints to check**:

- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis TCP: `0.0.0.0:6379` or the effective Redis bind address
- Redis Unix socket: none configured

**Templates rendered**:

- `redis.conf.erb` → `/etc/redis/6379.conf`: 1 render
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: 1 render when `job_control == 'systemd'`
- `redis.init.erb` → `/etc/init.d/redis6379`: 1 render when `job_control == 'initd'`
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`: 1 render when `job_control == 'upstart'`
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`: 1 render when `job_control == 'rcinit'`
- `/etc/pam.d/su` template: 1 render on Debian-family systems when the configured ulimit cookbook source is valid

## Pre-flight checks

### Memcached: instance `memcached`

```bash
# Service status
systemctl status memcached

# Process verification
ps aux | grep '[m]emcached'

# TCP listener verification
ss -ltnp | grep ':11211'
netstat -ltnp | grep ':11211'

# UDP listener verification
ss -lunp | grep ':11211'
netstat -lunp | grep ':11211'

# Basic protocol check
printf "version\r\nquit\r\n" | nc -w 2 127.0.0.1 11211

# Expected result:
# VERSION <version>

# Configuration and process arguments
ps -ef | grep '[m]emcached'

# Log directory
ls -ld /var/log/memcached
```

### Redis: instance `6379`

```bash
# Service status on systemd systems
systemctl status redis@6379

# Service status on init.d-compatible systems
systemctl status redis6379

# Process verification
ps aux | grep '[r]edis-server'

# TCP listener verification
ss -ltnp | grep ':6379'
netstat -ltnp | grep ':6379'
lsof -iTCP:6379 -sTCP:LISTEN

# Configuration file verification
test -f /etc/redis/6379.conf
grep -E '^(port|requirepass|dir|pidfile|databases|maxclients)' /etc/redis/6379.conf

# Verify authentication without exposing the password in shell history.
# Supply the Ansible Vault-managed password through an environment variable.
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" PING

# Expected result:
# PONG

# Authenticated information query
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" INFO server

# Verify the configured Redis port
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" CONFIG GET port

# Verify the instance data and PID directories
ls -ld /var/lib/redis
ls -ld /var/run/redis/6379

# Verify the Redis user and permissions
id redis
stat -c '%U:%G %a %n' /etc/redis/6379.conf
stat -c '%U:%G %a %n' /var/lib/redis
stat -c '%U:%G %a %n' /var/run/redis/6379

# Verify the post-configuration cleanup
if grep -Eq '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf; then
  echo "Unexpected replication-related directive remains"
  exit 1
fi

# Verify the systemd unit when applicable
systemctl is-enabled redis@6379
systemctl is-active redis@6379
```
