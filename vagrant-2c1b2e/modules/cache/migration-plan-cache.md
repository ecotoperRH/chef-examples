---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache instances: Memcached instance **memcached** on TCP and UDP port `11211`, and Redis instance **redis-6379** on TCP port `6379`. Memcached installation and service management are delegated to the external `memcached` cookbook custom resource. Redis installation and enablement are delegated to unavailable `redisio` cookbook recipes. The wrapper creates `/var/log/redis` and removes five replication-related directives from `/etc/redis/6379.conf`. Redis authentication uses a hardcoded Chef value that must be migrated to an Ansible Vault secret or AAP credential.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache instance managed by `memcached_instance['memcached']`.
  - Location/Path: `/var/log/memcached`
  - Port/Socket: `0.0.0.0:11211/TCP` and `0.0.0.0:11211/UDP`
  - Key Config: memory `64 MB`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, package version unset (`nil`), no experimental options, no additional CLI options, and service requested as started and enabled.
  - Thread count: `node['memcached']['threads']`; no default value is supplied and an Ansible value must not be invented.
  - Service account: resolved by the Chef `service_user` helper; the actual account is not available in the supplied source.

- **redis-6379**: Redis cache server configured through the external `redisio` cookbook.
  - Location/Path: `/etc/redis/6379.conf`, PID directory `/run/redis`, log directory `/var/log/redis`
  - Port/Socket: `6379/TCP`
  - Key Config: `requirepass` authentication is configured; `replicaservestaledata` is set to `nil`; Redis log directory is owned by `redis:redis` with mode `0755`.
  - Removed configuration directives: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
  - Bind address, package name, version, service unit, and service account behavior must be recovered from the unavailable `redisio` cookbook source or a Chef-managed host.

## File Structure

**Recipes:**
```text
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
```

**Providers:**
```text
None supplied in the execution tree.
```

**Templates:**
```text
None supplied in the execution tree.
```

**Attributes:**
```text
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
```

**Files:**
```text
None supplied in the execution tree.
```

> `redisio` and `redisio::enable` are included by `cookbooks/cache/recipes/default.rb`, but their recipe files were reported as not found in the supplied execution tree. Do not assume their package names, systemd service names, templates, ownership settings, or additional managed files without obtaining the `redisio` cookbook source or inspecting a current Chef-managed host.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`, which configures instance **memcached**.
   - Defines one Redis server, **redis-6379**, with port `6379`, `requirepass` authentication, and `replicaservestaledata` set to `nil`.
   - Sets the Redis PID base directory to `/run/redis`.
   - Includes `redisio`; its source is unavailable and must be recovered before reproducing Redis package installation, configuration rendering, service management, ownership, or restart behavior.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Runs `ruby_block['fix_redis_config']` only when `/etc/redis/6379.conf` exists.
   - Removes complete lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from `/etc/redis/6379.conf`.
   - Does not explicitly notify Redis to restart or reload after editing `/etc/redis/6379.conf`.
   - Includes `redisio::enable`; its source is unavailable and its exact service-enable behavior must be verified.
   - Resources used: `include_recipe` (3), `directory` (1), and `ruby_block` (1).
   - Iterations: none. The Redis `servers` array contains one explicitly named server: **redis-6379**.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance['memcached']`.
   - Requests memory `64`, port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, no experimental options, and no additional CLI options.
   - Passes `node['memcached']['threads']` to the custom resource. No default thread count exists in `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb`.
   - Uses the Chef `service_user` helper for the service user; the resolved user is not supplied.
   - Requests `start` and `enable` actions for **memcached**.
   - Resources used: `memcached_instance` custom resource (1).
   - Iterations: none.
   - The custom-resource provider source is not supplied. Recover the provider or inspect a Chef-managed host to determine the exact package name, service unit, service account, configuration file or systemd override, UDP behavior, ulimit rendering, and thread-count rendering.

3. **redisio** (source unavailable):
   - Included by `cookbooks/cache/recipes/default.rb` after the Redis server definition and PID directory attribute are set.
   - Expected to install and configure **redis-6379**, including creation of `/etc/redis/6379.conf`, but its exact behavior cannot be established from the supplied execution tree.
   - Iterations: unknown; source must be recovered.

4. **redisio::enable** (source unavailable):
   - Included by `cookbooks/cache/recipes/default.rb` after `/var/log/redis` creation and sanitization of `/etc/redis/6379.conf`.
   - Expected to enable the Redis service for **redis-6379**, but the exact unit name and service state behavior cannot be established from the supplied execution tree.
   - Iterations: unknown; source must be recovered.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared

**System package dependencies**:
- Memcached package: package name and version are not available because installation is implemented by the unavailable `memcached_instance` provider.
- Redis package: package name and version are not available because the `redisio` recipe source is unavailable.
- Verify real package names and versions on a Chef-managed host before implementing Ansible package tasks.

**Service dependencies**:
- Memcached service for **memcached**: requested as started and enabled by `memcached_instance`; exact service unit is unavailable.
- Redis service for **redis-6379**: installation, configuration, and enablement are delegated to `redisio` and `redisio::enable`; exact service unit is unavailable.

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None detected
  - **Path**: `cookbooks/cache/recipes/default.rb`; the value is expected to be rendered into `/etc/redis/6379.conf` by the external `redisio` cookbook.

