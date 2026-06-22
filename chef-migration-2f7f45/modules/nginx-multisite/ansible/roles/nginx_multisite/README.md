# Nginx Multisite Role

This Ansible role configures Nginx for hosting multiple websites with SSL support, security hardening, and performance optimization.

## Requirements

- Ansible 2.9 or higher
- Ubuntu 20.04 (Focal) or 22.04 (Jammy)
- Debian 10 (Buster) or 11 (Bullseye)

## Required Collections

This role requires the following Ansible collections:

```bash
ansible-galaxy collection install community.general
```

Or use the requirements.yml file:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Role Variables

### Main Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `nginx_sites` | List of websites to configure | `[]` |
| `ssl_certificate_path` | Path to SSL certificates | `/etc/ssl/certs` |
| `ssl_private_key_path` | Path to SSL private keys | `/etc/ssl/private` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `fail2ban_enabled` | Enable fail2ban | `true` |
| `fail2ban_bantime` | Ban time in seconds | `3600` |
| `fail2ban_findtime` | Time window in seconds | `600` |
| `fail2ban_maxretry` | Max number of retries | `3` |
| `ssh_disable_root` | Disable SSH root login | `true` |

## Example Playbook

```yaml
---
- hosts: webservers
  become: true
  vars:
    nginx_sites:
      - name: example.com
        document_root: /var/www/example.com
        ssl_enabled: true
      - name: test.com
        document_root: /var/www/test.com
        ssl_enabled: false
  roles:
    - nginx_multisite
```

## License

MIT

## Author Information

Your Name - your.email@example.com