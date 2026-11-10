# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile environment containing three local Chef cookbooks: a hardened Nginx multi-site front end, cache services (Memcached and Redis), and a FastAPI tutorial application backed by PostgreSQL. Chef 16+ is required by the local cookbook metadata; external cookbook versions are resolved in `Policyfile.lock.json`. The migration is moderate in complexity: the resource count is manageable, but the web/security configuration, TLS lifecycle, stateful PostgreSQL/Redis configuration, and inconsistent OS assumptions require deliberate validation. A two-person team can reasonably implement, test, and document the initial Ansible replacement in approximately 2–3 weeks, assuming a non-production development environment and timely decisions on operating-system and certificate strategy. Production hardening and application/database credential remediation should be planned as a separate release gate.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and configures Memcached through the external `memcached` cookbook and a password-protected Redis instance through `redisio`; creates the Redis log directory and applies a post-convergence Ruby workaround that removes several replica-related Redis directives from `/etc/redis/6379.conf`.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion, Redis on port 6379, Redis authentication, Redis service enablement, Redis log directory, direct configuration-file workaround.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` Git repository into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application requirements, provisions a local PostgreSQL database/user, writes an application `.env`, and runs Uvicorn as a root-owned systemd service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/venv and Git packages, Git checkout of the `main` branch, PostgreSQL service/database provisioning, pip dependency installation, systemd application service.

- **nginx-multisite**:
  - Description: Configures Nginx to serve three static subdomains (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), creates self-signed TLS certificates, deploys static site content, and applies host/web hardening using Fail2ban, UFW, SSH configuration changes, sysctl settings, and Nginx security headers.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration and virtual-host templates, HTTP-to-HTTPS redirects, TLS 1.2/1.3, self-signed certificates, static content deployment, Fail2ban, UFW default deny with SSH/HTTP/HTTPS allowances, SSH root/password-login disabling, kernel network hardening, rate-limit zones and HTTP security headers.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source and local/external cookbook resolution. Its locked external dependencies should be replaced by Ansible roles/collections and OS-native packages rather than carried forward as Chef artifacts.
- `Policyfile.rb`: Defines the authoritative Chef run order: `nginx-multisite`, then `cache`, then `fastapi-tutorial`; it also declares external cookbook constraints. Translate this into an Ansible site playbook with explicit role ordering and handlers.
- `Policyfile.lock.json`: Pins the resolved cookbook versions: Memcached 6.1.0, Nginx 12.3.1, Redisio 7.2.4, SELinux 6.2.4, and SSL Certificate 2.1.0. Retain it as migration evidence only; use it to identify behavior that must be tested rather than as an Ansible dependency file.
- `solo.json`: Chef Solo run list and environment-specific attributes for the three virtual hosts, certificate/key directories, Fail2ban/UFW intent, and SSH restrictions. Migrate to `group_vars`/`host_vars`, keeping environment-specific values outside role defaults.
- `solo.rb`: Chef Solo cache and cookbook-path configuration. No functional Ansible equivalent is required beyond the standard inventory, role path, and `ansible.cfg` setup.
- `Vagrantfile`: Development VM definition using `generic/fedora42`, private IP `192.168.121.10`, forwarded HTTP/HTTPS ports, and the Libvirt provider (2 GiB RAM, two CPUs). Reuse or replace with an Ansible provisioner for repeatable local integration tests.
- `vagrant-provision.sh`: Bootstrap script that runs `apt-get`, installs Chef from Omnitruck, installs Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with a minimal Python/Ansible bootstrap or Vagrant Ansible provisioner; it conflicts with the Fedora Vagrant box because it uses Debian/Ubuntu package tooling.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, certificate-location, and hardening values. Translate to role defaults, with deployed site/domain values supplied by inventory variables.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb`: Defines HTTP redirects, TLS virtual hosts, HSTS, security headers, gzip, static content behavior, hidden-file restrictions, and per-site logs. Convert to a Jinja2 template and validate Nginx syntax before reload.
- `cookbooks/nginx-multisite/templates/default/security.conf.erb`: Defines Nginx server-token suppression, request-rate zones, small request buffers/body limit, timeouts, and TLS settings. Convert to a Jinja2-managed Nginx include; validate that its restrictive 1 KiB request-body limit is intentional for FastAPI/API use.
- `project-plan.md`: Documentation for an unrelated/planned X2Ansible tool workflow, not active provisioning configuration. Keep as reference only and do not treat the described source-tree layout as present in this repository.
- `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`: Migration-tool rule/documentation artifact. It is not a Chef module or runtime dependency; review separately if it imposes delivery-process requirements.

### Target Details

- **Operating System**: The local cookbook metadata supports Ubuntu 18.04+ and CentOS 7+. The active Vagrant box is Fedora 42, but `vagrant-provision.sh` uses `apt-get`, and Nginx configuration assumes Debian-style `www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, UFW, and an `ssh` service name. The effective target OS is therefore ambiguous and currently inconsistent. Select and test one supported target before implementation. If no decision is available, standardize the Ansible target on Red Hat Enterprise Linux 9 as the default, but the existing Debian-specific Nginx/UFW conventions will require adaptation.
- **Virtual Machine Technology**: Vagrant with the Libvirt provider; the development VM uses the `generic/fedora42` box.
- **Cloud Platform**: Not specified. No cloud provider tooling, metadata endpoint usage, or cloud-init configuration was found.

