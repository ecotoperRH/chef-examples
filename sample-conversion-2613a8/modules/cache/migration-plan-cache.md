---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: a Memcached instance named **memcached** listening on TCP/UDP port `11211`, and a Redis instance named **6379** listening on TCP port `6379`. Memcached is started and enabled through `memcached_instance[memcached]`. Redis is installed from the Redis `3.2.11` source tarball by default on Ubuntu/CentOS, configured at `/etc/redis/6379.conf`, protected by a hardcoded `requirepass`, and started/enabled as `redis@6379` on systemd hosts. The wrapper removes five replication-related directives from the generated Redis configuration after configuration.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache daemon.
  - Location/Path: `/var/log/memcached`
  - Port/Socket: `0.0.0.0:11211/TCP` and `0.0.0.0:11211/UDP`
  - Key Config: `64 MB` memory, `1024` maximum connections, `1m` maximum item size, file-descriptor ulimit `1024`; started and enabled by `memcached_instance[memcached]`.

- **6379**: Redis cache server.
  - Location/Path: `/etc/redis/6379.conf`, data directory `/var/lib/redis`, PID directory `/var/run/redis/6379`
  - Port/Socket: `6379/TCP`; no Unix socket, TLS port, or TLS certificate paths configured
  - Key Config: service user/group `redis`, RDB persistence, `16` databases, `10000` maximum clients, TCP backlog `511`, unspecified bind address (`nil`), and `requirepass` configured. On systemd, the service is `redis@6379`; on init.d, Upstart, and rcinit it is `redis6379`.

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

No concrete `.erb` file is listed in the execution tree as rendered. The executed Redis provider dynamically selects the Redis configuration template named by `node['redisio']['redis_config']['template_source']`, whose default value is `redis.conf.erb`, and conditionally uses Redis init/service templates according to the detected init system.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Overrides `node['redisio']['servers']` with the single Redis instance **6379**.
   - Sets Redis instance `6379` to port `6379`, `requirepass=redis_secure_password_123`, and `replicaservestaledata=nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration. If `/etc/redis/6379.conf` exists, it removes all lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
   - Includes `redisio::enable`.
   - Ansible migration: manage `/etc/redis/6379.conf` using a template or use `ansible.builtin.replace` to ensure the five removed directives are absent.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Configures instance **memcached** with `64 MB` memory, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum item size `1m`, and ulimit `1024`.
   - Starts and enables the Memcached service.
   - Ansible migration: install the target platform’s Memcached package and manage the service configuration or systemd override to match the configured command-line options.

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - When `node['redisio']['package_install']` is `false`, which is the default source-installation behavior on Ubuntu/CentOS, includes `redisio::_install_prereqs` and runs `build_essential[install build deps]`.
   - When `node['redisio']['bypass_setup']` is `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs prerequisite package **tar** on Debian, Ubuntu, CentOS, RHEL, and Fedora.
   - Iterations: runs once for package **tar**.
   - Ansible migration: install `tar` with `ansible.builtin.package` before extracting the Redis source archive.

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - In the optional package-install branch, installs `redis-server` on Debian/Ubuntu or `redis` on CentOS/RHEL/Fedora.
   - In the default Ubuntu/CentOS source-install branch:
     - Includes `redisio::_install_prereqs`.
     - Runs `build_essential[install build deps]`.
     - Uses `redisio_install[redis-installation]`.
     - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
     - Extracts the archive, runs `make clean && make`, and runs `make install`.
     - Installs Redis binaries under `/usr/local/bin`.
   - Includes `redisio::ulimit`.
   - Ansible migration: install `tar` and the target platform’s verified C build toolchain before building Redis `3.2.11`, or deliberately adopt the supported OS package after compatibility validation.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family hosts, renders `/etc/pam.d/su`.
   - On Debian-family hosts, deploys `/etc/pam.d/sudo` with mode `0644`.
   - The default `node['ulimit']['users']` collection is empty.
   - Iterations: no `user_ulimit` resources are created because there are no named users in the collection.
   - Ansible migration: retain the PAM changes only when equivalent ulimit behavior is required; no per-user limits are configured by default.

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the default operating-system Redis service to avoid conflict with Redis instance `6379`.
   - Stops and disables `redis-server` on Ubuntu/Debian.
   - Stops and disables `redis` on CentOS/RHEL/Fedora.
   - Ansible migration: disable the appropriate OS service before enabling the Redis instance service.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`, which are already visited in the execution graph.
   - Uses `redisio_configure[redis-servers]` for Redis instance **6379**.
   - Iterations: runs once for Redis instance **6379**.
   - Renders the selected Redis configuration template, `redis.conf.erb` by default, to `/etc/redis/6379.conf`.
   - Creates user and group `redis` if absent.
   - Creates `/etc/redis` with mode `0775`, `/var/lib/redis` with mode `0775`, and `/var/run/redis/6379` with mode `0755`.
   - Uses syslog because `syslogenabled=yes` and `logfile=nil`; no dedicated Redis logfile is created.
   - Creates `/etc/redis/6379.conf.breadcrumb` if absent to prevent later Chef runs from overwriting the configuration.
   - Ansible migration: do not reproduce the Chef breadcrumb mechanism. Manage `/etc/redis/6379.conf` as an Ansible template and notify a Redis restart or reload handler when it changes.
   - For systemd, creates `/etc/tmpfiles.d/redis@6379.conf`, renders `/lib/systemd/system/redis@6379.service`, and declares `redis@6379`.
   - For init.d, renders `/etc/init.d/redis6379` and declares `redis6379`.
   - For Upstart, renders `/etc/init/redis6379.conf` and declares `redis6379`.
   - For rcinit, renders `/usr/local/etc/rc.d/redis6379` and declares `redis6379`.

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs once for Redis instance **6379**.
   - Starts and enables `redis@6379` on systemd.
   - Starts and enables `redis6379` on init.d, Upstart, and rcinit systems.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar` on Debian, Ubuntu, CentOS, RHEL, and Fedora when Redis source installation is selected.
