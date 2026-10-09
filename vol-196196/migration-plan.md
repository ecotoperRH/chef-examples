# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo deployment composed of three local cookbooks and several locked Supermarket dependencies. The effective run list provisions an nginx multi-site host, Redis/memcached caching, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in security and integration risk rather than scale: approximately 1–2 weeks for a production-ready Ansible conversion, including testing and reconciliation of the current inconsistencies, assuming one engineer familiar with Linux, nginx, PostgreSQL, and Ansible. A basic functional prototype could be produced in 3–5 working days.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and configures nginx for three static HTTPS virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), creates their document roots and sample index files, applies web security settings, manages firewall/fail2ban/SSH hardening, and generates development certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: nginx service and virtual hosts, HTTP-to-HTTPS redirects, TLS 1.2/1.3, security headers, rate limiting, UFW rules, fail2ban, sysctl hardening, self-signed certificates, static site files, and ERB templates.
    - Migration complexity: Medium to high because it combines web serving, host firewall policy, SSH hardening, kernel settings, certificates, and multiple templates. Convert into an Ansible role with separate task files for nginx, security, TLS, and sites, plus handlers for reload/restart operations.

- **cache**:
    - Description: Installs memcached and Redis, creates a Redis log directory, configures a Redis server on port 6379, applies a post-generation configuration workaround, and enables the Redis service.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: memcached dependency, Redis authentication, Redis service enablement, log directory management, and direct cleanup of generated replication-related configuration.
    - Migration complexity: Medium because service defaults and the Redis package layout must be validated on the target distribution, and the current cookbook contains a plaintext password and an imperative configuration hack.

- **fastapi-tutorial**:
    - Description: Installs Python and PostgreSQL packages, clones the FastAPI tutorial application, creates a virtual environment, installs its requirements, creates a PostgreSQL database/user, writes an application `.env` file, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git-based application deployment, Python virtualenv, PostgreSQL service, database initialization, systemd unit, Uvicorn on `0.0.0.0:8000`, and application environment configuration.
    - Migration complexity: Medium to high due to application lifecycle, database idempotency, remote repository drift, secret handling, and the service currently running as root. Use Ansible package, git, command/module-specific database tasks, template, systemd, and handlers; pin the application revision and Python dependencies before production use.

**CRITICAL PATH VERIFICATION:**
All three module paths above were present in the supplied repository tree and their primary `recipes/default.rb` files were reviewed. No Puppet manifests, Chef recipes outside these cookbooks, PowerShell modules, or Salt states were identified.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source, local cookbook paths, and external dependency constraints. Replace dependency installation with Ansible collection/role requirements and OS package variables; retain it as migration evidence only.
- `Policyfile.rb`: Defines the Chef policy run list and dependency declarations. Use it as the source for the initial Ansible site playbook and role ordering.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions, including nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, selinux 6.2.4, and ssl_certificate 2.1.0. Preserve these versions in the migration test matrix where applicable.
- `solo.rb`: Chef Solo cookbook path and logging configuration. Replace with Ansible inventory, `ansible.cfg`, group variables, and playbook configuration.
- `solo.json`: Chef attributes and run list. Convert nginx sites, TLS paths, security switches, and application/cache variables into vaulted or environment-specific Ansible variables. Note that its document roots differ from the cookbook defaults.
- `Vagrantfile`: Defines a libvirt VM using `generic/fedora42`, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 8080/8443. It is the principal local integration-test harness for the target deployment.
- `vagrant-provision.sh`: Installs Chef through a remote script, Berkshelf, dependencies, and runs Chef Solo. Replace it with an Ansible provisioner or a script that installs Ansible and invokes the target playbook. Its `apt-get` commands conflict with the Fedora base box and must be corrected or removed.
- `project-plan.md`: Documents the broader X2Ansible tool specification and workflow. Use it for migration coordination context, not as infrastructure configuration.
- `cookbooks/nginx-multisite/templates/`: nginx, site, security, fail2ban, and sysctl templates. Port to Ansible templates with explicit variables and validation before handlers reload services.
- `cookbooks/nginx-multisite/files/`: Static HTML test, CI, and status content. Copy into role files or deploy from an application artifact.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default sites and hardening values. Reconcile these with `solo.json` before conversion.

### Target Details

