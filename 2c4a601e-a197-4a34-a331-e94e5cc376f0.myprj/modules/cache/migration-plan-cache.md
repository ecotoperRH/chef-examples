# Migration Plan: cache

**TLDR**: This cookbook configures two caching services: Memcached and Redis. It sets up Redis with authentication and performs some configuration file modifications. The cookbook relies heavily on external dependencies for the actual service installation and configuration.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **Redis**:
  - Location/Path: /etc/redis/6379.conf
  - Port/Socket: 6379
  - Key Config: Authentication enabled with password, some replication settings disabled via ruby_block

- **Memcached**:
  - Location/Path: Not specified in this cookbook (handled by dependency)
  - Port/Socket: Not specified in this cookbook (handled by dependency)
  - Key Config: Not specified in this cookbook (handled by dependency)

## File Structure

```
cookbooks/cache/recipes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes the memcached recipe from an external cookbook
   - Sets Redis configuration attributes:
     - Port: 6379
     - Password: redis_secure_password_123
     - Disables replicaservestaledata
   - Creates Redis log directory at /var/log/redis
     - Owner: redis
     - Group: redis
     - Mode: 0755
     - Recursive: true
   - Includes the redisio recipe from an external cookbook
   - Executes a ruby_block to modify Redis configuration:
     - Removes specific replication and client buffer settings from /etc/redis/6379.conf
     - Specifically removes lines containing:
       - replica-serve-stale-data
       - replica-read-only
       - repl-ping-replica-period
       - client-output-buffer-limit
       - replica-priority
   - Includes the redisio::enable recipe from an external cookbook
   - Resources: include_recipe (3), directory (1), ruby_block (1)

## Dependencies

**External cookbook dependencies**:
- memcached (~> 6.0)
- redisio

**System package dependencies**:
- Redis server (installed by redisio cookbook)
- Memcached server (installed by memcached cookbook)

**Service dependencies**:
- redis service (managed by redisio cookbook)
- memcached service (managed by memcached cookbook)

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
  - **Provider**: Hardcoded
  - **URL**: N/A
  - **Path**: N/A

### Redis Authentication Password

- **Variable(s)**: `node.default['redisio']['servers'][0]['requirepass']`
- **Source file(s)**: cookbooks/cache/recipes/default.rb
- **Current storage**: hardcoded
- **Usage context**: Redis server authentication password

## Checks for the Migration

**Files to verify**:
- /etc/redis/6379.conf
- /var/log/redis (directory)
- Memcached configuration files (location depends on memcached cookbook)

**Service endpoints to check**:
- Ports listening: 6379 (Redis)
- Memcached port (typically 11211, but not specified in this cookbook)

**Templates rendered**:
- No templates are directly rendered by this cookbook

## Pre-flight checks:
```bash
# Redis Service status
systemctl status redis-server
systemctl status redis@6379
ps aux | grep redis

# Redis connectivity
redis-cli -h localhost -p 6379 ping
redis-cli -h localhost -p 6379 -a redis_secure_password_123 ping
redis-cli -h localhost -p 6379 -a redis_secure_password_123 info

# Redis configuration validation
cat /etc/redis/6379.conf | grep requirepass
cat /etc/redis/6379.conf | grep -v "replica-serve-stale-data"
cat /etc/redis/6379.conf | grep -v "replica-read-only"
cat /etc/redis/6379.conf | grep -v "repl-ping-replica-period"
cat /etc/redis/6379.conf | grep -v "client-output-buffer-limit"
cat /etc/redis/6379.conf | grep -v "replica-priority"

# Redis log directory
ls -la /var/log/redis
stat -c "%U %G %a" /var/log/redis

# Redis logs
tail -f /var/log/redis/redis_6379.log

# Redis network listening
netstat -tulpn | grep 6379
ss -tlnp | grep redis
lsof -i :6379

# Memcached Service status
systemctl status memcached
ps aux | grep memcached

# Memcached connectivity
echo stats | nc localhost 11211
memcached-tool localhost:11211 stats

# Memcached network listening
netstat -tulpn | grep memcached
ss -tlnp | grep memcached
lsof -i :11211

# Memory usage
free -m
ps aux | grep redis | awk '{print $2}' | xargs -I {} cat /proc/{}/status | grep VmRSS
ps aux | grep memcached | awk '{print $2}' | xargs -I {} cat /proc/{}/status | grep VmRSS
```