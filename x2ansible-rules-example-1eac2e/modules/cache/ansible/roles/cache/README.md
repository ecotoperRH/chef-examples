# Cache Role

This Ansible role installs and configures cache services:
- Memcached
- Redis

## Requirements

- Ansible 2.9 or higher
- Linux distribution (RHEL/CentOS 7/8, Ubuntu 18.04/20.04, Debian 10/11)

## Role Variables

### Memcached Configuration

```yaml
# Memcached configuration
memcached_memory: 64                # Memory size in MB
memcached_port: 11211               # Memcached port
memcached_max_connections: 1024     # Maximum number of connections
memcached_listen_address: 0.0.0.0   # Listen address
memcached_log_file: /var/log/memcached.log  # Log file path
```

### Redis Configuration

```yaml
# Redis configuration
redis_port: 6379                    # Redis port
redis_bind: 0.0.0.0                 # Bind address
redis_requirepass: "{{ redis_password | default('redis_secure_password_123') }}"  # Redis password
redis_maxmemory: "64mb"             # Maximum memory
redis_dir: "/var/lib/redis"         # Redis data directory
redis_logfile: "/var/log/redis/redis-server.log"  # Log file path
redis_log_dir: "/var/log/redis"     # Log directory
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: cache_servers
  roles:
    - role: cache
      vars:
        memcached_memory: 128
        redis_maxmemory: "128mb"
```

## License

Apache-2.0

## Author Information

Ansible Migration Team