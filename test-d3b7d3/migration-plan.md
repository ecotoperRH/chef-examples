# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile infrastructure stack with three local cookbooks: an Nginx multi-site/security layer, caching services, and a FastAPI/PostgreSQL application. The migration is moderate in breadth but high in security and correctness sensitivity because it contains hardcoded credentials, self-signed TLS generation, firewall/SSH hardening, and imperative shell/database commands. A focused team should be able to produce an initial Ansible implementation in approximately 2–4 weeks, including role development, Molecule or VM testing, security remediation, and cutover validation. Production-grade certificate and secret integration, OS compatibility work, and application behavior testing may extend this to 4–6 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web hosting for three named virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), with static content, HTTPS redirection, TLS configuration, security headers, rate limiting, and service management.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx package/service, per-site templates and symlinks, static index files, TLS 1.2/1.3, HSTS, CSP and other headers, gzip, Fail2ban, UFW, sysctl hardening, root-login/password-auth SSH hardening, and self-signed certificates.
    - Migration shape: Ansible role(s) for Nginx, security baseline, and certificate handling; use `template`, `copy`, `file`, `package`, `service`, `community.general.ufw`, `ansible.posix.sysctl`, and handlers.

- **cache**:
    - Description: Installs and enables Memcached and Redis, creates the Redis log directory, configures one Redis server on port 6379, and applies a post-configuration workaround to remove selected replication-related settings.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, Redis via `redisio`, Redis authentication, log directory ownership/mode, and imperative Redis configuration cleanup.
    - Migration shape: Ansible package/service/configuration tasks or maintained community roles; replace the Ruby post-processing workaround with an explicit managed Redis configuration and a controlled restart/handler.

