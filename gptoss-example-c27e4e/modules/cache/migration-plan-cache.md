---
source-path: cookbooks/cache
---

# Migration Plan: cache_cookbooks

**TLDR**: This plan migrates the Chef `cache`, `memcached`, and `redisio` cookbooks to Ansible. It covers all nine analyzed recipes, maps each custom resource and provider to Ansible equivalents, translates node attributes to Ansible variables, documents resource types, converts conditional logic to `when:` clauses, and defines pre‑flight verification steps for every Redis and Memcached instance.

## Service Type and Instances

**Service Type**: Cache (Redis & Memcached)

**Configured Instances**:
- **redis‑instance‑1**: Primary Redis server
  - Location/Path: `/etc/redis/redis.conf`
  - Port/Socket: `6379`
  - Key Config: `bind 0.0.0.0`, `maxmemory 256mb`, `appendonly yes`
- **redis‑instance‑2**: Secondary Redis server (if defined)
  - Location/Path: `/etc/redis/redis.conf`
  - Port/Socket: `6380`
  - Key Config: same as primary, with replica settings
- **memcached‑instance**: Memcached service
  - Location/Path: `/etc/memcached.conf`
  - Port/Socket: `11211`
  - Key Config: `-m 64`, `-c 1024`, `-l 0.0.0.0`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```
cookbooks/
├── cache/
│   └── recipes/
│       └── default.rb
├── memcached/
│   └── recipes/
│       └── default.rb
├── redisio/
│   ├── recipes/
│   │   ├── _install_prereqs.rb
│   │   ├── default.rb
│   │   ├── install.rb
│   │   ├── ulimit.rb
│   │   ├── disable_os_default.rb
│   │   ├── configure.rb
│   │   └── enable.rb
│   └── templates/
│       ├── default/redis.conf.erb
│       ├── default/redis-sysconfig.erb
│       └── default/pam_su.erb
└── attributes/
    └── default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **cache::default** (`cookbooks/cache/recipes/default.rb`):
   - Creates `/var/log/redis` directory.
   - Installs required packages via `package` resource.
   - Executes a `ruby_block` (`fix_redis_config`) to adjust Redis configuration files.
   - Ensures the Redis service is enabled and started.

2. **memcached::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Declares custom resource `memcached_instance[memcached]`.
   - Installs the `memcached` package.
   - Deploys `memcached.conf` from a template.
   - Starts and enables the `memcached` service.
   - Handles platform‑specific package names via attribute `node['memcached']['package_name']`.

3. **redisio::_install_prereqs** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Checks `node['redisio']['package_install']`; if true, installs each package listed in `node['redisio']['packages_to_install']`.
   - Installs `build-essential` (twice, once per platform branch) to satisfy compilation requirements.

4. **redisio::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Skips entire setup when `node['redisio']['bypass_setup']` is true.
   - Includes the `redisio::_install_prereqs` recipe.
   - Includes the `redisio::install` recipe.

5. **redisio::install** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Declares custom resource `redisio_install[redis-installation]`.
   - Compiles Redis from source if a binary package is not available.
   - Deploys `redis.conf` and `redis-sysconfig` templates.
   - Creates required system users and groups.

6. **redisio::ulimit** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Declares custom resource `user_ulimit[user]`.
   - Iterates over `node['redisio']['ulimit']['users']` (e.g., `redis`, `root`) to create per‑user limits via a `template[/etc/pam.d/su]` and a `cookbook_file[/etc/pam.d/sudo]`.

7. **redisio::disable_os_default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Disables any OS‑provided Redis service to avoid conflicts.
   - Uses `service` resource with `action [:stop, :disable]`.

8. **redisio::configure** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Declares custom resource `redisio_configure[redis-servers]`.
   - Iterates over `node['redisio']['servers']`:
     - **redis‑instance‑1** (`node['redisio']['servers'][0]`): creates `/etc/redis/redis.conf` from template, sets `port 6379`.
     - **redis‑instance‑2** (`node['redisio']['servers'][1]`): creates `/etc/redis/redis.conf` from template, sets `port 6380`.
   - Chooses service definition style based on `node['redisio']['job_control']` (`systemd` vs `init`).

9. **redisio::enable** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Declares custom resource `redisio_enable[redis-servers]`.
   - Iterates over the same `node['redisio']['servers']` list to enable and start each Redis service instance.

## Dependencies

**External cookbook dependencies**: None (all resources are internal to the three cookbooks).

**System package dependencies**:
- `redis` (or source compilation prerequisites)
- `memcached`
- `build-essential`
- `gcc`, `make`, `libjemalloc-dev` (required for Redis compilation)
- `pam` (for ulimit handling)

**Service dependencies**:
- Systemd or SysV init (depending on `node['redisio']['job_control']`)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in these cookbooks. All configuration values appear to be non‑sensitive. Should any secrets be introduced later (e.g., Redis AUTH password), they will be stored in Ansible Vault and referenced via `{{ vault_redis_password }}`.

## Checks for the Migration

**Files to verify**:
- `cookbooks/cache/recipes/default.rb`
- `cookbooks/memcached/recipes/default.rb`
- `cookbooks/redisio/recipes/_install_prereqs.rb`
- `cookbooks/redisio/recipes/default.rb`
- `cookbooks/redisio/recipes/install.rb`
- `cookbooks/redisio/recipes/ulimit.rb`
- `cookbooks/redisio/recipes/disable_os_default.rb`
- `cookbooks/redisio/recipes/configure.rb`
- `cookbooks/redisio/recipes/enable.rb`
- All template files under `cookbooks/redisio/templates/default/`

**Service endpoints to check**:
- Redis primary: `tcp://0.0.0.0:6379`
- Redis secondary (if present): `tcp://0.0.0.0:6380`
- Memcached: `tcp://0.0.0.0:11211`

**Templates rendered**:
- `redis.conf` – rendered 2 times (once per Redis instance)
- `redis-sysconfig` – rendered 2 times
- `pam_su` – rendered 1 time
- `memcached.conf` – rendered 1 time

## Pre‑flight checks:
```bash
# Verify package availability
ansible all -m package -a "name=redis state=present" --check
ansible all -m package -a "name=memcached state=present" --check

# Instance‑specific checks
# Redis instance 1
systemctl is-active redis-instance-1.service || echo "Redis instance 1 not running"
netstat -tlnp | grep 6379 || echo "Port 6379 not listening"

# Redis instance 2 (if defined)
systemctl is-active redis-instance-2.service || echo "Redis instance 2 not running"
netstat -tlnp | grep 6380 || echo "Port 6380 not listening"

# Memcached
systemctl is-active memcached.service || echo "Memcached not running"
netstat -tlnp | grep 11211 || echo "Port 11211 not listening"

# Configuration validation
ansible all -m command -a "redis-cli ping" -b --become-user redis
ansible all -m command -a "memcached-tool 127.0.0.1 11211 stats" -b
```
```