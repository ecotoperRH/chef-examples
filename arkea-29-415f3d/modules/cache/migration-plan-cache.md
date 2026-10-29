---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: a Memcached instance named **memcached** and a Redis instance named **6379**. Memcached listens on TCP and UDP port **11211** with 64 MB memory and 1,024 maximum connections. Redis is source-installed as version **3.2.11** by default, listens on TCP port **6379**, and runs as `redis@6379` on systemd hosts. The cookbook currently contains one hardcoded Redis password that must be migrated to an AAP credential, external secret manager, or encrypted Ansible Vault variable.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Default Memcached cache instance.
  - Location/Path: Distribution-specific Memcached configuration file; package and configuration path must be confirmed for the target operating system.
  - Port/Socket: TCP `11211`; UDP `11211`
  - Key Config:
    - Listen address: `0.0.0.0`
    - Memory allocation: `64 MB`
    - Maximum connections: `1024`
    - Maximum object size: `1m`
    - File-descriptor limit: `1024`
    - Thread value: Passed from `node['memcached']['threads']`; no default is supplied in the analyzed attributes.
    - Service state: Started and enabled by `memcached_instance[memcached]`.

- **6379**: Redis cache instance. The configured `node['redisio']['servers']` collection contains exactly one item, whose effective instance name is its port: **6379**.
  - Location/Path:
    - Configuration: `/etc/redis/6379.conf`
    - Data directory: `/var/lib/redis`
    - PID directory: `/var/run/redis/6379`
    - Log directory: `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured.
  - Key Config:
    - Systemd service: `redis@6379`
    - Service account: `redis:redis`
    - Redis version: `3.2.11` by default because `node['redisio']['package_install']` is `false`.
    - Installation method: Source build from `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
    - Authentication: `requirepass` is configured with a hardcoded password in the Chef wrapper and must be replaced with `{{ vault_redis_6379_password }}` in Ansible.
    - Persistence mode: `rdb`
    - Database count: `16`
    - Maximum clients: `10000`
    - TCP backlog: `511`
    - Systemd `LimitNOFILE`: `10032`, calculated as `maxclients (10000) + 32`.
    - The wrapper sets `replicaservestaledata` to `nil` and subsequently removes obsolete replication-related directives from `/etc/redis/6379.conf`.

## File Structure

Only files used by the supplied execution tree are listed below. Files not in the execution tree—including unrelated Redis recipes, Sentinel recipes, SELinux recipes, documentation, tests, and development files—are intentionally excluded.

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

