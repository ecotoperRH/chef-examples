# Migration Plan: redisio

**TLDR**: The `redisio` cookbook installs, configures, and manages one or more Redis server instances (and optionally Redis Sentinel instances) on Linux/FreeBSD nodes. It supports installation from source tarball or OS package, and supports multiple service managers: `initd`, `upstart`, `systemd`, and `rcinit` (FreeBSD). The default entry point (`default.rb`) chains `install` → `configure` → `enable`. Multiple Redis instances are supported on a single node, each with independent ports, config files, PID directories, data directories, and service units. Sentinel instances are managed separately via `sentinel.rb` and `sentinel_enable.rb`.

---

## Service Type and Instances

**Service Type**: Cache / In-Memory Data Store (Redis Server + optional Redis Sentinel)

**Configured Instances**:
- **redis6379** (default): Single Redis server instance on port 6379 (default when `node['redisio']['servers']` is not explicitly set)
  - Location/Path: `/etc/redis/` (config), `/var/lib/redis/` (data), `/var/run/redis/` (PID)
  - Port/Socket: `6379`
  - Key Config: `node['redisio']['servers']` array; defaults applied from `node['redisio']['default_settings']`

> **Note**: Additional instances are defined by populating `node['redisio']['servers']` with per-instance hashes specifying at minimum a `port` (and optionally a `name`). Sentinel instances are defined via `node['redisio']['sentinels']`. The exact instance names and ports are node-attribute-driven and must be confirmed per deployment.

---

## File Structure

```
redisio/
├── attributes/
│   └── default.rb
├── libraries/
│   ├── matchers.rb
│   └── redisio.rb
├── providers/
│   ├── configure.rb
│   ├── install.rb
│   └── sentinel.rb
├── recipes/
│   ├── _install_prereqs.rb
│   ├── configure.rb
│   ├── default.rb
│   ├── disable.rb
│   ├── disable_os_default.rb
│   ├── enable.rb
│   ├── install.rb
│   ├── sentinel.rb
│   ├── sentinel_enable.rb
│   └── ulimit.rb
└── resources/
    ├── configure.rb
    ├── install.rb
    └── sentinel.rb
```

---

## Module Explanation

The cookbook performs operations in this order:

**Entry point**: `redisio/recipes/default.rb` calls `install` → `configure` → `enable` in sequence.

1. **default** (`redisio/recipes/default.rb`):
   - Includes `redisio::install`
   - Includes `redisio::configure`
   - Includes `redisio::enable`
   - This is the primary entry point for the cookbook.

2. **_install_prereqs** (`redisio/recipes/_install_prereqs.rb`):
   - Installs the `tar` package on Debian and RHEL/Fedora platform families.
   - No-op on FreeBSD and other platforms.
   - Called as a dependency by `configure.rb` and `sentinel.rb`.

3. **install** (`redisio/recipes/install.rb`):
   - Sets `node['redisio']['servers']` to `[{ 'port' => '6379' }]` if not already defined.
   - Constructs the download URL from `node['redisio']['mirror']`, `base_name`, `version`, and `artifact_type`.
   - Invokes the `redisio_install` custom resource (`redisio/resources/install.rb` / `redisio/providers/install.rb`):
     - **If `package_install` is true**: installs the OS package (e.g., `redis-server` on Debian, `redis` on RHEL).
     - **If source install** (default on non-FreeBSD): downloads tarball via `remote_file` from `http://download.redis.io/releases/`, unpacks with `tar`, runs `make clean && make`, then `make install` (with optional `PREFIX` if `install_dir` is set).
     - Skips install if `safe_install` is `true` and `redis-server` binary already exists.

