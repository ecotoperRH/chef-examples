# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting 3 Chef cookbooks with their recipes, templates, and attributes to equivalent Ansible roles and playbooks.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- The codebase is well-structured with clear separation of concerns
- No custom resources or complex Chef-specific patterns
- Standard infrastructure components (web servers, caching, databases)

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and SSL certificate management
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup, security hardening (fail2ban, UFW firewall), sysctl security settings

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management for Chef cookbooks, lists external cookbook dependencies (nginx, ssl_certificate, memcached, redisio)
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `solo.rb`: Chef Solo configuration file
- `solo.json`: Node attributes and run list for Chef Solo
- `Vagrantfile`: Vagrant configuration for local development/testing using Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ based on cookbook metadata
- **Virtual Machine Technology**: Libvirt (based on Vagrantfile configuration)
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role (e.g., geerlingguy.nginx or custom role)
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management tasks using openssl module
- **memcached (~> 6.0)**: Replace with Ansible memcached role (e.g., geerlingguy.memcached)
- **redisio (~> 7.2.4)**: Replace with Ansible redis role (e.g., geerlingguy.redis or DavidWittman.redis)

### Security Considerations

- **SSL/TLS Configuration**: 
  - Migration approach: Use Ansible crypto modules for certificate generation
  - Ensure proper file permissions for private keys

- **Firewall Configuration (UFW)**:
  - Migration approach: Use Ansible ufw module to configure firewall rules
  - Ensure idempotent rule application

- **fail2ban Integration**:
  - Migration approach: Use Ansible to deploy fail2ban configuration templates
  - Ensure service is properly enabled and configured

- **SSH Hardening**:
  - Migration approach: Use Ansible to modify sshd_config with lineinfile or template module
  - Ensure proper testing to avoid lockouts

- **Vault/secrets management**:
  - Redis password in cache cookbook: Use Ansible Vault for secure storage
  - PostgreSQL credentials in fastapi-tutorial cookbook: Use Ansible Vault for secure storage
  - Count of credentials detected: 2 (Redis authentication password, PostgreSQL user password)

### Technical Challenges

- **Self-signed Certificate Generation**:
  - Description: The Chef cookbook generates self-signed certificates for each site
  - Mitigation strategy: Use Ansible's openssl_* modules to generate certificates with proper permissions

- **Multi-site Configuration**:
  - Description: Dynamic creation of multiple Nginx virtual hosts
  - Mitigation strategy: Use Ansible loops with templates to create site configurations

- **Service Dependencies**:
  - Description: Ensuring proper service startup order (e.g., PostgreSQL before FastAPI)
  - Mitigation strategy: Use Ansible handlers and meta dependencies between roles

- **Idempotent Firewall Rules**:
  - Description: Ensuring firewall rules are applied idempotently
  - Mitigation strategy: Use Ansible's ufw module with proper state definitions

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for web services)
   - Start with basic Nginx installation and configuration
   - Add SSL certificate management
   - Implement security hardening (fail2ban, firewall)
   - Configure virtual hosts

2. **cache** (low complexity, independent service)
   - Implement Memcached configuration
   - Implement Redis with authentication

3. **fastapi-tutorial** (high complexity, depends on PostgreSQL)
   - Set up PostgreSQL database
   - Deploy FastAPI application
   - Configure systemd service

### Assumptions

1. The target environment will continue to be Fedora 42 or compatible Linux distributions
2. Self-signed certificates are acceptable for the migrated solution (production would likely use Let's Encrypt or other CA)
3. The same security hardening measures are required in the Ansible implementation
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The directory structure for deployed applications will remain the same
6. No changes to the application configuration or behavior are required during migration
7. Redis and Memcached versions will remain compatible with the application requirements
8. The Vagrant development environment will be maintained for testing