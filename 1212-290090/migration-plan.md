# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks and several external cookbook dependencies. The intended workload combines an Nginx multi-site HTTPS front end, Redis and Memcached caching, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in implementation risk despite the small module count because the source contains hardcoded credentials, shell-based database provisioning, self-signed certificate generation, OS-specific firewall behavior, and a Vagrant test environment whose Fedora base image conflicts with the provisioning script's Debian/Ubuntu package commands. A focused team should expect approximately 2–4 weeks for an initial Ansible implementation and validation, or 4–6 weeks including security remediation, repeatable integration tests, operational documentation, and production cutover.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
    - Description: Installs and configures Memcached and Redis caching services, including a Redis listener on port 6379, a Redis log directory, authentication, service enablement, and a post-configuration workaround that removes selected replication settings.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: `memcached` cookbook inclusion, `redisio` cookbook inclusion, Redis password configuration, `/var/log/redis` ownership, and an imperative Redis configuration rewrite.

- **fastapi-tutorial**:
    - Description: Provisions a FastAPI tutorial application from the `dibanez/fastapi_tutorial` Git repository, installs Python and PostgreSQL packages, creates a Python virtual environment, installs application requirements, creates a PostgreSQL database/user, and runs the application with systemd and Uvicorn.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Python 3 virtual environment, Git-based application deployment, PostgreSQL service, `fastapi` database and user, `.env` file, and a root-run systemd service listening on `0.0.0.0:8000`.

- **nginx-multisite**:
    - Description: Configures Nginx as an HTTPS multi-site server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, deploys static site content, applies host security controls, and creates development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Nginx package/service management, per-site server blocks and symlinks, SSL certificate/key directories, Fail2ban, UFW rules, SSH hardening, sysctl security settings, static HTML content, and delayed reload/restart notifications.

**CRITICAL PATH VERIFICATION:**
Only the three local cookbook paths listed above were present in the repository tree and confirmed by their Chef metadata and recipes. External cookbooks are dependencies, not local modules, and are intentionally listed in the dependency section rather than the module inventory.

### Infrastructure Files

- `Berksfile`: Declares the Supermarket source, three local cookbooks, and external `nginx`, `memcached`, and `redisio` dependencies. The `ssl_certificate` dependency is commented out here and should not be assumed to be actively consumed by the source recipes.
- `Policyfile.rb`: Defines the policy name and run list, and declares the same local and external cookbooks, including `ssl_certificate` as an active policy dependency.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions, including Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. It also records the cache cookbook's dependency graph.
- `solo.rb`: Chef Solo configuration for cookbook paths, cache location, logging, and stdout output. Its cookbook path behavior must be replaced by Ansible project/inventory conventions.
- `solo.json`: Chef Solo run list and runtime attributes for sites, SSL paths, firewall settings, and SSH hardening. These values are the principal source for Ansible inventory/group variables.
- `Vagrantfile`: Defines a libvirt VM using `generic/fedora42`, hostname `chef-nginx`, private address `192.168.121.10`, forwarded ports 8080/8443, 2 GB RAM, and 2 CPUs. It rsyncs the repository and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs dependencies with `apt-get`, installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. It is not compatible with Fedora without adaptation and should be replaced by an Ansible provisioner or `ansible_local`/external Ansible workflow.
- `project-plan.md`: Describes the X2Ansible analysis/migration tool workflow and expected planning artifacts; it is coordination/documentation input rather than deployable infrastructure.
- `cookbooks/nginx-multisite/templates/`: Contains Nginx, security, site, Fail2ban, and sysctl configuration templates that must be converted to Ansible Jinja2 templates.
- `cookbooks/nginx-multisite/files/default/`: Contains static `index.html` content for the test, CI, and status sites and should become role-managed files.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The actual Vagrant box is Fedora 42, while `vagrant-provision.sh` uses `apt-get`, indicating an unresolved platform mismatch. The Ansible target OS must be selected explicitly; do not assume Fedora compatibility without testing. If no production target is specified, standardize initially on a supported RHEL-family target such as RHEL 9-compatible Linux, while retaining Debian-family variable mappings if Ubuntu remains required.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly configured. The migration test harness should preserve libvirt networking and port forwarding or document an equivalent CI environment.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP integration is present.

