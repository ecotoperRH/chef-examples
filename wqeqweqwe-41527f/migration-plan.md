# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx configuration with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will involve converting three primary Chef cookbooks, handling external dependencies, and ensuring proper security configurations are maintained.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible Roles: 3-4 weeks
- Testing and Validation: 2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 7-8 weeks

**Complexity Assessment:** Medium
- Multiple interconnected services
- Security configurations that need careful migration
- SSL certificate management
- Database integration

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and fail2ban/ufw integration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL/TLS setup with self-signed certificates, security headers, fail2ban integration, UFW firewall configuration

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration, log directory management

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Dependency management file listing both local cookbooks and external dependencies from Chef Supermarket
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `solo.json`: Configuration data for Chef Solo with site configurations and security settings
- `solo.rb`: Chef Solo configuration file defining cookbook paths and log settings
- `Vagrantfile`: Vagrant configuration for local development using Fedora 42
- `vagrant-provision.sh`: Provisioning script for Vagrant that installs Chef and runs the cookbooks

### Target Details

Based on the source configuration files:

- **Operating System**: Supports both Ubuntu (>= 18.04) and CentOS (>= 7.0) as specified in cookbook metadata, with Fedora 42 used for development in Vagrant
- **Virtual Machine Technology**: Vagrant with libvirt provider as indicated in the Vagrantfile
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or community.general.nginx_* modules
- **ssl_certificate (~> 2.1)**: Replace with Ansible crypto modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or package installation tasks
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct configuration

### Security Considerations

- **SSL/TLS Configuration**: 
  - Self-signed certificate generation for development environments
  - Proper certificate paths and permissions
  - Strong cipher configuration and TLS version restrictions

- **Firewall Configuration**:
  - UFW rules for HTTP, HTTPS, and SSH
  - Default deny policy

- **Fail2ban Integration**:
  - Jail configuration for SSH and web services

- **SSH Hardening**:
  - Root login disabled
  - Password authentication disabled

- **System Hardening**:
  - Sysctl security configurations

- **Vault/secrets management**:
  - Redis password in cache cookbook (plaintext: "redis_secure_password_123")
  - PostgreSQL user password in fastapi-tutorial cookbook (plaintext: "fastapi_password")
  - Database connection string in .env file
  - Total credentials detected: 3 plaintext passwords

### Technical Challenges

- **Multi-site Nginx Configuration**: 
  - Description: The current setup dynamically creates Nginx site configurations based on node attributes
  - Mitigation: Use Ansible templates with variable loops to achieve similar functionality

- **SSL Certificate Management**:
  - Description: Self-signed certificates are generated with specific ownership and permissions
  - Mitigation: Use Ansible's openssl_* modules to generate certificates with proper attributes

- **Service Orchestration**:
  - Description: Services have dependencies (e.g., FastAPI depends on PostgreSQL)
  - Mitigation: Use Ansible handlers and meta dependencies to ensure proper service ordering

- **Security Configuration**:
  - Description: Multiple security layers (firewall, fail2ban, SSH hardening)
  - Mitigation: Create dedicated security role with appropriate tags for selective application

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Contains security configurations that should be established first

2. **cache** (Priority 2)
   - Supporting services that the application will use
   - Relatively self-contained with minimal dependencies

3. **fastapi-tutorial** (Priority 3)
   - Application deployment that depends on both web server and database
   - More complex with multiple components (Python, PostgreSQL, Git)

### Assumptions

1. The target environment will continue to support either Ubuntu (>= 18.04) or CentOS (>= 7.0)
2. The Nginx sites configuration will remain similar (test.cluster.local, ci.cluster.local, status.cluster.local)
3. Self-signed certificates are acceptable for development (production would likely use Let's Encrypt or other CA)
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The security requirements (fail2ban, ufw, SSH hardening) will remain the same
6. The current plaintext passwords in the Chef recipes will be replaced with Ansible Vault encrypted values
7. The PostgreSQL database schema is managed by the FastAPI application and not by the infrastructure code
8. The Vagrant development environment is not required to be migrated (could be replaced with Ansible-compatible alternative)