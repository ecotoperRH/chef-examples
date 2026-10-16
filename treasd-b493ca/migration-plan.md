# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Berkshelf deployment with three local cookbooks and a Vagrant/libvirt test environment. The migration scope is modest in component count but moderate in risk because it combines Nginx multi-site TLS and host hardening, Redis/Memcached, and a FastAPI/PostgreSQL application. A realistic initial migration is approximately 2–4 engineering weeks, including Ansible implementation, secret remediation, Fedora/Ubuntu compatibility decisions, and validation. A production-ready migration with certificate issuance, database lifecycle design, CI testing, and controlled cutover should be planned for approximately 4–6 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web-server cookbook for three SSL-enabled sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), static document roots, security headers/configuration, Fail2ban, UFW firewall rules, SSH hardening, sysctl settings, and development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Includes separate security, Nginx, SSL, and sites recipes; renders Nginx and site templates; creates site symlinks; enables Nginx; disables root SSH login and password authentication; allows SSH/HTTP/HTTPS; generates RSA self-signed certificates.

- **cache**:
    - Description: Cache-service cookbook that installs and enables Memcached and Redis, creates the Redis log directory, configures a Redis listener on port 6379, and applies a post-generation configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Uses the external `memcached` and `redisio` cookbooks; configures Redis authentication; enables Redis; edits generated Redis configuration to remove replication-related directives.

- **fastapi-tutorial**:
    - Description: Host provisioning cookbook for a FastAPI tutorial application, including Python tooling, PostgreSQL server packages, source checkout, virtual environment, Python dependencies, database/user creation, environment configuration, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Clones `https://github.com/dibanez/fastapi_tutorial.git` at `main`; installs Python 3, pip, venv, Git, PostgreSQL, and `libpq-dev`; runs Uvicorn on `0.0.0.0:8000`; starts PostgreSQL and the application service.

The `nginx-multisite` recipes (`security.rb`, `nginx.rb`, `ssl.rb`, and `sites.rb`) are internal cookbook components, not separate cookbooks/modules. Likewise, the external `nginx`, `memcached`, `redisio`, `selinux`, and `ssl_certificate` entries are dependencies, not local module inventory items.

**CRITICAL PATH VERIFICATION:**
All listed cookbook paths are present in the provided repository tree. No Puppet, Salt, or PowerShell modules were identified. The repository is Chef-based because it contains Ruby cookbook metadata/recipes, Berkshelf and Policyfile configuration, Chef Solo configuration, and Chef provisioning scripts.

### Infrastructure Files

