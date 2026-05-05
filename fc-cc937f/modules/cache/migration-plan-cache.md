# Migration Plan: cache (memcached + redisio)

**TLDR**: The `cache` cookbook is the entry point that orchestrates two service stacks: a Memcached instance (via the `memcached` community cookbook using a custom systemd-based resource) and one or more Redis instances (via the `redisio` community cookbook using a configure provider). The cookbook creates the `/var/log/redis` directory, installs and configures both services, applies a `ruby_block[fix_redis_config]` post-configuration fixup, and enables all Redis instances. Redis authentication credentials (`requirepass`, `masterauth`) are loaded from a Chef data bag. Migration requires replicating systemd unit generation, PAM/ulimit configuration, SELinux context management, platform-conditional branching, and credential sourcing from a secrets manager.

---

## Service Type and Instances

**Service Type**: Cache (Memcached + Redis)

**Configured Instances**:

- **memcached (default instance)**: In-memory object cache
  - Port: `11211` (TCP + UDP)
  - Listen: `0.0.0.0`
  - Memory: `64` MB (default)
  - Max connections: `1024`
  - Ulimit: `1024`
  - Service management: systemd unit generated inline by `memcached_instance` resource
  - Default OS instance disabled and config removed to avoid port conflicts

- **redis instances** (per `node['redisio']['servers']` array — expand with actual instance names at deploy time):
  - Config directory: `/etc/redis/`
  - Data directory: per-instance (configured via `redisio_configure`)
  - PID directory: `/var/run/redis`
  - Log directory: `/var/log/redis`
  - Port: per-instance (default `6379`)
  - Service management: systemd unit at `/lib/systemd/system/redis@<name>.service`
  - `tmpfiles.d` entry created per instance when `job_control` is `systemd`

---

## File Structure

```
cookbooks/
└── cache/
    └── recipes/
        └── default.rb
cookbooks/
└── memcached/
    ├── recipes/
    │   └── _package.rb
    └── resources/
        └── memcached_instance.rb
cookbooks/
└── redisio/
    ├── recipes/
    │   ├── default.rb
    │   ├── install.rb
    │   ├── configure.rb
    │   ├── _install_prereqs.rb
    │   ├── ulimit.rb
    │   ├── disable_os_default.rb
    │   └── enable.rb
    ├── resources/
    │   ├── install.rb
    │   └── configure.rb
    ├── providers/
    │   ├── install.rb
    │   └── configure.rb
    └── templates/
        └── default/
            ├── domain.erb
            ├── redis-sentinel@.service
            ├── redis.conf.erb
            ├── redis.init.erb
            ├── redis.rcinit.erb
            ├── redis.upstart.conf.erb
            ├── redis@.service.erb
            ├── sentinel.conf.erb
            ├── sentinel.init.erb
            ├── sentinel.rcinit.erb
            ├── sentinel.upstart.conf.erb
            ├── su.erb
            └── ulimit.erb
```

---

## Module Explanation

The cookbook performs operations in this order:

**1. `cache::default`** (`cookbooks/cache/recipes/default.rb`):
- Entry point for the entire execution tree
- Calls `include_recipe 'memcached::default'` to install and configure Memcached
- Creates `directory[/var/log/redis]` — ensures the Redis log directory exists with correct ownership before Redis configuration runs
- Calls `include_recipe 'redisio::default'` to install and configure Redis
- Executes `ruby_block[fix_redis_config]` — an in-converge Ruby block that performs post-render fixups on the Redis configuration file (e.g., correcting values that cannot be expressed cleanly in the ERB template). Must be migrated as an Ansible `lineinfile` or `replace` task, or resolved by adjusting the Jinja2 template directly.
- Calls `include_recipe 'redisio::enable'` to enable and start all Redis service instances

**2. `memcached::default`** (via `include_recipe`):
- Installs the `memcached` package by calling `include_recipe 'memcached::_package'`
- Invokes the `memcached_instance` custom resource to configure and start the Memcached service

**3. `memcached::_package`** (`cookbooks/memcached/recipes/_package.rb`):
- Installs the `memcached` system package via the `package` resource

**4. `memcached_instance` resource** (`cookbooks/memcached/resources/memcached_instance.rb`):
- Provides `memcached_instance` (and legacy alias `memcached_instance_systemd`)
- Disables and optionally removes the default OS-managed memcached instance and config to prevent port conflicts (`disable_default_instance: true`, `remove_default_config: true`)
- Generates a systemd `.service` unit file inline with security hardening flags: `PrivateTmp`, `NoNewPrivileges`, `PrivateDevices`, and others
  - **Platform branch**: RHEL7/CentOS7 receive a reduced set of systemd security flags
