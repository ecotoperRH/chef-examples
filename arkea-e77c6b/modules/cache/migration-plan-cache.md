---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures a Memcached instance named **memcached** and a Redis instance named **6379**. Memcached listens on TCP and UDP port `11211` with 64 MB memory. Redis is configured on TCP port `6379`, uses `/etc/redis/6379.conf` and `/var/lib/redis`, runs as `redis@6379` on systemd, and requires a hardcoded password. The supplied validation identifies an unresolved conditional in `redisio::install`: Redis source-build claims, including Redis version `3.2.11`, must not be implemented until the effective `package_install` branch is verified.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Default Memcached daemon instance.
  - Location/Path: Default log path `/var/log/memcached`; exact package, service-unit, and configuration-file paths are not exposed by the permitted execution tree.
  - Port/Socket: TCP `11211`; UDP `11211`.
  - Key Config: Listens on `0.0.0.0`, uses 64 MB memory, maximum 1024 connections, maximum object size `1m`, and file-descriptor ulimit `1024`. The service is started and enabled through `memcached_instance[memcached]`.

- **6379**: Redis server instance identified by port because no explicit `name` attribute is configured.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`; log directory `/var/log/redis`.
  - Port/Socket: TCP `6379`; no Unix socket configured.
  - Key Config: Runs as user/group `redis`/`redis`; uses RDB persistence (`backuptype: rdb`); default save schedule applies because `save` is unset; `databases 16`, `tcp-backlog 511`, `maxclients 10000`, `appendfsync everysec`, `loglevel notice`, syslog enabled with facility `local0`, and `requirepass` configured. No explicit Redis bind address is configured.
  - Service: On systemd hosts, service name `redis@6379`, unit `/lib/systemd/system/redis@6379.service`, and tmpfiles declaration `/etc/tmpfiles.d/redis@6379.conf`.
  - Configuration cleanup: The wrapper removes `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from `/etc/redis/6379.conf`.
  - Installation status: `redisio['package_install']` is documented as `false` on Debian and RHEL-family platforms. The supplied structured analysis conflicts with the plan’s prior source-install claims by placing `redisio_install[redis-installation]` beneath `if node['redisio']['package_install']`. Verify the actual conditional in `redisio::install` before selecting package installation or source compilation.

The `redisio['servers']` collection is explicitly set by `cookbooks/cache/recipes/default.rb` and contains exactly one item:

1. **6379**
   - `port`: `6379`
   - `requirepass`: `redis_secure_password_123`
   - `replicaservestaledata`: `nil`

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

No static `.erb` file may be listed here under the supplied execution-tree restriction. Redis configuration is selected dynamically through `node['redisio']['redis_config']['template_source']`, whose default value is `redis.conf.erb`; it renders once to `/etc/redis/6379.conf`. The systemd unit source is `redis@.service.erb`, rendering once to `/lib/systemd/system/redis@6379.service` on systemd hosts.

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to the sole Redis instance **6379**.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` when present.
     - Removes the five configuration-line families: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
     - Writes the updated file to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: `directory` (1), `ruby_block` (1), `include_recipe` (3).

2. **default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Configures the named **memcached** instance with 64 MB memory, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum 1024 connections, maximum object size `1m`, and ulimit `1024`.
   - Starts and enables the service.
   - Resources: `memcached_instance` (1 custom resource).

3. **default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Executes `apt_update[apt_update]`.
   - Includes `redisio::_install_prereqs` when `redisio['package_install']` is `false`.
   - Uses `build_essential[install build deps]`.
   - When `redisio['bypass_setup']` is `false`, includes these recipes in order:
     1. `redisio::install`
     2. `redisio::disable_os_default`
     3. `redisio::configure`
   - Resources: `apt_update` (1), `build_essential` (1 custom resource), and `include_recipe` resources.

4. **_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Debian, RHEL, and Fedora, installs the verified package `tar`.
   - Resources: `package[tar]` (1).

5. **install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Includes `redisio::_install_prereqs` and uses `build_essential[install build deps]` within the branch represented in the supplied structured analysis.
   - The same analysis places `redisio_install[redis-installation]` in that branch, but the documented `package_install: false` value makes the claimed source-install execution path contradictory.
   - Do not assume Redis `3.2.11`, `http://download.redis.io/releases/redis-3.2.11.tar.gz`, `make clean && make`, `make install`, or `/usr/local/bin/redis-server` until the conditional is verified against `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`.
   - Resources: Effective installation resources are unresolved pending validation of the conditional.

