---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` and is started and enabled through the `memcached_instance` custom resource. Redis `3.2.11` is built from source by default, configured on TCP port `6379` with authentication, and managed as `redis@6379` under systemd. Redis configuration is rendered once, after which selected replication-related directives are removed.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Memcached cache service
  - Location/Path: Memcached configuration path is supplied by the Memcached cookbook implementation
  - Port/Socket: TCP `11211`; UDP `11211`
  - Key Config: Listens on `0.0.0.0`; memory `64` MB; maximum connections `1024`; maximum object size `1m`; ULimit `1024`; experimental and additional options are empty; started and enabled; service user is the resolved `service_user` value; thread count is supplied by the custom-resource attribute

- **6379**: Redis cache service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID `/var/run/redis/6379`; logs `/var/log/redis`
  - Port/Socket: TCP `6379`
  - Key Config: Redis `3.2.11`; user/group `redis`; source archive `http://download.redis.io/releases/redis-3.2.11.tar.gz`; systemd service `redis@6379`; default maximum clients `10000`; databases `16`; log level `notice`; syslog enabled with facility `local0`; authentication enabled with `requirepass`; selected replication directives removed after configuration

## File Structure

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
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
```

No static `cookbook_file` source file is identified in the execution tree. The `ulimit.rb` recipe references a configurable source for `/etc/pam.d/sudo`; its source cookbook and static file are supplied through attributes and are not identified.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes `memcached::default`.
   - Sets `node['redisio']['servers']` to one item for port `6379` with `requirepass` set to `redis_secure_password_123` and `replicaservestaledata` set to `nil`.
   - Creates `/var/log/redis` recursively with owner `redis`, group `redis`, and mode `0755`.
   - Includes `redisio::default` and `redisio::enable`.
   - Runs `ruby_block[fix_redis_config]` against `/etc/redis/6379.conf`.
   - Removes lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
   - Resources: one directory, one Ruby block, and three recipe inclusions.
   - The Ruby block does not explicitly restart Redis; service activation occurs in `redisio::enable`.

2. **default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures memory `64` MB, TCP and UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, maximum object size `1m`, ULimit `1024`, and the resolved `service_user`.
   - Uses the configured thread value.
   - Passes empty experimental-option and extra-option lists.
   - Starts and enables the Memcached service.
   - The custom-resource provider is not included in the execution tree; the Ansible role must reproduce the effective install, configuration, start, and enable behavior.

3. **default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - Evaluates `redisio.package_install`, which defaults to `false`.
   - Includes `_install_prereqs`, runs `build_essential[install build deps]`, and evaluates `redisio.bypass_setup`, which defaults to `false`.
   - Includes `install`, `disable_os_default`, and `configure`.
   - With supplied defaults, Redis follows the source-build path.
   - If `package_install` is `true`, source installation is skipped.
   - If `bypass_setup` is `true`, installation, default-service disabling, and configuration are skipped.

4. **_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - On Debian, RHEL, and Fedora, processes exactly one package item: `tar`.
   - Installs `package[tar]`.
   - The package collection is empty on other platforms.
   - The repeated inclusion from `install.rb` is already visited and must not be implemented twice in Ansible.

5. **install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses the source-install path because `redisio.package_install` is `false`.
   - Runs the build-essential dependency setup.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Creates `redisio_install[redis-installation]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Downloads and extracts the archive into `redis-3.2.11` using `--strip-components=1`.
   - Runs `make clean && make`, followed by `make install`.
   - Uses `/usr/local/bin` as the default installation path.
   - Skips rebuilding when the installed version already satisfies the requested version and safe-install behavior applies.
   - Includes `ulimit`.
   - If `package_install` is overridden to `true`, installs `redis-server` on Debian or `redis` on RHEL/Fedora; the package version is set only when `redisio.version` is non-nil.

