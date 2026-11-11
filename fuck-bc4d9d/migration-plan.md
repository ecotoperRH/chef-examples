# MIGRATION FROM CHEF TO ANSIBLE

The repository is a small Chef Solo/Berkshelf infrastructure repository with three local cookbooks and a policy that resolves several external cookbooks. The target migration is moderate in operational risk despite the limited module count: the Nginx cookbook combines web serving, multiple sites, firewalling, SSH hardening, Fail2ban, sysctl tuning, and development TLS; the cache cookbook contains an exposed hardcoded Redis password and a post-install configuration hack; and the FastAPI cookbook installs an application, PostgreSQL, a database user, and a systemd service. A pilot implementation and validation on a disposable VM should take approximately 1–2 weeks, with production hardening, secrets remediation, testing, and team review taking approximately 2–4 additional weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server configuration for three configurable sites, with static content, virtual hosts, development SSL certificates, host firewall rules, Fail2ban, sysctl security settings, and SSH hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: `nginx-multisite::default` composes `security`, `nginx`, `ssl`, and `sites`; Nginx service management; per-site document roots and enabled-site symlinks; UFW default-deny policy; Fail2ban; optional disabling of root SSH login and password authentication; self-signed RSA certificates for configured sites.

- **cache**:
    - Description: Local cache-service cookbook that installs and enables Memcached and Redis, creates Redis logging storage, configures a Redis listener on port 6379, and applies a compatibility cleanup to generated Redis configuration.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached inclusion; Redisio integration; Redis authentication; `/var/log/redis` ownership and permissions; `redisio::enable`; Ruby-based removal of selected replication and buffer directives.

