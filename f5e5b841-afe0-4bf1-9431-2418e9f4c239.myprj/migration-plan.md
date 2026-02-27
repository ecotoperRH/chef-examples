# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure for deploying a multi-site Nginx web server with SSL, caching services (Memcached and Redis), and a FastAPI application with PostgreSQL. The migration to Ansible is estimated to be of medium complexity, requiring approximately 3-4 weeks of effort for a complete migration with testing.

The repository consists of 3 primary cookbooks with clear responsibilities and minimal cross-dependencies, making this a good candidate for incremental migration. The Chef cookbooks follow standard patterns and use common resources that have direct equivalents in Ansible.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and self-signed certificate generation
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup, security hardening (fail2ban, ufw, sysctl)

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Git-based deployment, Python virtual environment, PostgreSQL database setup, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file listing cookbook dependencies (nginx, memcached, redisio, ssl_certificate)
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node attributes for Chef Solo, containing site configurations and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Vagrant configuration for local development using Fedora 42
- `vagrant-provision.sh`: Provisioning script for Vagrant VM setup

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary), with support for Ubuntu 18.04+ and CentOS 7+ mentioned in cookbook metadata
- **Virtual Machine Technology**: Libvirt (specified in Vagrantfile)
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud VMs

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or nginx_core modules
- **memcached (~> 6.0)**: Replace with Ansible memcached role or package/service modules
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or package/service modules
- **ssl_certificate (~> 2.1)**: Replace with Ansible openssl_* modules for certificate management

### Security Considerations

- **fail2ban configuration**: Migrate using Ansible fail2ban modules or templates
- **ufw firewall rules**: Replace with Ansible ufw module or firewalld for RHEL-based systems
- **SSH hardening**: Migrate using Ansible ssh_config module or templates
- **sysctl security settings**: Use Ansible sysctl module
- **Redis authentication**: Ensure password is stored securely in Ansible Vault
- **PostgreSQL credentials**: Store database credentials in Ansible Vault
- **Self-signed certificates**: Use Ansible openssl_* modules for certificate generation

### Technical Challenges

- **Multi-site Nginx configuration**: Requires careful templating in Ansible to maintain the same flexibility
- **Redis configuration hack**: The Chef cookbook uses a ruby_block to modify Redis config files; this will need a custom approach in Ansible
- **Service dependencies**: Ensuring proper ordering of service deployments (PostgreSQL before FastAPI, etc.)
- **Platform compatibility**: Supporting both Debian/Ubuntu and RHEL/CentOS/Fedora with the same playbooks

### Migration Order

1. **nginx-multisite cookbook** (moderate complexity, foundation for web services)
   - Start with basic Nginx installation and configuration
   - Add SSL certificate generation
   - Implement security hardening (fail2ban, ufw)
   - Configure virtual hosts

2. **cache cookbook** (low complexity, independent service)
   - Implement Memcached configuration
   - Implement Redis with authentication

3. **fastapi-tutorial cookbook** (high complexity, depends on PostgreSQL)
   - Set up PostgreSQL database
   - Deploy FastAPI application
   - Configure systemd service

### Assumptions

1. The target environment will continue to be Fedora-based, with potential for Ubuntu/CentOS deployment
2. Self-signed certificates are acceptable for development; production would require proper certificates
3. The current security configurations (fail2ban, ufw, SSH hardening) are sufficient and should be maintained
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. Redis and Memcached configurations don't require clustering or advanced features
6. The current directory structure in `/opt/server/` for website content and `/opt/fastapi-tutorial/` for the application will be maintained