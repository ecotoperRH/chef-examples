# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with FastAPI application deployment and caching services. The migration to Ansible will involve converting three Chef cookbooks with their dependencies, security configurations, and service orchestration. Based on the complexity and scope, this migration is estimated to require 3-4 weeks of effort with a team of 2 engineers.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and fail2ban/firewall integration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup with self-signed certificates, security headers, fail2ban integration, UFW firewall configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend and systemd service configuration
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database creation, systemd service management

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration, log directory management

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node attributes and run list for Chef Solo execution
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Vagrant configuration for local development/testing using Fedora 42
- `vagrant-provision.sh`: Provisioning script for Vagrant that installs Chef and runs the cookbooks

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ mentioned in cookbook metadata
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or collection
- **memcached (~> 6.0)**: Replace with Ansible memcached role
- **redisio (~> 7.2.4)**: Replace with Ansible redis role
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management modules (openssl_*)

### Security Considerations

- **SSL/TLS Configuration**: Migration must maintain the same security level for TLS protocols (TLSv1.2, TLSv1.3) and cipher suites
- **Security Headers**: Preserve all security headers (HSTS, X-Frame-Options, CSP, etc.) in Nginx configuration
- **Firewall Rules**: Maintain UFW firewall configuration with the same allowed services
- **fail2ban Integration**: Ensure fail2ban configuration is preserved for brute force protection
- **SSH Hardening**: Maintain SSH security settings (root login disabled, password authentication disabled)
- **Vault/secrets management**:
  - Redis password in cache cookbook (plaintext in recipe)
  - PostgreSQL database credentials in fastapi-tutorial cookbook (plaintext in recipe)
  - Environment variables in .env file for FastAPI application (plaintext in recipe)
  - Count: 3 sets of credentials detected, all stored as plaintext in recipes

### Technical Challenges

- **Multi-site Nginx Configuration**: The dynamic generation of multiple virtual hosts with SSL will require careful templating in Ansible
- **Self-signed Certificate Generation**: The current implementation uses inline shell commands for certificate generation, which will need to be replaced with Ansible's openssl modules
- **Redis Configuration Patching**: The current implementation uses a ruby_block to modify Redis configuration files after they're created, which will need a different approach in Ansible
- **Service Orchestration**: Ensuring proper service restart/reload notifications are maintained during the migration
- **PostgreSQL User/Database Creation**: The current implementation uses inline SQL commands, which should be replaced with Ansible's postgresql_* modules

### Migration Order

1. **cache cookbook** (low complexity, fewer dependencies)
   - Implement Memcached configuration
   - Implement Redis with authentication

2. **nginx-multisite cookbook** (moderate complexity)
   - Implement base Nginx configuration
   - Implement SSL certificate generation
   - Implement security configurations (fail2ban, UFW)
   - Implement virtual host configuration

3. **fastapi-tutorial cookbook** (higher complexity)
   - Implement Python environment setup
   - Implement PostgreSQL database configuration
   - Implement application deployment
   - Implement systemd service configuration

### Assumptions

1. The target environment will continue to be Fedora-based, though the cookbooks claim to support Ubuntu and CentOS as well
2. Self-signed certificates are acceptable for the migrated solution (production would likely use Let's Encrypt or other CA)
3. The same security hardening measures are required in the Ansible implementation
4. The PostgreSQL database will be local to the application server as in the current implementation
5. The Redis password and PostgreSQL credentials will need to be managed securely in the Ansible implementation (possibly using Ansible Vault)
6. The Vagrant development environment should be preserved for testing the Ansible implementation
7. The current implementation does not use Chef Vault or encrypted data bags for secrets management
8. The FastAPI application source will continue to be pulled from the same Git repository
9. The nginx-multisite cookbook's virtual hosts configuration will need to be preserved exactly as it is currently defined