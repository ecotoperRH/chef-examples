# Migration Plan: cache

**TLDR**: This cookbook configures two caching services: Redis and Memcached. It sets up a single Redis instance with authentication and includes Memcached with default configuration. The cookbook primarily relies on external dependencies for the actual implementation.

## Service Type and Instances

**Service Type**: Cache

**Configured Instances**:

- **Redis**:
  - Location/Path: /etc/redis/6379.conf
  - Port/Socket: 6379
  - Key Config: Authentication enabled with password 'redis_secure_password_123'

- **Memcached**:
  - Location/Path: Default (likely /etc/memcached.conf)
  - Port/Socket: Default (likely 11211)
  - Key Config: Uses default configuration from memcached cookbook

## File Structure

```
cookbooks/cache/recipes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/cache/recipes/default.rb`):
   - Includes memcached recipe from external cookbook
   - Sets Redis configuration with authentication:
     - Sets port to 6379
     - Sets password to 'redis_secure_password_123'
     - Disables replicaservestaledata
   - Creates Redis log directory at /var/log/redis
     - Owner: redis
     - Group: redis
     - Mode: 0755
     - Recursive: true
   - Includes redisio recipe from external cookbook
   - Executes ruby_block to modify Redis configuration:
     - Removes specific replication-related configuration lines from /etc/redis/6379.conf:
       - replica-serve-stale-data
       - replica-read-only
       - repl-ping-replica-period
       - client-output-buffer-limit
       - replica-priority
   - Includes redisio::enable recipe from external cookbook
   - Resources: include_recipe (3), directory (1), ruby_block (1)

## Dependencies

**External cookbook dependencies**:
- memcached (~> 6.0)
- redisio

**System package dependencies**:
- Redis server (installed by redisio cookbook)
- Memcached server (installed by memcached cookbook)

**Service dependencies**:
- redis (likely managed by redisio::enable)
- memcached (likely managed by memcached cookbook)

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
- **Usage context**: Redis server authentication password, used to secure Redis instance

## Checks for the Migration

**Files to verify**:
- /etc/redis/6379.conf
- /var/log/redis/ (directory)
- /etc/memcached.conf (likely path)

**Service endpoints to check**:
- Ports listening:
  - Redis: 6379
  - Memcached: 11211 (default)
- Unix sockets: None specified
- Network interfaces: Default (likely 127.0.0.1)

**Templates rendered**:
No templates are directly rendered by this cookbook. Templates are likely rendered by the dependent cookbooks (memcached and redisio).

## Pre-flight checks:

```bash
# Redis Service status
systemctl status redis-server
systemctl status redis@6379
ps aux | grep redis

# Redis connectivity
redis-cli -p 6379 ping
redis-cli -p 6379 -a 'redis_secure_password_123' ping
redis-cli -p 6379 -a 'redis_secure_password_123' info server

# Redis configuration validation
cat /etc/redis/6379.conf | grep -E 'port|requirepass'
cat /etc/redis/6379.conf | grep -E 'replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority'

# Redis logs
tail -f /var/log/redis/redis-server.log
tail -f /var/log/redis/redis_6379.log

# Redis network listening
netstat -tulpn | grep 6379
ss -tlnp | grep redis
lsof -i :6379

# Redis data directories
ls -lah /var/lib/redis/
df -h /var/lib/redis/

# Memcached Service status
systemctl status memcached
ps aux | grep memcached

# Memcached connectivity
echo stats | nc localhost 11211
memcached-tool localhost:11211 stats

# Memcached configuration validation
cat /etc/memcached.conf

# Memcached logs
tail -f /var/log/memcached.log
journalctl -u memcached -f

# Memcached network listening
netstat -tulpn | grep 11211
ss -tlnp | grep memcached
lsof -i :11211

# Memory usage checks
free -m
ps aux | grep redis | awk '{print $2}' | xargs -I {} cat /proc/{}/status | grep VmRSS
ps aux | grep memcached | awk '{print $2}' | xargs -I {} cat /proc/{}/status | grep VmRSS
```