---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook installs and configures two in-memory cache services: Memcached (single instance listening on port 11211 with 64MB memory) and Redis (single instance listening on port 6379 with password authentication). Both services are managed by systemd on modern systems. The cookbook includes dependency management for build tools, ulimit configuration, and SELinux support for Redis.

## Service Type and Instances

**Service Type**: Cache (In-Memory Data Store)

**Configured Instances**:

- **memcached**: Single Memcached instance
  - Port: 11211 (TCP and UDP)
  - Listen Address: 0.0.0.0
  - Memory: 64 MB
  - Max Connections: 1024
  - Max Object Size: 1m
  - User: memcache (Debian) / memcached (RHEL/Fedora)
  - Log Path: /var/log/memcached/memcached.log
  - Service Name: memcached (systemd)

- **redis**: Single Redis instance
  - Port: 6379 (TCP)
  - Authentication: Enabled (password: redis_secure_password_123)
  - Data Directory: /var/lib/redis
  - Config Directory: /etc/redis
  - Config File: /etc/redis/6379.conf
  - Log Directory: /var/log/redis
  - User: redis
  - Group: redis
  - Service Name: redis@6379 (systemd) / redis6379 (initd/upstart/rcinit)
  - Job Control: systemd (default on modern systems), initd, upstart, or rcinit (FreeBSD)

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

**Resources:**
```
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/resources/memcached_instance.rb
```

**Providers:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
```

**Templates:**
```
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
```

**Attributes:**
```
migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe to install and configure Memcached
   - Creates Redis log directory: /var/log/redis (owner: redis, group: redis, mode: 0755)
   - Configures Redis with single instance on port 6379 with password authentication
   - Includes redisio recipe to install and configure Redis
   - Executes ruby_block to fix Redis configuration by removing deprecated replica-related settings from /etc/redis/6379.conf:
     - Removes: replica-serve-stale-data, replica-read-only, repl-ping-replica-period, client-output-buffer-limit, replica-priority
   - Includes redisio::enable recipe to start and enable Redis service
   - Resources: directory (1), ruby_block (1), include_recipe (3)

**2. memcached::default** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource: memcached_instance['memcached']
     - Provider: migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/resources/memcached_instance.rb
     - Memory: 64 MB
     - Port: 11211 (TCP)
     - UDP Port: 11211
     - Listen: 0.0.0.0
     - Max Connections: 1024
     - Max Object Size: 1m
     - User: memcache (Debian) / memcached (RHEL/Fedora)
     - Ulimit: 1024
     - Actions: [:start, :enable]
     - Creates systemd unit file: /etc/systemd/system/memcached.service
     - Disables default memcached service if instance name is not 'memcached'
     - Removes default config files: /etc/memcached.conf, /etc/sysconfig/memcached, /etc/default/memcached
   - Resources: memcached_instance (1)

**3. memcached::_package** (`migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb`):
   - Installs memcached package
   - Creates memcache system group (Debian) / memcached system group (RHEL/Fedora)
   - Creates memcache system user (Debian) / memcached system user (RHEL/Fedora)
     - Home: /nonexistent
     - Shell: /bin/false
     - Comment: Memcached
     - Action: [:create, :lock]
   - Creates log directory: /var/log/memcached (owner: memcache/memcached, group: memcache/memcached, mode: 0755)
   - Creates runtime directory: /var/run/memcached (owner: memcache/memcached, group: memcache/memcached, mode: 0755)
   - Resources: package (1), group (1), user (1), directory (2)

**4. redisio::default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Updates apt cache (Debian systems)
   - Conditionally includes _install_prereqs recipe if package_install is false (source compilation)
   - Conditionally includes build_essential recipe if package_install is false
   - Conditionally includes install recipe if bypass_setup is false
   - Conditionally includes disable_os_default recipe if bypass_setup is false
   - Conditionally includes configure recipe if bypass_setup is false
   - Resources: apt_update (1), include_recipe (4-6 conditional)

**5. redisio::_install_prereqs** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs build prerequisites for source compilation
   - Installs package: tar
   - Resources: package (1)

**6. redisio::install** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Conditional branch 1 - Package install (if package_install is true):
     - Installs redis-server package (Debian) / redis package (RHEL/Fedora)
     - Resources: package (1)
   - Conditional branch 2 - Source install (if package_install is false):
     - Includes _install_prereqs recipe
     - Includes build_essential recipe
     - Uses custom resource: redisio_install['redis-installation']
       - Provider: migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
       - Version: 3.2.11 (default for source install)
       - Download URL: http://download.redis.io/releases/redis-3.2.11.tar.gz
       - Safe Install: true (prevents overwriting existing Redis)
       - Downloads tarball, unpacks, builds with make, installs to /usr/local/bin
     - Resources: redisio_install (1)
   - Includes ulimit recipe
   - Resources: include_recipe (1)

