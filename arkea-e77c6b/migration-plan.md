# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile-based development environment containing three local Chef cookbooks, provisioned in a Vagrant/libvirt virtual machine. It delivers an NGINX multi-site HTTPS front end with host hardening, Redis and Memcached caching, and a FastAPI tutorial application backed by a locally hosted PostgreSQL database. The migration scope is moderate: the resource set is small, but the application/database bootstrap, generated TLS material, firewall/SSH changes, and operating-system inconsistency require careful validation.

A practical delivery estimate is **2–4 weeks** for an engineer familiar with Ansible, including role implementation, test-environment correction, automated validation, and documentation/knowledge transfer. The configuration is most naturally migrated into a small Ansible playbook with separate roles for web/security, cache, and application/database services, rather than a literal cookbook-for-role translation.

## Module Migration Plan

This repository contains **Chef cookbooks** that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Provisions NGINX as a three-site web server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; deploys static index pages; creates NGINX virtual-host configuration; enables self-signed TLS; and applies host/web security hardening.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: NGINX service installation and enablement, site-specific document roots and static content, generated self-signed RSA-2048 certificates, NGINX configuration templates, Fail2ban, UFW default-deny policy with SSH/HTTP/HTTPS exceptions, sysctl hardening, and SSH root/password-login disablement.

- **cache**:
  - Description: Installs and enables Memcached and Redis, configures Redis to listen on port 6379 with password authentication, and creates the Redis log directory. It also directly edits the Redis configuration to remove selected replica-related settings as a compatibility workaround.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached cookbook inclusion, Redis service installation/enablement through `redisio`, Redis password configuration, `/var/log/redis` ownership and permissions, and an imperative Redis configuration cleanup block.

- **fastapi-tutorial**:
  - Description: Deploys the external `dibanez/fastapi_tutorial` Git repository as a root-run systemd service, builds a Python virtual environment, installs Python requirements, and provisions a local PostgreSQL database and application user.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python/Git/PostgreSQL package installation, Git checkout of the `main` branch, virtual environment and pip dependency installation, PostgreSQL service management, database/user/grant bootstrap, generated application `.env`, and Uvicorn systemd service on port 8000.

**CRITICAL PATH VERIFICATION:**

All paths above were explicitly present in the supplied repository tree and their Chef primary recipes (`recipes/default.rb`) were reviewed. No Puppet modules, Salt states, PowerShell modules, or additional Chef cookbooks were identified.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and external cookbook constraints. It is replaced by Ansible Galaxy collections/roles only where needed; most required functionality is available through built-in modules and `community.postgresql`.
- `Policyfile.rb`: Defines policy `nginx-multisite-policy` and run order: NGINX/security first, then cache services, then the FastAPI/PostgreSQL application. Translate this into an inventory-targeted playbook and role ordering/handler dependencies.
- `Policyfile.lock.json`: Locks the Chef resolution to NGINX 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SSL Certificate 2.1.0, and transitive SELinux 6.2.4. Use it as the dependency baseline and document the chosen OS package and Ansible collection versions; it also shows that the locked policy differs from the active Berksfile declaration for `ssl_certificate`.
- `solo.rb`: Chef Solo configuration pointing to `/chef-repo/cookbooks`. It has no direct Ansible equivalent; replace it with `ansible.cfg`, inventory, playbook entrypoints, and role paths.
- `solo.json`: Chef run list and runtime attribute overrides for sites, certificate locations, Fail2ban/UFW, and SSH hardening. Convert these to role defaults plus environment-specific group variables. Note that its site document roots differ from the cookbook defaults.
- `Vagrantfile`: Defines the development VM as `generic/fedora42`, with libvirt, 2 GB memory, 2 CPUs, private IP `192.168.121.10`, and host-forwarded HTTP/HTTPS ports. Retain or replace it with an Ansible-driven Vagrant provisioner and correct its platform mismatch before using it as acceptance-test infrastructure.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef from Omnitruck, invokes Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with Python/SSH bootstrap as necessary and `ansible-playbook`; do not retain curl-piped Chef installation.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, TLS-directory, firewall, Fail2ban, and SSH-hardening values. Migrate to typed, documented Ansible role defaults.
- `cookbooks/nginx-multisite/templates/default/*.erb`: NGINX, virtual-host, security header/configuration, Fail2ban jail, and sysctl templates. Translate to Jinja2 templates and validate rendered syntax before reloading services.
- `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html`: Static site content to deploy to the corresponding document roots.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource for line-oriented file edits and timestamped backups. It is not called by the reviewed primary recipe chain; if retained functionality is later required, replace it with `ansible.builtin.lineinfile` and explicit backup policy.
- `project-plan.md`: Project documentation that should be reviewed by the migration team for business requirements, ownership, and acceptance criteria; it was not required to establish cookbook inventory.

