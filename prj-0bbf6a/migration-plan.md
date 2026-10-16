# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a Chef Solo/Policyfile project with exactly three local Chef cookbooks requiring migration: `cookbooks/cache`, `cookbooks/fastapi-tutorial`, and `cookbooks/nginx-multisite`. The deployment configures Redis and Memcached, a PostgreSQL-backed FastAPI application, Nginx virtual hosts, TLS, firewall rules, Fail2ban, sysctl settings, and SSH hardening. The migration is small in module count but moderate in complexity because it contains hardcoded credentials, database bootstrap logic, security controls, generated certificates, systemd services, and inconsistent operating-system assumptions.

Estimated delivery is **2–4 weeks** for an experienced engineer for a tested development migration, or **4–6 weeks** including production certificate integration, security review, OS standardization, secret rotation, application packaging, and cutover. Team coordination should assign owners for platform/OS, Nginx/security, data services, application runtime, secrets, and acceptance testing.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning.

### MODULE INVENTORY

The repository tree shows three directories containing `recipes/default.rb`. Each is listed separately below; no Puppet `manifests/init.pp` modules or PowerShell `.psd1` modules were found.

- **cache**
  - Description: Configures Memcached and Redis caching services, including Redis authentication, log-directory creation, service enablement, and a compatibility workaround for generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef cookbook
  - Primary entrypoint: `cookbooks/cache/recipes/default.rb`
  - Key Features: Includes the `memcached` and `redisio` cookbooks; configures Redis on port 6379; currently embeds a Redis password; creates `/var/log/redis`; enables Redis.
  - Ansible migration: Create a cache role using supported Redis/Memcached packages or vetted roles. Store credentials in Ansible Vault or an external secret manager, explicitly define bind/access policy, and replace the Ruby file-edit workaround with a tested configuration template.

- **fastapi-tutorial**
  - Description: Installs Python and PostgreSQL prerequisites, deploys the FastAPI tutorial application, creates a virtual environment, installs Python dependencies, initializes a PostgreSQL database/user, writes environment configuration, and runs Uvicorn through systemd.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef cookbook
  - Primary entrypoint: `cookbooks/fastapi-tutorial/recipes/default.rb`
  - Key Features: Clones `https://github.com/dibanez/fastapi_tutorial.git` from mutable `main`; installs Python, pip, venv, Git, PostgreSQL, and libpq; creates `fastapi`/`fastapi_db`; writes `.env`; exposes Uvicorn on `0.0.0.0:8000`; runs the service as root.
  - Ansible migration: Split database and application responsibilities where practical. Use `ansible.builtin.git`, package and virtual-environment tasks, `community.postgresql` modules, a templated systemd unit, a dedicated service account, pinned application revisions, and Vault-managed credentials.

- **nginx-multisite**
  - Description: Installs and configures Nginx for multiple sites, deploys site content and virtual-host files, creates development TLS certificates, and applies host security controls.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef cookbook
  - Primary entrypoint: `cookbooks/nginx-multisite/recipes/default.rb`
  - Key Features: Includes the `security`, `nginx`, `ssl`, and `sites` recipes; manages Nginx templates and service; creates `sites-available`/`sites-enabled` links; deploys `ci`, `status`, and `test` static content; configures Fail2ban, UFW, sysctl, SSH settings, and self-signed RSA certificates.
  - Ansible migration: Convert ERB templates to Jinja2, attributes to documented inventory/group variables, cookbook files to role files, and Chef notifications to handlers. Use `nginx -t` before reload, platform-appropriate firewall modules, and a production CA/renewal process rather than self-signed certificates.

**CRITICAL PATH VERIFICATION:** All three paths above are directory paths shown in the supplied repository tree. Their `metadata.rb` and `recipes/default.rb` files were reviewed. No nonexistent module paths are included.

### Infrastructure Files

