# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/local-mode demonstration environment containing three local Chef cookbooks, provisioned into a Fedora 42 Vagrant/libvirt virtual machine. The workloads comprise a hardened multi-site Nginx static web tier, Redis and Memcached services, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in scope because the cookbook count is small, but it requires careful platform normalization, secret remediation, service integration, and testing of the security baseline. A two-person team can reasonably implement, test, and document the initial Ansible migration in approximately 2–3 weeks; allow additional time if the target must support both Fedora/RHEL and Ubuntu/CentOS as declared by the Chef metadata.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and configures Memcached and Redis caching services. It configures a Redis listener on port 6379 with password authentication, uses `/run/redis` for the PID path to accommodate Fedora, creates Redis logging storage, applies a compatibility cleanup to the generated Redis configuration, and enables the Redis service.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached recipe inclusion; Redis service configuration and enablement; Redis authentication; Fedora SELinux/runtime-path accommodation; Redis configuration post-processing.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from its Git repository, installs Python and PostgreSQL prerequisites, creates a virtual environment, installs application requirements, initializes PostgreSQL on Fedora/RHEL, creates the application database and role, writes a database `.env` file, and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Fedora/RHEL versus Debian-family package branching; Git-based application deployment; Python virtual environment; local PostgreSQL database provisioning; systemd application service.

- **nginx-multisite**:
  - Description: Provisions Nginx with three SSL-enabled static virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), sample site content, HTTP-to-HTTPS redirection, self-signed certificates, web security headers, Fail2ban, firewall rules, sysctl hardening, and SSH root/password-login restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration and service management; templated vhosts and site enablement; bundled static content; self-signed TLS certificates; Fail2ban; UFW firewall automation; SSH hardening; kernel/network sysctl configuration; TLS and HTTP security headers.

**CRITICAL PATH VERIFICATION:** All module paths above are present in the supplied repository tree. No Puppet modules, Salt states, or PowerShell module manifests/scripts were identified.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, the three local cookbooks, and external `nginx`, `memcached`, and `redisio` cookbook constraints. Replace Berkshelf resolution with pinned Ansible collection/role requirements and OS package mappings.
- `Policyfile.rb`: Defines the `chef-examples` policy and run list ordering: Nginx/security, cache, then FastAPI. Translate this orchestration into a top-level Ansible playbook and role dependency/order design.
- `solo.json`: Chef Solo run list and environment-specific values for site roots, certificate paths, and security options. Convert to inventory/group variables or role defaults; resolve its differing site document roots versus cookbook defaults before migration.
- `solo.rb`: Chef Solo cache and cookbook-path configuration. It has no direct Ansible equivalent; replace with repository layout, `ansible.cfg`, inventories, and dependency requirements.
- `Vagrantfile`: Defines the Fedora 42 base box, libvirt provider, 2 vCPU/2 GB sizing, private address `192.168.121.10`, port forwards 80→8080 and 443→8443, and rsync source sync. Retain as a development/test harness or replace the Chef provisioner with `ansible_local`/an external Ansible provisioner.
- `vagrant-provision.sh`: Installs Ruby/Chef 18.8.54 and Berkshelf, vendors cookbooks, and invokes Chef local mode. Replace with an Ansible bootstrap path; Chef licensing and Ruby/Gem installation should be removed from the target workflow.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default Nginx site, TLS path, Fail2ban, firewall, and SSH-hardening variables. Convert these to documented role defaults and override through inventory variables.
- `cookbooks/nginx-multisite/templates/default/`: Nginx main configuration, per-site vhost, web security, Fail2ban, and sysctl templates. Port to Jinja2 templates after validating distribution-specific include paths and package service users.
- `cookbooks/nginx-multisite/files/default/`: Static index pages for the three Nginx sites. Copy with `ansible.builtin.copy` or retain as role files.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the web cookbook. Assess whether it is used by non-entrypoint code; its intended line-edit behavior should map to `ansible.builtin.lineinfile` if retained.

### Target Details

- **Operating System**: The active Vagrant target is Fedora 42. Recipes explicitly branch for Fedora/RHEL package naming and PostgreSQL initialization, while cookbook metadata also declares Ubuntu 18.04+ and CentOS 7+ support. The initial Ansible target should be Fedora 42 (or a validated current RHEL-compatible equivalent); Ubuntu/CentOS support is not proven by the active provisioning configuration and should be a separately tested compatibility objective.
- **Virtual Machine Technology**: Vagrant with the libvirt provider. The Vagrant VM uses an rsync shared folder.
- **Cloud Platform**: Not specified. No cloud-provider tooling, metadata integration, or cloud resources are configured.

## Migration Approach

