# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx configuration with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks. The estimated timeline for this migration is 3-4 weeks, with moderate complexity due to the security configurations and multiple service integrations.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and firewall configuration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, UFW firewall rules, fail2ban integration

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Vagrantfile`: Defines the development VM configuration using Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef
- `solo.json`: Configuration data for Chef Solo, contains site configurations and security settings
- `solo.rb`: Chef Solo configuration file

### Target Details

Based on the source configuration files:

- **Operating System**: The cookbooks support both Ubuntu (>= 18.04) and CentOS (>= 7.0), but the Vagrant environment uses Fedora 42
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible's openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package configuration
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package configuration

### Security Considerations

- **Firewall Configuration**: Migration of UFW rules to Ansible's ufw module
- **fail2ban Integration**: Configuration of fail2ban using Ansible's template module
- **SSH Hardening**: Migration of SSH security settings (disable root login, password authentication)
- **Vault/secrets management**: 
  - Redis password in cache cookbook (hardcoded as 'redis_secure_password_123')
  - PostgreSQL database credentials in fastapi-tutorial cookbook (hardcoded as 'fastapi_password')
  - SSL certificate generation and management for multiple sites

### Technical Challenges

- **Multi-site Nginx Configuration**: Ensuring proper template conversion for the multiple virtual hosts
- **SSL Certificate Management**: Implementing self-signed certificate generation in Ansible
- **Service Dependencies**: Maintaining proper ordering of service installations and configurations
- **Security Hardening**: Ensuring all security measures are properly implemented in Ansible

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for other services)
   - Start with basic Nginx installation
   - Add SSL certificate generation
   - Configure virtual hosts
   - Implement security measures (fail2ban, UFW)

2. **cache** (low complexity, independent service)
   - Implement Memcached configuration
   - Implement Redis with authentication

3. **fastapi-tutorial** (high complexity, depends on PostgreSQL)
   - Set up PostgreSQL database
   - Configure Python environment
   - Deploy FastAPI application
   - Set up systemd service

### Assumptions

1. The target environment will continue to be Fedora-based systems, though the cookbooks support Ubuntu and CentOS
2. Self-signed certificates are acceptable for the migration (production would likely use Let's Encrypt or other CA)
3. The hardcoded credentials in the Chef recipes will be replaced with Ansible Vault for secure credential management
4. The directory structure for web content (/var/www/[site]) will remain the same
5. The PostgreSQL database structure and configuration will remain unchanged
6. The FastAPI application source will continue to be pulled from the same Git repository
7. The systemd service configuration for the FastAPI application will remain functionally equivalent
8. The security configurations (fail2ban, UFW, SSH hardening) will be maintained with equivalent settings
9. Redis and Memcached configurations will maintain the same performance characteristics