- **fastapi-tutorial**:
    - Description: FastAPI tutorial application deployment that installs Python and PostgreSQL packages, checks out an application from GitHub, builds a virtual environment, installs requirements, creates a PostgreSQL database and user, writes an environment file, and runs Uvicorn under systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Python 3 virtualenv; Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`; PostgreSQL service; `fastapi_db` and `fastapi` database principal; systemd service listening on `0.0.0.0:8000`.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree. The three local cookbook entrypoints were reviewed: `cookbooks/nginx-multisite/recipes/default.rb`, `cookbooks/cache/recipes/default.rb`, and `cookbooks/fastapi-tutorial/recipes/default.rb`.

### Infrastructure Files

- `Berksfile`: Defines the Supermarket source, three local cookbooks, and external cookbook constraints for Nginx, Memcached, Redisio, and a commented SSL certificate cookbook. Replace dependency resolution with Ansible Galaxy collections/roles and pinned collection versions.
- `Policyfile.rb`: Defines the active Chef policy and run list: `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`, plus dependency constraints.
- `Policyfile.lock.json`: Records resolved versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and SSL Certificate 2.1.0, as well as local cookbook revisions. Preserve this as migration evidence, not as an Ansible runtime dependency.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Replace with an Ansible inventory, `ansible.cfg`, playbooks, and role layout.
- `solo.json`: Active node attributes, three site definitions, SSL paths, security flags, and the Chef run list. Convert these values into group/host/role variables, with secrets removed from plaintext.
- `Vagrantfile`: Uses `generic/fedora42`, libvirt, two CPUs, 2 GB RAM, private IP `192.168.121.10`, ports 8080/8443, and an rsync-mounted repository. Retain or adapt as the Ansible integration-test harness.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef and Berkshelf, vendors dependencies, and invokes Chef Solo. Replace with Ansible installation/invocation or a Vagrant Ansible provisioner.
- `project-plan.md`: Existing project planning context should be reviewed by the migration coordinator and reconciled with the Ansible work breakdown before implementation.
- `cookbooks/nginx-multisite/attributes/default.rb`: Source of Nginx/security defaults should be compared with `solo.json`; values must be explicitly represented in Ansible defaults and environment variables.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates should be ported selectively into role templates after testing their exact rendered behavior.
- `cookbooks/nginx-multisite/files/default/`: Static `index.html` content for `ci`, `status`, and `test` sites should become role files or application artifacts.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource should be replaced with native `ansible.builtin.lineinfile`, `blockinfile`, or a rendered configuration template.

### Target Details

- **Operating System**: The Chef metadata supports Ubuntu >=18.04 and CentOS >=7. `vagrant-provision.sh` assumes Debian/Ubuntu (`apt-get`, `www-data`, UFW), while `Vagrantfile` provisions `generic/fedora42`. Fedora 42 is therefore the explicit test image, but the current provisioning script is inconsistent with it. The migration must choose a supported target matrix, preferably a current enterprise Linux distribution and/or Ubuntu, and test package names, service names, firewall tooling, SELinux behavior, and Nginx paths accordingly.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync folder synchronization. No production hypervisor is specified.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was identified.

## Migration Approach

1. Establish an Ansible project with `site.yml`, inventories for test/staging/production, `group_vars`, `host_vars` only where necessary, and roles for `nginx_multisite`, `cache`, and `fastapi_tutorial`.
2. Reproduce the three-site Nginx baseline first on a clean VM, including rendered configuration, static files, service handlers, firewall, and certificate behavior.
3. Migrate cache services using supported Ansible modules/roles, replacing the Chef Ruby configuration hack with an explicit Redis configuration template and idempotent service restart handler.
4. Migrate the application and PostgreSQL provisioning with package, Git, Python virtualenv, PostgreSQL module, systemd template, and application health checks.
5. Add Molecule or equivalent converge tests and Vagrant integration tests; compare rendered configs, listening ports, enabled services, and application responses against the Chef baseline.
6. Run Chef and Ansible in parallel in non-production, then cut over by environment with rollback through the previous Chef run and version-controlled VM/image snapshots.

### Key Dependencies to Address

- **nginx 12.3.1 Chef cookbook**: Replace with a maintained Ansible Nginx role or native `ansible.builtin.package`, `template`, `file`, and `service` tasks. Pin the selected role/collection and own the required configuration rather than relying on Chef cookbook defaults.
- **memcached 6.1.0 / `memcached` cookbook**: Use the distribution package and service modules or a pinned Ansible role; define bind address, port, and memory explicitly after confirming current Chef defaults.
- **redisio 7.2.4 / SELinux 6.2.4**: Use the distribution Redis package or a maintained Redis role. Handle SELinux labels/booleans with Ansible modules where applicable; do not blindly port the Chef post-processing hack.
- **ssl_certificate 2.1.0**: It is locked and listed in Policyfile dependencies, although the reviewed local SSL recipe generates self-signed certificates directly. Decide whether production certificates come from an internal CA, ACME, or Ansible Vault-managed deployment; do not assume the Chef dependency provides the intended behavior.
- **FastAPI Git repository and Python requirements**: Pin a commit or release instead of tracking `main`; use `ansible.builtin.git`, Python package installation inside a virtualenv, and an explicit dependency lock process.
- **PostgreSQL**: Replace shell `psql` commands with `community.postgresql` modules and a properly authenticated local connection. Confirm database version, schema migrations, and required extensions.
- **systemd**: Replace the inline Chef service file with an Ansible-managed unit template and `ansible.builtin.systemd_service` handlers.
- **UFW/Fail2ban/OpenSSL**: Use distribution-aware packages and native modules/templates. On Fedora, evaluate firewalld/nftables rather than assuming UFW is installed or appropriate.

### Security Considerations

- **Hardcoded Redis credential**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. It must be treated as compromised, rotated, and stored in Ansible Vault or an external secret manager. Redis should bind only to approved interfaces and be protected by network policy.
- **Hardcoded PostgreSQL credentials**: The FastAPI recipe contains `fastapi_password` in SQL commands and writes it into `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate it, store it in Vault, set restrictive permissions (for example 0600), and use PostgreSQL modules rather than shell commands.
- **TLS private keys and certificates**: The SSL recipe writes keys under `/etc/ssl/private` and grants group access through `ssl-cert`; generated self-signed certificates are development-only and have a one-year lifetime. Production certificates must be issued, renewed, distributed, permissioned, and audited through a defined certificate process. Never commit private keys.
- **SSH hardening**: The configured target disables root login and password authentication. Apply changes with validated `sshd_config` fragments and a safe handler, retaining an out-of-band or pre-tested key-based access path to prevent lockout.
- **Firewall and exposure**: UFW defaults to deny and allows SSH/HTTP/HTTPS, while FastAPI binds to all interfaces on port 8000 and Redis uses 6379. Verify whether 8000 and 6379 should be private-only, enforce host/cloud firewall rules, and validate IPv6 behavior.
- **Fail2ban and sysctl**: Port the templates and confirm jail names, log paths, kernel settings, and compatibility with the selected OS. Test that changes are valid before restarting services.
- **Application privilege**: The systemd unit runs FastAPI as `root`. Create a dedicated non-root service account, restrict filesystem ownership, and define only required capabilities.
- **Supply chain and installation**: The provisioning script downloads and executes Chef’s installer via `curl | bash`, and the application follows Git `main`. Replace these with verified, pinned artifacts and controlled repositories during migration.
- **Secrets management per module**: `cache` has a Redis password; `fastapi-tutorial` has database credentials in commands and `.env`; `nginx-multisite` handles private TLS keys but no visible secret store. No encrypted data bags or external vault integration were identified in the reviewed files.

