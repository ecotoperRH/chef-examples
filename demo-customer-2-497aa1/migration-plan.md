# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile deployment containing three local Chef cookbooks. The policy combines Nginx multi-site hosting and host hardening, Memcached/Redis caching, and a FastAPI application backed by local PostgreSQL. The migration is small in cookbook count but moderate in operational complexity due to public web services, SSH/firewall controls, TLS private keys, stateful services, and credentials committed in recipes. Estimate **3–5 weeks** for a two-person team to build, test, secure, and document the Ansible replacement, excluding decisions about production PKI, backups, and target OS standardization.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Configures Memcached and a password-protected Redis service, including Redis logging storage and service enablement.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Includes the external `memcached` and `redisio` cookbooks; defines Redis on port 6379; creates `/var/log/redis`; performs an imperative cleanup of selected Redis configuration directives; enables Redis.

- **fastapi-tutorial**:
  - Description: Deploys the FastAPI tutorial application from Git, provisions its Python environment and local PostgreSQL database, and runs Uvicorn through systemd.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Installs Python, Git, PostgreSQL, and libpq packages; clones `https://github.com/dibanez/fastapi_tutorial.git` at `main`; builds a virtual environment; installs application requirements; creates a PostgreSQL user/database/grants; writes `.env`; enables `fastapi-tutorial.service` on port 8000.

- **nginx-multisite**:
  - Description: Configures Nginx to host the `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` static sites with TLS and baseline host-security controls.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration, per-site virtual-host templates and bundled index pages; self-signed certificates; Fail2ban; UFW rules for SSH/HTTP/HTTPS; sysctl hardening; disabled SSH root login and password authentication; removal of the default Nginx site.

### Infrastructure Files