- Manages the service via the `systemd_unit` resource with actions `:start`, `:stop`, `:restart`, `:disable`, `:enable`

**5. `redisio::default`** (`cookbooks/redisio/recipes/default.rb`):
- Runs `apt_update` (Debian/Ubuntu only)
- Conditionally calls `include_recipe 'redisio::_install_prereqs'`
- Conditionally invokes `build_essential[install build deps]` when `package_install` is `false` (source build path)
- Calls `include_recipe 'redisio::install'`
- Calls `include_recipe 'redisio::disable_os_default'`
- Calls `include_recipe 'redisio::configure'`

**6. `redisio::_install_prereqs`** (`cookbooks/redisio/recipes/_install_prereqs.rb`):
- Installs prerequisite system packages required before Redis installation
- Called from `redisio::default`; appears twice in the execution tree (once flagged as a potential circular reference)
- Migration: map prerequisite packages to Ansible `package` module tasks

**7. `redisio::install`** (`cookbooks/redisio/recipes/install.rb`):
- Invokes the `redisio_install` custom resource
- Always calls `include_recipe 'redisio::ulimit'`
- **Package path**: delegates to the system `package` resource
- **Tarball path**: downloads via `remote_file`, unpacks with `tar`, runs `make clean && make`, then `make install` (with optional `PREFIX`)
- Conditionally invokes `build_essential[install build deps]` in the tarball/source branch
- Skips reinstall if version matches or binary exists when `safe_install: true`
- **Platform branch**: FreeBSD raises an error (source install unsupported)

**8. `redisio::ulimit`** (`cookbooks/redisio/recipes/ulimit.rb`):
- Manages PAM and ulimit configuration for the Redis user
- Creates `user_ulimit[redis]` custom resource entries (rendered via `ulimit.erb` to `/etc/security/limits.d/`) supporting: `nofile` (soft/hard), `nproc`, `memlock`, `core`, `stack`, `rtprio`, `as`
- Manages `template[/etc/pam.d/su]` rendered from `su.erb` — **Debian platforms only**
- Manages `cookbook_file[/etc/pam.d/sudo]` sourced from `node['ulimit']['ulimit_overriding_sudo_file_name']` — **Debian platforms only**
- Migration: use Ansible `pam_limits` module for ulimit entries; use `template` or `copy` module for PAM files with `when: ansible_os_family == 'Debian'` guard

**9. `redisio::disable_os_default`** (`cookbooks/redisio/recipes/disable_os_default.rb`):
- Stops and disables the OS-managed default Redis service to prevent conflicts
- **Platform branch**:
  - Debian: service name is `redis-server`
  - RHEL/Fedora: service name is `redis`
- Migration: Ansible `service` module with `state: stopped`, `enabled: false`, guarded by `when: ansible_os_family` condition

**10. `redisio::configure`** (`cookbooks/redisio/recipes/configure.rb`):
- Invokes `redisio_configure` custom resource with `version`, `default_settings`, and `servers` list
- Creates one `service` resource per Redis instance; supports `initd`, `upstart`, `systemd`, `rcinit` job control types
- Iterations: expands over all entries in `node['redisio']['servers']` — each entry produces one Redis instance with its own config file, directories, and service unit

**11. `redisio_configure` provider** (`cookbooks/redisio/providers/configure.rb`):
For each server instance in `node['redisio']['servers']`:
1. Detects Redis version from binary or attribute
2. Merges `default_settings` hash with per-instance overrides
3. Resolves `maxmemory` (supports `%` of total RAM, divided across instances)
4. Calculates file descriptor count (`descriptors`) from `ulimit`/`maxclients`
5. Creates: `user`, config `directory`, data `directory`, PID `directory`, log `directory`
6. Configures **SELinux** contexts if SELinux is enabled — sets types `redis_conf_t`, `redis_var_lib_t`, `redis_var_run_t`, `redis_log_t`. Migration: use `community.general.sefcontext` Ansible module.
7. Creates log file, AOF file, RDB file with correct ownership
8. Sets `user_ulimit` resource (skipped on FreeBSD)
9. Loads `requirepass` and `masterauth` from a **Chef data bag** (see Credentials section)
10. Renders `redis.conf.erb` with all ~70 configuration variables — **skipped if a breadcrumb file exists** (idempotency guard). Migration: replicate with Ansible `stat` + `when` condition or `creates` parameter.
11. Renders init system file based on `job_control`:
    - `initd` → `/etc/init.d/redis-<name>`
    - `upstart` → `/etc/init/redis-<name>.conf`
    - `rcinit` → `/usr/local/etc/rc.d/redis-<name>`
    - `systemd` → `/lib/systemd/system/redis@<name>.service` + `tmpfiles.d` entry + explicit `systemctl daemon-reload`. Migration: Ansible `systemd` module with `daemon_reload: true`.