## Migration Approach

Build an Ansible repository using an inventory-driven site playbook and separate roles such as `common_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep reusable OS-family mappings, package names, service names, and Nginx directory layouts in `vars/Debian.yml` and `vars/RedHat.yml`. Use handlers for daemon reload/restart/reload operations and CI to run `ansible-lint`, syntax checks, and an ephemeral Vagrant/Libvirt integration deployment. Assign a platform owner to resolve target OS behavior and a security owner to approve SSH, firewall, TLS, and secret-management changes before cutover.

### Key Dependencies to Address

- **Chef Infra Client (>= 16.0)**: Retire Chef Solo, Berkshelf, Berks vendoring, Policyfile execution, and Omnitruck installation. Use `ansible-core`, a pinned Python environment, inventories, and role requirements instead.
- **Chef Supermarket `memcached` (6.1.0)**: Replace with an Ansible `package` task for the OS-native Memcached package, a managed configuration only if required after behavior discovery, and a systemd service task/handler.
- **Chef Supermarket `redisio` (7.2.4)**: Replace with OS-native Redis packages/service management and a managed Redis configuration template. Preserve port 6379 and required authentication, but explicitly decide whether the Chef workaround removing replica directives reflects a package/version defect or desired configuration.
- **Chef Supermarket `nginx` (12.3.1)**: The local Nginx cookbook installs/configures Nginx directly and does not include this dependency in its metadata. Replace with package, template, directory, file, service, and `nginx -t` validation tasks; remove the unused Chef dependency unless detailed validation reveals omitted behavior.
- **Chef Supermarket `ssl_certificate` (2.1.0)**: Present in Policyfile declarations/lock but not included by the reviewed local recipes. Replace self-signed certificate generation with `community.crypto.openssl_*` modules for development, or preferably a managed enterprise PKI/ACME certificate workflow for production.
- **Chef Supermarket `selinux` (6.2.4)**: A transitive Redisio dependency in the lock file. It is relevant only for Red Hat-family targets; implement SELinux labeling/booleans only after selecting the OS and confirming required service paths/ports.
- **GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` (`main`)**: Use `ansible.builtin.git`, but pin a commit or signed release rather than the moving `main` branch for reproducible deployments. Confirm the Python dependency source and add controlled pip installation practices.
- **PostgreSQL client/server tooling**: Replace shell `psql` calls with `community.postgresql.postgresql_user`, `postgresql_db`, and `postgresql_privs`, running as the PostgreSQL administrative account. The controller will need a compatible Python PostgreSQL driver and suitable privilege escalation configuration.
- **System packages**: Map `python3`, `python3-pip`, `python3-venv`, `git`, PostgreSQL packages, `libpq-dev`, Nginx, OpenSSL, CA certificates, Fail2ban, and firewall tooling per selected OS family. Avoid assuming Debian package names on Fedora/RHEL.

