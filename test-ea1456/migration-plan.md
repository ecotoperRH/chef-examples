# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo infrastructure project with three local cookbooks and a Vagrant/libvirt test environment. The migration scope is modest in module count but moderate in operational risk because it combines Nginx virtual hosting, host hardening, self-signed TLS, Redis/Memcached, PostgreSQL, and a FastAPI service. A realistic implementation estimate is 1–2 engineers for approximately 1–2 weeks, including role development, Fedora/target-OS reconciliation, secret remediation, and idempotence/integration testing. The application and security roles should be migrated and validated separately before assembling the complete deployment.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths were present in the repository tree and whose primary recipes were reviewed are listed below.

- **nginx-multisite**:
    - Description: Nginx installation and configuration for three SSL-enabled static sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), including virtual host files, web content, TLS setup, and host/web security hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management, generated site configurations and symlinks, HTTP-to-HTTPS redirects, TLS 1.2/1.3 settings, security headers, rate-limit zones, Fail2ban, UFW, SSH hardening, sysctl hardening, and development self-signed certificates.

- **cache**:
    - Description: Caching service configuration that includes Memcached and a single Redis instance listening on port 6379.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, Redis installation/enabling through `redisio`, Redis log directory creation, password-protected Redis configuration, and a post-configuration Ruby workaround that removes replication directives.

- **fastapi-tutorial**:
    - Description: Deployment of the FastAPI tutorial application with Python tooling, a Git checkout, a virtual environment, PostgreSQL, database/user creation, environment configuration, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv installation, application checkout from `https://github.com/dibanez/fastapi_tutorial.git` at `main`, pip requirements installation, PostgreSQL service, `fastapi` database/user, `.env` creation, and Uvicorn on port 8000.

### Infrastructure Files

- `Berksfile`: Chef Supermarket and local cookbook dependency sources. It requests `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; an `ssl_certificate` dependency is commented out here.
- `Policyfile.rb`: Chef policy named `nginx-multisite-policy`; run list is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`. It also declares `ssl_certificate ~> 2.1` and the other external cookbooks.
- `Policyfile.lock.json`: Resolved dependency snapshot. It pins nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, ssl_certificate 2.1.0, and transitive selinux 6.2.4, alongside the three local cookbooks at version 1.0.0. It records local cookbook revision `c7845a8...` with a dirty working tree.
- `solo.rb`: Chef Solo configuration; uses `/var/chef-solo` for cache and `/chef-repo/cookbooks` plus wildcard cookbook paths.
- `solo.json`: Chef run list and node attributes for the three virtual hosts, SSL paths, Fail2ban/UFW, and SSH policy. Its document roots (`/var/www/...`) conflict with the cookbook defaults (`/opt/server/...`) and must be resolved.
- `Vagrantfile`: Defines a `generic/fedora42` VM named `chef-nginx`, libvirt resources (2 GB RAM, 2 CPUs), private address `192.168.121.10`, and forwarded ports 8080/8443. It rsyncs the repository to `/chef-repo` and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef via the Omnitruck script, installs Berkshelf, vendors cookbooks, and runs Chef Solo. This is inconsistent with the Fedora Vagrant box and must be replaced by Ansible installation/invocation and a target-OS-compatible bootstrap.
- `project-plan.md`: Project-level specification for an X2Ansible analysis/migration workflow; useful as process context but not an infrastructure module.

### Target Details

- **Operating System**: The Vagrant box explicitly declares Fedora 42, but the provisioner uses Debian/Ubuntu commands (`apt-get`) and the cookbooks support Ubuntu >=18.04 and CentOS >=7. The effective target is therefore ambiguous. Validate and select Fedora 42/RHEL-compatible package names and service names, or change the test box to Ubuntu; do not assume UFW, `www-data`, or `/var/log/auth.log` are available on Fedora.
- **Virtual Machine Technology**: libvirt through Vagrant, with rsync-based repository synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was found.

## Migration Approach

