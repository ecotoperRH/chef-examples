---
source-path: cookbooks/cache
---

# Migration Plan: `cache` Cookbook

**TLDR**: The `cache` cookbook configures two caching services: Memcached (via the `memcached` community cookbook using a `memcached_instance` custom resource backed by a systemd unit) and Redis (via the `redisio` community cookbook using an old-style LWRP). A post-converge `ruby_block` hack strips unsupported directives from `/etc/redis/6379.conf` at every Chef run. The Ansible migration replaces both community cookbooks with direct package installs, explicit systemd unit templates, and a clean Redis config template that eliminates the `ruby_block` hack entirely. The hardcoded Redis password is moved to Ansible Vault.

---

## Service Type and Instances

**Service Type**: Cache (Memcached + Redis)

**Configured Instances**:

- **memcached** (default instance): In-memory key-value cache
  - Location/Path: `/etc/systemd/system/memcached.service`
  - Port/Socket: TCP `11211`, UDP `11211`
  - Key Config: 64 MB memory, 1024 max connections, 1024 ulimit, listens on `0.0.0.0`
  - Removed default configs: `/etc/memcached.conf`, `/etc/sysconfig/memcached`, `/etc/default/memcached`

- **redis@6379** (instance name derived from port): Persistent key-value store
  - Location/Path: `/etc/redis/6379.conf`
  - Port/Socket: TCP `6379`, bound to `127.0.0.1`
  - Key Config: password-protected (`redis_secure_password_123` hardcoded in recipe), 16 databases, save rules `900 1` / `300 10` / `60 10000`, no AOF, `noeviction` maxmemory policy
  - Data dir: `/var/lib/redis`, Log dir: `/var/log/redis`, PID dir: `/var/run/redis/6379`

---

## File Structure

```
cookbooks/cache/
├── recipes/
│   └── default.rb
├── attributes/
│   └── default.rb
└── metadata.rb

cookbooks/memcached/
├── recipes/
│   └── default.rb
├── resources/
│   └── instance.rb
├── libraries/
│   └── helpers.rb
└── templates/
    └── memcached.service.erb

cookbooks/redisio/
├── recipes/
│   ├── default.rb
│   ├── install.rb
│   ├── configure.rb
│   └── enable.rb
├── providers/
│   ├── configure.rb
│   └── install.rb
├── resources/
│   ├── configure.rb
│   └── install.rb
├── attributes/
│   └── default.rb
└── templates/
    └── redis.conf.erb
```

---

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Sets `node['redisio']['servers']` attribute array with one entry: port `6379`, requirepass `redis_secure_password_123`, `replicaservestaledata: nil`
   - Sets `node['redisio']['job_control']` to `'systemd'`
   - Calls `include_recipe 'memcached'` → triggers `cookbooks/memcached/recipes/default.rb`
   - Calls `include_recipe 'redisio'` → triggers `cookbooks/redisio/recipes/default.rb` (which includes `redisio::install` and `redisio::configure`)
   - Calls `include_recipe 'redisio::enable'` → triggers `cookbooks/redisio/recipes/enable.rb`
   - Declares `directory '/var/log/redis'` with owner `redis`, group `redis`, mode `0755`
   - Declares `ruby_block 'fix_redis_config'` that post-processes `/etc/redis/6379.conf` at converge time, stripping lines matching: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`

2. **memcached::default** (`cookbooks/memcached/recipes/default.rb`):
   - Invokes the `memcached_instance` custom resource (defined in `cookbooks/memcached/resources/instance.rb`)
   - Iterations — one instance configured:
     - **memcached** (default instance): installs `memcached` package, disables the OS default `memcached` service, removes `/etc/memcached.conf` / `/etc/sysconfig/memcached` / `/etc/default/memcached`, renders `memcached.service` systemd unit via `systemd_unit` resource using `Memcached::Helpers` for binary path detection and platform-conditional security flags (RHEL excludes `RestrictNamespaces`, `RestrictRealtime`, `ProtectControlGroups`, `ProtectKernelTunables`, `ProtectKernelModules`, `MemoryDenyWriteExecute`), starts and enables the service

3. **redisio::default** (`cookbooks/redisio/recipes/default.rb`):
   - Includes `redisio::install` and `redisio::configure` in sequence

4. **redisio::install** (`cookbooks/redisio/recipes/install.rb`):
   - Invokes the `redisio_install` LWRP provider (`cookbooks/redisio/providers/install.rb`)
   - Installs Redis from source tarball (download → `make` → `make install`) unless `node['redisio']['package_install']` is true
   - Creates `redis` system user and group
   - Creates config directory `/etc/redis`, data directory `/var/lib/redis`, pid directory `/var/run/redis/6379`, log directory `/var/log/redis`

5. **redisio::configure** (`cookbooks/redisio/recipes/configure.rb`):
   - Invokes the `redisio_configure` LWRP provider (`cookbooks/redisio/providers/configure.rb`)
   - Iterations — one server entry in `node['redisio']['servers']`:
     - **6379**: renders `/etc/redis/6379.conf` from `cookbooks/redisio/templates/redis.conf.erb` with all configured attributes; renders `redis@6379.service` systemd unit file

6. **redisio::enable** (`cookbooks/redisio/recipes/enable.rb`):
   - Iterations — one server entry:
     - **redis@6379**: enables and starts `redis@6379.service` via `service` resource

---

## Dependencies

**External cookbook dependencies**:
- `memcached` community cookbook (provides `memcached_instance` custom resource, `Memcached::Helpers` library)
- `redisio` community cookbook (provides `redisio_install` and `redisio_configure` old-style LWRPs)

**System package dependencies**:
- `memcached` (OS package)
- `redis` (OS package — migration switches from source build to package install)

**Service dependencies**:
- `memcached.service` (custom systemd unit, replaces OS default)
- `redis@6379.service` (systemd template unit)

---

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded plaintext in recipe attribute assignment
- **Path**: `cookbooks/cache/recipes/default.rb`

### Redis Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']` (Chef); `vault_redis_password` (Ansible target)
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Plaintext string `redis_secure_password_123` hardcoded directly in the recipe
- **Usage context**: Passed to `redisio_configure` LWRP, rendered into `/etc/redis/6379.conf` as the `requirepass` directive; required by all Redis clients connecting to port 6379

