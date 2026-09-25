---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: the `memcached` instance and Redis instance `6379`. Memcached listens on TCP and UDP port `11211` with 64 MB memory and 1,024 maximum connections. Redis `3.2.11` is built from source by default on Ubuntu/CentOS, listens on TCP port `6379`, runs as systemd service `redis@6379`, uses RDB persistence, and is protected by a hardcoded Redis password. The migration must preserve the Chef sequence: install and start Memcached, create Redis logging, install Redis prerequisites and source build dependencies, build Redis, disable the OS Redis service, configure Redis instance `6379`, remove incompatible Redis directives, and enable/start `redis@6379`.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached in-memory cache service.
  - Location/Path: Log path `/var/log/memcached`
  - Port/Socket: TCP `11211`; UDP `11211`; listen address `0.0.0.0`
  - Key Config: Memory `64` MB; maximum connections `1024`; maximum object size `1m`; file-descriptor ulimit `1024`; enabled and started by `memcached_instance[memcached]`.

- **6379**: Redis persistent key-value cache instance.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11`; service `redis@6379`; user/group `redis:redis`; configuration directory `/etc/redis`; RDB persistence with default dump file `/var/lib/redis/dump-6379.rdb`; `maxclients 10000`; `tcp-backlog 511`; `databases 16`; syslog enabled with facility `local0`; authentication configured with `requirepass redis_secure_password_123`.
  - Compatibility cleanup: The following directives are removed from `/etc/redis/6379.conf` after configuration:
    - `replica-serve-stale-data`
    - `replica-read-only`
    - `repl-ping-replica-period`
    - `client-output-buffer-limit`
    - `replica-priority`

## File Structure

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
redis.conf.erb
redis@.service.erb
Debian PAM su template

Attributes:
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Defines exactly one Redis server instance: **6379**.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Executes `ruby_block[fix_redis_config]` after Redis configuration.
   - Reads `/etc/redis/6379.conf` only if the file exists, removes the five Redis replication/client-buffer directives, and writes the modified content back to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `include_recipe` (3), `directory` (1), `ruby_block` (1).

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource `memcached_instance[memcached]`.
   - Configures the named instance **memcached** with memory `64` MB, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, and ulimit `1024`.
   - Requests service actions `start` and `enable`.
   - Resources: `memcached_instance` custom resource (1).

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `redisio['package_install']` is `false` by default on Ubuntu/CentOS, includes `redisio::_install_prereqs` and uses `build_essential[install build deps]`.
   - Because `redisio['bypass_setup']` is `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Resources: `apt_update` (1), `build_essential` custom resource (1), `include_recipe` (4).

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Determines prerequisite packages by platform family.
   - On Debian, RHEL, and Fedora, installs the explicit prerequisite package **tar**.
   - Resources: `package` (1).

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - The package-install branch is not the default Ubuntu/CentOS path. If explicitly enabled, it installs `redis-server` on Debian or `redis` on RHEL/Fedora.
   - On the default source-install path, includes `redisio::_install_prereqs` again; Chef prevents duplicate recipe convergence.
   - Uses `build_essential[install build deps]`.
   - Uses `redisio_install[redis-installation]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Unpacks the Redis source tarball, runs `make clean && make`, and runs `make install`.
   - Uses safe-install behavior that avoids replacement when an existing Redis binary is detected.
   - Includes `redisio::ulimit`.
   - Resources: `build_essential` custom resource (1), `redisio_install` custom resource (1), `include_recipe` (2) on the default source-install path.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders the Debian PAM `su` template to `/etc/pam.d/su`.
   - Deploys cookbook file source `sudo` to `/etc/pam.d/sudo` with mode `0644`.
   - The `ulimit['users']` collection defaults to an empty hash; no `user_ulimit` resources are created with the supplied defaults.
   - Iterations: `user_ulimit` runs **0 times** because no user names are configured.
   - Resources on Debian: `template` (1), `cookbook_file` (1).
   - Resources with supplied defaults for user limits: `user_ulimit` (0).

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the operating-system Redis service to prevent conflicts with Redis instance **6379**.
   - Stops and disables `redis-server` on Ubuntu/Debian.
   - Stops and disables `redis` on CentOS/RHEL/Fedora.
   - Resources: `service` (1), actions `stop` and `disable`.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; both recipes have already been visited in the execution chain.
   - Uses `redisio_configure[redis-servers]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Iterations: runs **1 time** for Redis instance **6379**.
   - For instance **6379**:
     - Creates system user `redis` with home `/var/lib/redis`.
     - Creates `/etc/redis` with mode `0775`.
     - Creates `/var/lib/redis` owned by `redis:redis` with mode `0775`.
     - Creates `/var/run/redis/6379` owned by `redis:redis` with mode `0755`.
     - Renders `redis.conf.erb` to `/etc/redis/6379.conf`.
     - Creates `/etc/redis/6379.conf.breadcrumb` if missing, preventing subsequent Chef runs from overwriting the configuration while breadcrumb behavior is enabled.
     - On systemd hosts, creates `/etc/tmpfiles.d/redis@6379.conf`.
     - On systemd hosts, renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
     - Runs `systemctl daemon-reload` immediately when `/lib/systemd/system/redis@6379.service` changes.
     - Defines service resource `redis@6379` with start, stop, restart, and status support.
   - The systemd unit runs `/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no` as `redis:redis`, sets `LimitNOFILE` from Redis descriptor calculations, and is enabled under `multi-user.target`.
   - Resources for instance **6379** under the systemd branch: `user` (1), `directory` (3), `template` (2), `file` (2), `execute` (1, delayed until notified), `service` (1).

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs **1 time** for Redis instance **6379**.
   - Resolves `service[redis@6379]`.
   - Adds `start` and `enable` actions to service `redis@6379`.
   - Resources: modifies existing `service[redis@6379]` (1).

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar`
- Compiler and build dependencies supplied by the Chef `build_essential` custom resource; exact package names vary by operating system and must be selected by distribution in Ansible.
- Optional package-install alternative only when source installation is intentionally not preserved:
  - Ubuntu/Debian: `redis-server`
  - CentOS/RHEL/Fedora: `redis`

**Service dependencies**:
- Memcached service managed by `memcached_instance[memcached]`
- OS Redis service stopped and disabled:
  - `redis-server` on Debian/Ubuntu
  - `redis` on RHEL/Fedora
- Redis per-instance systemd service enabled and started: `redis@6379`

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Client Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef recipe attribute value
- **Usage context**: Written as Redis `requirepass` in `/etc/redis/6379.conf`; clients must authenticate before executing protected Redis commands.
- **Current value**: `redis_secure_password_123`

The migration must not store `redis_secure_password_123` in Git, group variables, or plaintext inventory. Store the value in an AAP credential, Ansible Vault, or an approved external secret manager. Apply `no_log: true` to configuration-rendering tasks where practical.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/var/log/memcached`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf`
- `/lib/systemd/system/redis@6379.service`
- `/var/lib/redis/dump-6379.rdb` after Redis performs an RDB save
- `/etc/pam.d/su` on Debian-family hosts
- `/etc/pam.d/sudo` on Debian-family hosts

**Service endpoints to check**:
- Memcached instance `memcached` TCP endpoint: `0.0.0.0:11211`
- Memcached instance `memcached` UDP endpoint: `0.0.0.0:11211`
- Redis instance `6379` TCP endpoint: `:6379`
- Redis instance `6379` Unix socket: none configured
- Redis instance `6379` bind address: no explicit bind address is configured; validate the rendered configuration and actual listener before exposing the host to untrusted networks.

**Templates rendered**:
- Redis server configuration template `redis.conf.erb` to `/etc/redis/6379.conf`: **1 render**
- Systemd Redis unit template `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: **1 render** on systemd hosts
- Debian PAM `su` template to `/etc/pam.d/su`: **1 render** on Debian-family hosts

