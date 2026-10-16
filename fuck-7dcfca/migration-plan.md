# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks: an Nginx multi-site web tier, caching services, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in operational risk rather than size: the codebase is small, but it combines web serving, TLS, host security hardening, Redis/Memcached, PostgreSQL, an externally sourced application, and systemd services. A single engineer familiar with Ansible could produce an initial implementation in approximately 1–2 weeks; production validation, secret remediation, OS compatibility work, and team handoff should be planned for another 1–2 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server configuration for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), including static site roots, security headers/configuration, fail2ban, UFW, SSH hardening, sysctl settings, and development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx package/service management, per-site templates and symlinks, static HTML files, fail2ban and UFW configuration, disabling root SSH login and password authentication, generated RSA certificates, and a custom `lineinfile` resource available for file editing.
    - Ansible target: A role or role set for Nginx, TLS, and host hardening; use `ansible.builtin.template`, `file`, `package`, `service`, `ufw`/platform firewall tasks, `sysctl`, and `openssh` configuration rather than shell-based edits where possible.

- **cache**:
    - Description: Installs and enables Memcached and Redis, creates the Redis log directory, configures a Redis server on port 6379, and applies a post-configuration workaround to remove several replication-related directives.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, RedisIO server configuration, Redis password authentication, Redis service enablement, and an imperative configuration cleanup workaround.
    - Ansible target: A cache role, potentially split into Redis and Memcached roles, using distribution packages or vetted Ansible roles and managed configuration templates. Redis credentials must be supplied through Ansible Vault or an external secret manager.

- **fastapi-tutorial**:
    - Description: Installs Python 3, PostgreSQL client/server packages, Git, and development libraries; clones `dibanez/fastapi_tutorial` at `main`; creates a virtual environment; installs application requirements; creates a PostgreSQL database/user; writes an environment file; and runs Uvicorn as a root-owned systemd service on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: External Git deployment, Python virtualenv, pip dependency installation, PostgreSQL service/database bootstrap, systemd unit creation, and application restart/service enablement.
    - Ansible target: An application role plus database tasks. Prefer a pinned Git revision, a non-root service account, idempotent PostgreSQL modules (`community.postgresql`), a templated systemd unit, and controlled secret file permissions.

**CRITICAL PATH VERIFICATION:**
Only the module paths listed above were present in the supplied repository tree and were confirmed by reading their primary `recipes/default.rb` files. External cookbooks in the lockfile are dependencies, not local modules, and are not included in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef dependency source and local cookbook declarations. It references local cookbooks and Supermarket dependencies including Nginx, Memcached, RedisIO, and a commented `ssl_certificate` declaration. Replace with Ansible collection/role requirements and document pinned versions.
- `Policyfile.rb`: Defines the Chef policy name, run list, local cookbook paths, and dependency constraints. Its run list is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`; convert this into an Ansible playbook and role order.
- `Policyfile.lock.json`: Resolved dependency graph and versions. It locks `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0, as well as the three local cookbooks. Preserve this as migration input, but do not assume the old Chef cookbook behavior maps directly to Ansible.
- `Vagrantfile`: Defines the test environment using `generic/fedora42`, libvirt, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and ports 8080/8443 forwarded to guest ports 80/443. It rsyncs the repository to `/chef-repo` and invokes `vagrant-provision.sh`. Adapt it to run `ansible-playbook` against the guest, or replace it with an Ansible-compatible Molecule/libvirt test harness.
- `vagrant-provision.sh`: Performs `apt-get` provisioning, installs Chef and Berkshelf from the internet, vendors dependencies, and runs Chef Solo. This is incompatible with the Fedora base image as written because it assumes `apt-get`; replace it with Ansible installation/bootstrap logic or use the distribution's Python/Ansible tooling from the host.
- `solo.rb`: Chef Solo cache, cookbook path, and logging configuration. It has no direct Ansible equivalent; retain only relevant logging/cache behavior in playbook execution and CI.
- `solo.json`: Chef run list and runtime attributes for the three sites, SSL paths, and security settings. Convert these values into group/host variables, role defaults, and vaulted secrets where applicable. Note that its document roots (`/var/www/...`) differ from the cookbook attribute defaults (`/opt/server/...`).
- `project-plan.md`: Existing project planning document; review during migration kickoff for requirements and acceptance criteria, but it was not needed to identify the implementation modules.
- `cookbooks/nginx-multisite/templates/*` and `files/default/*`: Nginx, security, fail2ban, sysctl, and virtual-host templates plus static `index.html` content. Convert templates to Jinja2 and static content to Ansible-managed files/templates.