- `Berksfile`: Declares the local cookbooks and external Supermarket dependencies used for dependency resolution and vendoring. Replace with an Ansible collection/role dependency strategy, typically `requirements.yml` plus pinned collection versions.
- `Policyfile.rb`: Defines the Chef policy name, run list, local cookbook paths, and intended dependency constraints. Use it as the authoritative source for the initial Ansible playbook scope, while resolving its differences from the Berksfile.
- `Policyfile.lock.json`: Records resolved versions, including `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0. Preserve this as migration evidence, but validate current Ansible package/role equivalents rather than translating cookbook versions literally.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 8080/8443. It syncs the repository and invokes shell provisioning. Rework this as an Ansible test harness or retain it only for integration testing.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. It also uses `apt-get`, which conflicts with the Fedora 42 Vagrant box and must be replaced or made OS-aware during migration.
- `solo.rb`: Chef Solo cookbook path, cache path, logging, and stdout settings. Its operational concerns map to Ansible inventory, role paths, logging, and execution configuration.
- `solo.json`: Chef run list and node attributes for sites, SSL paths, and security controls. These values should become inventory/group variables with environment-specific overrides.
- `project-plan.md`: Describes the broader X2Ansible tool and workflow rather than deployment behavior. It can inform coordination and validation workflow, but is not itself an infrastructure module.
- Cookbook templates and static files under `cookbooks/nginx-multisite/templates` and `cookbooks/nginx-multisite/files`: Migrate to Ansible role templates/files, preserving the Nginx, Fail2ban, sysctl, security, site, and static index content after review.

### Target Details

- **Operating System**: The Chef cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The Vagrant box is explicitly Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu `apt-get` commands. The target OS is therefore unresolved. Ansible should use OS-family abstractions (`ansible.builtin.package`, service facts, and firewall role variables), but the team must select and test a supported target. If no production specification exists, default planning should use Red Hat Enterprise Linux 9 as required, with a separate Ubuntu/Fedora compatibility decision.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly configured. The migration test environment can continue using Vagrant/libvirt, but Ansible should be invoked through the Vagrant provisioner or an equivalent test command.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud metadata integration was identified.

## Migration Approach

### Key Dependencies to Address

- **Ansible core and collections**: Pin a tested `ansible-core` version and maintain `requirements.yml`. Likely useful collections include `ansible.posix` for sysctl/mount/firewall-adjacent functionality and `community.general` where needed, subject to platform support.
- **Nginx package/service**: Replace Chef `nginx` cookbook 12.3.1 with an Ansible role or an internally owned role using package, template, file/link, and service handlers. Do not assume cookbook defaults map directly to the target distribution.
- **Memcached 6.1.0**: Replace with native package/service tasks or a vetted role. Define bind address, memory, and firewall exposure explicitly; the reviewed cookbook only includes the dependency and does not show custom Memcached settings.
- **Redis/redisio 7.2.4**: Replace with a supported Redis role or explicit package/configuration tasks. Reproduce authentication, port 6379, ownership, enablement, and the intended removal of replication directives without relying on an opaque post-generation edit.
- **SELinux 6.2.4 dependency**: Determine whether SELinux is enforcing on the selected OS. On RHEL-like targets, add explicit contexts/booleans/ports for Nginx, Redis, PostgreSQL, and the application rather than disabling SELinux. On Ubuntu/Fedora test systems, validate equivalent policy behavior.
- **PostgreSQL**: The application cookbook installs distribution PostgreSQL packages but does not pin a version or manage schema migrations. Use distribution-specific Ansible tasks or a PostgreSQL collection/role, and define database/user creation idempotently.
- **Python and FastAPI source**: Replace Chef `execute` resources with package/venv/pip tasks, Git checkout, a systemd template, and handlers. Pin the Git revision and Python dependencies before production use; the current source tracks mutable `main`.
- **TLS**: The locked Chef policy includes `ssl_certificate` 2.1.0, but the local SSL recipe actually generates self-signed certificates with OpenSSL. Decide whether the target uses ACME/Let's Encrypt, enterprise certificates, or development self-signed certificates, then implement certificate deployment and renewal separately from Nginx configuration.
- **Firewall and intrusion prevention**: Replace UFW shell commands with an OS-appropriate Ansible firewall implementation. Preserve default-deny intent, SSH/HTTP/HTTPS access, and add application/cache/database ports only where required.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123` in the Chef node configuration. Move it to Ansible Vault or an approved external secret manager, rotate it, and ensure it is not retained in Git history or logs.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` embeds username `fastapi`, password `fastapi_password`, and a full database URL in the shell commands and `/opt/fastapi-tutorial/.env`. The file is mode `0644` and the service runs as `root`; replace with Vault-backed values, restrictive permissions, a non-root application user, and idempotent PostgreSQL modules.
- **TLS private keys**: Keys are generated under `/etc/ssl/private` with root ownership and `ssl-cert` group mode 0710 directory / 0640 key files. Preserve least privilege, use Ansible `no_log` for secret material, and define certificate rotation. Current self-signed certificates are explicitly development-oriented and should not be promoted to production.
- **SSH hardening**: The intended settings disable root login and password authentication. Implement with `ansible.builtin.lineinfile` or a managed drop-in plus validation and a restart handler. Confirm an alternate administrative key/user exists before applying the change to avoid lockout.
- **Firewall and exposure**: UFW defaults to deny and allows SSH, HTTP, and HTTPS. The FastAPI service listens on all interfaces at port 8000, while cache/database services may expose local listeners depending on package defaults. Define bind addresses and firewall rules deliberately; avoid opening Redis, Memcached, PostgreSQL, or port 8000 externally without a requirement.
- **Systemd privilege**: The FastAPI service runs as `root`. Create a dedicated service account, restrict filesystem permissions, and use a systemd unit with an explicit environment-file policy.
- **Supply-chain controls**: The application is cloned from a public Git repository at mutable `main`, and pip installs are unpinned from `requirements.txt` at provisioning time. Pin a commit/release, review dependencies, use hashes or a controlled package repository, and add checksum/signature validation where feasible.
- **Template and command safety**: The Chef code uses shell commands and interpolated hostnames/paths for certificates and database creation. Ansible should prefer modules, quote variables, validate Nginx configuration before reload, and use `no_log` for credentials.
- **Per-module credential status**: `cache` contains a Redis password; `fastapi-tutorial` contains PostgreSQL credentials and a database URL; `nginx-multisite` contains certificate key handling but no private certificate material in the reviewed files; no encrypted data bags or Chef Vault usage were found.

### Technical Challenges

- **Distribution mismatch**: Cookbook metadata covers Ubuntu/CentOS, the VM is Fedora 42, and the provisioning shell assumes `apt-get`. Establish the supported OS matrix first and test package names, service names, firewall tooling, PostgreSQL layout, SELinux, and Nginx paths.
- **Chef attribute precedence and conflicting paths**: `attributes/default.rb` uses `/opt/server/...`, while `solo.json` overrides document roots to `/var/www/...`. Preserve the effective node configuration through explicit Ansible precedence and environment inventories; do not silently choose one path.
- **Configuration idempotency**: The current database commands use `|| true`, and the Redis recipe edits generated configuration with a Ruby block. Replace both with idempotent Ansible modules and explicit state checks so failures are visible.
- **Certificate lifecycle**: Self-signed generation is one-time and hostname-specific. Production migration requires certificate ownership, renewal, SANs, permissions, reload behavior, and possibly DNS/ACME integration.
- **Application readiness**: The cookbook installs PostgreSQL but does not run migrations, verify the application import path, or health-check Uvicorn. Add service ordering, readiness checks, migration policy, and rollback behavior.
- **Implicit external cookbook behavior**: `cache` depends on Memcached and Redis cookbooks, while `nginx-multisite` declares no metadata dependencies despite relying on Nginx-like package behavior. Reconstruct the actual desired behavior from rendered templates and test service defaults rather than translating includes mechanically.
- **Nginx template semantics**: Existing ERB templates and site files need conversion to Jinja2 and must be validated with `nginx -t` before reload. Confirm whether static content, security headers, and any upstream behavior are truly required.
- **Environment/test parity**: The documented URLs include inconsistent addresses (`192.168.56.10` in the shell output versus `192.168.121.10` in the Vagrantfile). Correct test documentation and add automated smoke tests for DNS/hosts resolution, HTTP redirects, TLS, ports, services, and application health.

### Migration Order

1. **Foundation and test contract**: Select the supported OS, pin Ansible/collection versions, define inventory and Vault strategy, and repair the Vagrant/libvirt provisioning/test path.
2. **`nginx-multisite` security baseline**: Implement OS facts, users/SSH hardening safeguards, sysctl, firewall, Fail2ban, certificate directory permissions, and validation handlers. Review lockout and firewall behavior first.
3. **`nginx-multisite` Nginx/sites**: Migrate templates, static files, site variables, symlinks, service management, and TLS. Validate each hostname and use `nginx -t` before reload.
4. **`cache`**: Implement Redis and Memcached packages/services with Vault-managed Redis authentication, local binding/firewall policy, and configuration tests.
5. **`fastapi-tutorial` platform**: Implement PostgreSQL, dedicated database/user, application account, pinned source/dependencies, virtual environment, environment file, and systemd service. Add health checks and migration handling.
6. **Integrated validation and cutover**: Compare Chef and Ansible behavior in the same VM class, run security and service smoke tests, perform staged deployment, and retire Chef only after rollback and secret-rotation procedures are documented.

### Assumptions

- The three directories under `cookbooks/` are the complete local cookbook inventory.
- The Chef Policyfile run list is the intended deployment scope: `nginx-multisite`, `cache`, and `fastapi-tutorial`.
- The versions in `Policyfile.lock.json` describe the tested Chef dependency set, although the Berksfile and Policyfile differ because `ssl_certificate` is commented out in Berksfile but locked by Policyfile.
- The external cookbook implementations were not reviewed in this high-level survey; their defaults and transitive behavior require validation before replacement.
- No production inventory, cloud platform, DNS system, certificate authority, backup policy, monitoring, or CI pipeline was provided.
- The target operating system is not settled. Fedora 42 is the declared test box, but `apt-get` and cookbook support metadata indicate an unresolved Ubuntu/CentOS/Fedora mix; OS selection is a prerequisite.
- The three `cluster.local` names are development/test names unless the owning team confirms otherwise; production DNS and certificate names must be supplied.
- The repository contains development credentials that must be treated as compromised and rotated, even if they are not currently used in production.
- PostgreSQL data persistence, backup/restore, schema migration, and version compatibility are outside the visible cookbook scope and require application-owner decisions.
- The FastAPI repository and its requirements are external mutable inputs and require a release/version ownership decision.
- Existing templates (`nginx.conf.erb`, `security.conf.erb`, `site.conf.erb`, `fail2ban.jail.local.erb`, and `sysctl-security.conf.erb`) must be reviewed during implementation for exact behavior; this plan does not assume undocumented template contents.
- The Ansible design should use roles, inventories, handlers, check mode, Vault, Molecule or equivalent tests, and CI linting rather than a single monolithic playbook.
- Team coordination should assign separate owners for platform/OS compatibility, security and secrets, Nginx/TLS, cache services, and FastAPI/PostgreSQL; integrate through a shared variable contract and a staged validation environment.