### Target Details

- **Operating System**: The declared Chef cookbook support is Ubuntu 18.04+ and CentOS 7+. Actual implementation strongly favors Debian/Ubuntu (`apt-get`, UFW, `www-data`, `/etc/nginx/sites-available` and `sites-enabled`, and service name `ssh`). The Vagrant box is Fedora 42, which conflicts with these assumptions and will not reliably support the provisioner or layout. Select and explicitly support **Ubuntu 22.04/24.04** for functional parity, or redesign the roles for a RHEL/Fedora family using DNF, firewalld, `nginx` ownership conventions, and appropriate service/configuration paths.
- **Virtual Machine Technology**: Vagrant with the **libvirt** provider. The supplied Vagrant environment uses an rsync shared folder and private/forwarded networking.
- **Cloud Platform**: Not specified. No cloud provider configuration or metadata integration was identified.

## Migration Approach

Create an Ansible repository with a top-level playbook (for example, `playbooks/site.yml`), inventories for development and later environments, and roles such as `nginx_multisite`, `host_security`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep environment-specific values—site list, document roots, firewall policy, certificate source, application revision, and database parameters—in `group_vars` rather than embedded in tasks.

Use idempotent package, template, service, Git, Python virtual-environment, PostgreSQL, file, and firewall modules. Implement handlers so configuration changes validate first and then reload NGINX, restart Fail2ban, reload sysctl, and reload/restart systemd services only as needed. Build Molecule or Vagrant/libvirt smoke tests that verify package/service state, HTTP/HTTPS virtual-host responses, firewall reachability, SSH policy, Redis authentication, database connectivity, and FastAPI health before decommissioning Chef.

### Key Dependencies to Address

- **Chef Infra Client/Solo (Chef >= 16.0)**: Remove Chef client, Berkshelf, `solo.rb`, and JSON run-list dependency. Use `ansible-core`, SSH connectivity, inventories, roles, and CI lint/test workflows.
- **Chef Berkshelf and Policyfile**: Replace cookbook resolution and lock management with pinned Ansible collection requirements (for example `requirements.yml`) and a documented, tested package baseline. Preserve the Policyfile execution order as role sequencing where it is meaningful.
- **Chef Supermarket `nginx` cookbook (locked 12.3.1; declared `~> 12.0`)**: Replace with distribution package management, `template`, `file`, and `service` tasks. Do not replicate the external cookbook unless the unreviewed dependency behavior is proven necessary.
- **Chef Supermarket `memcached` cookbook (locked 6.1.0; declared `~> 6.0`)**: Install and manage the OS Memcached package and service using Ansible. Capture any required listen address, memory, or authentication settings because they are not configured locally.
- **Chef Supermarket `redisio` cookbook (locked 7.2.4)**: Use the OS Redis package and service, render a controlled Redis configuration, set authentication through Ansible Vault, and avoid direct post-install text deletion. The lock shows a transitive `selinux` cookbook dependency that is only relevant if a RHEL-family target is selected.
- **Chef Supermarket `ssl_certificate` cookbook (locked 2.1.0)**: It appears in `Policyfile.rb` and the lock but is commented out in `Berksfile`; the local NGINX cookbook directly invokes OpenSSL instead. Resolve this inconsistency. Prefer organization-issued certificates/ACME automation in production; use controlled development self-signed certificates only where justified.
- **PostgreSQL server and client utilities**: Replace raw `psql` shell commands with `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_privs`, with `become_user: postgres`. Add `community.postgresql` to collection requirements.
- **Python, pip, and upstream FastAPI source**: Use Ansible package management, `ansible.builtin.git` pinned to an immutable tag or commit, `ansible.builtin.pip` with a virtual environment, and a systemd unit template. Review and pin the external repository's Python dependency lock state before deployment.
- **Vagrant/libvirt**: Retain for local testing only if required. Provision with `ansible_local` or a host-run Ansible workflow after correcting the VM OS; production target platform is not defined.