The supplied execution tree permits only `.rb` paths in this section’s file listing. It does not declare a concrete Redis configuration template filename path: the source is dynamically selected by `node['redisio']['redis_config']['template_source']`, whose effective value is `redis.conf.erb`. The provider also conditionally renders an init-system template; on systemd this is `redis@.service.erb`.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Overrides `node['redisio']['servers']` with exactly one Redis server definition named **6379**.
   - Configures the active Chef `requirepass` value as the hardcoded password `redis_secure_password_123`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` when it exists.
     - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the modified content to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `directory` (1), `ruby_block` (1), and `include_recipe` (3).
   - Ansible implementation: Render the desired final Redis configuration directly. Do not reproduce the Ruby post-processing unless a legacy configuration comparison requires removal of the five directives.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Configures the explicitly named instance **memcached**:
     - Memory: `64`
     - TCP port: `11211`
     - UDP port: `11211`
     - Listen address: `0.0.0.0`
     - Maximum connections: `1024`
     - Maximum object size: `1m`
     - Thread value: `node['memcached']['threads']`, with no analyzed default.
     - File-descriptor limit: `1024`
   - Starts and enables the Memcached service.
   - Resources: `memcached_instance` custom resource (1).
   - Ansible implementation: Install the target platform's verified Memcached package, configure the distribution-specific configuration file with the listed values, and enable and start the resulting service.

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Because `node['redisio']['package_install']` defaults to `false`, includes `redisio::_install_prereqs` and uses `build_essential[install build deps]`.
   - Because `node['redisio']['bypass_setup']` defaults to `false`, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Direct recipe inclusions:
     - `redisio::_install_prereqs`
     - `redisio::install`
     - `redisio::disable_os_default`
     - `redisio::configure`
   - Resources: `apt_update` (1), `build_essential` custom resource (1), and `include_recipe` (4).

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Determines Redis source-install prerequisites by platform family.
   - Installs `tar` on Debian, RHEL, and Fedora.
   - Resources: `package[tar]` (1).

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses the default source-install branch because `package_install` is `false`.
   - Includes `redisio::_install_prereqs`; Chef recognizes it as already visited in the normal execution chain.
   - Uses `build_essential[install build deps]`.
   - Uses `redisio_install[redis-installation]`.
   - The Redis installation provider:
     - Downloads `redis-3.2.11.tar.gz` from `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
     - Extracts the archive.
     - Runs `make clean && make`.
     - Runs `make install`.
     - Preserves an existing Redis binary when `safe_install` is enabled.
   - Includes `redisio::ulimit`.
   - Alternative package branch when `package_install` is enabled:
     - Debian: `redis-server`
     - RHEL/Fedora: `redis`
   - Resources in the active source-install branch: `build_essential` custom resource (1), `redisio_install` custom resource (1), and `include_recipe` (2).
   - Ansible implementation: For strict equivalence, obtain Redis `3.2.11` from an internally trusted repository or HTTPS source with a verified checksum, install verified compiler and build dependencies, compile, and install. An operating-system Redis package is acceptable only if version equivalence is not required.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `/etc/pam.d/su`.
   - Deploys `/etc/pam.d/sudo` with mode `0644`.
   - The default `node['ulimit']['users']` collection is empty; no `user_ulimit` resources are created.
   - Resources on Debian: `template[/etc/pam.d/su]` (1) and `cookbook_file[/etc/pam.d/sudo]` (1).
   - Ansible implementation: Preserve existing PAM configuration unless the original template and static file contents are reviewed. The Redis systemd unit independently sets the Redis file-descriptor limit.

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - On Debian, stops and disables `redis-server`.
   - On RHEL/Fedora, stops and disables `redis`.
   - Resources: one service resource with `stop` and `disable` actions.
   - Ansible implementation: Ensure disabling the distribution-provided Redis service does not stop the intended custom Redis service `redis@6379`.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; Chef recognizes both as already visited.
   - Uses `redisio_configure[redis-servers]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Iterations: Processes exactly one Redis instance, **6379**.
   - For Redis instance **6379**:
     - Creates user `redis` with home `/var/lib/redis` if needed.
     - Creates `/etc/redis` with owner `root`, group `redis`, and mode `0775`.
     - Creates `/var/lib/redis` with owner and group `redis` and mode `0775`.
     - Creates `/var/run/redis/6379` with owner and group `redis` and mode `0755`.
     - Does not create a Redis logfile because `syslogenabled` is `yes` and no explicit logfile is configured.
     - Renders `redis.conf.erb` to `/etc/redis/6379.conf`.
     - Creates `/etc/redis/6379.conf.breadcrumb` to prevent future Chef runs from overwriting the configuration.
     - On systemd hosts, creates `/etc/tmpfiles.d/redis@6379.conf`.
     - On systemd hosts, renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
     - Runs `systemctl daemon-reload` immediately when `/lib/systemd/system/redis@6379.service` changes.
     - Creates the service resource `service[redis@6379]`.
   - Systemd unit execution command:
     ```text
     /usr/local/bin/redis-server /etc/redis/6379.conf --daemonize no
     ```
   - Resources: `redisio_configure` custom resource (1) and `service[redis@6379]` (1).

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: Processes exactly one configured Redis instance, **6379**.
   - Adds `start` and `enable` actions to `service[redis@6379]` on systemd hosts.
   - Resources: Modifies the existing `service[redis@6379]` resource.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora when Redis source installation is used.
- Redis source build dependencies installed through `build_essential[install build deps]`; exact package names are not exposed in the supplied execution tree and must be verified for the target operating system.
- Memcached package name is encapsulated by `memcached_instance[memcached]` and must be verified for the target operating system.
- Alternative Redis package-install branch:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`

**Service dependencies**:
- Memcached service for instance `memcached`.
- Redis systemd service `redis@6379`.
- Network availability for Redis: `Wants=network-online.target` and `After=network-online.target`.
- The OS-default Redis service must remain disabled:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Instance 6379 Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded attribute value
- **Usage context**: Rendered into `/etc/redis/6379.conf` as the Redis `requirepass` authentication password. It is also available to initd shutdown logic when the initd branch is used.