## Migration Approach

Create an Ansible project with separate roles for `nginx_multisite`, `cache`, and `fastapi_tutorial`, plus shared inventory/group variables and an environment-specific playbook. Use handlers for Nginx, Fail2ban, SSH, sysctl, PostgreSQL, and application service changes. Convert Chef attributes into typed variables, preserve idempotency with Ansible modules, and validate rendered configuration before service reloads. Keep static site assets in role `files/`, configuration in role `templates/`, and secrets outside Git using Ansible Vault or an enterprise secret manager.

### Key Dependencies to Address

- **nginx 12.3.1**: Replace the external Chef cookbook with Ansible package/service tasks and an explicit Nginx role. Reproduce the repository's Nginx configuration and validate syntax with `nginx -t` before reload.
- **memcached 6.1.0**: Replace with distribution package installation, service management, and explicit listener/resource-limit configuration as required by the application.
- **redisio 7.2.4**: Replace with an Ansible Redis role or carefully maintained tasks/templates. Preserve port, authentication, ownership, and service behavior, but remove the brittle post-install text-edit workaround after determining the intended Redis configuration.
- **selinux 6.2.4**: Determine whether SELinux is enforcing on the selected target. Use Ansible SELinux modules, package/file contexts, and policy adjustments rather than treating the Chef dependency as an opaque install dependency.
- **ssl_certificate 2.1.0**: The Policyfile locks it, but reviewed local recipes generate self-signed certificates directly and do not call this cookbook. Decide whether development self-signed certificates or a real CA/ACME integration is required; do not carry the dependency forward without a confirmed use case.
- **PostgreSQL and Python packages**: The FastAPI cookbook installs distribution packages directly and has no separate Chef PostgreSQL cookbook. Map package names by OS, manage PostgreSQL readiness explicitly, and use Ansible PostgreSQL modules with a suitable Python PostgreSQL driver.
- **GitHub application repository**: Pin the application to a reviewed commit or release rather than tracking `main`; verify repository availability, requirements, and deployment ownership during migration.

### Security Considerations

- **Hardcoded Redis credential**: `redis_secure_password_123` is embedded in the cache recipe. Rotate it, place the replacement in Ansible Vault or a secret manager, and avoid exposing it in task output or generated configuration.
- **Hardcoded PostgreSQL credentials**: The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes the same credential into a world-readable `.env` file (`0644`). Treat the values as compromised, rotate them, restrict file permissions, and use Vault-backed variables.
- **Database provisioning safety**: Shell commands use `sudo -u postgres`, append `|| true`, and are not safely idempotent or auditable. Replace with PostgreSQL modules, explicit state checks, and controlled password handling.
- **TLS certificates and private keys**: Development certificates are generated as self-signed RSA 2048 certificates for 365 days. Preserve restrictive key ownership/mode, but define production certificate issuance, renewal, trust, SANs, and rotation. Never commit production private keys.
- **Nginx exposure**: Sites are configured for HTTPS and static content, but the source does not demonstrate a complete production TLS policy, HSTS strategy, or certificate validation. Review the templates and test TLS settings before declaring equivalence.
- **Firewall and SSH hardening**: UFW is configured to deny by default and allow SSH/HTTP/HTTPS; root login and password authentication are disabled by default. Make SSH access prerequisites, administrative source networks, and rollback access explicit before enabling these settings remotely. UFW behavior must be mapped to firewalld/nftables if the target is Fedora/RHEL.
- **Fail2ban and sysctl**: Preserve the Fail2ban jail and sysctl intent, but validate jails, log paths, kernel parameters, and service names for the target OS. Apply changes through validated templates and handlers.
- **Application privilege**: The systemd service runs FastAPI as `root`. Create a dedicated non-privileged service account, define writable paths, and review bind capability and file ownership.
- **Network exposure**: Uvicorn binds to all interfaces on port 8000. Prefer binding behind Nginx on localhost or a restricted application network unless direct exposure is intentional.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is the declared VM image, but provisioning uses `apt-get` and cookbook metadata targets Ubuntu/CentOS. Choose and test a canonical OS, then implement package/service/firewall abstractions and update the Vagrant workflow.
- **Chef resource semantics to Ansible idempotency**: `execute`, `ruby_block`, shell-based UFW checks, symlinks, and delayed notifications do not translate one-for-one. Replace them with declarative modules, handlers, validation commands, and explicit `changed_when`/`failed_when` only where unavoidable.
- **Nginx template behavior**: The primary recipes depend on unreviewed templates and attributes, including site paths that differ between `default.rb` and `solo.json`. Reconcile the effective configuration and test every hostname, certificate path, asset path, and reload order.
- **Redis workaround**: The recipe edits generated Redis configuration by regex after the external cookbook runs. Identify why those directives are removed, then encode the desired settings in the Ansible template rather than preserving an opaque mutation.
- **Certificate lifecycle**: Self-signed generation is acceptable for a development VM but is not a production certificate strategy. Define ACME/PKI ownership, renewal, deployment, and rollback before migration completion.
- **External application drift**: Pulling `main` and running an unpinned requirements file can make validation non-repeatable. Pin source and Python dependencies and establish an artifact/release process.
- **Integration ordering**: Nginx sites, PostgreSQL, Redis/Memcached, and the FastAPI service have cross-service assumptions. Use role dependencies or a single ordered play with readiness checks, then validate end-to-end requests.
- **Testing gap**: The repository has a Vagrant scenario but no visible automated convergence, lint, or service-level tests. Add Molecule or equivalent tests for package state, rendered configs, ports, TLS, firewall, database connectivity, and application health.

