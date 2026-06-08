# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks, handling external dependencies, and ensuring proper security configurations are maintained.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible roles: 3-4 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7-8 weeks

**Complexity Assessment:** Medium
- Multiple interconnected services
- Security configurations that need careful migration
- SSL certificate management
- Database configuration and credentials

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening with fail2ban and UFW firewall

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Dependency management for Chef cookbooks - will be replaced by Ansible Galaxy requirements.yml
- `Policyfile.rb`: Chef policy file defining the run list and cookbook versions - will be replaced by Ansible playbooks
- `Vagrantfile`: VM configuration for development/testing - can be adapted for Ansible testing
- `vagrant-provision.sh`: Shell script for Chef provisioning in Vagrant - will be replaced by Ansible provisioning
- `solo.json`: Chef node attributes configuration - will be migrated to Ansible variables
- `solo.rb`: Chef Solo configuration - not needed in Ansible

### Target Details

Based on the source configuration files:

- **Operating System**: Supports Ubuntu 18.04+ and CentOS 7.0+, with Fedora 42 used in Vagrant development environment
- **Virtual Machine Technology**: Libvirt (based on Vagrantfile configuration)
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic cloud VMs

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible's openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package configuration
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package configuration

### Security Considerations

- **SSL Certificate Management**: 
  - Self-signed certificates are generated in the Chef cookbook
  - Migration should use Ansible's `openssl_certificate` module for similar functionality
  - Consider adding Let's Encrypt integration for production environments

- **Firewall Configuration**: 
  - UFW firewall is configured in the Chef cookbook
  - Migration should use Ansible's `ufw` module to maintain identical rules

- **Fail2ban Configuration**: 
  - Fail2ban is configured for intrusion prevention
  - Migration should use Ansible's fail2ban role or direct configuration

- **SSH Hardening**:
  - Root login disabled
  - Password authentication disabled
  - Migration should maintain these security practices

- **Vault/secrets management**:
  - Redis password is hardcoded in the Chef recipe (`redis_secure_password_123`)
  - PostgreSQL credentials are hardcoded in the FastAPI recipe (`fastapi:fastapi_password`)
  - Migration should use Ansible Vault for these credentials

### Technical Challenges

- **Multi-site Nginx Configuration**: 
  - The Chef cookbook dynamically creates multiple virtual hosts
  - Ansible solution will need to use loops or with_items to achieve similar functionality
  - Challenge: Ensuring proper template rendering for each site

- **SSL Certificate Generation**:
  - Self-signed certificates are generated with specific attributes
  - Challenge: Replicating the exact certificate generation process in Ansible

- **Redis Configuration Hack**:
  - The Chef cookbook includes a ruby_block to modify Redis configuration
  - Challenge: Finding a clean Ansible approach to achieve the same result

- **Service Orchestration**:
  - Multiple interdependent services (Nginx, Redis, Memcached, PostgreSQL, FastAPI)
  - Challenge: Ensuring proper service start order and dependency handling

### Migration Order

1. **cache** (Priority 1):
   - Relatively simple configuration
   - Other services depend on it
   - Low complexity, good starting point

2. **nginx-multisite** (Priority 2):
   - More complex with templates and security configurations
   - Moderate complexity
   - Independent of application logic

3. **fastapi-tutorial** (Priority 3):
   - Most complex with application deployment, database setup
   - Depends on other services being configured
   - Highest complexity due to application-specific logic

### Assumptions

1. The target environment will continue to support Ubuntu 18.04+ or CentOS 7.0+
2. The self-signed SSL certificates approach is acceptable (vs. using Let's Encrypt)
3. The current security configurations (fail2ban, UFW, SSH hardening) are appropriate
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The current Redis and PostgreSQL passwords are development passwords and will be replaced in production
6. The Vagrant development environment will continue to be used for testing
7. No additional monitoring or logging solutions need to be integrated
8. The current directory structure for web content (/var/www/[site]) will be maintained