- C build dependencies supplied by `build_essential[install build deps]`; the exact package set is not enumerated in the supplied execution tree and must be verified for the target operating system.
- Optional Redis package-install branch:
  - Ubuntu/Debian: `redis-server`
  - CentOS/RHEL/Fedora: `redis`

**Service dependencies**:
- Memcached service for instance `memcached`.
- Redis instance service `redis@6379` on systemd.
- Redis instance service `redis6379` on init.d, Upstart, and rcinit.
- Default OS Redis service must be stopped and disabled before the per-instance Redis service is enabled:
  - `redis-server` on Ubuntu/Debian
  - `redis` on CentOS/RHEL/Fedora

## Credentials

**Detection Summary**: 1 active credential detected across 1 file. An optional Redis data-bag password mechanism exists in the provider but is not configured by this wrapper.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis `requirepass`
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef attribute value
- **Usage context**: Rendered into `/etc/redis/6379.conf` as the Redis authentication password. The current source value is `redis_secure_password_123`; Redis clients must authenticate before executing protected commands.

### Optional Redis data-bag password mechanism
- **Variable(s)**: `node['redisio']['default_settings']['data_bag_name']`, `node['redisio']['default_settings']['data_bag_item']`, `node['redisio']['default_settings']['data_bag_key']`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Chef `data_bag_item` when all three attributes are configured
- **Usage context**: When configured, assigns the data-bag value to both `requirepass` and `masterauth`.
- **Active in this module**: No. All three attributes are `nil`; the wrapper uses the hardcoded `requirepass`.

Use an Ansible Automation Platform credential, Ansible Vault-encrypted variable file, or approved external secret manager for the migrated Redis password. Do not store it in plaintext inventory, role variables, or templates. Use `no_log: true` on password-bearing configuration tasks and restrict Redis configuration permissions to `0640` or more restrictive where compatible with the Redis service account.

