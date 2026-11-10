---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two cache services: a Memcached instance named **memcached** and a Redis instance named **6379**. Memcached is configured through the `memcached_instance` custom resource and is started and enabled. Redis is source-installed by default as Redis **3.2.11**, configured on TCP port **6379** with authentication, managed by the `redis@6379` systemd unit on systemd hosts, and started and enabled after selected replication-related directives are removed from `/etc/redis/6379.conf`. Attribute values documented below require confirmation against the source cookbook attribute definitions or a Chef-managed host because attribute files were not included in the supplied execution tree.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:
- **memcached**: Memcached cache daemon.
  - Location/Path: Operating-system package configuration and unit-file paths are platform dependent; the custom-resource provider was not included in the supplied execution tree.
  - Port/Socket: TCP `11211` and UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory allocation `64 MB`; maximum connections `1024`; maximum object size `1m`; file-descriptor ulimit `1024`; log path attribute `/var/log/memcached`; started and enabled. No Memcached package version is pinned.

- **6379**: Redis persistent key-value cache instance.
  - Location/Path: Configuration `/etc/redis/6379.conf`; data directory `/var/lib/redis`; PID directory `/var/run/redis/6379`; log directory `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket configured
  - Key Config: Redis `3.2.11` is source-installed by default; service user/group `redis:redis`; RDB persistence (`backuptype: rdb`); `16` databases; `maxclients 10000`; `tcp-backlog 511`; syslog enabled with facility `local0`; authenticated with `requirepass`; started and enabled through `redis@6379` on systemd hosts. The service unit uses `LimitNOFILE=10032`.

The wrapper explicitly sets `node['redisio']['servers']` to one Redis server, **6379**. The configured server name is derived from `name || port`, and the configured value is `6379`.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

Only Ruby files present in the supplied execution tree are listed below.

**Recipes:**
```text
cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
```

**Templates:**
```text
```

**Attributes:**
```text
```

No static file is identified in the execution tree as a deployable cookbook file. The Redis provider references dynamically selected Redis configuration and init-system templates, but the execution-tree constraint does not identify a concrete rendered template file path for the Redis server configuration.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to one Redis instance: **6379**.
   - Configures **6379** with port `6379`, a `requirepass` value, and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]` after Redis configuration:
     - Reads `/etc/redis/6379.conf` if present.
     - Removes lines beginning with `replica-serve-stale-data`.
     - Removes lines beginning with `replica-read-only`.
     - Removes lines beginning with `repl-ping-replica-period`.
     - Removes lines beginning with `client-output-buffer-limit`.
     - Removes lines beginning with `replica-priority`.
     - Writes the modified content back to `/etc/redis/6379.conf`.
   - Includes `redisio::enable`.
   - Resources: one directory, one Ruby block, and three recipe includes.
   - Ansible migration sequence:
     1. Create `/var/log/redis` as `redis:redis`, mode `0755`.
     2. Install and configure Redis **6379**.
     3. Remove each of the five specified directives from `/etc/redis/6379.conf` with individual `ansible.builtin.lineinfile` tasks using `state: absent`.
     4. Restart Redis **6379** only when the managed configuration or one of the five line-removal tasks changes.
     5. Enable and start `redis@6379` on systemd hosts.

2. **memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses `memcached_instance[memcached]`.
   - Configures the **memcached** instance with memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, ulimit `1024`, and empty experimental and additional CLI-option lists.
   - Starts and enables Memcached.
   - The `memcached_instance` provider source is not included in the supplied execution tree. Confirm the destination package name, configuration-file location, unit-file name, and supported command-line arguments on the target platform before implementation.

3. **redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - With the documented default `package_install: false`, includes `redisio::_install_prereqs`.
   - Uses `build_essential[install build deps]`.
   - Includes the following recipes in order when `bypass_setup` is `false`:
     1. `redisio::install`
     2. `redisio::disable_os_default`
     3. `redisio::configure`
   - The `build_essential` custom-resource provider is external to the supplied execution tree; confirm platform-specific compiler and build-tool package names before migration.

4. **redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs package **tar** on Debian, RHEL, and Fedora source-install paths.
   - Iterations: runs one time for package **tar**.