Create an Ansible project with a site playbook and separate roles, at minimum: `nginx_multisite`, `security`, `cache`, and `fastapi_tutorial` (or keep security as a clearly separated role even though it is implemented inside the Nginx cookbook). Use inventory/group variables for site definitions and service settings, templates for Nginx/Fail2ban/systemd configuration, handlers for reload/restart actions, and Ansible Vault for all credentials and private keys. Preserve the Chef run-list order initially, then make dependencies explicit: base packages/security prerequisites, cache and PostgreSQL, application, and finally Nginx publication and validation.

### Key Dependencies to Address

- **nginx 12.3.1 / Chef nginx cookbook**: Replace with `ansible.builtin.package`, `template`, `file`, `service`, and `ansible.builtin.command` only where unavoidable; preferably use distribution-native Nginx configuration conventions.
- **memcached 6.1.0**: Replace with package installation and service configuration, using an Ansible role or a supported collection if bind/listen/auth settings are required.
- **redisio 7.2.4 and selinux 6.2.4**: Replace with an OS-appropriate Redis role/collection or explicit package, configuration template, service, and SELinux tasks. Re-evaluate the Chef Ruby workaround rather than copying the brittle text mutation.
- **ssl_certificate 2.1.0**: It is locked and declared in `Policyfile.rb`, but no reviewed local recipe uses it; decide whether to remove it or replace it with managed certificate material/ACME automation. Development currently generates self-signed certificates with OpenSSL.
- **PostgreSQL packages and database operations**: Use distribution packages and `community.postgresql.postgresql_db`/`postgresql_user` with `community.postgresql`, rather than shelling out to `psql`.
- **Python dependencies and Git checkout**: Use `ansible.builtin.git`, package/virtualenv tasks, and a controlled requirements lock/version. Pin the application revision instead of tracking `main` for production.
- **systemd**: Use a templated unit and `ansible.builtin.systemd_service` with daemon reload and enable/start handlers.
- **UFW/Fail2ban/SSH/sysctl**: Use platform-specific Ansible modules and templates. On Fedora, consider firewalld instead of UFW and verify Fail2ban package/filter/log-path availability.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, restrict Redis binding/firewall exposure, and rotate it during migration.
- **Hardcoded PostgreSQL credentials**: The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes it to a world-readable (`0644`) root-owned `.env`. Replace with Vault-managed credentials, mode `0600`, least-privilege database grants, and idempotent database modules.
- **TLS private keys and certificates**: Self-signed keys are generated under `/etc/ssl/private` with `0640` and `ssl-cert` ownership. Decide whether this remains development-only; use managed certificate issuance or protected vaulted/deployed certificate files in production. Do not store private keys in Git.
- **Nginx TLS posture**: TLS 1.2/1.3, custom cipher lists, HSTS, security headers, and HTTP-to-HTTPS redirects must be retained and tested. Review the cipher list and HSTS impact before production rollout.
- **Host hardening**: Root SSH login and password authentication are disabled, UFW defaults to deny, and SSH/HTTP/HTTPS are allowed. Preserve this only after confirming console/key-based access and adapting firewall tooling to the chosen OS.
- **Kernel hardening**: The sysctl template disables redirects, source routing, IPv6, and ICMP echo and enables SYN-cookie protections. Validate these settings against application/network requirements and apply with a controlled handler.
- **Fail2ban**: Jail definitions depend on `/var/log/auth.log` and Nginx log glob patterns. Verify log locations, filters, and IPv6 behavior on the target OS before enabling enforcement.
- **Application privilege**: The systemd service runs Uvicorn as `root`; migrate to a dedicated unprivileged service account, with explicit writable directories and a reverse-proxy boundary.
- **Supply chain**: The application tracks an external GitHub `main` branch and installs requirements at provision time. Pin commits and dependency hashes, and add CI checks for dependency/security scanning.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is declared while bootstrap and several recipes assume Debian/Ubuntu. Resolve the target OS first; maintain OS-specific variables/tasks or standardize the test image.
- **Chef attribute precedence and path drift**: `solo.json` overrides site document roots differently from `attributes/default.rb`; migration must establish one authoritative inventory variable model and test rendered roots/content.
- **Non-idempotent shell operations**: PostgreSQL creation uses `|| true`, Redis config is edited with a Ruby block, and SSH is modified via `sed`. Replace these with idempotent modules/templates and explicit change detection.
- **Certificate lifecycle**: Existing certificates are self-signed and generated only when absent. Define renewal, trust, hostname/SAN, and production certificate ownership requirements before implementation.
- **Web-to-application integration**: Nginx serves static sites while FastAPI listens on port 8000; the current reviewed configuration does not show an Nginx proxy to FastAPI. Confirm whether the API should be externally exposed or proxied and add the intended design explicitly.
- **Data preservation**: Redis, Memcached, PostgreSQL, and application files may contain state. Decide whether migration is rebuild-only or requires backups, restore tests, and cutover sequencing.
- **Platform service names/users**: `www-data`, `ssh`, PostgreSQL package names, UFW, and auth log paths may differ on Fedora/RHEL. Parameterize or standardize the operating system.
- **Testing limitations**: Vagrant port forwarding and commented host entries make hostname/TLS testing incomplete. Add automated `nginx -t`, TLS checks, service health checks, database connectivity, and endpoint tests.

