# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx web server setup with FastAPI application backend and caching services. The migration to Ansible is estimated to be of medium complexity, requiring approximately 2-3 weeks of effort for a skilled Ansible developer. The repository uses Chef cookbooks with external dependencies from the Chef Supermarket and includes security hardening, SSL certificate management, and multi-site configuration.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening (fail2ban, ufw firewall), and SSL certificate management
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening with fail2ban and ufw

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend, including Git repository cloning, Python virtual environment setup, and systemd service configuration
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: PostgreSQL database setup, Python environment configuration, systemd service management

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies including external cookbooks from Chef Supermarket (nginx, ssl_certificate, memcached, redisio)
- `Policyfile.rb`: Defines the Chef policy with run list and cookbook dependencies
- `solo.json`: Contains node attributes for Chef solo, including Nginx site configurations and security settings
- `solo.rb`: Chef solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for local development and testing
- `vagrant-provision.sh`: Shell script to provision the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Supports both Ubuntu (>= 18.04) and CentOS (>= 7.0) based on cookbook metadata, with Fedora 42 used for local development in Vagrant
- **Virtual Machine Technology**: Libvirt is used for local development as specified in the Vagrantfile
- **Cloud Platform**: No specific cloud provider configurations detected; appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role from Ansible Galaxy or create a custom role
- **ssl_certificate (~> 2.1)**: Replace with Ansible's openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or use package/service modules
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or create custom role for Redis configuration

### Security Considerations

- **Firewall Configuration**: The nginx-multisite cookbook configures ufw firewall rules that need to be migrated to Ansible's ufw module
- **fail2ban Setup**: fail2ban configuration needs to be migrated using Ansible's template module
- **SSH Hardening**: SSH security configurations (disabling root login, password authentication) need to be migrated using Ansible's lineinfile or template modules
- **Sysctl Security Settings**: System security settings in sysctl need to be migrated using Ansible's sysctl module
- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123" (hardcoded in recipe)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username "fastapi" with password "fastapi_password" (hardcoded in recipe)
  - SSL certificates are generated with self-signed certificates (no external vault integration)

### Technical Challenges

- **SSL Certificate Management**: The current implementation generates self-signed certificates. Migration should maintain this functionality while allowing for future integration with Let's Encrypt or other certificate authorities
- **Multi-site Configuration**: The dynamic generation of Nginx site configurations based on node attributes needs to be carefully migrated to Ansible's template system
- **Database Integration**: The PostgreSQL database setup for the FastAPI application needs to be properly migrated to ensure application functionality
- **Service Dependencies**: Ensuring proper service dependencies and restart handlers are maintained in the Ansible roles

### Migration Order

1. **nginx-multisite** (Priority 1): Core infrastructure component that other services depend on
   - Begin with basic Nginx installation and configuration
   - Add SSL certificate management
   - Implement security hardening (fail2ban, ufw)
   - Configure multi-site setup

2. **cache** (Priority 2): Supporting services with moderate complexity
   - Implement Memcached configuration
   - Implement Redis with authentication

3. **fastapi-tutorial** (Priority 3): Application deployment with database dependencies
   - Set up PostgreSQL database
   - Configure Python environment
   - Deploy FastAPI application
   - Configure systemd service

### Assumptions

1. The target environment will continue to support both Ubuntu and CentOS/RHEL-based systems
2. Self-signed certificates are acceptable for the initial migration (no immediate need for Let's Encrypt integration)
3. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain accessible
4. The migration will maintain the same security posture with fail2ban, ufw, and SSH hardening
5. Redis and Memcached configurations will maintain the same performance characteristics
6. The Ansible inventory will need to be created as part of the migration (not present in current repository)
7. The current repository is designed for a single-server deployment model (all services on one host)