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
- Well-structured Chef cookbooks with clear dependencies
- Standard infrastructure components (Nginx, Redis, Memcached, PostgreSQL)
- Security configurations that need careful migration
- Self-contained development environment using Vagrant

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
    - Key Features: Python virtual environment setup, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management for Chef cookbooks - will be replaced by Ansible Galaxy requirements.yml
- `Policyfile.rb` and `Policyfile.lock.json`: Chef policy definitions - will be replaced by Ansible playbooks
- `Vagrantfile`: Development environment configuration - can be adapted for Ansible testing
- `vagrant-provision.sh`: Chef provisioning script - will be replaced with Ansible provisioning
- `solo.json`: Chef node attributes - will be converted to Ansible variables
- `solo.rb`: Chef configuration - will be replaced by Ansible configuration

### Target Details

Based on the source configuration files:

- **Operating System**: Supports Ubuntu 18.04+ and CentOS 7+, with Fedora 42 used in Vagrant development environment
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or direct package installation
- **ssl_certificate (~> 2.1)**: Replace with Ansible crypto modules (openssl_*, community.crypto collection)
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation

### Security Considerations

- **SSL Certificate Management**: 
  - Self-signed certificates are generated in the Chef cookbook
  - Migration approach: Use Ansible's crypto modules for certificate generation or integrate with Let's Encrypt

- **Firewall Configuration**: 
  - UFW is configured to allow only necessary ports (SSH, HTTP, HTTPS)
  - Migration approach: Use Ansible's ufw module or firewalld module depending on target OS

- **SSH Hardening**:
  - Root login disabled
  - Password authentication disabled
  - Migration approach: Use Ansible's openssh_config module or ssh role

- **System Hardening**:
  - fail2ban for brute force protection
  - sysctl security settings
  - Migration approach: Use Ansible's fail2ban and sysctl modules

- **Vault/secrets management**:
  - Redis password hardcoded in recipe (redis_secure_password_123)
  - PostgreSQL password hardcoded in recipe (fastapi_password)
  - Migration approach: Use Ansible Vault for storing sensitive credentials

### Technical Challenges

- **Multi-site Nginx Configuration**: 
  - Description: The Chef cookbook dynamically creates multiple virtual hosts with SSL
  - Mitigation: Use Ansible templates and loops to generate similar configuration

- **Service Orchestration**: 
  - Description: Proper ordering of service installation, configuration, and startup
  - Mitigation: Use Ansible handlers and proper task dependencies

- **SSL Certificate Generation**: 
  - Description: Self-signed certificates are generated for development
  - Mitigation: Use Ansible's openssl_* modules or integrate with certbot for production

- **Database Initialization**: 
  - Description: PostgreSQL database and user creation
  - Mitigation: Use Ansible's postgresql_* modules from the community.postgresql collection

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for other services)
   - Create base Nginx role
   - Implement SSL certificate generation
   - Configure virtual hosts
   - Implement security hardening

2. **cache** (low complexity, independent service)
   - Create Redis role with authentication
   - Create Memcached role

3. **fastapi-tutorial** (high complexity, depends on database)
   - Create PostgreSQL role
   - Create Python application deployment role
   - Configure systemd service

### Assumptions

1. The target environment will continue to use the same operating systems (Ubuntu 18.04+ or CentOS 7+)
2. Self-signed certificates are acceptable for development, but production may require proper CA-signed certificates
3. The same security hardening measures will be maintained in the Ansible roles
4. The FastAPI application source code will remain available at the specified GitHub repository
5. The Vagrant development environment will be maintained for testing
6. No additional services beyond what's explicitly configured in the Chef cookbooks are required
7. The Redis and Memcached configurations don't require advanced clustering or replication
8. The PostgreSQL database doesn't require replication or advanced configuration
9. The current network configuration and firewall rules are appropriate for the target environment