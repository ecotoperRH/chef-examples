# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure for deploying a multi-site Nginx web server with caching services (Memcached and Redis) and a FastAPI application with PostgreSQL. The migration to Ansible is estimated to be of medium complexity, requiring approximately 3-4 weeks for a complete migration with testing. The repository consists of three main cookbooks with clear responsibilities and minimal external dependencies.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and self-signed certificates
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening (fail2ban, ufw, sysctl)

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

- `Berksfile`: Defines cookbook dependencies (nginx, memcached, redisio, ssl_certificate)
- `Policyfile.rb`: Defines the run list and cookbook dependencies
- `solo.json`: Contains node attributes for Nginx sites and security configurations
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for development/testing
- `vagrant-provision.sh`: Provisions the Vagrant VM with Chef

### Target Details

- **Operating System**: Fedora/RHEL-based (Fedora 42 specified in Vagrantfile) with Ubuntu/CentOS support in cookbooks
- **Virtual Machine Technology**: Libvirt (specified in Vagrantfile)
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or nginx_core modules
- **memcached (~> 6.0)**: Replace with Ansible memcached role or package installation
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible openssl modules for certificate generation

### Security Considerations

- **Firewall Configuration**: The Chef cookbook configures UFW; migration should use Ansible's firewalld or ufw modules
- **Fail2ban Setup**: Migrate fail2ban configuration to Ansible
- **SSH Hardening**: Migrate SSH security settings (disable root login, password authentication)
- **Sysctl Security**: Migrate sysctl security settings
- **Vault/secrets management**:
  - Redis password is hardcoded in the cache cookbook (`redis_secure_password_123`)
  - PostgreSQL password is hardcoded in the fastapi-tutorial cookbook (`fastapi_password`)
  - No Chef Vault or encrypted data bags are used
  - SSL certificates are self-generated with default values

### Technical Challenges

- **Multi-site Nginx Configuration**: The dynamic generation of multiple virtual hosts with SSL needs careful translation to Ansible templates
- **Redis Configuration Hack**: The Chef cookbook includes a Ruby block to modify Redis configuration files after installation, which will need a custom approach in Ansible
- **Service Dependencies**: Ensuring proper service startup order (PostgreSQL before FastAPI, etc.)

### Migration Order

1. **nginx-multisite cookbook** (medium complexity)
   - Core web server functionality
   - Required by the application
   - Contains security hardening that should be applied first

2. **cache cookbook** (low complexity)
   - Supporting services
   - Relatively simple configuration with external dependencies

3. **fastapi-tutorial cookbook** (medium complexity)
   - Application deployment
   - Depends on PostgreSQL setup and potentially the web server

### Assumptions

1. The target environment will continue to be Fedora/RHEL-based systems
2. Self-signed certificates are acceptable for development/testing
3. The same directory structure for web content will be maintained
4. Hardcoded passwords in the Chef recipes will be replaced with Ansible Vault
5. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
6. The current security configurations (fail2ban, ufw, SSH hardening) are appropriate for the target environment
7. The Nginx configuration templates will need to be preserved with minimal changes
8. Redis and Memcached configurations will remain similar
9. PostgreSQL database setup for FastAPI will follow the same naming conventions