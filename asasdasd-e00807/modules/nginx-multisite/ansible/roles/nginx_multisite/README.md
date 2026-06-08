# Nginx Multisite Role

This Ansible role installs and configures Nginx to serve multiple websites with optional SSL support.

## Requirements

- Ansible 2.9 or higher
- Ubuntu 18.04 or higher / Debian 10 or higher

## Role Variables

### Main Variables

```yaml
# SSL certificate paths
ssl_certificate_path: /etc/ssl/certs
ssl_private_key_path: /etc/ssl/private

# Nginx sites configuration
nginx_sites:
  example.com:
    document_root: /var/www/example.com
    ssl_enabled: true
  test.example.com:
    document_root: /var/www/test.example.com
    ssl_enabled: false

# Security settings
security:
  fail2ban:
    enabled: true
    bantime: 3600
    findtime: 600
    maxretry: 3
    maxretry_limit_req: 10
    maxretry_botsearch: 2
```

## Dependencies

None.

## Example Playbook

```yaml
- name: Deploy Nginx with Multiple Sites
  hosts: webservers
  become: yes
  vars:
    ssl_certificate_path: /etc/ssl/certs
    ssl_private_key_path: /etc/ssl/private
    
    nginx_sites:
      example.com:
        document_root: /var/www/example.com
        ssl_enabled: true
      test.example.com:
        document_root: /var/www/test.example.com
        ssl_enabled: false
    
    security:
      fail2ban:
        enabled: true
        bantime: 3600
        findtime: 600
        maxretry: 3
        maxretry_limit_req: 10
        maxretry_botsearch: 2
  
  roles:
    - nginx_multisite
```

## License

MIT

## Author Information

Created by Your Name