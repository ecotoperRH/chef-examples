---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: The `cache` cookbook configures one Memcached instance named `memcached` and one Redis instance named `6379`. Memcached listens on TCP and UDP port `11211` and is started and enabled through `memcached_instance[memcached]`. Redis `3.2.11` is installed from source by default on Debian-family systems, listens on port `6379`, uses a hardcoded authentication password that must be migrated to Ansible Vault, and is managed through the `redisio` custom resources. The cookbook creates Redis configuration, data, PID, and log directories, disables the operating-system Redis service, configures service startup, and removes selected Redis directives through a post-configuration cleanup workaround.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **`memcached`**: Memcached caching service
  - Location/Path: Managed by the `memcached_instance[memcached]` custom resource
  - Port/Socket: TCP `0.0.0.0:11211`; UDP `0.0.0.0:11211`
  - Key Config: Memory `64` MB; maximum connections `1024`; maximum object size `1m`; service user `service_user`; ulimit `1024`; starts and enables the service

- **`6379`**: Redis caching service
  - Location/Path: Configuration `/etc/redis/6379.conf`; data `/var/lib/redis`; PID `/var/run/redis/6379`
  - Port/Socket: TCP port `6379`; no Unix socket or TLS port configured
  - Key Config: Redis `3.2.11`; password `redis_secure_password_123`; user/group `redis`/`redis`; `16` databases; maximum clients `10000`; default RDB persistence; source installation by default; service name `redis@6379` under systemd or `redis6379` under init.d/upstart/rcinit

## File Structure

```text
### Recipes

cookbooks/cache/recipes/default.rb
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb

### Providers

migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb

### Templates

migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/#{node['redisio']['redis_config']['template_source']}

### Attributes

migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb

### Files

No static `cookbook_file` deployment is part of the active default execution. The conditional `cookbook_file[/etc/pam.d/sudo]` resource exists in the Debian branch of `redisio::ulimit`; its source cookbook and source file are unresolved by the wrapper cookbook and require manual resolution before migration.
```

## Module Explanation

The cookbook performs operations in this order:

1. **`cache::default`** (`cookbooks/cache/recipes/default.rb`):
   - Sets one Redis server item: port and derived name `6379`, password `redis_secure_password_123`, and `replicaservestaledata` set to `nil`.
   - Includes `memcached::default` before Redis.
   - Creates `/var/log/redis` owned by `redis:redis` with mode `0755`.
   - Includes `redisio::default`.
   - Runs `ruby_block[fix_redis_config]`, removing lines beginning with `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from `/etc/redis/6379.conf` when the file exists.
   - Includes `redisio::enable`.
   - Resources: one `directory`, one `ruby_block`, and three `include_recipe` resources.

2. **`memcached::default`** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Creates `memcached_instance[memcached]`.
   - Configures memory `64`, TCP port `11211`, UDP port `11211`, listen address `0.0.0.0`, maximum connections `1024`, service user `service_user`, maximum object size `1m`, configured thread value, empty experimental and extra CLI option lists, and ulimit `1024`.
   - Starts and enables the Memcached service.
   - The custom resource performs dependency installation, configuration, startup, and enablement; its provider is not included in the supplied execution tree.

3. **`redisio::default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Runs `apt_update[apt_update]`.
   - When `package_install` is false, includes `redisio::_install_prereqs` and runs `build_essential[install build deps]`.
   - When `bypass_setup` is false, includes `redisio::install`, `redisio::disable_os_default`, and `redisio::configure`.
   - Source installation is selected by default because `package_install` defaults to `false`.

4. **`redisio::_install_prereqs`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs one package: `tar`.
   - Iteration expansion: `package[tar]` runs once with action `install` on Debian, RHEL, and Fedora.
   - The package collection is empty on other platforms.

5. **`redisio::install`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Uses package `redis-server` on Debian or `redis` on RHEL/Fedora when `package_install` is true.
   - Uses source installation when `package_install` is false.
   - Includes `redisio::_install_prereqs` and runs `build_essential[install build deps]`.
   - Downloads `http://download.redis.io/releases/redis-3.2.11.tar.gz`.
   - Extracts `redis-3.2.11`, runs `make clean && make`, then runs `make install`.
   - Installs binaries under `/usr/local/bin` unless `install_dir` is configured.
   - Uses `redisio_install[redis-installation]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb`.
   - Includes `redisio::ulimit`.

