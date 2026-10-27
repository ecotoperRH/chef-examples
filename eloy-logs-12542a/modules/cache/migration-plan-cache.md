---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: a Memcached instance named **memcached** and an authenticated Redis instance named **6379**. Memcached listens on TCP and UDP port 11211 and is enabled at boot. Redis 3.2.11 is compiled from source by default on Ubuntu and CentOS, configured at `/etc/redis/6379.conf`, authenticated with a hardcoded password, and enabled as `redis@6379` on systemd hosts.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached in-memory cache instance.
  - Location/Path: Log path attribute `/var/log/memcached`
  - Port/Socket: TCP `11211`; UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory `64 MB`; maximum connections `1024`; maximum object size `1m`; file-descriptor limit `1024`; started and enabled by `memcached_instance[memcached]`.

- **6379**: Redis cache instance and the sole explicit item in `node['redisio']['servers']`.
  - Location/Path: Configuration `/etc/redis/6379.conf`; PID directory `/var/run/redis/6379`; data directory `/var/lib/redis`
  - Port/Socket: TCP `6379`; no Unix socket; no TLS port
  - Key Config: Redis 3.2.11 source installation; service account `redis:redis`; `16` databases; TCP backlog `511`; maximum clients `10000`; RDB persistence; `requirepass` set to `redis_secure_password_123`; replication stale-data setting is `nil`; obsolete replication directives are removed after configuration rendering.
  - Service Name: `redis@6379` on systemd; `redis6379` on init.d, Upstart, and FreeBSD rc.d.

## File Structure

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
```

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to exactly one Redis instance, **6379**:
     - Port: `6379`
     - Password: `redis_secure_password_123`
     - `replicaservestaledata`: `nil`
   - Creates `/var/log/redis` recursively as `redis:redis`, mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` only when it exists.
     - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the cleaned content to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Direct resources: directory (1), ruby_block (1), include_recipe (3).

2. **default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures **memcached** with memory `64 MB`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, and empty `experimental_options` and `extra_cli_options`.
   - Starts and enables the named instance **memcached**.
   - The Memcached custom-resource provider is not present in the supplied execution-tree file set. Preserve its package, service, configuration, and boot-enable behavior in Ansible.
   - Direct resources: memcached_instance (1 custom resource).

3. **default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `node['redisio']['package_install']` is `false` by default on Ubuntu and CentOS, includes `redisio::_install_prereqs` and invokes `build_essential[install build deps]`.
   - Because `node['redisio']['bypass_setup']` is `false`, includes the following recipes in order:
     1. `redisio::install`
     2. `redisio::disable_os_default`
     3. `redisio::configure`
   - Direct recipe includes: `redisio::_install_prereqs`, `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Direct resources: apt_update (1), build_essential (1 custom resource), include_recipe (4).

4. **_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Calculates source-install prerequisite packages by platform.
   - On Debian, RHEL, and Fedora, installs **tar**.
   - Iterations: Runs 1 time for package **tar**.
   - Direct resources: package (1).

5. **install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - In the default source-install path (`package_install: false`):
     - Includes `redisio::_install_prereqs`; Chef treats it as already visited.
     - Invokes `build_essential[install build deps]`.
     - Invokes `redisio_install[redis-installation]`.
     - Downloads `redis-3.2.11.tar.gz` from `http://download.redis.io/releases/`.
     - Unpacks the archive, runs `make clean && make`, then runs `make install`.
     - Installs Redis binaries to `/usr/local/bin` by default.
   - In the alternative package-install path (`package_install: true`):
     - Installs `redis-server` on Debian.
     - Installs `redis` on RHEL and Fedora.
     - Does not pin a package version.
   - Includes `redisio::ulimit`.
   - Direct resources in the default source-install path: build_essential (1 custom resource), redisio_install (1 custom resource), include_recipe (2).

6. **ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian, renders the PAM `su` configuration template to `/etc/pam.d/su`.
   - Deploys a cookbook file to `/etc/pam.d/sudo`, mode `0644`.
   - The default `node['ulimit']['users']` collection is empty.
   - Iterations: No `user_ulimit` instances are created unless `ulimit.users` is overridden.
   - Direct resources on Debian: template (1), cookbook_file (1), user_ulimit (0).

7. **disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the distribution-provided Redis service to avoid conflict with the cookbook-managed Redis 3.2.11 installation.
   - Disables `redis-server` on Debian.
   - Disables `redis` on RHEL and Fedora.
   - Direct resources: service (1), actions stop and disable.

