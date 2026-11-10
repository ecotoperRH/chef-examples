# MIGRATION FROM CHEF TO ANSIBLE

This is a Chef Infra Solo/local-mode repository containing three local cookbooks. The configured run list builds a security-hardened, TLS-enabled Nginx multi-site host, Redis and Memcached caches, and a Git-deployed FastAPI tutorial application with local PostgreSQL. Migration scope is moderate (three cookbooks), but the security/access controls, database and Redis passwords, TLS keys, external cookbook behavior, and cross-platform differences make it operationally sensitive. Estimate 3–5 weeks for a small platform team: design and current-state capture (one week), role implementation (one to two weeks), and integration/security/cutover testing (one to two weeks).

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and configures Memcached and Redis. Configures Redis on port 6379 with password authentication, uses `/run/redis` as its PID directory, creates `/var/log/redis`, enables Redis, and modifies generated Redis configuration to remove selected replica directives.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis service enablement; Redis authentication; SELinux-aware PID path; imperative configuration workaround.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from Git, installs Python and PostgreSQL dependencies, creates a virtual environment, installs Python requirements, provisions a PostgreSQL user/database, creates an application `.env`, and manages a Uvicorn systemd service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Fedora/RHEL and Debian package handling; PostgreSQL initialization on Fedora/RHEL; Git application deployment; Python virtualenv; local PostgreSQL; systemd service management.

- **nginx-multisite**:
  - Description: Configures Nginx for three SSL-enabled static virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), deploys their supplied index pages, generates development self-signed certificates, and applies host and web-server security controls.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx installation and service management; attribute-driven sites; HTTP-to-HTTPS redirects; self-signed TLS; virtual-host symlinks; Fail2ban; UFW; SSH root/password-login hardening; sysctl, security headers, and rate limits.

**CRITICAL PATH VERIFICATION:**

The three paths above are directories present in the supplied repository tree, and each contains a reviewed Chef primary entrypoint: `cookbooks/cache/recipes/default.rb`, `cookbooks/fastapi-tutorial/recipes/default.rb`, and `cookbooks/nginx-multisite/recipes/default.rb`. They are intentionally separate inventory entries. No Puppet `manifests/init.pp`, Salt states, or PowerShell `.psd1` manifests were identified.

### Infrastructure Files

- `Berksfile`: Declares local cookbook paths, Supermarket, and external cookbook constraints. Replace Chef dependency acquisition with documented OS repositories and, where needed, pinned Ansible collections in `collections/requirements.yml`.
- `Policyfile.rb`: Defines the `chef-examples` policy and run order: `nginx-multisite`, `cache`, then `fastapi-tutorial`. Translate to a top-level Ansible playbook with explicit role ordering and tags.
- `Policyfile.lock.json`: Locks the effective external dependencies: Memcached 6.1.0, Redisio 8.0.0, and Selinux 6.2.4. Use as a behavior/dependency baseline during parity testing.
- `solo.json`: Provides the active site document roots, SSL paths, and security settings. Convert to documented role defaults and environment/group variables; protect sensitive values with Vault or an external secret manager.
- `solo.rb`: Defines Chef Solo cache and cookbook paths. It has no direct Ansible equivalent; replace with documented inventory, role, collection, and `ansible.cfg` locations.
- `Vagrantfile`: Defines a Fedora 42 box, libvirt resources, private IP `192.168.121.10`, and HTTP/HTTPS forwarded ports. Retain as a disposable Ansible test target or replace with an equivalent test environment.
- `vagrant-provision.sh`: Installs Chef 18.8.54 and Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with an Ansible controller/bootstrap invocation and retire Chef tooling after cutover.
- `cookbooks/nginx-multisite/templates/`: ERB templates for Nginx, virtual hosts, Fail2ban, and sysctl. Convert to Jinja2 and retain syntax validation and handler behavior.
- `cookbooks/nginx-multisite/files/default/`: Static index pages for the three Nginx virtual hosts. Migrate with `ansible.builtin.copy`.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource not referenced by the reviewed default-recipe chain. Confirm whether it is unused before implementing an equivalent.
- `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`: Unreferenced auxiliary documentation/rule artifact. Confirm with maintainers whether it establishes migration process requirements.

### Target Details

