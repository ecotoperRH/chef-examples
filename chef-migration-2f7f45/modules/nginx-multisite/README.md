# Nginx Multisite Ansible Project

This project provides Ansible automation for deploying and configuring Nginx to host multiple websites with SSL support, security hardening, and performance optimization.

## Project Structure

```
.
├── ansible/
│   ├── roles/
│   │   └── nginx_multisite/
│   │       ├── defaults/
│   │       ├── handlers/
│   │       ├── meta/
│   │       ├── tasks/
│   │       ├── templates/
│   │       └── README.md
│   ├── ansible.cfg
│   ├── inventory.ini
│   ├── nginx_multisite.yml
│   └── requirements.yml
└── README.md
```

## Prerequisites

1. Ansible 2.9 or higher
2. Target servers running Ubuntu 20.04/22.04 or Debian 10/11
3. SSH access to target servers

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/nginx-multisite-ansible.git
   cd nginx-multisite-ansible
   ```

2. Install required Ansible collections:
   ```bash
   ansible-galaxy collection install -r ansible/requirements.yml
   ```

3. Update the inventory file with your server information:
   ```bash
   vim ansible/inventory.ini
   ```

4. Update the playbook variables as needed:
   ```bash
   vim ansible/nginx_multisite.yml
   ```

## Usage

Run the playbook:

```bash
cd ansible
ansible-playbook nginx_multisite.yml
```

## Configuration

Edit the `nginx_multisite.yml` playbook to configure your websites:

```yaml
nginx_sites:
  - name: example.com
    document_root: /var/www/example.com
    ssl_enabled: true
  - name: test.com
    document_root: /var/www/test.com
    ssl_enabled: false
```

## Security Features

- Fail2ban for intrusion prevention
- UFW firewall configuration
- SSH hardening
- SSL/TLS configuration
- Security headers

## License

MIT

## Author

Your Name - your.email@example.com