### Migration Order

1. **Inventory and target-OS decision**: Reconcile Fedora versus Ubuntu, `solo.json` versus cookbook defaults, expected site roots, certificate strategy, and API exposure.
2. **Base/security role**: Implement package prerequisites, users, SSH policy, firewall, sysctl, Fail2ban, and SELinux/firewalld behavior with a safe access rollback plan.
3. **Cache role**: Migrate Redis and Memcached with Vault credentials, service validation, and data/backup decisions.
4. **Application/database role**: Install PostgreSQL and Python, create database/user idempotently, deploy the pinned FastAPI revision, secure `.env`, and run the service as a non-root account.
5. **Nginx multisite role**: Migrate templates, static content, virtual hosts, TLS, headers, rate limits, and service handlers; confirm whether FastAPI needs a proxy location.
6. **Integration and cutover**: Test all three hostnames, ports 80/443, certificate behavior, firewall access, service restarts, reboot persistence, and rollback from Chef/Vagrant to Ansible.

### Assumptions

- The three directories under `cookbooks/` are the complete local cookbook inventory.
- Chef Policyfile lock versions represent the intended external dependency set, even where `Berksfile` and `Policyfile.rb` differ.
- `ssl_certificate` is an unused or future dependency because no reviewed local recipe invokes it.
- The Vagrant VM is a development/test target, not proof of the production operating system.
- The requested migration targets conventional Ansible playbooks/roles, not a direct automated translation of Chef resources.
- The `fastapi-tutorial` GitHub repository and its `requirements.txt` remain available, but its unpinned `main` branch must not be treated as a production release source.
- The three static HTML files under the cookbook `files/` tree are intended to be deployed to the corresponding sites, subject to the document-root discrepancy.
- Existing data in PostgreSQL, Redis, and Memcached has not been assessed; backups and migration requirements require owner confirmation.
- Certificate trust requirements, DNS ownership for `*.cluster.local`, and production certificate issuance are unspecified.
- The intended firewall implementation on Fedora/RHEL is unspecified; firewalld may be preferable to UFW.
- No cloud, external inventory, CI pipeline, monitoring, backup, or secret-management integration was present in the reviewed files.
- The displayed Vagrant output references `192.168.56.10`, while the Vagrantfile configures `192.168.121.10`; validate documentation and test access addresses during migration.
- Team coordination should assign separate owners for OS/security, data services, application runtime, Nginx/TLS, and validation. Require review of Vault data, an agreed variable schema, CI linting (`ansible-lint`/YAML checks), and a staged test deployment before production cutover.
