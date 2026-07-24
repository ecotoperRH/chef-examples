---
source-path: cookbooks/cache
---

# Migration Plan: cache

**TLDR**: This cookbook configures a caching infrastructure with both Memcached and Redis services. It sets up a single Memcached instance on port 11211 and a single Redis instance on port 6379 with password authentication. The Redis configuration includes some custom modifications to remove specific replication-related settings.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **memcached**: Standard Memcached instance
  - Location/Path: System default (/var/lib/memcached)
  - Port/Socket: 11211 (TCP and UDP)
  - Key Config: 64MB memory, 1024 max connections, listening on 0.0.0.0

- **redis-6379**: Redis instance with authentication
  - Location/Path: /var/lib/redis
  - Port/Socket: 6379
  - Key Config: Password authentication enabled, 16 databases, specific replication settings removed

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

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe
   - Sets Redis server configuration with authentication
   - Creates Redis log directory
   - Includes Redis recipes
   - Modifies Redis configuration to remove specific replication settings
   - Resources: include_recipe (3), directory (1), ruby_block (1)

2. **memcached::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb`):
   - Uses custom resource: memcached_instance['memcached']
   - Configures a single Memcached instance with 64MB memory, port 11211, and 1024 max connections
   - Resources: memcached_instance (1)

3. **redisio::default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb`):
   - Updates apt repositories
   - Includes prerequisite installation recipes
   - Includes Redis installation, configuration, and service management recipes
   - Resources: apt_update (1), include_recipe (multiple)

4. **redisio::_install_prereqs** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb`):
   - Installs prerequisite packages for Redis
   - Resources: package (multiple), build_essential (1)

5. **redisio::install** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb`):
   - Installs Redis either from package or source based on configuration
   - If using package: Installs redis-server package
   - If using source: Builds Redis from source
   - Resources: package (1) or redisio_install (1), build_essential (1)

6. **redisio::ulimit** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb`):
   - Configures ulimit settings for Redis
   - On Debian systems: Configures PAM settings
   - Resources: template (1), cookbook_file (1), user_ulimit (conditional)

7. **redisio::disable_os_default** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb`):
   - Disables default OS Redis service if present
   - Resources: service (1) with stop and disable actions

8. **redisio::configure** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb`):
   - Uses custom resource: redisio_configure['redis-servers']
   - Configures Redis server instances based on attributes
   - Sets up service management based on init system (systemd, upstart, initd, or rcinit)
   - Resources: redisio_configure (1), service (1 per Redis instance)

9. **ruby_block[fix_redis_config]** (`cookbooks/cache/recipes/default.rb`):
   - Modifies Redis configuration file at /etc/redis/6379.conf
   - Removes specific replication-related settings:
     - replica-serve-stale-data
     - replica-read-only
     - repl-ping-replica-period
     - client-output-buffer-limit
     - replica-priority
   - Resources: ruby_block (1)

10. **redisio::enable** (`/workspace/source/migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb`):
    - Enables and starts Redis services
    - Iterations: Runs for the Redis server on port 6379
    - Uses appropriate service name based on init system (redis@6379 for systemd, redis6379 otherwise)
    - Resources: service (1) with start and enable actions

## Dependencies

**External cookbook dependencies**:
- memcached
- redisio

**System package dependencies**:
- memcached
- redis-server (if using package installation)
- build-essential (if building Redis from source)

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

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: `cookbooks/cache/recipes/default.rb`
- **Current storage**: hardcoded
- **Usage context**: Redis authentication password used to secure Redis instance

## Checks for the Migration

**Files to verify**:
- /etc/redis/6379.conf
- /var/log/redis/
- /etc/memcached.conf (or distribution-specific location)
- /var/run/redis/redis_6379.pid
- /var/lib/redis/

**Service endpoints to check**:
- Ports listening: 11211 (Memcached TCP/UDP), 6379 (Redis)
- Unix sockets: None explicitly configured
- Network interfaces: 0.0.0.0 (Memcached), Redis default (typically 127.0.0.1)

**Templates rendered**:
- redis.conf.erb → /etc/redis/6379.conf (1 instance)
- redis@.service.erb or redis.init.erb → appropriate service file based on init system (1 instance)

## Pre-flight checks:

```bash
# Memcached checks
systemctl status memcached
ps aux | grep memcached
netstat -tulpn | grep 11211
ss -tulpn | grep 11211
echo "stats" | nc localhost 11211
memcached-tool localhost:11211 stats

# Redis checks
systemctl status redis@6379 || service redis6379 status
ps aux | grep redis
netstat -tulpn | grep 6379
ss -tulpn | grep 6379

# Redis authentication check
redis-cli -h localhost -p 6379 ping  # Should fail without password
redis-cli -h localhost -p 6379 -a redis_secure_password_123 ping  # Should return PONG
redis-cli -h localhost -p 6379 -a redis_secure_password_123 info server

# Redis configuration check
cat /etc/redis/6379.conf | grep -E 'port|requirepass'
cat /etc/redis/6379.conf | grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority'  # Should not find these lines

# Memcached configuration check
cat /etc/memcached.conf || cat /etc/sysconfig/memcached  # Depends on distribution
ps aux | grep memcached | grep -E 'memory|connections'  # Should show 64m and 1024

# Log files
ls -la /var/log/redis/
tail -f /var/log/redis/*.log
tail -f /var/log/memcached.log  # Location may vary by distribution

# Resource usage
free -m | grep Mem
redis-cli -h localhost -p 6379 -a redis_secure_password_123 info memory
```