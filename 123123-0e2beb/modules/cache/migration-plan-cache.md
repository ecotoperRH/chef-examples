# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services: Memcached (via the `memcached` community cookbook ~> 6.0) and Redis (via the `redisio` community cookbook pinned to a specific artifact). Redis runs on port 6379 with a hardcoded plaintext password and requires a post-generation config-patching hack to strip incompatible directives written unconditionally by the `redisio` template. Migration must address the EOL Redis 3.2.11 source-tarball install, the hardcoded credential, the config-scrubbing ruby_block, and all six redisio sub-recipes including their custom resource providers and conditional execution branches.

---

## Service Type and Instances

**Service Type**: Cache (Memcached + Redis)

**Configured Instances**:

- **memcached**: Default Memcached instance
  - Location/Path: Managed by `memcached` community cookbook
  - Port/Socket: Default (11211)
  - Key Config: Installed and configured via `include_recipe 'memcached'`

- **redis-6379**: Single Redis server instance
  - Location/Path: `/etc/redis/6379.conf`
  - Port/Socket: 6379
  - Key Config: `requirepass redis_secure_password_123` (hardcoded — see Credentials), `replicaservestaledata nil`, log directory `/var/log/redis`

---

## File Structure

```
cookbooks/cache/
├── metadata.rb
└── recipes/
    └── default.rb
```

---

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Calls `include_recipe 'memcached'` to install and configure the Memcached instance
   - Sets `node.default['redisio']['servers']` to a single-element array defining the Redis instance on port 6379 with `requirepass` and `replicaservestaledata nil`
   - Creates directory `/var/log/redis` for Redis log output
   - Calls `include_recipe 'redisio'` which triggers the full Redis installation and configuration subtree (see sub-recipes below)
   - Executes `ruby_block "fix_redis_config"` which reads `/etc/redis/6379.conf` and strips the following directives via regex substitution: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` — these are written unconditionally by the `redisio` template but are incompatible with the target Redis version/OS
   - Calls `include_recipe 'redisio::enable'` to enable and start the Redis service for the single configured instance (port 6379)
   - Iterations: The `node['redisio']['servers']` array contains exactly one entry — **redis instance on port 6379** — so all per-server loops execute once for this instance

2. **redisio::default** (entry point called by `include_recipe 'redisio'`):
   - Conditionally skips the entire install/configure subtree if `node['redisio']['bypass_setup']` is true (not set in this cookbook — subtree executes)
   - Calls `redisio::_install_prereqs`, `redisio::install`, `redisio::ulimit`, `redisio::disable_os_default`, and `redisio::configure` in sequence

3. **redisio::_install_prereqs** (`redisio-cac.../recipes/_install_prereqs.rb`):
   - Invokes the `build_essential[install build deps]` custom resource (from the `build-essential` cookbook) to install compiler toolchain packages required for building Redis from source
   - Executes only when `node['redisio']['package_install']` is false (default on Debian/Ubuntu — source build path is active in this deployment)

4. **redisio::install** (`redisio-cac.../recipes/install.rb`):
   - Branches on `node['redisio']['package_install']`:
     - **Source path (active)**: Invokes `redisio_install[redis-installation]` custom resource to download and compile Redis 3.2.11 from a pinned source tarball
     - **Package path (inactive)**: Would install Redis via the OS package manager — not used in this deployment
   - Iterations: Executes once for the single configured server instance (port 6379)

5. **redisio::ulimit** (`redisio-cac.../recipes/ulimit.rb`):
   - Manages PAM/ulimit configuration by writing `/etc/pam.d/su` and `/etc/pam.d/sudo`
   - Invokes the `user_ulimit[user]` custom resource (from the `ulimit` cookbook) to set per-user file descriptor and process limits for the Redis service user

6. **redisio::disable_os_default** (`redisio-cac.../recipes/disable_os_default.rb`):
   - Stops and disables the OS-default Redis service to prevent conflicts with the `redisio`-managed instance

7. **redisio::configure** (`redisio-cac.../recipes/configure.rb`):
   - Invokes the `redisio_configure[redis-servers]` custom resource to render `/etc/redis/6379.conf` from the `redisio` cookbook's `redis.conf.erb` template
   - Sets up service management; detects `node['redisio']['job_control']` to select backend:
     - **systemd** (active if systemd is available): Creates and enables a systemd unit for the Redis instance
     - **initd**: Would write a SysV init script — not active on systemd hosts
     - **upstart**: Would write an Upstart job — not active on systemd hosts
     - **rcinit**: Would write an rc.d script — not active on systemd hosts
   - Iterations: Executes once for the single configured server instance (port 6379)

8. **redisio::enable** (`redisio-cac.../recipes/enable.rb`):
   - Iterates over `node['redisio']['servers']` and for each entry conditionally manages service state based on `node['redisio']['job_control'] == 'systemd'`
   - For the single configured instance (port 6379): enables and starts the `redis6379` systemd service unit
   - Iterations: Executes once — **redis6379** service

---

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0`
- `redisio` (pinned to a specific artifact hash — evaluate upgrading or replacing)
- `build-essential` (transitive, required by `redisio` source build path)
- `ulimit` (transitive, required by `redisio::ulimit`)