Create an Ansible repository with a top-level site playbook and discrete roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`; optionally separate `os_hardening`, `postgresql`, and `tls_selfsigned` roles to make their risk boundaries and reuse clearer. Use inventories and variable files to replace Chef attributes and `solo.json`. Pin collections in `collections/requirements.yml`, use CI linting/idempotence tests, and validate in the existing Fedora/libvirt Vagrant environment before retiring Chef.

### Key Dependencies to Address

- **Chef Client 18.8.54 / Chef Solo / Berkshelf**: Eliminate from provisioning. Use `ansible-core` with version-pinned collections and a documented controller bootstrap process.
- **Chef Supermarket `memcached` (~> 6.0)**: Replace with `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service`/`systemd` tasks for Memcached. The local cookbook currently delegates configuration to the external cookbook, so its desired non-default settings must be captured before cutover.
- **Chef Supermarket `redisio` (~> 7.2.4; unbounded in cookbook metadata)**: Replace with package, configuration template, directory ownership, SELinux-aware configuration where needed, and systemd tasks. Explicitly model Redis version, bind address, persistence, service unit, and authentication policy rather than retaining the Chef compatibility hack.
- **Chef Supermarket `nginx` (~> 12.0)**: Although declared in `Berksfile`, the local Nginx cookbook installs the OS `nginx` package directly. Replace with native Ansible package/template/service tasks; remove this dependency unless a previously implicit external cookbook behavior is found during acceptance testing.
- **`ssl_certificate` (~> 2.1)**: Commented out in `Berksfile` and not an active dependency. Do not migrate it as a dependency; use `community.crypto` for development self-signed certificates or integrate the organization’s certificate authority for production.
- **Git repository `https://github.com/dibanez/fastapi_tutorial.git` at `main`**: Replace with `ansible.builtin.git`, but deploy a tested immutable commit/tag rather than the moving `main` branch. Establish an artifact, source-validation, and update policy.
- **Python/Pip application requirements**: Use `ansible.builtin.pip` with the virtualenv path and preferably a lock file or hash-verified, version-pinned requirements. Ensure compiler/database client dependencies match the selected operating system.
- **PostgreSQL server and client tooling**: Replace shell `psql` commands with PostgreSQL Ansible modules where practical (for example `community.postgresql.postgresql_user` and `postgresql_db`), with an appropriate Python PostgreSQL driver installed on the managed node.
- **OpenSSL, Fail2ban, UFW, and Nginx system packages**: Manage through OS-specific package variables. UFW is not normally native to Fedora; select and test `firewalld` on the Fedora/RHEL target, or explicitly make firewall implementation distribution-dependent.

### Security Considerations

- **Hardcoded Redis password (`cache`)**: `redis_secure_password_123` is embedded in the default recipe. Remove it from source control, generate/rotate a strong secret, store it in Ansible Vault or an approved external secret manager, and set restrictive Redis configuration file permissions.
- **Hardcoded PostgreSQL/FastAPI password (`fastapi-tutorial`)**: The recipe embeds `fastapi_password` in SQL commands and writes it into `/opt/fastapi-tutorial/.env` with mode `0644`. Store the database credential in Vault/external secret management, create it idempotently, ensure the environment file is readable only by the runtime identity, and rotate it during migration.
- **TLS certificates and keys (`nginx-multisite`)**: Certificates are self-signed and private keys are created under `/etc/ssl/private` with `root:ssl-cert` ownership and mode 0640. Self-signed certificates are acceptable only for development; production requires CA-issued certificates, controlled renewal, protected private-key access, and no key material in Git. The certificate subject includes `admin@example.com`, which is contact metadata rather than a secret but should be replaced by approved identity data.
- **SSH hardening (`nginx-multisite`)**: Root login and password authentication are disabled by direct `sed` edits to `sshd_config`. Use validated `sshd_config.d` drop-ins where supported, back up/validate configuration before reload, and preserve a tested key-based break-glass path to prevent administrator lockout.
- **Firewall and network exposure (`nginx-multisite`)**: The intended policy is default deny with SSH, HTTP, and HTTPS allowed. Implement equivalent firewall rules for the chosen OS and ensure port 8000, Redis 6379, Memcached, and PostgreSQL remain non-public unless explicitly required. Verify Vagrant port forwards do not become production requirements.
- **Web/TLS hardening (`nginx-multisite`)**: Preserve TLS 1.2/1.3, HSTS, access controls for dotfiles/VCS directories, and security headers, but review the CSP’s `'unsafe-inline'` allowances and the obsolete/deprecated `X-XSS-Protection` header. Validate cipher policy against current organizational standards.
- **Fail2ban and sysctl policy (`nginx-multisite`)**: Retain only controls compatible with the selected distribution and confirm they do not conflict with centrally managed security tooling. Notify/restart services only after configuration validation.
- **Runtime privilege (`fastapi-tutorial`)**: The FastAPI service runs as `root`, and the application tree is root-owned. Create a dedicated non-login service user, restrict write access, and apply systemd hardening options after compatibility testing.
- **Supply-chain control (`fastapi-tutorial`)**: The application uses an unpinned Git branch and unconstrained runtime dependency installation. Pin revisions/dependencies and introduce source/artifact verification in the Ansible deployment pipeline.

