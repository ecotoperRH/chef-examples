---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook provisions a Redis installation (via the `redisio` community cookbook with custom resources) and a Memcached instance (via the `memcached` community cookbook custom resource) on the target node. It disables the OS-default Redis service, compiles/installs a custom Redis build, configures per-instance Redis servers, applies user ulimits, and starts a named Memcached instance. Migration to Ansible requires replacing three community cookbook custom resource providers (`redisio_install`, `redisio_configure`, `memcached_instance`, `user_ulimit`) with native Ansible modules, resolving the `fix_redis_config` Ruby block logic before code generation, and vaulting the hardcoded Redis password.

---

## Service Type and Instances

**Service Type**: Cache Layer (Redis + Memcached)

**Configured Instances**:

- **redis-installation**: Redis custom-compiled installation managed by `redisio_install`
  - Location/Path: Managed by `redisio` cookbook artifact at `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/`
  - Port/Socket: Default Redis port (6379) — exact socket/port confirmed by provider analysis (pending)
  - Key Config: Source compilation vs. package install path TBD pending provider analysis; password `redis_secure_password_123` (hardcoded — must be vaulted)

- **redis-servers**: Redis per-instance configuration managed by `redisio_configure`
  - Location/Path: Managed by `redisio` cookbook artifact (same path as above)
  - Port/Socket: Per-instance config file generation — exact values pending provider analysis
  - Key Config: Post-template config patched by `ruby_block[fix_redis_config]` — logic must be documented before migration (see Module Explanation)

- **memcached**: Memcached instance managed by `memcached_instance` custom resource
  - Location/Path: Managed by `memcached` cookbook artifact at `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/`
  - Port/Socket: TCP port and/or socket — exact values pending provider analysis of `memcached_instance`
  - Key Config: Memory limits, socket vs. TCP configuration — pending provider analysis

---

## File Structure

```
cookbooks/cache/
├── attributes/
│   └── default.rb
├── recipes/
│   └── default.rb
├── templates/
│   └── (any Redis/Memcached config templates)
└── metadata.rb

migration-dependencies/cookbook_artifacts/
├── redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/
│   ├── providers/
│   │   ├── install.rb        # redisio_install provider
│   │   └── configure.rb      # redisio_configure provider
│   └── recipes/
│       ├── default.rb
│       ├── ulimit.rb         # calls user_ulimit custom resource
│       └── disable_os_default.rb
└── memcached-7992788f1a376defb902059063f5295e37d281cb/
    └── providers/
        └── (memcached_instance provider)
```

> ⚠️ **Investigation Required**: Full directory listings for `redisio` and `memcached` cookbook artifacts must be confirmed by provider analysis before migration proceeds.

---

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `redisio::disable_os_default` to stop and disable any OS-packaged Redis service before the custom build is started
   - Declares `redisio_install[redis-installation]` custom resource to compile/install Redis from source (or package — install path TBD pending provider analysis of `cookbooks/redisio/providers/install.rb`)
   - Declares `redisio_configure[redis-servers]` custom resource to generate per-instance Redis configuration files
   - Executes `ruby_block[fix_redis_config]` to patch the rendered Redis configuration post-template — **exact keys patched are unknown and must be inspected before migration**; Ansible replacement may require `lineinfile`, a custom `template`, or a handler chain
   - Includes `redisio::ulimit` which calls `user_ulimit[user]` to set per-user ulimit values for the Redis service user (maps to Ansible `pam_limits` module or `/etc/security/limits.d/` file management)
   - Declares `memcached_instance[memcached]` custom resource to configure and start the Memcached service (ports, memory limits, socket vs. TCP — pending provider analysis)

2. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-.../recipes/disable_os_default.rb`):
   - Iterations: Stops and disables `service[service_name]` (actions: `stop`, `disable`) — disables the OS default Redis/redis-server unit before the custom-compiled service is enabled
   - Ansible equivalent: Explicit task to `systemd`/`service` module with `state: stopped`, `enabled: false` targeting `redis` or `redis-server` before the custom service unit is started

3. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-.../recipes/ulimit.rb`):
   - Calls `user_ulimit[user]` custom resource to configure per-user open file limits for the Redis service user
   - Ansible equivalent: `pam_limits` module task or template deploying `/etc/security/limits.d/redis.conf`

---

## Dependencies

**External cookbook dependencies**:
- `redisio` (artifact: `redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db`) — provides `redisio_install`, `redisio_configure`, `redisio::disable_os_default`, `redisio::ulimit`
- `memcached` (artifact: `memcached-7992788f1a376defb902059063f5295e37d281cb`) — provides `memcached_instance`
- `user_ulimit` — provides `user_ulimit` custom resource (called from `redisio::ulimit`)

**System package dependencies**:
- Redis build dependencies (compiler toolchain, etc.) — exact list pending `redisio_install` provider analysis
- Memcached package or build dependencies — pending `memcached_instance` provider analysis