### Security Considerations

- **Hardcoded Redis password**: `cache` embeds `redis_secure_password_123` in source. Move it to Ansible Vault or an approved external secret manager; template the Redis configuration with restrictive ownership/mode and rotate the credential during migration.
- **Hardcoded PostgreSQL/application password**: `fastapi-tutorial` contains `fastapi_password` in SQL commands and writes it into `/opt/fastapi-tutorial/.env` with mode `0644`. Store the database credential in Vault/external secrets, create it idempotently, set the environment file to a service-specific owner and `0600`, and rotate the exposed password.
- **TLS certificates and private keys**: `nginx-multisite` generates unencrypted, 2048-bit RSA self-signed certificates valid for 365 days. Private-key directory mode is `0710`, individual keys are `0640`, and group `ssl-cert` is created. Retain restrictive access but replace development self-signed certificates with managed trusted certificates for production; protect certificate-key material with Vault or a PKI integration and define renewal/reload handling.
- **SSH lockout risk**: The security recipe disables root SSH login and password authentication using `sed`, then restarts `ssh`. Before applying an Ansible equivalent, verify an authorized key, the correct service unit (`ssh` vs `sshd`), console/break-glass access, and host-specific exceptions. Use `sshd_config` validation prior to restart.
- **Firewall policy**: The recipe sets UFW default deny and permits SSH/HTTP/HTTPS. Confirm management-network/IPv6 rules, application port exposure requirements, and the target firewall implementation (`ufw` versus `firewalld`) before enforcing. The FastAPI process listens on all interfaces at port 8000 but no firewall rule exposes it; preserve or revise that boundary intentionally.
- **Web hardening**: Preserve and test Nginx TLS protocols/ciphers, HSTS, frame/content-type/referrer/CSP headers, hidden VCS/file rules, rate-limit zones, and request timeouts. Review CSP use of `'unsafe-inline'`, the deprecated `X-XSS-Protection` header, and the globally small 1 KiB `client_max_body_size` against real application needs.
- **Privilege minimization**: The FastAPI systemd service runs as `root`, while static Nginx content is owned by `www-data`. Create a dedicated non-login application user/group, ownership model, and systemd hardening options; ensure OS-specific web-server account names are not assumed.
- **Credential patterns by module**: `cache` has a hardcoded Redis password. `fastapi-tutorial` has a hardcoded PostgreSQL password embedded in `.env`/database commands. `nginx-multisite` contains certificate/private-key paths and locally generated key material but no external certificate credentials. No Chef encrypted data bags, Chef Vault, or environment-variable secret injection were found in the reviewed source.

### Technical Challenges

- **Conflicting platform assumptions**: Fedora 42/Libvirt is declared in Vagrant, while the bootstrap script, UFW, `www-data`, Nginx `sites-*` directories, package conventions, and `ssh` service name are Debian-oriented. Mitigation: select a canonical OS before role development; use OS-specific variable/task files and test only supported combinations.
- **Chef declarations versus actual behavior**: `nginx` and `ssl_certificate` are pinned in the Policyfile but the local Nginx recipe directly manages Nginx and OpenSSL and does not visibly include those cookbooks. Mitigation: use Policyfile.lock as evidence of historic dependency resolution, then use convergence tests to establish the desired final state rather than blindly reproducing all Chef dependencies.
- **Stateful service migration**: PostgreSQL and Redis involve credentials and persistent data. Mitigation: separate installation/configuration from data migration, define backups and rollback, test idempotent database/user tasks, and decide whether existing data must be preserved before cutover.
- **Imperative/non-idempotent Chef patterns**: Shell commands use `|| true` for database creation and `sed` to alter SSH configuration; the Redis workaround edits a generated configuration file after another cookbook runs. Mitigation: replace with dedicated Ansible modules/templates, explicit `creates`/checks where modules are unavailable, validation commands, and clear handlers.
- **Application reproducibility and supply chain**: The application tracks Git `main` and installs unpinned requirements from a remote repository. Mitigation: pin an immutable revision, maintain a dependency-locking strategy, consider an internal artifact mirror, and run the service as a non-root user.
- **Web/application integration uncertainty**: Nginx virtual hosts serve static document roots only; reviewed configuration does not proxy traffic to Uvicorn on port 8000. Mitigation: confirm whether FastAPI is intentionally internal, then either preserve that design or add a reviewed reverse-proxy location and health checks.
- **Configuration discrepancies**: Cookbook defaults use `/opt/server/*`, while `solo.json` overrides site roots to `/var/www/*.cluster.local`; the provision script advertises a different private IP (`192.168.56.10`) than Vagrant (`192.168.121.10`). Mitigation: establish environment inventory variables as the single source of truth and add deployment assertions/tests.

