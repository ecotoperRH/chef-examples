---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook provisions two cache services: a Memcached instance named `memcached` and a Redis instance named `6379`. Memcached is started and enabled with its default configuration on TCP and UDP port `11211`. Redis `3.2.11` is built from source by default, configured at `/etc/redis/6379.conf`, protected with a hardcoded `requirepass`, and started and enabled as `redis@6379` on systemd hosts.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache service.
  - Location/Path: Log path attribute `/var/log/memcached`
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: `64` MB memory, maximum `1024` connections, maximum object size `1m`, file-descriptor limit `1024`, no experimental or extra CLI options, started and enabled. Thread count is passed from `node['memcached']['threads']` but is not explicitly set in the available attributes.

- **6379**: Redis cache service instance.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`
  - Port/Socket: TCP port `6379`; no Unix socket; no TLS port
  - Key Config: Redis `3.2.11` source installation from `http://download.redis.io/releases/redis-3.2.11.tar.gz`, user/group `redis:redis`, RDB persistence save points `900 1`, `300 10`, and `60 10000`, `maxclients 10000`, TCP backlog `511`, `16` databases, syslog enabled with facility `local0`, `appendfsync everysec`, and authentication through `requirepass`. No explicit Redis `bind` directive is configured. The service is `redis@6379` on systemd hosts and `redis6379` on non-systemd job-control implementations.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb

Attributes:
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Replaces `node['redisio']['servers']` with the single Redis instance **6379**:
     - Port: `6379`
     - Authentication: hardcoded `requirepass`
     - `replicaservestaledata`: `nil`
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` when the file exists.
     - Removes complete lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the modified configuration back to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `directory` (1), `ruby_block` (1), and `include_recipe` (3).
   - Ansible migration implementation must render the Redis configuration before removing the five directives with anchored replacements and before starting Redis.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Configures instance **memcached** with memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, file-descriptor limit `1024`, no experimental options, and no extra CLI options.
   - Uses the dependency-defined service user.
   - Starts and enables Memcached.
   - Resources: `memcached_instance` custom resource (1).
   - The custom-resource provider is not included in the execution tree; the migration must install the target-platform Memcached package and directly configure the equivalent service behavior.

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Uses the source-install path because `node['redisio']['package_install']` defaults to `false` on Debian and RHEL-family systems.
   - Includes `redisio::_install_prereqs`.
   - Uses `build_essential[install build deps]`.
   - Includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Resources: `apt_update` (1), `build_essential` custom resource (1), and `include_recipe` (5, including nested setup recipes).

4. **_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs package **tar** on Debian, RHEL, and Fedora.
   - Iterations: 1 iteration for package **tar**.
   - Resources: `package` (1).

5. **install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Takes the source-install branch because `node['redisio']['package_install']` is `false`.
   - Includes `redisio::_install_prereqs`, already visited by the parent dependency flow.
   - Uses `build_essential[install build deps]`.
   - Uses `redisio_install[redis-installation]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Builds Redis with `make clean && make`.
   - Installs Redis with `make install`.
   - Avoids rebuilding when Redis is already installed.
   - Installs the Redis executable at `/usr/local/bin/redis-server`.
   - Includes `redisio::ulimit`.
   - Resources: `build_essential` custom resource (1), `redisio_install` custom resource (1), and `include_recipe` (2).
   - If `node['redisio']['package_install']` is explicitly changed to `true`, installs `redis-server` on Debian or `redis` on RHEL/Fedora; no package version is specified in that branch.

6. **ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders a template to `/etc/pam.d/su`.
   - Deploys a cookbook file to `/etc/pam.d/sudo` with mode `0644`.
   - Does not create `user_ulimit` resources because `node['ulimit']['users']` defaults to an empty hash.
   - Resources on Debian: `template` (1), `cookbook_file` (1), and `user_ulimit` (0).
   - The source content for `/etc/pam.d/su` and `/etc/pam.d/sudo` is not available in the execution tree. Do not replace these PAM files during migration without separately obtaining and reviewing the original artifacts.

