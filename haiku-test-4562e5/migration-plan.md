# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef-based infrastructure-as-code project** with 3 custom cookbooks and 4 external dependencies. The project provisions a multi-site Nginx reverse proxy with SSL/TLS termination, security hardening (fail2ban, UFW, SSH lockdown), caching services (Memcached and Redis), and a FastAPI application backend with PostgreSQL.

**Migration Scope**: Low to moderate complexity. The codebase is well-structured with clear separation of concerns (security, nginx, SSL, sites, caching, application). Most configurations are straightforward package installations, service management, and template rendering—all of which map cleanly to Ansible.

**Estimated Timeline**: 2-3 weeks for a team of 2-3 engineers:
- Week 1: Dependency analysis, Ansible role scaffolding, and security/nginx role migration
- Week 2: Cache and FastAPI role migration, testing, and validation
- Week 3: Integration testing, documentation, and production readiness

**Key Risks**:
1. **Hardcoded credentials** in FastAPI recipe (database password, Redis password)
2. **Self-signed certificate generation** logic requires careful translation to Ansible
3. **Redis configuration workaround** (ruby_block hack) needs refactoring
4. **External cookbook dependencies** (nginx ~12.0, memcached ~6.0, redisio ~7.2.4) must be replaced with Ansible equivalents or community roles

**Strategic Recommendation**: Migrate in phases—start with security and nginx roles (highest value, lowest risk), then move to caching and application layers. Use Ansible Galaxy roles for external dependencies where available to reduce custom code.

---

## Module Migration Plan

This repository contains **Chef cookbooks** that need individual migration planning:

### MODULE INVENTORY

**nginx-multisite**:
- **Description**: Nginx reverse proxy with multi-site SSL/TLS termination, security hardening (fail2ban, UFW, SSH lockdown), and self-signed certificate generation for development environments
- **Path**: `cookbooks/nginx-multisite`
- **Technology**: Chef
- **Key Features**: 
  - Nginx package installation and service management
  - Multi-site configuration with ERB templates (nginx.conf, site.conf)
  - Self-signed SSL certificate generation via OpenSSL
  - Fail2ban intrusion detection with custom jail configuration
  - UFW firewall with port-based rules (SSH, HTTP, HTTPS)
  - SSH hardening (disable root login, disable password authentication)
  - Sysctl security tuning via template
  - Document root creation and index.html deployment
  - Service reload notifications on configuration changes
- **Recipes**: default.rb (orchestrator), nginx.rb (package + service), security.rb (fail2ban + UFW + SSH + sysctl), ssl.rb (certificate generation), sites.rb (vhost configuration)
- **Attributes**: 3 sites (test.cluster.local, ci.cluster.local, status.cluster.local), SSL paths, security flags
- **Templates**: nginx.conf.erb, security.conf.erb, site.conf.erb, fail2ban.jail.local.erb, sysctl-security.conf.erb
- **Supported OS**: Ubuntu ≥18.04, CentOS ≥7.0

**cache**:
- **Description**: Caching layer provisioning with Memcached and Redis, including Redis authentication and configuration workaround for deprecated replica settings
- **Path**: `cookbooks/cache`
- **Technology**: Chef
- **Key Features**:
  - Memcached installation and service management (via external cookbook dependency)
  - Redis installation with authentication (requirepass: redis_secure_password_123)
  - Redis log directory creation with proper ownership
  - Redis configuration file cleanup (ruby_block hack to remove deprecated replica settings)
  - Redis service enablement
- **Dependencies**: memcached ~6.0, redisio ~7.2.4 (external Supermarket cookbooks)
- **Security Concerns**: Hardcoded Redis password in recipe (redis_secure_password_123)
- **Supported OS**: Ubuntu ≥18.04, CentOS ≥7.0

