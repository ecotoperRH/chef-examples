# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a Fedora/Ubuntu/CentOS server running Nginx with multiple SSL-enabled virtual hosts, caching services (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL. The stack is currently exercised via Vagrant with a `libvirt` provider and a shell-based provisioner that invokes `chef-solo` with Berkshelf for dependency resolution.

The migration scope covers **3 local cookbooks** and **5 external Chef Supermarket dependencies**, all of which map cleanly to well-supported Ansible collections and modules. No Chef Server, encrypted data bags, or Chef Vault infrastructure is in use — the entire stack runs as Chef Solo — which significantly reduces migration complexity.

**Overall complexity: Medium.**
The primary challenges are the self-signed SSL certificate generation workflow, the Redis configuration post-processing hack, and the multi-site Nginx vhost loop that must be reproduced with Ansible's `loop` / `with_items` constructs. No exotic Chef resources or custom LWRPs are used beyond a single `lineinfile` resource stub.

**Estimated timeline: 2–3 weeks** for a single engineer, or 1–1.5 weeks with two engineers working in parallel on independent cookbooks.

**Current Status**: Partial migration already in progress. The `weqe-d92f93/` directory contains Ansible roles for `cache`, `fastapi-tutorial`, and `nginx-multisite` that have been generated from the Chef cookbooks. These roles are functional but require validation, testing, and integration into a unified playbook structure.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by 5 locked external Supermarket cookbooks that will be replaced by native Ansible modules and collections.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads. No paths have been inferred or invented.

---

#### **nginx-multisite**
- **Description**: Core Nginx web server cookbook that installs Nginx, deploys a hardened `nginx.conf`, configures three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), generates self-signed TLS certificates via `openssl`, deploys per-site static `index.html` files, configures `fail2ban` with a custom `jail.local`, enforces UFW firewall rules (deny-all default, allow SSH/HTTP/HTTPS), applies kernel-level sysctl security hardening, and hardens SSH (disables root login and password authentication).
- **Path**: `cookbooks/nginx-multisite`
- **Technology**: Chef
- **Key Features**:
  - Attribute-driven multi-site vhost loop (`node['nginx']['sites']`) rendered via `site.conf.erb`
  - Self-signed RSA-2048 certificate generation per vhost using `openssl req -x509`
  - SSL private key directory restricted to `root:ssl-cert` group with mode `0710`
  - `fail2ban` integration with templated `jail.local`
  - UFW firewall managed via idempotent `execute` guards
  - sysctl security hardening via `/etc/sysctl.d/99-security.conf` (20+ kernel parameters)
  - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
  - Recipes: `default` → `security` → `nginx` → `ssl` → `sites`
- **Ansible Migration Status**: Role exists at `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/` with tasks for security, nginx, SSL, and sites configuration. Requires validation and integration.

#### **cache**
- **Description**: Caching layer cookbook that installs and configures both Memcached (via the `memcached` Supermarket cookbook) and Redis (via `redisio`) with password authentication. Includes a notable `ruby_block` post-processing hack that strips deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` after `redisio` writes it, working around an incompatibility between the `redisio 7.2.4` cookbook and the installed Redis version.
- **Path**: `cookbooks/cache`
- **Technology**: Chef
- **Key Features**:
  - Memcached installed via `memcached ~> 6.0` Supermarket cookbook (64 MB RAM, port 11211, 1024 max connections)
  - Redis on port 6379 with `requirepass` authentication (hardcoded: `redis_secure_password_123`)
  - Post-write config file mutation via `ruby_block` (compatibility shim for deprecated directives)
  - `/var/log/redis` directory ownership enforced
  - External dependencies: `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4` (transitive)
- **Ansible Migration Status**: Role exists at `weqe-d92f93/modules/cache/ansible/roles/cache/` with tasks for memcached and Redis configuration. Includes AAP credential store integration for Redis password. Requires validation and credential management review.

#### **fastapi-tutorial**
- **Description**: Application deployment cookbook that clones a FastAPI Python application from GitHub (`https://github.com/dibanez/fastapi_tutorial.git`, `main` branch), creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file containing the database connection string, and registers a `systemd` service (`fastapi-tutorial.service`) to run the application via `uvicorn` on port 8000.
- **Path**: `cookbooks/fastapi-tutorial`
- **Technology**: Chef
- **Key Features**:
  - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
  - Git clone + sync from public GitHub repository
  - Python venv at `/opt/fastapi-tutorial/venv`
  - PostgreSQL user `fastapi` and database `fastapi_db` created via `psql` shell commands
  - `.env` file written to `/opt/fastapi-tutorial/.env` with `DATABASE_URL` containing plaintext credentials
  - `systemd` unit file deployed to `/etc/systemd/system/fastapi-tutorial.service`
  - Service runs as `root` (security concern — see Security Considerations)