### Security Considerations

- **Hardcoded Redis credential in `cache`**: `redis_secure_password_123` is directly embedded in `cookbooks/cache/recipes/default.rb`. Store the Redis password in Ansible Vault or an approved external secret manager, render it with restrictive permissions, rotate it during migration, and ensure clients are updated.
- **Hardcoded PostgreSQL/application credential in `fastapi-tutorial`**: The recipe creates the `fastapi` database user with password `fastapi_password` and writes the same password into `DATABASE_URL` in `/opt/fastapi-tutorial/.env`. Replace with Vault-managed database credentials, create the file with application-user ownership and mode `0600`, and rotate the database role/password. The current Chef `.env` mode is `0644`, exposing database credentials to all local users.
- **TLS certificates in `nginx-multisite`**: The cookbook generates self-signed certificates with private keys under `/etc/ssl/private`, group `ssl-cert`, mode `0710` for the directory and `0640` for keys. Preserve or tighten private-key access, never put production keys in Git, and use Vault/certificate automation or an enterprise PKI for non-development environments. The certificate generator explicitly uses `-nodes`, so encrypted-at-rest private-key protection is not provided by a key passphrase.
- **SSH access hardening in `nginx-multisite`**: Root login and password authentication are disabled using `sed` against `sshd_config`. Use `ansible.builtin.lineinfile` or a managed SSH drop-in, validate configuration with `sshd -t`, and ensure SSH public-key/break-glass access is verified before changes to avoid lockout.
- **Firewall and intrusion prevention in `nginx-multisite`**: The source makes UFW default-deny and allows only SSH, HTTP, and HTTPS, while enabling Fail2ban. Implement the chosen firewall backend conditionally by OS family; test management access and required FastAPI/Redis/PostgreSQL exposure policy. These latter services should remain private by default.
- **Application privilege model in `fastapi-tutorial`**: The FastAPI systemd unit runs as `root`, and its application directory is root-owned. Create a dedicated unprivileged system account, restrict writable paths, and use systemd hardening options appropriate to the application.
- **Supply-chain exposure**: The bootstrap script downloads Chef installer code via `curl | bash`; application code tracks the mutable Git `main` branch; pip installs requirements from the checked-out repository. Eliminate the Chef bootstrap, pin source revision and Python artifacts, and use approved package/Git/Python indexes with integrity controls.
- **Visible credential patterns by module**: `cache` contains a hardcoded Redis password; `fastapi-tutorial` contains a hardcoded PostgreSQL password and a plaintext database URI in `.env`; `nginx-multisite` contains generated TLS private keys and uses an administrative email in certificate subject data but no stored user credential. No Chef encrypted data bags, Chef Vault usage, or environment-variable secret injection were found in the reviewed files.

### Technical Challenges

