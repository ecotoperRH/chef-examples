# Migration Plan: cache

**TLDR**: This cookbook configures two caching services: Memcached and Redis. It sets up a single instance of Memcached with default configuration and a single Redis instance on port 6379 with password authentication. The cookbook handles installation, configuration, and service management for both caching solutions.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Default memcached instance
  - Location/Path: System default (/var/lib/memcached)
  - Port/Socket: 11211 (TCP and UDP)
  - Key Config: 64MB memory, 1024 max connections

- **redis-6379**: Redis instance with authentication
  - Location/Path: /var/lib/redis
  - Port/Socket: 6379
  - Key Config: Password authentication enabled, default memory settings

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
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.rcinit.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.upstart.conf.erb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb
/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb
/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe
   - Sets Redis server configuration with password authentication
   - Creates Redis log directory
   - Includes Redis recipes
   - Fixes Redis configuration with a ruby_block
   - Resources: include_recipe (3), directory (1), ruby_block (1)

2. **memcached::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource: memcached_instance['memcached']
   - Configures memcached with 64MB memory, port 11211, and 1024 max connections
   - Resources: memcached_instance (1)

3. **redisio::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Updates apt repositories
   - Includes prerequisite recipes if not using package installation
   - Includes installation, OS default disabling, and configuration recipes
   - Resources: apt_update (1), include_recipe (3)

4. **redisio::_install_prereqs** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs prerequisite packages for Redis compilation
   - Resources: package (multiple, depends on platform)

5. **redisio::install** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Installs Redis either from package or source based on configuration
   - Includes prerequisite recipes
   - Uses custom resource: redisio_install['redis-installation']
   - Includes ulimit recipe for system limits configuration
   - Resources: package (1) or redisio_install (1), build_essential (1)

6. **redisio::ulimit** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Configures system limits for Redis
   - Sets up PAM configuration for ulimit
   - Resources: template (1), cookbook_file (1), user_ulimit (conditional)

7. **redisio::disable_os_default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Disables default OS Redis service if present
   - Resources: service (1) with stop and disable actions

8. **redisio::configure** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Includes default and ulimit recipes
   - Uses custom resource: redisio_configure['redis-servers']
   - Creates service resources for each Redis instance (in this case, just one instance on port 6379)
   - Resources: redisio_configure (1), service (1)
   - Conditional service provider based on init system:
     - If systemd? → service['redis@6379']
     - If upstart? → service['redis6379'] with Upstart provider
     - If rcinit? → service['redis6379'] with Freebsd provider
     - Otherwise → service['redis6379'] with default provider

9. **redisio::enable** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
   - Enables and starts Redis services
   - Iterations: Runs 1 time for server: 6379
   - Resources: service (1) with start and enable actions

10. **ruby_block[fix_redis_config]** (`cookbooks/cache/recipes/default.rb`):
    - Modifies Redis configuration file to remove specific lines
    - Removes replica-related configuration options
    - Resources: ruby_block (1)

## Dependencies

**External cookbook dependencies**:
- memcached (~> 6.0)
- redisio

**System package dependencies**:
- memcached
- redis (if package_install is true, otherwise compiled from source)
- build-essential (if compiling Redis from source)

**Service dependencies**:
- memcached.service
- redis@6379.service (systemd) or redis6379 (other init systems)

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
- /var/log/redis/
- /etc/memcached.conf (or platform-specific location)
- /var/log/memcached/

**Service endpoints to check**:
- Ports listening: 6379 (Redis), 11211 (Memcached TCP and UDP)
- Unix sockets: None specified
- Network interfaces: 0.0.0.0 (Memcached listens on all interfaces)

**Templates rendered**:
- Redis configuration template (redis.conf.erb → /etc/redis/6379.conf)
- Redis service template (depends on init system)
  - systemd: redis@.service.erb → /etc/systemd/system/redis@.service
  - upstart: redis.upstart.conf.erb → /etc/init/redis6379.conf
  - init.d: redis.init.erb → /etc/init.d/redis6379
  - rcinit: redis.rcinit.erb → /etc/rc.d/redis6379

## Pre-flight checks:

```bash
# Memcached checks
systemctl status memcached
ps aux | grep memcached
netstat -tulpn | grep 11211
ss -tulpn | grep 11211
echo "stats" | nc localhost 11211
echo "version" | nc localhost 11211
memcached-tool localhost:11211 stats

# Redis checks
systemctl status redis@6379
ps aux | grep redis
netstat -tulpn | grep 6379
ss -tulpn | grep 6379

# Redis connectivity test (with authentication)
redis-cli -h localhost -p 6379 -a redis_secure_password_123 PING
redis-cli -h localhost -p 6379 -a redis_secure_password_123 INFO server
redis-cli -h localhost -p 6379 -a redis_secure_password_123 INFO clients
redis-cli -h localhost -p 6379 -a redis_secure_password_123 INFO memory

# Redis configuration verification
cat /etc/redis/6379.conf | grep -v "^#" | grep -v "^$"
cat /etc/redis/6379.conf | grep requirepass
cat /etc/redis/6379.conf | grep -E "port|bind|maxmemory"

# Check for removed configuration lines
! grep -E "replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority" /etc/redis/6379.conf

# Log files
tail -f /var/log/redis/redis_6379.log
tail -f /var/log/memcached.log

# Directory permissions
ls -la /var/log/redis/
ls -la /var/lib/redis/

# System limits
cat /proc/$(pgrep redis-server)/limits
cat /proc/$(pgrep memcached)/limits

# Memory usage
ps aux | grep redis-server
ps aux | grep memcached
```