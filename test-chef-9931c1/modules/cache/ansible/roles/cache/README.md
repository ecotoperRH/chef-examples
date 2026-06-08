# Cache Role

This role installs and configures caching services for your application.

## Supported Cache Systems

- **Memcached**: In-memory key-value store for small chunks of arbitrary data
- **Redis**: Advanced key-value store with optional persistence

## Requirements

- Ansible 2.9 or higher
- Ubuntu 18.04 or higher / RHEL/CentOS 7 or higher

## Role Variables

### Memcached Configuration

```yaml
# Memcached memory limit in MB
memcached_memory: 64

# Memcached connection settings
memcached_listen_ip: 127.0.0.1
memcached_port: 11211

# Memcached user to run as
memcached_user: memcache
```

### Redis Configuration

```yaml
# Whether to use the Redis collection or built-in tasks
redis_use_collection: false

# Redis service name
redis_service_name: redis-server

# Redis connection settings
redis_bind_interface: 127.0.0.1
redis_port: 6379

# Redis memory settings
redis_maxmemory: 256mb
redis_maxmemory_policy: allkeys-lru

# Redis persistence settings
redis_save_to_disk: true
redis_save_periods:
  - [900, 1]
  - [300, 10]
  - [60, 10000]
```

## Dependencies

When `redis_use_collection` is set to `true`, this role depends on:
- `eloy.redis` collection

## Example Playbook

```yaml
- hosts: webservers
  roles:
    - role: cache
      vars:
        memcached_memory: 128
        redis_maxmemory: 512mb
        redis_maxmemory_policy: volatile-lru
```

## License

MIT

## Author Information

Created for Chef to Ansible migration project.