# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- The repository has a clear structure with well-defined cookbooks
- Security configurations are present and need careful migration
- External dependencies on community cookbooks need to be replaced with Ansible Galaxy roles

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and proper SSL certificate management
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup, security headers, fail2ban integration, UFW firewall configuration

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies including nginx (~> 12.0), memcached (~> 6.0), and redisio (~> 7.2.4)
- `solo.json`: Defines the Chef run list and configuration attributes for nginx sites and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines a Fedora 42 VM for local development and testing
- `vagrant-provision.sh`: Shell script to provision the Vagrant VM with Chef

### Target Details

- **Operating System**: Fedora (based on Vagrantfile specifying "generic/fedora42"), with support for Ubuntu 18.04+ and CentOS 7+ (based on cookbook metadata)
- **Virtual Machine Technology**: Libvirt (based on Vagrantfile configuration)
- **Cloud Platform**: Not specified, appears to be targeting on-premises or generic VM deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` role from Galaxy or direct package installation and configuration
- **memcached (~> 6.0)**: Replace with Ansible's `geerlingguy.memcached` role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible's `geerlingguy.redis` or DavidWittman.redis role

### Security Considerations

- **SSL/TLS Configuration**: 
  - Migration approach: Use Ansible's `openssl_*` modules to generate self-signed certificates
  - Ensure proper file permissions are maintained for private keys

- **Firewall (UFW)**: 
  - Migration approach: Use Ansible's `ufw` module to configure firewall rules
  - Ensure default deny policy and specific allow rules are preserved

- **fail2ban**: 
  - Migration approach: Use Ansible to install and configure fail2ban with appropriate jail settings
  - Maintain existing jail configurations

- **SSH Hardening**: 
  - Migration approach: Use Ansible's `lineinfile` or templates to configure SSH daemon
  - Preserve settings for disabling root login and password authentication

- **Vault/secrets management**:
  - Redis password: Currently hardcoded as 'redis_secure_password_123' in cache/recipes/default.rb
  - PostgreSQL credentials: Currently hardcoded as user 'fastapi' with password 'fastapi_password'
  - Count: 2 sets of credentials detected
  - Migration approach: Use Ansible Vault to securely store these credentials

### Technical Challenges

- **Multi-site Nginx Configuration**: 
  - Description: The current setup dynamically creates multiple virtual hosts with SSL
  - Mitigation: Use Ansible templates with loops to generate site configurations, similar to the Chef approach

- **SSL Certificate Generation**: 
  - Description: Self-signed certificates are generated for each site
  - Mitigation: Use Ansible's `openssl_certificate` module to generate certificates with proper permissions

- **PostgreSQL User and Database Creation**: 
  - Description: The current setup uses shell commands via execute resources
  - Mitigation: Use Ansible's `postgresql_*` modules for more idiomatic database management

- **Redis Configuration Patching**: 
  - Description: The current setup uses a ruby_block to modify Redis configuration
  - Mitigation: Use Ansible templates to generate proper Redis configuration files directly

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Contains security configurations that should be established first

2. **cache** (Priority 2)
   - Moderate complexity with external dependencies
   - Required for application performance but not for basic functionality

3. **fastapi-tutorial** (Priority 3)
   - Application deployment that depends on properly configured infrastructure
   - Involves database setup and application-specific configurations

### Assumptions

1. The target environment will continue to be Fedora-based systems, with potential deployment to Ubuntu or CentOS as indicated in the cookbook metadata.

2. The self-signed SSL certificates approach is acceptable for the migrated solution rather than integrating with Let's Encrypt or another certificate authority.

3. The security configurations (fail2ban, UFW, SSH hardening) are required in the migrated solution.

4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available and compatible.

5. The current hardcoded credentials in the Chef recipes will be replaced with more secure approaches using Ansible Vault.

6. The Vagrant-based development workflow will be maintained, but updated to use Ansible provisioning instead of Chef.

7. The current directory structure with separate modules for nginx, cache, and application deployment will be maintained in the Ansible roles structure.

8. The current nginx site configurations (test.cluster.local, ci.cluster.local, status.cluster.local) will remain the same in the migrated solution.