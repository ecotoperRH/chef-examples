# Nginx Multisite Role

This Ansible role installs and configures Nginx with support for multiple sites and security hardening.

## Requirements

- Ansible 2.9 or higher
- Debian/Ubuntu Linux distribution

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Nginx package and service settings
nginx_package_name: nginx
nginx_service_name: nginx
nginx_user: www-data
nginx_group: www-data

# Default site configuration
default_server_name: example.com
default_document_root: /var/www/html
ssl_enabled: false
cert_file: /etc/ssl/certs/ssl-cert-snakeoil.pem
key_file: /etc/ssl/private/ssl-cert-snakeoil.key

# Security settings
enable_fail2ban: true
enable_firewall: true
allowed_ports:
  - 22
  - 80
  - 443

# Nginx performance settings
worker_processes: auto
worker_connections: 768
keepalive_timeout: 65

# Sites configuration
nginx_sites:
  - server_name: "{{ default_server_name }}"
    document_root: "{{ default_document_root }}"
    ssl_enabled: "{{ ssl_enabled }}"
    cert_file: "{{ cert_file }}"
    key_file: "{{ key_file }}"
```

## Dependencies

None.

## Example Playbook

```yaml
- hosts: webservers
  vars:
    nginx_sites:
      - server_name: "example.com"
        document_root: "/var/www/example"
        ssl_enabled: true
        cert_file: "/etc/letsencrypt/live/example.com/fullchain.pem"
        key_file: "/etc/letsencrypt/live/example.com/privkey.pem"
      - server_name: "test.example.com"
        document_root: "/var/www/test"
        ssl_enabled: false
  roles:
    - nginx_multisite
```

## License

MIT

## Author Information

Ansible Automation Team