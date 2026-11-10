---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures a cache service stack consisting of Memcached through the external `memcached` cookbook and one password-authenticated Redis instance through the external `redisio` cookbook. The local cookbook configures Redis on TCP port `6379`, sets the Redis PID base directory to `/run/redis`, creates `/var/log/redis`, removes selected replication-related directives from `/etc/redis/6379.conf`, and invokes `redisio::enable`. The Redis password is hardcoded in the Chef recipe and must be migrated to an Ansible-managed secret.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **Redis instance on port 6379**: Password-authenticated Redis instance managed through the external `redisio` cookbook.
  - Location/Path: `/etc/redis/6379.conf`
  - Port/Socket: TCP port `6379`
  - Key Config:
    - Redis `requirepass` is configured from a hardcoded Chef recipe value and must be migrated to a protected Ansible secret.
    - `replicaservestaledata` is set to `nil` in the Redis server attribute data.
    - Redis PID base directory is `/run/redis`, intended to accommodate Fedora `/var/run` to `/run` mapping and SELinux labeling.
    - Redis log directory is `/var/log/redis`, owned by `redis:redis` with mode `0755`.
    - The local configuration cleanup removes lines beginning with:
      - `replica-serve-stale-data`
      - `replica-read-only`
      - `repl-ping-replica-period`
      - `client-output-buffer-limit`
      - `replica-priority`

- **Memcached**: Memcached service configured through the external `memcached` cookbook.
  - Location/Path: Not available in the supplied execution tree.
  - Port/Socket: Not available in the supplied execution tree.
  - Key Config: The external cookbook source, package name, service name, configuration path, and instance configuration must be obtained from the dependency cookbook or the current managed host before migration.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

**Recipes:**
```text
recipes/default.rb
```

**Providers:**
```text
```

**Templates:**
```text
```

**Attributes:**
```text
```

**Files:**
```text
```

No local provider, template, attributes, or static-file paths are present in the supplied execution tree. The `memcached`, `redisio`, and `redisio::enable` recipe implementations were not supplied and must not be represented as local cookbook files.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes the external `memcached` recipe.
     - Dependency: `memcached`, version `~> 6.0`.
     - The dependency recipe source is not present in the supplied execution tree.
     - Obtain and translate the external Memcached cookbook behavior separately.
     - Preserve this execution position before Redis configuration if ordering is significant in the target environment.

   - Defines the Redis server collection.
     - Redis instance: **Redis instance on port 6379**.
       - `port`: `6379`
       - `requirepass`: hardcoded Chef recipe value; migrate as an Ansible-managed secret.
       - `replicaservestaledata`: `nil`
     - Sets `node.default['redisio']['base_piddir']` to `/run/redis`.
     - Define the Redis instance configuration explicitly for port `6379`.
     - Set the PID directory to `/run/redis` if required by the selected Redis package and service implementation.
     - Store the Redis password in Ansible Vault, AAP credential inputs, or an approved external secret manager. Do not store it in plaintext role variables, inventory, or source control.

   - Includes the external `redisio` recipe.
     - Dependency: `redisio`, with no version constraint specified.
     - The dependency is expected to install and configure Redis and create the `redis` service account before the local directory operation.
     - The dependency recipe source is not present in the supplied execution tree.
     - Translate the external Redis installation and base configuration separately, ensuring the `redis` user and group exist before creating `/var/log/redis`.

   - Creates directory `/var/log/redis`.
     - Owner: `redis`
     - Group: `redis`
     - Mode: `0755`
     - Recursive creation: enabled.
     - Do not create the `redis` account in the local role unless the separately migrated Redis installation tasks do not create it.

   - Executes Ruby block `fix_redis_config`.
     - Target file: `/etc/redis/6379.conf`.
     - Makes no change if `/etc/redis/6379.conf` does not exist.
     - Removes every complete line beginning with `replica-serve-stale-data`.
     - Removes every complete line beginning with `replica-read-only`.
     - Removes every complete line beginning with `repl-ping-replica-period`.
     - Removes every complete line beginning with `client-output-buffer-limit`.
     - Removes every complete line beginning with `replica-priority`.
     - The Chef resource has no explicit notification and does not explicitly restart or reload Redis after changing the configuration.
     - In Ansible, check for `/etc/redis/6379.conf` with `ansible.builtin.stat` before removing directives with explicit `ansible.builtin.replace` tasks.
     - Deliberately determine whether changed configuration must notify a Redis restart. The Redis service unit name must be discovered before implementing a handler.

   - Includes the external `redisio::enable` recipe.
     - This recipe executes after the Redis log directory creation and configuration cleanup.
     - Its implementation is unavailable in the supplied execution tree.
     - Inspect the dependency cookbook or a managed host and reproduce the exact Redis enablement and start behavior only after identifying the actual Redis service unit.

   - **Resources in execution order**:
     1. `include_recipe` `memcached`
     2. `include_recipe` `redisio`
     3. `directory` `/var/log/redis`
     4. `ruby_block` `fix_redis_config`
     5. `include_recipe` `redisio::enable`

## Dependencies

**External cookbook dependencies**:
- `memcached`, version `~> 6.0`
- `redisio`, no version constraint specified

**System package dependencies**:
- Redis package name is not available in the supplied execution tree. It is installed by the unavailable `redisio` dependency recipe and must be verified from the dependency cookbook or managed host.
- Memcached package name is not available in the supplied execution tree. It is installed by the unavailable `memcached` dependency recipe and must be verified from the dependency cookbook or managed host.

