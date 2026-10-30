# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks and a Vagrant-based libvirt test environment. The migration scope is moderate rather than large: the cookbook count is low, but the deployment spans Nginx virtual hosts and TLS, host hardening, Redis/Memcached, and a FastAPI/PostgreSQL application. A reasonable initial estimate is 2–4 weeks for one engineer, including implementation, dependency replacement, secure secret handling, and functional testing; production rollout should be scheduled separately after environment validation.

The target Ansible design should use a collection or repository with separate roles, explicit inventories, group/host variables, templates, handlers, and Ansible Vault. The current Chef run order is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
    - Description: Configures Memcached and Redis caching services, including a Redis listener on port 6379, Redis authentication, logging directory creation, service enablement, and a post-configuration cleanup workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached cookbook inclusion, RedisIO integration, Redis password configuration, `/var/log/redis` ownership, and a `ruby_block` that removes selected replication-related settings from `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
    - Description: Installs and runs a FastAPI tutorial application from the `main` branch of GitHub, with Python tooling, a virtual environment, PostgreSQL, an application database/user, an environment file, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv, Git checkout, PostgreSQL packages and service, `fastapi_db` database and `fastapi` user, Uvicorn on `0.0.0.0:8000`, and systemd management.

- **nginx-multisite**:
    - Description: Provisions Nginx for three configured sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), serves static site content, generates development self-signed certificates, and applies host and web-server security controls.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx configuration and reload handlers, per-site server blocks, static `index.html` files, SSL certificate/key directories, Fail2ban, UFW default-deny rules, SSH hardening, sysctl settings, and removal of the default Nginx site.

**CRITICAL PATH VERIFICATION:**
All module paths above are present in the supplied repository tree and their primary entrypoints were reviewed. External cookbooks are dependencies, not local module inventory entries.

### Infrastructure Files

- `Berksfile`: Declares the local cookbooks and external Supermarket cookbook constraints. Replace Berkshelf resolution with Ansible Galaxy collection/role requirements or vendored roles, with versions pinned in CI.
- `Policyfile.rb`: Defines the Chef policy name, run list, and intended cookbook versions/dependencies. Its run list becomes an Ansible playbook and role order.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions. Preserve it as migration evidence and translate the tested dependency set into an Ansible lock/requirements process.
- `Vagrantfile`: Defines a `generic/fedora42` VM, hostname, private and forwarded ports, 2 GB RAM, 2 CPUs, libvirt provider, rsync repository mount, and shell provisioning. Adapt it to invoke `ansible-playbook` and decide whether the Fedora image or an Ubuntu/RHEL-compatible image is the supported target.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. It has no direct Ansible equivalent; replace it with inventory, project layout, logging, and execution configuration.
- `solo.json`: Chef attributes and run list, including sites, certificate locations, Fail2ban/UFW settings, and SSH policy. Convert these values to group/host variables, with secrets removed into Vault.
- `vagrant-provision.sh`: Installs Chef/Berkshelf, vendors dependencies, and runs Chef Solo. Replace with Ansible installation/bootstrap logic or an external developer setup script; do not pipe an unpinned remote installer directly into a shell in production workflows.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates. Port these to Jinja2 templates and Ansible handlers.
- `cookbooks/nginx-multisite/files/`: Static files for the three sites. Move into role `files/` or, preferably, deploy application/site content from a separately versioned artifact.
- `cookbooks/nginx-multisite/attributes/default.rb`: Defaults for site roots, TLS paths, and security settings. Convert to documented role defaults and environment-specific variables.
- `project-plan.md`: Repository planning context that should be reviewed by the migration owner before implementation if it contains requirements not represented in the Chef files.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu 18.04+ and CentOS 7+, while the Vagrant box is `generic/fedora42`. The provisioning script uses `apt-get`, and resources/user paths such as `www-data`, UFW, and Debian-style package names are Ubuntu-oriented. The supported target is therefore ambiguous; validate and select an explicit OS before role development. If no decision is made, use the requested default of Red Hat Enterprise Linux 9, but expect changes for package names, firewall tooling, service names, Nginx layout, and web-user ownership.
- **Virtual Machine Technology**: libvirt via Vagrant, with a 2-vCPU/2-GB development VM and rsync-mounted repository.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud-init configuration was identified.

## Migration Approach

### Key Dependencies to Address

- **Nginx cookbook 12.3.1**: Replace with `ansible.builtin.package`, templated configuration, site symlinks, service management, and validation handlers; retain the tested behavior rather than assuming the cookbook's defaults.
- **Memcached cookbook 6.1.0**: Replace with an Ansible role or native package/service/tasks, documenting bind address, port, memory, and firewall exposure.
- **RedisIO cookbook 7.2.4**: Replace with a maintained Ansible role or explicit distribution-specific tasks. Reproduce authentication, service enablement, log directory permissions, and configuration semantics without the brittle file-edit workaround.
- **SELinux cookbook 6.2.4**: Determine whether SELinux is required for the selected OS. On RHEL 9, use native Ansible SELinux modules and restorecon/semanage policy as needed; do not simply disable enforcement.
- **ssl_certificate cookbook 2.1.0**: The current local recipe generates self-signed certificates itself and does not visibly use this dependency. Decide whether development certificates remain self-signed or production uses an enterprise CA/Let's Encrypt workflow; use Vault or a certificate-management pipeline for private keys.
- **PostgreSQL system packages/service**: Replace shell-created database objects with `community.postgresql` modules, idempotent role/database/user tasks, and `pg_hba.conf` policy. Confirm the required PostgreSQL version and whether the database is local or external.
- **FastAPI Git repository and Python dependencies**: Replace Chef `git` and `execute` resources with `ansible.builtin.git`, package/venv tasks, and a pinned dependency artifact or requirements lock. Pin a commit or release instead of tracking `main` for production.
- **Chef/Berkshelf/Policyfile**: Remove Chef runtime dependencies after parity testing. Use `ansible-core` version pinning, `collections/requirements.yml`, role requirements, linting, Molecule or equivalent tests, and CI checks.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it immediately to Ansible Vault or an external secret manager, rotate it, and avoid exposing it in logs or rendered configuration.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes the same value to a world-readable (`0644`) `.env` file and database URL. Treat this credential as compromised, rotate it, use Vault, set restrictive file permissions, and prefer a service-specific non-root runtime account.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Create a dedicated application user, restrict filesystem access, and use a reverse proxy or socket/controlled port arrangement where appropriate.
- **TLS certificates and keys**: Self-signed RSA certificates are generated for all three sites, with private keys under `/etc/ssl/private`. Protect key material with restrictive ownership/mode, define renewal/rotation, and replace self-signed certificates for production with an approved CA. Confirm certificate SANs and the actual certificate deployment process.
- **SSH hardening**: Root login and password authentication are disabled through `sed` edits. Implement validated Ansible-managed `sshd_config` fragments, ensure key-based access and emergency access are available, run `sshd -t` before restart, and avoid locking out operators.
- **Firewall and Fail2ban**: UFW is enabled with default deny and SSH/HTTP/HTTPS allowances. Map this to the selected OS firewall (`firewalld` on RHEL is likely) and explicitly account for FastAPI port 8000, Redis, Memcached, and management networks. Keep Fail2ban jails aligned with the final Nginx and SSH logs.
- **Sysctl and Nginx security templates**: Port the reviewed security templates with validation and rollback safeguards. Test kernel settings and Nginx configuration before applying reloads.
- **Supply-chain security**: The installer downloads Chef from `omnitruck.chef.io`, the application clones an unpinned GitHub `main` branch, and Python packages are installed from an unconstrained requirements file. Pin and verify versions, use trusted mirrors/artifacts, and scan dependencies.
- **Per-module credential inventory**: `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials in commands and `.env`; `nginx-multisite` handles private TLS keys but no secret value is present in reviewed files. No encrypted data bags or Chef Vault usage were found in the reviewed repository.