### Migration Order

1. **Platform baseline and common security** (low-to-moderate risk): decide OS, create inventory/group variables, package/service mappings, privileged-access model, firewall policy, SSH validation, and Vagrant/Libvirt CI test harness. Do not apply SSH restrictions until access validation passes.
2. **Nginx multisite** (moderate complexity): migrate static sites, Jinja2 Nginx configuration, security include, TLS development/production strategy, content ownership, configuration validation, and service handlers. Validate all three hostnames, redirects, headers, certificate behavior, and firewall access.
3. **Cache services** (moderate complexity): install Memcached and Redis, manage Redis authentication through Vault, confirm the purpose of the replica-setting workaround, and test service availability/authentication without exposing Redis externally.
4. **PostgreSQL and FastAPI application** (highest complexity/dependency): provision PostgreSQL role/database with vaulted secrets, deploy a pinned application revision and virtual environment, create a least-privileged systemd service, and confirm application health and intended Nginx exposure. Execute data backup/restore and rollback testing before production adoption.
5. **Parallel cutover validation and Chef retirement**: compare rendered configuration, packages, listening ports, systemd state, firewall rules, TLS/web headers, database access, and cache behavior. Update operations documentation/runbooks, train support teams, freeze Chef changes, and remove Chef/Berkshelf bootstrap only after acceptance.

### Assumptions

- The repository tree is complete as provided; no Puppet manifests, Salt states, PowerShell modules, Chef data bags, encrypted data bags, Chef Vault items, Hiera files, or cloud configuration are present.
- Each directory under `cookbooks/` with `metadata.rb` and `recipes/default.rb` is treated as one local Chef cookbook: `cache`, `fastapi-tutorial`, and `nginx-multisite`.
- The Policyfile run list represents the intended full deployment order, although Chef Solo is invoked using `solo.json` rather than Policyfile execution.
- The lock file captures resolved external cookbook versions at the time it was generated; it does not prove that every locked cookbook contributes runtime resources to the local recipes.
- The intended production operating system is not confirmed. Fedora 42 is the Vagrant box, but provisioning/configuration contains strong Debian/Ubuntu assumptions; RHEL 9 is only the requested default fallback if no OS decision is made.
- The three `*.cluster.local` sites are development/test hostnames with static HTML content, and their self-signed certificates are development-only. DNS, trusted certificate issuance, and production domain names are outside the reviewed configuration.
- It is unknown whether existing PostgreSQL, Redis, or Memcached data exists and must be migrated. The plan assumes a configuration migration unless stakeholders identify data-retention requirements.
- It is unknown whether Uvicorn port 8000 should be reachable directly or behind Nginx; the reviewed Nginx templates do not define a reverse proxy.
- The exact FastAPI repository revision, Python package versions, database schema migration procedure, and application health-check endpoint are not specified and must be supplied by the application team.
- The template’s Nginx request-body limit and buffer settings may be intentional security controls, but their compatibility with API payloads has not been established.
- Vagrant/Libvirt is treated as local development/test infrastructure, not evidence of the production virtualization platform.