**7. redisio::ulimit** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Conditional: if platform_family is 'debian'
     - Deploys /etc/pam.d/su template
     - Deploys /etc/pam.d/sudo cookbook file
   - Conditional: if ulimit['users'] hash exists
     - Uses custom resource: user_ulimit for each configured user (0-N iterations)
   - Resources: template (1), cookbook_file (1), user_ulimit (0-N conditional)

**8. redisio::disable_os_default** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Disables default OS Redis service to prevent conflicts
   - Conditional: Determines service name based on platform_family
     - Debian: redis-server
     - RHEL/Fedora: redis
   - Stops and disables the default service
   - Resources: service (1)

**9. redisio::configure** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes redisio::default recipe
   - Includes redisio::ulimit recipe
   - Determines redis_instances from node['redisio']['servers'] or defaults to single instance on port 6379
   - Uses custom resource: redisio_configure['redis-servers']
     - Provider: migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
     - Version: 3.2.11 (default)
     - Default Settings: Comprehensive Redis configuration defaults
     - Servers: Array with single instance: [{port: 6379, requirepass: redis_secure_password_123, replicaservestaledata: nil}]
     - Base PID Directory: /var/run/redis
     - For Redis instance on port 6379, creates:
       - Redis user (redis) with home directory /var/lib/redis
       - Configuration directory: /etc/redis (mode: 0775)
       - Data directory: /var/lib/redis (mode: 0775)
       - PID directory: /var/run/redis/6379 (mode: 0755)
       - Log directory: /var/log/redis (if logfile is configured, mode: 0755)
       - Configuration file: /etc/redis/6379.conf (rendered from redis.conf.erb)
         - Template variables: port, requirepass, maxclients, maxmemory, databases, persistence settings, replication settings, cluster settings, TLS settings, etc.
       - Breadcrumb file: /etc/redis/6379.conf.breadcrumb (prevents overwriting config on subsequent runs)
       - Init script based on job_control setting:
         - systemd: /lib/systemd/system/redis@6379.service (rendered from redis@.service.erb)
         - initd: /etc/init.d/redis6379 (rendered from redis.init.erb)
         - upstart: /etc/init/redis6379.conf (rendered from redis.upstart.conf.erb)
         - rcinit (FreeBSD): /usr/local/etc/rc.d/redis6379 (rendered from redis.rcinit.erb)
       - tmpfiles.d config for systemd: /etc/tmpfiles.d/redis@6379.conf (manages Redis runtime directory persistence across reboots)
   - Creates service resource for Redis instance 6379:
     - Service name: redis@6379 (systemd) / redis6379 (other init systems)
     - Supports: start, stop, restart, status
   - Resources: redisio_configure (1), service (1)