4. **configure** (`redisio/recipes/configure.rb`):
   - Includes `redisio::_install_prereqs` and `redisio::install`.
   - Invokes the `redisio_configure` custom resource (`redisio/resources/configure.rb` / `redisio/providers/configure.rb`).
   - **Provider iterates over each server in `node['redisio']['servers']`** (expanded below):
     - **Instance: redis6379** (port `6379`, default):
       1. Merges `node['redisio']['default_settings']` with per-instance settings.
       2. Computes `maxmemory` (supports percentage of total RAM).
       3. Computes file descriptor limit (`descriptors`).
       4. Creates the `redis` system user and group.
       5. Creates config directory (`/etc/redis/`), data directory (`/var/lib/redis/`), PID directory (`/var/run/redis/`), log directory/file.
       6. Applies SELinux file contexts (`redis_conf_t`, `redis_var_lib_t`, etc.) if SELinux is enabled.
       7. Sets `user_ulimit` for the `redis` user.
       8. Optionally loads `requirepass` and `masterauth` from a Chef data bag (see Credentials).
       9. Renders `/etc/redis/redis6379.conf` from `redis.conf.erb` template (skipped if breadcrumb file exists).
       10. Creates breadcrumb file alongside the config to prevent future overwrites.
       11. Renders service init file based on `node['redisio']['job_control']`:
           - `initd`: `/etc/init.d/redis6379`
           - `upstart`: `/etc/init/redis6379.conf`
           - `rcinit`: `/usr/local/etc/rc.d/redis6379`
           - `systemd`: `/lib/systemd/system/redis@6379.service` + `/etc/tmpfiles.d/redis@6379.conf`, notifies `systemctl daemon-reload`

5. **enable** (`redisio/recipes/enable.rb`):
   - Includes `redisio::configure`.
   - Iterates over `node['redisio']['servers']` and creates a `service` resource for each instance:
     - **Instance: redis6379**:
       - `initd`: `service[redis6379]`
       - `upstart`: `service[redis6379]` with Upstart provider
       - `systemd`: `service[redis@6379]` with Systemd provider
       - `rcinit`: `service[redis6379]` with FreeBSD RC provider
   - Starts and enables each service.

6. **disable** (`redisio/recipes/disable.rb`):
   - **Requires `enable.rb` to have already run** (mutates already-declared service resources).
   - Iterates over `node['redisio']['servers']` and appends `:stop` and `:disable` actions to each service resource:
     - **Instance: redis6379**: stops and disables `service[redis6379]` (or `service[redis@6379]` for systemd).

7. **disable_os_default** (`redisio/recipes/disable_os_default.rb`):
   - Stops and disables the OS-default Redis service:
     - Debian: `redis-server`
     - RHEL/Fedora: `redis`
   - Used when migrating from a package-installed Redis to the cookbook-managed instance.

8. **ulimit** (`redisio/recipes/ulimit.rb`):
   - On Debian: manages `/etc/pam.d/su` and `/etc/pam.d/sudo` from cookbook templates/files.
   - Iterates over `node['ulimit']['users']` and calls the `user_ulimit` resource for each defined user.

9. **sentinel** (`redisio/recipes/sentinel.rb`):
   - Includes `redisio::_install_prereqs`, `redisio::install`, and `redisio::ulimit`.
   - Uses `node['redisio']['sentinels']` (or a default single-sentinel config) to invoke the `redisio_sentinel` custom resource (`redisio/resources/sentinel.rb` / `redisio/providers/sentinel.rb`).
   - **Provider iterates over each sentinel in `node['redisio']['sentinels']`**:
     1. Merges `sentinel_defaults` with per-sentinel settings.
     2. Creates the `redis` user, config dir, PID dir, log dir/file.
     3. Handles backward-compatible old sentinel format (single `master_ip`/`master_port` keys).
     4. Optionally loads `auth_pass` from a Chef data bag (see Credentials).
     5. Merges per-master settings with defaults.
     6. Validates required fields: `master_ip`, `master_port`, `quorum_count`.
     7. Renders `sentinel.conf.erb` (skipped if breadcrumb file exists).
     8. Creates breadcrumb file.
     9. Renders service init file for `initd`, `upstart`, or `rcinit`.
   - For systemd: creates `/lib/systemd/system/redis-sentinel@.service` template in the recipe (shared template, not per-sentinel).
   - Creates a `service` resource for each sentinel instance named by sentinel name.

10. **sentinel_enable** (`redisio/recipes/sentinel_enable.rb`):
    - Iterates over `node['redisio']['sentinels']` (or default).
    - Looks up the already-declared sentinel service resource and appends `:start` action.
    - For non-systemd: also appends `:enable`.
    - For systemd: creates a symlink in `multi-user.target.wants/` and notifies `systemctl daemon-reload`.

---

## Dependencies