6. **`redisio::ulimit`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - On Debian-family systems, renders `template[/etc/pam.d/su]` using `node['ulimit']['pam_su_template_cookbook']`.
   - On Debian-family systems, declares conditional `cookbook_file[/etc/pam.d/sudo]` using source name `sudo` and `node['ulimit']['ulimit_overriding_sudo_file_cookbook']`.
   - The source cookbook and source file for `/etc/pam.d/sudo` are not configured by `cache`; the migration must resolve them manually or intentionally omit this conditional task with an explicit implementation note.
   - The `users` collection is empty, so no `user_ulimit` resources are created.

7. **`redisio::disable_os_default`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables `service[redis-server]` on Debian.
   - Stops and disables `service[redis]` on RHEL/Fedora.
   - Skips the resource when no platform service name is available.

8. **`redisio::configure`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Resolves exactly one Redis item: `6379`.
   - Uses port `6379`, derived name `6379`, password `redis_secure_password_123`, and `replicaservestaledata: nil`.
   - Uses `redisio_configure[redis-servers]`, implemented by `migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb`.
   - Creates or manages user `redis` with home `/var/lib/redis`, system-user enabled, managed home, and `/bin/false` shell on Debian.
   - Creates `/etc/redis` with owner `root`, group `redis`, and mode `0775`.
   - Creates `/var/lib/redis` with owner/group `redis:redis` and mode `0775`.
   - Creates `/var/run/redis/6379` with owner/group `redis:redis` and mode `0755`.
   - Does not create a log directory or log file by default because `logfile` is `nil`.
   - Applies SELinux resources only when SELinux is enabled.
   - Adjusts existing AOF/RDB file permissions when applicable.
   - Applies a calculated file-descriptor limit of `10032` (`maxclients` `10000` plus `32`).
   - Does not perform a data bag lookup because `data_bag_name`, `data_bag_item`, and `data_bag_key` are unset.
   - Renders `redis.conf.erb` to `/etc/redis/6379.conf`, owned by `redis:redis` with mode `0644`.
   - Does not overwrite the configuration when `/etc/redis/6379.conf.breadcrumb` exists.
   - Creates `/etc/redis/6379.conf.breadcrumb` when `breadcrumb` is true, which is the default.
   - Under systemd, creates `/etc/tmpfiles.d/redis@6379.conf`, executes `systemctl daemon-reload` through `execute[redis@6379 systemd reload]`, and renders `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`.
   - Under init.d, renders `redis.init.erb` to `/etc/init.d/redis6379`.
   - Under upstart, renders `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`.
   - Under rcinit, renders `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`.
   - The systemd unit uses `/usr/local/bin/redis-server`, `/etc/redis/%i.conf`, user/group `redis:redis`, and `LimitNOFILE=10032`.

9. **`redisio::enable`** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Iteration expansion: processes Redis instance `6379` once.
   - Enables and starts `service[redis@6379]` under systemd.
   - Enables and starts `service[redis6379]` under init.d, upstart, or rcinit.

## Dependencies

**External cookbook dependencies**:
- `memcached`, version `~> 6.0`
- `redisio`, no explicit version constraint

**System package dependencies**:
- `tar` on Debian, RHEL, and Fedora for source installation
- Build dependencies supplied through `build_essential`
- `redis-server` on Debian when package installation is explicitly enabled
- `redis` on RHEL/Fedora when package installation is explicitly enabled

**Service dependencies**:
- Memcached service managed by `memcached_instance[memcached]`
- Redis instance `6379`, managed as `redis@6379` under systemd or `redis6379` under init.d, upstart, and rcinit
- Operating-system Redis service stopped and disabled: `redis-server` on Debian or `redis` on RHEL/Fedora

## Credentials

**Detection Summary**: 1 credential detected across 1 source file.

**Source**:
  - **Provider**: Hardcoded Chef node default attribute assignment; no external secret provider is used
  - **URL**: None
  - **Path**: `cookbooks/cache/recipes/default.rb`

### Redis authentication password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded as `redis_secure_password_123` in a Chef node default attribute assignment
- **Usage context**: Rendered as the Redis `requirepass` value for instance `6379`
- **Migration storage**: Move to an Ansible Vault variable such as `redis_password`; use `no_log: true` for tasks that may expose the value

The Redis provider supports data-bag loading for `requirepass` and `masterauth`, but the required data-bag attributes are unset and no lookup occurs. No Chef Vault, encrypted data bag, CyberArk, Conjur, HashiCorp Vault, AWS Secrets Manager, or environment-variable secret usage was detected. TLS certificate, key, CA, and key-passphrase attributes are also unset.

