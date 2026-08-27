# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure configuration for a multi-site Nginx web server setup with FastAPI application backend and caching services (Redis and Memcached). The migration scope is moderate, consisting of 3 local cookbooks with dependencies on 4 external cookbooks. The estimated timeline for migration is 2-3 weeks for a single engineer, or 1 week with a team of 2-3 engineers working in parallel.

The repository is well-structured with clear separation of concerns between web serving (nginx-multisite), application deployment (fastapi-tutorial), and caching services (cache). The migration complexity is moderate, with security configurations and SSL certificate management requiring special attention.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx with multiple SSL-enabled virtual hosts, security hardening, and site configurations
    - Path: cookbooks/nginx-multisite
    - Technology: Chef
    - Key Features: Multi-site configuration, SSL setup, security hardening (fail2ban, ufw)

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI Python application with PostgreSQL database backend
    - Path: cookbooks/fastapi-tutorial
    - Technology: Chef
    - Key Features: Python virtual environment setup, PostgreSQL database configuration, systemd service management

- **cache**:
    - Description: Configures caching services (Memcached and Redis) with security settings
    - Path: cookbooks/cache
    - Technology: Chef
    - Key Features: Redis with password authentication, Memcached configuration

### Infrastructure Files

- `Berksfile`: Dependency management file listing local and external cookbooks
- `Policyfile.rb`: Chef policy file defining the run list and cookbook dependencies
- `Policyfile.lock.json`: Locked versions of cookbook dependencies
- `solo.json`: Node attributes and run list for Chef Solo
- `solo.rb`: Chef Solo configuration file
- `Vagrantfile`: Vagrant configuration for local development/testing
- `vagrant-provision.sh`: Shell script for provisioning the Vagrant VM with Chef

### Target Details

Based on the source configuration files:

- **Operating System**: Supports both Ubuntu (>= 18.04) and CentOS (>= 7.0) as specified in cookbook metadata, but the Vagrantfile uses Fedora 42
- **Virtual Machine Technology**: Vagrant with libvirt provider
- **Cloud Platform**: Not specified, appears to be designed for on-premises or generic cloud VMs

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0)**: Replace with Ansible nginx role or nginx_core module
- **ssl_certificate (~> 2.1)**: Replace with Ansible openssl_* modules for certificate management
- **memcached (~> 6.0)**: Replace with Ansible memcached module or community.general.memcached module
- **redisio (~> 7.2.4)**: Replace with Ansible redis module or community.general.redis module

### Security Considerations

- **SSL Certificate Management**: The nginx-multisite cookbook manages SSL certificates for multiple sites. Migration should use Ansible's `openssl_certificate`, `openssl_csr`, and `openssl_privatekey` modules.
- **Firewall Configuration**: The security recipe configures UFW. Migration should use Ansible's `ufw` module.
- **Fail2ban Configuration**: Security hardening includes fail2ban setup. Migration should use Ansible's `fail2ban` module or tasks.
- **SSH Hardening**: SSH configuration disables root login and password authentication. Migration should use Ansible's `lineinfile` or templates for SSH configuration.
- **Vault/secrets management**:
  - Redis password in cache cookbook: "redis_secure_password_123" (hardcoded)
  - PostgreSQL database credentials in fastapi-tutorial cookbook: username "fastapi" with password "fastapi_password" (hardcoded)
  - Total credentials detected: 2 hardcoded passwords

### Technical Challenges

- **Multi-site Configuration**: The nginx-multisite cookbook dynamically creates site configurations based on node attributes. Migration should use Ansible templates with loops over site variables.
- **SSL Certificate Generation**: SSL certificate management may require additional Ansible modules or roles for proper implementation.
- **Service Dependencies**: The FastAPI application depends on PostgreSQL, and the nginx configuration depends on the FastAPI service being available. Migration should maintain these dependencies using Ansible handlers and conditionals.
- **Redis Configuration Hack**: The cache cookbook includes a ruby_block to modify Redis configuration files after they're created. Migration should handle this with proper Ansible templates.

### Migration Order

1. **cache** (Priority 1): Low complexity, minimal dependencies
   - Implement Redis and Memcached configuration
   - Address password security for Redis

2. **fastapi-tutorial** (Priority 2): Moderate complexity
   - Set up Python environment and dependencies
   - Configure PostgreSQL database
   - Deploy application and systemd service

3. **nginx-multisite** (Priority 3): Higher complexity, depends on fastapi-tutorial
   - Implement base Nginx configuration
   - Configure SSL certificates
   - Set up security features (fail2ban, ufw)
   - Create virtual host configurations for multiple sites

### Assumptions

1. The migration will maintain the same operating system compatibility (Ubuntu 18.04+ and CentOS 7+)
2. The Vagrant development environment will be preserved or replaced with an equivalent Ansible-based setup
3. SSL certificates are self-signed for development (based on Vagrant setup) but may need to support proper certificates in production
4. The current hardcoded credentials will be replaced with Ansible Vault or another secure secret management solution
5. The FastAPI application source code is external (cloned from GitHub) and not part of this migration
6. The current Chef setup is used for both development (via Vagrant) and potentially production environments
7. The migration will need to support the same multi-site configuration capability with dynamic site definitions
8. The current setup appears to be for internal services (.cluster.local domains) rather than public-facing websites