6. **ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family hosts, renders a template to `/etc/pam.d/su`.
   - Deploys the configured `sudo` file to `/etc/pam.d/sudo` with mode `0644`.
   - `ulimit['users']` defaults to an empty Mash; no named `user_ulimit` resources are created unless node, role, or environment overrides add users.
   - Resources on Debian: `template` (1), `cookbook_file` (1).

7. **disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the operating system Redis service to prevent conflict with the configured Redis instance.
   - Disables `redis-server` on Debian.
   - Disables `redis` on RHEL and Fedora.
   - Resources: `service` (1), actions `stop` and `disable`.

8. **configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`; both are already visited in this execution chain.
   - Uses `redisio_configure[redis-servers]` once for Redis instance **6379**.
   - Creates the `redis` service account with home `/var/lib/redis` when absent.
   - Creates `/etc/redis` with owner `root`, group `redis`, and mode `0775`.
   - Creates `/var/lib/redis` with owner/group `redis` and mode `0775`.
   - Creates `/var/run/redis/6379` with owner/group `redis` and mode `0755`.
   - Renders the configured Redis template once:
     - `redis.conf.erb` → `/etc/redis/6379.conf`
     - Owner/group: `redis`/`redis`
     - Mode: `0644`
   - Creates `/etc/redis/6379.conf.breadcrumb` when absent, preventing Chef from overwriting the configuration on later converges.
   - On systemd hosts:
     - Creates `/etc/tmpfiles.d/redis@6379.conf`.
     - Renders `redis@.service.erb` once to `/lib/systemd/system/redis@6379.service`.
     - Triggers `systemctl daemon-reload` when the unit changes.
     - Declares `service[redis@6379]`.
   - On non-systemd platforms, declares `service[redis6379]`.

9. **enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Processes the sole configured Redis instance **6379**.
   - Adds `start` and `enable` actions to the previously declared service resource.
   - On systemd, starts and enables `redis@6379`.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint specified

**System package dependencies**:
- `tar`
- Build-toolchain packages installed through Chef’s `build_essential` resource; the exact package names are platform-dependent and must be verified for the target operating system.
- Memcached package name is not exposed by the permitted execution tree and must be verified for the target operating system.
- Redis installation package name, source archive, build commands, and binary path are unresolved until the `redisio::install` conditional is validated.

**Service dependencies**:
- `memcached`
- `redis@6379` on systemd hosts
- Disabled OS Redis service:
  - `redis-server` on Debian
  - `redis` on RHEL/Fedora

## Credentials

**Detection Summary**: 1 active credential detected across 1 file. One optional inactive Chef data-bag password capability exists in the Redis provider.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded attribute value
- **Usage context**: Rendered into `/etc/redis/6379.conf` as Redis `requirepass`; Redis clients must authenticate before executing protected commands.
- **Detected value**: `redis_secure_password_123`
- **Migration action**: Store the value in Ansible Vault, an encrypted AAP survey variable, or an approved external secret-manager lookup. Apply `no_log: true` to tasks handling the password. Use mode `0640` or stricter for `/etc/redis/6379.conf` if operational compatibility permits; Chef currently sets mode `0644`.

### Optional Redis Data Bag Password Source — Not Active

- **Variable(s)**: `data_bag_name`, `data_bag_item`, `data_bag_key`, `requirepass`, `masterauth`
- **Source file(s)**: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
- **Current storage**: Standard Chef data bag when all three data-bag attributes are configured.
- **Usage context**: Retrieves a password and assigns it to both Redis `requirepass` and `masterauth`.
- **Current cookbook state**: Not configured. The active Redis password is the wrapper cookbook’s hardcoded `requirepass`.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/tmpfiles.d/redis@6379.conf` on systemd
- `/lib/systemd/system/redis@6379.service` on systemd
- `/etc/pam.d/su` on Debian
- `/etc/pam.d/sudo` on Debian
- `/var/log/memcached` if produced by the selected Memcached provider implementation

