# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three primary Chef cookbooks to Ansible roles, addressing external dependencies, and ensuring security configurations are properly maintained.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- The codebase is well-structured with clear separation of concerns
- No complex custom resources or providers
- Standard infrastructure components (web server, caching, application deployment)
- Security configurations need careful attention during migration

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
    - Key Features: Git-based deployment, Python virtual environment, PostgreSQL database setup, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `solo.json`: Configuration data for Chef Solo, contains site configurations and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for local development and testing
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Supports both Ubuntu (>= 18.04) and CentOS (>= 7.0), with Fedora 42 used for development
- **Virtual Machine Technology**: Vagrant with libvirt provider for development
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or collection (e.g., `ansible.posix.nginx`)
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role (e.g., `geerlingguy.memcached`)
- **redisio (~> 7.2.4)**: Replace with Ansible Redis role (e.g., `geerlingguy.redis`)

### Security Considerations

- **Firewall Configuration**: The Chef cookbook configures UFW; migrate to Ansible's `ufw` module or `firewalld` module depending on target OS
- **Fail2ban Setup**: Migrate fail2ban configuration to Ansible using the `template` module
- **SSH Hardening**: Preserve SSH security settings (disable root login, password authentication)
- **Sysctl Security Settings**: Migrate sysctl security configurations
- **Vault/secrets management**:
  - Redis password in cache cookbook: `redis_secure_password_123` (hardcoded)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username `fastapi` with password `fastapi_password` (hardcoded)
  - SSL certificates and private keys generated and stored in `/etc/ssl/certs` and `/etc/ssl/private`
  - FastAPI environment variables in `.env` file

### Technical Challenges

- **SSL Certificate Generation**: Chef cookbook generates self-signed certificates; ensure Ansible properly handles certificate generation and permissions
- **Multi-site Configuration**: The nginx-multisite cookbook dynamically creates site configurations; ensure Ansible templates maintain this flexibility
- **Service Dependencies**: Ensure proper ordering of service deployments (e.g., PostgreSQL before FastAPI application)
- **Redis Configuration**: The Chef cookbook includes a hack to fix Redis configuration; ensure Ansible handles Redis configuration properly
- **Idempotency**: Ensure database creation commands are idempotent in Ansible

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component
   - Other services depend on it
   - Contains security configurations that should be established first

2. **cache** (Priority 2)
   - Standalone services with minimal dependencies
   - Required by the application layer

3. **fastapi-tutorial** (Priority 3)
   - Application layer that depends on both web server and database
   - Should be migrated last as it depends on other components

### Assumptions

1. The target environment will continue to support both Ubuntu and CentOS as specified in the cookbook metadata
2. The Vagrant development environment will be maintained for testing
3. Self-signed certificates are acceptable for development (production would likely use different certificate management)
4. The current security configurations are appropriate and should be maintained
5. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
6. The hardcoded credentials in the cookbooks are for development only and will be replaced with Ansible Vault in production
7. The current directory structure with separate modules will be maintained in the Ansible project
8. The PostgreSQL database schema and data migration is out of scope for this infrastructure migration