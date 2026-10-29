# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile environment with three local cookbooks, Supermarket dependencies, and a Vagrant/libvirt development VM. It provisions a multi-site Nginx frontend, host hardening controls, Redis and Memcached caching, and a FastAPI tutorial application backed by a local PostgreSQL instance. The migration is moderate in complexity: the role count is low, but the configuration combines OS-specific package/service assumptions, security-sensitive SSH/firewall/TLS changes, third-party cookbook behavior, and embedded plaintext credentials. A two-engineer effort can reasonably deliver an initial, tested Ansible implementation in approximately 2–4 weeks, including environment reconciliation, secret remediation, integration testing, and rollout documentation.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:** All paths below are present in the supplied repository tree. Each cookbook has been assessed from its `metadata.rb` and primary `recipes/default.rb`; the Nginx orchestrator’s included recipes were reviewed because they define its central behavior.

- **nginx-multisite**:
  - Description: Provisions an Nginx web frontend serving three named sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`) with static landing pages, per-site virtual-host configurations, and development self-signed TLS certificates.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Installs and enables Nginx; renders main, security, and site configuration templates; creates document roots and deploys supplied static content; enables site symlinks and removes the default site; generates one RSA 2048-bit self-signed certificate per TLS-enabled site; configures Fail2ban, UFW, sysctl hardening, and SSH root/password-login restrictions.

- **cache**:
  - Description: Configures local Memcached and Redis services, including Redis authentication and a compatibility-oriented post-processing edit to the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Includes external `memcached` and `redisio` recipes; configures Redis on port 6379; creates `/var/log/redis`; enables Redis; deletes selected replication and client-buffer directives from `/etc/redis/6379.conf` through an imperative Ruby block.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from GitHub to `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application dependencies, and runs it as a systemd service backed by local PostgreSQL.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Installs Python, Git, PostgreSQL, and development packages; clones the `main` branch; installs requirements with pip; creates the database role/database/grants with `psql`; writes an application `.env`; exposes Uvicorn on all interfaces at port 8000; enables and starts PostgreSQL and the FastAPI service.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and external cookbook constraints. It is replaced by Ansible Collections/roles declared in `collections/requirements.yml` only where a collection is actually selected; native Ansible modules should cover most functions.
- `Policyfile.rb`: Defines the authoritative Chef run list and requested dependency constraints. Translate its sequencing into a site playbook that applies baseline/security and frontend controls before application validation, while retaining explicit service dependencies.
- `Policyfile.lock.json`: Locks resolved Supermarket cookbook versions: Memcached 6.1.0, Nginx 12.3.1, RedisIO 7.2.4, SELinux 6.2.4, and SSL Certificate 2.1.0. Retain this as source evidence only; validate package/version behavior directly in Ansible rather than attempting cookbook-for-cookbook substitution.
- `solo.json`: Chef Solo run list plus Nginx site, certificate-directory, and security inputs. Convert into role defaults and environment-specific `group_vars`; resolve its document-root values (`/var/www/...`) against the cookbook defaults (`/opt/server/...`) before implementation.
- `solo.rb`: Chef Solo cache, cookbook path, and logging setup. No functional Ansible equivalent is required beyond the Ansible project/inventory configuration and CI logging.
- `Vagrantfile`: Defines a `generic/fedora42` libvirt VM with 2 GB RAM, two CPUs, private IP `192.168.121.10`, and HTTP/HTTPS forwarding. Preserve or replace with a Vagrant Ansible provisioner for development testing. The libvirt provider is the only identified VM technology.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef from Omnitruck, installs Berkshelf, vendors cookbooks, and invokes Chef Solo. It should be retired and replaced by Ansible provisioning; its Debian package commands conflict with the Fedora Vagrant box and must not be copied unchanged.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default Nginx sites, certificate paths, and host-security feature flags. Model as documented, overridable Ansible role defaults.
- `cookbooks/nginx-multisite/templates/` and `cookbooks/nginx-multisite/files/`: Nginx, virtual-host, security, Fail2ban, and sysctl templates plus static site assets. Convert ERB templates to Jinja2 and preserve managed-file ownership/modes after OS-specific account validation.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource source. It is not invoked by the reviewed primary recipes; assess whether it is unused before porting. If needed, use `ansible.builtin.lineinfile` rather than recreating a custom abstraction.

### Target Details

- **Operating System**: Mixed and inconsistent. Cookbook metadata supports Ubuntu 18.04+ and CentOS 7+, while `Vagrantfile` selects Fedora 42. Nginx site paths (`sites-available/sites-enabled`), `www-data`, UFW, and service name `ssh` are Debian/Ubuntu-oriented; the bootstrap uses `apt-get`. Default target should therefore be Ubuntu LTS for behavior parity, despite the current Fedora Vagrant box. If Fedora/RHEL 9 is required, redesign firewall (firewalld), SSH service naming, Nginx layout, package names, ownership, SELinux policy, and PostgreSQL/Redis paths before rollout.
- **Virtual Machine Technology**: Vagrant with the libvirt provider. No production virtualization platform is specified.
- **Cloud Platform**: Not specified. No cloud-provider tooling or metadata integration was found.

