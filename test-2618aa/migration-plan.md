# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile environment composed of three local cookbooks: an Nginx multi-site edge configuration, caching services, and a FastAPI/PostgreSQL tutorial application. It is suitable for migration to a compact Ansible repository built around roles and a single environment playbook. The core configuration is straightforward, but production readiness requires remediation of plaintext credentials, development self-signed certificates, service account choices, and inconsistent operating-system assumptions. For one engineer, allow approximately **2–3 weeks** for role implementation, test-environment correction, functional/security validation, and documentation; add time for production certificate, secret-management, and database ownership decisions.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Provisions an Nginx web tier serving three named virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`). It deploys site content, Nginx and security configuration templates, self-signed TLS certificates, Fail2ban, UFW firewall rules, kernel sysctl hardening, and SSH root/password-login restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx service management; per-site document roots and enabled site links; HTTP/HTTPS exposure; self-signed RSA certificates; Fail2ban; UFW default-deny firewall; SSH hardening; sysctl security configuration.

- **cache**:
  - Description: Installs and enables Memcached and Redis caching services, creates the Redis log directory, configures a Redis listener on port 6379 with authentication, and applies a post-install Ruby workaround that removes selected replication/client-buffer directives from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis service enablement; Redis password configuration; `/var/log/redis` ownership; configuration post-processing workaround.

- **fastapi-tutorial**:
  - Description: Deploys the external `dibanez/fastapi_tutorial` Git application with Python 3 and a virtual environment, installs Python requirements, installs and starts local PostgreSQL, creates the `fastapi` database/user, writes application database environment configuration, and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Git-based application deployment; Python virtual environment and pip dependency installation; PostgreSQL database provisioning; `.env` generation; systemd service lifecycle management.

**CRITICAL PATH VERIFICATION:** All paths above were present in the supplied repository tree. No external Chef Supermarket cookbook has been represented as a local module inventory item.

### Infrastructure Files

- `Berksfile`: Chef Supermarket dependency source and local cookbook paths. Replace Berkshelf resolution with pinned Ansible collection requirements and OS/Python dependency documentation; retain the resolved Chef versions as an initial compatibility reference.
- `Policyfile.rb`: Defines the `nginx-multisite-policy` run list and dependency constraints. Replace with an Ansible site playbook that applies roles in a verified dependency order.
- `Policyfile.lock.json`: Captures the resolved dependency set, including Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, `ssl_certificate` 2.1.0, and transitive SELinux support. Use it to identify behavior that must not silently disappear during conversion.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. No direct Ansible equivalent is required; replace execution details with `ansible.cfg`, inventories, and CI command documentation.
- `solo.json`: Chef node/run-list data for Nginx site names, document roots, TLS locations, and security controls. Convert these to environment-specific `group_vars` or role defaults, with sensitive values moved to Ansible Vault or an external secret manager.
- `Vagrantfile`: Local Vagrant/libvirt test topology: `generic/fedora42`, 2 vCPUs, 2 GiB RAM, private address `192.168.121.10`, and forwarded HTTP/HTTPS ports. Retain or replace with an Ansible Molecule/libvirt test scenario; reconcile it with Debian/Ubuntu-oriented configuration before using it as the acceptance baseline.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef and Berkshelf, vendors dependencies, then runs Chef Solo. Retire Chef/Berkshelf steps and replace with an Ansible controller/bootstrap invocation; its `apt-get` usage conflicts with the Fedora Vagrant box.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default Nginx sites, TLS directories, and security flags. Translate to documented role defaults and inventory overrides.
- `cookbooks/nginx-multisite/templates/` and `cookbooks/nginx-multisite/files/`: Nginx, site, Fail2ban, sysctl, and static HTML assets. Port templates to Jinja2 and retain static assets under the Nginx role.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: A custom Chef resource present in the cookbook. Its use is not established by the reviewed primary recipe; assess it during implementation and replace any active usage with `ansible.builtin.lineinfile`.
- `project-plan.md`: Documentation for an infrastructure migration tool, not runtime provisioning. It can inform workflow expectations but does not require configuration migration.

### Target Details

- **Operating System**: The declared cookbook support matrix is Ubuntu 18.04+ and CentOS 7+. The active implementation is predominantly Debian/Ubuntu-oriented: it uses `apt-get`, `ufw`, `www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and a service named `ssh`. However, `Vagrantfile` selects `generic/fedora42`, where `apt-get` and UFW are not native. Treat Ubuntu as the provisional target for functional parity unless the team elects to rework the roles for Fedora/RHEL; do not assume the provided Vagrant VM currently provisions successfully.
- **Virtual Machine Technology**: Vagrant with the libvirt provider, using rsync folder synchronization.
- **Cloud Platform**: Not specified. No cloud provider tooling or metadata integration was found.

## Migration Approach

Create an Ansible repository with an inventory, an environment playbook, and independently testable roles such as `baseline_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep application/site configuration in inventory variables; use handlers for Nginx, Fail2ban, systemd, and sysctl reloads. First establish an OS support decision and a repeatable test target, then migrate behavior role by role with idempotency and service-validation tests. Assign an infrastructure engineer to the security/Nginx baseline, an application/database engineer to FastAPI/PostgreSQL, and a reviewer to secret and platform validation. Capture acceptance criteria, ownership, rollback procedures, and knowledge-transfer runbooks alongside the roles.