### Technical Challenges

- **OS mismatch**: Fedora 42 is the Vagrant image, apt-based bootstrap assumes Debian/Ubuntu, and cookbook metadata also claims CentOS support. Resolve the support matrix first and test all roles on the chosen OS.
- **Non-idempotent shell behavior**: PostgreSQL creation uses `|| true`, Redis uses direct file rewriting, and security changes use `sed`/shell checks. Replace these with Ansible modules and explicit state assertions.
- **Configuration path and data drift**: `solo.json` uses `/var/www/...` roots while cookbook defaults use `/opt/server/...`; static files are selected from cookbook paths based on site names. Reconcile the authoritative document roots and preserve content mapping in variables.
- **TLS lifecycle**: Self-signed certificate generation is only suitable for development and has no renewal or CA integration. Define separate development and production certificate workflows.
- **Service ordering and readiness**: Nginx, Redis, PostgreSQL, and the FastAPI service need deterministic handlers, daemon reloads, database readiness checks, and application health checks. Model these dependencies in plays and handlers rather than relying on Chef resource ordering.
- **External cookbook behavior**: The lock includes transitive SELinux and cache-service dependencies whose exact defaults are not represented in the local cookbooks. Capture current runtime state and test parity before removing Chef.
- **Testing coverage**: Establish Molecule/integration tests for Nginx sites and TLS, firewall/SSH policy, Redis authentication, PostgreSQL schema access, FastAPI health, and reboot persistence. Use Vagrant/libvirt for a repeatable first target.

