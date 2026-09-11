# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration that needs to be migrated to Ansible. The migration involves three Chef cookbooks (nginx-multisite, cache, and fastapi-tutorial) with dependencies on external cookbooks. The repository already contains a partial Ansible implementation for the nginx module, which can serve as a reference for the migration approach.

**Estimated Timeline:** 3-4 weeks for complete migration, testing, and documentation.
**Complexity:** Medium - The cookbooks have clear responsibilities and moderate complexity.
**Team Size Recommendation:** 2 engineers (1 for infrastructure components, 1 for application components)

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures nginx with multiple SSL-enabled subdomains, security hardening, and site-specific configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate management, security hardening with fail2ban and UFW

- **cache**:
    - Description: Configures caching services including Redis with authentication and Memcached
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis configuration with authentication, Memcached setup

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies for the Chef environment
- `Policyfile.rb`: Defines the run list and cookbook versions
- `Vagrantfile`: Defines the development environment for testing
- `solo.json`: Chef solo configuration
- `solo.rb`: Chef solo configuration
- `vagrant-provision.sh`: Shell script for provisioning Vagrant environment

### Target Details

Based on the source configuration files:

- **Operating System**: Both Ubuntu (>= 18.04) and CentOS (>= 7.0) are supported in the current implementation. The Ansible implementation should maintain compatibility with both.
- **Virtual Machine Technology**: Vagrant is used for development/testing environments.
- **Cloud Platform**: No specific cloud platform dependencies were identified in the reviewed files.

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role (already partially implemented)
- **ssl_certificate (~> 2.1)**: Replace with Ansible's crypto modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation and configuration
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation and configuration

### Security Considerations

- **SSL/TLS Configuration**: The current implementation generates self-signed certificates. Migration should maintain this capability while providing an option for proper certificate management.
- **Firewall Configuration**: UFW configuration should be migrated to equivalent Ansible UFW module or firewalld for RedHat-based systems.
- **Fail2ban Integration**: Current fail2ban configuration should be preserved in the Ansible implementation.
- **SSH Hardening**: Current SSH security configurations (disabling root login, password authentication) should be maintained.
- **Vault/secrets management**:
  - Redis password is hardcoded in the cache cookbook
  - PostgreSQL credentials are hardcoded in the fastapi-tutorial cookbook
  - These should be migrated to Ansible Vault or another secrets management solution

### Technical Challenges

- **Multi-OS Support**: The current implementation supports both Ubuntu and CentOS. The Ansible implementation must maintain this compatibility with proper conditionals.
- **SSL Certificate Management**: The current implementation generates self-signed certificates. The Ansible implementation should provide options for both self-signed and proper CA-signed certificates.
- **Configuration Templates**: The nginx configuration templates will need careful migration to ensure all security and performance settings are preserved.
- **Application Deployment**: The FastAPI application deployment involves multiple steps (git clone, venv setup, dependency installation, database setup) that need to be carefully orchestrated in Ansible.

### Migration Order

1. **nginx-multisite** (Priority 1): Already has a partial Ansible implementation that can be extended. This is a foundational component.
2. **cache** (Priority 2): Relatively simple configuration that depends on external modules.
3. **fastapi-tutorial** (Priority 3): More complex application deployment that depends on the web server being configured.

### Assumptions

1. The target environment will continue to support both Ubuntu and CentOS operating systems.
2. The current self-signed certificate approach is acceptable for the migrated solution, though improvements for production use may be needed.
3. The current security configurations (fail2ban, UFW, SSH hardening) are appropriate and should be maintained.
4. The FastAPI application source will continue to be available at the specified Git repository.
5. The directory structure and file paths in the current implementation are appropriate and can be maintained in the Ansible implementation.
6. The existing Ansible implementation for nginx in the modules directory is intended to be used as a reference or starting point for the migration.