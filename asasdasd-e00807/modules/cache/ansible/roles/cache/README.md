# Cache Role

This Ansible role installs and configures caching services:

- Memcached: A distributed memory object caching system
- Redis: An in-memory data structure store

## Requirements

- Ansible 2.9 or higher
- For Redis, the `eloy.redis` collection is required

## Role Variables

### Memcached Configuration

```yaml
memcached_enabled: true
memcached_service_name: memcached
memcached_packages:
  Debian: memcached
  RedHat: memcached
memcached_port: 11211
memcached_memory: 64
memcached_connections: 1024
memcached_listen_address: 127.0.0.1
```

### Redis Configuration

```yaml
redis_enabled: true
redis_user: redis
redis_group: redis
redis_port: 6379
redis_password: "{{ lookup('env', 'REDIS_PASSWORD') | default('') }}"
redis_databases: 16
redis_datadir: /var/lib/redis
redis_logdir: /var/log/redis
redis_logfile: "{{ redis_logdir }}/redis-server.log"
```

## Dependencies

- `eloy.redis.redis` role for Redis installation and configuration

## Example Playbook

```yaml
- hosts: cache_servers
  vars:
    memcached_memory: 128
    redis_port: 6380
    redis_password: "{{ vault_redis_password }}"
  roles:
    - role: x2a.cache
```

## License

Apache-2.0