### Target Details

- **Operating System**: The stated test target is Fedora 42 (`generic/fedora42`) under Vagrant/libvirt, while cookbook metadata claims support for Ubuntu >=18.04 and CentOS >=7. The provisioning script assumes Debian/Ubuntu (`apt-get`), and recipes use Debian-oriented names such as `www-data`, `ufw`, and `ssh`. Establish Fedora 42 as the first-class target or explicitly support separate Debian and Red Hat-family variable sets before implementation.
- **Virtual Machine Technology**: libvirt through Vagrant, with a 2-CPU/2-GB development VM and rsync-mounted source repository.
- **Cloud Platform**: Not specified. No cloud provider integration or cloud-init configuration is present.

## Migration Approach

### Key Dependencies to Address

- **Ansible core and collections**: Standardize an Ansible version and use `ansible.posix` for `sysctl`, firewall-related tasks where appropriate, and `community.general`/`community.postgresql` for service-specific capabilities. Pin collection versions in `collections/requirements.yml`.
- **Nginx Chef cookbook 12.3.1**: Replace with native Ansible package/service/template tasks or a reviewed Nginx role. Recreate the custom Nginx configuration, security configuration, virtual hosts, and site links explicitly.
- **Memcached Chef cookbook 6.1.0**: Replace with platform-aware package, configuration, and service tasks. Confirm whether Memcached is actually required by the application; the current cookbook includes it without application wiring.
- **RedisIO 7.2.4 and SELinux 6.2.4**: Replace with a supported Redis role or native tasks. Reconcile Fedora SELinux policy and Redis paths, ports, and service names instead of copying the Chef workaround blindly.
- **ssl_certificate 2.1.0**: It is locked in the Policyfile but not declared in the active Berksfile and the local cookbook directly generates self-signed certificates. Decide whether development certificates remain local-only or production uses an enterprise CA/ACME workflow.
- **PostgreSQL**: Use distribution packages plus `community.postgresql.postgresql_db` and `postgresql_user`, with explicit idempotency and authentication rules. The current shell commands suppress errors with `|| true`, which must not be carried forward.
- **FastAPI Git repository and Python dependencies**: Replace the floating `main` revision with a commit/tag, validate the repository's requirements, and use a Python role or Ansible tasks for virtualenv/pip installation. Add deployment health checks before switching traffic.
- **Systemd**: Convert the inline unit to a Jinja2 template and use `ansible.builtin.systemd_service` with daemon reload handlers. Define a dedicated least-privilege application user.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123` in source. Remove it from code and rotate it; store the replacement in Ansible Vault or an external secret manager, and configure Redis with restrictive file ownership.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` embeds username `fastapi`, password `fastapi_password`, and a full database URL in shell commands and `/opt/fastapi-tutorial/.env`. Treat these credentials as compromised, rotate them, vault them, and write the environment file with restrictive mode (not 0644).
- **TLS private keys**: The Nginx cookbook generates self-signed private keys under `/etc/ssl/private` with mode 0640 and group `ssl-cert`. Preserve restrictive ownership, but use managed CA-issued certificates or a controlled certificate deployment process for non-development environments. Never commit private keys.
- **SSH hardening**: Root login and password authentication are disabled through `sed`. Reimplement with a validated SSH configuration fragment, preserve an out-of-band access path, and test before restarting SSH to avoid lockout.
- **Firewall and exposure**: UFW defaults to deny and allows SSH/HTTP/HTTPS; Fedora may use firewalld rather than UFW. Model the firewall by OS and confirm that the application on port 8000 and cache services remain inaccessible from untrusted networks.
- **Fail2ban and sysctl**: Review the actual templates for policy compatibility, use handlers and syntax validation, and test that fail2ban jails match the Fedora/Ubuntu log locations.
- **Application privilege**: The current systemd service runs Uvicorn as `root` and listens on all interfaces. Migrate to a dedicated account, bind internally where possible, and expose it through Nginx only if required.
- **Supply-chain controls**: The Git repository is pulled from `main` and pip dependencies are installed without a visible hash/pin policy. Pin source revisions and dependency versions, scan dependencies, and define trusted artifact/network access in CI.