**12. `redisio::enable`** (`cookbooks/redisio/recipes/enable.rb`):
- Final step in the execution tree; called from `cache::default` after `ruby_block[fix_redis_config]`
- Enables and starts each Redis service instance
- **Platform branch**: systemd path uses `systemctl enable redis@<name>` style unit targeting
- Migration: Ansible `systemd` module with `state: started`, `enabled: true` per instance

---

## Dependencies

**External cookbook dependencies**:
- `memcached` (community cookbook — provides `memcached_instance` custom resource and `memcached::_package` recipe)
- `redisio` (community cookbook — provides full Redis install/configure/enable lifecycle)
- `build-essential` (Chef supermarket cookbook — provides `build_essential` resource used in source-install path)
- `user_ulimit` (community cookbook — provides `user_ulimit` custom resource used in `redisio::ulimit`)

**System package dependencies**:
- `memcached` (system package, installed by `memcached::_package`)
- `redis` or `redis-server` (system package, installed by `redisio::install` on package path)
- Prerequisite packages installed by `redisio::_install_prereqs` (exact list requires inspection of that recipe)
- Build tools (`build-essential`, `gcc`, `make`) — required on source-install path

**Service dependencies**:
- `memcached.service` (systemd, generated inline by `memcached_instance` resource)
- `redis@<name>.service` (systemd, generated by `redisio_configure` provider per instance)
- Default OS services disabled: `memcached` (default instance), `redis-server` (Debian) / `redis` (RHEL/Fedora)

---

## Credentials

**Detection Summary**: 2 credentials detected across 1 file

**Source**:
- **Provider**: Chef Encrypted Data Bag (or plain data bag)
- **Path**: `cookbooks/redisio/providers/configure.rb`

### Redis Authentication Password (`requirepass`)
- **Variable(s)**: `requirepass`
- **Source file(s)**: `cookbooks/redisio/providers/configure.rb`
- **Current storage**: Chef data bag (`data_bag_item` call inside `redisio_configure` provider)
- **Usage context**: Redis client authentication — written into `redis.conf.erb` as the `requirepass` directive; required by any client connecting to the Redis instance

### Redis Replication Authentication Password (`masterauth`)
- **Variable(s)**: `masterauth`
- **Source file(s)**: `cookbooks/redisio/providers/configure.rb`
- **Current storage**: Chef data bag (`data_bag_item` call inside `redisio_configure` provider)
- **Usage context**: Redis replication authentication — written into `redis.conf.erb` as the `masterauth` directive; used by replica nodes to authenticate with the primary

---

## Checks for the Migration

**Files to verify**:
- `/etc/memcached.conf` (default instance config — should be absent/removed)
- `/lib/systemd/system/memcached-<instance>.service` (generated systemd unit)
- `/etc/redis/<instance>.conf` (per Redis instance config)
- `/lib/systemd/system/redis@<instance>.service` (per Redis instance systemd unit)
- `/etc/tmpfiles.d/redis-<instance>.conf` (per Redis instance tmpfiles.d entry)
- `/var/log/redis/` (directory, correct ownership)
- `/var/run/redis/` (PID directory)
- `/etc/security/limits.d/redis.conf` (ulimit entries)
- `/etc/pam.d/su` (Debian only — rendered from `su.erb`)
- `/etc/pam.d/sudo` (Debian only — from cookbook_file)
- Redis breadcrumb file (path defined in `redisio_configure` provider — verify idempotency behavior)

**Service endpoints to check**:
- Memcached: `0.0.0.0:11211` (TCP), `0.0.0.0:11211` (UDP)
- Redis: per-instance port (default `6379`)