**External cookbook dependencies**:
- `build_essential` — provides `build_essential[install build deps]` resource for source compilation
- `user_ulimit` — provides `user_ulimit[user]` resource for per-user file descriptor limits

**System package dependencies**:
- `tar` — installed by `_install_prereqs.rb` on Debian and RHEL/Fedora
- `redis-server` (Debian) or `redis` (RHEL/Fedora/FreeBSD) — when `package_install` is `true`
- Build tools (gcc, make, etc.) — when installing from source via `build_essential`

**Service dependencies**:
- `redis@<name>.service` or `redis<name>` — per-instance Redis service unit
- `redis-sentinel@<name>.service` or `redis-sentinel<name>` — per-instance Sentinel service unit (if sentinel recipe is used)

---

## Credentials

**Detection Summary**: 3 credential variables detected across 2 files

**Source**:
- **Provider**: Chef Data Bag
- **URL**: N/A
- **Path**: Data bag name, item, and key are specified per server/sentinel instance via `data_bag_name`, `data_bag_item`, and `data_bag_key` attributes on each instance hash in `node['redisio']['servers']` and `node['redisio']['sentinels']`

### Redis Server Authentication Password (`requirepass`)
- **Variable(s)**: `requirepass`, controlled by `data_bag_name`, `data_bag_item`, `data_bag_key` per server instance
- **Source file(s)**: `redisio/providers/configure.rb`
- **Current storage**: Chef data bag (loaded at converge time if `data_bag_name` is set on the server instance)
- **Usage context**: Sets the Redis `requirepass` directive in `redis.conf`, requiring clients to authenticate before executing commands

### Redis Replication Authentication Password (`masterauth`)
- **Variable(s)**: `masterauth`, controlled by `data_bag_name`, `data_bag_item`, `data_bag_key` per server instance
- **Source file(s)**: `redisio/providers/configure.rb`
- **Current storage**: Chef data bag (loaded at converge time if `data_bag_name` is set on the server instance)
- **Usage context**: Sets the Redis `masterauth` directive in `redis.conf`, used by replica instances to authenticate with their master

### Redis Sentinel Authentication Password (`auth_pass`)
- **Variable(s)**: `auth_pass`, controlled by `data_bag_name`, `data_bag_item`, `data_bag_key` per sentinel instance
- **Source file(s)**: `redisio/providers/sentinel.rb`
- **Current storage**: Chef data bag (loaded at converge time if `data_bag_name` is set on the sentinel instance)
- **Usage context**: Sets the `auth-pass` directive in `sentinel.conf`, used by Sentinel to authenticate with monitored Redis masters

---

## Checks for the Migration

**Files to verify**:
- `redisio/attributes/default.rb`
- `redisio/recipes/default.rb`
- `redisio/recipes/_install_prereqs.rb`
- `redisio/recipes/install.rb`
- `redisio/recipes/configure.rb`
- `redisio/recipes/enable.rb`
- `redisio/recipes/disable.rb`
- `redisio/recipes/disable_os_default.rb`
- `redisio/recipes/ulimit.rb`
- `redisio/recipes/sentinel.rb`
- `redisio/recipes/sentinel_enable.rb`
- `redisio/providers/install.rb`
- `redisio/providers/configure.rb`
- `redisio/providers/sentinel.rb`
- `redisio/resources/install.rb`
- `redisio/resources/configure.rb`
- `redisio/resources/sentinel.rb`
- `redisio/libraries/redisio.rb`
- `redisio/libraries/matchers.rb`
- `/etc/redis/redis6379.conf` (rendered config — default instance)
- `/lib/systemd/system/redis@6379.service` (systemd unit — default instance)
- `/etc/tmpfiles.d/redis@6379.conf` (systemd tmpfiles — default instance)
- `/etc/init.d/redis6379` (initd unit — default instance, if applicable)
- `/etc/init/redis6379.conf` (upstart unit — default instance, if applicable)
- `/lib/systemd/system/redis-sentinel@.service` (sentinel systemd unit, if sentinel used)