**10. redisio::enable** (`migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Enables and starts Redis service instance 6379
   - Modifies service resource created in configure recipe
   - Adds actions: [:start, :enable]
   - Service name: redis@6379 (systemd) / redis6379 (other init systems)
   - Resources: service (1 modified)

## Dependencies

**External cookbook dependencies**: 
- memcached (7992788f1a376defb902059063f5295e37d281cb)
- redisio (cac70a2ec9102cac4f5391358c8565d244f5d4db)
- build-essential (for source compilation of Redis)
- ulimit (embedded in redisio)
- selinux (optional, used if SELinux is enabled)

**System package dependencies**: 
- memcached (package)
- redis-server (Debian) / redis (RHEL/Fedora) - if package_install is true
- tar (for source compilation)
- build-essential packages (gcc, make, etc. for source compilation)

**Service dependencies**: 
- systemd (or initd/upstart/rcinit depending on platform)
- memcached service
- redis service (redis@6379 on systemd, redis6379 on other init systems)

## Credentials

**Detection Summary**: 1 credential detected in 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Redis Authentication Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: Hardcoded in recipe
- **Usage context**: Redis server authentication - used in requirepass configuration directive in /etc/redis/6379.conf to require password authentication for all Redis connections

**CRITICAL SECURITY NOTE**: The Redis password `redis_secure_password_123` is hardcoded in the recipe. This is a security risk and should be migrated to use:
- Ansible Vault for encrypted variable storage
- External secrets management (HashiCorp Vault, AWS Secrets Manager, CyberArk)
- Environment variables injected at runtime
- Ansible Tower/AAP credential management

## Checks for the Migration

**Files to verify**:
- /var/log/memcached/memcached.log (Memcached log file)
- /var/log/redis (Redis log directory)
- /var/lib/redis (Redis data directory)
- /var/run/redis/6379 (Redis PID directory)
- /var/run/memcached (Memcached runtime directory)
- /etc/redis/6379.conf (Redis configuration file)
- /etc/redis/6379.conf.breadcrumb (Redis configuration breadcrumb file)
- /etc/systemd/system/memcached.service (Memcached systemd unit)
- /lib/systemd/system/redis@6379.service (Redis systemd unit)
- /etc/tmpfiles.d/redis@6379.conf (Redis tmpfiles.d configuration)

**Service endpoints to check**:
- Ports listening:
  - 11211 (Memcached TCP and UDP)
  - 6379 (Redis TCP)
- Unix sockets: None configured by default
- Network interfaces: 0.0.0.0 (Memcached listens on all interfaces), 127.0.0.1 (Redis default if not specified)

**Templates rendered**:
- redis.conf.erb → /etc/redis/6379.conf (1 time for single Redis instance)
- redis@.service.erb → /lib/systemd/system/redis@6379.service (1 time for systemd)
- redis.init.erb → /etc/init.d/redis6379 (1 time for initd, if applicable)
- redis.upstart.conf.erb → /etc/init/redis6379.conf (1 time for upstart, if applicable)
- redis.rcinit.erb → /usr/local/etc/rc.d/redis6379 (1 time for FreeBSD rcinit, if applicable)

## Pre-flight checks:

```bash
# Memcached service status
systemctl status memcached
ps aux | grep memcached | grep -v grep

# Memcached connectivity - verify port 11211 is listening
netstat -tulpn | grep 11211
ss -tlnp | grep 11211
lsof -i :11211

# Memcached health check
echo "stats" | nc localhost 11211
echo "version" | nc localhost 11211

# Memcached logs
tail -f /var/log/memcached/memcached.log
journalctl -u memcached -f

# Memcached set/get operations test
echo -e "set testkey 0 0 5\nhello\nget testkey\nquit" | nc localhost 11211

# Redis service status
systemctl status redis@6379
ps aux | grep redis | grep -v grep

# Redis connectivity - verify port 6379 is listening
netstat -tulpn | grep 6379
ss -tlnp | grep 6379
lsof -i :6379

# Redis authentication test - MUST provide password
redis-cli -p 6379 -a redis_secure_password_123 PING
# Expected output: PONG

# Redis info command - verify authentication works
redis-cli -p 6379 -a redis_secure_password_123 INFO server
# Should show Redis version and server info

# Redis configuration validation
cat /etc/redis/6379.conf | grep -E 'port|requirepass|maxmemory|databases'
redis-cli -p 6379 -a redis_secure_password_123 CONFIG GET requirepass
# Expected output: 1) "requirepass" 2) "redis_secure_password_123"

# Redis logs
tail -f /var/log/redis/redis.log
journalctl -u redis@6379 -f

# Redis data directory
ls -lah /var/lib/redis/
df -h /var/lib/redis/

# Redis configuration file
ls -lah /etc/redis/6379.conf
cat /etc/redis/6379.conf | head -50

# Verify deprecated settings were removed by ruby_block
grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority' /etc/redis/6379.conf
# Should return nothing (empty output)

# Verify both services are enabled and will start on boot
systemctl is-enabled memcached
systemctl is-enabled redis@6379

# Memory usage
ps aux | grep -E 'memcached|redis' | grep -v grep | awk '{print $2, $6}'
# Memcached should use ~64MB, Redis usage depends on data

# Network connections
netstat -tulpn | grep -E '11211|6379'
ss -tlnp | grep -E '11211|6379'

# Verify systemd units exist
ls -lah /etc/systemd/system/memcached.service
ls -lah /lib/systemd/system/redis@6379.service
ls -lah /etc/tmpfiles.d/redis@6379.conf

# Verify user and group ownership
id memcache  # Debian
id memcached  # RHEL/Fedora
id redis

# Verify directory permissions
ls -lah /var/log/memcached/
ls -lah /var/log/redis/
ls -lah /var/lib/redis/
ls -lah /var/run/redis/
ls -lah /etc/redis/

# Test Redis set/get operations
redis-cli -p 6379 -a redis_secure_password_123 SET testkey "hello"
redis-cli -p 6379 -a redis_secure_password_123 GET testkey
# Expected output: "hello"

# Test Redis persistence (RDB)
redis-cli -p 6379 -a redis_secure_password_123 BGSAVE
redis-cli -p 6379 -a redis_secure_password_123 LASTSAVE
ls -lah /var/lib/redis/dump-6379.rdb

# Verify no errors in logs
grep ERROR /var/log/memcached/memcached.log
grep ERROR /var/log/redis/redis.log
journalctl -u memcached -p err
journalctl -u redis@6379 -p err

# Verify SELinux contexts (if SELinux is enabled)
getenforce
ls -laZ /etc/redis/
ls -laZ /var/lib/redis/
ls -laZ /var/log/redis/
```