**Templates rendered**:
- `redis.conf.erb` — rendered once per Redis instance (skipped if breadcrumb exists)
- `redis@.service.erb` — rendered once per Redis instance (systemd path)
- `ulimit.erb` — rendered once per Redis user ulimit entry
- `su.erb` → `/etc/pam.d/su` — rendered once (Debian only)
- `redis.init.erb` → `/etc/init.d/redis-<name>` — rendered per instance (initd path only)
- `redis.upstart.conf.erb` → `/etc/init/redis-<name>.conf` — rendered per instance (upstart path only)
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis-<name>` — rendered per instance (rcinit path only)

---

## Pre-flight Checks

```bash
# ── System prerequisites ──────────────────────────────────────────────────────

# Verify memcached package is installed
dpkg -l memcached 2>/dev/null || rpm -q memcached

# Verify redis package is installed (package-install path)
dpkg -l redis-server 2>/dev/null || rpm -q redis

# Verify build tools present (source-install path only)
which make && which gcc

# ── Memcached instance ────────────────────────────────────────────────────────

# Check memcached systemd unit exists and is active
systemctl status memcached.service

# Verify memcached is listening on port 11211
ss -tlnp | grep 11211

# Confirm default OS memcached instance is disabled
systemctl is-enabled memcached 2>/dev/null && echo "WARNING: default memcached still enabled"

# ── Redis log directory ───────────────────────────────────────────────────────

# Verify /var/log/redis exists with correct ownership
ls -ld /var/log/redis
stat /var/log/redis

# ── Redis instances (expand for each named instance) ─────────────────────────

# For each Redis instance (replace <instance> with actual name, e.g. default, cache, session):

# Check Redis config file exists
ls -l /etc/redis/<instance>.conf

# Check Redis systemd unit exists
ls -l /lib/systemd/system/redis@<instance>.service

# Check tmpfiles.d entry exists
ls -l /etc/tmpfiles.d/redis-<instance>.conf

# Check Redis service is active and enabled
systemctl status redis@<instance>.service
systemctl is-enabled redis@<instance>.service

# Verify Redis is listening on expected port
ss -tlnp | grep 6379

# Verify Redis responds to PING
redis-cli -p 6379 PING

# Verify Redis authentication (requirepass set)
redis-cli -p 6379 -a "$REDIS_PASSWORD" PING

# Check PID directory exists
ls -ld /var/run/redis

# ── Disable OS default Redis ──────────────────────────────────────────────────

# Debian: confirm redis-server default service is stopped and disabled
systemctl is-active redis-server && echo "WARNING: default redis-server still active"
systemctl is-enabled redis-server && echo "WARNING: default redis-server still enabled"

# RHEL/Fedora: confirm redis default service is stopped and disabled
systemctl is-active redis && echo "WARNING: default redis still active"
systemctl is-enabled redis && echo "WARNING: default redis still enabled"

# ── PAM / ulimit (Debian only) ────────────────────────────────────────────────

# Verify ulimit entries for redis user
grep redis /etc/security/limits.d/*.conf

# Verify PAM su file exists (Debian only)
test -f /etc/pam.d/su && echo "OK" || echo "MISSING: /etc/pam.d/su"

# Verify PAM sudo file exists (Debian only)
test -f /etc/pam.d/sudo && echo "OK" || echo "MISSING: /etc/pam.d/sudo"

# ── SELinux contexts (RHEL/Fedora with SELinux enforcing) ─────────────────────

# Check SELinux is in enforcing or permissive mode
getenforce

# Verify Redis file contexts are set correctly
ls -Z /etc/redis/
ls -Z /var/lib/redis/
ls -Z /var/run/redis/
ls -Z /var/log/redis/

# ── Credentials / data bag ────────────────────────────────────────────────────

# Verify Redis requirepass is set (non-empty) in rendered config
grep "^requirepass" /etc/redis/<instance>.conf

# Verify Redis masterauth is set (non-empty) in rendered config (replication setups)
grep "^masterauth" /etc/redis/<instance>.conf

# ── Post-converge: ruby_block[fix_redis_config] equivalent ───────────────────

# Verify the config fixup was applied (check for the specific line/value that
# fix_redis_config was correcting — inspect the ruby_block source for exact pattern)
grep "<expected_fixed_value>" /etc/redis/<instance>.conf

# ── systemd daemon state ──────────────────────────────────────────────────────

# Confirm systemd has loaded all new unit files
systemctl daemon-reload
systemctl list-units 'redis@*' --all
systemctl list-units 'memcached*' --all
```