## Pre-flight checks:
```bash
# Confirm the declared source-build version before migration.
# Expected: Redis server v=3.2.11, subject to existing host drift.
redis-server -v

# Memcached named instance: memcached.
# Expected: active, enabled, and listening on TCP/UDP port 11211.
systemctl status memcached --no-pager
systemctl is-enabled memcached
pgrep -a memcached
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

# Memcached TCP health checks for named instance memcached.
# Expected: VERSION response and STAT output.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | head -20

# Redis named instance: 6379.
# Expected: active, enabled, and listening on TCP port 6379.
systemctl status redis@6379 --no-pager
systemctl is-enabled redis@6379
pgrep -a redis-server
ss -ltnp | grep ':6379'

# Redis authentication and connectivity for named instance 6379.
# Replace REDIS_PASSWORD with an AAP-injected secret during automated validation.
# Expected: PONG.
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 PING

# Redis runtime configuration for named instance 6379.
# Expected: port=6379, databases=16, tcp-backlog=511, maxclients=10000.
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET port
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET databases
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET tcp-backlog
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET maxclients
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 INFO persistence
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 INFO replication

# Validate the Redis instance 6379 configuration and compatibility cleanup.
test -f /etc/redis/6379.conf
grep -E '^(port|databases|tcp-backlog|maxclients|requirepass|dir|dbfilename|syslog-enabled)' /etc/redis/6379.conf
! grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf

# Validate generated systemd files for named instance 6379.
systemctl daemon-reload
systemctl cat redis@6379
systemctl show redis@6379 --property=User,Group,LimitNOFILE,ActiveState,SubState

# Validate expected directories, ownership, and persistence location.
stat -c '%n %U:%G %a' /var/log/redis /etc/redis /var/lib/redis /var/run/redis/6379
ls -ld /var/log/memcached
ls -l /etc/redis/6379.conf /etc/redis/6379.conf.breadcrumb
test -f /etc/tmpfiles.d/redis@6379.conf
test -f /lib/systemd/system/redis@6379.service
df -h /var/lib/redis

# Validate Debian-family PAM files when applicable.
test -f /etc/pam.d/su
test -f /etc/pam.d/sudo

# Check service logs for both named instances.
journalctl -u memcached -n 100 --no-pager
journalctl -u redis@6379 -n 100 --no-pager

# Confirm the OS Redis service remains disabled and cannot conflict.
# Debian/Ubuntu:
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true

# RHEL/Fedora:
systemctl is-enabled redis 2>/dev/null || true
systemctl is-active redis 2>/dev/null || true
```