**fastapi-tutorial**:
- **Description**: FastAPI application deployment with Python virtual environment, PostgreSQL database setup, and systemd service management
- **Path**: `cookbooks/fastapi-tutorial`
- **Technology**: Chef
- **Key Features**:
  - Python 3 runtime installation (python3, python3-pip, python3-venv)
  - Git repository cloning (https://github.com/dibanez/fastapi_tutorial.git, main branch)
  - Python virtual environment creation
  - Pip dependency installation from requirements.txt
  - PostgreSQL service enablement and startup
  - PostgreSQL user and database creation with privilege grants
  - .env file generation with database connection string
  - Systemd service file creation for FastAPI application
  - Service enablement and startup
  - Uvicorn ASGI server configuration (host 0.0.0.0, port 8000)
- **Security Concerns**: 
  - Hardcoded database password (fastapi_password) in recipe and .env file
  - Hardcoded database credentials in environment variables
  - .env file created with mode 0644 (world-readable)
- **Supported OS**: Ubuntu ≥18.04, CentOS ≥7.0

---

### Infrastructure Files

- **Berksfile**: Dependency manifest specifying local cookbooks (nginx-multisite, cache, fastapi-tutorial) and external Supermarket cookbooks (nginx ~12.0, memcached ~6.0, redisio ~7.2.4). Used by Berkshelf to resolve and vendor dependencies.

- **Policyfile.rb**: Chef Policyfile defining the run_list (nginx-multisite::default, cache::default, fastapi-tutorial::default) and cookbook versions. Provides deterministic dependency locking for production deployments.

- **Policyfile.lock.json**: Locked dependency versions generated by `berks lock` or `chef install`. Ensures reproducible builds across environments.

- **solo.rb**: Chef Solo configuration specifying cache path (/var/chef-solo), cookbook paths, log level, and output destination. Used by chef-solo for standalone provisioning without a Chef Server.

- **solo.json**: Chef Solo run-list and node attributes in JSON format. Defines the run_list and overrides default attributes for nginx sites, SSL paths, and security settings.

- **Vagrantfile**: Vagrant VM configuration using libvirt provider (Fedora 42 box, 2GB RAM, 2 CPUs). Configures port forwarding (80→8080, 443→8443), rsync folder sync, and shell provisioning via vagrant-provision.sh.

- **vagrant-provision.sh**: Bootstrap script for Vagrant VM. Installs Chef, Berkshelf, downloads cookbook dependencies, and runs chef-solo with solo.rb and solo.json.

- **project-plan.md**: Project specification for X2Ansible migration tool (not part of the infrastructure code; describes the tool's architecture and workflow).

---

### Target Details

**Operating System**: 
- **Primary**: Ubuntu 18.04 LTS or later (based on Vagrantfile generic/fedora42 and metadata.rb supports)
- **Secondary**: CentOS 7.0 or later (listed in metadata.rb)
- **Inference**: The Vagrantfile uses Fedora 42 (libvirt), but cookbooks support Ubuntu and CentOS. Recommend **Ubuntu 20.04 LTS or 22.04 LTS** as primary target for Ansible migration (widely supported, long-term support, consistent with cookbook metadata).

**Virtual Machine Technology**: 
- **Vagrant with libvirt provider** (KVM/QEMU hypervisor on Linux)
- **Inference**: Vagrantfile specifies `config.vm.provider "libvirt"` with memory and CPU allocation. This is Linux-native virtualization (not VMware, VirtualBox, or Hyper-V).
- **For Ansible**: Assume bare-metal or cloud VMs (AWS EC2, Azure VMs, GCP Compute Engine) as primary targets; libvirt is development-only.

**Cloud Platform**: 
- **Not specified** in the repository. No cloud-specific configurations (AWS CLI, Azure tools, GCP SDK, cloud-init, metadata endpoints) detected.
- **Recommendation**: Design Ansible playbooks to be cloud-agnostic; use standard Linux package managers and systemd. If cloud deployment is required, add cloud-specific roles (e.g., AWS security groups, Azure NSGs) as separate optional roles.

---

## Migration Approach

### Key Dependencies to Address

1. **nginx ~12.0** (Supermarket cookbook):
   - **Current Role**: Provides nginx package installation, service management, and configuration templates
   - **Ansible Solution**: Use `ansible.builtin.package` module for nginx installation; replace with Ansible Galaxy role `geerlingguy.nginx` (community-maintained, production-ready) or custom role using templates
   - **Migration Strategy**: Evaluate geerlingguy.nginx compatibility with multi-site configuration; if incompatible, create custom Ansible role mirroring current Chef logic

2. **memcached ~6.0** (Supermarket cookbook):
   - **Current Role**: Memcached package installation and service management
   - **Ansible Solution**: Use `ansible.builtin.package` module for memcached; optionally use Ansible Galaxy role `geerlingguy.memcached`
   - **Migration Strategy**: Simple package + service; low risk. Inline in cache role or use Galaxy role.

3. **redisio ~7.2.4** (Supermarket cookbook):
   - **Current Role**: Redis package installation, configuration, and service management
   - **Ansible Solution**: Use `ansible.builtin.package` module for redis-server; optionally use Ansible Galaxy role `geerlingguy.redis`
   - **Migration Strategy**: Moderate complexity due to configuration file manipulation (ruby_block hack). Refactor as Ansible template or use Galaxy role with custom configuration.

4. **ssl_certificate ~2.1** (Supermarket cookbook, commented out in Berksfile):
   - **Current Role**: SSL certificate management (not actively used; self-signed certs generated via openssl execute)
   - **Ansible Solution**: Use `ansible.builtin.openssl_certificate` module or `community.crypto.x509_certificate` for certificate generation
   - **Migration Strategy**: Not required for current deployment; skip unless production certificate management is needed.

### Security Considerations

1. **Hardcoded Credentials**:
   - **Redis Password** (cache/recipes/default.rb): `requirepass: 'redis_secure_password_123'`
   - **FastAPI Database Password** (fastapi-tutorial/recipes/default.rb): `fastapi_password` in .env file and PostgreSQL user creation
   - **Migration Approach**: 
     - Use Ansible Vault for credential storage (encrypt sensitive variables in group_vars or host_vars)
     - Create separate vars files for secrets (e.g., `group_vars/all/vault.yml`)
     - Use `ansible-vault encrypt` to protect credentials at rest
     - Document credential rotation procedures for operations team

2. **SSH Hardening**:
   - **Current Configuration** (nginx-multisite/recipes/security.rb):
     - Disable root login (PermitRootLogin no)
     - Disable password authentication (PasswordAuthentication no)
   - **Migration Approach**: 
     - Translate sed commands to Ansible `lineinfile` module
     - Use `ansible.builtin.lineinfile` with `regexp` and `line` parameters
     - Notify SSH service restart on changes
     - Ensure SSH key-based authentication is pre-configured before disabling passwords

3. **Firewall Configuration**:
   - **Current Configuration** (nginx-multisite/recipes/security.rb):
     - UFW firewall with default deny policy
     - Allow SSH (22), HTTP (80), HTTPS (443)
   - **Migration Approach**:
     - Use `community.general.ufw` Ansible module for UFW rules
     - Or use `ansible.builtin.firewalld` module if firewalld is preferred
     - Ensure idempotency (use `not_if` conditions to prevent duplicate rules)

4. **Fail2ban Configuration**:
   - **Current Configuration** (nginx-multisite/recipes/security.rb):
     - Fail2ban installation and service management
     - Custom jail configuration via fail2ban.jail.local.erb template
   - **Migration Approach**:
     - Use `ansible.builtin.package` for fail2ban installation
     - Use `ansible.builtin.template` to deploy fail2ban.jail.local configuration
     - Notify fail2ban service restart on configuration changes

5. **SSL/TLS Certificates**:
   - **Current Configuration** (nginx-multisite/recipes/ssl.rb):
     - Self-signed certificate generation via openssl execute
     - Certificates stored in /etc/ssl/certs and /etc/ssl/private
     - Certificate permissions: 0644 for certs, 0640 for keys (owned by root:ssl-cert)
   - **Migration Approach**:
     - Use `community.crypto.x509_certificate` module for self-signed certificate generation
     - Or use `ansible.builtin.openssl_certificate` module (built-in, limited features)
     - Ensure proper file permissions and ownership
     - For production: integrate with Let's Encrypt via `community.crypto.acme_certificate` module

6. **Environment Variable Secrets**:
   - **Current Configuration** (fastapi-tutorial/recipes/default.rb):
     - DATABASE_URL with credentials in .env file (mode 0644, world-readable)
   - **Migration Approach**:
     - Use Ansible Vault to encrypt .env file content
     - Deploy .env file with restricted permissions (0600)
     - Use `ansible.builtin.template` with `mode: '0600'` to ensure secure permissions
     - Consider using systemd environment files with restricted permissions instead of .env

---

### Technical Challenges

1. **Redis Configuration Workaround (ruby_block hack)**:
   - **Challenge**: Cache cookbook uses ruby_block to remove deprecated Redis replica settings from /etc/redis/6379.conf
   - **Root Cause**: redisio cookbook generates config with deprecated settings; ruby_block removes them post-generation
   - **Ansible Migration Strategy**:
     - Option A: Use `ansible.builtin.lineinfile` module to remove deprecated lines directly
     - Option B: Use `ansible.builtin.template` to generate clean Redis config from scratch (preferred)
     - Option C: Use Ansible Galaxy role `geerlingguy.redis` which may handle this automatically
     - **Recommendation**: Option B (template-based) for clarity and maintainability

2. **Self-Signed Certificate Generation Logic**:
   - **Challenge**: nginx-multisite/recipes/ssl.rb generates certificates per site with complex openssl command
   - **Complexity**: Multi-line command with variable substitution, conditional execution (not_if), and service notifications
   - **Ansible Migration Strategy**:
     - Use `community.crypto.x509_certificate` module (preferred, idempotent)
     - Or use `ansible.builtin.openssl_certificate` module (built-in, simpler)
     - Create a loop over sites to generate certificates for each domain
     - Ensure proper error handling if certificate generation fails
     - **Recommendation**: Use community.crypto module for production-grade certificate management

3. **External Cookbook Dependencies**:
   - **Challenge**: Berksfile specifies nginx ~12.0, memcached ~6.0, redisio ~7.2.4 from Supermarket
   - **Complexity**: These cookbooks may have their own dependencies, version constraints, and platform-specific logic
   - **Ansible Migration Strategy**:
     - Option A: Use Ansible Galaxy roles (geerlingguy.nginx, geerlingguy.memcached, geerlingguy.redis)
     - Option B: Inline package installation and configuration in custom roles
     - Option C: Hybrid approach (use Galaxy roles where available, custom roles for complex logic)
     - **Recommendation**: Start with Galaxy roles for rapid migration; refactor to custom roles if needed for specific requirements

4. **Vagrant/Development Environment**:
   - **Challenge**: Vagrantfile uses libvirt provider (KVM/QEMU); Ansible typically targets production VMs or cloud instances
   - **Complexity**: Vagrant provisioning workflow differs from Ansible playbook execution
   - **Ansible Migration Strategy**:
     - Create Ansible playbooks for production deployment (separate from Vagrant)
     - Optionally create Vagrant provisioner using Ansible (instead of shell script)
     - Document both development (Vagrant) and production (Ansible) workflows
     - **Recommendation**: Use Ansible provisioner in Vagrantfile for consistency

5. **Git Repository Cloning in FastAPI Recipe**:
   - **Challenge**: fastapi-tutorial/recipes/default.rb clones external GitHub repository (https://github.com/dibanez/fastapi_tutorial.git)
   - **Complexity**: Dependency on external repository; version pinning via git revision (main branch)
     - **Risk**: main branch is mutable; production deployments should pin to specific commit or tag
   - **Ansible Migration Strategy**:
     - Use `ansible.builtin.git` module to clone repository
     - Pin to specific commit hash or tag (not main branch) for reproducibility
     - Add error handling for network failures or repository unavailability
     - Consider using artifact repository (Artifactory, Nexus) for production deployments
     - **Recommendation**: Pin to specific commit hash; document version management process

6. **Python Virtual Environment Management**:
   - **Challenge**: fastapi-tutorial/recipes/default.rb creates venv and installs dependencies via pip
   - **Complexity**: Dependency on external requirements.txt file; pip version management
   - **Ansible Migration Strategy**:
     - Use `ansible.builtin.pip` module with `virtualenv` parameter
     - Or use `ansible.builtin.command` module to run python3 -m venv and pip install
     - Ensure Python 3 is installed before venv creation
     - Consider using Python 3.10+ for better performance and security
     - **Recommendation**: Use ansible.builtin.pip module with virtualenv parameter for idempotency

7. **Systemd Service File Generation**:
   - **Challenge**: fastapi-tutorial/recipes/default.rb generates systemd service file via Chef file resource
   - **Complexity**: Multi-line service file with environment variables and ExecStart command
   - **Ansible Migration Strategy**:
     - Use `ansible.builtin.template` module to deploy systemd service file
     - Or use `ansible.builtin.copy` module with inline content
     - Notify systemd daemon-reload on file changes
     - Use `ansible.builtin.systemd` module to enable and start service
     - **Recommendation**: Use template module for flexibility and maintainability

---

### Migration Order

Based on dependency analysis and risk assessment, recommend the following migration sequence:

1. **Phase 1: Foundation (Week 1, Days 1-2)**
   - **nginx-multisite (security recipe)**: SSH hardening, UFW firewall, fail2ban, sysctl tuning
   - **Rationale**: Low risk, no external dependencies, foundational security layer
   - **Effort**: 1-2 days (straightforward package + service + template + lineinfile operations)
   - **Value**: Immediate security hardening; enables other services to run safely

2. **Phase 1: Core Services (Week 1, Days 3-5)**
   - **nginx-multisite (nginx + ssl + sites recipes)**: Nginx installation, SSL certificate generation, multi-site configuration
   - **Rationale**: Core infrastructure; moderate complexity (certificate generation, template rendering)
   - **Effort**: 2-3 days (certificate generation requires careful translation; multi-site loop logic)
   - **Value**: Web server provisioning; enables FastAPI and static site hosting

3. **Phase 2: Caching Layer (Week 2, Days 1-2)**
   - **cache**: Memcached and Redis installation, configuration, authentication
   - **Rationale**: Moderate complexity; depends on external cookbooks; hardcoded credentials require Vault integration
   - **Effort**: 1-2 days (package installation straightforward; Redis config workaround requires refactoring)
   - **Value**: Caching infrastructure; improves application performance

4. **Phase 2: Application Deployment (Week 2, Days 3-5)**
   - **fastapi-tutorial**: Python runtime, git clone, venv, pip install, PostgreSQL, systemd service
   - **Rationale**: Highest complexity; multiple dependencies (Python, PostgreSQL, git); hardcoded credentials
   - **Effort**: 2-3 days (git clone, venv, pip install, systemd service, credential management)
   - **Value**: Application provisioning; enables end-to-end testing

5. **Phase 3: Integration & Testing (Week 3)**
   - **End-to-end testing**: Verify all services work together (nginx → FastAPI → PostgreSQL → Redis/Memcached)
   - **Security validation**: Confirm SSH hardening, firewall rules, fail2ban, SSL/TLS
   - **Documentation**: Update runbooks, troubleshooting guides, credential rotation procedures
   - **Effort**: 3-5 days (testing, documentation, refinement)
   - **Value**: Production readiness; team knowledge transfer

---

### Assumptions

1. **Target OS**: Ansible playbooks will target Ubuntu 20.04 LTS or 22.04 LTS (or CentOS 8/9 equivalent). Vagrantfile uses Fedora 42, but production deployments assume Debian/Ubuntu or RHEL-based systems.

2. **Ansible Version**: Assumes Ansible 2.10+ (supports community.crypto, community.general modules). If older Ansible is required, some modules may need substitution.

3. **Credential Management**: Assumes Ansible Vault will be used for secrets (Redis password, FastAPI database password). Team must establish vault password management procedures (e.g., vault password file, CI/CD integration).

4. **External Dependencies**: Assumes Ansible Galaxy roles (geerlingguy.nginx, geerlingguy.memcached, geerlingguy.redis) are acceptable for production use. If not, custom roles must be created.

5. **Git Repository Stability**: Assumes https://github.com/dibanez/fastapi_tutorial.git repository remains available and stable. If repository is internal or private, access credentials must be configured.

6. **PostgreSQL Installation**: Assumes PostgreSQL will be installed via system package manager (apt/yum). If PostgreSQL is managed separately (e.g., RDS, managed service), FastAPI recipe logic must be adapted.

7. **SSL Certificates**: Assumes self-signed certificates are acceptable for development/testing. For production, assumes Let's Encrypt or internal CA will be used (requires additional Ansible roles/modules).

8. **Systemd Availability**: Assumes target systems use systemd for service management (standard on Ubuntu 18.04+, CentOS 7+). If older init systems are required, service management logic must be adapted.

9. **Network Configuration**: Assumes static IP configuration (192.168.121.10 in Vagrantfile) is not required for Ansible playbooks. Playbooks should be network-agnostic (use DHCP or cloud-provided IPs).

10. **Idempotency**: Assumes all Ansible tasks will be idempotent (safe to run multiple times). Chef recipes use `not_if` guards; Ansible equivalents must be carefully implemented to ensure idempotency.

11. **No Chef Server**: Assumes Chef Solo (standalone) provisioning model will be replaced with Ansible (agentless). No Chef Server integration required.

12. **Berkshelf Removal**: Assumes Berkshelf dependency management will be replaced with Ansible Galaxy and requirements.yml. Policyfile.lock.json will be discarded.

13. **Vagrant Provisioning**: Assumes Vagrant will be updated to use Ansible provisioner (instead of shell script). Alternatively, Vagrant can be deprecated in favor of cloud-based testing.

14. **Documentation**: Assumes current Chef cookbooks lack comprehensive documentation. Ansible playbooks should include inline comments, README files, and runbooks for operations team.

15. **Testing**: Assumes no automated tests (Test Kitchen, InSpec) currently exist. Ansible playbooks should be tested manually or with Molecule (Ansible testing framework).

---

## Summary

This Chef-based infrastructure repository is a **good candidate for Ansible migration**. The codebase is well-organized, uses standard patterns (package installation, service management, template rendering), and has clear separation of concerns. The main challenges are:

1. **Hardcoded credentials** (Redis, FastAPI database) → Solve with Ansible Vault
2. **External cookbook dependencies** → Solve with Ansible Galaxy roles or custom roles
3. **Complex certificate generation** → Solve with community.crypto module
4. **Redis configuration workaround** → Solve with template-based configuration

**Recommended approach**: Migrate in phases (security → nginx → cache → application), use Ansible Galaxy roles where available, and establish Vault-based credential management early. Estimated effort: 2-3 weeks for a team of 2-3 engineers.

**Next Steps**:
1. Set up Ansible project structure (roles, playbooks, inventory, group_vars)
2. Create Ansible Vault for credential storage
3. Begin Phase 1 migration (security role)
4. Establish testing and validation procedures
5. Document Ansible playbooks and operational procedures
