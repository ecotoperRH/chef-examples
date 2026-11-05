# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Vagrant environment containing three local cookbooks: an Nginx multi-site/security configuration, cache services, and a FastAPI tutorial application. The migration is moderate in operational risk rather than size: the codebase is small, but it combines web serving, TLS, firewall/SSH hardening, Redis and Memcached, PostgreSQL, a remote application checkout, and several hardcoded credentials. A first Ansible implementation and functional validation should take approximately 1–2 weeks for one engineer, or 2–3 weeks including security review, cross-platform decisions, integration testing, and team handover.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and manages Nginx as a three-site HTTP/HTTPS static web server, creates site roots and sample content, configures virtual hosts, and applies web/server security controls.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; HTTP-to-HTTPS redirects; self-signed certificates; TLS 1.2/1.3; security headers; gzip; rate limiting; fail2ban; UFW; SSH hardening; sysctl settings; Nginx templates and static site files.
    - Ansible shape: A role with separate tasks/templates/handlers for packages, Nginx, vhosts, certificates, fail2ban, firewall, SSH, and sysctl. Site definitions should become validated variables rather than Chef node attributes.

- **cache**:
    - Description: Installs Memcached and Redis, configures a Redis server on port 6379, creates the Redis log directory, enables the Redis service, and applies a post-configuration workaround to remove replication-related directives.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, RedisIO dependency, Redis authentication, service enablement, log directory ownership, and a Ruby-based Redis configuration rewrite.
    - Ansible shape: A cache role using supported Ansible package/service/template modules, with Redis configuration represented explicitly and the workaround replaced by a maintained template or documented compatibility task.

- **fastapi-tutorial**:
    - Description: Provisions a Python FastAPI tutorial application from GitHub, installs Python and PostgreSQL packages, creates a virtual environment, installs application requirements, creates a PostgreSQL database/user, writes `.env`, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`; Python venv; PostgreSQL service; `fastapi` database/user; systemd unit on `0.0.0.0:8000`; application owned and run as root in the current implementation.
    - Ansible shape: An application role with package, Git, venv/pip, PostgreSQL database/user, environment-file, systemd, and handler tasks. Pin the application revision and Python dependencies before production migration.

**CRITICAL PATH VERIFICATION:**

The three module paths above were present in the supplied repository tree and their primary `recipes/default.rb` and metadata files were reviewed. No Puppet modules, Salt states, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef Supermarket and local cookbook dependency declarations. It includes local cookbooks plus `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; an SSL cookbook line is commented out. Replace this dependency graph with Ansible Galaxy collections/roles only where useful, preferably with maintained built-in modules.
- `Policyfile.rb`: Defines the policy name, run list, local cookbook paths, and dependency constraints, including `ssl_certificate ~> 2.1` even though it is absent from the active Berksfile.
- `Policyfile.lock.json`: Records resolved versions: Nginx 12.3.1, Memcached 6.1.0, RedisIO 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0, as well as the three local cookbooks. Preserve this as migration evidence, not as an Ansible runtime dependency.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, forwarded ports 8080/8443, and rsync of the repository to `/chef-repo`. Replace Chef provisioning with an Ansible provisioner or an inventory-based test workflow.
- `vagrant-provision.sh`: Runs `apt-get`, installs Chef and Berkshelf via remote installers, vendors dependencies, and runs Chef Solo. It is not compatible with the declared Fedora image as written and should be retired or rewritten for Ansible.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration.
- `solo.json`: Current run list and site/security settings. It contains the externally supplied site roots and the most visible credentials; convert its data into group/host variables and Ansible Vault.
- `project-plan.md`: Project documentation that should be updated with the Ansible inventory, role ownership, test commands, and cutover criteria.

### Target Details

- **Operating System**: The Vagrant box is `generic/fedora42`, but provisioning uses Debian/Ubuntu assumptions (`apt-get`, `www-data`, `/var/log/auth.log`, UFW, and Debian-style Nginx paths). Cookbook metadata claims Ubuntu >=18.04 and CentOS >=7. The target OS is therefore unresolved. Select and standardize a supported OS before implementation; if no decision is available, use Red Hat Enterprise Linux 9 as the planning default and explicitly map package/service/path/firewall differences. Fedora 42 should not be treated as equivalent to RHEL 9 without testing.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync-based source synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was found.