- **Operating System**: Fedora 42 is explicit in the Vagrant box. Cookbook metadata also supports Ubuntu 18.04+ and CentOS 7+, while recipes distinguish Fedora/RHEL from Debian package names and PostgreSQL initialization. Implement RedHat and Debian variable files. If production OS is not confirmed, use Red Hat Enterprise Linux 9 as the planning default and validate packages/service names before delivery.
- **Virtual Machine Technology**: Vagrant using the libvirt provider; underlying virtualization is KVM/libvirt.
- **Cloud Platform**: Not specified; no cloud-specific tooling or metadata usage was found.

## Migration Approach

Create an Ansible repository with a `site.yml`, environment-separated inventory, and roles such as `baseline_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep site definitions, package mappings, TLS mode, firewall policy, and application revision in variables rather than task files. Prefer native idempotent modules over shell commands. Establish CI with `ansible-lint`, YAML checks, template validation, `nginx -t`, service checks, endpoint smoke tests, and idempotence runs on Vagrant/libvirt or other disposable instances.

Coordinate platform, security, and application/database owners. Platform should own role structure and OS abstractions; security should approve SSH/firewall/sysctl/Fail2ban/TLS/secret controls; application/database owners should approve application revision, package dependencies, service account, database settings, and health tests. Maintain a Chef-to-Ansible behavior matrix and require sign-off before Chef retirement.

### Key Dependencies to Address

- **Chef Infra Client 18.8.54 / Chef Solo**: Remove after cutover; use `ansible-playbook` from controlled CI/CD or an automation runner.
- **Berkshelf / Chef Supermarket**: Replace cookbook resolution with OS package repositories and pinned Ansible collection requirements when non-core modules are used.
- **memcached cookbook (~> 6.0; lock 6.1.0)**: Use `ansible.builtin.package` and `ansible.builtin.service`. The local recipe delegates details to the external cookbook, so capture the present host configuration before asserting parity.
- **redisio cookbook (lock 8.0.0)**: Use distribution Redis packages, a declarative Redis template, directory/ownership tasks, service management, and SELinux context tasks where applicable. Model port, authentication, PID location, and replica settings directly.
- **selinux cookbook (transitive; lock 6.2.4)**: Use `ansible.posix.selinux` and persistent file-context management. Verify labels for `/run/redis`, including behavior after reboot.
- **Nginx package**: Use `ansible.builtin.package`, Jinja2 templates, `nginx -t` before applying changes, and handler-driven reloads. The Berksfile Nginx cookbook constraint is not in the Policyfile lock; confirm whether it is stale.
- **PostgreSQL**: Use OS packages plus `community.postgresql.postgresql_user`, `postgresql_db`, and `postgresql_privs`; document the required collection and Python PostgreSQL driver.
- **Git, Python, pip, and virtualenv**: Use `ansible.builtin.git`, package tasks, and `ansible.builtin.pip`. Pin the current moving `main` branch to an approved commit or tag.
- **OpenSSL/CA certificates**: Use package management and `community.crypto` only for development certificates; use approved CA/ACME/PKI and secret delivery in production.
- **Fail2ban, firewall, SSH, sysctl**: Use `community.general.ufw` only for UFW-capable Debian targets and `ansible.posix.firewalld` for Fedora/RHEL. Use templating/validated edits for SSH and `ansible.posix.sysctl` for kernel parameters.

### Security Considerations

- **`cache` Redis password**: `redis_secure_password_123` is hardcoded in the recipe. Move to Ansible Vault or an external secret manager, rotate it, avoid outputting it in logs, and constrain Redis network exposure.
- **`fastapi-tutorial` database/application password**: `fastapi_password` is hardcoded in PostgreSQL commands and written in the `.env` database URL. Vault/generate and rotate it, use database modules rather than password-bearing shell commands, and make the resulting environment file owned by the application account with mode `0600`.
- **Root application service**: The FastAPI systemd unit runs as `root`. Replace with a dedicated non-login service account and assess systemd hardening such as `NoNewPrivileges`, `PrivateTmp`, and restricted read/write paths.
- **`nginx-multisite` TLS material**: The cookbook creates 2048-bit RSA, 365-day self-signed certificates and group-readable private keys in `/etc/ssl/private`. This is appropriate only for development. Use an approved certificate lifecycle, vaulted private material, least-privilege file access, and automated renewal in production.
- **SSH and firewall lockout risk**: Source behavior sets default-deny UFW, permits SSH/HTTP/HTTPS, disables SSH root login, and disables password authentication. Apply only after confirmed key-based access and console/break-glass recovery. UFW is not the standard Fedora 42 firewall interface, so validate intent on the target OS.
- **Nginx hardening**: Preserve TLS 1.2/1.3, HSTS, server-token suppression, security headers, dotfile/VCS denial, and limits. Security/application owners should review `unsafe-inline` CSP allowances and 1 KB request/body/header limits.
- **Fail2ban and sysctl**: Security-review converted templates and reload only after configuration validation.
- **Credential-pattern summary**: `cache` contains a plaintext Redis password. `fastapi-tutorial` contains a plaintext PostgreSQL password/database URL. `nginx-multisite` creates TLS private keys and references certificate paths. No Chef encrypted data bags, Chef Vault, or other secret source was found in reviewed metadata, run lists, or entry recipes.

### Technical Challenges

- **OS/platform divergence**: Fedora 42 is the active VM while metadata includes Ubuntu and obsolete CentOS 7. Package names, PostgreSQL initialization, Nginx layout, firewall tooling, SELinux, and service names differ. Decide supported platforms early and test each explicitly.
- **Chef attribute precedence**: The Nginx default attributes use `/opt/server/...`, but `solo.json` supplies `/var/www/...`; the JSON values are expected to take precedence in the configured Solo run. Define one Ansible variable hierarchy and test rendered roots and ownership.
- **Opaque external cookbook behavior**: Memcached and most Redis configuration comes from external cookbook dependencies not present as local source. Capture actual rendered files and runtime state before implementing parity.
- **Imperative patterns**: The Redis Ruby block mutates generated configuration, and PostgreSQL creation uses `psql ... || true`. Replace with templates and database modules to produce observable, idempotent state.
- **Application supply chain**: The source tracks a public Git `main` branch and installs its requirements without a repository-level lock visible in Chef. Pin/approve application and Python dependency versions, ideally via internal mirrors/artifacts, with a rollback plan.
- **Service integration ambiguity**: Nginx serves static sites while FastAPI listens on 8000; reviewed Nginx configuration does not proxy to FastAPI. Confirm intended exposure before building ingress.
- **Cutover safety**: Firewall, SSH, Nginx, database, and Redis changes can affect both availability and administrator access. Use canaries, snapshots, backups, smoke tests, and a tested rollback plan.

### Migration Order

1. **Foundation and verification**: Establish repository layout, inventory, secret management, OS variables, Vagrant/libvirt testing, CI, and current-state capture. Confirm target OS, firewall, TLS, and access strategy.
2. **Nginx multisite and baseline security**: Migrate static content, sites, Nginx templates/handlers, TLS modes, Fail2ban, sysctl, SSH, and OS-appropriate firewall policy. Verify safe administrator access before enforcement.
3. **Cache services**: Migrate Memcached and Redis, introduce vaulted Redis credentials, validate SELinux contexts, and test service restart/client connectivity.
4. **PostgreSQL and FastAPI**: Provision PostgreSQL roles/database, deploy a pinned application revision and virtualenv, manage protected configuration, run FastAPI as a dedicated account, and execute application/database smoke tests.
5. **Integrated cutover and Chef retirement**: Perform security and idempotence regression testing, complete a canary/parallel deployment, obtain sign-off, update operations documentation, and remove Chef/Berkshelf after the rollback window.

### Assumptions

- The Policyfile and `solo.json` define the intended deployment path; no Chef server, environments, roles, data bags, encrypted data bags, or Chef Vault configuration appeared in the supplied tree.
- `cookbooks/cache`, `cookbooks/fastapi-tutorial`, and `cookbooks/nginx-multisite` are the complete local Chef cookbook inventory because each has `recipes/default.rb`; no other source technology modules were identified.
- Fedora 42/libvirt is a development/test target and may not be production. Production OS/version/support lifecycle require confirmation.
- The external Nginx Berksfile dependency may be stale because the local recipe uses a direct package resource and the dependency is absent from the reviewed Policyfile lock.
- The commented `ssl_certificate` Berksfile dependency is inactive.
- Self-signed certificates, local hostnames, and static pages appear development-oriented. DNS, ingress, CA, and renewal requirements are unspecified.
- Database schema migration, application health endpoint, runtime settings beyond `.env`, and Python dependency locking require confirmation from the application owner.
- Redis and PostgreSQL appear local-only based on reviewed source; required exposure, backups, replication, persistence, and monitoring are unspecified.
- The custom Chef `lineinfile` resource is assumed unused pending maintainer confirmation.
- Visible passwords are assumed non-production examples but must be treated as exposed and rotated before production migration.
