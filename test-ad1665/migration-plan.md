# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx setup with FastAPI application and caching services. The migration to Ansible will involve converting three Chef cookbooks with their dependencies, templates, and attributes to equivalent Ansible roles and playbooks.

**Scope**: 3 Chef cookbooks with external dependencies
**Complexity**: Medium
**Estimated Timeline**: 2-3 weeks

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
    - Description: Configures caching services (Memcached and Redis)
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Configures FastAPI Python application with PostgreSQL database
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, Git repository deployment, PostgreSQL database configuration, systemd service management

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled subdomains, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security hardening (fail2ban, UFW firewall), sysctl security settings

### Infrastructure Files

- `Berksfile`: Defines cookbook dependencies (both local and external) - will be replaced by Ansible Galaxy requirements.yml
- `Policyfile.rb`: Defines the run list and cookbook versions - will be replaced by Ansible playbook structure
- `solo.json`: Contains node attributes and run list - will be replaced by Ansible inventory variables
- `solo.rb`: Chef Solo configuration - not needed in Ansible
- `Vagrantfile`: Defines the development VM - can be adapted for Ansible testing
- `vagrant-provision.sh`: Provisions the VM with Chef - will be replaced with Ansible provisioning

### Target Details

- **Operating System**: Fedora 42 (based on Vagrantfile), with support for Ubuntu 18.04+ and CentOS 7+ (based on cookbook metadata)
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible's `nginx` module or community.general collection
- **memcached (~> 6.0)**: Replace with Ansible's `memcached` module
- **redisio (~> 7.2.4)**: Replace with Ansible's `redis` module or community.general collection
- **ssl_certificate (~> 2.1)**: Replace with Ansible's `openssl_*` modules

### Security Considerations

- **SSL/TLS Configuration**: The nginx-multisite cookbook generates self-signed certificates. In Ansible, use `openssl_certificate`, `openssl_csr`, and `openssl_privatekey` modules.
- **Firewall Rules**: UFW configuration in security.rb should be migrated to Ansible's `ufw` module.
- **Fail2ban**: Configuration should be migrated to Ansible templates and service management.
- **SSH Hardening**: SSH configuration changes should use Ansible's `lineinfile` or templates.
- **Vault/secrets management**:
  - Redis password in cache cookbook: Should be stored in Ansible Vault
  - PostgreSQL credentials in fastapi-tutorial cookbook: Should be stored in Ansible Vault
  - Count: 2 credentials detected (Redis password, PostgreSQL user/password)

### Technical Challenges

- **Multi-site Configuration**: The nginx-multisite cookbook uses Chef attributes to define multiple sites. In Ansible, this should be implemented using host_vars or group_vars with loops in templates.
- **Service Dependencies**: The fastapi-tutorial cookbook sets up dependencies between services (PostgreSQL, FastAPI app). Ansible handlers and meta dependencies will need to be carefully configured.
- **Template Conversion**: All ERB templates need to be converted to Jinja2 format for Ansible.
- **Idempotency**: Ensure all custom commands remain idempotent when converted to Ansible tasks.

### Migration Order

1. **cache** (Priority 1): Lowest complexity, minimal dependencies
   - Create roles for memcached and redis
   - Implement Ansible Vault for Redis password

2. **nginx-multisite** (Priority 2): Medium complexity
   - Create nginx role with SSL, security, and multi-site support
   - Convert ERB templates to Jinja2
   - Implement firewall and fail2ban configurations

3. **fastapi-tutorial** (Priority 3): Highest complexity
   - Create roles for Python application deployment
   - Implement PostgreSQL configuration
   - Set up systemd service management

### Assumptions

1. The target environment will continue to be Fedora 42 or compatible Linux distributions.
2. Self-signed certificates are acceptable for development; production may require integration with Let's Encrypt or other certificate providers.
3. The same network configuration (ports, IPs) will be maintained.
4. The FastAPI application source will continue to be pulled from the same Git repository.
5. Redis and PostgreSQL passwords currently hardcoded will be moved to Ansible Vault.
6. The current multi-site configuration pattern will be preserved in the Ansible inventory structure.
7. No changes to the application functionality are required during migration.