# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment composed of three local cookbooks and several external cookbook dependencies. It provisions a development-oriented Fedora Vagrant VM as an Nginx multi-site host, caching services, and a FastAPI tutorial application backed by PostgreSQL. The functional migration is moderate in scope, but security remediation is high priority because Redis, PostgreSQL, and application credentials are currently embedded in cookbook code and generated configuration. A focused migration can be delivered in approximately 2–4 weeks, including role conversion, molecule/integration testing, secret remediation, and Vagrant validation; production hardening and operational rollout should be planned separately.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web hosting stack for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), including web content directories, Nginx configuration, TLS setup, host firewall, Fail2ban, sysctl hardening, and SSH hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management; per-site templates and symlinks; static `index.html` content; self-signed RSA certificates for development; UFW rules; Fail2ban; disabled root SSH login and password authentication.
    - Ansible target: A role or coordinated roles for `nginx`, `tls`, `firewall`, `fail2ban`, and `ssh_hardening`, with site definitions represented as structured variables.

- **cache**:
    - Description: Memcached and Redis service configuration for local caching, including Redis logging, a password-protected Redis instance on port 6379, service enablement, and a post-configuration workaround for generated Redis replication settings.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Inclusion of external Memcached and Redis cookbooks; Redis authentication; `/var/log/redis` ownership and permissions; direct configuration-file mutation to remove incompatible replication directives.
    - Ansible target: A cache role using distribution packages or supported Ansible collections, explicit Redis configuration, handlers, and idempotent service management. The current Ruby workaround should be replaced by a documented configuration model rather than a text-edit hack.

- **fastapi-tutorial**:
    - Description: Installs Python 3 and PostgreSQL, checks out the `dibanez/fastapi_tutorial` GitHub repository, creates a virtual environment, installs Python requirements, initializes the `fastapi` database/user, writes a `.env` file, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git-based application deployment; Python virtual environment; PostgreSQL service; database and user bootstrap; systemd unit; Uvicorn bound to `0.0.0.0:8000`.
    - Ansible target: Separate application, PostgreSQL, and systemd tasks/roles, with database modules and Ansible Vault rather than shell SQL commands or plaintext credentials.

**CRITICAL PATH VERIFICATION:**

The module paths above were present in the supplied repository tree and their `metadata.rb` and `recipes/default.rb` entrypoints were reviewed. The three local cookbooks are the modules in scope; external cookbooks listed below are dependencies, not local module inventory entries.

### Infrastructure Files