- **fastapi-tutorial**:
    - Description: Installs Python 3 tooling, PostgreSQL client/server packages, Git, and libpq development headers; checks out a FastAPI tutorial application; creates a virtual environment; installs requirements; creates a PostgreSQL database/user; writes `.env`; and runs the application with systemd/Uvicorn on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout from `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python venv, pip install, PostgreSQL service, database bootstrap, systemd unit, and automatic service restart behavior.
    - Migration shape: Ansible role for runtime/application deployment and a separate database role or PostgreSQL collection tasks. Use `ansible.builtin.git`, `pip`, `community.postgresql.postgresql_user`, `postgresql_db`, `template`, `systemd`, and vaulted credentials.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree, and each module's `recipes/default.rb` entrypoint was reviewed. No Puppet, Salt, or PowerShell modules were found.

### Infrastructure Files

- `Berksfile`: Chef Supermarket and local cookbook dependency sources. It declares local cookbooks plus Nginx `~> 12.0`, Memcached `~> 6.0`, Redisio `~> 7.2.4`; the SSL cookbook line is commented out. Replace dependency resolution with Ansible Galaxy requirements and collection pinning.
- `Policyfile.rb`: Chef run list and dependency policy. It runs `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`, and explicitly includes `ssl_certificate ~> 2.1` even though the local Nginx cookbook generates certificates itself.
- `Policyfile.lock.json`: Resolved versions include nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, selinux 6.2.4, and ssl_certificate 2.1.0, plus the three local cookbooks. Treat these as the baseline for behavior comparison, not as direct Ansible dependencies.
- `Vagrantfile`: Local test harness using `generic/fedora42`, libvirt, 2 CPUs, 2 GB RAM, private IP `192.168.121.10`, and forwarded HTTP/HTTPS ports. It rsyncs the repository to `/chef-repo` and invokes `vagrant-provision.sh`. Port/address documentation in the shell script is inconsistent and must be corrected during test migration.
- `vagrant-provision.sh`: Installs Chef and Berkshelf using `apt-get`, vendors dependencies, and runs Chef Solo. The provisioning commands assume Debian/Ubuntu despite the Fedora Vagrant box; replace this with Ansible provisioner/inventory setup and OS-aware bootstrap.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Its paths define the source layout but have no direct runtime equivalent beyond Ansible project/inventory configuration.
- `solo.json`: Chef run list, site overrides, SSL paths, and security settings. It overrides cookbook default document roots to `/var/www/...` and is the key source for site variables and hardening intent.
- `project-plan.md`: Describes the surrounding X2Ansible analysis/migration tool rather than host configuration. Preserve as project context, but do not treat its example components as infrastructure requirements for this migration.

### Target Details

- **Operating System**: Intended runtime is ambiguous. Cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The Vagrant box is Fedora 42, while `vagrant-provision.sh` uses `apt-get` and Chef resources refer to Debian-style services/paths such as `www-data`, `ufw`, and `/var/log/auth.log`. The first Ansible target should be explicitly selected; Ubuntu 22.04/24.04 is the closest behavioral match. Add a separate Fedora/RHEL variable map only if Fedora is a required target.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly configured. No production virtualization platform is specified.
- **Cloud Platform**: Not specified. There are no AWS, Azure, or GCP-specific configurations.

## Migration Approach

### Key Dependencies to Address

- **Nginx 12.3.1 Chef cookbook**: Replace with an Ansible Nginx role or a locally owned role using distribution packages and managed templates. Preserve virtual hosts, links, handlers, logs, and validation with `nginx -t`.
- **Memcached 6.1.0 Chef cookbook**: Use distribution packages and an Ansible service/configuration role; define listen address, memory, and exposure explicitly rather than relying on cookbook defaults.
- **Redisio 7.2.4 and SELinux 6.2.4**: Replace with a supported Redis installation strategy and explicit SELinux policy/booleans where applicable. Verify configuration syntax and authentication behavior before cutover.
- **ssl_certificate 2.1.0**: It is locked by Policyfile but not used in the reviewed local recipes. Decide whether to remove it or replace it with Ansible-managed ACME/enterprise certificates. Do not carry forward self-signed certificates for production.
- **Python 3, pip, venv, Git, PostgreSQL, libpq-dev**: Map to OS-specific package names and Ansible package tasks. Pin Python dependencies from the application's requirements file during implementation; that file is external to this repository and was not reviewed.
- **PostgreSQL**: Use idempotent PostgreSQL collection modules rather than shell commands. Define database encoding, ownership, authentication method, and password storage explicitly.
- **Chef run list and attributes**: Convert to inventories, group variables, role defaults, and a top-level playbook. Separate web/security, cache, and application roles so teams can test and deploy independently.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and avoid placing it in rendered world-readable configuration or logs.
- **Hardcoded PostgreSQL credential**: `fastapi-tutorial` embeds `fastapi_password` in SQL commands and `/opt/fastapi-tutorial/.env`, which is mode `0644`. Treat this as compromised, rotate it, store it in Vault, and make `.env` mode `0600` with least-privilege ownership.
- **Database idempotency and exposure**: Current `CREATE USER`/`CREATE DATABASE` shell commands use `|| true`, masking failures and making state unclear. Use idempotent modules and verify local-only PostgreSQL access unless remote access is explicitly required.
- **TLS certificates and keys**: The Nginx role generates self-signed RSA 2048 certificates for each hostname, stores keys under `/etc/ssl/private`, and uses development identities. Replace with trusted certificates, ACME, or an enterprise certificate workflow; protect private keys and manage renewal. Review the configured cipher list and HSTS policy before production use.
- **Firewall and SSH hardening**: Preserve default-deny UFW, SSH/HTTP/HTTPS rules, disabled root login, and disabled password authentication, but make changes through Ansible modules and validate console/key access before applying. The current settings are enabled through hardcoded Chef conditionals and may fail or differ on Fedora/RHEL.
- **Nginx controls**: Preserve security headers, request limits, hidden-file denial, TLS protocol restrictions, and Fail2ban jails. Review the very small `client_max_body_size` (1K), CSP `unsafe-inline`, HSTS on all hosts, and custom cipher compatibility rather than blindly reproducing them.
- **Privilege and supply chain**: The FastAPI systemd service runs as `root`, clones an unpinned `main` branch, and installs dependencies without a reviewed lock file. Create a dedicated service account, pin a commit/release and dependency hashes, and restrict filesystem permissions.
- **Secret inventory by module**: `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials and a database URL; `nginx-multisite` has TLS private keys/certificate paths but no private key material in the tree. No Chef encrypted data bags or Chef Vault references were observed.