**Service dependencies**:
- Redis service managed externally by `redisio` and `redisio::enable`; the exact service unit name is not available.
- Memcached service managed externally by `memcached`; the exact service unit name is not available.

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None detected
  - **Path**: None detected

### Redis Authentication Password
- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded recipe attribute value
- **Usage context**: Passed to the external `redisio` cookbook as the Redis `requirepass` configuration value for the Redis instance on TCP port `6379`.

- Migrate the password to Ansible Vault, an AAP credential or custom credential type, or an approved external secret manager.
- Do not place the password in plaintext in the Ansible role, inventory, Git repository, task output, or generated configuration validation output.
- Use `no_log: true` for Ansible tasks that render or pass the password when it could appear in task output.
- Ensure generated Redis configuration files use restrictive ownership and permissions appropriate to the selected Redis package.

No Chef data bags, encrypted data bags, Chef Vault calls, CyberArk or Conjur calls, environment-variable secret references, TLS private keys, or embedded connection strings were detected in the available local recipe.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
  - Must exist as a directory.
  - Owner must be `redis`.
  - Group must be `redis`.
  - Mode must be `0755`.

- `/etc/redis/6379.conf`
  - Verify only if the separately migrated Redis implementation creates this exact file.
  - Must not contain active lines beginning with:
    - `replica-serve-stale-data`
    - `replica-read-only`
    - `repl-ping-replica-period`
    - `client-output-buffer-limit`
    - `replica-priority`
  - Must contain the intended Redis authentication configuration without exposing the password in CI, AAP output, or logs.

- `/run/redis`
  - Verify if the migrated Redis implementation uses the cookbook-configured PID base directory.

- Memcached configuration file
  - Configuration path is not available in the supplied execution tree.
  - Discover and verify the path from the external `memcached` cookbook or the existing Chef-managed host.

**Service endpoints to check**:
- **Redis instance on port 6379**
  - TCP port: `6379`
  - Authentication is required.
  - Bind interface is not specified by this cookbook and must be determined from the final Redis configuration.

- **Memcached**
  - Port, socket, bind interface, and service unit are not available in the supplied execution tree.
  - Discover these values from the external `memcached` cookbook or the existing Chef-managed host before implementing endpoint validation.

**Templates rendered**:
- Local templates rendered by `cookbooks/cache/recipes/default.rb`: 0.
- Templates rendered by the external `memcached` dependency recipe: unknown; requires separate dependency analysis.
- Templates rendered by the external `redisio` dependency recipe: unknown; requires separate dependency analysis.

## Pre-flight checks:
```bash
# Redis instance on port 6379: confirm expected configuration file exists.
sudo test -f /etc/redis/6379.conf && echo "Redis 6379 configuration exists"

# Redis instance on port 6379: verify Redis log directory ownership and mode.
sudo stat -c '%n owner=%U group=%G mode=%a' /var/log/redis
# Expected: owner=redis group=redis mode=755

# Redis instance on port 6379: verify PID base directory if used by the migrated Redis implementation.
sudo stat -c '%n owner=%U group=%G mode=%a' /run/redis 2>/dev/null || true

# Redis instance on port 6379: verify all directives removed by fix_redis_config are absent.
# Each grep command should produce no output and return exit code 1 when the directive is absent.
sudo grep -nE '^replica-serve-stale-data.*$' /etc/redis/6379.conf
sudo grep -nE '^replica-read-only.*$' /etc/redis/6379.conf
sudo grep -nE '^repl-ping-replica-period.*$' /etc/redis/6379.conf
sudo grep -nE '^client-output-buffer-limit.*$' /etc/redis/6379.conf
sudo grep -nE '^replica-priority.*$' /etc/redis/6379.conf

# Redis instance on port 6379: verify requirepass is configured without displaying the value.
sudo grep -nE '^requirepass[[:space:]]+[^[:space:]]+' /etc/redis/6379.conf
# Expected: one active requirepass directive.

# Redis instance on port 6379: confirm TCP port 6379 is listening.
sudo ss -ltnp | grep ':6379'
# Expected: a listening TCP socket on port 6379.

# Redis instance on port 6379: authenticated connectivity checks.
# Source REDISCLI_AUTH securely at runtime; do not place the password in shell history or logs.
REDISCLI_AUTH='<redis_password>' redis-cli -h 127.0.0.1 -p 6379 PING
# Expected: PONG
REDISCLI_AUTH='<redis_password>' redis-cli -h 127.0.0.1 -p 6379 INFO server
REDISCLI_AUTH='<redis_password>' redis-cli -h 127.0.0.1 -p 6379 INFO replication

# Redis instance on port 6379: identify the actual Redis service unit before encoding it in Ansible.
systemctl list-unit-files --type=service | grep -i redis || true
systemctl list-units --type=service --all | grep -i redis || true

# Redis instance on port 6379: inspect logs after identifying the Redis service unit.
# Replace <redis-service-unit> with the discovered unit name.
sudo journalctl -u <redis-service-unit> -n 100 --no-pager

# Memcached: discover the package, service unit, configuration file, port, socket, and bind interface.
rpm -qa | grep -i memcached || dpkg-query -W -f='${binary:Package} ${Version}\n' '*memcached*' 2>/dev/null || true
systemctl list-unit-files --type=service | grep -i memcached || true
systemctl list-units --type=service --all | grep -i memcached || true
sudo ss -ltnp | grep -i memcached || true

# Memcached: after discovering the service unit, inspect service status and logs.
# Replace <memcached-service-unit> with the discovered unit name.
sudo systemctl status <memcached-service-unit> --no-pager
sudo journalctl -u <memcached-service-unit> -n 100 --no-pager
```