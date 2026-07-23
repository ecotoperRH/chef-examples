# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with caching services (Redis and Memcached) and a FastAPI application backend. The migration to Ansible will involve converting three Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible roles: 2-3 weeks
- Testing and Validation: 1 week
- Documentation and Knowledge Transfer: 1 week
- Total: 5-6 weeks

**Complexity Assessment:** Medium
- The codebase is well-structured with clear separation of concerns
- Contains security hardening that will need careful migration
- Includes SSL certificate generation and management
- Contains hardcoded credentials that will need to be migrated to Ansible Vault

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and firewall configuration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, fail2ban integration, UFW firewall rules, security hardening

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: FastAPI Python application deployment with PostgreSQL database
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Dependency management file for Chef cookbooks, lists both local and external dependencies
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node configuration data for Chef Solo, contains site configurations and security settings
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Defines the development environment using Vagrant with Fedora 42
- `vagrant-provision.sh`: Provisioning script for the Vagrant environment, installs Chef and dependencies

### Target Details

Based on the source configuration files:

- **Operating System**: Fedora 42 (primary) with support for Ubuntu 18.04+ and CentOS 7+ (based on cookbook metadata)
- **Virtual Machine Technology**: KVM/libvirt (based on Vagrantfile configuration)
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or community.general.nginx_* modules
- **ssl_certificate (~> 2.1)**: Replace with Ansible's openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or package installation tasks
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or package installation and configuration tasks

### Security Considerations

- **Firewall Configuration**: The Chef cookbook configures UFW. Migration should use Ansible's firewalld or ufw modules.
- **fail2ban Integration**: The Chef cookbook configures fail2ban. Migration should use Ansible's template module for fail2ban configuration.
- **SSH Hardening**: The Chef cookbook disables root login and password authentication. Migration should use Ansible's lineinfile or template module for SSH configuration.
- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123" (hardcoded)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username "fastapi" with password "fastapi_password" (hardcoded)
  - SSL certificates and private keys generated and stored in /etc/ssl/certs and /etc/ssl/private
  - All credentials should be migrated to Ansible Vault

### Technical Challenges

- **SSL Certificate Management**: The Chef cookbook generates self-signed certificates. Migration should use Ansible's openssl_* modules to maintain the same functionality.
- **Multi-site Configuration**: The Chef cookbook uses templates and attributes to configure multiple Nginx sites. Migration should use Ansible templates with similar variable structures.
- **Service Dependencies**: The FastAPI application depends on PostgreSQL. Migration should maintain these dependencies using Ansible's handlers and notify system.
- **Security Hardening**: The Chef cookbook applies various security measures. Migration should ensure all security configurations are properly implemented in Ansible.

### Migration Order

1. **cache** (Priority 1): Relatively simple cookbook with Redis and Memcached configuration
2. **nginx-multisite** (Priority 2): Core infrastructure component with moderate complexity
3. **fastapi-tutorial** (Priority 3): Application deployment with database dependencies

### Assumptions

1. The target environment will continue to be Fedora 42 or similar Linux distributions.
2. The same network configuration (IP addresses, port mappings) will be maintained.
3. Self-signed certificates are acceptable for development/testing environments.
4. The FastAPI application source will continue to be pulled from the same Git repository.
5. The PostgreSQL database structure and user permissions will remain the same.
6. The Redis and Memcached configurations will maintain the same memory allocations and security settings.
7. The Nginx site configurations (test.cluster.local, ci.cluster.local, status.cluster.local) will remain unchanged.
8. The security hardening measures (fail2ban, UFW, SSH configuration) will be maintained.