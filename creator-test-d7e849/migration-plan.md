# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment composed of three local cookbooks: hardened Nginx multi-site hosting, Redis/Memcached caching, and a FastAPI tutorial application backed by PostgreSQL. The source is operationally meaningful but contains portability inconsistencies, imperative shell/Ruby workarounds, development TLS, and plaintext credentials. A staged migration into three Ansible roles plus a site playbook is moderate complexity. Estimate **2–4 engineering weeks** for role implementation, test-environment parity, security remediation, and acceptance testing; allow additional time if the application repository, database schema/initialization, or production certificate workflow needs to be defined.

The Policyfile applies the components in this order: Nginx/security, cache, then FastAPI. Ansible should instead model explicit role ordering and service dependencies, with shared variables and handlers. Assign a platform/security owner, an application/database owner, and a reviewer responsible for idempotence and validation. Maintain a Chef-versus-Ansible configuration matrix and test each role in an isolated disposable VM before integrated deployment.

## Module Migration Plan

This repository contains **Chef cookbooks** that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Installs and enables Nginx, serves three static virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), redirects HTTP to HTTPS, and creates development self-signed certificates. It also configures host hardening through Fail2ban, UFW, sysctl settings, and SSH root/password-login restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx global/security configuration templates; per-site document roots, index files, available/enabled-site links; TLS 1.2/1.3, HSTS and HTTP security headers; gzip; self-signed certificate generation; UFW allow rules for SSH/HTTP/HTTPS; Fail2ban; SSH and kernel-network hardening.

