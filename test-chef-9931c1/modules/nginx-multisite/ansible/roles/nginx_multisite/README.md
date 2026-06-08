# Nginx Multisite Role

This Ansible role configures Nginx with multiple virtual hosts and security settings.

## Requirements

- Ansible 2.9 or higher
- Ubuntu 18.04+ or Debian 10+

## Role Variables

```yaml
# Sites configuration
nginx_sites:
  'test.cluster.local':
    document_root: '/opt/server/test'
    ssl_enabled: true
  'ci.cluster.local':
    document_root: '/opt/server/ci'
    ssl_enabled: true
  'status.cluster.local':
    document_root: '/opt/server/status'
    ssl_enabled: true

# SSL paths
nginx_ssl_certificate_path: '/etc/ssl/certs'
nginx_ssl_private_key_path: '/etc/ssl/private'

# Security settings
security_fail2ban_enabled: true
security_ufw_enabled: true
security_ssh_disable_root: true
security_ssh_password_auth: false
```

## Example Playbook

```yaml
- hosts: webservers
  roles:
    - role: nginx_multisite
      vars:
        nginx_sites:
          'example.com':
            document_root: '/var/www/example'
            ssl_enabled: true
          'blog.example.com':
            document_root: '/var/www/blog'
            ssl_enabled: true
```

## License

MIT

## Author Information

Created by the Ansible Migration Team