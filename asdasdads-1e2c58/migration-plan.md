# MIGRATION FROM CHEF TO ANSIBLE

This is a small Chef Solo/Policyfile repository containing three local cookbooks and a Vagrant-based development environment. The migration is moderate in operational risk rather than size: the code footprint is small, but it combines web serving, TLS, host hardening, Redis/Memcached, PostgreSQL, and a FastAPI systemd service. A focused team should be able to produce an initial Ansible implementation in approximately 1–2 weeks, followed by 3–5 days of functional, security, and idempotence testing. Production rollout timing will depend on certificate, DNS, database, and secret-management decisions that are not represented in this repository.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server configuration for three SSL-enabled virtual hosts, with static content, host security hardening, firewall rules, Fail2ban, SSH restrictions, sysctl settings, and development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Nginx installation and service management, `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` sites, SSL certificate/key directories, UFW default-deny rules, Fail2ban, root-login and password-authentication disabling, and templated Nginx/security configuration.
    - Ansible shape: A role with separate task files for `nginx`, `security`, `ssl`, and `sites`; handlers for Nginx/Fail2ban/SSH reloads and sysctl application; Jinja2 templates; and variables for sites and certificate paths.

- **cache**:
    - Description: Host caching services cookbook that enables Memcached and configures a Redis server on port 6379.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached inclusion, Redis installation/enabling through external cookbooks, Redis log directory creation, Redis authentication, and a post-generation configuration workaround that removes replication-related settings.
    - Ansible shape: A role using distribution-appropriate Memcached and Redis packages/services, a managed Redis configuration template, a protected password variable, and explicit service handlers. The current Ruby file-edit workaround should be replaced by a declarative configuration rather than reproduced as an arbitrary text mutation.

