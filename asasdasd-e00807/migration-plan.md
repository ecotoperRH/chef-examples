# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks, handling external dependencies, and ensuring proper security configurations are maintained.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible roles: 3-4 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 6-8 weeks

**Complexity:** Medium to High
- Multiple interconnected services
- Security configurations that need careful migration
- Database and application configurations

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening with fail2ban and UFW

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

- `Berksfile`: Dependency management for Chef cookbooks - will be replaced by Ansible Galaxy requirements
- `Policyfile.rb` and `Policyfile.lock.json`: Chef policy definitions - will be replaced by Ansible playbooks
- `Vagrantfile`: VM configuration for development/testing - can be adapted for Ansible testing
- `vagrant-provision.sh`: Chef provisioning script - will be replaced by Ansible provisioning
- `solo.rb`: Chef Solo configuration - will be replaced by Ansible configuration
- `solo.json`: Chef attributes and run list - will be replaced by Ansible variables and playbooks

### Target Details

Based on the source configuration files:

- **Operating System**: Supports Ubuntu 18.04+ and CentOS 7+, with Fedora 42 used in Vagrant development environment
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud VMs

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible crypto modules (openssl_*, community.crypto collection)
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation

### Security Considerations

- **Firewall Configuration**: UFW rules need to be migrated to Ansible UFW module or firewalld for RHEL-based systems
- **Fail2ban Setup**: Configuration needs to be migrated to Ansible fail2ban role
- **SSL Certificate Management**: Self-signed certificates generation needs to be handled with Ansible crypto modules
- **SSH Hardening**: SSH configuration hardening needs to be migrated
- **Vault/secrets management**:
  - Redis password in cache cookbook (hardcoded as 'redis_secure_password_123')
  - PostgreSQL database credentials in fastapi-tutorial cookbook (hardcoded as 'fastapi_password')
  - Total credentials detected: 2 hardcoded passwords that should be moved to Ansible Vault

### Technical Challenges

- **Multi-site Configuration**: The dynamic generation of multiple Nginx sites will need careful translation to Ansible templates and loops
- **SSL Certificate Management**: Self-signed certificate generation and management will need to be handled with Ansible's crypto modules
- **Service Interdependencies**: Ensuring proper ordering of service deployment (database before application, etc.)
- **Security Hardening**: Ensuring all security measures are properly translated to Ansible equivalents
- **Python Environment Management**: Handling Python virtual environments and dependencies with Ansible

### Migration Order

1. **cache** (Priority 1): Relatively simple Redis and Memcached configuration
2. **nginx-multisite** (Priority 2): Core infrastructure component with security configurations
3. **fastapi-tutorial** (Priority 3): Application deployment that depends on database setup

### Assumptions

1. The target environment will continue to support Ubuntu 18.04+ or CentOS 7+ as specified in the cookbook metadata
2. The Vagrant development environment will be maintained for testing
3. The current security configurations (fail2ban, UFW, SSH hardening) are required in the Ansible version
4. Self-signed certificates are acceptable for development (production would likely use Let's Encrypt or other CA)
5. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
6. The current hardcoded credentials will be replaced with Ansible Vault secrets
7. The current directory structure for web content (/var/www/[site]) will be maintained
8. The PostgreSQL database configuration will remain similar
9. The systemd service configuration for FastAPI will be maintained