## Migration Approach

### Key Dependencies to Address

- **Chef Solo/Policyfile/Berkshelf**: Replace with an Ansible project containing an inventory, `site.yml`, roles, pinned collection requirements, and CI lint/idempotence tests. Retain the locked Chef versions only as a behavioral reference.
- **nginx 12.3.1 cookbook**: Replace with `ansible.builtin.apt/dnf`, `template`, `file`, `service`, and `assert` tasks, or a vetted Nginx role. Prefer native tasks so the custom virtual-host and security behavior remains visible.
- **memcached 6.1.0**: Use OS packages and an Ansible service task; expose listen address, port, and memory settings as variables. Confirm whether Memcached is intended for local-only use.
- **redisio 7.2.4 and SELinux 6.2.4**: Use the distribution Redis package and explicit configuration/service tasks, with `ansible.posix.seboolean`, `ansible.posix.selinux`, or policy packages where required. Validate the old Ruby workaround against the target Redis version.
- **ssl_certificate 2.1.0**: The current code actually generates self-signed certificates with OpenSSL. For development, use an Ansible certificate-generation task or pre-generated test certificates; for real environments, use an approved CA/ACME workflow and Vault-backed private keys.
- **PostgreSQL and Python runtime**: Install target OS packages, use `community.postgresql.postgresql_db` and `postgresql_user`, and use `ansible.builtin.git`, `pip`, and `systemd`. Pin the Git revision and dependency versions rather than tracking `main`.
- **Fail2ban/UFW/SSH/sysctl**: Use `ansible.builtin.package`, `template`, `sysctl`, `service`, and `ansible.posix.firewalld` or UFW modules according to the selected OS. Avoid shell edits to `sshd_config` where Ansible drop-ins are available.

### Security Considerations

- **Hardcoded Redis credential**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Treat it as compromised, rotate it, and store the replacement in Ansible Vault or an external secrets manager. Do not place it in defaults or committed templates.
- **Hardcoded PostgreSQL credentials**: `fastapi` / `fastapi_password` are embedded in the recipe and written to a world-readable `.env` file (`0644`). Rotate the password, use Vault, restrict the file to the application user, and ensure it is excluded from logs and backups where appropriate.
- **TLS private keys and certificates**: Keys are written under `/etc/ssl/private` with `0640` and group `ssl-cert`; certificates are self-signed for development. Preserve restrictive permissions, never generate production keys casually on every host, and define certificate renewal/rotation ownership. The current one-year self-signed certificates will produce client trust warnings.
- **TLS configuration**: TLS 1.2/1.3, HSTS, selected ciphers, and security headers must be regression-tested. Review the cipher list and HSTS behavior before production, especially if any non-HTTPS endpoint or subdomain is expected.
- **Firewall and SSH**: UFW defaults to deny and allows SSH/HTTP/HTTPS, while root login and password authentication are disabled. Reproduce this carefully with the target OS firewall, preserve console/break-glass access, and validate SSH connectivity before enabling the final policy.
- **Application privilege**: The systemd service runs Uvicorn as `root` and exposes port 8000 on all interfaces. Create a dedicated unprivileged service account, bind only as required or protect the port behind Nginx, and define systemd hardening controls.
- **Remote supply chain**: The application is cloned from an unpinned `main` branch and pip installs its requirements. Pin a reviewed commit, use a controlled package index/lock file, and verify checksums where feasible.
- **Secrets management by module**: `cache` contains the Redis password; `fastapi-tutorial` contains the database password and connection string; `nginx-multisite` contains no application credential but handles private TLS key paths and certificate generation. No Chef encrypted data bags or Chef Vault usage were visible in the reviewed files.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is declared while the provisioning script and many paths assume Ubuntu/Debian. Resolve the target platform first and create an OS-variable matrix for packages, service names, firewall, web user, SSH log path, and SELinux behavior.
- **Chef resource ordering and notifications**: Chef includes recipes and delayed reload/restart notifications. Recreate ordering with role task boundaries and handlers, then test idempotence and convergence on a clean VM.
- **Nginx site/content path mismatch**: `solo.json` uses `/var/www/...`, while cookbook defaults use `/opt/server/...`; static files are selected from cookbook paths based on site names. Establish one authoritative site model and verify all content, symlinks, roots, and HTTP redirects.
- **Redis compatibility workaround**: The Ruby block deletes several replication directives after RedisIO writes them. Determine the original Redis error/compatibility requirement and replace it with a supported configuration rather than porting the mutation blindly.
- **Certificate lifecycle**: Self-signed certificates are suitable for the Vagrant demo but not a production trust model. Separate development certificates from production CA/ACME integration.
- **Database/application readiness**: The current shell command ignores database creation errors with `|| true`, and the service may start before migrations or application readiness checks. Use idempotent PostgreSQL modules, explicit grants, health checks, and deployment handlers.
- **Firewall lockout and service exposure**: Applying firewall and SSH changes remotely can disconnect operators; test with Vagrant console access and staged enforcement.
- **Dependency and platform drift**: Chef dependency locks are historical snapshots, while Ansible modules and OS packages will have different defaults. Capture behavior with integration tests rather than attempting a literal line-by-line translation.