7. **disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - On Debian, stops and disables the `redis-server` service.
   - On RHEL and Fedora, stops and disables the `redis` service.
   - Resources: `service` (1).
   - The distribution Redis service must be stopped and disabled before the source-built Redis instance **6379** is enabled.

8. **configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; both recipes were already visited by the dependency flow.
   - Uses `redisio_configure[redis-servers]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Iterations: 1 iteration for Redis instance **6379**.
   - Creates the `redis` system user with home directory `/var/lib/redis`.
   - Creates `/etc/redis` as `root:redis` with mode `0775`.
   - Creates `/var/lib/redis` as `redis:redis` with mode `0775`.
   - Creates `/var/run/redis/6379` as `redis:redis` with mode `0755`.
   - Renders `redis.conf.erb` to `/etc/redis/6379.conf` as `redis:redis` with mode `0644`.
   - Creates `/etc/redis/6379.conf.breadcrumb` when absent to prevent subsequent Chef converges from overwriting the generated configuration.
   - For the effective systemd path:
     - Creates `/etc/tmpfiles.d/redis@6379.conf`.
     - Renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
     - Configures the unit to run `/usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no`.
     - Configures `User=redis`, `Group=redis`, and `LimitNOFILE=10032`.
     - Notifies `systemctl daemon-reload` when the unit template changes.
   - For alternative job-control paths:
     - `initd`: renders `redis.init.erb` to `/etc/init.d/redis6379`.
     - `upstart`: renders `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`.
     - `rcinit`: renders `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`.
   - Resources for the effective systemd path: `redisio_configure` custom resource (1), `user` (1), `directory` (3), `template` (2), `file` (2), notification-driven `execute` (1), and `service` declaration (1).

9. **enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: 1 iteration for Redis instance **6379**.
   - Adds `:start` and `:enable` actions to the service declared during configuration.
   - Starts and enables `redis@6379` on systemd.
   - Starts and enables `redis6379` on non-systemd job-control implementations.

## Dependencies

**External cookbook dependencies**: `memcached` version constraint `~> 6.0`; `redisio` with no declared version constraint.

**System package dependencies**: `tar` on Debian, RHEL, and Fedora source-install paths; build compiler and toolchain dependencies installed through `build_essential[install build deps]`; `redis-server` on Debian or `redis` on RHEL/Fedora only when `node['redisio']['package_install']` is explicitly set to `true`; target-platform Memcached package required for instance `memcached`.

**Service dependencies**: Memcached service for instance `memcached`; `redis@6379` on systemd hosts or `redis6379` on non-systemd hosts; distribution `redis-server` on Debian or `redis` on RHEL/Fedora must be stopped and disabled; `network-online.target` is required by the systemd Redis unit.

## Credentials

**Detection Summary**: 1 active credential detected across 2 files. One optional data-bag password-loading mechanism exists in the Redis provider but is not configured by this cookbook.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis AUTH Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`; template variable `@requirepass`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`; `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`; `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
- **Current storage**: Hardcoded attribute value in `cookbooks/cache/recipes/default.rb`.
- **Usage context**: Rendered as the Redis `requirepass` directive in `/etc/redis/6379.conf`; Redis clients must authenticate with `AUTH` before executing regular commands.

### Optional Redis Data Bag Password Loader — Not Active
- **Variable(s)**: `node['redisio']['default_settings']['data_bag_name']`; `node['redisio']['default_settings']['data_bag_item']`; `node['redisio']['default_settings']['data_bag_key']`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb`; `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Optional `data_bag_item` capability; inactive because all three attributes are `nil`.
- **Usage context**: When configured, the provider retrieves a data-bag value and uses it as both Redis `requirepass` and `masterauth`.

For the Ansible migration, store the Redis password in AAP as a protected secret, such as `vault_redis_6379_requirepass`, inject it through `redis_6379_requirepass`, and use `no_log: true` for tasks that could expose the secret. No Chef Vault, encrypted data bag, CyberArk, Conjur, AWS Secrets Manager, environment-variable secret references, or other secret providers were detected.