- **cache**:
  - Description: Configures Memcached and a password-protected Redis instance on port 6379, creates Redis logging storage, and uses a Ruby post-processing block to remove selected replication/client-buffer directives from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis server attributes and enablement; Redis authentication; `/var/log/redis`; imperative compatibility workaround for `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
  - Description: Deploys the externally hosted `dibanez/fastapi_tutorial` Python application from Git, creates a virtual environment, installs Python requirements, provisions a local PostgreSQL database/user, writes an application `.env`, and runs Uvicorn as a systemd service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3, pip, venv, Git and PostgreSQL packages; Git checkout of the `main` branch; PostgreSQL service/database grants; systemd unit; restart-on-failure application service.

### Infrastructure Files

- `Berksfile`: Berkshelf source and cookbook resolution. It declares all three local cookbooks and Chef Supermarket dependencies; replace dependency retrieval with Ansible collections/roles pinned in `requirements.yml` where required.
- `Policyfile.rb`: Defines the Chef policy run list and requested cookbook constraints. Translate this to a top-level Ansible playbook with explicit role order and inventory/group-variable scoping.
- `Policyfile.lock.json`: Records the resolved cookbook versions: Memcached 6.1.0, Nginx 12.3.1, Redisio 7.2.4, SELinux 6.2.4 transitively, and ssl_certificate 2.1.0. Treat it as the authoritative Chef dependency snapshot during parity testing.
- `solo.json`: Chef Solo run list and runtime values for sites, TLS paths, Fail2ban/UFW, and SSH security. Convert it into typed Ansible defaults plus environment-specific `group_vars`; resolve its document-root values against cookbook defaults before migration.
- `solo.rb`: Chef Solo cache, cookbook-path, and logging configuration. It has no direct runtime equivalent beyond Ansible project layout, logging, and execution configuration.
- `Vagrantfile`: Development VM definition using `generic/fedora42`, libvirt, 2 GB RAM, two CPUs, private IP `192.168.121.10`, and host port forwarding (8080→80, 8443→443). Preserve or replace with an Ansible test target; document libvirt as the current VM platform.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef/Berkshelf, vendors cookbooks, and invokes Chef Solo. It conflicts with the Fedora Vagrant box and should be retired in favor of a minimal Ansible bootstrap (Python availability) and `ansible-playbook`.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, TLS-path, and hardening values. Convert to role defaults; do not retain environment-dependent paths solely in defaults.
- `cookbooks/nginx-multisite/templates/default/*.erb`: Nginx, site, Fail2ban, security, and sysctl configuration sources. Convert to Jinja2 templates after validating syntax and OS-specific target locations.
- `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html`: Static site content that should be copied by the Nginx role or managed as application/site artifacts.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu 18.04+ and CentOS 7+. Actual recipe choices (`apt-get`, `ufw`, `www-data`, `/etc/nginx/sites-available`, and service name `ssh`) strongly indicate an Ubuntu/Debian-oriented target. The declared Vagrant box is Fedora 42, which is inconsistent with those choices. The migration must select and test a supported target explicitly rather than defaulting to RHEL 9. If RHEL 9 is selected, replace UFW with firewalld, adapt package/service names and Nginx layout, and validate SELinux.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; the configuration uses a generic Fedora 42 box.
- **Cloud Platform**: Not specified. No cloud-provider configuration was found.

## Migration Approach

Create an Ansible repository with a site playbook (for example, `playbooks/site.yml`), inventory and environment-specific `group_vars`, and roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`. Use role defaults only for non-sensitive, portable values; use handlers for Nginx, Fail2ban, SSH, sysctl, PostgreSQL, and systemd reload events. Make the platform choice a prerequisite and test both a clean deployment and a repeat run for idempotence.

Translate Chef package, directory, file/template, service, Git, and link resources to native Ansible modules. Replace shell-heavy resources with purpose-built modules where available: PostgreSQL modules for users/databases/grants, firewall modules, OpenSSL/certificate modules or a managed PKI workflow, and systemd modules. Preserve the source’s operational outcome, but do not blindly retain development-only patterns or unsafe workarounds.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Eliminate Chef runtime, Berkshelf vendoring, `solo.rb`, and the Chef run-list. Replace with version-controlled Ansible roles/playbooks and CI lint/test tooling.
- **Chef Supermarket `nginx` (locked 12.3.1)**: The local Nginx cookbook installs/configures Nginx directly and does not visibly include this dependency. Do not migrate it as a required external Ansible role without first confirming why it is retained in the policy; use `ansible.builtin.package`, templates, files, and `ansible.builtin.service`/`systemd` for the local behavior.
- **Chef Supermarket `memcached` (locked 6.1.0)**: Replace with native package/service tasks, with package name and configuration verified for the chosen operating system.
- **Chef Supermarket `redisio` (locked 7.2.4; transitively `selinux` 6.2.4)**: Replace with OS-native Redis packages and service management, a managed Redis configuration template, a dedicated secret-backed password, and explicit SELinux handling only on SELinux platforms. Reassess the Chef Ruby directive-removal workaround rather than reproducing it.
- **Chef Supermarket `ssl_certificate` (locked 2.1.0)**: It is locked by the Policyfile but not visibly used by the local cookbook, which generates certificates through `openssl`. Replace development generation with `community.crypto` only if self-signed development certificates remain a requirement; use enterprise PKI, ACME, or pre-provisioned certificates for real environments.
- **Python application dependencies from the external Git repository**: Ansible must clone a pinned commit/tag instead of mutable `main`, create the venv, and install the application’s requirements. Review and pin Python dependencies separately because they are outside this repository.
- **PostgreSQL client/server tooling**: Replace `psql` shell commands with `community.postgresql.postgresql_user`, `postgresql_db`, and privilege tasks, using a controlled PostgreSQL administrative connection and required Python driver package.

### Security Considerations

- **Plaintext Redis secret in `cache`**: `redis_secure_password_123` is set directly in the Chef recipe. Move it to Ansible Vault or an external secret manager, rotate it, set restrictive Redis configuration permissions, and limit Redis network exposure/bind settings as part of the target design.
- **Plaintext PostgreSQL/application secret in `fastapi-tutorial`**: The recipe creates user `fastapi` with password `fastapi_password` and writes the same credential in `/opt/fastapi-tutorial/.env` with mode `0644`. Store the database password in Vault/external secrets, rotate it, render `.env` mode `0600` under a dedicated non-root service account, and prevent it from appearing in logs or source control.
- **TLS certificates and private keys in `nginx-multisite`**: Certificates are self-signed and keys are generated locally with `openssl`; key directory mode is `0710`, individual keys become `0640`, and group `ssl-cert` can read them. This is acceptable only as a controlled development pattern. For production, provision trusted certificates and keys through a secret/PKI workflow, restrict read access to the Nginx service identity, define renewal, and avoid exposing private key material in play output.
- **SSH hardening**: The source disables root SSH login and password authentication by in-place `sed` edits. Use a validated drop-in configuration or managed `sshd_config`, retain a break-glass/authorized-key access plan, validate configuration before reload, and avoid locking out automation users.
- **Firewall and intrusion prevention**: The source defaults UFW to deny and opens SSH, HTTP, and HTTPS; it also enables Fail2ban. Parameterize SSH port and permitted management networks, use the firewall technology appropriate to the selected OS, and test ordering so the Ansible connection remains available.
- **Nginx security headers**: The site template enables TLS 1.2/1.3, HSTS, frame/content-type/referrer headers, and a CSP that permits inline scripts/styles. Preserve the headers but review CSP, HSTS domain scope, TLS cipher compatibility, and application requirements with security stakeholders before production.
- **Privilege and process ownership**: FastAPI runs as `root`, while web files are owned by `www-data`. Create a dedicated unprivileged FastAPI system user, install only necessary permissions, and ensure database/application/log directories have least-privilege ownership.
- **Supply-chain exposure**: The application is cloned anonymously from GitHub `main`, Chef cookbooks originate from the public Supermarket, and the bootstrap script curls and executes the Chef installer. The Ansible migration should remove runtime Chef downloads, pin source revisions, and use approved artifact/package repositories.

### Technical Challenges

- **OS/platform contradiction**: Fedora 42/libvirt is declared, but the provisioning shell script and Nginx/security conventions are Ubuntu/Debian-specific. Decide whether to standardize on Ubuntu/Debian or port deliberately to Fedora/RHEL; do not consider the current Vagrant run a portable baseline. Maintain platform-specific variable/task files if both families are required.
- **Conflicting site document-root inputs**: Cookbook attributes use `/opt/server/...`, whereas `solo.json` overrides them with `/var/www/<site>`. Capture the intended environment-specific value in inventory variables and confirm where static content should reside before implementation.
- **Chef policy dependency ambiguity**: `nginx` and `ssl_certificate` appear in the Policyfile lock, but the reviewed local Nginx recipes manage Nginx and certificates themselves. Confirm whether they are historical/residual dependencies; avoid reproducing unused dependencies in Ansible.
- **Imperative and non-idempotent patterns**: Redis configuration is modified via a Ruby text substitution after cookbook generation; database creation relies on shell commands with `|| true`; certificate creation is command-based. Replace these with managed desired-state templates/modules and define safe upgrade/migration behavior for existing hosts.
- **Service integration gaps**: Nginx serves only static content and does not configure a proxy to Uvicorn on port 8000. Confirm whether FastAPI is intentionally accessed directly, is expected to be reverse-proxied, or requires an additional configuration before asserting end-to-end application availability.
- **Database lifecycle and application readiness**: The source only creates a user/database; it does not show schema migrations, PostgreSQL authentication policy, backups, or readiness checks. Define database migration ownership, backup/recovery requirements, and application health checks outside simple package provisioning.
- **Template and layout validation**: Nginx’s Debian-style `sites-available/sites-enabled` paths, `www-data` ownership, and the included templates require validation on the selected platform. Run `nginx -t`, `sshd -t`, and syntax validation before handler restarts.

### Migration Order

1. **Foundation and security baseline (nginx-multisite security portion)**: Select the supported OS/image; establish inventory, Vault/external secrets integration, package repositories, firewall access for automation, SSH hardening safeguards, sysctl settings, and test/rollback procedures. This is high priority because subsequent roles rely on safe remote access and consistent platform assumptions.
2. **Nginx multi-site and TLS role (`nginx-multisite`)**: Migrate Nginx installation, static site directories/content, virtual-host templates, handlers, and certificate strategy. Validate all three hostnames, HTTP-to-HTTPS behavior, port forwarding, headers, and certificate/key access. Use development self-signed certificates only where explicitly approved.
3. **Caching role (`cache`)**: Deploy Memcached and Redis with native packages, secret-managed Redis authentication, service enablement, configuration validation, and only the confirmed compatibility settings. Verify application connectivity and ensure Redis/Memcached are not unintentionally externally reachable.
4. **Application and database role (`fastapi-tutorial`)**: Implement PostgreSQL service/user/database management, Git artifact pinning, venv/dependency installation, secret-backed `.env`, dedicated service user, systemd unit, health checks, and any confirmed schema migration process. Execute integration testing after cache and database dependencies are available.
5. **Integrated cutover and retirement**: Compare Chef and Ansible outcomes, conduct security review and user acceptance testing, document operational runbooks/secret rotation, run Ansible in check and normal modes, then remove Chef Solo/Berkshelf provisioning from the Vagrant workflow after approval.

### Assumptions

- The only infrastructure-as-code technology in scope is Chef; no Puppet, Salt, PowerShell, or existing Ansible content is present in the supplied tree.
- The three directories under `cookbooks/` are the complete local cookbook inventory.
- The target operating system has not been finalized. Ubuntu/Debian is inferred from source behavior despite the Fedora 42 Vagrant box; production may require a separate RHEL/Fedora implementation decision.
- Vagrant/libvirt is a development/test environment, not proof of a production virtualization or cloud target.
- No cloud platform, production inventory, DNS management, CI/CD pipeline, monitoring, backup strategy, or enterprise PKI integration is specified.
- The repository does not disclose the FastAPI application’s requirements file, database schema/migration commands, reverse-proxy requirements, or application health endpoint; these must be confirmed with the application owner.
- `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` are intended hostnames, but DNS/host-file provisioning is outside the active source (the Vagrant host entries are commented out).
- The self-signed certificates, tutorial application, hardcoded passwords, and direct GitHub checkout appear development-oriented and must not be accepted unchanged for production.
- The listed Chef Supermarket dependencies and exact lock versions are the dependency baseline; locked dependencies that are not directly referenced by the reviewed local recipes require confirmation before equivalent Ansible dependencies are selected.
- The Chef metadata states Ubuntu 18.04+ and CentOS 7+ support, but no evidence establishes compatibility with current supported OS releases; platform validation is required.
