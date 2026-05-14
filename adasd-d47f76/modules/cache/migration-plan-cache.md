---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures two caching services — **Memcached** and **Redis** — on a single host. Memcached is installed and configured via the community `memcached` cookbook (v6.1.0). Redis is installed and enabled via the community `redisio` cookbook (v7.2.4), configured as a single instance on port **6379** with password authentication (`requirepass`). A `ruby_block` hack post-processes the generated Redis config file at `/etc/redis/6379.conf` to strip out several incompatible directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the installed Redis version does not support. The cookbook supports Ubuntu ≥ 18.04 and CentOS ≥ 7.0.

## Service Type and Instances

**Service Type**: Cache (in-memory key-value stores)

**Configured Instances**:

- **Memcached**: Default instance managed entirely by the community `memcached` cookbook (v6.1.0). No custom attributes are set in this cookbook; all defaults from the upstream cookbook apply.
  - Port: **11211** (upstream default)
  - Key Config: All defaults from `memcached` cookbook v6.1.0

- **Redis (port 6379)**: Single Redis server instance managed by the community `redisio` cookbook (v7.2.4).
  - Port: **6379**
  - Config file: `/etc/redis/6379.conf`
  - Authentication: `requirepass redis_secure_password_123` (**hardcoded password — see Credentials section**)
  - `replicaservestaledata`: explicitly set to `nil` (removed from config by the post-processing hack)
  - Post-processing: The `ruby_block[fix_redis_config]` strips the following directives from `/etc/redis/6379.conf` after `redisio` generates it:
    - `replica-serve-stale-data`
    - `replica-read-only`
    - `repl-ping-replica-period`
    - `client-output-buffer-limit`
    - `replica-priority`

## File Structure

```
cookbooks/cache/recipes/default.rb
cookbooks/cache/metadata.rb
```

> **Note**: The `memcached` (v6.1.0) and `redisio` (v7.2.4) community cookbooks are resolved from Chef Supermarket (`supermarket.chef.io`) and are not present in the local `cookbooks/` directory. Their recipes (`memcached::default`, `redisio::default`, `redisio::enable`) are called via `include_recipe` but their source files are not available locally for analysis. No custom resource providers or `.erb` templates exist in this cookbook; templates are owned by the upstream community cookbooks.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):

   - **Step 1 — include_recipe 'memcached'**: Delegates entirely to the community `memcached` cookbook v6.1.0 (`memcached::default`). This recipe installs the `memcached` package, creates the memcached user/group, deploys the memcached configuration file, and enables/starts the `memcached` service. No custom attributes are set by this cookbook before the call — all upstream defaults apply.
     - Source: Chef Supermarket `memcached` v6.1.0

   - **Step 2 — Set Redis node attributes**: Before including `redisio`, the recipe sets `node.default['redisio']['servers']` to a single-element array defining one Redis server instance:
     - `port`: `'6379'`
     - `requirepass`: `'redis_secure_password_123'` (**hardcoded plaintext password**)
     - `replicaservestaledata`: `nil` (explicitly unset/nil)

   - **Step 3 — directory['/var/log/redis']**: Creates the Redis log directory.
     - Path: `/var/log/redis`
     - Owner: `redis`
     - Group: `redis`
     - Mode: `0755`
     - Recursive: `true`
     - Resources: directory (1)

   - **Step 4 — include_recipe 'redisio'**: Delegates to the community `redisio` cookbook v7.2.4 (`redisio::default`). This recipe installs the Redis package, creates the `redis` user and group, and generates the configuration file `/etc/redis/6379.conf` from the `node['redisio']['servers']` attribute set in Step 2.
     - Source: Chef Supermarket `redisio` v7.2.4

   - **Step 5 — ruby_block['fix_redis_config']**: A post-processing hack that reads `/etc/redis/6379.conf` (if it exists) and removes lines matching the following patterns using `gsub!` with regex substitution:
     - Removes all lines matching: `^replica-serve-stale-data.*$`
     - Removes all lines matching: `^replica-read-only.*$`
     - Removes all lines matching: `^repl-ping-replica-period.*$`
     - Removes all lines matching: `^client-output-buffer-limit.*$`
     - Removes all lines matching: `^replica-priority.*$`
     - Writes the modified content back to `/etc/redis/6379.conf`
     - Resources: ruby_block (1)

   - **Step 6 — include_recipe 'redisio::enable'**: Delegates to `redisio::enable` from the community `redisio` cookbook v7.2.4. This recipe enables and starts the Redis service (typically `redis6379` or `redis_6379` systemd unit, depending on the redisio version and OS init system).
     - Source: Chef Supermarket `redisio` v7.2.4

   **Total resources in this recipe**: include_recipe (3), directory (1), ruby_block (1)

## Dependencies