5. **redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Follows the source-install branch when `package_install` is `false`.
   - Includes `redisio::_install_prereqs`, which is already visited in this execution path.
   - Uses `build_essential[install build deps]`.
   - Uses `redisio_install[redis-installation]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`, unpacks the archive, runs `make clean && make`, and runs `make install`.
   - Uses safe-install behavior: an existing Redis installation is not overwritten merely because its version differs.
   - Includes `redisio::ulimit`.
   - If `package_install` is changed to `true`, the package-install branch uses `redis-server` on Debian, `redis` on RHEL/Fedora, and `redis` on FreeBSD. Package versions are unpinned in that branch.

6. **redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family hosts, renders a template to `/etc/pam.d/su`.
   - On Debian-family hosts, deploys a cookbook file to `/etc/pam.d/sudo`, using the `sudo` source by default and mode `0644`.
   - The documented default `node['ulimit']['users']` collection is empty; therefore no `user_ulimit` resources are created.
   - Iterations: zero times for `user_ulimit` because there are no named users in the collection.
   - The `user_ulimit` custom-resource provider is external to the supplied execution tree. Obtain the existing rendered PAM files from a Chef-managed host before replacing `/etc/pam.d/su` or `/etc/pam.d/sudo`.

7. **redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables the distribution Redis service before enabling the source-built instance.
   - Service name on Debian: `redis-server`.
   - Service name on RHEL and Fedora: `redis`.

8. **redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default` and `redisio::ulimit`, both already visited by the execution path.
   - Uses `redisio_configure[redis-servers]` from `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Iterations: runs one time for Redis instance **6379**.
   - Creates the `redis` service account where required.
   - Creates `/etc/redis` with owner/group `root:redis` and mode `0775`.
   - Creates `/var/lib/redis` with owner/group `redis:redis` and mode `0775`.
   - Creates `/var/run/redis/6379` with owner/group `redis:redis` and mode `0755`.
   - Manages `/etc/redis/6379.conf` with owner/group `redis:redis` and mode `0644`.
   - Creates `/etc/redis/6379.conf.breadcrumb` if absent; this prevents subsequent Chef converges from overwriting the configuration.
   - Manages `/var/lib/redis/dump-6379.rdb` permissions only when the file exists and RDB persistence is active.
   - On systemd hosts, creates `/etc/tmpfiles.d/redis@6379.conf` and `/lib/systemd/system/redis@6379.service`.
   - The systemd unit template is `redis@.service.erb` and uses:
     - `ExecStart=/usr/local/bin/redis-server /etc/redis/%i.conf --daemonize no`
     - `User=redis`
     - `Group=redis`
     - `LimitNOFILE=10032`
   - Changes to `/lib/systemd/system/redis@6379.service` notify `systemctl daemon-reload`.
   - The Redis configuration template is selected dynamically as `redis.conf.erb`. Prefer an always-managed Ansible template rather than reproducing Chef’s write-once breadcrumb behavior unless that behavior is intentional.

9. **redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterations: runs one time for Redis instance **6379**.
   - Locates `service[redis@6379]` when `job_control` is `systemd`.
   - Appends `start` and `enable` actions to `redis@6379`.
   - Enables and starts Redis instance **6379**.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version constraint `~> 6.0`