- **fastapi-tutorial**:
    - Description: Deployment of a FastAPI tutorial application from GitHub with Python virtualenv, PostgreSQL, application database/user creation, environment configuration, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Python 3/pip/venv and PostgreSQL packages, checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, virtual environment creation, requirements installation, PostgreSQL startup, database provisioning, `.env` generation, and Uvicorn listening on `0.0.0.0:8000`.
    - Ansible shape: Application, PostgreSQL, and systemd tasks (possibly split into roles), `ansible.builtin.git`, `pip`/virtualenv management, PostgreSQL modules, a systemd unit template, and handlers for daemon reload/restart.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree and their primary entrypoints were reviewed. No Puppet, Salt, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef dependency source and local cookbook declarations. It references local `nginx-multisite`, `cache`, and `fastapi-tutorial`, plus Supermarket `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; a commented `ssl_certificate` dependency is also present.
- `Policyfile.rb`: Defines policy `nginx-multisite-policy`, the Chef run list, and dependency constraints. It includes `ssl_certificate ~> 2.1` even though the local cookbook generates certificates directly.
- `Policyfile.lock.json`: Resolved versions include nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, ssl_certificate 2.1.0, and selinux 6.2.4, plus the three local cookbooks at 1.0.0. It is the authoritative snapshot for the Chef dependency set and should be retained as migration evidence.
- `Vagrantfile`: Defines a `generic/fedora42` VM, hostname `chef-nginx`, private IP `192.168.121.10`, ports 80/443 forwarded to 8080/8443, 2 GiB RAM, 2 CPUs, libvirt, and an rsync-mounted repository. Provisioning invokes `vagrant-provision.sh`.
- `vagrant-provision.sh`: Installs packages and Chef/Berkshelf, vendors dependencies, and runs Chef Solo. It uses `apt-get`, which conflicts with the Fedora 42 Vagrant box and must be corrected or replaced by Ansible provisioning.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration.
- `solo.json`: Chef run list plus site, SSL path, and security attributes. It overrides site document roots to `/var/www/...`, while the cookbook defaults use `/opt/server/...`; resolve this precedence intentionally in Ansible.
- `project-plan.md`: Repository-level specification for the X2Ansible analysis/migration workflow. It is process documentation rather than infrastructure configuration, but it can inform generated-plan and validation workflows.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates that must be ported to Jinja2 after reviewing their exact rendered behavior.
- `cookbooks/nginx-multisite/files/`: Static `index.html` content for the test, CI, and status sites; these should become role-managed files or templates.

### Target Details

- **Operating System**: The cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The Vagrant box is Fedora 42, but `vagrant-provision.sh` uses Debian/Ubuntu `apt-get`; therefore the effective target OS is ambiguous and the current development provisioning is likely incompatible with Fedora. Select and test a supported target explicitly. If no production requirement exists, standardize on a current supported Ubuntu or RHEL-family release and use Ansible facts/package variables.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 CPUs and 2048 MB memory. The Ansible replacement should support provisioning the VM through Vagrant or run remotely against the resulting host.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud metadata configuration was found.

## Migration Approach

Create an Ansible project with an inventory and environment-specific `group_vars`, a top-level site playbook, and roles for `nginx-multisite`, `cache`, and `fastapi-tutorial`. Preserve the existing three-service topology initially, then refactor shared concerns such as firewall, SSH hardening, TLS, and PostgreSQL if reuse is required. Use check mode, Molecule or equivalent disposable-VM tests, service health checks, and rendered-configuration comparisons before cutover.

### Key Dependencies to Address

- **Chef Solo / Berkshelf / Policyfile**: Replace the Chef execution and dependency resolution layer with Ansible collections, roles, `ansible-galaxy` requirements, and pinned collection/role versions where external content is needed.
- **nginx cookbook 12.3.1**: Replace with `ansible.builtin.package`, templated Nginx configuration, service/handler tasks, or a reviewed Ansible Nginx role. Do not assume the Chef cookbook's defaults map directly to the target OS.
- **memcached cookbook 6.1.0**: Replace with distribution packages and an explicit service/configuration role.
- **redisio cookbook 7.2.4 plus selinux 6.2.4**: Replace with supported Redis packages/configuration and explicit SELinux policy/booleans/ports where applicable. Test authentication and service startup on the chosen OS.
- **ssl_certificate 2.1.0**: It is locked but not visibly used by the local recipes. Decide whether to use an Ansible certificate role, ACME/Let's Encrypt, externally managed certificates, or development-only self-signed certificates.
- **GitHub FastAPI repository and Python dependencies**: Pin the application revision instead of tracking `main` for production. Evaluate dependency lock files, package build requirements, and network access during deployment.
- **PostgreSQL**: Use `community.postgresql` modules and a database-specific role. Ensure the target PostgreSQL version and authentication method are selected rather than relying on distribution defaults.
- **UFW and Fail2ban**: Replace shell `execute` resources with Ansible modules and templates where possible; use `ansible.posix.firewalld` on RHEL-family systems if Fedora/RHEL remains the target.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and avoid exposing it in logs or rendered artifacts.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes the same value into a world-readable `.env` file (`0644`). Treat the credential as compromised, rotate it, store it in Vault, restrict the file to the service account, and use PostgreSQL modules with idempotent password handling.
- **Application service privilege**: The systemd unit runs FastAPI as `root`. Create a dedicated non-root user, define ownership and permissions for `/opt/fastapi-tutorial`, and bind/reverse-proxy the application safely.
- **TLS certificates and private keys**: Self-signed certificates are generated for development with one-year validity and private keys under `/etc/ssl/private`. Protect keys, avoid committing generated material, define renewal/rotation, and use trusted certificates for real environments. Validate subject names/SANs and certificate paths for every site.
- **SSH hardening**: Root login and password authentication are disabled by default. Preserve these controls, but ensure a tested key-based administrative access path exists before applying them and use a validated SSH configuration mechanism rather than fragile `sed` edits.
- **Firewall behavior**: UFW is set to default deny and permits SSH, HTTP, and HTTPS. Confirm required application/database/cache access and avoid locking out operators. On Fedora, translate this to firewalld rather than installing UFW solely for parity.
- **Fail2ban and sysctl**: Port the templated policies and sysctl settings after reviewing the templates. Test compatibility with the selected kernel and service log formats.
- **Supply-chain security**: The application is cloned from an unpinned Git branch and pip installs remote requirements. Pin source revisions and dependency hashes where feasible, and add repository/package verification to CI.
- **Secrets management by module**: `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials in commands and `.env`; `nginx-multisite` handles private TLS keys but no external secret store is shown. No Chef encrypted data bags or Chef Vault usage were found in the reviewed files.

### Technical Challenges