### Key Dependencies to Address

- **Chef Infra Client/Solo (>= 16.0)**: Remove Chef runtime, Berkshelf, Solo JSON, and Chef-specific resources. Use `ansible-core`, supported collections, inventories, and playbooks.
- **Chef Supermarket `nginx` (locked 12.3.1; Berks constraint `~> 12.0`)**: The local Nginx cookbook installs/configures the operating-system Nginx package directly rather than visibly including this cookbook. Verify whether the external cookbook has any required indirect behavior; implement explicit package, template, site-link, and service tasks with `ansible.builtin` modules.
- **Chef Supermarket `memcached` (locked 6.1.0; constraint `~> 6.0`)**: Replace with distribution package installation and `ansible.builtin.service` management. Define any intended Memcached listener, memory, or access-control settings explicitly because they are not visible in the local recipe.
- **Chef Supermarket `redisio` (locked 7.2.4)**: Replace with OS Redis packages plus a Jinja2-managed Redis configuration and service. Preserve only required settings after validating why the Chef recipe removes multiple replication and client-buffer directives.
- **Chef Supermarket `ssl_certificate` (locked 2.1.0)**: It is policy-locked but the reviewed local TLS recipe uses OpenSSL commands directly. Do not carry the dependency forward unless a fuller implementation review confirms use; manage development certificates using `community.crypto` or, preferably, integrate a production PKI/certificate authority.
- **Chef Supermarket `selinux` (locked 6.2.4, transitive)**: Relevant if RHEL-family support is retained. Define SELinux policy/contexts explicitly in an Ansible RHEL variant; it is not a substitute for the Ubuntu UFW logic.
- **PostgreSQL, Python 3, pip, venv, Git, libpq development headers, and application Python requirements**: Use package tasks separated by OS family, `ansible.builtin.git`, a virtual-environment-aware pip task, and `community.postgresql` modules for database/user/grant management. Pin and review Python requirements from the cloned application repository rather than installing an uncontrolled moving `main` branch.
- **System services and firewall tooling**: Use `ansible.builtin.systemd`/`service`, `ansible.posix.sysctl`, and an OS-specific firewall role (`community.general.ufw` for Ubuntu or `ansible.posix.firewalld` for RHEL/Fedora). Ensure SSH daemon service names are platform-specific.

### Security Considerations

- **Hardcoded Redis credential (`cache`)**: `redis_secure_password_123` is stored directly in the Chef recipe. Remove it from source control, rotate it, store its replacement in Ansible Vault or an external secret manager, set strict Redis configuration permissions, and restrict Redis network exposure.
- **Hardcoded PostgreSQL/application credential (`fastapi-tutorial`)**: The `fastapi_password` password appears both in SQL commands and in `/opt/fastapi-tutorial/.env`; the environment file is mode `0644`, exposing the database URL to all local users. Rotate the credential, manage the DB user using `community.postgresql.postgresql_user`, and deploy an owner-restricted environment file (for example `0600`) via Vault/external secrets.
- **TLS certificates and private keys (`nginx-multisite`)**: The cookbook generates one-year, 2048-bit self-signed certificates using `openssl ... -nodes`; private keys are stored in `/etc/ssl/private` with `root:ssl-cert` and mode `0640`. This is acceptable only for isolated development. Use organization-issued/ACME certificates in production, define renewal/reload handling, restrict key-read group membership, and prevent private material from entering Git or Ansible facts/log output.
- **SSH and host security (`nginx-multisite`)**: Root login and password authentication are disabled through `sed` edits to `sshd_config`; preserve this outcome with `sshd_config` drop-ins or validated configuration management, retain an active key-based administrative access path, validate with `sshd -t`, and stage changes to avoid lockout. Fail2ban, a default-deny UFW policy, and sysctl hardening should be migrated only after a review of their template values and operational access requirements.
- **Network exposure**: Nginx is opened for HTTP/HTTPS and FastAPI listens on `0.0.0.0:8000`, while Redis defaults to port 6379. Explicitly decide whether FastAPI and Redis are internal-only, bind them accordingly, and add firewall/security-group rules. Nginx should proxy the application only if that behavior is present in the unreviewed Nginx template and is verified during implementation.
- **Privilege/service account (`fastapi-tutorial`)**: The FastAPI Uvicorn service runs as `root`. Create a dedicated non-login service account, grant only needed ownership/read access, and move writable/log paths outside root-owned application code as required.
- **Supply-chain controls (`fastapi-tutorial` and provisioning)**: The application is cloned from the mutable `main` branch and pip installs its requirements without reviewed hashes or version controls; Chef installation is fetched by piping a remote script to Bash. In Ansible, pin a Git commit/tag, establish dependency locking/hashing and artifact/proxy policy, and obtain controller/runtime packages through approved channels.
- **Vault/secrets management by module**:
  - `nginx-multisite`: TLS private keys/certificates are generated on-node; no external private key is committed, but production certificate/key references must be held in Vault or a PKI integration.
  - `cache`: A visible Redis authentication password is hardcoded in the recipe.
  - `fastapi-tutorial`: A visible PostgreSQL password and a database URL containing it are hardcoded and written to `.env`.

