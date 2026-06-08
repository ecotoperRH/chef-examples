# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- Well-structured Chef cookbooks with clear separation of concerns
- Standard infrastructure components (Nginx, Redis, Memcached, PostgreSQL)
- Security configurations that need careful migration
- Credentials that need to be migrated to Ansible Vault

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and firewall configuration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, fail2ban integration, UFW firewall rules

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

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `Vagrantfile`: Defines the development VM configuration using Vagrant with Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef
- `solo.json`: Configuration data for Chef Solo, contains site configurations and security settings
- `solo.rb`: Chef Solo configuration file

### Target Details

Based on the source configuration files:

- **Operating System**: Supports both Ubuntu (>= 18.04) and CentOS (>= 7.0) as indicated in cookbook metadata files. Development environment uses Fedora 42 (from Vagrantfile).
- **Virtual Machine Technology**: Vagrant with libvirt provider as indicated in the Vagrantfile.
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud VMs.

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` role or direct package installation and configuration
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible's `memcached` role or direct package installation and configuration
- **redisio (~> 7.2.4)**: Replace with Ansible's `redis` role or direct package installation and configuration

### Security Considerations

- **SSL Certificate Management**: 
  - Self-signed certificates are generated for development
  - Migration should maintain the same security level or improve it
  - Consider using Ansible's `openssl_certificate` module

- **Firewall Configuration**: 
  - UFW is configured with specific rules for HTTP, HTTPS, and SSH
  - Migration should use Ansible's `ufw` module or equivalent for the target OS

- **fail2ban Integration**: 
  - fail2ban is configured for intrusion prevention
  - Use Ansible's `fail2ban` module or direct configuration

- **SSH Hardening**: 
  - Root login is disabled
  - Password authentication is disabled
  - Use Ansible's `ssh` module to maintain these security settings

- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123"
  - PostgreSQL database credentials in fastapi-tutorial cookbook: "fastapi:fastapi_password"
  - These should be migrated to Ansible Vault

### Technical Challenges

- **Multi-site Nginx Configuration**: 
  - The Chef cookbook dynamically creates multiple virtual hosts
  - Ansible implementation will need to handle the same dynamic configuration
  - Solution: Use Ansible loops with templates for site configuration

- **SSL Certificate Generation**: 
  - Self-signed certificates are generated for each site
  - Solution: Use Ansible's `openssl_certificate` module with proper conditionals

- **Service Dependencies**: 
  - FastAPI application depends on PostgreSQL
  - Solution: Use Ansible's `meta: dependencies` or explicit ordering with `handlers`

- **Security Hardening**: 
  - Multiple security layers (fail2ban, UFW, SSH hardening)
  - Solution: Create dedicated security role with proper tagging for selective application

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component
   - Other services depend on it
   - Start with basic Nginx configuration, then add SSL and multi-site features

2. **cache** (Priority 2)
   - Independent service but used by the application
   - Relatively simple configuration with external dependencies

3. **fastapi-tutorial** (Priority 3)
   - Application layer that depends on other services
   - More complex with database integration and application deployment

### Assumptions

1. The target environment will continue to support both Ubuntu and CentOS as specified in the cookbook metadata.
2. Self-signed certificates are acceptable for the migrated environment (production would likely use proper certificates).
3. The same security policies (disabled root login, password authentication) will be maintained.
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain accessible.
5. The same VM resources (2GB RAM, 2 CPUs) will be sufficient for the Ansible-managed environment.
6. The current network configuration (port forwarding, private network) will be maintained.
7. Redis and Memcached configurations will remain similar (versions, authentication requirements).
8. PostgreSQL database name and credentials can remain the same.