**External cookbook dependencies**:
- `memcached` ~> 6.0 (resolved: v6.1.0) — from Chef Supermarket
- `redisio` >= 0.0.0 (resolved: v7.2.4) — from Chef Supermarket; itself depends on `selinux` v6.2.4

**System package dependencies**:
- `memcached` — installed by the `memcached` cookbook
- `redis-server` (or `redis`) — installed by the `redisio` cookbook

**Service dependencies** (systemd services managed):
- `memcached` — enabled and started by `memcached::default`
- `redis_6379` or `redis6379` — enabled and started by `redisio::enable` (service name format depends on redisio v7.2.4 conventions)

## Credentials

**Detection Summary**: 1 credential detected in 1 file.

**Source**:
- **Provider**: Hardcoded (plaintext in recipe source)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`)
- **Current storage**: **Hardcoded** — plaintext string literal directly in the recipe file
- **Usage context**: Redis `requirepass` directive — any client connecting to Redis on port 6379 must authenticate with this password. This is written directly into `/etc/redis/6379.conf` by the `redisio` cookbook.

> ⚠️ **Security Risk**: This password (`redis_secure_password_123`) is stored in plaintext in the recipe source code. During migration to Ansible, this credential **MUST** be moved to a secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager, AAP Credential Store, or Ansible Vault) and referenced via a variable — never hardcoded in a playbook or role.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis configuration file (generated by redisio, post-processed by ruby_block)
- `/var/log/redis/` — Redis log directory (created by this cookbook)
- `/etc/memcached.conf` — Memcached configuration file (created by memcached cookbook)
- `/var/run/redis/` or `/var/run/redis_6379.pid` — Redis PID file (location varies by OS/redisio version)

**Service endpoints to check**:
- **6379** — Redis (TCP)
- **11211** — Memcached (TCP)
- Unix sockets: None configured (both services use TCP)

**Templates rendered**:
- `/etc/redis/6379.conf` — rendered once by `redisio::default`, then post-processed once by `ruby_block[fix_redis_config]`
- `/etc/memcached.conf` — rendered once by `memcached::default`

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED checks
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached

# Verify memcached is listening on port 11211
netstat -tulpn | grep 11211
ss -tlnp | grep 11211
lsof -i :11211

# Functional test: set and get a key
echo -e "set testkey 0 60 5\r\nhello\r\nget testkey\r\nquit\r\n" | nc -q 2 127.0.0.1 11211
# Expected output: STORED ... VALUE testkey 0 5 ... hello

# Configuration file
cat /etc/memcached.conf

# Logs
journalctl -u memcached -n 50 --no-pager
journalctl -u memcached -f

# ============================================================
# REDIS (port 6379) checks
# ============================================================

# Service status
systemctl status redis_6379
ps aux | grep redis

# Verify Redis is listening on port 6379
netstat -tulpn | grep 6379
ss -tlnp | grep 6379
lsof -i :6379

# Functional test: authenticate and ping
redis-cli -p 6379 -a 'redis_secure_password_123' PING
# Expected output: PONG

# Verify authentication is required (unauthenticated access should fail)
redis-cli -p 6379 PING
# Expected output: NOAUTH Authentication required.

# Verify server info
redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep -E 'redis_version|tcp_port|config_file'

# Configuration file: verify post-processing removed the problematic directives
cat /etc/redis/6379.conf | grep -E 'requirepass|port'
# Expected: requirepass redis_secure_password_123, port 6379

# Verify the following directives are ABSENT from the config (ruby_block hack)
grep 'replica-serve-stale-data' /etc/redis/6379.conf && echo "FAIL: directive still present" || echo "OK: replica-serve-stale-data removed"
grep 'replica-read-only' /etc/redis/6379.conf && echo "FAIL: directive still present" || echo "OK: replica-read-only removed"
grep 'repl-ping-replica-period' /etc/redis/6379.conf && echo "FAIL: directive still present" || echo "OK: repl-ping-replica-period removed"
grep 'client-output-buffer-limit' /etc/redis/6379.conf && echo "FAIL: directive still present" || echo "OK: client-output-buffer-limit removed"
grep 'replica-priority' /etc/redis/6379.conf && echo "FAIL: directive still present" || echo "OK: replica-priority removed"

# Log directory ownership and permissions
ls -lah /var/log/redis/
# Expected: drwxr-xr-x owned by redis:redis

# Redis logs
journalctl -u redis_6379 -n 50 --no-pager
journalctl -u redis_6379 -f

# Memory and resource usage
redis-cli -p 6379 -a 'redis_secure_password_123' INFO memory | grep -E 'used_memory_human|maxmemory_human'
redis-cli -p 6379 -a 'redis_secure_password_123' INFO stats | grep -E 'total_commands_processed|connected_clients'
```