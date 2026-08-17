# MIGRATION FROM CHEF TO ANSIBLE

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services and a FastAPI application. The migration to Ansible will require converting 3 cookbooks with their dependencies to equivalent Ansible roles and playbooks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL setup, security hardening

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

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node attributes and run list for Chef Solo
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for local testing with port forwarding
- `vagrant-provision.sh`: Bash script to provision the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ (from cookbook metadata)
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible's openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation

### Security Considerations

- **SSL/TLS Configuration**: Migration must preserve SSL certificate paths and configurations
  - Certificate path: `/etc/ssl/certs`
  - Private key path: `/etc/ssl/private`
  
- **Redis Authentication**: Redis is configured with password authentication
  - Password: `redis_secure_password_123` (stored in plaintext in recipe)
  
- **PostgreSQL Credentials**: Database credentials for FastAPI application
  - Username: `fastapi`
  - Password: `fastapi_password` (stored in plaintext in recipe)
  
- **Security Hardening**: The nginx-multisite cookbook includes security hardening
  - fail2ban integration
  - ufw firewall configuration
  - SSH hardening (root login disabled, password authentication disabled)

### Technical Challenges

- **Multi-site Configuration**: The Nginx setup manages multiple virtual hosts with SSL, which will require careful template conversion
  - Solution: Create Ansible templates that preserve the multi-site configuration structure

- **Redis Configuration Patching**: The cache cookbook includes a Ruby block that modifies Redis configuration after installation
  - Solution: Create an Ansible template for Redis configuration rather than patching an existing file

- **FastAPI Application Deployment**: The FastAPI application deployment includes Git clone, venv setup, and systemd service creation
  - Solution: Use Ansible's git, pip, and systemd modules to replicate this functionality

### Migration Order

1. **cache cookbook** (low complexity, foundational service)
   - Memcached and Redis installation and configuration
   - Minimal dependencies on other components

2. **nginx-multisite cookbook** (medium complexity, core infrastructure)
   - Base Nginx installation and configuration
   - Security hardening
   - SSL certificate management
   - Virtual host configuration

3. **fastapi-tutorial cookbook** (high complexity, application layer)
   - PostgreSQL database setup
   - Python environment configuration
   - Application deployment
   - Service management

### Assumptions

1. The target environment will continue to be Fedora-based, with potential for Ubuntu/CentOS deployment
2. The multi-site configuration will remain similar (test.cluster.local, ci.cluster.local, status.cluster.local)
3. SSL certificates are self-signed for development (based on Vagrant setup)
4. The FastAPI application source will remain available at the same Git repository
5. The current plaintext password approach will be replaced with Ansible Vault for secure credential management
6. The Vagrant development environment will be preserved but converted to use Ansible provisioning