### Redis Authentication Password
- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef recipe literal
- **Usage context**: Sets Redis `requirepass` authentication for **redis-6379** on port `6379`.

Store the migrated value as `redis_password` in an Ansible Vault-encrypted variable or AAP custom credential. Inject the credential at runtime, use `no_log: true` on tasks that could expose the password, and restrict the rendered Redis configuration file to the Redis account and authorized administrators. Rotate the exposed hardcoded password during migration rather than copying it unchanged.

No Chef data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, environment-variable secret references, TLS private keys, TLS certificates, or embedded database connection strings were detected in the supplied cookbook files.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis` — must exist recursively with owner `redis`, group `redis`, and mode `0755`.
- `/etc/redis/6379.conf` — must exist before the sanitizing task; it must contain Redis authentication configuration and must not contain the five directives removed by Chef.
- `/run/redis` — must exist if retained by the recovered `redisio` implementation.
- `/var/log/memcached` — configured by the Memcached attribute; verify actual creation and use after recovering the omitted `memcached_instance` provider.
- `cookbooks/cache/recipes/default.rb` — source wrapper recipe defining Redis configuration and post-configuration edits.
- `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb` — source recipe defining `memcached_instance['memcached']`.
- `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb` — source of Memcached defaults.

**Service endpoints to check**:
- **memcached**:
  - TCP: `0.0.0.0:11211`
  - UDP: `0.0.0.0:11211`, subject to recovered custom-resource and target-platform behavior.
- **redis-6379**:
  - TCP: port `6379`
  - Bind address: not supplied; determine from recovered `redisio` source or the existing Redis configuration.
- Unix sockets: none identified in the supplied source.

**Templates rendered**:
- Known templates rendered from supplied source: `0`.
- No template files are supplied or referenced in the available execution tree.
- The unavailable `memcached_instance` provider may render configuration or service-unit templates; template names, destinations, and render counts are unknown.
- The unavailable `redisio` recipes may render Redis configuration and service templates; template names, destinations, and render counts are unknown.

## Pre-flight checks:
```bash
# Run on the current Chef-managed host before migration and after Ansible deployment.
# Replace placeholder service-unit names only after discovering them on the host.

# ----- Memcached instance: memcached -----

# Discover the actual package and service unit.
systemctl list-unit-files | grep -i memcached
systemctl list-units --type=service --all | grep -i memcached
rpm -qa | grep -i '^memcached' || dpkg-query -W -f='${Package} ${Version}\n' 'memcached*'

# Verify service state after convergence.
systemctl status <memcached-service-unit>
systemctl is-enabled <memcached-service-unit>
systemctl is-active <memcached-service-unit>

# Verify the required TCP endpoint and runtime settings.
printf 'version\r\nstats settings\r\nquit\r\n' | nc -w 3 127.0.0.1 11211
ss -ltnp | grep ':11211'
lsof -nP -iTCP:11211 -sTCP:LISTEN
printf 'stats settings\r\nquit\r\n' | nc -w 3 127.0.0.1 11211 | \
  grep -E 'STAT (maxbytes|num_threads|inter|tcpport|udpport|maxconns)'

# UDP is required only if the recovered provider configuration enables it.
ss -lunp | grep ':11211' || true

# Verify the configured log-path attribute.
ls -ld /var/log/memcached

# ----- Redis instance: redis-6379 -----

# Discover exact Redis package and service-unit identity.
systemctl list-unit-files | grep -i redis
systemctl list-units --type=service --all | grep -i redis
rpm -qa | grep -i '^redis' || dpkg-query -W -f='${Package} ${Version}\n' 'redis*'

# Verify service state after the redisio::enable equivalent runs.
systemctl status <redis-service-unit>
systemctl is-enabled <redis-service-unit>
systemctl is-active <redis-service-unit>

# Verify required directories.
stat -c '%n %U:%G %a' /var/log/redis
# Expected: /var/log/redis redis:redis 755
stat -c '%n %U:%G %a' /run/redis

# Redis configuration must exist before sanitization.
test -f /etc/redis/6379.conf

# The directives removed by Chef must not remain.
grep -nE '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf && exit 1 || true

# Confirm authentication configuration without printing the secret.
grep -qE '^requirepass[[:space:]]+' /etc/redis/6379.conf && \
  echo 'Redis requirepass is configured'

# Verify authenticated Redis connectivity.
# Supply REDIS_PASSWORD from Ansible Vault or AAP credentials; do not place it in shell history.
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 PING
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h 127.0.0.1 -p 6379 INFO server | \
  grep -E '^(redis_version|tcp_port):'

# Verify the Redis TCP listener.
ss -ltnp | grep ':6379'
lsof -nP -iTCP:6379 -sTCP:LISTEN

# Review logs using the discovered service units.
journalctl -u <redis-service-unit> -n 100 --no-pager
journalctl -u <memcached-service-unit> -n 100 --no-pager
```