- **Ansible Migration Status**: Role exists at `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/` with tasks for package installation, Git clone, venv setup, database provisioning, and systemd service management. Requires credential management review and service user privilege reduction.

---

### Infrastructure Files

- **Berksfile**: Berkshelf dependency manifest declaring all 3 local cookbook paths and 4 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1`). The `ssl_certificate` entry is commented out in the Berksfile but active in `Policyfile.rb`. **Migration consideration**: Replace entirely with Ansible Galaxy `requirements.yml`.

- **Policyfile.rb**: Chef Policyfile declaring the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook versions. **Migration consideration**: The run list order defines the provisioning sequence and must be preserved in the Ansible playbook task order.

- **Policyfile.lock.json**: Locked dependency graph with exact versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. **Migration consideration**: Reference for exact upstream versions being replaced; `selinux` is a transitive dependency of `redisio` and has no direct Ansible equivalent needed (Ansible's `ansible.posix.selinux` module covers this natively).

- **solo.json**: Chef Solo node JSON providing the run list and all node attribute overrides (site definitions, SSL paths, security flags). **Migration consideration**: This is the primary source of truth for variable values; all keys map directly to Ansible `vars` or `group_vars`.

- **solo.rb**: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks`. **Migration consideration**: No Ansible equivalent needed; superseded by `ansible.cfg` and inventory.

- **Vagrantfile**: Vagrant configuration using `generic/fedora42` box with `libvirt` provider, 2 vCPUs, 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. **Migration consideration**: Reusable as-is for Ansible testing; replace the `shell` provisioner block with an `ansible_local` or `ansible` provisioner pointing to the new playbook.

- **vagrant-provision.sh**: Shell bootstrap script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. **Migration consideration**: Replace with a minimal bootstrap that installs Ansible (e.g., `pip install ansible` or `dnf install ansible`) and runs `ansible-playbook`.

- **cookbooks/nginx-multisite/resources/lineinfile.rb**: Custom LWRP stub named `lineinfile` — a Chef analogue to Ansible's `lineinfile` module. **Migration consideration**: Drop entirely; Ansible's built-in `ansible.builtin.lineinfile` module is a direct replacement.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` as the development VM. `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `vagrant-provision.sh` script uses `apt-get`, indicating the primary tested target is a Debian/Ubuntu family OS. The `nginx-multisite` cookbook uses `www-data` as the Nginx user (Debian convention). **Recommendation**: Target **Ubuntu 22.04 LTS** for Ansible migration to match the `apt-get`/`www-data` conventions already in the cookbooks, or **Fedora 42** to match the Vagrant box — confirm with the owning team.

- **Virtual Machine Technology**: **libvirt/KVM** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. Vagrant is used for local development/testing only; no production VM platform is specified in the repository.

- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present in any reviewed file.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket: Replace with `ansible.builtin.package` to install the OS-native Nginx package, plus `ansible.builtin.template` for `nginx.conf` and vhost configs. The `nginxinc.nginx` Galaxy role is an optional drop-in if richer management is needed.
  - **Ansible Solution**: Use `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service`
  - **Status**: Already implemented in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/nginx.yml`

- **memcached (6.1.0)** — Chef Supermarket: Replace with `ansible.builtin.package` (`memcached`) and `ansible.builtin.service`. No complex configuration is applied beyond defaults; direct module usage is sufficient.
  - **Ansible Solution**: Use `ansible.builtin.package` + `ansible.builtin.service` + `ansible.builtin.template` for advanced config
  - **Status**: Already implemented in `weqe-d92f93/modules/cache/ansible/roles/cache/tasks/memcached.yml`

- **redisio (7.2.4)** — Chef Supermarket: Replace with `ansible.builtin.package` (`redis`) and a templated `redis.conf` with `requirepass` set. The `ruby_block` post-processing hack (stripping deprecated directives) becomes unnecessary when managing the config file directly via Ansible template — this is a net simplification.
  - **Ansible Solution**: Use `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.lineinfile` for cleanup
  - **Status**: Already implemented in `weqe-d92f93/modules/cache/ansible/roles/cache/tasks/redisio*.yml`

- **ssl_certificate (2.1.0)** — Chef Supermarket (locked but commented out in Berksfile): Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` from the `community.crypto` Ansible collection, which provides idempotent self-signed certificate generation without shelling out to `openssl`.
  - **Ansible Solution**: Use `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` or `ansible.builtin.command` with `openssl`
  - **Status**: Already implemented using `ansible.builtin.command` in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/ssl.yml`

- **selinux (6.2.4)** — Chef Supermarket (transitive via redisio): Replace with `ansible.posix.selinux` module if SELinux management is required on the target. On Ubuntu/Debian targets this dependency is irrelevant.
  - **Ansible Solution**: Use `ansible.posix.selinux` module (optional, target-dependent)
  - **Status**: Not required for Ubuntu/Debian targets; can be skipped

### Security Considerations

#### Credential Management

**CRITICAL SECURITY ISSUES IDENTIFIED:**

1. **Redis Password Hardcoded in Chef Recipe**
   - **Location**: `cookbooks/cache/recipes/default.rb` line 7: `'requirepass' => 'redis_secure_password_123'`
   - **Issue**: Plaintext password in source code, visible in Git history
   - **Ansible Migration**: The generated Ansible role at `weqe-d92f93/modules/cache/ansible/roles/cache/` includes AAP credential store integration (`aap-configuration/controller_credentials.yml`) that references `{{ vault_redis_password }}`. This is a significant improvement but requires:
     - Ansible Vault setup or AAP credential store configuration
     - Removal of hardcoded password from defaults
     - Injection of password via `--extra-vars` or Vault at runtime

2. **FastAPI Database Credentials in `.env` File**
   - **Location**: `cookbooks/fastapi-tutorial/recipes/default.rb` lines 42–47: `.env` file contains `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
   - **Issue**: Plaintext credentials in deployed file, readable by any process running as root
   - **Ansible Migration**: The generated role at `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/` uses templated `.env` file with variables. Requires:
     - Ansible Vault or AAP credential store for `db_password`, `db_username`, `db_name`, `db_host`
     - Restrict `.env` file permissions to `0600` (currently `0644`)
     - Consider using environment variables or systemd EnvironmentFile instead of `.env`

3. **SSL Certificate Generation**
   - **Location**: `cookbooks/nginx-multisite/recipes/ssl.rb` lines 24–35: Self-signed certificates generated with hardcoded subject DN
   - **Issue**: Self-signed certificates are acceptable for development/testing but unsuitable for production. No Let's Encrypt or external CA integration.
   - **Ansible Migration**: The generated role uses `ansible.builtin.command` with `openssl req -x509`. For production:
     - Integrate `community.crypto.x509_certificate` for idempotent generation
     - Add Let's Encrypt support via `community.crypto.acme_certificate` or `certbot`
     - Store certificates in Ansible Vault or external secret store