### Migration Order

1. **Foundation and target platform**: Select the OS, repair the Vagrant/Ansible test path, define inventory, privilege escalation, package mappings, and secret storage.
2. **cache**: Migrate Memcached and Redis service installation and baseline configuration, with credential rotation and connectivity tests. This is relatively isolated but contains the highest immediate secret concern.
3. **fastapi-tutorial**: Migrate packages, pinned application checkout, virtual environment, PostgreSQL database/user, secure environment file, and a dedicated systemd service. Validate database readiness and application health.
4. **nginx-multisite security baseline**: Migrate Fail2ban, firewall, SSH, sysctl, and certificate directory controls with a tested rollback path.
5. **nginx-multisite web serving**: Migrate Nginx, templates, site directories, static assets, certificates, and handlers. Validate all three sites and proxy/application integration if later required.
6. **End-to-end cutover**: Run parallel validation against Chef and Ansible-managed test hosts, compare package/service/filesystem/network behavior, then retire Chef only after operational acceptance.

### Assumptions

- The three directories containing `metadata.rb` and `recipes/default.rb` are the complete local cookbook inventory.
- The Policyfile lock is authoritative for resolved external cookbook versions, although `Berksfile` and `Policyfile.rb` differ regarding `ssl_certificate`.
- No production inventory, cloud account, DNS authority, certificate authority, or secret manager configuration is present in the reviewed repository.
- `solo.json` may override cookbook defaults; the differing document roots must be resolved rather than assumed equivalent.
- The requested target environment is not specified; OS selection, firewall implementation, PostgreSQL version, Redis version, and service naming require stakeholder confirmation.
- The Vagrant Fedora box may be a stale or erroneous choice because the shell provisioner uses Debian package commands.
- The reviewed recipes are representative entry points; template contents and the custom `resources/lineinfile.rb` were not audited line by line and require focused follow-up during implementation.
- The FastAPI GitHub repository and its runtime requirements are external to this repository and must be reviewed and pinned.
- Existing self-signed certificates are development artifacts, not production credentials or a production TLS solution.
- A two-person infrastructure/application team can perform the initial conversion in 2–4 weeks; security remediation, OS reconciliation, test automation, and production rollout may extend the effort to 4–6 weeks.
- Teams should assign an owner for each role, a security reviewer for secrets/TLS/SSH/firewall changes, and an application owner for PostgreSQL and FastAPI behavior. Coordinate through a shared variable contract, change review, and a migration checklist with explicit test evidence before cutover.