## Checks for the Migration

**Files to verify**:
- `/var/log/memcached`
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/pam.d/su` — Debian-family hosts only
- `/etc/pam.d/sudo` — Debian-family hosts only
- `/etc/tmpfiles.d/redis@6379.conf` — systemd hosts only
- `/lib/systemd/system/redis@6379.service` — systemd hosts only
- `/etc/init.d/redis6379` — init.d hosts only
- `/etc/init/redis6379.conf` — Upstart hosts only
- `/usr/local/etc/rc.d/redis6379` — rcinit hosts only

**Service endpoints to check**:
- **memcached**: `0.0.0.0:11211/TCP` and `0.0.0.0:11211/UDP`
- **Redis instance 6379**: TCP port `6379`; final bind behavior must be verified because the configured bind attribute is unspecified
- **Redis instance 6379 Unix socket**: none configured
- **Redis instance 6379 TLS port**: none configured

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf`
  - Render count: **1**
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` on systemd
  - Render count: **1**
- `redis.init.erb` → `/etc/init.d/redis6379` on init.d
  - Render count: **1**
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf` on Upstart
  - Render count: **1**
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379` on rcinit
  - Render count: **1**
- Debian PAM template → `/etc/pam.d/su`
  - Render count: **1**

## Pre-flight checks:
```bash
# -------------------------------------------------------------------
# Memcached instance: memcached
# -------------------------------------------------------------------

systemctl status memcached
systemctl is-enabled memcached

ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

printf 'version\r\n' | nc -w 3 127.0.0.1 11211

printf 'stats settings\r\n' | nc -w 3 127.0.0.1 11211 | \
  grep -E 'STAT (maxbytes|maxconns|inter|udpport)'

ls -ld /var/log/memcached

# -------------------------------------------------------------------
# Redis instance: 6379
# -------------------------------------------------------------------

# systemd hosts
systemctl status redis@6379
systemctl is-enabled redis@6379

# Verify the conflicting OS Redis service is disabled.
# Ubuntu/Debian:
systemctl is-active redis-server || true
systemctl is-enabled redis-server || true

# CentOS/RHEL/Fedora:
systemctl is-active redis || true
systemctl is-enabled redis || true

ss -ltnp | grep ':6379'
lsof -iTCP:6379 -sTCP:LISTEN

# Set REDIS_PASSWORD from an approved secret source. Do not enter the
# previous hardcoded Chef password into shell history.
redis-cli -h 127.0.0.1 -p 6379 --no-auth-warning -a "$REDIS_PASSWORD" PING

redis-cli -h 127.0.0.1 -p 6379 --no-auth-warning -a "$REDIS_PASSWORD" INFO server | \
  grep -E 'redis_version|process_id|tcp_port'

redis-cli -h 127.0.0.1 -p 6379 --no-auth-warning -a "$REDIS_PASSWORD" CONFIG GET databases
redis-cli -h 127.0.0.1 -p 6379 --no-auth-warning -a "$REDIS_PASSWORD" CONFIG GET maxclients

test -f /etc/redis/6379.conf
grep -E '^(port|requirepass|databases|maxclients|dir|pidfile)' /etc/redis/6379.conf

# These directives must be absent from the final managed configuration.
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf && exit 1 || true

ls -ld /etc/redis /var/lib/redis /var/run/redis/6379 /var/log/redis
stat -c '%U:%G %a %n' /etc/redis/6379.conf /var/lib/redis /var/run/redis/6379

# systemd hosts only
systemctl cat redis@6379
systemd-analyze verify /lib/systemd/system/redis@6379.service
cat /etc/tmpfiles.d/redis@6379.conf
journalctl -u redis@6379 -n 100 --no-pager

ls -lah /var/lib/redis
df -h /var/lib/redis
```