---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services on a single host: **Memcached** (in-memory object cache) and **Redis** (persistent key-value store). Memcached is deployed via the `memcached_instance` custom resource with default settings (64 MB memory, port 11211). Redis is installed from source (version 3.2.11 by default, or via OS package on FreeBSD), configured with a single instance on port 6379 with password authentication (`redis_secure_password_123` — a hardcoded credential), and managed as a systemd service (`redis@6379`). A post-configuration `ruby_block` hack strips several deprecated replica-related directives from the generated `/etc/redis/6379.conf` to ensure compatibility.

---

## Service Type and Instances

**Service Type**: Cache (dual-service: Memcached + Redis)

**Configured Instances**:

- **memcached** (Memcached instance):
  - Location/Path: `/var/log/memcached` (log), `/var/run/memcached` (PID), `/nonexistent` (user home)
  - Port/Socket: TCP port **11211**, UDP port **11211**
  - Key Config: memory=64 MB, maxconn=1024, listen=0.0.0.0, max_object_size=1m, ulimit=1024, threads=default, managed as systemd service (`:start, :enable`)

- **redis / port 6379** (Redis instance):
  - Location/Path: config=`/etc/redis/6379.conf`, data=`/var/lib/redis`, PID dir=`/var/run/redis/6379`, log=syslog (local0), systemd unit=`/lib/systemd/system/redis@6379.service`, tmpfiles=`/etc/tmpfiles.d/redis@6379.conf`
  - Port/Socket: TCP port **6379**
  - Key Config: requirepass=`redis_secure_password_123` (hardcoded), backuptype=rdb, maxclients=10000, loglevel=notice, syslog-enabled=yes, replicaservestaledata=nil (stripped by ruby_block hack), clusterenabled=no, version=3.2.11 (source install on Debian/RHEL)

---

## File Structure

**Recipes:**
```
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
```

**Templates:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
```

**Attributes:**
```
cookbooks/cache/metadata.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

---

## Module Explanation

The cookbook performs operations in this order:

**1. cache::default** (`cookbooks/cache/recipes/default.rb`):
- Entry point. Sets `node['redisio']['servers']` to a single-element array: `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Calls `include_recipe 'memcached'` (triggers the full memcached setup)
- Creates directory `/var/log/redis` with owner=redis, group=redis, mode=0755, recursive=true
- Calls `include_recipe 'redisio'` (triggers the full Redis setup)
- Executes `ruby_block 'fix_redis_config'`: reads `/etc/redis/6379.conf` and strips the following lines using regex substitution:
  - `replica-serve-stale-data ...`
  - `replica-read-only ...`
  - `repl-ping-replica-period ...`
  - `client-output-buffer-limit ...`
  - `replica-priority ...`
- Calls `include_recipe 'redisio::enable'` (starts and enables the Redis service)
- Resources: directory (1), ruby_block (1), include_recipe (3)

---

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
- Uses custom resource `memcached_instance['memcached']` (custom resource from memcached cookbook)
  - Internally calls `_package.rb` which installs the `memcached` OS package (version=nil → latest)
  - Creates system group `memcached` (only if user does not already exist)
  - Creates system user `memcached` with shell=/bin/false, home=/nonexistent, locked account
  - Creates directory `/var/log/memcached` (owner=memcached, group=memcached, mode=0755)
  - Creates directory `/var/run/memcached` (owner=memcached, group=memcached, mode=0755)
  - Configures the instance with: memory=64 MB, port=11211, udp_port=11211, listen=0.0.0.0, maxconn=1024, max_object_size=1m, ulimit=1024, experimental_options=[], extra_cli_options=[]
  - Actions: `:start, :enable` (starts and enables the memcached systemd service)
- Resources: memcached_instance (1) → internally: package (1), group (1), user (1), directory (2), service (1)

---

**3. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
- Runs `apt_update` (refreshes APT cache on Debian/Ubuntu)
- Conditional: `unless node['redisio']['package_install']` — since `package_install` defaults to `false` on Debian/RHEL (only `true` on FreeBSD), this block **executes** on Debian/RHEL:
  - Calls `include_recipe 'redisio::_install_prereqs'` (installs `tar` package)
  - Calls `build_essential 'install build deps'` (installs gcc, make, build tools)
- Conditional: `unless node['redisio']['bypass_setup']` — since `bypass_setup` defaults to `false`, this block **always executes**:
  - Calls `include_recipe 'redisio::install'`
  - Calls `include_recipe 'redisio::disable_os_default'`
  - Calls `include_recipe 'redisio::configure'`
- Resources: apt_update (1), build_essential (1), include_recipe (3)

---

**4. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
- Installs prerequisite packages needed to build Redis from source
- On Debian/Ubuntu: installs package **`tar`**
- On RHEL/Fedora: installs package **`tar`**
- On other platforms: installs nothing
- Resources: package (1) — `tar`

---

**5. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
- Conditional: `if node['redisio']['package_install']` — **false** on Debian/RHEL, so the **else branch** executes:
  - Calls `include_recipe 'redisio::_install_prereqs'` again (idempotent, `tar` already installed)
  - Calls `build_essential 'install build deps'` (idempotent)
  - Uses custom resource `redisio_install['redis-installation']`:
    - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`
    - Downloads tarball from `http://download.redis.io/releases/redis-3.2.11.tar.gz`
    - Extracts to a temp directory, runs `make clean && make`, then `make install`
    - Installs binaries to `/usr/local/bin/` (redis-server, redis-cli, etc.)
    - Skips if Redis binary already exists and `safe_install=true` (default)