- **Target OS contradiction**: Fedora 42 is declared in Vagrant, while provisioning runs `apt-get` and the NGINX/SSH/firewall implementation assumes Ubuntu/Debian. Decide the supported OS before implementation; use Ubuntu for parity or formally build and test OS-specific task files. Do not use the current Vagrant result as proof of cross-platform correctness.
- **Configuration drift between defaults and runtime attributes**: Cookbook attributes place site content under `/opt/server/...`, while `solo.json` overrides the same sites to `/var/www/...`. Establish a single Ansible variable contract and document precedence per environment, then test the actual rendered document roots and content deployment.
- **Imperative Chef shell/Ruby workarounds**: Redis configuration is changed by a Ruby block that deletes a list of lines after cookbook generation; database creation relies on shell commands with `|| true`; SSH settings use in-place `sed`. Replace these with declarative Ansible modules/templates and explicit idempotence. Validate the reason for the Redis replica-directive removal against the selected Redis version before preserving it.
- **External application uncertainty**: The repository does not contain the FastAPI source or its Python requirements; it retrieves a mutable external Git branch at deploy time. Coordinate with application owners to identify the supported revision, runtime entrypoint, migration/schema steps, configuration schema, health endpoint, and production service account before cutover.
- **Service integration gap**: No reverse-proxy configuration reviewed here explicitly maps NGINX virtual hosts to FastAPI port 8000; the NGINX sites primarily deploy static content. Confirm whether FastAPI is intentionally independent, requires an upstream proxy route, or is only a tutorial component, then model the intended network boundary.
- **Narrow test coverage and inconsistent documentation**: The shell script advertises `192.168.56.10`, while Vagrant configures `192.168.121.10`. Add automated assertions and update runbooks rather than carrying forward incorrect access documentation.

### Migration Order

1. **Foundation and target-platform decision**: Confirm Ubuntu-versus-RHEL support, choose the authoritative inventory/environment model, correct Vagrant provisioning, establish Ansible version/collection pinning, CI linting, Vault/secret-manager access, and test criteria. This prevents a role design around incompatible package managers and paths.
2. **nginx-multisite / host security**: Migrate NGINX, static sites, NGINX templates, TLS strategy, Fail2ban, sysctl, firewall, and SSH hardening as separate but coordinated roles. Test access before enforcing SSH/firewall policy and test all three HTTP/HTTPS virtual hosts.
3. **cache**: Migrate Memcached and Redis with version-compatible configuration and Vault-sourced Redis authentication. Replace the Ruby cleanup hack with a complete rendered Redis configuration and service validation.
4. **fastapi-tutorial and PostgreSQL**: Migrate PostgreSQL role/user/database provisioning and the FastAPI deployment after secrets, application revision, Python dependency controls, user privileges, and application acceptance tests are agreed. This is the highest-risk functional component because it depends on an external mutable source repository and a local database.
5. **Parallel-run validation and Chef retirement**: Run Chef and Ansible only in isolated comparable test hosts where necessary, compare service/configuration outcomes, perform rollback rehearsal, update operations documentation, transfer ownership, and remove Chef/Berkshelf bootstrap artifacts after sign-off.

### Assumptions

- This plan covers only the three local cookbooks found under `cookbooks/`; external Chef cookbook internals were not present in the supplied tree and were not audited.
- Chef is currently applied using Chef Solo and the run list in `solo.json`/`Policyfile.rb`, rather than a Chef Server-managed node workflow.
- Ubuntu/Debian is the likely intended runtime because of `apt-get`, UFW, Debian NGINX paths, `www-data`, and the `ssh` service name, despite the Fedora Vagrant box and CentOS support metadata.
- The Vagrant/libvirt machine is a development/test environment, not evidence of the intended production virtualization or cloud platform.
- The three named NGINX sites are development-style hostnames, and locally generated self-signed certificates are intended only for development; production certificate requirements are unspecified.
- Redis, Memcached, PostgreSQL, and FastAPI are expected to run on the same host unless inventory design states otherwise. No remote database, cache, or cloud managed-service configuration was found.
- The FastAPI Git repository, branch, application dependencies, and Uvicorn entrypoint are assumed reachable and valid at deployment time, but they need application-owner confirmation and immutable version pinning.
- No database schema migration, backup/restore, monitoring, log aggregation, health-check endpoint, SELinux policy, or production high-availability configuration was found in the reviewed source and must be designed separately if required.
- The included NGINX templates were identified as supporting configuration artifacts but were not exhaustively audited; their directives must be translated and tested for semantic equivalence during implementation.
- Team coordination should assign clear owners for platform/Ansible standards, security and secret rotation, application/database acceptance, network/firewall approval, and Vagrant/CI test automation. Maintain a migration decision log and require functional plus security sign-off before Chef retirement.
