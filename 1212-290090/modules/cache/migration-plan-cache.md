---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook manages one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached is configured for TCP and UDP port `11211`. Redis is configured on TCP port `6379`, with source installation of Redis `3.2.11` and systemd service `redis@6379` on the expected Debian-like systemd path. The Redis password is hardcoded in `cookbooks/cache/recipes/default.rb` and must be moved to Ansible Vault or another approved secret store. Several dependency defaults and provider-specific implementation details require verification against the underlying cookbook artifacts before migration.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: In-memory key/value cache
  - Location/Path: Dependency-managed Memcached configuration path; verify on the target platform
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: 64 MB memory, maximum 1024 connections, maximum object size `1m`, user `service_user`, ulimit `1024`, empty experimental and additional option lists. The thread value is inherited from `memcached['threads']` and requires verification from the dependency defaults.
  - Actions: Start and enable the service

- **6379**: Redis cache/database instance
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID directory `/var/run/redis/6379`; logs `/var/log/redis`
  - Port/Socket: TCP `6379`; no Unix socket or TLS port configured
  - Key Config: Authentication enabled with `requirepass`; Redis user and group `redis`; shell `/bin/false`; 16 databases, maximum 10000 clients, default RDB persistence, and `shutdown_save` disabled according to the current plan values. These Redis defaults require verification against the dependency attribute files.
  - Installation: Source installation using Redis `3.2.11` from `http://download.redis.io/releases/redis-3.2.11.tar.gz` when `package_install` is false
  - Service: systemd `redis@6379`; non-systemd alternatives use `redis6379`
  - Replication: No master or replica endpoint; `replicaservestaledata` is explicitly `nil`

## File Structure

The following files are relevant to the executed migration flow. Paths are relative to the repository root and retain the required `migration-dependencies/` prefix.

### Recipes

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

### Providers

```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
```

### Templates

```text
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
```

### Attributes

The executed recipes consume defaults from the dependency cookbooks. The supplied execution tree does not execute an attributes recipe directly, so no additional attribute recipe is included in the execution-file list.

### Files

No `cookbook_file` or `remote_file` static file is deployed by the executed wrapper flow. Redis source installation downloads a remote tarball through the `redisio_install` custom resource.

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to exactly one Redis item named `6379` by port.
   - The configured Redis item contains port `6379`, password value `redis_secure_password_123`, and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` with owner `redis`, group `redis`, mode `0755`, and recursive creation.
   - Includes `redisio::default`.
   - Runs the `fix_redis_config` Ruby block.
   - Includes `redisio::enable`.
   - The supplied structured analysis does not confirm a `group['redis']` resource in this recipe; the migration must ensure the group exists through the Redis configuration implementation or an explicit Ansible task.
   - The `fix_redis_config` block checks `/etc/redis/6379.conf` and removes matching lines for `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` when present.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance['memcached']`.
   - Starts and enables the Memcached service.
   - Configures memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, user `service_user`, and ulimit `1024`.
   - Uses empty experimental and extra CLI option lists.
   - Uses `memcached['threads']`; its effective value requires verification from the dependency defaults.
   - The provider path is not present in the supplied execution tree and must not be invented.
   - Iterations: one item, **`memcached`**.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update`.
   - Evaluates the prerequisite-installation branch controlled by `node['redisio']['package_install']`.
   - Includes `redisio::_install_prereqs`.
   - Declares `build_essential['install build deps']`.
   - Includes `redisio::install`.
   - Includes `redisio::disable_os_default`.
   - Includes `redisio::configure`.
   - The current plan assumes `package_install` is false and `bypass_setup` is false; both values require verification from the dependency attributes.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Debian-family systems, installs package `tar`.
   - Declares `package['tar']` with action `install`.
   - The recipe is referenced more than once but is visited once in the Chef execution flow.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Evaluates the package-install branch.
   - On the assumed source-install path, includes `redisio::_install_prereqs`.
   - Declares `build_essential['install build deps']`.
   - Builds the Redis source URL.
   - Creates `redisio_install['redis-installation']`.
   - Includes `redisio::ulimit`.
   - Uses provider `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Expected source URL: `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Source extraction, build commands, installation prefix, and cleanup behavior must be verified against the provider before being treated as confirmed migration behavior.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Renders the attribute-controlled PAM template to `/etc/pam.d/su`.
   - Installs the attribute-controlled cookbook file at `/etc/pam.d/sudo` with mode `0644`.
   - Evaluates the `ulimit['users']` collection; the supplied plan states that it is empty by default, but this requires attribute verification.
   - Any `user_ulimit['redis']` resource and its calculated limit require verification in the Redis configure provider.
   - The PAM source files and exact ulimit values are attribute-controlled.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - On Debian-family systems, manages `service['redis-server']`.
   - Stops and disables the distribution-provided `redis-server` service.
   - Prevents the operating-system Redis service from competing with the cookbook-managed instance.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes `redisio::default`; this circular dependency is already visited and must not be repeated in Ansible.
   - Includes `redisio::ulimit`; this circular dependency is already visited and must not be repeated in Ansible.
   - Creates exactly one Redis configuration item: **`6379`**.
   - Uses provider `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Manages Redis user and group `redis`, data directory `/var/lib/redis`, configuration directory `/etc/redis`, PID directory `/var/run/redis/6379`, and configuration file `/etc/redis/6379.conf`.
   - Renders the Redis configuration template once for instance **`6379`**.
   - On the expected systemd path, manages service `redis@6379`.
   - The plan’s claims about breadcrumb files, tmpfiles configuration, daemon reloads, calculated ulimit values, and exact provider resource operations require verification against the provider source before implementation.
   - Conditional non-systemd service templates are selected as follows:
     - `initd`: `/etc/init.d/redis6379` from `redis.init.erb`
     - `upstart`: `/etc/init/redis6379.conf` from `redis.upstart.conf.erb`
     - `rcinit`: `/usr/local/etc/rc.d/redis6379` from `redis.rcinit.erb`
   - Iterations: one item, **`6379`**.

9. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iterates over exactly one Redis item: **`6379`**.
   - Resolves `service['redis@6379']` on systemd.
   - Adds `start` and `enable` actions.
   - Intended systemd result: `systemctl enable --now redis@6379`.

## Dependencies

**External cookbook dependencies**: `memcached`, `redisio`

**System package dependencies**:
- `tar`
- Build toolchain provided through the `build_essential` dependency resource; the exact platform package list must be resolved by the target Ansible role.
- Memcached package installation is encapsulated by `memcached_instance['memcached']`; the supplied execution tree does not identify the exact package name and no package name should be invented.
- `redis-server` is the distribution service name that is stopped and disabled on Debian-family systems. The current plan assumes source installation and does not install the Redis package; this requires verification of `package_install`.

**Service dependencies**:
- Memcached service
- Distribution `redis-server` service, stopped and disabled
- Redis instance service `redis@6379`, started and enabled under systemd

## Credentials

**Detection Summary**: 1 active credential detected in 1 file.

**Source**:
  - **Provider**: Wrapper recipe `cookbooks/cache/recipes/default.rb`
  - **URL**: None
  - **Path**: `cookbooks/cache/recipes/default.rb`
  - **Recommended storage**: Ansible Vault, AAP credentials, or an approved external secret manager

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`; migrate as `redis_requirepass`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded Chef attribute value `redis_secure_password_123`
- **Usage context**: Rendered into `/etc/redis/6379.conf` as the Redis `requirepass` directive and may also be used by an init.d service template if that platform branch is selected.
- **Migration requirement**: Replace the plaintext value with a vaulted Ansible variable. Do not commit the password to plaintext inventory, group variables, templates, or operational scripts.

The Redis provider contains an inactive data-bag capability using `data_bag_name`, `data_bag_item`, and `data_bag_key`. The supplied configuration leaves these attributes unset, and no active data-bag lookup is part of the analyzed execution flow. No additional active credentials, certificates, private keys, database connection strings, or external secret references were detected.

## Checks for the Migration

**Files to verify**:
- `cookbooks/cache/recipes/default.rb`
- `migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`
- `/etc/redis`
- `/etc/redis/6379.conf`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- `/etc/tmpfiles.d/redis@6379.conf`, if confirmed by provider analysis
- `/lib/systemd/system/redis@6379.service`, if systemd is selected
- `/etc/init.d/redis6379`, if init.d is selected
- `/etc/init/redis6379.conf`, if upstart is selected
- `/usr/local/etc/rc.d/redis6379`, if rcinit is selected
- `/etc/pam.d/su`
- `/etc/pam.d/sudo`
- Redis source archive `redis-3.2.11.tar.gz`, if source installation is selected

**Service endpoints to check**:
- Memcached TCP: `0.0.0.0:11211`
- Memcached UDP: `0.0.0.0:11211`
- Redis instance `6379` TCP: `0.0.0.0:6379` or the configured bind address
- Redis instance `6379` Unix socket: none configured
- Redis instance `6379` TLS port: none configured

**Templates rendered**:
- Redis configuration template → `/etc/redis/6379.conf`
  - Render count: 1
- `redis@.service.erb` → `/lib/systemd/system/redis@6379.service`
  - Render count: 1 on systemd
- `redis.init.erb` → `/etc/init.d/redis6379`
  - Render count: 1 on init.d
- `redis.upstart.conf.erb` → `/etc/init/redis6379.conf`
  - Render count: 1 on upstart
- `redis.rcinit.erb` → `/usr/local/etc/rc.d/redis6379`
  - Render count: 1 on rcinit
- PAM template → `/etc/pam.d/su`
  - Render count: 1 when the Debian ulimit branch executes
- PAM cookbook file → `/etc/pam.d/sudo`
  - Installation count: 1 when the Debian ulimit branch executes

## Pre-flight checks

```bash
# Confirm the operating system and service manager
cat /etc/os-release
ps -p 1 -o comm=
```

### Memcached instance `memcached`

```bash
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached
```

Expected result: the `memcached` service is enabled and active.

```bash
printf "version\r\n" | nc -w 2 127.0.0.1 11211
ss -ltnp | grep ':11211'
```

Expected result: Memcached responds with a line beginning with `VERSION` and listens on TCP port `11211`.

```bash
ss -lunp | grep ':11211'
```

Expected result: Memcached listens on UDP port `11211` if UDP support is enabled by the target package and service configuration.

### Redis instance `6379`

Use the vaulted value of `redis_requirepass` in place of the placeholder below.

```bash
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379
```

Expected result: `redis@6379` is enabled and active on systemd systems.

```bash
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" PING
```

Expected result:

```text
PONG
```

```bash
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" INFO server | grep -E 'redis_version|tcp_port'
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_REQUIREPASS" CONFIG GET databases
ss -ltnp | grep ':6379'
```

Verify that Redis reports TCP port `6379`, the expected installed version, and the configured database count.

```bash
grep -E '^(port|requirepass|dir|dbfilename|maxclients|loglevel|syslog-enabled)' /etc/redis/6379.conf
```

Verify the following values where confirmed by the dependency attributes:
- `port` is `6379`
- `requirepass` is populated from the vaulted secret
- `maxclients` is `10000`
- `loglevel` is `notice`
- `syslog-enabled` is `yes`

```bash
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
```

Expected result: no matching active configuration lines after the cleanup block runs.

```bash
stat -c '%U:%G %a %n' \
  /etc/redis \
  /etc/redis/6379.conf \
  /var/lib/redis \
  /var/run/redis/6379 \
  /var/log/redis