4. **SSH Hardening**
   - **Location**: `cookbooks/nginx-multisite/recipes/security.rb` lines 48–62: SSH hardening via `lineinfile` edits
   - **Issue**: Disables root login and password authentication — good security practice, but requires key-based authentication setup
   - **Ansible Migration**: Already implemented in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/security.yml`. Ensure:
     - SSH public keys are pre-deployed before disabling password auth
     - Fallback access method is documented (e.g., console, recovery mode)

5. **Service User Privilege**
   - **Location**: `cookbooks/fastapi-tutorial/recipes/default.rb` line 60: FastAPI service runs as `root`
   - **Issue**: Unnecessary privilege escalation; application should run as unprivileged user
   - **Ansible Migration**: The generated role should be updated to:
     - Create dedicated `fastapi` system user
     - Run service as `fastapi` user
     - Adjust file ownership accordingly

#### Secrets Management Strategy

**Recommended Approach for Ansible Migration:**

1. **Development/Testing**: Use Ansible Vault with a single vault password file (stored securely, not in Git)
   ```bash
   ansible-vault create group_vars/all/vault.yml
   ```

2. **Production**: Use Ansible Automation Platform (AAP) credential store or HashiCorp Vault integration
   - AAP already has credential types defined in `weqe-d92f93/modules/cache/ansible/roles/cache/aap-configuration/controller_credentials.yml`
   - Extend to include database credentials, SSL certificates, SSH keys

3. **CI/CD Integration**: Store secrets in CI/CD platform (GitHub Secrets, GitLab CI/CD Variables, etc.) and inject at runtime
   ```bash
   ansible-playbook site.yml --extra-vars "redis_password=$REDIS_PASSWORD db_password=$DB_PASSWORD"
   ```

### Technical Challenges

#### Challenge 1: Redis Configuration Post-Processing Hack
- **Description**: The `cache` cookbook includes a `ruby_block` that strips deprecated Redis directives from the generated config file. This is a workaround for incompatibility between `redisio 7.2.4` and the installed Redis version.
- **Mitigation**: In Ansible, manage the Redis config file directly via template, ensuring only compatible directives are included. This eliminates the need for post-processing and improves idempotency.
- **Implementation**: Use `weqe-d92f93/modules/cache/ansible/roles/cache/templates/redis.conf.j2` to generate a clean config without deprecated directives.

#### Challenge 2: Multi-Site Nginx Vhost Loop
- **Description**: The `nginx-multisite` cookbook uses a Chef loop (`node['nginx']['sites'].each`) to generate per-site vhost configs. Ansible's `loop` construct is similar but requires careful variable scoping.
- **Mitigation**: Use Ansible's `loop` with `dict2items` filter to iterate over the sites dictionary. Already implemented in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/nginx.yml`.
- **Implementation**: Ensure loop variables are properly scoped and handlers are triggered correctly for each iteration.

#### Challenge 3: Self-Signed Certificate Generation Idempotency
- **Description**: The Chef recipe uses `openssl req -x509` with a `not_if` guard to avoid regenerating certificates. Ansible's `ansible.builtin.command` with `creates` parameter provides similar functionality, but the generated role uses `creates` which may not be sufficient if the certificate needs to be updated.
- **Mitigation**: Use `community.crypto.x509_certificate` module for idempotent generation, or enhance the `ansible.builtin.command` task with proper state checking.
- **Implementation**: Already partially addressed in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/ssl.yml` using `creates` parameter.

#### Challenge 4: UFW Firewall Idempotency
- **Description**: The Chef recipe uses `execute` resources with `not_if` guards to manage UFW rules. Ansible's `community.general.ufw` module is more idempotent but may not support all UFW features.
- **Mitigation**: Use `community.general.ufw` module for standard rules, fall back to `ansible.builtin.command` for advanced configurations.
- **Implementation**: Already implemented in `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/tasks/security.yml` using `ansible.builtin.command` with `changed_when` for idempotency.

#### Challenge 5: PostgreSQL Database and User Creation
- **Description**: The FastAPI cookbook uses shell commands (`sudo -u postgres psql`) to create database and user. Ansible's `community.postgresql.postgresql_db` and `community.postgresql.postgresql_user` modules are more idempotent.
- **Mitigation**: Use `community.postgresql` collection modules instead of shell commands. Already partially addressed in the generated role using `ansible.builtin.shell` with `changed_when: false` (not ideal).
- **Implementation**: Update `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/tasks/main.yml` to use `community.postgresql.postgresql_db` and `community.postgresql.postgresql_user` modules.

#### Challenge 6: Python Virtual Environment Management
- **Description**: The FastAPI cookbook uses `execute` to create venv and install dependencies. Ansible's `ansible.builtin.pip` module with `virtualenv` parameter is more idempotent.
- **Mitigation**: Already implemented in the generated role using `ansible.builtin.command` for venv creation and `ansible.builtin.pip` for dependency installation.
- **Implementation**: Ensure `creates` parameter is used correctly to avoid re-running venv creation.

### Migration Order

Based on dependency analysis, the recommended migration order is:

1. **Priority 1: cache** (Low risk, high value)
   - **Rationale**: Standalone module with no dependencies on other local cookbooks. Memcached and Redis are well-supported by Ansible. The main challenge is credential management (Redis password), which is already addressed in the generated role.
   - **Effort**: 1–2 days
   - **Status**: Ansible role exists; requires validation and credential management review

2. **Priority 2: nginx-multisite** (Moderate complexity, high value)
   - **Rationale**: Depends on no other local cookbooks but is a critical infrastructure component. Multi-site vhost loop and SSL certificate generation are the main challenges, both already addressed in the generated role.
   - **Effort**: 2–3 days
   - **Status**: Ansible role exists; requires validation and testing

3. **Priority 3: fastapi-tutorial** (Moderate complexity, moderate value)
   - **Rationale**: Depends on no other local cookbooks but requires careful credential management and service user privilege reduction. PostgreSQL integration is the main challenge.
   - **Effort**: 2–3 days
   - **Status**: Ansible role exists; requires credential management review and service user privilege reduction

**Parallel Execution**: Modules 1–3 can be migrated in parallel by different team members, as they have no inter-module dependencies. However, integration testing should be sequential to ensure the full stack works together.

### Assumptions

1. **Target OS**: Assumed to be Ubuntu 22.04 LTS or Fedora 42 based on Vagrantfile and metadata.rb. If a different OS is targeted, package names and service management may differ.

2. **Ansible Version**: Assumed to be Ansible 2.10+ (supports `ansible.builtin` namespace and `community.crypto` collection). If an older version is required, some modules may not be available.

3. **Ansible Collections**: Assumes `community.crypto`, `community.postgresql`, `community.general`, and `ansible.posix` collections are installed. These are not part of the core Ansible distribution and must be installed via `ansible-galaxy collection install`.

4. **Credential Management**: Assumes Ansible Vault or AAP credential store will be used for secrets. If a different secrets management system is in place (e.g., HashiCorp Vault, AWS Secrets Manager), integration points will need to be adjusted.

5. **SSH Access**: Assumes SSH key-based authentication is available for Ansible to connect to target hosts. The SSH hardening in `nginx-multisite` disables password authentication, so keys must be pre-deployed.

6. **PostgreSQL Installation**: Assumes PostgreSQL is installed on the target system before the FastAPI role is applied. The current recipe installs PostgreSQL as a system package, which is acceptable for development but may not be suitable for production (consider containerization or managed database services).

7. **Git Repository Access**: Assumes the FastAPI tutorial repository (`https://github.com/dibanez/fastapi_tutorial.git`) remains publicly accessible. If the repository is moved or made private, the Git clone task will fail.