- **OS mismatch**: Fedora 42 is declared by Vagrant while the provisioning script uses `apt-get`, and cookbook support lists Ubuntu/CentOS rather than Fedora. Choose the target OS first and test package names, service names, firewall, SELinux, PostgreSQL, and Nginx paths.
- **Chef attribute precedence and configuration drift**: Cookbook defaults use `/opt/server/...`, while `solo.json` overrides to `/var/www/...`. Convert the effective values into explicit Ansible variables and document environment precedence.
- **Template behavior is not fully visible in the entrypoint review**: Nginx, site, security, Fail2ban, and sysctl templates determine important runtime behavior. Port them with rendered-config tests and `nginx -t`, rather than translating only the recipe resources.
- **Non-idempotent shell/database operations**: PostgreSQL creation uses `|| true`, and the Redis workaround edits generated files. Replace both with declarative modules and controlled migrations.
- **Certificate lifecycle**: Current certificates are development self-signed artifacts. Production migration requires ownership of DNS, ACME/account credentials or certificate distribution, renewal, and rollback.
- **Application deployment reliability**: Installing from `main`, running pip without a lock strategy, and running Uvicorn directly as root create reproducibility and availability risks. Establish version pinning, health checks, graceful restarts, and a dedicated service account.
- **Service integration and ordering**: FastAPI depends on PostgreSQL; Nginx sites and TLS depend on files/certificates; Redis/Memcached must be available to consumers. Model dependencies with handlers, `systemd` ordering, and post-deployment checks.
- **External dependency ambiguity**: `ssl_certificate` is present in the lock but not used in the reviewed local recipes. Confirm whether it is legacy, transitively required, or intended for future use before replacing it.

### Migration Order

1. **Repository foundation and target OS**: Establish inventory, Vault strategy, CI linting, Molecule/disposable-VM tests, and resolve Fedora versus Ubuntu/RHEL requirements.
2. **cache**: Migrate Memcached and Redis with secure variables and service tests. It is relatively self-contained, but credential handling and SELinux/firewall behavior require validation.
3. **fastapi-tutorial data/application stack**: Provision PostgreSQL, application user/database, pinned source, virtualenv, non-root systemd service, and health checks.
4. **nginx-multisite security baseline**: Port SSH hardening, firewall, Fail2ban, sysctl, and file permissions with an access-recovery test plan.
5. **nginx-multisite web/TLS/sites**: Port Nginx installation, templates, static files, virtual hosts, certificate lifecycle, and reload handlers; validate all three hostnames and HTTP-to-HTTPS expectations.
6. **Integrated cutover and decommissioning**: Compare rendered configuration and service behavior with Chef, execute staged rollout/rollback, then remove Chef/Berkshelf provisioning after acceptance.

### Assumptions

- The repository is a development/demo deployment rather than an already defined production topology; no production inventory or cloud account details are present.
- The three local cookbooks are the complete first-party module inventory; external cookbooks are dependencies, not modules to list separately.
- The exact contents of the Nginx, security, Fail2ban, sysctl, and site templates were not required to identify the module inventory but must be reviewed during implementation.
- `solo.json` values are intended to override cookbook defaults; this must be confirmed because document-root paths differ.
- The three `.cluster.local` names are development names and require DNS or `/etc/hosts` entries; the commented Vagrant host mapping is not active.
- The Vagrant private IP in the file is `192.168.121.10`, while the provisioning script prints `192.168.56.10`; the correct address must be confirmed.
- The target may be Fedora because of the Vagrant box, but the current shell script and cookbook support declarations do not establish a valid Fedora target.
- Self-signed certificates are acceptable only for development. Production certificate authority, SANs, renewal, and secret distribution remain unspecified.
- Redis authentication is intended, but the required password is currently a placeholder/hardcoded value and must be rotated.
- PostgreSQL is intended to run locally on the application host; remote database topology, backup, replication, and upgrade requirements are unspecified.
- The FastAPI repository's `main` branch and requirements are trusted but not version-pinned; release management and artifact provenance need an owner.
- No database backup, monitoring, logging aggregation, HA, or disaster-recovery configuration was identified.
- No Ansible inventory, collection requirements, CI pipeline, or secret backend currently exists; these are migration deliverables.
- A successful migration means equivalent service behavior and security intent, not literal reproduction of Chef shell commands or Chef-specific dependency structure.
