# MIGRATION FROM CHEF TO ANSIBLE

The repository is a small Chef Solo/Policyfile deployment with three local cookbooks: an Nginx multi-site/security stack, caching services, and a FastAPI tutorial application. The migration is moderate in risk despite the small module count because it includes public-facing TLS and firewall configuration, database credentials embedded in recipes, a source-controlled application checkout, and several imperative Chef shell/Ruby workarounds. A focused implementation should take approximately 2–4 engineer-weeks, including role development, secrets remediation, functional testing, and parallel validation in the Vagrant environment. A production-ready migration should allow an additional 1–2 weeks if certificate issuance, application ownership, or target OS decisions are unresolved.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules confirmed from the repository tree and Chef Policyfile are listed below. External cookbooks are treated as dependencies, not local modules.

- **nginx-multisite**:
    - Description: Installs and manages Nginx as a multi-site web server for three SSL-enabled virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It also configures host security controls, site roots, static content, self-signed development certificates, and Nginx service lifecycle.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx configuration templates, three virtual hosts, static `index.html` content, Fail2ban, UFW default-deny rules, SSH hardening, sysctl settings, self-signed RSA certificates, and delayed service reloads
    - Ansible target: A role split into `nginx`, `nginx_security`, and optionally `tls`, or a single role with clearly separated task files and handlers. Use `ansible.builtin.template`, `package`, `service`, `file`, `copy`, `community.general.ufw`, `ansible.posix.sysctl`, and `ansible.posix.authorized_key`/SSH configuration mechanisms as appropriate.

- **cache**:
    - Description: Installs Memcached and Redis, creates the Redis log directory, configures a Redis instance on port 6379 with authentication, applies a post-install configuration cleanup, and enables Redis.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, Redisio dependency, Redis password configuration, service enablement, and an imperative Ruby-based Redis configuration patch
    - Ansible target: A `cache` role using distribution packages or a vetted Redis role, explicit Redis configuration templates, service handlers, and Ansible Vault for the Redis password. The Redis replication-related cleanup should be replaced by a supported configuration model rather than copied as a text mutation.

