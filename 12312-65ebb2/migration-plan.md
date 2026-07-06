# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks with their dependencies, security configurations, and service deployments.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- Well-structured Chef cookbooks with clear separation of concerns
- Standard web infrastructure components (Nginx, Redis, Memcached, PostgreSQL)
- Security hardening configurations that need careful migration
- Self-signed SSL certificate generation that needs to be replicated

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and self-signed certificate generation
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup, security headers, fail2ban integration, UFW firewall configuration

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Git repository deployment, Python virtual environment setup, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies (nginx, ssl_certificate, memcached, redisio)
- `Policyfile.rb`: Defines the run list and cookbook dependencies
- `Vagrantfile`: Defines the development environment (Fedora 42) with port forwarding and networking
- `solo.rb`: Chef Solo configuration file
- `solo.json`: JSON attributes for Chef run, including site configurations and security settings
- `vagrant-provision.sh`: Bash script for provisioning the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ mentioned in cookbook metadata
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` role or community.general collection
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules for certificate generation
- **memcached (~> 6.0)**: Replace with Ansible's `memcached` role or community.general collection
- **redisio (~> 7.2.4)**: Replace with Ansible's `redis` role or community.general collection

### Security Considerations

- **SSL/TLS Configuration**: 
  - Migration approach: Use Ansible's `openssl_*` modules to generate self-signed certificates
  - Ensure proper file permissions (640) and ownership (root:ssl-cert) for private keys

- **Firewall Configuration**: 
  - Migration approach: Use Ansible's `ufw` module to configure firewall rules
  - Ensure SSH, HTTP, and HTTPS ports are allowed

- **Fail2ban Integration**: 
  - Migration approach: Use Ansible's `template` module to configure fail2ban
  - Ensure fail2ban service is enabled and started

- **System Hardening**: 
  - Migration approach: Use Ansible's `sysctl` module to apply system security settings
  - Migrate SSH hardening configurations (disable root login, disable password authentication)

- **Vault/secrets management**:
  - Redis password: Found in cache/recipes/default.rb (hardcoded as 'redis_secure_password_123')
  - PostgreSQL credentials: Found in fastapi-tutorial/recipes/default.rb (username: 'fastapi', password: 'fastapi_password')
  - Database connection string: Found in .env file template in fastapi-tutorial/recipes/default.rb
  - Total credentials detected: 3 (all hardcoded in recipes)

### Technical Challenges

- **Self-signed Certificate Generation**: 
  - Description: The Chef cookbook generates self-signed certificates for each virtual host
  - Mitigation strategy: Use Ansible's `openssl_certificate` module with similar parameters

- **Multi-site Nginx Configuration**: 
  - Description: The Chef cookbook dynamically creates Nginx site configurations from attributes
  - Mitigation strategy: Use Ansible's template module with loops to create site configurations

- **Security Headers and Best Practices**: 
  - Description: The Chef cookbook applies various security headers and best practices
  - Mitigation strategy: Ensure all security headers are properly migrated to Ansible templates

- **Redis Configuration Workaround**: 
  - Description: The Chef cookbook includes a hack to fix Redis configuration
  - Mitigation strategy: Create proper Redis configuration templates in Ansible

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Contains security configurations that should be established first

2. **cache** (Priority 2)
   - Moderate complexity with Redis and Memcached configuration
   - Depends on basic system setup but not on other application components

3. **fastapi-tutorial** (Priority 3)
   - Application deployment that depends on PostgreSQL and potentially cache services
   - More complex with database setup, Python environment, and application deployment

### Assumptions

1. The target environment will continue to be Fedora-based systems (specifically Fedora 42 as indicated in the Vagrantfile)
2. The same network configuration (IP addresses, port forwarding) will be maintained
3. Self-signed certificates are acceptable for the migrated environment (not using Let's Encrypt or other CA)
4. The FastAPI application source will continue to be pulled from the same Git repository
5. The Redis and PostgreSQL passwords currently hardcoded in the recipes will be moved to Ansible Vault in the migrated solution
6. The current security configurations (fail2ban, UFW, SSH hardening) are still relevant and should be maintained
7. The Nginx site configurations (test.cluster.local, ci.cluster.local, status.cluster.local) will remain the same
8. The directory structure for document roots (/var/www/[site]) will be preserved