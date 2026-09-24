---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The **cache** cookbook provisions two cache services – **Memcached** (single instance named *memcached*) and **Redis** (configurable via the `redisio` dependency). It installs packages, creates users/groups, configures directories, renders service configuration templates, and enables the services. No credentials or secrets are embedded in the cookbook.

## Service Type and Instances

**Service Type**: Cache (Memcached & Redis)

**Configured Instances**:
- **memcached**: Memcached service
  - Location/Path: Managed by the `memcached_instance` custom resource
  - Port/Socket: 11211
  - Key Config: Uses the `memcached_instance['memcached']` custom resource; starts and enables the service.
- **Redis**: No Redis servers are defined by default. Define entries under `node['redisio']['servers']` (e.g., `node['redisio']['servers']['redis1'] = { ... }`) to create named Redis instances.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```
**Recipes:**
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb

**Providers:**
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb

**Templates:**
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis-sentinel@.service
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/sentinel.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/<dynamic>

**Attributes:**
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb

**Files (static):**
*None* – all files are generated from templates or installed via packages.
```

## Module Explanation

The cookbook runs in the order shown below. Full paths are used.

1. **`cookbooks/cache/recipes/default.rb`**
   - Includes **`memcached::default`** (`migration-dependencies/.../memcached/.../recipes/default.rb`)
     - Calls custom resource **`memcached_instance['memcached']`** with attributes (memory, port, bind address).
     - Actions: `[:start, :enable]`.
   - Includes **`redisio::default`** (`migration-dependencies/.../redisio/.../recipes/default.rb`)
     1. **`apt_update`** – updates package index.
     2. **Conditional** `unless node['redisio']['package_install']` → runs **`redisio::_install_prereqs`** (`recipes/_install_prereqs.rb`)
        - Installs each prerequisite package listed in `packages_to_install` (e.g., `build-essential`, `libjemalloc-dev`). *(expanded list based on typical redisio defaults)*
        - Executes custom resource **`build_essential[install build deps]`**.
     3. **Conditional** `unless node['redisio']['bypass_setup']` → runs **`redisio::install`** (`recipes/install.rb`)
        - If `node['redisio']['package_install']` is true, installs **`redisio_package_name`** (typically `redis-server`).
        - Otherwise runs **`redisio::_install_prereqs`** again and executes custom resource **`redisio_install[redis-installation]`**.
        - Calls **`redisio::ulimit`** (`recipes/ulimit.rb`):
          - On Debian families renders **template[/etc/pam.d/su]** and **cookbook_file[/etc/pam.d/sudo]**.
          - If `node['redisio']['ulimit']['users']` is defined, iterates over each user and creates **`user_ulimit[user]`** custom resources.
     4. **`redisio::disable_os_default`** (`recipes/disable_os_default.rb`)
        - Stops and disables any OS‑provided Redis service via **`service[service_name]`**.
     5. **`redisio::configure`** (`recipes/configure.rb`)
        - Renders main Redis configuration template (`redis.conf.erb`) to `${node['redisio']['default_settings']['configdir']}/redis.conf` using **`redisio/providers/configure.rb`**.
   - Includes **`redisio::enable`** (`recipes/enable.rb`)
     - Iterates over `node['redisio']['servers']`. For each defined server (none by default) it:
       - Renders the appropriate service unit template (`redis@.service.erb`, `redis.init.erb`, `redis.upstart.conf.erb`, etc.).
       - Deploys the unit via **`redisio/providers/configure.rb`**.
   - After the includes, the **cache** recipe creates additional resources:
     - **directory** `/var/log/redis` (mode `0755`).
     - **group** `redis`.
     - **ruby_block** `fix_redis_config` – reads the generated Redis config file and applies any needed fixes.
2. **`memcached::default`** (executed via include)
   - Calls **`memcached_instance['memcached']`** (already described above).

### Expanded .each Loops
- **Prerequisite packages installed**: `build-essential`, `libjemalloc-dev`, `tcl`, `pkg-config` *(example list based on redisio defaults)*.
- **Redis servers**: *No servers defined; loop produces no resources.*

## Dependencies

- **External cookbook dependencies**: `memcached`, `redisio`, `build-essential`, `ulimit`
- **System package dependencies**: `memcached`, `redis-server` (or `redis` when `node['redisio']['package_install']` is true), `gcc`, `make`, `libjemalloc-dev`, `tcl`, `pkg-config`
- **Service dependencies**: Systemd, Upstart, or SysV init (chosen at runtime)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

No credentials or secrets were detected in this cookbook. All configuration values appear to be non‑sensitive.

## Checks for the Migration

**Files to verify**:
- `/etc/redis/redis.conf` (if any Redis server defined)
- `/var/log/redis/` directory
- `/etc/pam.d/su` and `/etc/pam.d/sudo` (Debian families only)
- Memcached service unit (`/etc/systemd/system/memcached.service` or `/etc/init.d/memcached`)

**Service endpoints to check**:
- **Memcached** – TCP port **11211**
- **Redis** – TCP port **6379** (only if a Redis server is defined)

**Templates rendered**:
- `redis.conf.erb` – once per Redis server (none by default)
- Service unit templates (`redis@.service.erb`, `redis.init.erb`, `redis.upstart.conf.erb`, etc.) – once per Redis server
- Sentinel templates (rendered only when sentinel is enabled; not in default flow)
- PAM/SU template (`/etc/pam.d/su`) – once on Debian families
- `sudo` cookbook_file – once on Debian families

## Pre‑flight checks:
```bash
# Memcached checks
systemctl status memcached
ps aux | grep memcached
netstat -tulpn | grep 11211
ss -tlnp | grep 11211
# Optional quick test
printf "stats\nquit\n" | nc 127.0.0.1 11211

# Redis checks (run only if a Redis server is defined, e.g., redis1)
# Example for a server named redis1
systemctl status redis@redis1
ps aux | grep redis
netstat -tulpn | grep 6379
ss -tlnp | grep 6379
redis-cli -h 127.0.0.1 -p 6379 ping   # should return PONG
grep -E 'port|bind|maxmemory' /etc/redis/redis.conf
```