- **fastapi-tutorial**:
    - Description: Installs Python, PostgreSQL, build/database packages, and Git; checks out the FastAPI tutorial application; creates a virtual environment; installs Python requirements; creates a PostgreSQL database/user; writes an application `.env`; and runs Uvicorn through a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout from `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python virtualenv, PostgreSQL service, database bootstrap, systemd unit, Uvicorn bound to `0.0.0.0:8000`, and application environment configuration
    - Ansible target: A role using package installation, `ansible.builtin.git`, `ansible.builtin.pip` or virtualenv-aware commands, `community.postgresql.postgresql_db`/`postgresql_user`, templated systemd unit, and handlers for daemon reload and service restart. Pin the application revision and Python dependencies before production migration.

### Infrastructure Files

- `Berksfile`: Chef Supermarket and local cookbook dependency source. It declares local cookbooks plus `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; the commented `ssl_certificate` line differs from the active Policyfile dependency. Replace this dependency resolution with `ansible-galaxy requirements.yml` only for reusable Ansible collections/roles; most functionality should use core modules and maintained collections.
- `Policyfile.rb`: Defines the policy name, run list, local cookbook paths, and external cookbook constraints. It additionally declares `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. Preserve this as migration evidence, but independently validate equivalent Ansible behavior and package versions.
- `Vagrantfile`: Defines the test VM (`generic/fedora42`), hostname `chef-nginx`, private IP `192.168.121.10`, forwarded ports 8080/8443, 2 GB RAM, 2 CPUs, libvirt provider, and rsync of the repository to `/chef-repo`. Convert or supplement it with an Ansible provisioner and retain it as an integration test harness.
- `vagrant-provision.sh`: Installs packages and Chef dynamically, runs Berkshelf, vendors cookbooks, and invokes Chef Solo. It uses `apt-get`, which conflicts with the Fedora 42 Vagrant box; this script must be replaced by Ansible provisioning and the OS mismatch resolved.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Its operational concerns map to Ansible inventory, `ansible.cfg`, role paths, and controller logging.
- `solo.json`: Chef run list, three site definitions, TLS paths, and security flags. Migrate these values into inventory/group variables and role defaults/vars, with secrets removed from plaintext.
- `project-plan.md`: Describes the X2Ansible tool and expected analysis/migration workflow. Use it as process context, not as a runtime dependency of the infrastructure deployment.
- `x2a-rules/403375bd-a1b3-4f96-ac46-9086acb161ed.md`: Repository-specific migration/tooling rule documentation. Review it alongside the generated Ansible design before implementation.

### Target Details

- **Operating System**: The Vagrant target is explicitly Fedora 42 (`generic/fedora42`), but the Chef metadata claims support for Ubuntu >=18.04 and CentOS >=7. The provisioning script uses Debian/Ubuntu `apt-get`, while the cookbooks use package/service names that may vary by distribution. Select and document a supported target, preferably Fedora/RHEL-family if Fedora remains authoritative, then implement package and service variables. Do not assume Ubuntu compatibility without testing.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync-based source synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration is present.

## Migration Approach

### Key Dependencies to Address

- **Nginx 12.3.1 Chef cookbook**: Replace with native Ansible package, template, file, and service tasks. Reproduce only the required virtual-host behavior; do not carry over Chef cookbook internals.
- **Memcached 6.1.0**: Install and configure using the target OS package/service model. Confirm whether Memcached needs a bind address, firewall rule, or authentication in the target environment; the reviewed local recipe only includes the cookbook.
- **Redisio 7.2.4 and SELinux 6.2.4**: Replace with a supported Redis installation/configuration approach and explicit SELinux policy tasks where required. Validate Redis version, config syntax, service name, and SELinux labels on Fedora/RHEL.
- **ssl_certificate 2.1.0**: The lock contains it, but the Berksfile comments it out and the reviewed local recipe generates certificates directly with OpenSSL. Determine whether the locked cookbook is actually needed. In Ansible, use managed certificate files or an ACME/PKI workflow; retain self-signed certificates only for development.
- **PostgreSQL and Python system packages**: Use target-OS package modules and the `community.postgresql` collection. Ensure the PostgreSQL server, client libraries, Python headers, and virtualenv tooling are available.
- **FastAPI Git repository and Python requirements**: Pin a reviewed Git commit/tag rather than `main`, verify dependency hashes where feasible, and decide whether application deployment belongs in this infrastructure role or a separate application pipeline.
- **Systemd/Uvicorn**: Template a unit with least-privilege service user, explicit environment file, restart policy, and dependency ordering. Add health checks and handler-driven restarts.
- **Chef imperative behavior**: Replace shell `sed`, `ufw`, `openssl`, PostgreSQL SQL strings, and the Redis Ruby block with idempotent Ansible modules and validated templates.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and template Redis configuration with restrictive permissions.
- **Hardcoded PostgreSQL credential**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes it into `/opt/fastapi-tutorial/.env` and the database URL. Treat the credential as compromised, rotate it, store it in Vault, and set the environment file to mode 0600 owned by the service account.
- **Application privilege**: The current systemd service runs Uvicorn as `root`. Create a dedicated non-root application user, constrain filesystem access, and bind through Nginx or a controlled socket/port where appropriate.
- **TLS certificates and private keys**: The SSL recipe creates self-signed 2048-bit RSA certificates valid for 365 days under `/etc/ssl/certs` and keys under `/etc/ssl/private`. Protect private keys, verify ownership/group access, and replace development certificates with managed production certificates and renewal automation. Ensure the Nginx templates do not expose private key content.
- **Firewall exposure**: UFW allows SSH, HTTP, and HTTPS and defaults to deny. Reproduce the policy with an OS-appropriate firewall solution; Fedora/RHEL commonly uses firewalld rather than UFW. Confirm whether port 8000, Redis, Memcached, and PostgreSQL must remain loopback-only.
- **SSH hardening**: Root login and password authentication are disabled by text mutation. Use a validated SSH configuration template/drop-in, preserve out-of-band access, and test before applying to remote hosts.
- **Fail2ban and sysctl**: Port the Fail2ban jail and sysctl template after reviewing their actual contents. Validate distribution paths and avoid applying unsafe kernel settings without platform testing.
- **Supply-chain controls**: The application is cloned from an external GitHub repository at a mutable `main` branch and pip installs requirements at converge time. Pin revisions, review dependencies, and consider an internal artifact registry.
- **Secrets management scope**: No Chef encrypted data bags or Chef Vault usage were found in the reviewed files. Visible credential patterns are the Redis password, PostgreSQL password, database URL, and TLS private-key locations. Search the full repository and deployment environment before declaring secrets inventory complete.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is the declared VM, but provisioning uses `apt-get` and cookbook support lists Ubuntu/CentOS. Establish the target OS first and create a compatibility matrix for package names, services, firewall, SELinux, and PostgreSQL.
- **Imperative and non-idempotent commands**: The Chef code uses shell SQL with `|| true`, `sed` mutations, raw OpenSSL commands, and a Ruby text-rewrite hack. Replace each with modules/templates and explicit change handlers; test repeated runs for zero changes.
- **Nginx/TLS behavior**: Preserve three site definitions, document roots, symlinks, security include files, certificate paths, and reload ordering. Use `nginx -t` before reload and add certificate/SAN validation.
- **Redis configuration workaround**: The recipe removes several replication directives after Redisio generates configuration. Determine the root cause and target Redis version; do not blindly reproduce the deletion because it may alter replication or data-safety semantics.
- **Application lifecycle**: The current recipe has no migration command, health check, deployment rollback, or explicit service account. Define ownership between infrastructure and application teams before converting it.
- **Unreviewed templates/content**: Nginx, Fail2ban, sysctl, and site templates determine important runtime/security behavior but were not fully inspected for this high-level survey. Treat their exact directives as a validation gate.
- **Environment drift and test reachability**: The shell output references `192.168.56.10`, while Vagrant config uses `192.168.121.10`. Correct documentation and test URLs during migration.

### Migration Order

1. **Foundation and inventory**: Resolve Fedora versus Ubuntu/RHEL target, define Ansible inventory, collections, Vault strategy, and Vagrant/CI test workflow.
2. **cache**: Migrate Memcached/Redis with secrets and service validation. This is relatively isolated but requires careful Redis and SELinux testing.
3. **fastapi-tutorial**: Migrate packages, PostgreSQL objects, application checkout, virtualenv, environment secrets, and systemd service. Coordinate with the application owner and pin the application revision.
4. **nginx-multisite security baseline**: Port firewall, SSH, sysctl, Fail2ban, and ownership controls in a staged manner to avoid lockout.
5. **nginx-multisite sites and TLS**: Port Nginx configuration, static content, virtual hosts, certificate management, and validation handlers. Integrate upstream/application connectivity after the FastAPI service is healthy.
6. **Cutover and decommissioning**: Run Chef and Ansible in parallel where safe, compare package/service/configuration outcomes, perform repeatability tests, then remove Chef/ Berkshelf provisioning and rotate all migrated credentials.

### Assumptions

- The three directories under `cookbooks/` are the complete local cookbook inventory; external cookbooks are not being independently migrated.
- The Policyfile lock is the authoritative record of resolved external Chef versions, although Berksfile and Policyfile declarations differ for `ssl_certificate`.
- The three sites are intended for development/test use because certificates are self-signed and static sample files are present; production DNS, certificate authority, and content ownership are not specified.
- `solo.json` overrides the cookbook defaults for document roots, so the Ansible design must decide whether `/var/www/...` or `/opt/server/...` is authoritative.
- PostgreSQL is local to the application host and the application database/user should be retained, but database schema migration requirements are unknown.
- The target will use systemd, as indicated by the current service unit, but firewall and package implementation must be selected for the final OS.
- No cloud platform, production inventory, DNS management, load balancer, monitoring, backup, or CI/CD integration is defined.
- The reviewed metadata does not reveal all template directives or runtime dependencies; full template inspection and acceptance testing are required before declaring behavioral parity.
- The exact desired Redis topology is unclear; the current recipe configures one server and removes replication-related lines, so this requires owner confirmation.
- The application repository, its license, requirements, and production deployment model are external to this repository and must be reviewed separately.
- Secrets shown in source are examples or development credentials, but they must still be considered exposed and rotated.
- Migration estimates assume one engineer familiar with Chef and Ansible plus application/security review support; parallel team execution can reduce elapsed time but not validation effort.
