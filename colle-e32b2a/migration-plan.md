# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks and four externally resolved cookbooks. The effective configuration provisions an Nginx multi-site host, Redis and Memcached, and a FastAPI tutorial application backed by PostgreSQL, with host hardening and development TLS. The migration is moderate in risk despite the small module count because it contains plaintext credentials, shell-based configuration edits, generated certificates, an application pulled from a mutable Git branch, and a significant operating-system mismatch between the Vagrant image and the provisioning script. A focused implementation can be completed in approximately 1–2 weeks, including testing and reconciliation of intended runtime behavior; production hardening and secret-management integration should be planned as a separate workstream.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and configures Nginx for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), serves static fixture pages, and applies host and web-server security settings.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx package and service management, per-site document roots and enabled-site links, templated Nginx and security configuration, Fail2ban, UFW default-deny firewall rules, SSH hardening, sysctl settings, and self-signed RSA certificates for development.

- **cache**:
    - Description: Configures Memcached and a single Redis instance listening on port 6379, including Redis logging, startup enablement, and a custom post-configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: `memcached` integration, `redisio` integration, Redis authentication, `/var/log/redis` ownership and permissions, and a Ruby block that removes selected replication-related directives from `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
    - Description: Installs a Python FastAPI tutorial application from GitHub, creates a virtual environment, installs its requirements, provisions PostgreSQL, creates the application database and user, and runs the application through systemd on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python and PostgreSQL packages, Git checkout of `dibanez/fastapi_tutorial` at `main`, virtualenv and pip installation, database initialization, `.env` generation, and a root-owned Uvicorn service.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree and their primary entrypoints were reviewed. External cookbooks are dependencies, not local modules, and are therefore not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Declares the Supermarket source, three local cookbooks, and external `nginx`, `memcached`, and `redisio` dependencies. It also contains a commented `ssl_certificate` declaration; reconcile this with the active Policyfile before migration.
- `Policyfile.rb`: Defines the Chef policy name, effective run list, local cookbook paths, and pinned/constraint-based external cookbook requirements.
- `Policyfile.lock.json`: Records resolved versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0, plus local cookbook revisions. Use this as historical evidence, not as an Ansible dependency mechanism.
- `Vagrantfile`: Defines the development VM (`generic/fedora42`) on libvirt with 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, forwarded ports 8080/8443, and an rsync-mounted repository.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. It uses `apt-get`, which conflicts with the Fedora Vagrant box and must be replaced by Ansible-compatible bootstrap logic.
- `solo.rb`: Chef Solo cache, cookbook search paths, and logging configuration; these have no direct target equivalent beyond Ansible project/inventory conventions.
- `solo.json`: Chef run list and overriding site/security values. Convert these values to inventory/group variables or role defaults, with secrets removed from version control.
- `project-plan.md`: Documents the X2Ansible tool and its staged analysis/migration/validation workflow; retain its coordination concepts, but the generated Ansible repository should be independently testable.
- `cookbooks/nginx-multisite/templates/` and `files/`: Source material for Nginx, security, Fail2ban, sysctl, virtual-host configuration, and static HTML. These should become role templates/files.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the tree; inspect its behavior during detailed implementation even though it is not invoked by the reviewed default recipe.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The declared Vagrant box is Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu `apt-get` and the recipes use Debian-style paths/users such as `www-data`, `/etc/nginx/sites-available`, UFW, and PostgreSQL service naming. The target OS is therefore unresolved. Select and test one supported target explicitly; do not assume Fedora compatibility. If no decision is available, use Red Hat Enterprise Linux 9 as the migration planning baseline and adapt firewall, package, web-root, and service conventions accordingly.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 vCPUs and 2 GB memory. The Ansible replacement should preserve Vagrant/libvirt acceptance testing or define an equivalent CI test VM.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP integration is present.

## Migration Approach

Create an Ansible project with a top-level site playbook and separate roles for `nginx_multisite`, `cache`, `fastapi_tutorial`, and optionally `host_security`. Keep application, web, and cache variables in inventory/group variables. Use handlers for service reloads/restarts, `ansible.builtin.package` for OS abstraction, `template`/`copy` for configuration and static content, `community.general.ufw` or the selected platform firewall equivalent, `ansible.posix.sysctl`, `ansible.builtin.systemd`, and `community.postgresql` modules for database/user creation. Replace Chef shell blocks with idempotent modules wherever possible.

### Key Dependencies to Address

- **nginx cookbook 12.3.1**: Replace with an explicit Nginx role using Ansible package, template, file/link, and service tasks. Preserve the three virtual hosts, document roots, static pages, and reload handlers.
- **memcached cookbook 6.1.0**: Replace with distribution packages and a cache role; define listen address, service state, and firewall exposure explicitly rather than inheriting cookbook defaults.
- **redisio cookbook 7.2.4**: Replace with the target OS Redis package/repository and an Ansible-managed Redis configuration. Preserve port 6379 and authentication, but redesign the replication-directive workaround as a supported configuration rather than post-editing generated files.
- **selinux cookbook 6.2.4**: The lockfile shows it as a transitive Redis dependency. Determine whether SELinux is enforcing on the selected OS and implement required contexts/booleans with `ansible.posix`/appropriate SELinux modules; do not silently disable it.
- **ssl_certificate 2.1.0**: It is locked but not in the effective Policyfile run list reviewed. Confirm whether it was intended for use. The current local SSL recipe generates self-signed certificates with OpenSSL; for production replace this with an approved certificate source or ACME workflow.
- **PostgreSQL and Python runtime**: The FastAPI cookbook directly installs distribution PostgreSQL, Python, pip, venv, Git, and `libpq-dev`. Pin the application revision and Python dependency set, and decide whether PostgreSQL remains local or becomes an externally managed service.
- **GitHub application source**: Replace checkout of mutable `main` with a tag or commit, and add availability/checksum and rollback strategy.

### Security Considerations

- **Plaintext Redis credential**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Move it to Ansible Vault or an enterprise secret manager, rotate it, and avoid exposing it in task output.
- **Plaintext PostgreSQL credentials**: The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes the same value to a world-readable `.env` file (`0644`). Treat the credential as compromised, rotate it, use Vault/secret-manager lookup, set restrictive ownership/mode, and avoid command-line password leakage.
- **TLS private keys and certificates**: The SSL role generates self-signed keys under `/etc/ssl/private` with group `ssl-cert` and mode 0640. Preserve restrictive permissions and ownership, but establish certificate lifecycle, SAN coverage, renewal, backup, and trust requirements. Self-signed certificates are suitable only for the stated development scenario.
- **SSH hardening**: The source disables root login and password authentication. Implement this with managed `sshd_config` fragments and validation before restarting SSH; ensure a tested administrative key path exists to prevent lockout.
- **Firewall exposure**: UFW denies by default and allows SSH, HTTP, and HTTPS. Reproduce this with the selected OS firewall, verify remote access and ordering, and decide whether application port 8000, Redis, or Memcached must remain loopback-only (they should not be broadly exposed).
- **Fail2ban and sysctl**: Preserve the Fail2ban jail and sysctl intent from the reviewed templates, validate syntax, and document platform-specific differences.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Migrate to a dedicated unprivileged service account, with explicit writable directories and least-privilege permissions.
- **Credential patterns by module**: `cache` contains a Redis password; `fastapi-tutorial` contains database credentials in both SQL commands and `.env`; `nginx-multisite` handles private TLS keys but no external secret store is visible. No Chef encrypted data bags or Chef Vault usage were found in the reviewed files.

### Technical Challenges

- **OS/platform inconsistency**: Fedora 42 is provisioned with `apt-get`, while cookbook support and paths imply multiple Linux families. Resolve the target OS first and test package names, service names, firewall tooling, Nginx layout, PostgreSQL initialization, and user/group names.
- **Chef attribute precedence versus Ansible variables**: `attributes/default.rb` defines defaults while `solo.json` overrides document roots and security values. Build a precedence map and write automated assertions for the effective three-site configuration.
- **Idempotence and shell workarounds**: Redis uses a Ruby file rewrite and the application uses `|| true` database commands. Replace these with declarative Redis/PostgreSQL modules and explicit existence checks/migrations.
- **Database/application readiness**: The current recipe starts PostgreSQL but does not clearly initialize schema, wait for readiness, or manage application migrations. Add service readiness checks, database privileges, migrations, health checks, and controlled restart handlers.
- **Template behavior and static content**: Nginx templates and fixture files must be ported without losing variable substitutions, certificate paths, security headers, or symlink semantics. Validate with `nginx -t` before reload.
- **Mutable external dependencies**: The GitHub `main` branch and unconstrained `redisio` dependency in metadata reduce reproducibility. Pin source revisions and document package/repository versions.
- **Development versus production intent**: Cluster-local names, self-signed certificates, forwarded Vagrant ports, and tutorial application code indicate a demo/test environment. Define whether production requirements are in scope before preserving these defaults.

### Migration Order

1. **Target platform and test harness**: Decide OS, firewall, package repositories, service naming, and whether Vagrant/libvirt remains the acceptance environment. Establish Ansible linting, Molecule or equivalent VM tests, and secret injection.
2. **Host security baseline**: Implement SSH hardening, firewall, sysctl, Fail2ban, base packages, and service-account conventions. Validate administrative access before enabling enforcement.
3. **cache**: Migrate Memcached and Redis with vaulted credentials and controlled local-network exposure. Validate persistence, authentication, service startup, and the intent of the Redis workaround.
4. **fastapi-tutorial**: Provision pinned application code, Python environment, PostgreSQL/database credentials, migrations, and an unprivileged systemd service. Add health and rollback checks.
5. **nginx-multisite**: Port templates, static files, virtual hosts, certificate handling, and service handlers; integrate backend routing only if required by the actual template. Validate all three hostnames and TLS.
6. **End-to-end cutover and decommissioning**: Compare package/service/file/firewall/database outcomes against a Chef-provisioned reference, run security checks, then remove Chef/Berkshelf bootstrap paths after rollback artifacts are available.

Estimated effort: 1–2 engineer-weeks for a tested development migration, or 3–5 engineer-weeks when production-grade secret management, certificate automation, OS portability, database migration, and CI acceptance testing are included.

### Assumptions

- The three local cookbooks are the complete migration scope; external cookbook internals are not present in the repository and will be replaced rather than translated line by line.
- The effective Chef run list is the three recipes in `Policyfile.rb`/`Policyfile.lock.json`; the differing shorthand in `solo.json` is treated as equivalent but should be verified.
- `solo.json` values are intended runtime overrides, although the reviewed Nginx recipe defaults use different document roots; the migration must choose one authoritative configuration.
- The selected OS is currently ambiguous. Fedora 42 is declared by Vagrant, but the bootstrap script is Debian-oriented and cookbook metadata supports Ubuntu/CentOS.
- The environment is primarily development/test because it uses `.cluster.local` names, Vagrant port forwarding, fixture HTML, and self-signed certificates.
- PostgreSQL is intended to run on the same host as FastAPI; this must be confirmed before designing inventory groups.
- Redis and Memcached should be private services unless an explicit external-consumer requirement is identified.
- The locked `ssl_certificate` cookbook is historical or transitive because it is not in the effective run list; confirm before implementing certificate automation.
- The contents of the Nginx, security, site, and Fail2ban templates were not exhaustively audited here; detailed migration work must validate their directives and any hidden assumptions.
- The custom `lineinfile` resource exists but was not shown as called by the reviewed entrypoints; confirm whether another recipe invokes it.
- No encrypted Chef data bags, Chef Vault records, CI deployment credentials, cloud integrations, or external inventory were found in the reviewed files.
- DNS/hosts management for the three virtual hosts is not enabled in the Vagrantfile and must be supplied by the test harness or environment.
- The Ansible implementation will preserve intended behavior, not insecure literal secrets or root-running application behavior, unless an approved exception is documented.
- Teams should coordinate through a dependency/ownership matrix: platform engineers own OS and security baseline, application engineers own FastAPI/PostgreSQL lifecycle, web engineers own Nginx/TLS, and security/platform reviewers approve secrets, firewall, SSH, and certificate changes. Each role should have an owner, acceptance tests, rollback steps, and a documented Chef-to-Ansible behavior comparison.