### Technical Challenges

- **OS mismatch**: Fedora 42 is the Vagrant target, but bootstrap and resource assumptions are Ubuntu-oriented. Create OS-specific variables and handlers for package names, service names, users/groups, firewall implementation, SELinux, and Nginx layout; validate both supported families only if both are required.
- **Configuration drift in site roots**: `solo.json` specifies `/var/www/test.cluster.local` and similar paths, while cookbook defaults specify `/opt/server/test`, `/opt/server/ci`, and `/opt/server/status`. Resolve the intended source of truth before writing Ansible defaults.
- **TLS behavior is development-only**: Self-signed certificates are generated based on file existence and do not provide renewal or trust-chain management. Separate development certificates from production certificate issuance and renewal.
- **Imperative Chef workarounds**: Redis uses a Ruby block to delete generated directives, and SSH/UFW use shell commands. Reproduce the desired end state with declarative templates/modules and add convergence tests.
- **Database idempotency and application readiness**: The current PostgreSQL commands ignore failures and the service is started without migrations or health checks. Build explicit user/database ownership, password handling, schema/migration steps, and service verification.
- **External application uncertainty**: The actual FastAPI repository is outside this source tree. Confirm its startup contract, required environment variables, migrations, and production server expectations before finalizing the role.
- **Testing and access**: Rebuild the Vagrant workflow around Ansible, verify all three hostnames and forwarded ports, run Nginx configuration tests, check TLS, Redis/PostgreSQL connectivity, and validate SSH/firewall behavior in an isolated environment.

### Migration Order

1. **Repository and test harness foundation**: Define Ansible layout, pinned collections, inventory, Fedora variables, secrets policy, Molecule/Vagrant test workflow, and acceptance tests. Resolve the document-root and target-OS ambiguities first.
2. **nginx-multisite web and static content**: Migrate package/service, templates, sites, links, static files, and Nginx validation. This establishes the externally visible baseline and provides a place to route the application.
3. **Host security controls**: Migrate sysctl, SSH, firewall, fail2ban, and SELinux-compatible settings after establishing safe console/rollback access. Validate these independently before enabling them in production.
4. **cache**: Migrate Memcached and Redis with vaulted credentials and platform-aware service configuration. Test local-only binding and application connectivity.
5. **fastapi-tutorial and PostgreSQL**: Migrate OS packages, pinned application checkout, virtualenv, database provisioning, secret environment, systemd unit, and health checks. Run after database and cache interfaces are stable.
6. **Integration, hardening, and rollout**: Execute repeatable convergence tests, compare rendered Nginx/TLS/security behavior with the Chef VM, perform staged deployment, document rollback, and retire Chef only after acceptance sign-off.

### Assumptions

- The three directories containing `recipes/default.rb` are the complete set of local cookbooks requiring migration.
- The supplied Policyfile lock is the authoritative record of resolved external Chef versions, although the Berksfile and Policyfile declarations are not fully consistent for `ssl_certificate`.
- `solo.json` is intended to override cookbook defaults, but the conflicting site document roots must be resolved with the application owner.
- Fedora 42 is the intended development target because it is explicitly selected in `Vagrantfile`; production OS and version are not specified.
- No cloud deployment, inventory, DNS automation, load balancer, or external secret manager is represented in this repository.
- The external FastAPI Git repository and its dependency requirements are not part of this repository and need separate review.
- The static HTML files are sample content, not necessarily production application content.
- Self-signed TLS is acceptable only for local development; production certificate ownership and renewal are unspecified.
- The desired runtime topology is unclear: Nginx serves static sites, FastAPI listens on port 8000, but no Nginx proxy configuration was confirmed from the reviewed entrypoints.
- Redis and Memcached are both installed, but their consumers and required persistence/availability characteristics are not documented.
- The current hardcoded Redis and PostgreSQL credentials are test values, but they must nevertheless be rotated and excluded from the migrated repository.
- The Chef cookbook metadata advertises Ubuntu and CentOS support, but the implementation may not be portable to either family without changes; Ansible support should be explicitly scoped.
- The migration estimate assumes one small team and no major application refactoring; production compliance, certificate integration, HA databases, or multi-host orchestration would extend the schedule.
