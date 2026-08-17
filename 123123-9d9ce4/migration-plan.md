# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with FastAPI application and caching services. The migration to Ansible is estimated to be of medium complexity, requiring approximately 3-4 weeks for a complete migration with testing. The repository uses Chef Solo with Berkshelf for dependency management and contains three primary cookbooks with external dependencies.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and firewall configuration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, fail2ban integration, UFW firewall setup, security hardening

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database configuration, systemd service management

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration, service management

### Infrastructure Files

- `Berksfile`: Dependency management file listing local and external cookbooks with version constraints
- `Policyfile.rb`: Chef Policyfile defining the run list and cookbook dependencies
- `solo.json`: Configuration data for Chef Solo with node attributes
- `solo.rb`: Chef Solo configuration file defining paths and log settings
- `Vagrantfile`: Vagrant configuration for local development/testing using Fedora 42
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: The repository supports both Ubuntu (>= 18.04) and CentOS (>= 7.0) as indicated in cookbook metadata files. The Vagrantfile uses Fedora 42 for testing.
- **Virtual Machine Technology**: Vagrant with libvirt provider is used for development/testing.
- **Cloud Platform**: No specific cloud provider configurations were detected. The setup appears to be designed for on-premises or generic cloud VMs.

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role from Galaxy or custom role
- **memcached (~> 6.0)**: Replace with Ansible memcached role from Galaxy or custom role
- **redisio (~> 7.2.4)**: Replace with Ansible Redis role from Galaxy or custom role
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management using openssl module

### Security Considerations

- **Self-signed SSL certificates**: The nginx-multisite cookbook generates self-signed certificates for development. In Ansible, use the `openssl_certificate` module to generate certificates or integrate with Let's Encrypt using `community.crypto.acme_certificate`.
- **Firewall configuration**: The cookbook configures UFW. Use Ansible's `ufw` module to maintain the same security posture.
- **fail2ban integration**: Configure fail2ban using Ansible's `template` module and service management.
- **SSH hardening**: The cookbook disables root login and password authentication. Implement using Ansible's `lineinfile` or `template` module for sshd_config.
- **Vault/secrets management**:
  - Redis password is hardcoded in the cache cookbook (`redis_secure_password_123`)
  - PostgreSQL credentials are hardcoded in the fastapi-tutorial cookbook (`fastapi`/`fastapi_password`)
  - Consider using Ansible Vault for these credentials

### Technical Challenges

- **Multi-site configuration**: The nginx-multisite cookbook dynamically creates site configurations based on node attributes. Implement using Ansible loops and templates.
- **Service dependencies**: The fastapi-tutorial service depends on PostgreSQL. Implement using Ansible handlers and wait_for module to ensure proper startup order.
- **Redis configuration hack**: The cache cookbook includes a ruby_block to modify Redis configuration. Implement using Ansible's lineinfile or template module with proper configuration.
- **Python virtual environment**: The fastapi-tutorial cookbook sets up a Python virtual environment. Use Ansible's `pip` module with the `virtualenv` parameter.

### Migration Order

1. **nginx-multisite** (moderate complexity, foundation for web services)
   - Start with basic Nginx installation and configuration
   - Add SSL certificate generation
   - Implement security hardening (fail2ban, UFW)
   - Configure virtual hosts

2. **cache** (moderate complexity, independent service)
   - Implement Memcached configuration
   - Implement Redis with authentication
   - Ensure proper service management

3. **fastapi-tutorial** (high complexity, depends on PostgreSQL)
   - Set up PostgreSQL database
   - Configure Python environment
   - Deploy application from Git
   - Set up systemd service

### Assumptions

1. The target environment will continue to be either Ubuntu (>= 18.04) or CentOS (>= 7.0)
2. Self-signed certificates are acceptable for development, but production may require proper certificates
3. The same security posture (disabled root login, password authentication, UFW, fail2ban) will be maintained
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available
5. The same directory structure for web content (/opt/server/test, /opt/server/ci, /opt/server/status) will be used
6. The same virtual hosts (test.cluster.local, ci.cluster.local, status.cluster.local) will be maintained
7. The migration will not change the application architecture or dependencies
8. The PostgreSQL database schema and user permissions will remain the same
9. Redis and Memcached configurations will maintain the same performance characteristics