8. **configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; both are already visited in the execution flow.
   - Invokes `redisio_configure[redis-servers]` for exactly one instance: **6379**.
   - Creates the `redis` system user and group when absent.
   - Creates the following directories:
     - `/etc/redis`, owned by `root:redis`, mode `0775`
     - `/var/lib/redis`, owned by `redis:redis`, mode `0775`
     - `/var/run/redis/6379`, owned by `redis:redis`, mode `0755`
   - Renders the Redis configuration template once:
     - `redis.conf.erb` by default from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}`
     - Destination: `/etc/redis/6379.conf`
     - Owner/group: `redis:redis`
     - Mode: `0644`
     - Includes settings for port `6379`, password, persistence, networking, replication, TLS, memory, logging, and ACLs.
   - Creates `/etc/redis/6379.conf.breadcrumb` when `breadcrumb` is true. This is a Chef-specific marker that prevents later Chef template overwrites and should normally be omitted from the Ansible implementation.
   - On systemd hosts:
     - Creates `/etc/tmpfiles.d/redis@6379.conf`.
     - Renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
     - Runs `systemctl daemon-reload` immediately when the systemd unit changes.
   - Creates `service[redis@6379]` on systemd or `service[redis6379]` on init.d, Upstart, and rcinit.
   - Direct resources for **6379** on systemd: user (1), directory (3), template (2), file (2), execute (1, notified by systemd unit changes), service (1), redisio_configure (1 custom resource).

9. **enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: Runs 1 time for Redis instance **6379**.
   - Looks up the service created by `redisio::configure`.
   - Starts and enables `redis@6379` on systemd.
   - Starts and enables `redis6379` on init.d, Upstart, and rcinit.
   - Direct resources: resource lookup/action update (1).

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint specified

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora when Redis is source-installed.
- Build prerequisites supplied through `build_essential[install build deps]`; the exact package expansion is not present in the supplied execution tree.
- Alternative Redis package-install branch:
  - Debian/Ubuntu: `redis-server`
  - RHEL/Fedora: `redis`

**Service dependencies**:
- Memcached service managed by `memcached_instance[memcached]`.
- Distribution Redis service disabled:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`
- Cookbook-managed Redis service enabled:
  - systemd: `redis@6379`
  - non-systemd: `redis6379`

## Credentials

**Detection Summary**: 1 active credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: Not applicable
  - **Path**: Not applicable

### Redis Client Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef attribute value
- **Usage context**: The value `redis_secure_password_123` is passed to the Redis configuration provider and rendered as the Redis `requirepass` value in `/etc/redis/6379.conf`. It may also be used for authenticated shutdown behavior on init.d platforms.

The Redis provider supports optional `data_bag_name`, `data_bag_item`, and `data_bag_key` attributes, but they are `nil` for the active instance. No Chef data bag, encrypted data bag, Chef Vault, CyberArk, Conjur, AWS Secrets Manager, or environment-variable secret source is active.

For Ansible Automation Platform, store the replacement password in an AAP credential, Ansible Vault, or an external secret-manager lookup. Use `no_log: true` for configuration-rendering and `redis-cli` tasks, and restrict access to `/etc/redis/6379.conf` because it contains the password in plaintext.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/pam.d/su` on Debian
- `/etc/pam.d/sudo` on Debian
- `/etc/redis/6379.conf.breadcrumb` is a Chef-only artifact and should normally be omitted from the Ansible implementation.

**Service endpoints to check**:
- **memcached**
  - TCP: `0.0.0.0:11211`
  - UDP: `0.0.0.0:11211`
- **6379**
  - TCP: port `6379`
  - Bind address: no explicit address is configured; listener behavior is determined by the Redis configuration template and Redis 3.2.11 defaults.
  - Unix socket: none configured
  - TLS port: none configured

**Templates rendered**:
- Redis server configuration template (`redis.conf.erb` by default): 1 render
  - Destination: `/etc/redis/6379.conf`
- `redis@.service.erb`: 1 render on systemd
  - Destination: `/lib/systemd/system/redis@6379.service`
- PAM `su` template: 1 render on Debian
  - Destination: `/etc/pam.d/su`

## Pre-flight checks:
```bash
# ---------------------------------------------------------------------------
# Memcached instance: memcached
# ---------------------------------------------------------------------------

systemctl status memcached --no-pager
pgrep -a memcached

# Verify the configured TCP and UDP listeners.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
nc -vz 127.0.0.1 11211

# Verify the Memcached protocol.
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | head -n 20
printf 'version\r\n' | nc -w 3 127.0.0.1 11211

# Confirm the externally reachable listen address.
ss -ltnp | grep '0.0.0.0:11211'

# ---------------------------------------------------------------------------
# Redis instance: 6379
# ---------------------------------------------------------------------------

# Verify systemd service state on systemd hosts.
systemctl status redis@6379 --no-pager
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Verify the default source-installed Redis binary and version.
test -x /usr/local/bin/redis-server && /usr/local/bin/redis-server -v

# Verify the instance listener and local connectivity.
ss -ltnp | grep ':6379'
nc -vz 127.0.0.1 6379

# Verify authenticated and unauthenticated Redis behavior.
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" PING
redis-cli -h 127.0.0.1 -p 6379 PING

# Validate Redis configuration values.
grep -E '^(port|requirepass|tcp-backlog|databases|maxclients|dir|pidfile) ' \
  /etc/redis/6379.conf

# Confirm compatibility-cleanup directives are absent.
! grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf

# Verify ownership, modes, and required directories.
stat -c '%A %U:%G %n' \
  /etc/redis \
  /etc/redis/6379.conf \
  /var/lib/redis \
  /var/run/redis/6379 \
  /var/log/redis

# Confirm no Unix socket exists for instance 6379.
test ! -S /var/run/redis/redis.sock

# Verify systemd artifacts on systemd hosts.
test -f /etc/tmpfiles.d/redis@6379.conf
test -f /lib/systemd/system/redis@6379.service
systemd-analyze verify /lib/systemd/system/redis@6379.service
systemctl cat redis@6379

# Validate authentication, persistence, and data-path operation.
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" INFO server
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" INFO persistence
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" SET migration_check_6379 ok EX 60
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" GET migration_check_6379

# Review Redis logs.
journalctl -u redis@6379 -n 100 --no-pager
journalctl -u redis@6379 -p warning --no-pager

# Confirm the conflicting distribution Redis service remains disabled.
systemctl is-enabled redis-server 2>/dev/null || true
systemctl is-active redis-server 2>/dev/null || true
systemctl is-enabled redis 2>/dev/null || true
systemctl is-active redis 2>/dev/null || true
```