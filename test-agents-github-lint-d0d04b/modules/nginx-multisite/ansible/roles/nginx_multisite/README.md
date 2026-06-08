# Nginx Multisite Role

This Ansible role installs and configures Nginx for hosting multiple websites with optional SSL support.

## Requirements

- Debian/Ubuntu based system
- Ansible 2.9 or higher

## Role Variables

```yaml
# Security settings
security_ssh_disable_root: true
security_ssh_password_auth: false

# SSL paths
nginx_ssl_certificate_path: /etc/ssl/certs
nginx_ssl_private_key_path: /etc/ssl/private

# Site configuration
nginx_sites:
  example.com:
    document_root: /var/www/example.com
    ssl_enabled: true
  test.example.com:
    document_root: /var/www/test.example.com
    ssl_enabled: false
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: webservers
  roles:
    - role: nginx_multisite
      vars:
        nginx_sites:
          mysite.example.com:
            document_root: /var/www/mysite
            ssl_enabled: true
          blog.example.com:
            document_root: /var/www/blog
            ssl_enabled: false
```

## License

MIT

## Author Information

Created by Ansible Migration Assistant