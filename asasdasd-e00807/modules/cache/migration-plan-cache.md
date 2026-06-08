---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook installs and configures both Memcached and Redis cache services. It sets up a single Memcached instance on port 11211 and a single Redis instance on port 6379 with password authentication. The cookbook handles installation, configuration, and service management for both caching solutions.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Default Memcached instance
  - Location/Path: /var/lib/memcached
  - Port/Socket: 11211
  - Key Config: 64MB memory, 1024 max connections

- **redis-6379**: Redis instance with authentication
  - Location/Path: /var/lib/redis
  - Port/Socket: 6379
  - Key Config: Password authentication enabled, 16 databases

## File Structure

```
cookbooks/cache/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **cache::default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe
   - Sets Redis server configuration with password authentication
   - Creates Redis log directory
   - Includes Redis recipes
   - Fixes Redis configuration with a ruby_block
   - Resources: include_recipe (3), directory (1), ruby_block (1)

2. **memcached::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource: memcached_instance['memcached']
   - Configures Memcached with 64MB memory, port 11211, and 1024 max connections
   - Resources: memcached_instance (1)

3. **redisio::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Updates apt package cache
   - Conditionally includes redisio::_install_prereqs if not using package install
   - Conditionally includes redisio::install, redisio::disable_os_default, and redisio::configure
   - Resources: apt_update (1), include_recipe (3)

4. **redisio::_install_prereqs** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs prerequisite packages based on platform
   - Resources: package (multiple, platform dependent)

5. **redisio::install** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Conditionally installs Redis from package or source
   - If using package: installs redis-server package
   - If using source: includes redisio::_install_prereqs and uses redisio_install custom resource
   - Includes redisio::ulimit
   - Resources: package (1) or redisio_install (1), include_recipe (1)

6. **redisio::ulimit** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Configures ulimit settings for Redis
   - On Debian systems: configures PAM settings
   - Resources: template (1), cookbook_file (1), user_ulimit (conditional)

7. **redisio::disable_os_default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables default OS Redis service if present
   - Resources: service (1)

8. **redisio::configure** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Uses custom resource: redisio_configure['redis-servers']
   - Configures Redis server(s) based on attributes
   - Creates service resources based on job control system (systemd, initd, upstart, or rcinit)
   - Resources: redisio_configure (1), service (1 per server)

9. **ruby_block[fix_redis_config]** (`cookbooks/cache/recipes/default.rb`):
   - Modifies Redis configuration file to remove specific lines
   - Removes replica-related configuration options
   - Resources: ruby_block (1)

10. **redisio::enable** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Enables and starts Redis service(s)
    - Iterates over server instances: 6379
    - Resources: service (1 per server)

## Dependencies

**External cookbook dependencies**:
- memcached
- redisio

**System package dependencies**:
- memcached
- redis-server (if using package install)
- build-essential (if building from source)

**Service dependencies**:
- memcached.service
- redis@6379.service (systemd) or redis6379 (initd/upstart)

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Redis Password

- **Variable(s)**: `node['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: hardcoded
- **Usage context**: Redis authentication password used for client connections

## Checks for the Migration

**Files to verify**:
- /etc/redis/6379.conf
- /etc/memcached.conf (or /etc/sysconfig/memcached on RHEL)
- /var/log/redis/
- /var/log/memcached.log

**Service endpoints to check**:
- Ports listening: 6379 (Redis), 11211 (Memcached)
- Unix sockets: None specified
- Network interfaces: 0.0.0.0 (Memcached), Redis binds to default

**Templates rendered**:
- redis.conf.erb → /etc/redis/6379.conf (1 instance)
- redis@.service.erb → /etc/systemd/system/redis@6379.service (if using systemd)
- redis.init.erb → /etc/init.d/redis6379 (if using initd)

## Pre-flight checks:

```bash
# Memcached checks
systemctl status memcached
ps aux | grep memcached
netstat -tulpn | grep 11211
ss -tlnp | grep memcached
echo "stats" | nc localhost 11211
echo "version" | nc localhost 11211
cat /etc/memcached.conf

# Redis checks
systemctl status redis@6379
ps aux | grep redis
netstat -tulpn | grep 6379
ss -tlnp | grep redis

# Redis authentication check
redis-cli -h localhost -p 6379 -a redis_secure_password_123 ping
redis-cli -h localhost -p 6379 -a redis_secure_password_123 info

# Redis configuration check
cat /etc/redis/6379.conf | grep -E 'port|requirepass|databases'
cat /etc/redis/6379.conf | grep -v "^#" | grep -v "^$"

# Check for removed configuration lines
cat /etc/redis/6379.conf | grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority'

# Log files
ls -la /var/log/redis/
tail -f /var/log/redis/*.log
tail -f /var/log/memcached.log

# Memory usage
ps -o pid,user,%mem,command ax | grep redis
ps -o pid,user,%mem,command ax | grep memcached

# Connectivity tests
echo "set test 0 60 5\r\nhello\r" | nc localhost 11211
echo "get test\r" | nc localhost 11211

# Redis data test
redis-cli -h localhost -p 6379 -a redis_secure_password_123 set test "hello"
redis-cli -h localhost -p 6379 -a redis_secure_password_123 get test

# Service file verification
if [ -f /etc/systemd/system/redis@6379.service ]; then
  cat /etc/systemd/system/redis@6379.service
elif [ -f /etc/init.d/redis6379 ]; then
  cat /etc/init.d/redis6379
fi

# Check ulimit settings for Redis
cat /proc/$(pgrep -f "redis-server.*:6379")/limits
```