### Migration Order

1. **Foundation and target platform decision**: Select Fedora/RHEL or Ubuntu, rebuild the Vagrant test path for Ansible, define inventory/group variables, Vault workflow, service accounts, and baseline CI checks.
2. **nginx-multisite**: Migrate package/service, site roots, static content, virtual hosts, handlers, and development TLS first because it is the primary exposed service and validates the target OS.
3. **Security baseline**: Add SSH, firewall, sysctl, fail2ban, TLS permissions, and Nginx headers/rate limits in a controlled stage after console and rollback procedures are proven.
4. **cache**: Migrate Memcached and Redis independently, rotate the embedded password, validate bind addresses and persistence/authentication, and confirm the Redis compatibility behavior.
5. **fastapi-tutorial**: Migrate PostgreSQL, application checkout, venv, secret file, systemd unit, and Nginx integration. Run this after the platform and security baseline are stable.
6. **Cutover and decommissioning**: Run parallel validation, compare ports/logs/configuration, perform an idempotence test, document rollback, then retire Chef/Berkshelf scripts and remove plaintext secrets from Git history where policy requires.

### Assumptions

- The three directories containing `recipes/default.rb` are the complete set of local cookbooks requiring migration.
- The Policyfile run list is the intended deployment set; `solo.json` is a legacy or alternate run configuration and its path differences require confirmation.
- The application repository and its requirements are available during deployment, but its exact runtime requirements and migration commands were not reviewed.
- The intended production OS is not established. The stated Fedora box, Ubuntu-style commands, and cookbook support metadata conflict.
- The Vagrant private IP appears as `192.168.121.10`, while provisioning output references `192.168.56.10`; the correct test address must be confirmed.
- The three cluster hostnames are development/test names and DNS or `/etc/hosts` management is outside the reviewed repository.
- Self-signed TLS is for development only; production certificate ownership, CA, renewal, and trust distribution remain to be decided.
- Redis authentication is required, but the desired Redis bind address, persistence, replication topology, and Memcached bind policy are not specified.
- PostgreSQL is intended to run locally on the same host and the application database schema/migrations are handled elsewhere unless confirmed otherwise.
- The application is currently intentionally run as root, but the migration should treat this as a security defect and use a dedicated account unless a documented exception exists.
- No cloud platform, external secret manager, monitoring, backup, DNS, load balancer, or CI system was specified.
- Chef Supermarket dependencies and their locked versions are source behavior references; they do not guarantee compatibility with the selected Ansible target OS.
- Timeline estimate assumes one environment, three local roles, no HA architecture, and access to test credentials and a disposable VM. Production rollout, compliance review, and certificate/secret integration may extend the schedule.

Team coordination should assign separate owners for platform/inventory, Nginx/security, cache services, and application/PostgreSQL work. Require a shared variable contract, peer review for all Vault and firewall changes, an integration test matrix for the selected OS, and a recorded acceptance checklist covering idempotence, ports 80/443/8000, TLS behavior, database connectivity, Redis authentication, SSH recovery, and rollback.