**Service endpoints to check**:
- `6379/tcp` — default Redis server instance
- Additional ports as defined in `node['redisio']['servers']`
- `26379/tcp` — default Redis Sentinel port (if sentinel used)

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/redis<name>.conf` — rendered once per server instance (skipped if breadcrumb exists)
- `redis@.service.erb` → `/lib/systemd/system/redis@<name>.service` — rendered once per server instance (systemd only)
- `redis@.conf.erb` → `/etc/tmpfiles.d/redis@<name>.conf` — rendered once per server instance (systemd only)
- `redis<name>.init.erb` → `/etc/init.d/redis<name>` — rendered once per server instance (initd only)
- `redis<name>.conf.erb` → `/etc/init/redis<name>.conf` — rendered once per server instance (upstart only)
- `sentinel.conf.erb` → per-sentinel config file — rendered once per sentinel instance (skipped if breadcrumb exists)
- `redis-sentinel@.service.erb` → `/lib/systemd/system/redis-sentinel@.service` — rendered once (shared, systemd only)
- PAM templates → `/etc/pam.d/su`, `/etc/pam.d/sudo` — rendered by `ulimit.rb` on Debian

---

## Pre-flight checks

```bash
# ── Redis binary and version ──────────────────────────────────────────────────
which redis-server && redis-server --version
# Expected: Redis server v=3.2.11 (or configured version)

# ── Default instance (redis6379) ─────────────────────────────────────────────
# Service status
systemctl status redis@6379.service        # systemd
# OR
service redis6379 status                   # initd/upstart

# Config file present
test -f /etc/redis/redis6379.conf && echo "OK: config exists" || echo "MISSING: /etc/redis/redis6379.conf"

# Breadcrumb file (prevents config overwrite)
test -f /etc/redis/redis6379.conf.breadcrumb && echo "OK: breadcrumb exists" || echo "INFO: no breadcrumb — config will be rendered"

# Data directory
test -d /var/lib/redis && ls -la /var/lib/redis/

# PID directory
test -d /var/run/redis && ls -la /var/run/redis/

# Port listening
ss -tlnp | grep ':6379' || netstat -tlnp | grep ':6379'

# Redis connectivity
redis-cli -p 6379 ping
# Expected: PONG

# Redis INFO (auth required if requirepass is set)
redis-cli -p 6379 INFO server | grep redis_version

# ── Sentinel instance (if applicable) ────────────────────────────────────────
# Service status
systemctl status redis-sentinel@<sentinel-name>.service   # systemd
# OR
service redis-sentinel<sentinel-name> status              # initd/upstart

# Sentinel config
test -f /etc/redis/sentinel-<sentinel-name>.conf && echo "OK" || echo "MISSING"

# Sentinel port listening (default 26379)
ss -tlnp | grep ':26379' || netstat -tlnp | grep ':26379'

# Sentinel connectivity
redis-cli -p 26379 ping

# ── System user ───────────────────────────────────────────────────────────────
id redis
# Expected: uid=<N>(redis) gid=<N>(redis) groups=<N>(redis)

# ── Ulimit / file descriptors ─────────────────────────────────────────────────
# Check effective limits for redis user
su -s /bin/sh redis -c 'ulimit -n'
# Expected: >= maxclients (default 10000) + headroom

# ── SELinux (RHEL/Fedora only) ────────────────────────────────────────────────
getenforce
# If Enforcing, verify file contexts:
ls -Z /etc/redis/redis6379.conf
# Expected: system_u:object_r:redis_conf_t:s0

# ── Systemd unit files (systemd only) ────────────────────────────────────────
test -f /lib/systemd/system/redis@6379.service && echo "OK: unit file exists"
test -f /etc/tmpfiles.d/redis@6379.conf && echo "OK: tmpfiles entry exists"
systemctl is-enabled redis@6379.service
# Expected: enabled

# ── PAM ulimit files (Debian only) ───────────────────────────────────────────
grep -i redis /etc/pam.d/su
grep -i redis /etc/pam.d/sudo

# ── Data bag credential check (if credentials are data-bag-sourced) ───────────
# Verify the data bag and item exist on the Chef server before migration:
# knife data bag show <data_bag_name> <data_bag_item>
# Confirm keys: requirepass, masterauth (server), auth_pass (sentinel)

# ── Build tools (source install only) ────────────────────────────────────────
which make && make --version
which gcc && gcc --version

# ── Download mirror reachability (source install only) ───────────────────────
curl -I http://download.redis.io/releases/redis-3.2.11.tar.gz
# Expected: HTTP 200 or 302
```