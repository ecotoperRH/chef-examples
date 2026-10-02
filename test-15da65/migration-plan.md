# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef-based infrastructure-as-code project** with **3 custom cookbooks** and **4 external cookbook dependencies**. The infrastructure provisions a multi-site Nginx reverse proxy with SSL termination, caching services (Redis and Memcached), and a FastAPI application backend with PostgreSQL.

**Scope**: 3 custom cookbooks + 4 external dependencies (nginx, memcached, redisio, ssl_certificate)  
**Complexity**: **Moderate** — The project has clear separation of concerns (web server, caching, application), but includes several security configurations, SSL certificate generation, and service orchestration that require careful translation.  
**Estimated Timeline**: **2-3 weeks** for a team of 2-3 engineers (1 week for core migration, 1 week for testing and validation, 1 week for documentation and knowledge transfer)

**Key Challenges**:
- External cookbook dependencies (nginx, memcached, redisio) must be replaced with Ansible equivalents or community roles
- Redis configuration includes a "HACK" workaround that needs investigation and proper handling
- Self-signed SSL certificate generation requires careful handling in Ansible
- Security hardening (fail2ban, UFW, SSH configuration, sysctl tuning) must be preserved
- FastAPI application deployment includes git cloning, Python virtual environments, and systemd service management

**Recommended Approach**: Migrate in dependency order (security → caching → web server → application), using Ansible roles to mirror the cookbook structure. Leverage Ansible Galaxy community roles for nginx, Redis, and Memcached where possible, but plan for custom role development for application-specific logic.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**nginx-multisite**:
- **Description**: Nginx reverse proxy with multi-site SSL/TLS termination, self-signed certificate generation, and security hardening (fail2ban, UFW, SSH lockdown, sysctl tuning). Serves three subdomains (test.cluster.local, ci.cluster.local, status.cluster.local) with separate document roots and SSL-enabled virtual hosts.
- **Path**: cookbooks/nginx-multisite
- **Technology**: Chef
- **Key Features**: 
  - Nginx package installation and service management
  - Multi-site configuration with ERB templating (nginx.conf, site.conf, security.conf)
  - Self-signed SSL certificate generation via OpenSSL (365-day validity, RSA 2048-bit)
  - Fail2ban intrusion detection with custom jail configuration
  - UFW firewall with SSH, HTTP, HTTPS rules
  - SSH hardening (disable root login, disable password authentication)
  - Kernel parameter tuning via sysctl (security.conf)
  - Static HTML index files per site
  - Service reload notifications on configuration changes

**cache**:
- **Description**: Caching layer provisioning with Redis and Memcached. Configures Redis with authentication (requirepass), log directory management, and includes a workaround for Redis configuration file cleanup. Depends on external memcached and redisio cookbooks.
- **Path**: cookbooks/cache
- **Technology**: Chef
- **Key Features**:
  - Memcached installation and configuration (via external cookbook)
  - Redis installation with password authentication (redis_secure_password_123)
  - Redis log directory creation with proper ownership (redis:redis)
  - Redis configuration file cleanup via ruby_block (removes deprecated replica settings)
  - Redis service enablement and startup
  - External dependencies: memcached (~> 6.0), redisio (~> 7.2.4)