- `redisio`, no version constraint declared
- External custom-resource/provider coverage is required for `memcached_instance`, `build_essential`, and `user_ulimit`; their provider source files were not included in the supplied execution tree.

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora source-install paths.
- Platform-specific compiler and build-tool packages required to build Redis from source; exact package names must be confirmed from the target platform and the external `build_essential` provider.
- Optional package-install branch only:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`
  - FreeBSD: `redis`

**Service dependencies**:
- Memcached service for instance **memcached**.
- Redis systemd service `redis@6379` on systemd hosts.
- Distribution Redis service disabled before source-built Redis is enabled:
  - Debian: `redis-server`
  - RHEL/Fedora: `redis`

## Credentials

**Detection Summary**: 1 credential detected across 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None
  - **Path**: None

### Redis Instance 6379 Authentication Password
- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded attribute override
- **Usage context**: Rendered into `/etc/redis/6379.conf` as the Redis `requirepass` directive and required by clients before executing protected Redis commands.

Migrate the password to an AAP credential, Ansible Vault variable, or external secret lookup, such as `vault_cache_redis_6379_password`. Mark secret-bearing template tasks with `no_log: true`, rotate the exposed Chef password during migration, and evaluate whether `/etc/redis/6379.conf` can use a stricter mode than the legacy `0644` while remaining readable by Redis and required administration tooling.

No Chef data bag, Chef Vault, encrypted data bag, HashiCorp Vault, CyberArk, Conjur, AWS Secrets Manager, environment-variable secret lookup, or TLS certificate/key path is actively configured in this execution path.

## Checks for the Migration

**Files to verify**:
- `/var/log/redis`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb` if preserving Chef write-once behavior
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/lib/redis/dump-6379.rdb` after Redis writes an RDB snapshot
- `/etc/tmpfiles.d/redis@6379.conf` on systemd hosts
- `/lib/systemd/system/redis@6379.service` on systemd hosts
- `/etc/pam.d/su` and `/etc/pam.d/sudo` on Debian-family hosts if preserving `redisio::ulimit` behavior
- The destination platform’s Memcached configuration file and unit-file arguments

**Service endpoints to check**:
- **memcached**: TCP `11211` on `0.0.0.0`; UDP `11211` on `0.0.0.0`
- **6379**: TCP `6379`; bind address must be verified from the rendered Redis configuration; no Unix socket configured

**Templates rendered**:
- `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render for instance **6379**, unless Chef’s breadcrumb file blocks replacement.
- `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render for instance **6379** on systemd hosts.
- Debian PAM template to `/etc/pam.d/su`: 1 render on Debian-family hosts; the concrete source template path is not identified in the supplied execution tree.

## Pre-flight checks:
```bash
# Memcached instance: memcached
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached

ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'
lsof -nP -iTCP:11211 -sTCP:LISTEN

printf 'version\r\n' | nc -w 3 127.0.0.1 11211
printf 'stats\r\n' | nc -w 3 127.0.0.1 11211

ps -ef | grep '[m]emcached'
systemctl cat memcached

# Redis instance: 6379
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379

# Confirm the competing distribution service is inactive on Debian hosts.
systemctl is-active redis-server || true
systemctl is-enabled redis-server || true

# Use the RHEL/Fedora service name where applicable.
systemctl is-active redis || true
systemctl is-enabled redis || true

ss -ltnp | grep ':6379'
lsof -nP -iTCP:6379 -sTCP:LISTEN

REDISCLI_AUTH='<retrieve-from-AAP-or-Ansible-Vault>' \
  redis-cli -h 127.0.0.1 -p 6379 PING

REDISCLI_AUTH='<retrieve-from-AAP-or-Ansible-Vault>' \
  redis-cli -h 127.0.0.1 -p 6379 INFO server | grep -E 'redis_version|tcp_port'

# Authentication must be required.
redis-cli -h 127.0.0.1 -p 6379 PING

grep -E '^(port|requirepass|tcp-backlog|databases|maxclients|dir|dbfilename|save|syslog-enabled|syslog-facility)' \
  /etc/redis/6379.conf

grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf || true

stat -c '%U:%G %a %n' /etc/redis/6379.conf
stat -c '%U:%G %a %n' /var/lib/redis
stat -c '%U:%G %a %n' /var/run/redis/6379

REDISCLI_AUTH='<retrieve-from-AAP-or-Ansible-Vault>' \
  redis-cli -h 127.0.0.1 -p 6379 SAVE
stat -c '%U:%G %a %n' /var/lib/redis/dump-6379.rdb

systemctl cat redis@6379
systemctl show redis@6379 -p LimitNOFILE
cat /etc/tmpfiles.d/redis@6379.conf

journalctl -u redis@6379 -n 100 --no-pager

ps -ef | grep '[r]edis-server.*6379'
redis_pid="$(pgrep -f 'redis-server.*6379' | head -n 1)"
test -n "$redis_pid" && cat "/proc/${redis_pid}/limits" | grep 'open files'
```