6. **ulimit** (`migration-dependencies/cookbooks/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `/etc/pam.d/su` using the configured `pam_su_template_cookbook`.
   - Deploys `/etc/pam.d/sudo` with `cookbook_file`, source name `sudo`, configured source cookbook, and mode `0644`.
   - Creates no `user_ulimit` resources because the default `ulimit['users']` collection is empty.

7. **disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Selects `redis-server` as the distribution service name on Debian.
   - Selects `redis` as the distribution service name on RHEL/Fedora.
   - Stops and disables the selected distribution Redis service.
   - Prevents the operating-system Redis service from conflicting with `redis@6379`.

8. **configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Circular inclusions of `redisio::default` and `redisio::ulimit` are already visited.
   - Processes exactly one Redis server item: port `6379`.
   - Creates `redisio_configure[redis-servers]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Merges Redis defaults with the port `6379` definition; wrapper values take precedence.
   - Creates system user `redis` with home `/var/lib/redis`, system-user status enabled, and shell `/bin/false` on Debian.
   - Creates `/etc/redis` as `root` owned, group `redis`, mode `0775`.
   - Creates `/var/lib/redis` as `redis:redis`, mode `0775`.
   - Creates `/var/run/redis/6379` as `redis:redis`, mode `0755`.
   - Renders `/etc/redis/6379.conf` once from `redis.conf.erb`, owned by `redis:redis`, mode `0644`.
   - Creates `/etc/redis/6379.conf.breadcrumb` when breadcrumb mode is enabled.
   - On systemd, creates `/etc/tmpfiles.d/redis@6379.conf` and `/lib/systemd/system/redis@6379.service`.
   - Runs `systemctl daemon-reload` immediately when the systemd template changes.
   - Creates one `user_ulimit` resource for Redis. With `ulimit: 0` and `maxclients: 10000`, the calculated descriptor limit is `10032`.
   - Creates one service resource:
     - systemd: `service[redis@6379]`
     - initd, upstart, or rcinit: `service[redis6379]`
   - Systemd receives Redis binary path `/usr/local/bin`, user `redis`, group `redis`, and the calculated file-descriptor limit.
   - Conditional log and data-file resources are created only when their configured conditions are satisfied.

9. **enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Processes exactly one Redis instance: `6379`.
   - Starts and enables `redis@6379` under systemd.
   - Starts and enables `redis6379` under initd, upstart, or rcinit.
   - This is the final Redis service activation step.

## Dependencies

**External cookbook dependencies**: `memcached` version `~> 6.0`; `redisio` with no version constraint; SELinux behavior may be referenced by the Redis provider when SELinux is enabled, but no `selinux` recipe appears in the execution tree.

**System package dependencies**: `tar`; build-essential toolchain through `build_essential`; `redis-server` when package installation is explicitly enabled on Debian; `redis` when package installation is explicitly enabled on RHEL/Fedora.

**Service dependencies**: Distribution Redis service is stopped and disabled (`redis-server` on Debian or `redis` on RHEL/Fedora). The managed Redis service is started and enabled as `redis@6379` under systemd or `redis6379` under initd/upstart/rcinit.

**Source-built application dependency**: Redis `3.2.11`, downloaded from `http://download.redis.io/releases/redis-3.2.11.tar.gz`.

## Credentials

**Detection Summary**: 1 credential detected in 1 file.

**Source**:
  - **Provider**: Hardcoded
  - **URL**: None detected
  - **Path**: None detected

### Redis authentication password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded in the recipe as `redis_secure_password_123`
- **Usage context**: Passed to Redis as the `requirepass` value for instance `6379`
- **Migration requirement**: Store the value in Ansible Vault, an AAP credential, or another approved secret-management system. Do not place the literal password in group variables, role defaults, or plain-text templates.
- **Related attributes**: `masterauth`, `tlskeyfilepass`, and `tlsclientkeyfilepass` are supported but have no configured values.

No data bag, encrypted data bag, Chef Vault, Conjur, CyberArk, HashiCorp Vault, AWS Secrets Manager, environment-variable secret, certificate value, or database connection string was detected.

## Checks for the Migration

**Files to verify**:

- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/tmpfiles.d/redis@6379.conf`
- `/lib/systemd/system/redis@6379.service`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- `/etc/pam.d/su`
- `/etc/pam.d/sudo`
- Memcached configuration path supplied by the Memcached cookbook
- Redis source/build directory used by `redisio_install`
- Redis binary, normally `/usr/local/bin/redis-server`
- Memcached binary, normally `/usr/bin/memcached`

**Service endpoints to check**:

- Instance `memcached`: TCP `0.0.0.0:11211`
- Instance `memcached`: UDP `0.0.0.0:11211`
- Instance `6379`: TCP `0.0.0.0:6379`, unless the Redis address is overridden
- Unix sockets: none configured by default
- Redis TLS port: none configured
- Redis Sentinel port: none configured or executed

**Templates rendered**:

- Redis configuration template → `/etc/redis/6379.conf`: 1 render
- Systemd Redis template → `/lib/systemd/system/redis@6379.service`: 1 render on systemd
- Init.d Redis template → `/etc/init.d/redis6379`: 1 render on initd
- Upstart Redis template → `/etc/init/redis6379.conf`: 1 render on upstart
- FreeBSD rcinit Redis template → `/usr/local/etc/rc.d/redis6379`: 1 render on rcinit
- `/etc/pam.d/su`: 1 render on Debian-family systems

Only the template branch matching the target operating system and job-control mechanism should be implemented.

## Pre-flight checks

```bash
# Memcached instance: memcached
systemctl status memcached
systemctl is-enabled memcached
systemctl is-active memcached

printf "version\r\n" | nc -w 2 127.0.0.1 11211
printf "version\r\n" | nc -u -w 2 127.0.0.1 11211

ss -ltnp | grep ':11211'
ss -lunp | grep ':11211'

# Redis instance: 6379
systemctl status redis@6379
systemctl is-enabled redis@6379
systemctl is-active redis@6379

systemctl is-active redis-server || true
systemctl is-active redis || true

read -rsp 'Redis password: ' REDIS_PASSWORD
echo
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" PING
unset REDIS_PASSWORD

redis-cli -h 127.0.0.1 -p 6379 PING

grep -E '^(port|requirepass|dir|pidfile|loglevel|databases|maxclients)' \
  /etc/redis/6379.conf

grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' \
  /etc/redis/6379.conf

systemctl daemon-reload
systemctl cat redis@6379
systemctl show redis@6379 | grep -E 'User=|Group=|LimitNOFILE='

ss -ltnp | grep ':6379'
netstat -ltnp 2>/dev/null | grep ':6379' || true

stat -c '%U:%G %a %n' \
  /etc/redis \
  /var/lib/redis \
  /var/run/redis/6379 \
  /var/log/redis

journalctl -u redis@6379 --no-pager -n 100
pgrep -a redis-server
ps -o user,group,pid,ppid,args -C redis-server

# Confirm coexistence of both named instances
ss -ltnp | grep -E ':11211|:6379'
```

Expected results:

- `memcached` is active and enabled.
- Memcached accepts TCP and UDP requests on port `11211`.
- Redis instance `6379` is active and enabled as `redis@6379`.
- Authenticated Redis `PING` returns `PONG`.
- Unauthenticated Redis access fails with an authentication error.
- `/etc/redis/6379.conf` contains port `6379` and the Vault-supplied password.
- The five post-processing replication directives are absent.
- Redis runs as user and group `redis` with a file-descriptor limit approximately `10032`.
- Redis listens on TCP port `6379`.
- `/etc/redis` is root-owned with group `redis` and mode approximately `0775`.
- `/var/lib/redis` is owned by `redis:redis` with mode approximately `0775`.
- `/var/run/redis/6379` is owned by `redis:redis` with mode approximately `0755`.
- `/var/log/redis` is owned by `redis:redis` with mode `0755`.
- The distribution Redis service is inactive.
- Both cache instances are listening on their assigned ports, with no port collision.