- `Berksfile`: Declares the local cookbooks and external Chef dependencies `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; the `ssl_certificate` declaration is commented out. Replace this with pinned Ansible collection/role requirements.
- `Policyfile.rb`: Defines policy `nginx-multisite-policy` and run list `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`.
- `Policyfile.lock.json`: Locks local cookbook versions at 1.0.0 and external versions including Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and `ssl_certificate` 2.1.0. Treat the lock as source evidence, not as a direct Ansible version mapping.
- `Vagrantfile`: Uses `generic/fedora42`, Vagrant/libvirt, 2 CPUs, 2 GB RAM, private IP `192.168.121.10`, and forwarded guest ports 80/443 to host ports 8080/8443. It invokes `vagrant-provision.sh`.
- `vagrant-provision.sh`: Installs Chef through a remote script, uses `apt-get`, installs Berkshelf, vendors dependencies, and runs Chef Solo. Replace with an Ansible Vagrant provisioner or an explicit `ansible-playbook` workflow.
- `solo.rb`: Chef Solo configuration; map cookbook paths and run configuration to Ansible project structure and inventory.
- `solo.json`: Chef node attributes; migrate its site, SSL, and security data to host/group variables, with secrets separated into Vault.
- `cookbooks/nginx-multisite/attributes/default.rb`: Source of Nginx site, SSL, and security attributes. Convert to validated Ansible variables.
- `cookbooks/nginx-multisite/templates/`: Nginx, Fail2ban, sysctl, and site templates. Convert ERB to Jinja2.
- `cookbooks/nginx-multisite/files/`: Static `ci`, `status`, and `test` pages. Preserve as Ansible role files.
- `project-plan.md`: Existing project context to reconcile with the migration backlog and acceptance tests.

### Target Details

- **Operating System**: Development configuration says Fedora 42, but `vagrant-provision.sh` uses `apt-get`, while recipes use Debian-style names/users and UFW. The production OS is unspecified. Resolve this before implementation. If no decision is available, use RHEL 9 as the baseline and adapt package names, service names, SELinux, firewall, and web-user settings. Alternatively standardize on Ubuntu and correct the Fedora box.
- **Virtual Machine Technology**: Vagrant using the libvirt provider; 2 CPUs and 2048 MB memory.
- **Cloud Platform**: Not specified; no AWS, Azure, or GCP configuration was found.

## Migration Approach

### Key Dependencies to Address

- **nginx 12.3.1 cookbook**: Replace with native Ansible package, template, link, service, and handler tasks or a vetted role.
- **memcached 6.1.0 cookbook**: Replace with OS packages and explicit configuration, service, listen address, and firewall policy.
- **redisio 7.2.4 cookbook**: Replace with a supported Redis role or template implementation; preserve authentication and test persistence, binding, and service behavior.
- **selinux 6.2.4**: This is a transitive locked dependency. Define SELinux mode, labels, booleans, and allowed ports explicitly if RHEL is selected.
- **ssl_certificate 2.1.0**: It appears in the lock file but is not actively declared in the Berksfile and is not visibly used by the reviewed local recipes. Confirm whether it is required; use ACME or the organization’s certificate platform for production.
- **PostgreSQL**: Use `community.postgresql` for users, databases, and grants instead of shell commands that suppress errors with `|| true`.
- **Python/pip dependencies**: Pin the external Git revision and Python dependencies; do not deploy mutable `main` without an approved release process.
- **Ansible collections**: Pin `ansible.posix`, `community.general`, and `community.postgresql` versions in `collections/requirements.yml` as required by the implementation.

### Security Considerations

- **Redis secret**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Treat it as exposed, rotate it, and store the replacement in Vault or an external secret manager.
- **PostgreSQL secret**: `cookbooks/fastapi-tutorial/recipes/default.rb` contains `fastapi_password` in SQL and the generated database URL. Rotate it and remove it from command strings and source control.
- **Application secret file**: The source creates `.env` with mode `0644`. Use mode `0600`, controlled ownership, and secret injection where possible.
- **Root service**: The FastAPI systemd unit runs as root. Create a dedicated least-privilege service account and restrict application directories.
- **TLS keys**: Self-signed certificates and private keys are generated locally. Preserve this only for development; use managed certificates, renewal, strict key permissions, and separate production secret handling.
- **SSH hardening**: Root login and password authentication may be disabled by editing `sshd_config`. Use validated Ansible-managed configuration, ensure key-based access first, and test before restarting SSH.
- **Firewall**: UFW defaults to deny and allows SSH/HTTP/HTTPS. Use `ansible.posix.firewalld` on RHEL or UFW on Ubuntu. Confirm whether port 8000 must remain private behind Nginx.
- **Network exposure**: Uvicorn binds to all interfaces. Prefer loopback or a private interface unless direct exposure is explicitly required.
- **Supply chain**: Replace remote Chef installation and mutable Git/pip inputs with trusted repositories, pinned versions, checksums or immutable commits, and CI scanning.
- **Per-module credential summary**: `cache` contains Redis credentials; `fastapi-tutorial` contains PostgreSQL credentials and an environment file; `nginx-multisite` manages private TLS keys but only visibly generates development certificates. No encrypted data bags or Chef Vault references were found in reviewed files.

### Technical Challenges

- Resolve Fedora/`apt-get`/Ubuntu-CentOS support mismatch before writing portable tasks.
- Translate Chef node attribute precedence into an explicit Ansible inventory and variable schema for sites, document roots, SSL paths, and security switches.
- Convert ERB templates and delayed Chef notifications into Jinja2 templates and Ansible handlers with Nginx syntax validation.
- Replace non-idempotent SQL shell blocks with declarative PostgreSQL modules and separate schema migrations from host provisioning.
- Make application deployment repeatable by pinning Git and Python dependencies and adding service health checks.
- Reproduce Redis behavior without the direct configuration rewrite until its version-specific purpose is understood.
- Separate development self-signed TLS from production certificate issuance and DNS requirements.
- Add Molecule or equivalent integration tests covering Nginx, TLS, firewall, Redis authentication, PostgreSQL connectivity, and FastAPI health.

### Migration Order

1. Confirm target OS, inventory, DNS, certificate authority, secret manager, service-account standard, and rollback approach.
2. Create Ansible project structure, pin collections, and build the Vagrant/libvirt test workflow.
3. Migrate `nginx-multisite` baseline: packages, templates, static files, virtual hosts, service handlers, and development TLS.
4. Migrate Nginx security controls: SSH, firewall, sysctl, and Fail2ban, with a security-team review.
5. Migrate `cache`; rotate Redis credentials and validate Redis/Memcached binding and access policy.
6. Migrate PostgreSQL and FastAPI prerequisites, pin application inputs, and move credentials to Vault.
7. Migrate the systemd application service, integrate it behind Nginx if intended, and run end-to-end tests.
8. Perform Chef/Ansible comparison, acceptance testing, security sign-off, cutover, rollback rehearsal, and Chef decommissioning.

### Assumptions

- The three local cookbooks listed in the MODULE INVENTORY are the complete migration scope.
- The Policyfile run list represents the intended deployment sequence.
- External cookbook implementation details are unavailable locally and require behavior validation.
- Fedora 42 is a development choice, not proof of the production OS.
- Site definitions and security values are supplied by Chef attributes/node data; their final values must be captured from `solo.json` and `attributes/default.rb` during implementation.
- The external FastAPI repository, schema, health endpoint, and dependency lock state are not fully represented here.
- Self-signed certificates are development-only unless the owner explicitly states otherwise.
- Redis persistence/replication, Memcached exposure, monitoring, backups, production DNS, load balancing, and disaster recovery are not specified.
- Existing hardcoded credentials may already be compromised and must be rotated.
- Timeline assumes access to platform, security, application, and database owners plus a representative test environment.