## Checks for the Migration

**Files to verify**:
- Memcached service configuration and status
- `/etc/redis/6379.conf`
- `/etc/redis/6379.conf.breadcrumb`
- `/etc/redis`
- `/var/lib/redis`
- `/var/run/redis/6379`
- `/var/log/redis`
- `/lib/systemd/system/redis@6379.service`
- `/etc/tmpfiles.d/redis@6379.conf`
- `/etc/init.d/redis6379`
- `/etc/init/redis6379.conf`
- `/usr/local/etc/rc.d/redis6379`
- `/etc/pam.d/su`
- `/etc/pam.d/sudo` when the Debian `redisio::ulimit` conditional source is resolved and migrated

**Service endpoints to check**:
- Memcached TCP `0.0.0.0:11211`
- Memcached UDP `0.0.0.0:11211`
- Redis TCP port `6379`
- Redis Unix socket: none
- Redis TLS: none
- Redis Sentinel: none

**Templates rendered**:
- `redis.conf.erb` to `/etc/redis/6379.conf`: 1 render, subject to the breadcrumb guard
- `/etc/redis/6379.conf.breadcrumb`: 1 creation
- `redis@.service.erb` to `/lib/systemd/system/redis@6379.service`: 1 render when `job_control` is `systemd`
- `redis.init.erb` to `/etc/init.d/redis6379`: 1 render when `job_control` is `initd`
- `redis.upstart.conf.erb` to `/etc/init/redis6379.conf`: 1 render when `job_control` is `upstart`
- `redis.rcinit.erb` to `/usr/local/etc/rc.d/redis6379`: 1 render when `job_control` is `rcinit`
- Only one service-manager template is rendered for Redis instance `6379`

## Pre-flight checks

The commands below assume Debian/Ubuntu, systemd, and source-installed Redis.

### Memcached instance `memcached`

```bash
systemctl status memcached
systemctl is-enabled memcached

ss -ltnp | grep ':11211'
lsof -iTCP:11211 -sTCP:LISTEN
ss -lunp | grep ':11211'

printf "version\r\n" | nc -w 2 127.0.0.1 11211
printf "stats\r\n" | nc -w 2 127.0.0.1 11211 | head -20

systemctl show memcached | grep -E 'User=|LimitNOFILE='
ps aux | grep '[m]emcached'
```

Expected results: Memcached is active and enabled, TCP and UDP port `11211` are listening, and the protocol test returns a `VERSION` response.

### Redis instance `6379`

```bash
systemctl status redis@6379
systemctl is-enabled redis@6379

ps aux | grep '[r]edis-server.*6379.conf'
ss -ltnp | grep ':6379'
lsof -iTCP:6379 -sTCP:LISTEN

redis-cli -p 6379 PING
redis-cli -p 6379 -a "$REDIS_PASSWORD" PING

grep -E '^(port|requirepass|dir|pidfile|databases|maxclients)' /etc/redis/6379.conf

systemctl cat redis@6379
cat /etc/tmpfiles.d/redis@6379.conf
ls -ld /etc/redis /var/lib/redis /var/run/redis/6379

cat /etc/redis/6379.conf.breadcrumb
/usr/local/bin/redis-server -v
ls -lah /var/lib/redis
journalctl -u redis@6379 --no-pager -n 100
```

Expected results: `redis@6379` is active and enabled, Redis listens on TCP port `6379`, unauthenticated access is rejected because authentication is configured, authenticated access returns `PONG`, `/etc/redis/6379.conf` is owned by `redis:redis` with mode `0644`, and the data and PID directories are owned by `redis:redis`.

### Disabled operating-system Redis service

```bash
systemctl status redis-server
systemctl is-enabled redis-server
```

Expected result: `redis-server` is stopped and disabled, while the independently managed service is `redis@6379`.

### Configuration cleanup

```bash
grep -E '^(replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority)' /etc/redis/6379.conf
```

The five targeted directives should be absent when the cleanup workaround applies.

### Authentication validation

Use an Ansible Vault variable and protect authentication tasks with `no_log: true`. Avoid placing the password directly in command-line arguments where possible.

```bash
redis-cli -p 6379 --user default PING
```

Use the appropriate password or ACL mechanism for the target Redis version without exposing the secret in Ansible output.