## Migration Approach

Create a conventional Ansible repository with an inventory, environment/group variables, `collections/requirements.yml`, and roles such as `baseline_security`, `nginx_multisite`, `cache`, and `fastapi_tutorial`. Use handlers for Nginx, Fail2ban, SSH, sysctl, and systemd reloads. Establish CI that runs `ansible-lint`, syntax checks, idempotence tests, and a Vagrant/libvirt (or equivalent disposable VM) integration test. Assign ownership by role, use a shared variable/secrets contract, and hold joint security/application acceptance reviews before production deployment.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Remove from managed hosts. Replace Chef convergence, attributes, notifications, and run-list ordering with Ansible roles, variables, handlers, and playbooks.
- **Chef Supermarket / Berkshelf**: Retire dependency vendoring. Prefer `ansible.builtin` and `ansible.posix` modules; pin any required community collections in `collections/requirements.yml` and lock/test them in CI.
- **nginx Chef cookbook (resolved 12.3.1; requested ~> 12.0)**: The local cookbook installs the OS Nginx package itself and does not visibly include this dependency. Implement package installation, configuration deployment, service enablement, and validation natively; determine whether the locked cookbook has hidden historical significance before omitting it.
- **memcached Chef cookbook (resolved 6.1.0; requested ~> 6.0)**: Replace with package/service tasks and explicit configuration only if the external cookbook’s effective defaults are required. Validate listener address, memory settings, and exposure because this repository does not declare them.
- **redisio Chef cookbook (resolved 7.2.4)**: Replace with Redis package/configuration/service tasks. Explicitly model port, authentication, log directory, and desired replication/client-buffer settings instead of text deletion after configuration generation.
- **ssl_certificate Chef cookbook (resolved 2.1.0)**: It is listed in the Policyfile and lock but commented out in `Berksfile` and not declared in local cookbook metadata. The local code generates certificates with OpenSSL, so use `community.crypto` certificate/key modules or an approved PKI workflow; confirm whether the cookbook is unnecessary.
- **SELinux Chef cookbook (resolved 6.2.4)**: Present transitively in the lock but not directly used in reviewed local recipes. Determine whether it is required only by external dependencies. For RHEL/Fedora targets, manage SELinux state, file contexts, and network access explicitly rather than disabling enforcement.
- **GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` (`main`)**: Pin a reviewed commit/tag or signed release in Ansible rather than deploying the mutable `main` branch. Establish ownership for application release, dependency lock files, and availability checks.
- **PostgreSQL, Python/pip/venv, Uvicorn, Nginx, OpenSSL, Fail2ban, UFW, Memcached, Redis**: Use distribution-aware packages and service units. Validate availability and version compatibility for the chosen operating-system baseline.

### Security Considerations

- **Plaintext Redis credential in `cache`**: `redis_secure_password_123` is embedded in the recipe. Store a replacement secret in Ansible Vault or an approved external secret manager, deploy it with restrictive permissions, rotate it, and confirm client configuration uses the new secret.
- **Plaintext PostgreSQL/application credential in `fastapi-tutorial`**: `fastapi_password` is embedded in database-creation commands and written into `/opt/fastapi-tutorial/.env` with mode `0644`. Move the database password and `DATABASE_URL` to Vault/external secrets, generate/rotate a strong password, run database tasks with `no_log: true`, and restrict the environment file to the application account (normally `0600`).
- **TLS in `nginx-multisite`**: The source generates self-signed certificates with `-nodes`, so private keys are unencrypted at rest and valid for 365 days. Keys are currently `root:ssl-cert` mode `0640`; preserve least-privilege access but replace development certificates with enterprise PKI/ACME-issued certificates in non-development environments. Never commit private keys or vault passwords.
- **SSH hardening in `nginx-multisite`**: Root login and password authentication are disabled by in-place `sed` operations. Use a managed drop-in configuration with syntax validation and ensure named administrators have working key-based access and an emergency rollback path before applying it.
- **Network controls in `nginx-multisite`**: UFW defaults to deny and permits SSH/HTTP/HTTPS; Fail2ban and sysctl hardening are enabled. Implement firewall policy atomically and test console access to avoid lockout. Ensure Redis (6379), Memcached, PostgreSQL, and FastAPI (8000) remain loopback-only or are explicitly protected; the reviewed source does not prove their bind/exposure settings.
- **FastAPI process privilege**: The systemd unit runs as `root` and binds Uvicorn to `0.0.0.0:8000`. Migrate to a dedicated non-login service account, least-privilege writable paths, and preferably proxy only through Nginx. Add service sandboxing where compatible.
- **Supply chain**: Chef is installed from a curl-piped remote shell script, packages are unpinned, and the application follows a mutable Git branch. Ansible deployment should use controlled package repositories, pinned application revisions, dependency hashes/constraints, and approved collection sources.

### Technical Challenges

- **OS contradiction and incomplete portability**: Fedora 42 is declared for Vagrant, but the provisioning script and multiple cookbook assumptions are Ubuntu/Debian-specific. Select and document the target OS before role implementation; test only supported OS families or provide explicit platform task branches.
- **Configuration-source conflict**: `solo.json` overrides cookbook site document roots with `/var/www/...`, whereas cookbook defaults use `/opt/server/...`. Define variable precedence and the intended environment-specific values, then test that static content and virtual hosts use the same locations.
- **External cookbook behavior is opaque in the local source**: Memcached and RedisIO implement behavior not fully visible here, and the Redis recipe additionally edits generated config using brittle regex-based deletion. Capture the desired final Redis/Memcached configuration from a representative Chef-converged host, agree on supported settings, and express them declaratively in templates or module arguments.
- **Database idempotence and lifecycle**: Chef suppresses all database/user creation errors using `|| true`. Use PostgreSQL-aware Ansible modules with peer/administrative authentication, explicit ownership/privileges, and an agreed migration/backup process. Do not treat all database errors as success.
- **Application runtime deployment**: The source runs pip against an unpinned application repository and uses a root-owned root-run systemd service. Pin releases and Python dependencies, define health checks, place Nginx proxy behavior explicitly if required, and coordinate schema/application deployment with the application team.
- **Security-control rollout risk**: Firewall and SSH changes can sever access; self-signed TLS behavior can affect clients. Stage on isolated VMs, validate connectivity from management networks, and use serial/canary deployment with documented rollback.

### Migration Order

1. **Foundation and target-platform decision**: Confirm Ubuntu LTS versus RHEL/Fedora, build the Ansible repository/inventory/CI scaffold, define variable precedence, create secret storage, and reproduce the Vagrant/libvirt test environment. This unblocks reliable role development.
2. **baseline security / nginx-multisite**: Migrate firewall, SSH, Fail2ban, sysctl, certificate handling, Nginx configuration, static site deployment, and handlers. Validate public HTTP/HTTPS plus administrative SSH access before application integration.
3. **cache**: Replace Memcached/Redis cookbook dependencies with explicit packages, services, binding/access controls, declarative Redis authentication, and migrated secrets. Verify application connectivity and cache persistence/availability requirements.
4. **fastapi-tutorial**: Migrate PostgreSQL provisioning, controlled Git release deployment, Python environment/dependency installation, environment secrets, dedicated service account, systemd unit, and application health checks. Integrate it with the validated Nginx frontend and run end-to-end tests.
5. **Cutover and retirement**: Compare Chef-converged and Ansible-managed hosts, conduct security/application sign-off, deploy through canary then phased rollout, document operational ownership/runbooks, and remove Chef/Berkshelf bootstrap artifacts after acceptance.

### Assumptions

- The only infrastructure-as-code technology to migrate is Chef; no Puppet, Salt, or PowerShell modules are present in the supplied tree.
- The three directories under `cookbooks/` are the complete set of local Chef cookbooks.
- Chef Policyfile ordering (`nginx-multisite`, `cache`, `fastapi-tutorial`) represents the intended deployment scope, though the actual dependency order between Nginx and the FastAPI service is not fully expressed.
- Ubuntu LTS is recommended for initial parity because of UFW, `www-data`, Nginx Debian layout, and `apt-get` usage. Fedora 42 in Vagrant may be an accidental or unfinished test target; it must be confirmed rather than assumed.
- No production inventory, environment tiers, DNS, certificate authority, cloud platform, load balancer, CI system, or production VM platform is specified.
- The three `.cluster.local` names and bundled static pages appear to be development/test content; ownership and production DNS/certificate requirements require confirmation.
- The intended final Memcached, Redis, Nginx template, Fail2ban, and sysctl settings must be validated against a converged Chef host because templates and third-party cookbook internals were not exhaustively audited in this high-level survey.
- The FastAPI application’s dependency pinning, database migration method, expected reverse-proxy path, and health endpoint are not specified by the reviewed cookbook and need application-team input.
- The hardcoded passwords and self-signed certificates are treated as insecure development defaults, not acceptable production secret or PKI practices.
- The custom `lineinfile` Chef resource appears unused by reviewed primary recipes; it should not be migrated unless a usage review confirms otherwise.