### Technical Challenges

- **Distribution mismatch and unsupported combinations**: The Vagrant target is Fedora 42, while metadata advertises Ubuntu and CentOS. UFW and Debian-style `sites-available` layout are particularly non-native on Fedora. Build role variables/tasks by OS family and test the selected target first; do not claim multi-platform support until each platform has CI coverage.
- **Chef external cookbook behavior is partially opaque**: The local cache cookbook includes Memcached and Redisio recipes rather than declaring all resulting configurations. Capture the actual converged VM state (packages, configuration files, units, ports, users, SELinux labels) as acceptance criteria before replacing it.
- **Imperative configuration fixes**: Redis configuration is modified using a Ruby `gsub` cleanup after `redisio` runs, and SSH/firewall changes use shell commands. Replace these with declarative templates/modules and configuration validation so reruns are predictable and idempotent.
- **Service dependency and rollout coordination**: FastAPI requires PostgreSQL before startup, while Nginx currently only serves static sites and does not proxy FastAPI. Confirm intended application ingress, health checks, and startup ordering with stakeholders before adding any reverse-proxy behavior that is not present in Chef.
- **Variable drift**: `solo.json` specifies `/var/www/<site>` roots, whereas cookbook defaults specify `/opt/server/<site>`. Determine the authoritative environment configuration and test that each intended static file is deployed to the selected path.
- **Database migration limits**: The cookbook creates only a user and empty database; application schema initialization is not visible. Define whether schema migrations are application-owned and add a controlled migration step only after reviewing the application’s documented process.

### Migration Order

1. **Foundation and test harness**: Establish the Ansible repository, Fedora/RHEL inventory, variable conventions, Vault/external secret integration, collection pinning, CI linting, and Vagrant/libvirt validation. Baseline the current Chef-converged host for comparison.
2. **Nginx static-site role**: Migrate Nginx package/service, static content, vhosts, and templates first. Test HTTP/HTTPS routing, headers, certificate paths, and idempotency before enabling disruptive host hardening.
3. **Cache role**: Implement Memcached and Redis with explicit configuration, Vault-provided Redis credentials, service checks, localhost/network binding decisions, and SELinux/firewall validation.
4. **PostgreSQL and FastAPI roles**: Provision PostgreSQL, create least-privilege application credentials/database, deploy a pinned application revision and virtualenv, install a hardened systemd unit, and test application startup and database connectivity.
5. **Security hardening and final cutover**: Migrate Fail2ban, OS-appropriate firewall rules, sysctl controls, SSH hardening, and production certificate integration. Perform access-lockout, rollback, vulnerability, and functional acceptance tests before Chef removal.

Team coordination should assign a platform/security owner for baseline and firewall/SSH controls, an application/database owner for FastAPI/PostgreSQL behavior and secret rotation, and an automation owner for role design, CI, and Vagrant testing. Maintain a shared acceptance matrix covering package versions, listeners, service states, rendered configuration, permissions, TLS behavior, and rollback steps; conduct a handover session documenting inventory, Vault access procedures, routine updates, and incident recovery.

### Assumptions

- Chef is the sole source technology in scope; no Puppet, Salt, or PowerShell modules were present in the supplied tree.
- The supplied tree is complete and contains exactly the three local cookbooks listed in `Berksfile` and `Policyfile.rb`.
- Fedora 42 with Vagrant/libvirt is the immediate target because it is the only explicitly configured execution environment; production operating system, cloud provider, and production VM platform are not specified.
- The local cookbook entrypoints reviewed are the intended run-list entrypoints. `nginx-multisite` delegates its implementation to four sub-recipes, which were reviewed because the entrypoint is solely orchestration.
- Current self-signed TLS certificates and sample static sites are development/test behavior, not a production certificate-management design.
- Redis and PostgreSQL passwords in source are insecure example credentials and must not be carried forward as production values.
- The FastAPI deployment is intentionally Git-based in the current configuration, but migration should require stakeholder approval of a pinned revision/artifact and the application’s schema migration process.
- The desired Memcached settings are not visible in the local cookbook because configuration is delegated to the external Chef cookbook; a current-state capture is required.
- The repository does not establish that Nginx should reverse proxy the FastAPI service; no such behavior should be introduced without a confirmed requirement.
- `solo.json` overrides site document roots differently from the cookbook defaults; environment owners must identify the authoritative values before implementation.