### Technical Challenges

- **OS mismatch**: Fedora 42 is declared by Vagrant but provisioning uses Debian tooling and Ubuntu-oriented assumptions. Resolve the canonical target OS before role design; add CI coverage for each supported family if portability is required.
- **Configuration precedence**: Nginx cookbook defaults use `/opt/server/{test,ci,status}`, while `solo.json` overrides them to `/var/www/{...}`. Establish one authoritative variable model and verify static file source paths (`cookbook_file` expects per-site source files).
- **Chef include/dependency behavior**: The Nginx default recipe includes `security`, `nginx`, `ssl`, and `sites`; the metadata does not declare an explicit dependency on the external Nginx cookbook even though Policyfile includes it. Ansible must make role/task ordering explicit.
- **Imperative workarounds**: Redis uses a Ruby block to remove several generated directives, and SSH/firewall/database configuration uses shell commands. Replace these with declarative templates/modules and tests; retain shell only where no safe module exists.
- **Application deployment lifecycle**: Git sync, pip installation, systemd daemon reload, service restart, and database initialization need clear change detection and handlers. Avoid reinstalling dependencies or restarting the API on every run.
- **External application source**: The FastAPI repository and its requirements were not included in this tree. Pin and review the source, runtime command, configuration contract, and migrations before production migration.
- **Testing limitations**: Existing testing is a single Vagrant flow with likely OS incompatibility and self-signed TLS. Build Molecule scenarios or equivalent VM tests for Nginx, security, Redis/Memcached, PostgreSQL, and end-to-end HTTP/HTTPS/API checks.

### Migration Order

1. **Foundation and target contract**: Select Ubuntu or a supported RHEL/Fedora target, define inventory/group variables, Vault integration, collections, linting, and the Vagrant/CI test strategy.
2. **Nginx-multisite static hosting**: Migrate package/service, site directories/content, templates, links, TLS variables, and handlers. Validate `nginx -t`, all three hostnames, HTTP-to-HTTPS redirects, and forwarded ports.
3. **Security baseline**: Implement firewall, SSH, sysctl, Fail2ban, file permissions, and TLS controls. Apply only after out-of-band access and rollback procedures are verified.
4. **Cache services**: Migrate Redis and Memcached with explicit bind/authentication/configuration, then test service startup, persistence expectations, and application connectivity. Rotate the current Redis secret.
5. **FastAPI/PostgreSQL application**: Provision packages and database idempotently, deploy a pinned application revision, create a dedicated user/service account, render vaulted configuration, and manage systemd/Uvicorn.
6. **Integrated cutover and decommissioning**: Run parallel validation against Chef and Ansible, compare packages/services/files/security behavior, perform staged rollout, and remove Chef/Berkshelf bootstrap only after rollback criteria are met.

### Assumptions

- The three local directories containing `metadata.rb` and `recipes/default.rb` are the complete cookbook/module inventory.
- Chef Solo is the effective execution model; no Chef Server, environments, roles, encrypted data bags, or external node attributes were found in the reviewed files.
- Ubuntu is the likely desired target because of `apt-get`, UFW, `www-data`, and Debian log/service conventions, but this must be confirmed because Vagrant declares Fedora 42 and metadata also supports CentOS.
- The locked external cookbook versions are the intended source baseline, although exact behavior of those external cookbooks was not audited.
- `ssl_certificate` is an unused or transitional dependency in the local recipes; its production requirement needs confirmation.
- The FastAPI Git repository, application requirements, database migrations, and expected API behavior are external and require separate review.
- The three static HTML files under `nginx-multisite/files/default` are intended to populate the three sites; their mapping and destination override should be tested.
- Hostnames are development/test names and DNS/`/etc/hosts` management is outside the repository; production DNS and certificate ownership are not specified.
- No cloud platform, load balancer, external database, monitoring, backup, or centralized secrets provider is specified.
- The documented timeline assumes one platform engineer and one application/security reviewer working in parallel, with stakeholder access to test hosts and credentials.
- Migration acceptance means equivalent or intentionally improved package, service, file, network, TLS, authentication, and application behavior—not literal one-to-one reproduction of Chef implementation quirks.