- **Operating System**: The cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The supplied Vagrant box is Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu-specific `apt-get`, `/var/log/auth.log`, UFW, `www-data`, and Debian-style service/package assumptions. The Ansible target OS is therefore unresolved; define supported platforms explicitly, preferably Ubuntu/Debian and Fedora/RHEL variants with variable-based package/service/firewall handling. Do not assume Fedora works until tested.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync synchronization. No production hypervisor is specified.
- **Cloud Platform**: Not specified. The configuration is local/VM-oriented and contains no AWS, Azure, or GCP integration.

## Migration Approach

Create an Ansible project with a site playbook and three roles: `nginx_multisite`, `cache`, and `fastapi_tutorial`. Add inventory groups for web/application hosts and environment-specific `group_vars`. Keep templates and static content close to the relevant role. Use handlers for nginx, fail2ban, SSH, sysctl, Redis, and systemd reloads. Use `ansible-lint`, Molecule or Vagrant-based convergence tests, nginx configuration validation, TLS checks, and service/application smoke tests. Migrate one role at a time while running Chef and Ansible against isolated test VMs; do not run both against the same live host without an ownership plan.

### Key Dependencies to Address

- **nginx cookbook 12.3.1**: Replace with native Ansible package/service/template tasks and the `community.general`/`ansible.posix` modules where needed. Preserve nginx configuration behavior but validate distribution-specific paths.
- **memcached cookbook 6.1.0**: Replace with OS package installation, service management, and a deliberately defined memcached configuration. Confirm whether memcached is actually consumed by the application.
- **redisio cookbook 7.2.4**: Replace with a supported Redis package/repository strategy and an Ansible-managed config template. Avoid reproducing the Ruby post-processing hack unless its exact runtime requirement is documented.
- **selinux cookbook 6.2.4**: The lock includes it transitively through redisio, but no local SELinux policy behavior was reviewed. Decide whether SELinux is required and use `ansible.posix.selinux` plus correct file contexts on Fedora/RHEL.
- **ssl_certificate 2.1.0**: It is locked in Policyfile but not used by the reviewed local recipes; Berksfile comments it out. Either remove it or replace it with managed certificates, ACME automation, or externally supplied certificate files. Do not silently generate self-signed certificates for production.
- **PostgreSQL and Python runtime**: These are installed directly by the FastAPI cookbook, without a local cookbook dependency declaration. Use distribution-aware PostgreSQL tasks, `community.postgresql` for database/user creation, Python virtualenv management, and a pinned requirements file.
- **Git repository `https://github.com/dibanez/fastapi_tutorial.git`**: Replace floating `main` with a commit/tag and define outbound network/proxy requirements. Treat upstream dependency installation as an application release concern.
- **Chef Policyfile/berkshelf locking**: Use the lock file to establish baseline versions, but independently verify package versions and behavior because Ansible will not consume Chef cookbook locks.

### Security Considerations

