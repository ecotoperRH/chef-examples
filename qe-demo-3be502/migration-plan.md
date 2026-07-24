# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup focused on deploying web applications with Nginx, caching services (Redis and Memcached), and a FastAPI application with PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks.

**Scope**: 3 Chef cookbooks with external dependencies
**Complexity**: Medium
**Estimated Timeline**: 2-3 weeks

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening (fail2ban, UFW), and self-signed certificates
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
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies (both local and external) - will be replaced by Ansible Galaxy requirements file
- `Policyfile.rb`: Defines the run list and cookbook dependencies - will be replaced by Ansible playbook structure
- `solo.rb`: Chef Solo configuration - will be replaced by Ansible configuration
- `solo.json`: Node attributes and run list - will be replaced by Ansible inventory and variable files
- `Vagrantfile`: Defines the development VM - can be adapted for Ansible testing
- `vagrant-provision.sh`: Provisions the VM with Chef - will be replaced with Ansible provisioning

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (from Vagrantfile), with support for Ubuntu 18.04+ and CentOS 7+ (from cookbook metadata)
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be targeting on-premises or local development environments

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation and configuration
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation and configuration
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation and configuration
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management modules (openssl_*)

### Security Considerations

- **Self-signed SSL certificates**: Migration must preserve the certificate generation for development environments
  - Current approach: OpenSSL commands in Chef recipes
  - Ansible approach: Use `openssl_certificate` module

- **Redis authentication**: 
  - Current approach: Redis password set in node attributes
  - Ansible approach: Use Ansible Vault for the Redis password

- **PostgreSQL credentials**:
  - Current approach: Hardcoded in Chef recipe
  - Ansible approach: Use Ansible Vault for database credentials

- **SSH hardening**:
  - Current approach: Modifies sshd_config to disable root login and password authentication
  - Ansible approach: Use `lineinfile` module or dedicated SSH role

- **Firewall configuration**:
  - Current approach: Uses UFW with Chef execute resources
  - Ansible approach: Use `ufw` module

- **Fail2ban configuration**:
  - Current approach: Custom template for jail.local
  - Ansible approach: Use `template` module or dedicated fail2ban role

### Technical Challenges

- **Multi-site Nginx configuration**: 
  - Challenge: The current implementation uses Chef attributes to define multiple sites
  - Mitigation: Create Ansible variables structure that mirrors the Chef attributes, use with_items/loop to iterate through sites

- **Redis configuration hacks**: 
  - Challenge: The Chef recipe includes a ruby_block to modify Redis config files after they're created
  - Mitigation: Create a custom Redis configuration template in Ansible that doesn't require post-processing

- **Service dependencies**: 
  - Challenge: Ensuring proper service startup order (PostgreSQL before FastAPI, etc.)
  - Mitigation: Use Ansible handlers and notify system, or explicit wait_for tasks

- **SSL certificate management**: 
  - Challenge: Generating and managing SSL certificates for multiple domains
  - Mitigation: Use Ansible's openssl_* modules with proper conditionals to check for existing certificates

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Start with basic Nginx installation and configuration
   - Add SSL certificate generation
   - Add security hardening (fail2ban, UFW)
   - Add multi-site configuration

2. **cache** (Priority 2)
   - Memcached configuration
   - Redis installation and configuration
   - Redis security setup

3. **fastapi-tutorial** (Priority 3)
   - PostgreSQL installation and configuration
   - Python environment setup
   - Application deployment
   - Service configuration

### Assumptions

1. The target environment will continue to be Vagrant-based for development/testing
2. The same operating systems will be supported (Fedora, Ubuntu, CentOS)
3. Self-signed certificates are acceptable for development environments
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The current security practices (fail2ban, UFW, SSH hardening) should be maintained
6. The current multi-site structure for Nginx will be preserved
7. Redis and Memcached will continue to be used as caching solutions
8. PostgreSQL will continue to be the database for the FastAPI application