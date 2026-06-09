# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure for deploying a multi-site Nginx configuration with caching services (Redis and Memcached) and a FastAPI application backed by PostgreSQL. The migration to Ansible will require converting 3 Chef cookbooks with their recipes, templates, and attributes to equivalent Ansible roles and playbooks.

**Estimated Timeline:** 3-4 weeks
**Complexity:** Medium to High
**Key Challenges:** Nginx multi-site SSL configuration, security hardening, and service integration

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening, and fail2ban/ufw integration
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL certificate generation, security headers, rate limiting, firewall configuration

- **cache**:
    - Description: Caching services configuration including Memcached and Redis with authentication
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis password authentication, Memcached configuration

- **fastapi-tutorial**:
    - Description: Python FastAPI application deployment with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment, Git repository deployment, PostgreSQL database setup, systemd service configuration

### Infrastructure Files

- `Berksfile`: Chef dependency manager file listing cookbook dependencies (nginx, ssl_certificate, memcached, redisio)
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Vagrantfile`: Vagrant configuration for local development using Fedora 42
- `vagrant-provision.sh`: Bash script for provisioning the Vagrant VM with Chef
- `solo.json`: Chef configuration data with site definitions and security settings
- `solo.rb`: Chef solo configuration file

### Target Details

- **Operating System**: Fedora 42 (based on Vagrantfile), with support for Ubuntu 18.04+ and CentOS 7+ (based on cookbook metadata)
- **Virtual Machine Technology**: Libvirt (based on Vagrantfile provider configuration)
- **Cloud Platform**: Not specified, appears to be designed for on-premises deployment

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role (e.g., geerlingguy.nginx)
- **ssl_certificate (~> 2.1)**: Replace with Ansible certificate management tasks or community.crypto collection
- **memcached (~> 6.0)**: Replace with Ansible memcached role (e.g., geerlingguy.memcached)
- **redisio (~> 7.2.4)**: Replace with Ansible Redis role (e.g., geerlingguy.redis)

### Security Considerations

- **SSL/TLS Configuration**: The migration must maintain the same TLS protocols (TLSv1.2, TLSv1.3) and cipher suites
- **Firewall Rules**: UFW configuration must be migrated to equivalent Ansible UFW module tasks
- **Fail2ban**: Configuration must be preserved in Ansible format
- **SSH Hardening**: SSH security settings (disable root login, password authentication) must be maintained
- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123" (hardcoded)
  - PostgreSQL credentials in fastapi-tutorial cookbook: username "fastapi" with password "fastapi_password" (hardcoded)
  - SSL certificates and private keys (generated during deployment)
  - Total credentials detected: 3 sets (Redis, PostgreSQL, SSL)

### Technical Challenges

- **Nginx Multi-site Configuration**: The current Chef implementation uses templates to generate site configurations. Ansible will need equivalent template handling for multiple virtual hosts.
- **SSL Certificate Generation**: Self-signed certificate generation logic needs to be replicated in Ansible, potentially using the community.crypto collection.
- **Security Hardening**: The comprehensive security measures (headers, rate limiting, firewall) must be carefully migrated to maintain the same security posture.
- **Service Integration**: The FastAPI application depends on PostgreSQL and potentially the cache services. These dependencies must be maintained in the Ansible playbook ordering.

### Migration Order

1. **cache role** (Low complexity, foundational service)
   - Implement Memcached configuration
   - Implement Redis with authentication

2. **nginx-multisite role** (Medium complexity, core infrastructure)
   - Implement base Nginx configuration
   - Implement SSL certificate generation
   - Implement virtual host configuration
   - Implement security hardening (headers, rate limiting)
   - Implement firewall and fail2ban configuration

3. **fastapi-tutorial role** (High complexity, application layer)
   - Implement PostgreSQL installation and configuration
   - Implement Python environment setup
   - Implement application deployment from Git
   - Implement systemd service configuration

### Assumptions

1. The target environment will continue to be Fedora-based (or compatible with the existing configuration)
2. Self-signed certificates are acceptable for the migrated solution (production would likely use Let's Encrypt or other CA)
3. The same security posture is required in the Ansible implementation
4. Hardcoded credentials in the Chef recipes will be replaced with Ansible Vault variables
5. The FastAPI application source repository (https://github.com/dibanez/fastapi_tutorial.git) will remain available
6. The Nginx configuration requires special attention as highlighted in the user requirements
7. The existing directory structure for web content (/var/www/[site]) will be maintained
8. The existing security configurations (fail2ban, ufw, SSH hardening) are required in the migrated solution