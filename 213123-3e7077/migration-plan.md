# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration that needs to be migrated to Ansible. The codebase consists of three primary Chef cookbooks that manage a web application stack with Nginx, caching services (Redis and Memcached), and a FastAPI Python application with PostgreSQL. The migration complexity is moderate, with an estimated timeline of 4-6 weeks for a complete migration. One module (nginx) has already been partially migrated to Ansible, which can serve as a reference for the remaining modules.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL setup, security hardening with fail2ban, sysctl security configurations

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database configuration, systemd service management

### Infrastructure Files

- `Berksfile`: Chef dependency manager file listing cookbook dependencies (both local and external)
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Chef solo configuration file
- `solo.rb`: Chef solo Ruby configuration
- `Vagrantfile`: Vagrant configuration for development/testing environment
- `vagrant-provision.sh`: Shell script for Vagrant provisioning

### Target Details

Based on the source configuration files:

- **Operating System**: The cookbooks support both Ubuntu (>= 18.04) and CentOS (>= 7.0) as specified in the metadata.rb files. The migration should target both OS families.
- **Virtual Machine Technology**: Vagrant is used for development/testing, suggesting a VM-based deployment.
- **Cloud Platform**: No specific cloud platform configurations were identified. The deployment appears to be platform-agnostic.

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role (already partially migrated)
- **ssl_certificate (~> 2.1)**: Replace with Ansible's crypto modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached role or direct package installation
- **redisio (~> 7.2.4)**: Replace with Ansible redis role or direct package installation

### Security Considerations

- **SSL/TLS Configuration**: The nginx-multisite cookbook includes SSL configuration that needs to be migrated with updated protocols (TLSv1.2, TLSv1.3)
- **fail2ban Integration**: The nginx-multisite cookbook configures fail2ban for security, which needs to be migrated
- **sysctl Security Settings**: System-level security configurations need to be preserved
- **Vault/secrets management**:
  - Redis authentication password is hardcoded in the cache cookbook
  - PostgreSQL database credentials are hardcoded in the fastapi-tutorial cookbook
  - These should be migrated to Ansible Vault or another secrets management solution

### Technical Challenges

- **Multi-site Nginx Configuration**: The nginx-multisite cookbook uses Ruby templates to generate site configurations. This logic needs to be replicated in Ansible templates.
- **Custom Resources**: The nginx-multisite cookbook includes a custom resource (lineinfile.rb) that needs to be replaced with Ansible's lineinfile module.
- **Database Initialization**: The fastapi-tutorial cookbook uses inline SQL commands to initialize the PostgreSQL database. This needs to be migrated to Ansible's PostgreSQL modules.
- **Service Dependencies**: Ensuring proper service dependencies and ordering in Ansible (e.g., PostgreSQL before FastAPI application)

### Migration Order

1. **cache** (low risk, moderate value): Start with the cache module as it has fewer dependencies and provides a foundation for the application stack.
2. **nginx-multisite** (moderate complexity): Continue with the nginx-multisite module, leveraging the existing partial migration in the modules/nginx directory.
3. **fastapi-tutorial** (high complexity, dependencies): Finally, migrate the application module which depends on the other components.

### Assumptions

1. The existing Ansible nginx role in modules/nginx/ansible/roles/nginx is intended to replace the nginx-multisite cookbook, but may need additional features to fully match the cookbook's functionality.
2. The target environment will continue to support both Ubuntu and CentOS/RHEL systems.
3. The deployment model (VM-based, potentially with Vagrant for development) will remain the same.
4. No CI/CD pipeline integration is currently visible in the repository, so no CI/CD migration is required.
5. The current hardcoded credentials will need to be replaced with a more secure approach in Ansible.
6. The existing directory structure in the repository (with modules/nginx) suggests a pattern for organizing the migrated Ansible roles.