- **Plaintext Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and ensure Redis configuration and logs do not expose it.
- **Plaintext PostgreSQL credentials**: The FastAPI recipe embeds `fastapi_password` in SQL commands and writes it to `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate it, store it in Vault, write the file with restrictive permissions (for example `0600`), and use idempotent database modules rather than shell commands.
- **TLS private keys and certificates**: Keys are generated under `/etc/ssl/private` with group `ssl-cert` and mode `0640`; preserve least privilege and use Ansible Vault or a certificate manager for real certificates. Self-signed certificates are explicitly development-only and produce browser warnings.
- **TLS configuration**: TLS 1.2/1.3, custom ciphers, HSTS, and security headers must be regression-tested. Review cipher policy and HSTS before production, especially if any non-HTTPS site is retained.
- **Firewall and SSH hardening**: The cookbook defaults to deny incoming traffic, allows SSH/HTTP/HTTPS, disables root login, and disables password authentication. Confirm the administrative access path before applying these settings to avoid lockout. Use `ansible.posix.firewalld` on Fedora/RHEL or `community.general.ufw` on Ubuntu rather than shell commands.
- **Kernel networking settings**: The sysctl template disables IPv6 and ICMP echo and changes routing protections. Confirm these are intentional for every environment; apply with `ansible.posix.sysctl` and document operational impacts.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Create a dedicated application user, restrict filesystem access, and assess binding/proxy architecture before migration.
- **Web exposure**: Uvicorn listens on all interfaces at port 8000, while nginx serves static sites. Decide whether port 8000 should be firewalled and whether nginx should reverse proxy the application.
- **Supply chain and execution**: The provision script downloads and executes Chef’s installer via curl, and the application clones a mutable branch. Pin and verify installers, repositories, package sources, and Python dependencies.

### Technical Challenges

- **OS mismatch and portability**: Fedora 42 is the test box but the scripts use apt/UFW/Debian paths. Mitigation: choose a supported OS matrix, add `ansible_facts`-based variables, and test both Debian-family and Red Hat-family behavior or narrow support explicitly.
- **Conflicting source of truth**: `attributes/default.rb` uses `/opt/server/...`, while `solo.json` uses `/var/www/...`; `Policyfile.rb` includes `ssl_certificate` while `Berksfile` comments it out; Vagrant comments host entries but test URLs depend on name resolution. Resolve these decisions with the service owner before implementation.
- **Non-idempotent shell operations**: PostgreSQL creation uses `|| true`, and Redis configuration is modified with a Ruby block. Replace with Ansible modules and explicit change detection, then test repeat runs.
- **Template and platform semantics**: nginx site enablement, service names, SSH log paths, ownership (`www-data`), and certificate directories vary by OS. Add configuration tests and use variables rather than copying Debian assumptions.
- **Application deployment drift**: `main` and an unpinned `requirements.txt` can change independently of infrastructure. Establish release artifacts, health checks, rollback behavior, and migration handling before production cutover.
- **Firewall/SSH outage risk**: Apply connectivity checks and a staged hardening role; preserve console access in Vagrant and use `serial`/maintenance controls in shared environments.
- **Dependency ambiguity**: The lock includes external cookbooks not directly invoked by the visible run list. Verify the actual Chef-expanded resource graph and runtime behavior before declaring them required Ansible components.

### Migration Order

1. **Foundation and test harness**: Correct the Vagrant/OS assumptions, establish inventory, variables, linting, Molecule or Vagrant tests, and a baseline snapshot of current services/configuration.
2. **fastapi-tutorial**: Build package, PostgreSQL, application checkout, virtualenv, systemd, and health-check tasks; first remove plaintext credentials and root execution.
3. **cache**: Migrate Redis and memcached with vaulted credentials, supported package configuration, and repeat-run tests. Validate application connectivity before cutover.
4. **nginx-multisite core**: Migrate packages, templates, static files, sites, service handlers, and certificate paths; verify all three hostnames and HTTP-to-HTTPS behavior.
5. **Security hardening**: Apply fail2ban, firewall, SSH, sysctl, TLS, and headers in a controlled stage after access and certificate procedures are confirmed. This is part of nginx migration but should be deployed separately or behind explicit enablement flags.
6. **Cutover and decommissioning**: Compare rendered configuration and service behavior, perform a controlled host cutover, monitor logs/health checks, and retain Chef rollback until the Ansible deployment is stable.

A reasonable schedule is 1–2 days for discovery and target decisions, 2–3 days for role implementation, 2–3 days for integration/security testing, and 1–2 days for remediation, documentation, and cutover planning. Add time for production certificate/secret integration or multi-OS support.

### Assumptions

- The intended source technology is Chef Solo, based on Ruby cookbooks, Berksfile, Policyfile, `solo.rb`, and `chef-solo` provisioning.
- The three directories under `cookbooks/` are the complete local cookbook inventory.
- The Policyfile run list represents the intended deployment order, although `solo.json` uses shorthand recipe names and should be normalized.
- The supplied files do not establish a production hostname, inventory, DNS, certificate authority, secret manager, backup policy, monitoring system, or cloud platform.
- PostgreSQL is intended to run locally on the same host as FastAPI; this must be confirmed before selecting a managed/external database design.
- The three `.cluster.local` names are development/test names and require `/etc/hosts` or DNS; the commented Vagrant host entries are not active.
- The sample HTML files are test content, not necessarily production application content.
- Redis replication-related settings are intentionally removed by the workaround, but the reason and required Redis topology are undocumented.
- `ssl_certificate` being locked does not prove it is used; dependency usage must be confirmed before migration or removal.
- The final Ansible design should preserve behavior only after owners approve the conflicting document-root values and the target OS.
- Timeline estimates assume access to an isolated test environment and an engineer able to validate Linux services, nginx, PostgreSQL, Redis, and Ansible.
- Team coordination should assign owners for OS/platform, web/security, application/database, secrets/certificates, and test/cutover approval; review variable names and security defaults jointly before merging.