8. **Firewall Configuration**: Assumes UFW is available on the target system. On systems without UFW (e.g., RHEL/CentOS with firewalld), the firewall configuration tasks will fail and need to be adapted.

9. **Existing Ansible Infrastructure**: Assumes no existing Ansible infrastructure is in place. If Ansible is already deployed in the organization, integration with existing playbooks, roles, and inventory may be required.

10. **Testing and Validation**: Assumes the generated Ansible roles have been tested in a development environment (e.g., Vagrant with libvirt) before deployment to production. The existing Vagrantfile can be adapted to use Ansible provisioner instead of Chef.

11. **Backward Compatibility**: Assumes no requirement to maintain Chef cookbooks alongside Ansible roles during a transition period. If a gradual migration is required, both systems may need to coexist temporarily.

12. **Documentation**: Assumes team members are familiar with Ansible basics (playbooks, roles, variables, handlers). If not, training or documentation updates may be required.

---

## Integration and Testing Strategy

### Unified Playbook Structure

Create a top-level playbook that orchestrates all three roles in the correct order:

```yaml
# site.yml
---
- name: Configure nginx-multisite infrastructure
  hosts: all
  become: true
  
  roles:
    - role: cache
      tags: [cache]
    - role: nginx_multisite
      tags: [nginx, web]
    - role: fastapi_tutorial
      tags: [fastapi, app]
```

### Testing Approach

1. **Unit Testing**: Use Molecule to test each role in isolation
   - Existing Molecule configurations are present in each role's `molecule/` directory
   - Run `molecule test` for each role to validate syntax, idempotency, and functionality

2. **Integration Testing**: Use Vagrant with Ansible provisioner
   - Update `Vagrantfile` to use `ansible_local` or `ansible` provisioner
   - Run full stack provisioning and verify all services are running

3. **Validation Checklist**:
   - [ ] Nginx is installed and running on port 80/443
   - [ ] Three virtual hosts are configured and accessible
   - [ ] SSL certificates are generated and valid
   - [ ] Memcached is running on port 11211
   - [ ] Redis is running on port 6379 with password authentication
   - [ ] FastAPI application is running on port 8000
   - [ ] PostgreSQL database and user are created
   - [ ] Firewall rules are applied (UFW active, SSH/HTTP/HTTPS allowed)
   - [ ] SSH hardening is applied (root login disabled, password auth disabled)
   - [ ] All services start on boot

