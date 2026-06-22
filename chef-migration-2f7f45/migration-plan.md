# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI Python application with PostgreSQL. The migration to Ansible will involve converting Chef cookbooks, recipes, templates, and attributes to Ansible roles, playbooks, templates, and variables. The complexity is moderate with an estimated timeline of 3-4 weeks for complete migration.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and custom configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security headers, fail2ban integration, UFW firewall configuration

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration, log directory management

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies (both local and external from Chef Supermarket)
- `Policyfile.rb`: Defines the Chef policy with run list and cookbook dependencies
- `solo.rb`: Chef Solo configuration file specifying cookbook paths and log settings
- `solo.json`: Node attributes and run list for Chef Solo
- `Vagrantfile`: Defines the development VM using Fedora 42 with port forwarding and resource allocation
- `vagrant-provision.sh`: Bash script to provision the Vagrant VM with Chef

### Target Details

- **Operating System**: Fedora 42 (based on Vagrantfile) with support for Ubuntu 18.04+ and CentOS 7+ (based on cookbook metadata)
- **Virtual Machine Technology**: Libvirt (based on Vagrantfile provider configuration)
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or collection (e.g., `ansible.posix.nginx`)
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible Redis role or direct package installation and configuration

### Security Considerations

- **SSL/TLS Configuration**: Migrate the self-signed certificate generation logic to Ansible's `openssl_certificate` module
- **Firewall Rules**: Convert UFW rules to Ansible's `ufw` module or `firewalld` module for Fedora
- **fail2ban Configuration**: Migrate fail2ban jail configuration to Ansible templates
- **SSH Hardening**: Preserve SSH security settings (disable root login, password authentication)
- **Vault/secrets management**:
  - Redis password in cache cookbook: `redis_secure_password_123` (hardcoded)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username `fastapi` with password `fastapi_password` (hardcoded)
  - SSL certificates and private keys stored in `/etc/ssl/certs` and `/etc/ssl/private`

### Technical Challenges

- **Multi-site Nginx Configuration**: The dynamic generation of multiple virtual hosts based on node attributes will need careful translation to Ansible variables and templates
- **SSL Certificate Management**: Self-signed certificate generation and management will need to be handled with Ansible's OpenSSL modules
- **Service Dependencies**: Ensuring proper ordering of service installation, configuration, and startup in Ansible
- **Idempotency**: Ensuring all operations remain idempotent, particularly the database user and database creation tasks

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for web services)
   - Start with basic Nginx installation and configuration
   - Add SSL certificate generation
   - Implement virtual host configuration
   - Add security hardening features

2. **cache** (low complexity, standalone services)
   - Implement Memcached configuration
   - Implement Redis with authentication

3. **fastapi-tutorial** (high complexity, application deployment)
   - Set up PostgreSQL database
   - Deploy Python application from Git
   - Configure virtual environment and dependencies
   - Set up systemd service

### Assumptions

1. The target environment will continue to be Fedora 42 or compatible Linux distributions
2. Self-signed certificates are acceptable for the migrated solution (production would likely use Let's Encrypt or other CA)
3. The same security hardening measures are required in the Ansible version
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The current hardcoded credentials will be replaced with Ansible Vault encrypted variables
6. The multi-site configuration pattern will be preserved with the same site names and document roots
7. The current directory structure in the target environment will be maintained