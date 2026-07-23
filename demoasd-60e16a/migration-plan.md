# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure setup for a multi-site Nginx web server with FastAPI application backend and caching services (Redis and Memcached). The migration to Ansible will involve converting 3 Chef cookbooks with their dependencies to equivalent Ansible roles and playbooks.

**Estimated Timeline:**
- Analysis and Planning: 1 week
- Development of Ansible roles: 2-3 weeks
- Testing and Validation: 1-2 weeks
- Documentation and Knowledge Transfer: 1 week
- Total: 5-7 weeks

**Complexity Assessment:** Medium
- The Chef cookbooks are well-structured and focused on specific concerns
- External dependencies on community cookbooks need to be replaced with Ansible Galaxy roles
- Security configurations and SSL certificate management require careful handling

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening with fail2ban and UFW

- **cache**:
    - Description: Configures caching services including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database creation, systemd service configuration

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies for the Chef environment. Will be replaced by Ansible Galaxy requirements.yml.
- `Policyfile.rb` and `Policyfile.lock.json`: Define the Chef policy and locked dependencies. Will be replaced by Ansible playbook structure.
- `solo.json`: Contains node configuration data including site definitions and security settings. Will be migrated to Ansible inventory variables.
- `solo.rb`: Chef Solo configuration. Will be replaced by Ansible configuration.
- `Vagrantfile`: Defines the development VM. Can be adapted to use Ansible provisioner instead of Chef.
- `vagrant-provision.sh`: Bootstraps Chef in the Vagrant environment. Will be replaced with Ansible provisioning script.

### Target Details

- **Operating System**: Fedora 42 (based on Vagrantfile configuration)
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` module or community.general collection
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible Galaxy role for Memcached (e.g., `geerlingguy.memcached`)
- **redisio (~> 7.2.4)**: Replace with Ansible Galaxy role for Redis (e.g., `geerlingguy.redis`)

### Security Considerations

- **SSL Certificate Management**: The current implementation generates self-signed certificates. Ansible's `openssl_*` modules can handle this, but consider integrating with Let's Encrypt for production.
- **Firewall Configuration**: UFW rules need to be migrated to Ansible's `ufw` module or firewalld for Fedora.
- **fail2ban Configuration**: Migrate fail2ban configuration to Ansible's `template` module with appropriate handlers.
- **SSH Hardening**: Current implementation disables root login and password authentication. Migrate to Ansible's `lineinfile` or `template` module.
- **Vault/secrets management**:
  - Redis password is hardcoded in the cache cookbook (`redis_secure_password_123`)
  - PostgreSQL credentials are hardcoded in the fastapi-tutorial cookbook (`fastapi`/`fastapi_password`)
  - These should be migrated to Ansible Vault for secure storage

### Technical Challenges

- **Multi-site Configuration**: The dynamic generation of Nginx site configurations based on node attributes will need careful translation to Ansible's templating system.
- **Service Dependencies**: Ensuring proper ordering of service installations and configurations (e.g., PostgreSQL before FastAPI application).
- **Idempotency**: Ensuring that database creation and user setup operations are idempotent in Ansible.
- **SSL Certificate Generation**: Ensuring secure and idempotent certificate generation or acquisition.
- **Python Environment Management**: Managing Python virtual environments and dependencies with Ansible.

### Migration Order

1. **nginx-multisite** (Priority 1)
   - Core infrastructure component that other services depend on
   - Start with basic Nginx installation and configuration
   - Add SSL certificate management
   - Add security hardening (fail2ban, UFW)
   - Add multi-site configuration

2. **cache** (Priority 2)
   - Implement Memcached configuration
   - Implement Redis with authentication
   - Ensure proper integration with Nginx

3. **fastapi-tutorial** (Priority 3)
   - Set up PostgreSQL database
   - Deploy FastAPI application
   - Configure systemd service
   - Integrate with Nginx and caching services

### Assumptions

1. The target environment will continue to be Fedora-based (the Vagrantfile specifies Fedora 42).
2. Self-signed certificates are acceptable for development, but production may require proper CA-signed certificates.
3. The current security settings (disabling root login, password authentication) are appropriate for the target environment.
4. The FastAPI application repository at https://github.com/dibanez/fastapi_tutorial.git will remain available.
5. The current Redis and PostgreSQL passwords are for development only and will be replaced with secure passwords in production.
6. The current Nginx site configuration (test.cluster.local, ci.cluster.local, status.cluster.local) will be maintained in the Ansible implementation.
7. The Vagrant development environment will continue to be used for testing.