**Service endpoints to check**:
- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis TCP: `*:6379`
- Redis Unix socket: none configured

**Templates rendered**:
- Dynamic Redis configuration template (`redis.conf.erb` by default) → `/etc/redis/6379.conf`: 1 render
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`: 1 render on systemd
- Debian PAM `su` template → `/etc/pam.d/su`: 1 render on Debian
- Memcached template path and render count: not confirmed from the supplied execution tree

## Pre-flight checks:
```bash
# ---- Memcached instance: memcached ----

# Confirm the service unit name for the target platform before migration.
systemctl status memcached
systemctl is-enabled memcached

# Confirm TCP and UDP listeners on port 11211.
ss -ltnp | grep '0.0.0.0:11211'
ss -lunp | grep ':11211'

# Confirm Memcached responds on the TCP endpoint.
printf 'stats\r\nquit\r\n' | nc -w 3 127.0.0.1 11211

# Confirm configured file-descriptor limits.
MEMCACHED_PID="$(pgrep -o memcached)"
test -n "${MEMCACHED_PID}"
cat "/proc/${MEMCACHED_PID}/limits" | grep -i 'open files'

# Inspect logs when the selected target implementation uses this default path.
test -e /var/log/memcached && tail -n 50 /var/log/memcached
journalctl -u memcached -n 100 --no-pager


# ---- Redis instance: 6379 ----

# Resolve the redisio::install conditional before implementation:
# verify whether package_install=false invokes source installation,
# package installation, or no Redis installation resource.
grep -nE 'package_install|redisio_install|build_essential' \
  migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb

# Confirm the systemd service is enabled and active.
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl show redis@6379 -p ActiveState -p SubState -p LimitNOFILE

# Confirm the Redis listener. No explicit bind address is configured.
ss -ltnp | grep ':6379'
lsof -nP -iTCP:6379 -sTCP:LISTEN

# Confirm configuration ownership, mode, and critical settings.
test -f /etc/redis/6379.conf
stat -c '%U:%G %a %n' /etc/redis/6379.conf
grep -E '^(port|dir|dbfilename|databases|maxclients|requirepass|syslog-enabled|syslog-facility)' \
  /etc/redis/6379.conf

# Confirm wrapper cleanup removed all targeted directives.
if grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf; then
  echo "Unexpected replica directives remain"
  exit 1
else
  echo "Expected: replica directives are absent"
fi

# Confirm authenticated Redis connectivity. Supply REDIS_PASSWORD securely.
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 PING
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 SET migration-check-6379 ok EX 60
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 GET migration-check-6379

# Confirm required directories and ownership.
stat -c '%U:%G %a %n' /var/lib/redis
stat -c '%U:%G %a %n' /var/run/redis/6379
stat -c '%U:%G %a %n' /var/log/redis
ls -lah /var/lib/redis
df -h /var/lib/redis

# Confirm systemd artifacts.
test -f /etc/tmpfiles.d/redis@6379.conf
test -f /lib/systemd/system/redis@6379.service
systemctl daemon-reload
systemctl cat redis@6379

# Confirm the OS Redis package service is not competing with redis@6379.
systemctl is-active redis-server || true
systemctl is-enabled redis-server || true
systemctl is-active redis || true
systemctl is-enabled redis || true

# Review Redis logs.
journalctl -u redis@6379 -n 100 --no-pager
```