- `Berksfile`: Defines local cookbook sources and Supermarket dependencies for Nginx, Memcached, Redis, and the optional/commented SSL cookbook. Its dependency resolution should be replaced by Ansible collections, OS packages, and project roles.
- `Policyfile.rb`: Defines the Chef policy name, run list, local cookbook paths, and pinned/version-constrained external cookbooks. The run list is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`.
- `Policyfile.lock.json`: Records resolved versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, Selinux 6.2.4, and ssl_certificate 2.1.0, plus the three local cookbooks at version 1.0.0. Preserve this as migration evidence and create an Ansible dependency lock/version policy.
- `Vagrantfile`: Defines the test environment: `generic/fedora42`, hostname `chef-nginx`, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 8080/8443 to guest ports 80/443. It rsyncs the repository to `/chef-repo` and runs `vagrant-provision.sh`.
- `vagrant-provision.sh`: Installs packages, Chef, Berkshelf, vendors dependencies, and runs Chef Solo. Replace it with an Ansible-compatible bootstrap or use Ansible provisioner/`ansible_local`, while avoiding remote installer scripts in production.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. It has no direct Ansible equivalent; replace it with inventory, `ansible.cfg`, role paths, and execution documentation.
- `solo.json`: Supplies the run list, three site definitions, SSL paths, and security settings. Its values should become group/host variables, with secrets moved to Vault.
- `project-plan.md`: Existing project planning context; reconcile it with the Ansible implementation backlog and acceptance criteria.
- `cookbooks/nginx-multisite/templates/` and `files/`: Source Nginx, security, Fail2ban, sysctl, and site templates plus static site pages. Convert ERB templates to Jinja2 and static files to role `files/` content.

### Target Details

- **Operating System**: The explicit test target is Fedora 42 (`generic/fedora42`), but the provisioning script uses `apt-get`, and cookbook metadata claims support for Ubuntu >=18.04 and CentOS >=7. The effective target is therefore unresolved. First migration milestone must select Fedora/RHEL-family behavior or Ubuntu behavior and test package/service names accordingly. Do not assume the current script can provision Fedora.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 vCPUs and 2 GB memory. The target Ansible workflow should retain a Vagrant/libvirt integration test or establish an equivalent CI VM.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was identified.

## Migration Approach

### Key Dependencies to Address

- **Nginx Chef cookbook 12.3.1**: Replace with Ansible package/service tasks and Jinja2-managed configuration. Decide whether to use `ansible.posix`/`community.general` modules or a maintained internal Nginx role.
- **Memcached cookbook 6.1.0**: Replace with OS package installation, service management, and explicit listening/security configuration. Confirm whether Memcached is actually required by the application.
- **Redisio cookbook 7.2.4**: Replace with a supported Redis role or package-based tasks. Reproduce authentication, logging, startup, and the intended non-replication configuration without the current post-edit workaround.
- **Selinux cookbook 6.2.4**: Determine whether SELinux is required for the chosen Fedora/RHEL target. Use `ansible.posix.selinux`, file-context tasks, and appropriate booleans rather than silently disabling controls.
- **ssl_certificate 2.1.0**: It is locked and listed in Policyfile but not visibly invoked by the reviewed local recipes. Confirm whether it is legacy or transitive configuration. Replace with Ansible certificate deployment or an approved ACME/PKI workflow; retain self-signed certificates only for development.
- **PostgreSQL and Python system packages**: The FastAPI cookbook installs these directly and does not lock versions. Define supported PostgreSQL/Python versions, package repositories, migration behavior, and compatibility tests.
- **Git repository `https://github.com/dibanez/fastapi_tutorial.git` at `main`**: Replace the floating branch with a commit/tag or release artifact for reproducibility, and define how application updates are promoted.
- **Chef run list and attributes**: Translate to inventories, role defaults, group variables, handlers, and tags. Preserve the current execution dependency: security/web setup, cache services, and application/database readiness.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Remove it from source history where appropriate, rotate it, and store the replacement in Ansible Vault or an external secret manager. Restrict Redis to required interfaces and verify authentication after deployment.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes the same value into `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate it, use `community.postgresql.postgresql_user`/`postgresql_db`, protect the environment file (normally `0600`), and avoid logging credentials.
- **TLS certificates and private keys**: The Nginx cookbook generates self-signed certificates and stores keys under `/etc/ssl/private` with `root:ssl-cert` and mode `0710` on the directory, then key mode `0640`. In Ansible, deploy production certificates through a controlled PKI/secret path, use restrictive permissions, validate certificate/key matching, and define renewal. Never treat the development certificate generation as production TLS.
- **SSH hardening**: Root login and password authentication are disabled through `sed` edits. Use `ansible.builtinประก_lineinfile`/`template` with validation (`sshd -t`) and ensure an administrative key-based user exists before applying the change to avoid lockout.
- **Firewall and service exposure**: UFW allows SSH, HTTP, and HTTPS, while the FastAPI service listens on all interfaces at port 8000 and Redis/PostgreSQL may be locally reachable. Explicitly define allowed sources and whether backend services must be loopback-only. Account for Fedora's firewalld rather than assuming UFW.
- **Fail2ban and sysctl**: Preserve the reviewed templates and validate their intended rules in the target OS. Apply handlers safely and test that an invalid configuration does not interrupt SSH or networking.
- **Application execution**: The systemd service runs Uvicorn as `root`. Create a dedicated unprivileged service account, use systemd hardening options where compatible, and place writable application/state paths deliberately.
- **Supply-chain and reproducibility**: Chef installation uses `curl | bash`, dependencies include a GitHub `main` branch, and pip requirements are not pinned by this repository. Pin installers/artifacts, verify checksums where practical, and establish CI scanning for secrets and vulnerable packages.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is the Vagrant box, while `vagrant-provision.sh` invokes `apt-get` and the cookbook targets Ubuntu/CentOS. Resolve the support matrix first; use OS-family conditionals only if both families are a real requirement.
- **Chef resource semantics versus Ansible idempotence**: Several resources use shell commands (`psql`, `sed`, `openssl`, UFW commands) and one Ruby block mutates Redis configuration. Convert these to purpose-built Ansible modules, templates, and handlers, with `changed_when`/`failed_when` only where unavoidable.
- **Configuration drift in site paths**: `attributes/default.rb` uses `/opt/server/...`, while `solo.json` overrides the sites to `/var/www/...`. The static cookbook files are under `files/default/{ci,status,test}`. Establish one canonical variable schema and verify content placement and Nginx document roots.
- **TLS and virtual-host behavior**: Three sites depend on generated certificate filenames and an ERB site template. Build representative tests for HTTP/HTTPS bindings, certificate paths, disabled default site, and Nginx syntax before enabling reload handlers.
- **Database initialization repeatability**: Current SQL commands use `|| true`, masking failures and making ownership/permissions behavior unclear. Use PostgreSQL modules, explicit state, readiness checks, and migration strategy for existing databases.
- **Application lifecycle**: The cookbook installs dependencies on every convergence and runs as root. Define deployment, upgrade, rollback, service health checks, and process ownership in the Ansible design.
- **External dependency uncertainty**: The locked `ssl_certificate` dependency is not visibly used, and external cookbook internals were not part of the local source review. Validate behavior against the running Chef environment before declaring parity.
- **Testing and rollout**: Preserve Vagrant/libvirt as a fast integration environment and add Molecule or equivalent tests for each role. Compare rendered configurations and service states during a staged dual-run/cutover.

### Migration Order

1. **Foundation and target OS decision**: Establish inventory, Vagrant/Ansible execution, supported OS, package repositories, SSH access, and secret storage. Add CI linting and Molecule smoke tests.
2. **nginx-multisite security and web baseline**: Migrate Nginx, static files, virtual hosts, firewall, Fail2ban, sysctl, and SSH hardening. This is the central host role and provides visible integration tests.
3. **cache**: Migrate Memcached and Redis after the OS/package model is stable. Resolve the Redis configuration workaround and rotate the exposed password before testing.
4. **PostgreSQL and fastapi-tutorial application**: Provision database securely, pin the application revision and Python dependencies, create a non-root service, and validate the FastAPI health path. This is the highest application complexity.
5. **TLS productionization and hardening**: Replace self-signed certificates where required, confirm certificate renewal/secret delivery, run security scans, and perform staged acceptance testing.
6. **Cutover and Chef retirement**: Freeze Chef changes, run Ansible in the Vagrant acceptance environment, document rollback, migrate any persistent data, then remove Chef/Berkshelf bootstrap dependencies after operational sign-off.

Estimated implementation effort is about 3–5 engineer-weeks for one team: 1 week for foundation and web role, 0.5–1 week for cache, 1–2 weeks for PostgreSQL/FastAPI and security remediation, and 0.5–1 week for testing, documentation, and rollout. Add time for production certificate/secret integration and any undocumented dependencies.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local modules in scope.
- The supplied Policyfile lock is the authoritative snapshot of external Chef dependencies, although the working tree is marked unclean in its SCM metadata.
- The Vagrant Fedora box is a development/test target, not proof that production runs Fedora.
- Production cloud, inventory, DNS ownership, persistent storage, backup, monitoring, and certificate authority requirements were not specified.
- The three cluster-local hostnames and their DNS/hosts-file resolution are test fixtures; production DNS and ingress requirements must be supplied.
- The FastAPI repository, its `requirements.txt`, application health endpoint, and database schema/migration behavior were not inspected and must be validated separately.
- The application needs PostgreSQL, Redis, and/or Memcached as deployed; actual runtime dependency and ports must be confirmed with application owners.
- Existing data may need preservation, but no backup or migration procedure is present in the reviewed files.
- Self-signed TLS is acceptable only for local development; production certificates and renewal ownership remain undefined.
- The intended firewall is not fixed: UFW is configured by Chef, while Fedora commonly uses firewalld.
- Existing administrative access is assumed to be key-based before SSH password authentication and root login are disabled.
- Secrets may already have entered Git history through the hardcoded Redis and PostgreSQL values; repository scanning, rotation, and history remediation are required.
- The Ansible implementation should preserve externally observable behavior, not reproduce Chef-specific implementation details such as `ruby_block`, `include_recipe`, or `chef-solo` paths.
- Team coordination should assign owners for OS/platform, web/security, cache, database/application, secrets/PKI, and test/operations work; each owner should provide acceptance checks and rollback steps before production cutover.