### Technical Challenges

- **OS mismatch**: Fedora 42 is the Vagrant image, but provisioning uses `apt-get`, UFW, Debian package names, and `www-data`. Mitigation: choose the target OS before role implementation and add OS-family variables/conditionals only where genuinely required.
- **Chef attribute and template semantics**: Nginx sites are data-driven through `node['nginx']['sites']`, while defaults may also come from the Nginx cookbook. Build a clear Ansible schema and validate all three hosts, paths, SSL flags, and generated links.
- **Certificate lifecycle**: Self-signed generation is idempotent only by file existence and does not renew or validate names. Define development versus production certificate ownership and renewal before cutover.
- **Non-idempotent shell behavior**: PostgreSQL creation uses `|| true`, and Redis configuration is edited with a Ruby block. Replace with state-aware modules and explicit changed handlers.
- **External cookbook behavior**: The lock includes dependencies not visibly invoked by the local recipes, including SSL Certificate and SELinux. Inventory the effective Chef run before removing them and map only required behavior to Ansible.
- **Application lifecycle**: Tracking a remote branch and installing an unconstrained requirements file can produce drift. Pin application code and dependencies, add health checks, and decide how updates and rollback work.
- **Ordering and service reloads**: Nginx templates, certificates, site links, firewall, and services have notification relationships in Chef. Implement ordered tasks and handlers so certificates/configuration exist before reloads.
- **Test coverage**: No automated tests were identified in the supplied tree. Establish syntax checks, linting, idempotence checks, rendered-config tests, and end-to-end HTTP/HTTPS/FastAPI/database checks before production migration.

### Migration Order

1. **Foundation and test harness**: Resolve the Fedora-versus-APT decision, create Ansible inventories/variables, establish Vault/secrets handling, and adapt Vagrant/libvirt for repeatable testing.
2. **nginx-multisite**: Highest visible surface area but a natural first functional role; migrate Nginx, sites, static files, TLS test certificates, firewall, Fail2ban, sysctl, and SSH hardening with rollback safeguards.
3. **cache**: Migrate Memcached and Redis after OS/service choices are settled; rotate the Redis password and replace the configuration hack with a deterministic template.
4. **fastapi-tutorial**: Migrate PostgreSQL, application checkout/dependencies, secure environment configuration, non-root systemd service, and port 8000 health checks. This should follow the database and secrets design decisions.
5. **Integration and cutover**: Run comparative validation, document operational procedures, obtain security review, migrate staging, then production in controlled waves while retaining Chef rollback capability.

### Assumptions

- The three local cookbooks are the complete in-scope configuration modules; external cookbooks are dependencies rather than modules to be independently rewritten.
- `solo.json` represents the intended active node configuration, including the three DNS-style site names and SSL paths.
- The Vagrant VM is a development/test environment, not evidence of the production OS or hosting platform.
- The intended production certificate source, DNS ownership, and ACME/internal-CA process are not specified.
- The intended production database version, backup/restore policy, replication requirements, and migration ownership are not specified.
- The FastAPI repository, its `requirements.txt`, application health endpoint, and deployment release policy were not inspected; these must be assessed before final role design.
- The Chef Nginx cookbook's effective defaults and all local templates were not exhaustively audited; rendered behavior should be captured from a working Chef run before cutover.
- The `ssl_certificate` dependency appears in the lock but is not explicitly called by the reviewed local recipes; its operational relevance must be confirmed.
- Redis and Memcached network binding requirements are not specified; defaulting them to localhost/private interfaces is safer than preserving broad exposure.
- Existing plaintext credentials are assumed invalid for future use and should be rotated, even if they are only development credentials.
- No cloud provider, production inventory, CI pipeline, monitoring, backup system, or secret manager was identified.
- Teams should assign separate owners for OS/platform roles, web/security, data services, application deployment, secrets, and test/cutover coordination; each owner should sign off on rendered configuration and rollback procedures.
- Timeline estimates assume one engineer familiar with Ansible and one application/platform reviewer; parallel work can shorten elapsed time but does not remove security and integration gates.
