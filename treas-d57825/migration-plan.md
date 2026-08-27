# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services (Redis and Memcached) and a FastAPI application. The migration to Ansible is estimated to be of medium complexity, with approximately 3-4 weeks of effort required for a complete migration. The repository is well-structured with clear separation of concerns between cookbooks, making it suitable for incremental migration.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and site-specific configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening with fail2ban and UFW

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies including external cookbooks from Chef Supermarket (nginx, memcached, redisio)
- `Policyfile.rb`: Defines the run list and cookbook dependencies for Chef Policyfile workflow
- `solo.json`: Contains node attributes for Nginx sites, SSL configuration, and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for local development and testing
- `vagrant-provision.sh`: Shell script to provision the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ based on cookbook metadata
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or nginx_core modules
- **memcached (~> 6.0)**: Replace with Ansible memcached role or package installation tasks
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or package installation tasks
- **ssl_certificate (~> 2.1)**: Replace with Ansible openssl modules for certificate generation

### Security Considerations

- **Firewall Configuration**: The Chef cookbook configures UFW. Migration should use Ansible's `ufw` module to maintain identical firewall rules.
- **Fail2ban Setup**: The Chef cookbook configures fail2ban. Migration should use Ansible to install and configure fail2ban with identical jail settings.
- **SSH Hardening**: The Chef cookbook disables root login and password authentication. Migration should ensure these security settings are maintained.
- **SSL Certificate Management**: Self-signed certificates are generated for each site. Migration should maintain this functionality using Ansible's `openssl_*` modules.
- **Vault/secrets management**: 
  - Redis password is hardcoded in the cache cookbook (`redis_secure_password_123`)
  - PostgreSQL credentials are hardcoded in the fastapi-tutorial cookbook (`fastapi:fastapi_password`)
  - No external vault integration is present in the current implementation

### Technical Challenges

- **Multi-site Configuration**: The Nginx configuration dynamically creates virtual hosts based on node attributes. Ansible implementation will need to maintain this flexibility.
- **SSL Certificate Generation**: The current implementation generates self-signed certificates for each site. Ansible will need to replicate this behavior with proper file permissions.
- **Service Dependencies**: The FastAPI application depends on PostgreSQL. Migration must maintain proper service ordering and dependencies.
- **Configuration Templates**: Multiple Nginx configuration templates will need to be converted to Ansible templates while maintaining variable substitution.

### Migration Order

1. **cache cookbook** (low complexity): Simple Redis and Memcached configuration with minimal dependencies
2. **nginx-multisite cookbook** (medium complexity): Core infrastructure component with security configurations
3. **fastapi-tutorial cookbook** (medium complexity): Application deployment with database dependencies

### Assumptions

1. The target environment will continue to be Fedora 42 or compatible Linux distributions.
2. The current security configurations (fail2ban, UFW, SSH hardening) are required in the Ansible implementation.
3. Self-signed SSL certificates are acceptable for the target environment (no Let's Encrypt or external CA integration required).
4. The current hardcoded credentials will be maintained in the Ansible implementation, though they should be moved to Ansible Vault.
5. The Vagrant development environment will be maintained for testing the Ansible implementation.
6. The FastAPI application source will continue to be pulled from the GitHub repository specified in the cookbook.