## Checks for the Migration

**Files to verify**: `/var/log/redis`; `/etc/redis`; `/var/lib/redis`; `/var/run/redis/6379`; `/etc/redis/6379.conf`; `/etc/redis/6379.conf.breadcrumb`; `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts; `/lib/systemd/system/redis@6379.service` on systemd hosts; `/etc/init.d/redis6379` on initd hosts; `/etc/init/redis6379.conf` on Upstart hosts; `/usr/local/etc/rc.d/redis6379` on FreeBSD rcinit hosts; `/var/lib/redis/dump-6379.rdb` after Redis persistence; `/var/log/memcached` when used by the target Memcached deployment; `/etc/pam.d/su` and `/etc/pam.d/sudo` only if the separately reviewed PAM migration is intentionally implemented.

**Service endpoints to check**: Memcached instance `memcached` on TCP `0.0.0.0:11211` and UDP `0.0.0.0:11211`; Redis instance `6379` on TCP port `6379`, with no configured explicit bind interface, Unix socket, or TLS port.

**Templates rendered**: `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render; `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render on systemd; `redis.init.erb` to `/etc/init.d/redis6379`: 1 render only on initd; `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: 1 render only on Upstart; `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: 1 render only on FreeBSD rcinit.

## Pre-flight checks:
```bash
# --- Memcached instance: memcached ---

systemctl status memcached
systemctl is-enabled memcached
pgrep -a memcached

# Validate TCP and UDP listeners.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

# Validate Memcached protocol availability.
printf 'version\r\n' | nc -w 3 127.0.0.1 11211
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | head -n 5

# Confirm effective configuration includes 64 MB cache, TCP/UDP 11211,
# listen address 0.0.0.0, maximum connections 1024, and object size 1m.
ps -ef | grep '[m]emcached'
journalctl -u memcached -n 100 --no-pager


# --- Redis instance: 6379 ---

# Validate the named systemd instance.
systemctl status redis@6379
systemctl is-enabled redis@6379

# Ensure the distribution Redis service is not competing with the custom instance.
systemctl is-active redis-server
systemctl is-enabled redis-server

# Validate the source-installed binary and expected source version.
command -v redis-server
/usr/local/bin/redis-server -v

# Validate listener, configuration, and lack of a Unix socket.
ss -ltnp | grep ':6379'
grep -E '^(port|unixsocket|requirepass|dir|pidfile|maxclients|syslog-enabled)' /etc/redis/6379.conf

# Confirm post-render cleanup removed the intended directives.
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
# Expected: no output and a non-zero grep exit status.

# Authenticate using a protected secret supplied by the migration environment.
REDISCLI_AUTH="${REDIS_6379_REQUIREPASS}" redis-cli -h 127.0.0.1 -p 6379 PING
redis-cli -h 127.0.0.1 -p 6379 PING
# Expected unauthenticated response: NOAUTH Authentication required.

# Validate persistence, client configuration, and data directory.
REDISCLI_AUTH="${REDIS_6379_REQUIREPASS}" redis-cli -h 127.0.0.1 -p 6379 INFO persistence
REDISCLI_AUTH="${REDIS_6379_REQUIREPASS}" redis-cli -h 127.0.0.1 -p 6379 INFO clients
REDISCLI_AUTH="${REDIS_6379_REQUIREPASS}" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET dir

# Validate account, ownership, configuration, service unit, and file-descriptor limit.
id redis
stat -c '%U:%G %a %n' /var/log/redis /etc/redis /var/lib/redis /var/run/redis/6379
ls -l /etc/redis/6379.conf /etc/redis/6379.conf.breadcrumb
cat /etc/tmpfiles.d/redis@6379.conf
systemctl cat redis@6379
systemctl show redis@6379 -p LimitNOFILE

# Validate Redis persistence output after writes and a save have occurred.
ls -lah /var/lib/redis/dump-6379.rdb
journalctl -u redis@6379 -n 100 --no-pager
```