### Migration Order

1. **Baseline and target decision**: Inventory the live Chef-rendered state, rotate exposed credentials, choose the supported OS, and preserve the Policyfile lock as the initial behavior baseline.
2. **nginx-multisite**: Migrate static files, Nginx templates, virtual hosts, handlers, and development TLS first because it is visible and provides a useful integration test surface. Include hardening only after safe access is verified.
3. **cache**: Migrate Memcached and Redis with secure variables and service tests. Validate Redis authentication and determine whether either service must be network-accessible.
4. **fastapi-tutorial**: Migrate PostgreSQL, application checkout/build, secret injection, systemd service, and health checks. This is the highest-risk local module because it combines a database, third-party source, Python dependencies, and a privileged service.
5. **Host hardening and production cutover**: Finalize firewall/SELinux/SSH policy, certificate issuance, observability, rollback, and staged deployment. Run Chef and Ansible in a controlled comparison period before disabling Chef.

### Assumptions

- The three directories under `cookbooks/` are the complete local cookbook inventory.
- Chef Solo/Policyfile is the authoritative source; no Chef Server roles, environments, data bags, encrypted data bags, or external attribute repositories were visible in the reviewed files.
- The locked external cookbook versions are the intended behavior baseline: Nginx 12.3.1, Memcached 6.1.0, RedisIO 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0.
- The `ssl_certificate` dependency appears in the lock but is not visibly invoked by the local entrypoints; dependency usage must be confirmed before removal.
- `project-plan.md` was not used to infer implementation behavior; its requirements should be reconciled with this plan before coding.
- The actual contents and semantics of the ERB templates, including Nginx security directives, Fail2ban jails, and sysctl values, require targeted review during implementation.
- The application repository, `requirements.txt`, database schema/migrations, and operational health endpoint are external or not represented here.
- `main` branch deployment is currently intentional, but production migration will require a release or commit pin.
- The three hostnames resolve to the migrated host in the intended environment; DNS and certificate SAN requirements remain to be confirmed.
- The Vagrant forwarded ports and the provisioning script's printed IP addresses are not fully consistent; networking and operator access must be verified.
- The target may be development-only, but production-like security requirements are assumed because SSH, firewall, TLS, database, and credentials are configured.
- Ansible execution connectivity, privilege escalation method, inventory topology, monitoring, backup requirements, and secret-management platform are not specified and must be assigned to the platform and application teams.
- Team coordination should assign separate owners for OS/platform roles, Nginx/TLS, cache services, PostgreSQL/application deployment, security review, and integration testing; all owners should agree on variable contracts and acceptance tests before parallel implementation.