**fastapi-tutorial**:
- **Description**: FastAPI application deployment with Python runtime, PostgreSQL database, and systemd service management. Clones a FastAPI tutorial repository, creates Python virtual environment, installs dependencies, configures PostgreSQL user/database, and manages application lifecycle via systemd.
- **Path**: cookbooks/fastapi-tutorial
- **Technology**: Chef
- **Key Features**:
  - Python 3 runtime installation (python3, python3-pip, python3-venv)
  - Git repository cloning (https://github.com/dibanez/fastapi_tutorial.git, main branch)
  - Python virtual environment creation and dependency installation
  - PostgreSQL service enablement and startup
  - PostgreSQL user and database creation (fastapi user, fastapi_db database)
  - Environment configuration file (.env) with DATABASE_URL
  - Systemd service file generation for FastAPI application (uvicorn, port 8000)
  - Service enablement and startup

### Infrastructure Files

- **Berksfile**: Dependency manifest specifying local cookbooks (nginx-multisite, cache, fastapi-tutorial) and external Supermarket cookbooks (nginx ~> 12.0, memcached ~> 6.0, redisio ~> 7.2.4). Used by Berkshelf for dependency resolution.
- **Policyfile.rb**: Chef Policyfile defining the run list (nginx-multisite::default, cache::default, fastapi-tutorial::default) and cookbook versions. Provides deterministic dependency locking.
- **Policyfile.lock.json**: Lock file generated by Policyfile, pinning exact versions of all dependencies for reproducible deployments.
- **solo.rb**: Chef Solo configuration specifying cache path (/var/chef-solo), cookbook paths, and logging level (info to STDOUT).
- **solo.json**: Node attributes JSON file defining the run list and Nginx/security configuration (sites, SSL paths, fail2ban/UFW/SSH settings).
- **Vagrantfile**: Vagrant configuration for local development using Fedora 42 (libvirt provider), 2GB RAM, 2 CPUs, port forwarding (80→8080, 443→8443), and rsync folder sync.
- **vagrant-provision.sh**: Bash provisioning script that installs Chef, Berkshelf, downloads cookbook dependencies, and runs Chef Solo with solo.rb and solo.json.
- **project-plan.md**: Project specification document describing the X2Ansible migration tool architecture (not part of the infrastructure code, but provides context for the migration effort).

### Target Details

**Operating System**: 
- **Primary Target**: Fedora 42 (as specified in Vagrantfile)
- **Supported Platforms**: Ubuntu >= 18.04, CentOS >= 7.0 (as declared in cookbook metadata)
- **Recommendation for Ansible**: Target Fedora 42 for development/testing, but ensure playbooks support both Ubuntu and CentOS/RHEL for production flexibility

**Virtual Machine Technology**: 
- **Development**: libvirt (KVM) via Vagrant (2GB RAM, 2 CPUs)
- **Network**: Private network (192.168.121.10), port forwarding for HTTP/HTTPS
- **Sync Method**: rsync for cookbook synchronization

**Cloud Platform**: 
- **Not specified** — This is a local development environment. No cloud-specific configurations (AWS CLI, Azure tools, GCP SDK, cloud-init) are present. Ansible playbooks should be designed to work on-premises or in any cloud environment without cloud-specific dependencies.

---

## Migration Approach

### Key Dependencies to Address

**External Chef Cookbooks** (must be replaced or wrapped):
- **nginx (~> 12.0)**: Replace with Ansible nginx role from Ansible Galaxy (community.general.nginx or geerlingguy.nginx). The custom nginx-multisite cookbook extends this with multi-site configuration, so plan for a hybrid approach: use the Galaxy role for base installation, then layer custom site configuration via Ansible templates.
- **memcached (~> 6.0)**: Replace with Ansible memcached role from Ansible Galaxy (geerlingguy.memcached or community.general.memcached). Minimal custom configuration required.
- **redisio (~> 7.2.4)**: Replace with Ansible redis role from Ansible Galaxy (geerlingguy.redis or community.general.redis). Note: The cache cookbook includes a workaround (ruby_block) that removes deprecated Redis configuration options — this must be investigated and either applied as a post-install task or addressed in the role configuration.
- **ssl_certificate (~> 2.1)**: This cookbook is commented out in Berksfile but present in Policyfile.rb. The nginx-multisite cookbook generates self-signed certificates via OpenSSL commands, so this dependency may be unused. Verify before migration.

**System-Level Dependencies**:
- **OpenSSL**: Required for self-signed certificate generation (already present on target systems)
- **Git**: Required for FastAPI repository cloning
- **PostgreSQL**: Required for FastAPI database backend
- **Python 3**: Required for FastAPI application runtime

### Security Considerations

**SSH Hardening**:
- **Current Implementation**: Disables root login and password authentication via sed commands on /etc/ssh/sshd_config
- **Migration Approach**: Use Ansible lineinfile or template module to manage SSH configuration. Consider using community.general.sshd module for idempotent SSH configuration management.
- **Credentials**: No hardcoded SSH keys visible in reviewed files; assume key-based authentication is configured externally.

**Firewall Configuration**:
- **Current Implementation**: UFW (Uncomplicated Firewall) with default deny policy, explicit allow rules for SSH (22), HTTP (80), HTTPS (443)
- **Migration Approach**: Use Ansible ufw module to replicate firewall rules. Ensure idempotency (use `not_if` conditions in Chef → `state: enabled` in Ansible).

**Intrusion Detection**:
- **Current Implementation**: fail2ban with custom jail.local configuration (ERB template)
- **Migration Approach**: Use Ansible fail2ban role or community.general.fail2ban module. Migrate the jail.local template to Ansible jinja2 template.

**Kernel Security Parameters**:
- **Current Implementation**: sysctl tuning via /etc/sysctl.d/99-security.conf (ERB template)
- **Migration Approach**: Use Ansible sysctl module to apply kernel parameters. Migrate the sysctl-security.conf template to Ansible jinja2 template.

**Secrets Management**:
- **Redis Password**: Hardcoded in cache cookbook as `redis_secure_password_123` (plaintext in recipe)
  - **Risk**: Credentials visible in source code
  - **Migration Approach**: Move to Ansible vault or external secrets management (HashiCorp Vault, AWS Secrets Manager). Use `ansible-vault` to encrypt sensitive variables.
- **PostgreSQL Password**: Hardcoded in fastapi-tutorial cookbook as `fastapi_password` (plaintext in recipe)
  - **Risk**: Credentials visible in source code
  - **Migration Approach**: Move to Ansible vault or environment variables. Use `ansible-vault` to encrypt database credentials.
- **FastAPI Environment Variables**: DATABASE_URL and API_VERSION stored in .env file (plaintext on disk)
  - **Risk**: Credentials visible in deployed files
  - **Migration Approach**: Use Ansible template module with vault-encrypted variables, or integrate with external secrets management.

**SSL/TLS Certificates**:
- **Current Implementation**: Self-signed certificates generated via OpenSSL with 365-day validity, RSA 2048-bit
- **Migration Approach**: 
  - For development: Continue using self-signed certificates via Ansible openssl_certificate module
  - For production: Integrate with Let's Encrypt (certbot) or enterprise CA. Use community.general.certbot role or custom Ansible tasks.
- **Certificate Paths**: /etc/ssl/certs (public), /etc/ssl/private (private, restricted to ssl-cert group)
  - Ensure proper file permissions and ownership in Ansible (mode 0640, owner root:ssl-cert for private keys)

### Technical Challenges

**Challenge 1: Redis Configuration Workaround**
- **Description**: The cache cookbook includes a ruby_block that removes deprecated Redis configuration options (replica-serve-stale-data, replica-read-only, repl-ping-replica-period, client-output-buffer-limit, replica-priority). This suggests the redisio cookbook generates outdated configuration that needs cleanup.
- **Impact**: Without this workaround, Redis may fail to start or generate warnings.
- **Mitigation Strategy**: 
  1. Investigate the root cause: Does the redisio cookbook version (7.2.4) generate deprecated options?
  2. In Ansible, either:
     - Use a custom Redis role that generates correct configuration from the start
     - Apply a post-install task using lineinfile or template to remove deprecated options
     - Pin to a newer redisio version that doesn't generate deprecated options
  3. Test Redis startup and configuration validation in the Ansible playbook

**Challenge 2: External Cookbook Dependencies**
- **Description**: The project depends on 4 external Chef cookbooks (nginx, memcached, redisio, ssl_certificate). These must be replaced with Ansible equivalents or custom roles.
- **Impact**: Ansible Galaxy roles may have different configuration interfaces, defaults, and behavior than Chef cookbooks.
- **Mitigation Strategy**:
  1. Evaluate Ansible Galaxy roles for each dependency:
     - nginx: geerlingguy.nginx (well-maintained, widely used)
     - memcached: geerlingguy.memcached (well-maintained)
     - redis: geerlingguy.redis (well-maintained, but verify it doesn't generate deprecated options)
  2. Create a compatibility layer: Map Chef cookbook attributes to Ansible role variables
  3. Test each role independently before integrating into the full playbook
  4. Document any behavioral differences (e.g., service names, configuration paths, default ports)

**Challenge 3: Multi-Site Nginx Configuration**
- **Description**: The nginx-multisite cookbook dynamically generates site configurations for three subdomains (test.cluster.local, ci.cluster.local, status.cluster.local) using ERB templates and node attributes. Each site has its own document root, SSL certificate, and index.html file.
- **Impact**: Ansible must replicate this dynamic configuration generation without Chef's node attribute system.
- **Mitigation Strategy**:
  1. Define site configuration in Ansible variables (group_vars or host_vars):
     ```yaml
     nginx_sites:
       - name: test.cluster.local
         document_root: /var/www/test.cluster.local
         ssl_enabled: true
       - name: ci.cluster.local
         document_root: /var/www/ci.cluster.local
         ssl_enabled: true
       - name: status.cluster.local
         document_root: /var/www/status.cluster.local
         ssl_enabled: true
     ```
  2. Use Ansible loops (with_items or loop) to generate site configurations from templates
  3. Migrate ERB templates to Jinja2 templates (syntax is similar, but test thoroughly)
  4. Ensure proper file ownership (www-data:www-data) and permissions (0755 for directories, 0644 for files)

**Challenge 4: FastAPI Application Deployment**
- **Description**: The fastapi-tutorial cookbook clones a Git repository, creates a Python virtual environment, installs dependencies, configures PostgreSQL, and manages the application via systemd. This involves multiple sequential steps with interdependencies.
- **Impact**: Ansible must handle Git cloning, Python environment setup, and service management in the correct order with proper error handling.
- **Mitigation Strategy**:
  1. Create a dedicated Ansible role for FastAPI deployment (fastapi-tutorial)
  2. Use Ansible modules:
     - git: Clone the repository
     - pip: Install Python dependencies (use requirements.txt)
     - postgresql_user, postgresql_db: Create database and user (requires ansible-core >= 2.9)
     - template: Generate .env file with vault-encrypted variables
     - systemd: Manage service lifecycle
  3. Handle idempotency:
     - Use `creates` parameter for git clone (skip if directory exists)
     - Use `state: present` for database/user creation (idempotent)
     - Use `state: started` for service management (idempotent)
  4. Test the playbook multiple times to ensure idempotency

**Challenge 5: Secrets Management**
- **Description**: Hardcoded credentials in Chef recipes (Redis password, PostgreSQL password, FastAPI DATABASE_URL) must be moved to a secure secrets management system.
- **Impact**: Current approach exposes credentials in source code and deployed files, violating security best practices.
- **Mitigation Strategy**:
  1. Use Ansible Vault to encrypt sensitive variables:
     - Create `group_vars/all/vault.yml` with encrypted credentials
     - Reference vault variables in playbooks (e.g., `{{ vault_redis_password }}`)
  2. Implement a secrets rotation policy:
     - Document how to update vault-encrypted credentials
     - Provide scripts for automated credential rotation
  3. For production, integrate with external secrets management:
     - HashiCorp Vault: Use ansible-vault plugin or community.hcp_vault module
     - AWS Secrets Manager: Use community.aws.secretsmanager module
     - Azure Key Vault: Use community.azure.azure_keyvault module
  4. Ensure proper file permissions on vault files (0600, readable only by Ansible user)

**Challenge 6: Service Orchestration and Notifications**
- **Description**: Chef uses `notifies` to trigger service reloads/restarts when configuration changes. Ansible must replicate this behavior using handlers.
- **Impact**: Without proper handlers, configuration changes may not take effect until manual service restart.
- **Mitigation Strategy**:
  1. Create Ansible handlers for each service:
     - nginx reload/restart
     - fail2ban restart
     - ssh restart
     - fastapi-tutorial restart
  2. Use `notify` in tasks to trigger handlers:
     ```yaml
     - name: Update nginx configuration
       template:
         src: nginx.conf.j2
         dest: /etc/nginx/nginx.conf
       notify: reload nginx
     ```
  3. Ensure handlers run at the end of the playbook (default behavior)
  4. Test handler execution by running the playbook multiple times

### Migration Order

**Recommended migration sequence** (based on dependencies and complexity):

1. **security** (Priority 1 - Foundation)
   - **Rationale**: Security hardening (SSH, UFW, sysctl) should be applied first to establish a secure baseline
   - **Risk**: Low — straightforward configuration management
   - **Value**: High — enables secure access to other services
   - **Effort**: 2-3 days
   - **Dependencies**: None (system-level only)

2. **cache** (Priority 2 - Infrastructure)
   - **Rationale**: Caching services (Redis, Memcached) are infrastructure dependencies for the web server and application
   - **Risk**: Moderate — requires investigation of Redis configuration workaround
   - **Value**: High — enables application performance optimization
   - **Effort**: 3-4 days (includes testing Redis configuration)
   - **Dependencies**: security (optional, but recommended)

3. **nginx-multisite** (Priority 3 - Web Server)
   - **Rationale**: Nginx reverse proxy is the primary entry point for the infrastructure
   - **Risk**: Moderate — multi-site configuration and SSL certificate generation require careful testing
   - **Value**: High — enables web service delivery
   - **Effort**: 4-5 days (includes template migration and multi-site testing)
   - **Dependencies**: security, cache (optional)

4. **fastapi-tutorial** (Priority 4 - Application)
   - **Rationale**: FastAPI application is the final component, depends on all infrastructure services
   - **Risk**: Moderate — involves Git cloning, Python environment, and PostgreSQL configuration
   - **Value**: High — enables application deployment
   - **Effort**: 3-4 days (includes testing application startup and database connectivity)
   - **Dependencies**: security, cache, nginx-multisite

**Total Estimated Effort**: 12-16 days of development + 3-5 days of testing and validation = **2-3 weeks** for a team of 2-3 engineers

---

## Assumptions

1. **Ansible Version**: Assumes Ansible >= 2.9 (required for postgresql_user, postgresql_db modules). If using older Ansible, these modules must be installed via community.postgresql collection.

2. **Target Environment**: Assumes the Ansible control node has network access to target hosts and can execute tasks with sudo privileges. SSH key-based authentication is configured.

3. **Secrets Management**: Assumes the team will implement Ansible Vault or external secrets management (HashiCorp Vault, AWS Secrets Manager) for credential storage. Current Chef implementation uses plaintext credentials, which is a security risk.

4. **External Cookbook Replacement**: Assumes Ansible Galaxy roles (geerlingguy.nginx, geerlingguy.memcached, geerlingguy.redis) are acceptable replacements for Chef cookbooks. If not, custom Ansible roles must be developed.

5. **Redis Configuration Workaround**: Assumes the ruby_block workaround in the cache cookbook is necessary due to deprecated options in the redisio cookbook. This must be investigated and either replicated in Ansible or addressed by using a newer cookbook/role version.

6. **SSL Certificates**: Assumes self-signed certificates are acceptable for development/testing. For production, assumes the team will integrate with Let's Encrypt or enterprise CA.

7. **PostgreSQL User/Database Creation**: Assumes the PostgreSQL service is running and accessible locally. The fastapi-tutorial cookbook uses `sudo -u postgres psql` commands, which assumes the postgres user exists and has sudo privileges.

8. **Git Repository Availability**: Assumes the FastAPI tutorial repository (https://github.com/dibanez/fastapi_tutorial.git) remains publicly accessible and the main branch is stable. If the repository is private or changes frequently, additional configuration may be required.

9. **Python Virtual Environment**: Assumes Python 3 is available on target systems and pip can install packages from PyPI. If target systems have restricted internet access, a local package mirror or pre-built virtual environment must be provided.

10. **Idempotency**: Assumes all Ansible tasks are designed to be idempotent (safe to run multiple times without side effects). This requires careful use of `creates`, `state`, and conditional checks.

11. **Testing Environment**: Assumes the team will use Vagrant with libvirt for local testing before deploying to production. Vagrant configuration must be updated to use Ansible provisioner instead of Chef Solo.

12. **Documentation**: Assumes the team will maintain comprehensive documentation of the migration process, including:
    - Mapping of Chef cookbooks to Ansible roles
    - Variable naming conventions
    - Secrets management procedures
    - Testing and validation procedures
    - Rollback procedures

13. **Backward Compatibility**: Assumes the team does not need to maintain Chef cookbooks alongside Ansible playbooks. If parallel operation is required, additional coordination and testing is needed.

14. **Fedora 42 Specifics**: Assumes Fedora 42 is the target OS for development/testing. If production uses different OS (Ubuntu, CentOS, RHEL), playbooks must be tested on those platforms to ensure compatibility.

15. **Fail2ban Configuration**: Assumes the fail2ban.jail.local.erb template is available and can be migrated to Jinja2 format. If the template is complex or uses Chef-specific features, additional investigation may be required.

16. **Sysctl Configuration**: Assumes the sysctl-security.conf.erb template contains standard kernel parameters that can be migrated to Ansible sysctl module. If the template uses Chef-specific features, additional investigation may be required.

17. **Service Names**: Assumes service names are consistent across target OS versions (e.g., `nginx`, `redis`, `memcached`, `postgresql`, `ssh`, `fail2ban`). If service names differ, playbooks must include OS-specific conditionals.

18. **Package Names**: Assumes package names are consistent across target OS versions. If package names differ (e.g., `postgresql` vs `postgresql-server`), playbooks must include OS-specific conditionals or use package manager abstractions.

19. **File Paths**: Assumes file paths are consistent across target OS versions (e.g., `/etc/nginx/nginx.conf`, `/etc/redis/6379.conf`, `/etc/fail2ban/jail.local`). If paths differ, playbooks must include OS-specific conditionals.

20. **User/Group Names**: Assumes user and group names are consistent across target OS versions (e.g., `www-data` for Nginx, `redis` for Redis, `postgres` for PostgreSQL). If names differ (e.g., `nginx` instead of `www-data`), playbooks must include OS-specific conditionals.

---

## Next Steps

1. **Immediate**: Review this migration plan with the team and stakeholders. Identify any additional requirements, constraints, or dependencies not captured in this analysis.

2. **Week 1**: 
   - Set up Ansible development environment (control node, test inventory)
   - Create Ansible project structure (roles, playbooks, group_vars, host_vars)
   - Implement security role (SSH, UFW, sysctl hardening)
   - Begin cache role development (Redis, Memcached)

3. **Week 2**:
   - Complete cache role and testing
   - Implement nginx-multisite role (multi-site configuration, SSL certificates)
   - Migrate ERB templates to Jinja2
   - Test multi-site configuration and SSL certificate generation

4. **Week 3**:
   - Implement fastapi-tutorial role (Git cloning, Python environment, PostgreSQL, systemd)
   - Integrate all roles into a master playbook
   - Implement Ansible Vault for secrets management
   - Comprehensive testing and validation

5. **Post-Migration**:
   - Document the migration process and lessons learned
   - Provide team training on Ansible playbook maintenance
   - Establish procedures for credential rotation and secrets management
   - Plan for deprecation of Chef cookbooks (if applicable)