---

## Checks for the Migration

**Files to verify**:
- `/etc/systemd/system/memcached.service`
- `/etc/redis/6379.conf`
- `/etc/tmpfiles.d/redis@6379.conf`
- `/var/lib/redis/` (directory, owned `redis:redis`)
- `/var/log/redis/` (directory, owned `redis:redis`)
- `/var/run/redis/6379/` (directory, owned `redis:redis`)
- `/etc/redis/` (directory, owned `root:redis`, mode `0775`)
- Absence of `/etc/memcached.conf`
- Absence of `/etc/sysconfig/memcached`
- Absence of `/etc/default/memcached`

**Service endpoints to check**:
- Memcached: TCP `11211`, UDP `11211`
- Redis: TCP `6379` (bound to `127.0.0.1`)

**Templates rendered**:
- `memcached.service.j2` → `/etc/systemd/system/memcached.service` (1 render, memcached instance)
- `redis.conf.j2` → `/etc/redis/6379.conf` (1 render, redis@6379 instance)

---

## Pre-flight Checks

```bash
# ── Memcached instance: memcached ──────────────────────────────────────────

# Verify memcached package is installed
rpm -q memcached || dpkg -l memcached

# Verify OS default memcached service is disabled
systemctl is-enabled memcached && echo "WARNING: default memcached still enabled" || echo "OK: default memcached disabled"

# Verify default config files are absent
for f in /etc/memcached.conf /etc/sysconfig/memcached /etc/default/memcached; do
  [ -f "$f" ] && echo "WARNING: $f still exists" || echo "OK: $f absent"
done

# Verify custom systemd unit is deployed
test -f /etc/systemd/system/memcached.service && echo "OK: unit file present" || echo "MISSING: memcached.service"

# Verify memcached service is running and enabled
systemctl is-active memcached
systemctl is-enabled memcached

# Verify memcached is listening on TCP 11211
ss -tlnp | grep ':11211' || echo "WARNING: memcached not listening on 11211"

# Verify memcached is listening on UDP 11211
ss -ulnp | grep ':11211' || echo "WARNING: memcached not listening on UDP 11211"

# Smoke test memcached connectivity
echo "stats" | nc -q1 127.0.0.1 11211 | head -5


# ── Redis instance: redis@6379 ─────────────────────────────────────────────

# Verify redis package is installed
rpm -q redis || dpkg -l redis

# Verify redis user and group exist
id redis || echo "MISSING: redis user"
getent group redis || echo "MISSING: redis group"

# Verify directory ownership and permissions
stat -c "%U %G %a" /etc/redis        # expect: root redis 775
stat -c "%U %G %a" /var/lib/redis    # expect: redis redis 775
stat -c "%U %G %a" /var/log/redis    # expect: redis redis 755
stat -c "%U %G %a" /var/run/redis/6379 2>/dev/null || echo "NOTE: pid dir may be tmpfs-managed"

# Verify Redis config file is deployed and has correct permissions
test -f /etc/redis/6379.conf && echo "OK: config present" || echo "MISSING: /etc/redis/6379.conf"
stat -c "%U %G %a" /etc/redis/6379.conf  # expect: redis redis 640

# Verify config does NOT contain stripped directives (ruby_block equivalence check)
for directive in replica-serve-stale-data replica-read-only repl-ping-replica-period client-output-buffer-limit replica-priority; do
  grep -q "^${directive}" /etc/redis/6379.conf && echo "WARNING: $directive present in config" || echo "OK: $directive absent"
done

# Verify tmpfiles config is deployed
test -f /etc/tmpfiles.d/redis@6379.conf && echo "OK: tmpfiles config present" || echo "MISSING: tmpfiles config"

# Verify redis@6379 service is running and enabled
systemctl is-active redis@6379
systemctl is-enabled redis@6379

# Verify Redis is listening on 127.0.0.1:6379
ss -tlnp | grep ':6379' || echo "WARNING: redis not listening on 6379"

# Smoke test Redis connectivity (requires password)
redis-cli -h 127.0.0.1 -p 6379 -a "${REDIS_PASSWORD}" ping | grep -q PONG && echo "OK: redis PONG" || echo "FAIL: redis not responding"

# Verify requirepass is set in config (value should not be plaintext in output)
grep -q "^requirepass" /etc/redis/6379.conf && echo "OK: requirepass directive present" || echo "WARNING: requirepass not set"

# Verify Ansible Vault variable is defined (pre-deploy check)
ansible -m debug -a "var=vault_redis_password" localhost 2>&1 | grep -v "VARIABLE IS NOT DEFINED" && echo "OK: vault_redis_password defined" || echo "MISSING: vault_redis_password not in vault"
```