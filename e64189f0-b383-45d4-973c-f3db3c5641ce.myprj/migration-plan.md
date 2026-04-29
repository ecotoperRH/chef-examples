# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three primary Chef cookbooks to Ansible roles, addressing external dependencies, and ensuring proper security configurations are maintained.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 3 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7 weeks

**Complexity Assessment:** Medium
- The repository has a clear structure with well-defined cookbooks
- Security configurations are present and need careful migration
- External dependencies on community cookbooks need to be replaced with Ansible Galaxy roles

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and custom configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening (fail2ban, ufw firewall)

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

- `Berksfile`: Dependency management file listing cookbook dependencies (nginx, ssl_certificate, memcached, redisio)
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `solo.json`: Configuration data for Chef Solo with site configurations and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Vagrant configuration for local development using Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

- **Operating System**: Fedora (based on Vagrantfile specifying "generic/fedora42")
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` module and community.general collection
- **memcached (~> 6.0)**: Replace with Ansible Galaxy role `geerlingguy.memcached`
- **redisio (~> 7.2.4)**: Replace with Ansible Galaxy role `geerlingguy.redis` or DavidWittman.redis
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules from community.crypto collection

### Security Considerations

- **Firewall Configuration**: Migrate UFW rules to Ansible's `ufw` module or `firewalld` module for Fedora
- **Fail2ban Setup**: Use Ansible Galaxy role `geerlingguy.security` or custom tasks for fail2ban configuration
- **SSH Hardening**: Migrate SSH security settings using Ansible's `lineinfile` or `template` modules
- **Vault/secrets management**:
  - Redis password in cache cookbook (hardcoded as 'redis_secure_password_123')
  - PostgreSQL credentials in fastapi-tutorial cookbook (hardcoded as 'fastapi_password')
  - SSL certificates and private keys in nginx-multisite cookbook
  - Recommendation: Use Ansible Vault for storing sensitive credentials

### Technical Challenges

- **SSL Certificate Generation**: Chef cookbook generates self-signed certificates; need to implement equivalent functionality in Ansible using the `openssl_*` modules
- **Multi-site Nginx Configuration**: Need to create templates and loops in Ansible to handle multiple site configurations
- **System Tuning**: Security-related sysctl settings need to be migrated to Ansible's `sysctl` module
- **Service Dependencies**: Ensure proper ordering of service installations and configurations, especially for the FastAPI application which depends on PostgreSQL

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Contains security configurations that should be established first

2. **cache** (Priority 2)
   - Supporting services that the application may depend on
   - Relatively straightforward migration with community roles available

3. **fastapi-tutorial** (Priority 3)
   - Application deployment that depends on the infrastructure being in place
   - More complex with database setup, Python environment, and application deployment

### Assumptions

1. The target environment will continue to be Fedora-based systems (as indicated by the Vagrantfile)
2. Self-signed certificates are acceptable for the migrated solution (production environments would likely use Let's Encrypt or other CA)
3. The same directory structure for web content will be maintained (/var/www/[site])
4. The FastAPI application will continue to be deployed from the same Git repository
5. The current security configurations (fail2ban, ufw, SSH hardening) are appropriate for the target environment
6. Redis and Memcached configurations will remain similar in terms of memory allocation and authentication requirements
7. PostgreSQL database name, user, and credentials can remain the same
8. No CI/CD pipeline integration is required as part of the migration