```

Verify expected ownership and permissions:
- `/etc/redis/6379.conf`: `redis:redis`, mode `644`
- `/var/lib/redis`: `redis:redis`, mode `775`
- `/var/run/redis/6379`: `redis:redis`, mode `755`
- `/var/log/redis`: `redis:redis`, mode `755`

On systemd systems:

```bash
systemctl cat redis@6379
systemctl show redis@6379 | grep -E 'User=|Group=|LimitNOFILE='
```

Verify that the unit invokes the configured Redis binary with `/etc/redis/6379.conf` and that the service runs as user and group `redis`. Verify `LimitNOFILE` only if the provider analysis confirms the calculated limit.

```bash
journalctl -u redis@6379 --no-pager -n 100
```

Check for successful startup and absence of authentication, permission, or configuration errors.

### Redis source installation

Run these checks only when source installation is confirmed:

```bash
/usr/local/bin/redis-server --version
/usr/local/bin/redis-cli --version
test -x /usr/local/bin/redis-server
test -x /usr/local/bin/redis-cli
```

Confirm that the binaries exist and report the expected source-installed Redis version.

### Configuration and dependency validation

```bash
grep -R "package_install\|bypass_setup\|maxclients\|databases\|shutdown_save" \
  migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db
```

Verify the dependency attribute values before making the following settings authoritative:
- `package_install`
- `bypass_setup`
- Redis version
- `maxclients`
- database count
- `shutdown_save`
- Memcached memory, ports, threads, and service defaults