### Technical Challenges

- **Conflicting platform model**: The Vagrant guest is Fedora 42, whereas the bootstrap and most Nginx/security choices require Ubuntu/Debian. Select the supported target(s) before conversion; implement separate package/service/firewall variable maps only if multi-platform support is an explicit requirement.
- **Chef dependency behavior is partly external**: Memcached and Redis are delegated to Chef Supermarket cookbooks, so the exact installed package names, service behavior, defaults, and configuration generated by those cookbooks must be baselined before replacement. Compare desired state on a working Chef node, not merely Chef recipe intent.
- **Non-idempotent/opaque imperative steps**: Redis is altered using a Ruby text substitution workaround; database creation uses shell commands with `|| true`; SSH settings use `sed`; certificate creation uses shell commands. Replace these with declarative Ansible modules/templates, validation checks, and explicit state rather than reproducing shell behavior.
- **Application deployment reproducibility**: A mutable Git branch plus unconstrained pip installation makes repeatable builds difficult. Pin application and dependency versions, decide release/update policy, and test service restart/rollback behavior.
- **Configuration precedence and paths**: `solo.json` overrides the cookbook's default Nginx document roots (`/var/www/...` versus `/opt/server/...`). Establish Ansible variable precedence and document the canonical environment values before testing. Verify the Nginx template assumptions, including distro-specific site directory layout.
- **Database lifecycle/data protection**: The current configuration creates a local database but has no migration, backup, restore, retention, encryption, or high-availability definition. Coordinate with application/DB owners before promoting this design beyond a tutorial/development target.

### Migration Order

1. **Platform baseline and security role** (high priority): Decide Ubuntu versus Fedora/RHEL support; build inventory/test VM; migrate package abstraction, firewall, Fail2ban, sysctl, and SSH hardening with safe-access tests. This establishes the operating-system contract for all other roles.
2. **Nginx multi-site role** (moderate complexity): Migrate Nginx installation, templates, static site content, TLS directory/certificate strategy, vhosts, handlers, and HTTP/HTTPS tests. Use approved development certificates only until production PKI is integrated.
3. **Cache role** (moderate complexity): Replace Memcached/Redis Chef dependencies with explicit package/configuration/service tasks, externalize the Redis password, decide network binding, and validate compatibility after removing the Chef-specific configuration workaround.
4. **PostgreSQL and FastAPI application roles** (highest complexity): Provision PostgreSQL declaratively, migrate secrets, create a non-root service identity, pin application/dependency versions, deploy the systemd unit, and test application/database health, restart, and rollback flows.
5. **Integrated acceptance and cutover**: Execute the full site playbook against the chosen Vagrant/libvirt or equivalent test environment, validate firewall and TLS behavior, compare service states/configurations to a Chef baseline, document operations, then plan staged production rollout with rollback.

### Assumptions

- The repository contains Chef configuration only; no Puppet manifests, Salt states, PowerShell modules, or existing Ansible content were present in the supplied tree.
- The three local cookbook directories are the complete local migration scope. Supermarket cookbooks are dependencies, not local modules to port verbatim.
- Ubuntu is the provisional functional-parity target because of `apt-get`, UFW, `www-data`, and Debian Nginx site-directory usage, despite the Fedora 42 Vagrant box and the stated CentOS support.
- The provided configuration appears development/tutorial-oriented: self-signed certificates, `.local` names, a tutorial FastAPI repository, and plaintext example passwords should not be treated as production-approved settings.
- The current Chef Policyfile lock is the intended dependency baseline, although `Berksfile` comments out `ssl_certificate` while `Policyfile.rb` and the lock include it; dependency intent must be reconciled.
- The Nginx templates, Fail2ban/sysctl template values, custom `lineinfile` resource implementation, and the external FastAPI repository requirements were not exhaustively reviewed as part of this high-level survey. Their exact behavior must be validated during detailed role design.
- No DNS, load balancer, cloud security-group, certificate authority, monitoring, backup, CI/CD, secret-management platform, or production inventory is defined in the reviewed source.
- `Vagrantfile` port forwarding uses host ports 8080/8443 and private IP `192.168.121.10`, while `vagrant-provision.sh` prints `192.168.56.10`; test documentation/network expectations require correction.
