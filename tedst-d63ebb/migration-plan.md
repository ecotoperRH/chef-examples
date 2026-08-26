# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx web server setup with FastAPI application backend and caching services (Redis and Memcached). The migration scope is moderate, involving 3 custom cookbooks with dependencies on 4 external cookbooks. Based on the complexity and interdependencies, we estimate a 2-3 week timeline for complete migration, with the most complex components being the Nginx configuration with SSL and the FastAPI application deployment.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site virtual hosts, SSL configuration, security hardening (fail2ban, UFW)

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment, Git repository deployment, PostgreSQL database setup, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `solo.json`: Configuration data for Chef solo, contains site configurations and security settings
- `solo.rb`: Chef solo configuration file
- `Vagrantfile`: Defines the development environment using Vagrant with Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ (from cookbook metadata)
- **Virtual Machine Technology**: Libvirt (specified in Vagrantfile)
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role (e.g., geerlingguy.nginx)
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management modules (openssl_certificate, openssl_csr, openssl_privatekey)
- **memcached (~> 6.0)**: Replace with Ansible memcached role (e.g., geerlingguy.memcached)
- **redisio (~> 7.2.4)**: Replace with Ansible redis role (e.g., geerlingguy.redis)

### Security Considerations

- **SSL Configuration**: Migration must preserve SSL certificate paths and configurations for multiple sites
  - Current paths: /etc/ssl/certs (certificates), /etc/ssl/private (private keys)
  - Approach: Use Ansible's openssl modules to manage certificates

- **Firewall Configuration**: UFW firewall is enabled in the security configuration
  - Approach: Use Ansible's ufw module to configure firewall rules

- **Fail2ban Integration**: Fail2ban is enabled for intrusion prevention
  - Approach: Use Ansible's package and template modules to configure fail2ban

- **SSH Hardening**: SSH configuration disables root login and password authentication
  - Approach: Use Ansible's template module to configure SSH daemon

- **Vault/secrets management**:
  - Redis password in plaintext in the cache cookbook (redis_secure_password_123)
  - PostgreSQL credentials in plaintext in the FastAPI cookbook (fastapi/fastapi_password)
  - Approach: Move all credentials to Ansible Vault

### Technical Challenges

- **Multi-site Nginx Configuration**: The current setup dynamically creates Nginx configurations for multiple sites
  - Mitigation: Create Ansible templates that can generate site configurations from variables

- **Redis Configuration Patching**: The cache cookbook uses a ruby_block to patch Redis configuration
  - Mitigation: Create a proper Redis configuration template in Ansible that doesn't require patching

- **FastAPI Application Deployment**: The current setup clones a Git repository and sets up a Python environment
  - Mitigation: Use Ansible's git, pip, and template modules to replicate this functionality

- **PostgreSQL Database Setup**: The current setup uses inline SQL commands to create database and users
  - Mitigation: Use Ansible's postgresql modules for cleaner database management

### Migration Order

1. **cache cookbook** (low risk, standalone functionality)
   - Implement Memcached configuration
   - Implement Redis configuration with proper templates

2. **nginx-multisite cookbook** (moderate complexity)
   - Implement base Nginx installation and configuration
   - Implement SSL certificate management
   - Implement site configuration templates
   - Implement security hardening (fail2ban, UFW)

3. **fastapi-tutorial cookbook** (high complexity, dependencies)
   - Implement PostgreSQL database setup
   - Implement Python environment setup
   - Implement application deployment from Git
   - Implement systemd service configuration

### Assumptions

1. The target environment will continue to be Fedora-based systems, with potential for Ubuntu and CentOS as indicated in cookbook metadata
2. The current directory structure with separate modules will be maintained in the Ansible roles
3. The Vagrant development environment will be preserved but updated to use Ansible provisioning
4. SSL certificates are self-signed for development (based on Vagrant script comments)
5. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
6. No custom Chef resources are being used that would require special handling in Ansible
7. The current security configurations (fail2ban, UFW, SSH hardening) are sufficient and should be maintained
8. Redis and Memcached configurations don't have specific tuning requirements beyond what's visible in the code