- `Berksfile`: Defines local cookbook paths and Supermarket dependencies: Nginx `~> 12.0`, Memcached `~> 6.0`, and Redisio `~> 7.2.4`. Its `ssl_certificate` declaration is commented out.
- `Policyfile.rb`: Defines the intended Chef run list in order: `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`; it also declares `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Locks resolved external cookbook versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SSL Certificate 2.1.0, and transitive SELinux 6.2.4.
- `solo.json`: Supplies Chef Solo run-list attributes, three Nginx site definitions, certificate paths, and enabled security settings. Convert this to inventory/group variables.
- `solo.rb`: Sets Chef Solo cookbook paths, cache location, and logging. Replace with Ansible project, inventory, and logging conventions.
- `Vagrantfile`: Defines a Fedora 42 Vagrant VM with libvirt, 2 GB RAM, two vCPUs, private IP `192.168.121.10`, and forwarded HTTP/HTTPS ports. Use as a migration test fixture or replace with Molecule/libvirt.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. It uses `apt-get`, which conflicts with the Fedora Vagrant box; replace with an Ansible test/bootstrap workflow.
- `cookbooks/nginx-multisite/attributes/default.rb`: Provides default vhost, certificate, and security attributes. Its `/opt/server/...` document-root defaults conflict with the `/var/www/...` values in `solo.json` and must be reconciled.
- `cookbooks/nginx-multisite/templates/` and `cookbooks/nginx-multisite/files/default/`: Source templates and static content to convert to Jinja2 templates and Ansible role files.

### Target Details

- **Operating System**: Chef metadata supports Ubuntu 18.04+ and CentOS 7+. Actual resource choices are mainly Debian/Ubuntu-specific (`apt-get`, UFW, `www-data`, and Nginx `sites-available/sites-enabled`), while Vagrant selects Fedora 42. Standardize the platform before migration. If no decision is made, default to **Red Hat Enterprise Linux 9**, but implement explicit substitutions for UFW, Nginx layout, and user/group conventions. Ubuntu is closer to current behavior.
- **Virtual Machine Technology**: Vagrant using libvirt.
- **Cloud Platform**: Not specified.

## Migration Approach

Create an Ansible repository with a site playbook and independently testable roles: `baseline_security`, `nginx_multisite`, `cache`, and `fastapi_tutorial`. Store environment-specific configuration in `group_vars`, non-secret defaults in role defaults, and secret values in Ansible Vault or an approved external secret manager. Use handlers for systemd reload/restarts and validate rendered Nginx configuration with `nginx -t` before reload. Establish CI with `ansible-lint`, syntax checks, idempotence testing, and a disposable libvirt/Vagrant or Molecule environment.

### Key Dependencies to Address

- **Chef Infra Client/Chef Solo (>=16)**: Retire from managed nodes; replace Chef run-list sequencing with Ansible playbooks and role order.
- **Berkshelf/Chef Supermarket**: Retire Chef dependency resolution. Reimplement required service behavior with `ansible.builtin` modules and approved collections.
- **nginx cookbook (12.3.1)**: Replace with package, template, file/copy, service, and handler tasks. Use `community.crypto` only for development self-signed certificates, or integrate enterprise PKI/ACME for production.
- **memcached cookbook (6.1.0)**: Install/configure the OS Memcached package and service. Confirm whether any application actually uses it.
- **redisio cookbook (7.2.4)**: Use the distribution Redis package, a declarative configuration template, systemd, and a Vault-sourced password. Do not preserve the Chef Ruby post-processing hack without first identifying its required outcome.
- **selinux cookbook (6.2.4, transitive)**: On RHEL-family targets, assess enforcing mode and implement required SELinux, port, and file-context configuration with `ansible.posix` and system modules.
- **ssl_certificate cookbook (2.1.0)**: It is Policyfile-locked but not included by the reviewed local recipes and is commented in `Berksfile`; verify need before retaining any equivalent capability.
- **FastAPI Git source (`main`)**: Pin an immutable tag or commit and define update/rollback ownership; a mutable branch is not reproducible.
- **Python requirements**: Install in a controlled virtual environment from pinned requirements and preferably an approved package mirror.
- **PostgreSQL**: Use PostgreSQL-aware Ansible modules and `become_user: postgres` for database objects; define backup, restoration, retention, monitoring, and upgrade requirements.

### Security Considerations

- **cache credentials**: The Redis `requirepass` is hardcoded in `cookbooks/cache/recipes/default.rb`. Move it to Ansible Vault/external secrets, mark secret tasks `no_log`, rotate it during cutover, and restrict Redis network exposure.
- **fastapi-tutorial credentials**: PostgreSQL credentials are hardcoded in SQL commands and the generated `DATABASE_URL`. Store these in Vault/external secrets, restrict the `.env` file to the application account, and rotate the credential.
- **Application privilege and file permissions**: The FastAPI service runs as `root` and `.env` is `0644`. Create a dedicated non-login application user and deploy secrets as root/application-group readable only (for example `0640`).
- **TLS key material**: `nginx-multisite` generates 365-day self-signed RSA certificates and stores private keys in `/etc/ssl/private` with `root:ssl-cert` ownership and `0640` permissions. Use approved CA-issued certificates in production, protect key delivery with Vault/secret retrieval, and implement renewal/reload handling.
- **Host hardening**: Preserve intended default-deny firewall posture, Fail2ban, SSH root-login disablement, password-authentication disablement, and sysctl configuration as declarative tasks. Stage SSH/firewall changes only after automation access and break-glass access are verified.
- **Service exposure**: FastAPI binds to `0.0.0.0:8000`. Determine whether it should bind to localhost and be reachable only through Nginx; block direct access at host/cloud firewalls if appropriate.
- **Bootstrap supply chain**: `vagrant-provision.sh` executes remote installation code using `curl | bash` and installs gems dynamically. Remove this workflow and pin Ansible collections and CI images.
- **Credential patterns by cookbook**: `cache` contains a Redis password; `fastapi-tutorial` contains PostgreSQL/application credentials and a database URL; `nginx-multisite` manages TLS private-key paths. No Chef encrypted data bags or Chef Vault use was found.

### Technical Challenges

- **OS mismatch**: Fedora 42 in Vagrant conflicts with Debian-oriented provisioning and filesystem/service assumptions. Select a target OS before role implementation, or maintain tested OS-specific task paths.
- **Imperative Chef workarounds**: Redis configuration is edited with a Ruby block, PostgreSQL SQL relies on `|| true`, and SSH configuration uses `sed`. Replace with idempotent modules/templates and validation rather than shell text manipulation.
- **Attribute drift**: `solo.json` changes document roots relative to cookbook defaults. Establish authoritative Ansible variables and test every vhost/content mapping.
- **Nginx layout portability**: Debian `sites-available/sites-enabled` conventions do not directly match default RHEL layouts. Choose and document a target layout; validate with `nginx -t` before handler reload.
- **Application lifecycle gaps**: The source does not demonstrate immutable releases, health checks, migrations, process tuning, reverse-proxy upstream rules, or rollback. Resolve these with the application team before production cutover.
- **Stateful-service readiness**: Redis, Memcached, and PostgreSQL have no visible backup, HA, persistence, sizing, monitoring, or restore design. Confirm whether they are development-only before production migration.

### Migration Order

1. **Baseline platform and security**: Select Ubuntu or RHEL 9; create inventory, secret management, CI/testing, application account, and safely staged firewall/SSH/sysctl/Fail2ban controls.
2. **nginx-multisite**: Migrate Nginx configuration, static content, vhosts, certificate workflow, and handlers; test all three hostnames and TLS behavior.
3. **cache**: Migrate Memcached and Redis with Vault-backed Redis authentication, explicit bindings, and validated service configuration.
4. **fastapi-tutorial**: Pin application and Python dependencies, provision PostgreSQL securely, deploy restrictive runtime configuration, and manage the systemd service behind Nginx.
5. **Integrated validation and handover**: Execute idempotence, functional, security, restore/rollback, and canary tests; deliver runbooks and assign ownership to platform, application, and data-service teams.

### Assumptions

- The repository inventory contains exactly the three local Chef cookbooks listed above; no Puppet, Salt, or PowerShell modules appear in the supplied tree.
- `Policyfile.rb` represents intended scope and order even though the Vagrant script invokes Chef Solo with Berkshelf rather than Policyfile-based Chef Client execution.
- The included Nginx security, SSL, and site recipes are central behavior reached by `nginx-multisite::default`; templates were not exhaustively audited.
- `ssl_certificate` is considered unused by local recipes until implementation review proves otherwise.
- The three `cluster.local` names and self-signed certificates appear development/test oriented; DNS, production PKI, load balancing, and cloud networking are unspecified.
- Production inventory, cloud provider, CI/CD platform, compliance baseline, monitoring, backup solution, and external secrets manager are not specified and require stakeholder decisions.
- If an OS choice remains unresolved, RHEL 9 is the requested default, despite Ubuntu being closer to the source behavior.