### Deployment Checklist

- [ ] Ansible Vault or AAP credential store is configured
- [ ] SSH keys are pre-deployed to target hosts
- [ ] Ansible inventory is created with target host(s)
- [ ] `ansible.cfg` is configured with correct settings
- [ ] All required Ansible collections are installed
- [ ] Playbook syntax is validated (`ansible-playbook --syntax-check`)
- [ ] Dry-run is executed (`ansible-playbook --check`)
- [ ] Full provisioning is executed
- [ ] Post-deployment validation is performed
- [ ] Rollback plan is documented (if needed)

---

## Deliverables and Timeline

### Phase 1: Validation and Refinement (1 week)
- [ ] Review and validate existing Ansible roles
- [ ] Test each role with Molecule
- [ ] Identify and document any gaps or issues
- [ ] Update roles to address identified issues
- **Deliverable**: Validated Ansible roles with passing tests

### Phase 2: Integration and Testing (1 week)
- [ ] Create unified playbook (`site.yml`)
- [ ] Update Vagrantfile to use Ansible provisioner
- [ ] Perform integration testing with Vagrant
- [ ] Document testing results and any issues
- **Deliverable**: Integrated playbook with passing integration tests

### Phase 3: Credential Management and Security (1 week)
- [ ] Set up Ansible Vault or AAP credential store
- [ ] Migrate hardcoded credentials to vault
- [ ] Implement service user privilege reduction for FastAPI
- [ ] Review and document security best practices
- **Deliverable**: Secure credential management implementation

### Phase 4: Documentation and Knowledge Transfer (1 week)
- [ ] Create Ansible playbook documentation
- [ ] Document variable definitions and customization points
- [ ] Create deployment runbook
- [ ] Conduct team training on Ansible playbook usage
- **Deliverable**: Complete documentation and team training

**Total Estimated Timeline: 3–4 weeks** (with one engineer) or **2–3 weeks** (with two engineers working in parallel)

---

## Next Steps

1. **Immediate**: Review this migration plan with the team and confirm target OS and deployment environment
2. **Week 1**: Validate existing Ansible roles using Molecule and identify any gaps
3. **Week 2**: Integrate roles into unified playbook and perform integration testing
4. **Week 3**: Implement credential management and security hardening
5. **Week 4**: Document and conduct team training

---

## Appendix: File Mapping Reference

### Chef to Ansible Mapping

| Chef Component | Location | Ansible Equivalent | Status |
|---|---|---|---|
| nginx-multisite cookbook | `cookbooks/nginx-multisite/` | `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/` | ✅ Exists |
| cache cookbook | `cookbooks/cache/` | `weqe-d92f93/modules/cache/ansible/roles/cache/` | ✅ Exists |
| fastapi-tutorial cookbook | `cookbooks/fastapi-tutorial/` | `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/` | ✅ Exists |
| Berksfile | `Berksfile` | `requirements.yml` | ⏳ To be created |
| Policyfile.rb | `Policyfile.rb` | `site.yml` | ⏳ To be created |
| solo.json | `solo.json` | `group_vars/all/main.yml` | ⏳ To be created |
| Vagrantfile | `Vagrantfile` | Updated with Ansible provisioner | ⏳ To be updated |

### Key Variables Mapping

| Chef Attribute | Ansible Variable | Location |
|---|---|---|
| `node['nginx']['sites']` | `nginx_multisite_sites` | `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/defaults/main.yml` |
| `node['nginx']['ssl']['certificate_path']` | `nginx_multisite_ssl_certificate_path` | `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/defaults/main.yml` |
| `node['security']['ssh']['disable_root']` | `nginx_multisite_ssh_disable_root` | `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/defaults/main.yml` |
| `node['redisio']['servers'][0]['requirepass']` | `redis_password` | `weqe-d92f93/modules/cache/ansible/roles/cache/defaults/main.yml` |
| `fastapi_tutorial_db_user` | `db_username` | `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/defaults/main.yml` |

---

## Conclusion

The migration from Chef to Ansible is well-scoped and achievable within 3–4 weeks. The existing Ansible roles provide a solid foundation, and the main work involves validation, integration, credential management, and documentation. The team should prioritize credential management and security hardening to ensure the migrated infrastructure is production-ready.

**Recommendation**: Proceed with Phase 1 (Validation and Refinement) immediately to identify any gaps and establish a clear path forward.
