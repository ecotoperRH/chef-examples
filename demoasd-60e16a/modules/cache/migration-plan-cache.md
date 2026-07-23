---
source-path: cookbooks/cache
---

# Migration Plan: Cache

**TLDR**: This cookbook sets up a caching infrastructure with both Memcached and Redis services. It configures one Memcached instance on port 11211 and one Redis instance on port 6379 with password authentication. The cookbook handles installation, configuration, and service management for both caching solutions.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: In-memory caching service
  - Location/Path: System default paths
  - Port/Socket: 11211 (TCP and UDP)
  - Key Config: 64MB memory, 1024 max connections, listens on 0.0.0.0

- **redis**: In-memory data structure store
  - Location/Path: /etc/redis/6379.conf
  - Port/Socket: 6379
  - Key Config: Password authentication enabled with 'redis_secure_password_123'

## File Structure

**Recipes:**
```
cookbooks/cache/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb
```

**Providers:**
```
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/configure.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/providers/install.rb
```

**Templates:**
```
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.init.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
```

**Attributes:**
```
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe
   - Sets Redis server configuration with authentication
   - Creates Redis log directory
   - Includes Redis recipes
   - Fixes Redis configuration with a ruby_block
   - Resources: include_recipe (3), directory (1), ruby_block (1)

2. **memcached::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource: memcached_instance['memcached']
   - Configures memcached with 64MB memory, port 11211, max connections 1024
   - Sets memcached to listen on 0.0.0.0
   - Resources: memcached_instance (1)

3. **redisio::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Updates apt package cache
   - Includes prerequisite installation recipe
   - Resources: apt_update (1), include_recipe (1)

4. **redisio::_install_prereqs** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs platform-specific prerequisite packages
   - For Debian: installs build-essential package
   - Resources: package (variable number based on platform)

5. **redisio::install** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Installs Redis either from package or source
   - Uses custom resource: redisio_install['redis-installation']
   - Includes ulimit recipe
   - Resources: build_essential (1), redisio_install (1), include_recipe (1)

6. **redisio::ulimit** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Configures ulimit settings for Redis
   - On Debian platforms, configures PAM settings
   - Resources: template (1), cookbook_file (1), user_ulimit (variable)

7. **redisio::disable_os_default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Stops and disables default OS Redis service if present
   - Resources: service (1)

8. **redisio::configure** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Uses custom resource: redisio_configure['redis-servers']
   - Configures Redis server instance on port 6379 with password authentication
   - Sets up service management based on job control system (systemd, initd, upstart, or rcinit)
   - Resources: redisio_configure (1), service (1)

9. **ruby_block[fix_redis_config]** (`cookbooks/cache/recipes/default.rb`):
   - Modifies Redis configuration file at /etc/redis/6379.conf
   - Removes specific configuration lines related to replication
   - Resources: ruby_block (1)

10. **redisio::enable** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Enables and starts Redis service for the configured instance (port 6379)
    - Uses appropriate service name based on job control system
    - Resources: service (1)

## Dependencies

**External cookbook dependencies**:
- memcached
- redisio

**System package dependencies**:
- memcached
- redis-server (or build dependencies if installing from source)
- build-essential (when installing Redis from source)

**Service dependencies**:
- memcached.service
- redis@6379.service (systemd) or redis6379 (initd/upstart)

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Redis Authentication Password

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: hardcoded
- **Usage context**: Redis server authentication password used to secure Redis instance

## Checks for the Migration

**Files to verify**:
- /etc/redis/6379.conf
- /var/log/redis/
- /etc/memcached.conf (or platform-specific location)
- /var/log/memcached

**Service endpoints to check**:
- Ports listening: 6379 (Redis), 11211 (Memcached TCP/UDP)
- Unix sockets: None specified
- Network interfaces: 0.0.0.0 (Memcached), Redis binding depends on default configuration

**Templates rendered**:
- Redis configuration template → /etc/redis/6379.conf
- Redis service template (based on init system) → appropriate service file location

## Pre-flight checks:

```bash
# Memcached checks
systemctl status memcached
ps aux | grep memcached
netstat -tulpn | grep 11211
ss -tulpn | grep 11211
echo "stats" | nc localhost 11211
echo "version" | nc localhost 11211

# Redis checks
systemctl status redis@6379
ps aux | grep redis
netstat -tulpn | grep 6379
ss -tulpn | grep 6379

# Redis authentication check
redis-cli -h localhost -p 6379 ping
# Should fail without password
redis-cli -h localhost -p 6379 -a 'redis_secure_password_123' ping
# Should return PONG

# Redis configuration check
cat /etc/redis/6379.conf | grep requirepass
cat /etc/redis/6379.conf | grep port

# Check for removed configuration lines
cat /etc/redis/6379.conf | grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority'
# Should return nothing

# Memory usage checks
ps -o pid,user,%mem,command ax | grep memcached
ps -o pid,user,%mem,command ax | grep redis

# Log checks
tail -f /var/log/memcached
tail -f /var/log/redis/redis_6379.log

# Service file verification
if [ -f /etc/systemd/system/redis@.service ]; then
  cat /etc/systemd/system/redis@.service
elif [ -f /etc/init.d/redis6379 ]; then
  cat /etc/init.d/redis6379
fi

if [ -f /etc/systemd/system/memcached.service ]; then
  cat /etc/systemd/system/memcached.service
elif [ -f /etc/init.d/memcached ]; then
  cat /etc/init.d/memcached
fi

# Ulimit checks for Redis
cat /proc/$(pgrep -f 'redis-server.*:6379')/limits

# Functional tests
# Memcached
echo -e "set test_key 0 60 11\nhello world" | nc localhost 11211
echo -e "get test_key" | nc localhost 11211
# Should return "hello world"

# Redis
redis-cli -h localhost -p 6379 -a 'redis_secure_password_123' set test_key "hello world"
redis-cli -h localhost -p 6379 -a 'redis_secure_password_123' get test_key
# Should return "hello world"
```