- Calls `include_recipe 'redisio::ulimit'`
- Resources: redisio_install (1), include_recipe (2)

---

**6. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
- Conditional: `if platform_family?('debian')` — on Debian/Ubuntu only:
  - Deploys template `/etc/pam.d/su` (from `ulimit['pam_su_template_cookbook']`, defaults to nil → uses redisio cookbook's own template)
  - Deploys `cookbook_file '/etc/pam.d/sudo'` (source: `node['ulimit']['ulimit_overriding_sudo_file_name']` = `'sudo'`, mode=0644)
- Conditional: `if ulimit.key?('users')` — since `node['ulimit']['users']` defaults to an empty `Mash.new`, this block **does not execute** unless users are explicitly configured
  - If users were configured: iterates over each user and applies `user_ulimit` custom resource with per-user file handle limits
- Resources: template (1, Debian only), cookbook_file (1, Debian only), user_ulimit (0 by default)

---

**7. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
- Determines the OS-default Redis service name:
  - Debian/Ubuntu: `redis-server`
  - RHEL/Fedora: `redis`
- Stops and disables the OS-default Redis service to prevent conflicts with the source-installed version
- Resources: service (1) — actions: `[:stop, :disable]`

---

**8. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
- Calls `include_recipe 'redisio::default'` and `include_recipe 'redisio::ulimit'` (both already visited, idempotent)
- Reads `node['redisio']['servers']` — set in `cache::default` to `[{ 'port' => '6379', 'requirepass' => 'redis_secure_password_123', 'replicaservestaledata' => nil }]`
- Uses custom resource `redisio_configure['redis-servers']`:
  - Provider: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`
  - Iterates over the servers array — **1 iteration for server: port 6379** (server_name = `'6379'`):
    - Creates system user `redis` (comment='Redis service account', manage_home=true, home=/var/lib/redis, shell=/bin/false on Debian, system=true)
    - Creates directory `/etc/redis` (owner=root, group=redis, mode=0775, recursive=true)
    - Creates directory `/var/lib/redis` (owner=redis, group=redis, mode=0775, recursive=true)
    - Creates directory `/var/run/redis/6379` (owner=redis, group=redis, mode=0755, recursive=true)
    - Sets up SELinux contexts if SELinux is enabled (selinux_fcontext for configdir, datadir, piddir)
    - Sets `user_ulimit 'redis'` with filehandle_limit = maxclients(10000) + 32 = **10032** (since ulimit=0 in defaults)
    - Renders template `/etc/redis/6379.conf` from `redis.conf.erb`:
      - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb`
      - Key variables: port=6379, requirepass=redis_secure_password_123, replicaservestaledata=nil, backuptype=rdb, maxclients=10000, loglevel=notice, syslogenabled=yes, syslogfacility=local0, databases=16, save=[900 1, 300 10, 60 10000], appendfsync=everysec, clusterenabled=no, version=3.2.11
      - Protected by breadcrumb: skips re-render if `/etc/redis/6379.conf.breadcrumb` exists
    - Creates breadcrumb file `/etc/redis/6379.conf.breadcrumb` (create_if_missing)
    - Since `job_control='systemd'` (default on systemd hosts):
      - Creates file `/etc/tmpfiles.d/redis@6379.conf` (content: `d /var/run/redis/6379 0755 redis redis`)
      - Renders template `/lib/systemd/system/redis@6379.service` from `redis@.service.erb`:
        - Source: `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb`
        - Variables: bin_path=/usr/local/bin, user=redis, group=redis, limit_nofile=10032
        - ExecStart: `/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no`
        - Notifies: `execute 'systemctl daemon-reload'` immediately
      - Executes `systemctl daemon-reload` (triggered by template notification)
- Creates service resource `service['redis@6379']` (provider=Systemd, supports start/stop/restart/status)
- Resources: user (1), directory (3), user_ulimit (1), template (2), file (3), execute (1), service (1)

---

**9. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
- Iterates over `node['redisio']['servers']` — **1 iteration for server: port 6379**:
  - Looks up the already-defined service resource `service['redis@6379']`
  - Appends actions `:start` and `:enable` to the service resource
  - Result: `redis@6379.service` is started and enabled at boot
- Resources: service (1) — actions: `[:start, :enable]`

---

## Dependencies

**External cookbook dependencies**:
- `memcached ~> 6.0` (provides `memcached_instance` custom resource)
- `redisio` (provides `redisio_install`, `redisio_configure`, `user_ulimit` custom resources)
- `build-essential` (transitive dependency of redisio, provides `build_essential` resource)

**System package dependencies**:
- `memcached` (OS package, latest version)
- `tar` (prerequisite for Redis source build, on Debian/RHEL)
- `gcc`, `make`, `build-essential` / `Development Tools` (via build_essential resource, for compiling Redis from source)

**Service dependencies**:
- `memcached.service` (systemd, started and enabled)
- `redis@6379.service` (systemd template unit, started and enabled)
- `redis-server` or `redis` (OS default Redis service — explicitly **stopped and disabled**)

---

## Credentials

**Detection Summary**: 1 credential detected across 2 files (defined in recipe, consumed in template)

**Source**:
- **Provider**: Hardcoded (plaintext in recipe file)
- **URL**: N/A
- **Path**: `cookbooks/cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` → rendered as `requirepass redis_secure_password_123` in `/etc/redis/6379.conf`; also passed as `@requirepass` variable to `redis.init.erb` (init.d mode) for the `redis-cli shutdown` command
- **Source file(s)**:
  - `cookbooks/cache/recipes/default.rb` — hardcoded value `'redis_secure_password_123'` set directly in the servers array
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb` — passes `requirepass` to the `redis.conf.erb` template; also supports optional data bag lookup via `data_bag_item(current['data_bag_name'], current['data_bag_item'])` if `data_bag_name`, `data_bag_item`, and `data_bag_key` attributes are set (not used in this cookbook)
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb` — renders `requirepass <%= @requirepass %>` into `/etc/redis/6379.conf`
  - `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb` — embeds password in the `redis-cli shutdown` command (init.d mode only, not used on systemd)
- **Current storage**: Hardcoded plaintext in recipe attribute assignment
- **Usage context**: Redis `requirepass` directive — all clients (including application services) must authenticate with `AUTH redis_secure_password_123` before issuing commands. Also used as `masterauth` if replication is configured.

> ⚠️ **Security Note for Solutions Architect**: This password is stored in plaintext in the cookbook source. During Ansible migration, this credential **must** be moved to AAP Credentials, HashiCorp Vault, or an encrypted Ansible Vault variable. Do **not** replicate the hardcoded value in Ansible playbooks or variable files.

---

## Checks for the Migration

**Files to verify**:
- `/etc/redis/6379.conf` — Redis instance configuration
- `/etc/redis/6379.conf.breadcrumb` — breadcrumb sentinel file (prevents config overwrite)
- `/lib/systemd/system/redis@6379.service` — systemd unit template
- `/etc/tmpfiles.d/redis@6379.conf` — tmpfiles.d entry for PID directory
- `/var/lib/redis/` — Redis data directory (RDB dump files)
- `/var/run/redis/6379/` — Redis PID directory
- `/var/log/redis/` — Redis log directory (created by cache::default)
- `/var/log/memcached/` — Memcached log directory
- `/var/run/memcached/` — Memcached PID/socket directory
- `/usr/local/bin/redis-server` — Redis server binary (source install)
- `/usr/local/bin/redis-cli` — Redis CLI binary (source install)
- `/etc/pam.d/su` — PAM su config (Debian only, from ulimit recipe)
- `/etc/pam.d/sudo` — PAM sudo config (Debian only, from ulimit recipe)

**Service endpoints to check**:
- **11211** (TCP) — Memcached
- **11211** (UDP) — Memcached
- **6379** (TCP) — Redis
- Unix sockets: None configured by default
- Network interfaces: Both services bind to `0.0.0.0` (all interfaces) by default

**Templates rendered**:
- `redis.conf.erb` → `/etc/redis/6379.conf` — renders **1 time** (for the single server on port 6379); skipped on subsequent Chef runs if breadcrumb file exists
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service` — renders **1 time** (systemd job_control mode)
- `/etc/pam.d/su` template — renders **1 time** on Debian/Ubuntu only
- `cookbook_file sudo` → `/etc/pam.d/sudo` — deployed **1 time** on Debian/Ubuntu only

---

## Pre-flight Checks

```bash
# ============================================================
# MEMCACHED CHECKS
# ============================================================

# Service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Verify memcached is listening on port 11211 (TCP and UDP)
ss -tlnp | grep 11211
ss -ulnp | grep 11211
netstat -tulpn | grep 11211

# Memcached connectivity test
echo "stats" | nc -q 1 localhost 11211
echo "version" | nc -q 1 localhost 11211
# Expected output: VERSION x.x.x

# Verify memcached configuration
ps aux | grep memcached | grep -v grep
# Verify flags: -m 64 (memory), -p 11211 (port), -U 11211 (UDP), -c 1024 (maxconn), -l 0.0.0.0 (listen)

# Verify memcached user and directories
id memcached
ls -lah /var/log/memcached/
ls -lah /var/run/memcached/

# Memcached logs
journalctl -u memcached -n 50 --no-pager
tail -f /var/log/memcached/memcached.log 2>/dev/null || echo "Logging to syslog/journald"

# ============================================================
# REDIS CHECKS
# ============================================================

# Service status
systemctl status redis@6379
ps aux | grep redis-server | grep -v grep

# Verify Redis binary (source install)
ls -lh /usr/local/bin/redis-server
ls -lh /usr/local/bin/redis-cli
/usr/local/bin/redis-server --version
# Expected: Redis server v=3.2.11 sha=...

# Verify Redis is listening on port 6379
ss -tlnp | grep 6379
netstat -tulpn | grep 6379
lsof -i :6379

# Redis connectivity test (with authentication)
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' PING
# Expected: PONG

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' INFO server | grep -E 'redis_version|tcp_port|config_file'
# Expected: redis_version:3.2.11, tcp_port:6379

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' INFO clients | grep connected_clients
# Expected: connected_clients:1 (or more)

/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' CONFIG GET requirepass
# Expected: requirepass, redis_secure_password_123

# Verify config file exists and breadcrumb is present
ls -lah /etc/redis/6379.conf
ls -lah /etc/redis/6379.conf.breadcrumb
cat /etc/redis/6379.conf | grep -E '^port|^requirepass|^loglevel|^maxclients|^syslog-enabled|^databases'
# Expected: port 6379, requirepass redis_secure_password_123, loglevel notice, maxclients 10000, syslog-enabled yes, databases 16

# Verify the ruby_block hack removed deprecated directives
grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority' /etc/redis/6379.conf
# Expected: NO output (all lines should have been stripped)

# Verify systemd unit file
cat /lib/systemd/system/redis@6379.service
# Expected: ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no
# Expected: User=redis, Group=redis, LimitNOFILE=10032

# Verify tmpfiles.d entry
cat /etc/tmpfiles.d/redis@6379.conf
# Expected: d /var/run/redis/6379 0755 redis redis

# Verify Redis data and PID directories
ls -lah /var/lib/redis/
ls -lah /var/run/redis/6379/
ls -lah /var/log/redis/

# Verify Redis user
id redis
# Expected: uid=... gid=... groups=redis

# Verify ulimit for redis user
cat /etc/security/limits.d/redis.conf 2>/dev/null || echo "Check ulimit via systemd LimitNOFILE"
systemctl show redis@6379 | grep LimitNOFILE
# Expected: LimitNOFILE=10032

# Verify OS default Redis service is stopped and disabled
systemctl is-active redis-server 2>/dev/null && echo "WARNING: redis-server still active" || echo "OK: redis-server not active"
systemctl is-enabled redis-server 2>/dev/null && echo "WARNING: redis-server still enabled" || echo "OK: redis-server not enabled"
# On RHEL/Fedora, check 'redis' instead of 'redis-server':
systemctl is-active redis 2>/dev/null && echo "WARNING: redis still active" || echo "OK: redis not active"
systemctl is-enabled redis 2>/dev/null && echo "WARNING: redis still enabled" || echo "OK: redis not enabled"

# Redis RDB persistence check
ls -lah /var/lib/redis/dump-6379.rdb 2>/dev/null || echo "No RDB file yet (normal on fresh install)"
/usr/local/bin/redis-cli -p 6379 -a 'redis_secure_password_123' BGSAVE
# Expected: Background saving started

# Redis logs
journalctl -u redis@6379 -n 50 --no-pager
# Check syslog (Redis logs to syslog facility local0 by default)
grep 'redis-6379' /var/log/syslog 2>/dev/null | tail -20
grep 'redis-6379' /var/log/messages 2>/dev/null | tail -20

# ============================================================
# PAM ULIMIT FILES (Debian/Ubuntu only)
# ============================================================
ls -lah /etc/pam.d/su
ls -lah /etc/pam.d/sudo
grep -i 'pam_limits' /etc/pam.d/su
grep -i 'pam_limits' /etc/pam.d/sudo

# ============================================================
# OVERALL SYSTEM CHECK
# ============================================================
# Both services should be running
systemctl is-active memcached && echo "memcached: OK" || echo "memcached: FAILED"
systemctl is-active redis@6379 && echo "redis@6379: OK" || echo "redis@6379: FAILED"
systemctl is-enabled memcached && echo "memcached enabled: OK" || echo "memcached enabled: FAILED"
systemctl is-enabled redis@6379 && echo "redis@6379 enabled: OK" || echo "redis@6379 enabled: FAILED"
```