**System package dependencies**:
- Build toolchain packages (gcc, make, etc.) installed by `build_essential` resource during source build
- No OS Redis package installed (source build path is active)

**Service dependencies**:
- `redis6379.service` (systemd unit managed by `redisio`)
- `memcached.service` (managed by `memcached` cookbook)

---

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded plaintext string in recipe attribute assignment
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded plaintext value `redis_secure_password_123` assigned directly in recipe via `node.default['redisio']['servers']` array
- **Usage context**: Passed to the `redisio` cookbook which writes the value as the `requirepass` directive in `/etc/redis/6379.conf`, requiring all Redis clients to authenticate with this password
- **Remediation required**: Remove hardcoded value and source from a secrets management backend (Chef Vault, AWS Secrets Manager, HashiCorp Vault, or encrypted data bag) prior to migration. The target mechanism must be specified and implemented before this cookbook is migrated.

---

## Checks for the Migration

**Files to verify**:
- `cookbooks/cache/metadata.rb`
- `cookbooks/cache/recipes/default.rb`
- `/etc/redis/6379.conf`
- `/var/log/redis/` (directory)
- `/etc/pam.d/su`
- `/etc/pam.d/sudo`
- Systemd unit file for `redis6379`

**Service endpoints to check**:
- Redis: `127.0.0.1:6379`
- Memcached: `127.0.0.1:11211`

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` (rendered once, for the single server instance on port 6379; subsequently patched by `ruby_block "fix_redis_config"`)

---

## Pre-flight Checks

```bash
# --- Memcached instance ---
systemctl status memcached
echo "stats" | nc -q1 127.0.0.1 11211

# --- Redis instance: redis6379 ---
systemctl status redis6379
redis-cli -p 6379 -a 'redis_secure_password_123' ping
redis-cli -p 6379 -a 'redis_secure_password_123' info server | grep redis_version

# --- Validate Redis config file ---
test -f /etc/redis/6379.conf && echo "Config exists" || echo "MISSING: /etc/redis/6379.conf"

# --- Confirm hack-stripped directives are absent from config ---
grep -E "^replica-serve-stale-data|^replica-read-only|^repl-ping-replica-period|^client-output-buffer-limit|^replica-priority" /etc/redis/6379.conf \
  && echo "WARNING: stripped directives still present" || echo "OK: stripped directives absent"

# --- Validate log directory ---
test -d /var/log/redis && echo "Log dir exists" || echo "MISSING: /var/log/redis"

# --- Validate PAM ulimit files ---
test -f /etc/pam.d/su && echo "OK: /etc/pam.d/su" || echo "MISSING: /etc/pam.d/su"
test -f /etc/pam.d/sudo && echo "OK: /etc/pam.d/sudo" || echo "MISSING: /etc/pam.d/sudo"

# --- Confirm OS default Redis service is disabled ---
systemctl is-enabled redis 2>/dev/null && echo "WARNING: OS default redis service is still enabled" || echo "OK: OS default redis service disabled"

# --- Confirm Redis version (expected 3.2.11 from source build) ---
redis-server --version

# --- Confirm systemd job_control is active ---
systemctl list-units --type=service | grep redis6379
```