**Service dependencies**:
- OS-default `redis` / `redis-server` service must be stopped and disabled before custom Redis service starts
- Memcached service managed by `memcached_instance`

---

## Credentials

**Detection Summary**: 1 confirmed credential detected across 1 file. 1 additional credential (`fastapi_password`) referenced in project context but belongs to `fastapi-tutorial` cookbook — not in scope for this plan.

**Source**:
  - **Provider**: Hardcoded in Chef attributes file
  - **URL**: N/A
  - **Path**: `cookbooks/cache/attributes/default.rb` (path inferred from cookbook structure — must be confirmed by attributes file analysis before migration)

### Redis Authentication Password

- **Variable(s)**: `redis_secure_password_123` (literal string value; attribute key name TBD pending attributes file analysis)
- **Source file(s)**: `cookbooks/cache/attributes/default.rb` (to be confirmed)
- **Current storage**: Hardcoded plaintext in Chef attributes file
- **Usage context**: Written into Redis configuration via `redisio_configure[redis-servers]` template rendering and/or patched by `ruby_block[fix_redis_config]`; used for Redis AUTH

> ⚠️ **Required Action**: This credential must be migrated to **Ansible Vault** before the `cache` role is generated. The attributes file path and exact attribute key must be confirmed by analysis of `cookbooks/cache/attributes/default.rb`.

---

## Checks for the Migration

**Files to verify**:
- `cookbooks/cache/recipes/default.rb`
- `cookbooks/cache/attributes/default.rb`
- `cookbooks/cache/metadata.rb`
- `migration-dependencies/cookbook_artifacts/redisio-.../recipes/disable_os_default.rb`
- `migration-dependencies/cookbook_artifacts/redisio-.../recipes/ulimit.rb`
- `migration-dependencies/cookbook_artifacts/redisio-.../providers/install.rb` (**required before migration**)
- `migration-dependencies/cookbook_artifacts/redisio-.../providers/configure.rb` (**required before migration**)
- `migration-dependencies/cookbook_artifacts/memcached-.../providers/` (**required before migration**)

**Service endpoints to check**:
- Redis on `redis-installation` / `redis-servers`: port 6379 (default — confirm via provider analysis)
- Memcached on `memcached`: port and/or socket (confirm via `memcached_instance` provider analysis)

**Templates rendered**:
- Redis configuration template: rendered once per configured Redis instance by `redisio_configure[redis-servers]` (count: 1 instance named `redis-servers`; exact template path in `redisio` artifact)
- Memcached configuration: rendered once for instance named `memcached` by `memcached_instance` provider (exact template path in `memcached` artifact)
- Post-render patch: `ruby_block[fix_redis_config]` modifies rendered Redis config (1 execution — logic must be documented)

---

## Pre-flight Checks

```bash
# ── Prerequisite Investigation (must complete before Ansible code generation) ──

# 1. Inspect fix_redis_config ruby block logic
grep -A 30 'fix_redis_config' cookbooks/cache/recipes/default.rb

# 2. Confirm Redis password attribute key and value
grep -r 'redis_secure_password' cookbooks/cache/attributes/
grep -r 'password' cookbooks/cache/attributes/

# 3. Analyze redisio_install provider
cat migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb

# 4. Analyze redisio_configure provider
cat migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb

# 5. Analyze memcached_instance provider
find migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/ -name '*.rb' | xargs grep -l 'memcached_instance\|action'

# 6. Analyze user_ulimit provider
find migration-dependencies/cookbook_artifacts/ -path '*/user_ulimit*' -name '*.rb'

# ── Service Status: redis-installation ──
systemctl status redis || systemctl status redis-server
redis-cli -a 'redis_secure_password_123' ping

# ── Service Status: redis-servers (per-instance config) ──
redis-cli -p 6379 -a 'redis_secure_password_123' info server
ls -la /etc/redis/ || ls -la /usr/local/etc/redis/

# ── Service Status: memcached ──
systemctl status memcached
echo "stats" | nc -q 1 127.0.0.1 11211

# ── OS Default Redis Service (must be disabled) ──
systemctl is-enabled redis 2>/dev/null || echo "redis not found"
systemctl is-enabled redis-server 2>/dev/null || echo "redis-server not found"

# ── Ulimit Verification for Redis Service User ──
grep -r redis /etc/security/limits.d/ 2>/dev/null || echo "No Redis ulimit config found"
id redis 2>/dev/null || echo "Redis service user not found"

# ── Configuration File Locations ──
find /etc /usr/local/etc -name 'redis*.conf' 2>/dev/null
find /etc -name 'memcached*' 2>/dev/null

# ── Credential Audit ──
grep -r 'redis_secure_password_123' cookbooks/
# Expected: found only in cookbooks/cache/attributes/default.rb
# Action required: vault this value before Ansible role generation
```