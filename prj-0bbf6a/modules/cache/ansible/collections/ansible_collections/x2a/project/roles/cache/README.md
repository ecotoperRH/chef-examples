# cache

An Ansible role for deploying Memcached and a Redis instance on Linux hosts.

## Credentials

Provide `redis_password` through the AAP credential integration or Ansible Vault. The role validates the credential before configuring Redis and hides secret-bearing tasks by default.

## Main defaults

- `cache_memcached_port`: Memcached TCP port.
- `cache_memcached_memory`: Memcached memory in megabytes.
- `cache_redis_port`: Redis TCP port.
- `cache_redis_version`: Redis source version.
- `cache_secure_logging`: Controls secret task output suppression.
