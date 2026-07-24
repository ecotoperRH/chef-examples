# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure for deploying a multi-site Nginx web server with FastAPI application backend and caching services (Redis and Memcached). The migration to Ansible is estimated to be of moderate complexity with approximately 2-3 weeks of effort for a skilled Ansible developer.

The repository consists of three Chef cookbooks with clear responsibilities and dependencies on community cookbooks. The migration will require converting Chef recipes to Ansible roles and tasks, with special attention to security configurations and secrets management.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
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
    - Key Features: Python virtual environment setup, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node configuration with attributes for Nginx sites, SSL paths, and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines the development VM using Fedora 42, with port forwarding and network configuration
- `vagrant-provision.sh`: Shell script to provision the VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (from Vagrantfile), with support for Ubuntu 18.04+ and CentOS 7+ (from cookbook metadata)
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be targeting on-premises or local development

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or nginx_core module
- **memcached (~> 6.0)**: Replace with Ansible memcached role or memcached module
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or community.general.redis module
- **ssl_certificate (~> 2.1)**: Replace with Ansible openssl_* modules for certificate management

### Security Considerations

- **SSL Certificate Management**: The current implementation generates self-signed certificates. Migration should use Ansible's `openssl_certificate` module with similar parameters.
- **Firewall Configuration**: UFW rules need to be migrated to Ansible's `ufw` module or `firewalld` module for Fedora.
- **fail2ban Configuration**: Migrate fail2ban configuration to Ansible's `template` module with similar jail configurations.
- **SSH Hardening**: Current implementation disables root login and password authentication. Migrate to Ansible's `lineinfile` or `template` module for SSH configuration.
- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123" (hardcoded)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username "fastapi" with password "fastapi_password" (hardcoded)
  - Environment variables in .env file for FastAPI application (hardcoded)

### Technical Challenges

- **Multi-site Nginx Configuration**: The current implementation uses Chef attributes and templates to configure multiple Nginx sites. Ansible will need to use loops with the `template` module to achieve similar functionality.
- **Service Dependencies**: The FastAPI application depends on PostgreSQL. Ansible handlers and meta dependencies will need to be configured to ensure proper service ordering.
- **SSL Certificate Generation**: The current implementation uses inline shell commands for certificate generation. This should be replaced with Ansible's `openssl_certificate` module.
- **Redis Configuration Hack**: The cache cookbook includes a ruby_block to modify Redis configuration. This will need to be replaced with Ansible's `lineinfile` or `template` module.

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for other services)
   - Start with basic Nginx installation and configuration
   - Add SSL certificate generation
   - Configure multi-site setup
   - Implement security hardening

2. **cache** (low complexity, independent service)
   - Configure Memcached
   - Set up Redis with authentication
   - Ensure proper service management

3. **fastapi-tutorial** (high complexity, depends on PostgreSQL)
   - Set up PostgreSQL database
   - Deploy FastAPI application
   - Configure systemd service
   - Set up environment variables

### Assumptions

1. The target environment will continue to be Fedora 42 or similar Linux distribution.
2. Self-signed certificates are acceptable for the migration (production environments would likely use Let's Encrypt or other CA).
3. The hardcoded passwords in the Chef recipes will be replaced with Ansible Vault encrypted variables.
4. The FastAPI application source will continue to be pulled from the same GitHub repository.
5. The Nginx site configurations will remain the same (test.cluster.local, ci.cluster.local, status.cluster.local).
6. The current security hardening measures (fail2ban, UFW, SSH hardening) are required in the Ansible implementation.
7. The Vagrant development environment will be maintained but updated to use Ansible provisioning instead of Chef.