Migrate this value to an AAP credential, external secret manager credential, or encrypted Ansible Vault variable such as `vault_redis_6379_password`. Mark Redis configuration-rendering tasks as `no_log: true` when output could expose the secret. Use mode `0640` or `0600` for `/etc/redis/6379.conf` unless strict Chef compatibility requires its existing `0644` mode.

### Optional Redis Data-Bag Credential Mechanism

- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Not configured for this deployment.
- **Usage context**: If all values were configured, the provider would load a plain Chef data bag value and use it as both `requirepass` and `masterauth`.

No Chef Vault, encrypted data bag, CyberArk, Conjur, or environment-variable secret source is configured.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/pam.d/su` on Debian-family hosts if preserving Chef ulimit behavior
- `/etc/pam.d/sudo` on Debian-family hosts if preserving Chef ulimit behavior
- The target operating system's Memcached configuration file
- Do not create `/etc/redis/6379.conf.breadcrumb`; it is Chef-specific.

**Service endpoints to check**:
- **memcached**
  - TCP `11211`
  - UDP `11211`
  - Bind address `0.0.0.0`
- **6379**
  - TCP `6379`
  - No Unix socket configured
  - Verify the effective Redis bind behavior from `/etc/redis/6379.conf`.

**Templates rendered**:
- `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render for instance **6379**.
- `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render on systemd hosts for instance **6379**.
- `redis.init.erb` to `/etc/init.d/redis6379`: 1 render only on initd hosts.
- `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: 1 render only on Upstart hosts.
- `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: 1 render only on FreeBSD rcinit hosts.

## Pre-flight checks:
```bash
# -----------------------------
# Memcached instance: memcached
# -----------------------------

systemctl status memcached
systemctl is-enabled memcached

# Confirm TCP and UDP listeners.
ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
lsof -nP -iTCP:11211 -sTCP:LISTEN

# Confirm Memcached protocol connectivity and runtime values.
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211 | grep '^STAT '
printf 'version\r\n' | nc -w 3 127.0.0.1 11211 | grep '^VERSION '
printf 'stats settings\r\n' | nc -w 3 127.0.0.1 11211 | grep -E \
  'STAT (maxbytes 67108864|maxconns 1024|item_size_max 1048576)'

pgrep -a memcached
journalctl -u memcached -n 100 --no-pager

# ----------------------
# Redis instance: 6379
# ----------------------

systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl show redis@6379 -p User -p Group -p LimitNOFILE

# Expected values: User=redis, Group=redis, LimitNOFILE=10032.
systemctl cat redis@6379
systemctl daemon-reload
systemctl is-active redis@6379

# Confirm the Redis listener.
ss -ltnp | grep ':6379'
lsof -nP -iTCP:6379 -sTCP:LISTEN

# Set REDIS_PASSWORD securely through the AAP credential mechanism.
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 PING
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 INFO server \
  | grep '^redis_version:'
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET databases
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 CONFIG GET maxclients
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379 INFO persistence \
  | grep -E '^(rdb_last_save_time|aof_enabled):'

# Verify non-secret configuration settings.
grep -E '^(port|databases|tcp-backlog|maxclients|dir|dbfilename|appendonly|syslog-enabled)' \
  /etc/redis/6379.conf
grep -q '^requirepass ' /etc/redis/6379.conf \
  && echo 'requirepass is configured'

# Verify that Chef's obsolete replication directives are absent.
! grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf \
  && echo 'Legacy replication directives are absent'

# Verify ownership, permissions, and required directories.
stat -c '%U:%G %a %n' \
  /etc/redis \
  /etc/redis/6379.conf \
  /var/lib/redis \
  /var/run/redis/6379 \
  /var/log/redis \
  /etc/tmpfiles.d/redis@6379.conf \
  /lib/systemd/system/redis@6379.service

pgrep -a redis-server
journalctl -u redis@6379 -n 100 --no-pager

# Confirm the distribution-default Redis service is disabled.
systemctl is-active redis-server || true
systemctl is-enabled redis-server || true
systemctl is-active redis || true
systemctl is-enabled redis || true

# Confirm available Redis persistence capacity.
df -h /var/lib/redis
ls -lah /var/lib/redis
```