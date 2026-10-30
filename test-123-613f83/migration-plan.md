# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile-based infrastructure project with three local cookbooks: an Nginx multisite/security stack, caching services, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in operational risk despite the small module count because it includes hardcoded credentials, firewall and SSH hardening, generated TLS keys, service orchestration, and an OS/provisioning mismatch. A focused migration should take approximately 1–2 weeks for one experienced engineer, including implementation, validation, and documentation; allow 2–3 weeks if production-like testing, certificate/secret redesign, or application ownership coordination is required.

The recommended target is an Ansible project organized into roles for `nginx_multisite`, `cache`, and `fastapi_tutorial`, with shared inventory/group variables and Ansible Vault or an external secret manager. Preserve the current Vagrant/libvirt test workflow initially, but correct the Fedora-versus-Debian assumptions before treating the environment as a reliable acceptance target.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and manages Nginx serving three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), with static content, security controls, and service lifecycle management.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx installation, generated `nginx.conf` and security configuration, per-site templates and symlinks, static index files, fail2ban, UFW rules, sysctl hardening, disabling root SSH login and password authentication, and self-signed RSA certificates for development.
    - Ansible shape: `roles/nginx_multisite` with package/service tasks, templated Nginx configuration, site data variables, handlers, firewall tasks, hardening tasks, and certificate handling.

- **cache**:
    - Description: Installs and enables Memcached and Redis, configures Redis on port 6379, creates its log directory, and applies a post-generation configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, RedisIO integration, Redis password authentication, Redis log directory, Redis service enablement, and removal of selected replication-related settings through a Ruby block.
    - Ansible shape: `roles/cache` with separate Memcached and Redis tasks, explicit Redis configuration templating, service handlers, and a documented decision about whether the legacy workaround remains necessary.

- **fastapi-tutorial**:
    - Description: Provisions a Python FastAPI tutorial application from GitHub, creates a virtual environment, installs PostgreSQL and Python dependencies, creates a PostgreSQL database/user, writes an environment file, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv setup, Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, PostgreSQL service management, database initialization, systemd unit creation, port 8000 binding, and automatic restart.
    - Ansible shape: `roles/fastapi_tutorial` with package, repository, virtualenv, dependency, PostgreSQL, systemd, and application configuration tasks. Database creation should use idempotent PostgreSQL modules rather than shell commands.

**CRITICAL PATH VERIFICATION:**
The three cookbook paths above are present in the supplied repository tree and their primary entrypoints were reviewed. No Puppet modules, Salt states, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef dependency source and local cookbook declarations. It references local `nginx-multisite`, `cache`, and `fastapi-tutorial` cookbooks plus external `nginx` `~> 12.0`, `memcached` `~> 6.0`, and `redisio` `~> 7.2.4`; the `ssl_certificate` declaration is commented out. Replace this dependency model with `collections/requirements.yml`, role requirements if needed, and explicit Ansible package/module prerequisites.
- `Policyfile.rb`: Defines policy name, run list, local cookbook paths, and external cookbook constraints. It includes `ssl_certificate` even though the Berksfile declaration is commented, so the lock file is the authoritative resolved state to reconcile during migration.
- `Policyfile.lock.json`: Pins local cookbook revisions and external versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0. Use it as a migration inventory, not as a direct Ansible dependency mechanism.
- `Vagrantfile`: Defines a `generic/fedora42` VM using libvirt, 2 GB RAM, 2 CPUs, private address `192.168.121.10`, and forwarded ports 8080/8443 to guest ports 80/443. It syncs the repository to `/chef-repo` and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef and Berkshelf, vendors Chef dependencies, and runs Chef Solo. It must be replaced with Ansible provisioning or an Ansible Vagrant provisioner; its Debian package assumptions conflict with the Fedora base box.
- `solo.rb`: Chef Solo cache, cookbook search paths, and logging configuration. It has no direct Ansible equivalent beyond project layout and command-line configuration.
- `solo.json`: Chef run list and node attributes for the three sites, SSL paths, firewall state, and SSH hardening. Convert these values to inventory/group variables, with secrets removed from plaintext.
- `project-plan.md`: Describes the broader X2Ansible analysis/migration/validation workflow. Retain relevant validation and coordination concepts, but do not treat it as infrastructure runtime configuration.
- `cookbooks/nginx-multisite/templates/`: Nginx, security, site, fail2ban, and sysctl templates must be ported to Jinja2 and reviewed for Fedora/Debian path and directive differences.
- `cookbooks/nginx-multisite/files/`: Static HTML fixtures for the three sites should become role files or application-owned deployment artifacts.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the tree; determine whether it is used by the reviewed recipes before migration and replace any usage with Ansible `ansible.builtin.lineinfile` or a template.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The Vagrant box is Fedora 42, but `vagrant-provision.sh` uses `apt-get`, indicating an unresolved platform mismatch. Confirm the intended target before implementation. If no production specification exists, standardize on one supported family; for a current enterprise target, RHEL-compatible 9 should be evaluated, with Fedora retained only if explicitly required. Package names, service names, firewall tooling, Nginx paths, PostgreSQL packages, and SSH service names must be tested on the selected OS.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly specified. The VM has 2 CPUs and 2 GB memory and uses rsync folder synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration is present.

## Migration Approach

Create an Ansible repository with an inventory for the Vagrant test host, group variables for site definitions and non-secret settings, and roles for the three local cookbooks. Add a top-level playbook that preserves the current run order while making dependencies explicit. Use handlers for Nginx, fail2ban, Redis, SSH, sysctl, and systemd reloads. Validate first in an isolated VM, then perform a controlled cutover with configuration snapshots and rollback instructions.

### Key Dependencies to Address

- **Nginx cookbook 12.3.1**: Replace with native Ansible package/service/template tasks and the distribution's Nginx package. Confirm repository/version requirements rather than assuming Chef cookbook behavior.
- **Memcached cookbook 6.1.0**: Replace with package installation, service management, and an explicit configuration template. Confirm bind address and exposure requirements, which are not visible in the reviewed local recipe.
- **RedisIO cookbook 7.2.4**: Replace with a supported Redis installation/configuration role or distribution packages. Reproduce password authentication and port settings using a template, not an imperative text-edit workaround.
- **SELinux cookbook 6.2.4**: The lock file records this transitive Redis dependency, but the local recipes do not show its policy behavior. On Fedora/RHEL, define SELinux mode, labels, and required booleans/ports deliberately rather than disabling SELinux.
- **ssl_certificate cookbook 2.1.0**: It is locked by Policyfile but not used by the reviewed local recipes. Determine whether it was intended for certificate deployment. Replace with Ansible certificate files, a supported ACME role, or an enterprise certificate service; do not carry forward unused dependency behavior.
- **PostgreSQL**: The FastAPI cookbook installs distribution PostgreSQL packages and uses shell `psql` commands. Use `community.postgresql` modules, install the collection, and ensure Python PostgreSQL libraries and administrative authentication are configured.
- **Python application dependencies**: The application pulls `requirements.txt` from a mutable Git `main` branch. Pin a commit/tag and establish dependency lock and supply-chain review before production use.
- **Firewall and hardening**: Replace UFW shell commands with `ansible.posix.firewalld` on RHEL/Fedora or `community.general.ufw` on Debian/Ubuntu, selected based on the final OS.
- **Ansible collections**: At minimum evaluate `ansible.posix`, `community.general`, and `community.postgresql`; pin tested collection versions in `requirements.yml`.

### Security Considerations

- **Redis credential exposure**: `cookbooks/cache/recipes/default.rb` contains the plaintext password `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and restrict Redis binding/firewall access.
- **PostgreSQL credential exposure**: `fastapi-tutorial` embeds `fastapi_password` in shell commands and writes it into `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate it, use Vault-backed variables, set restrictive permissions such as `0600`, and avoid logging command-line credentials.
- **TLS private keys and certificates**: The SSL recipe generates self-signed private keys under `/etc/ssl/private` with root ownership and `ssl-cert` group access. Preserve restrictive permissions, but replace development certificates with managed certificates in production and ensure private keys are delivered through a protected mechanism.
- **SSH hardening**: Root login and password authentication are disabled through direct `sed` edits. Implement this with a validated SSH configuration template or `lineinfile`, use `sshd -t` before restart, and confirm an alternate administrative key/session exists to prevent lockout.
- **Firewall defaults**: UFW is set to default deny while allowing SSH, HTTP, and HTTPS. Reconcile this with the application’s port 8000 and any internal Redis/Memcached/PostgreSQL access; do not expose data services publicly.
- **fail2ban and sysctl**: Port the reviewed templates and test them against the target OS. Validate jail names, log paths, kernel parameter compatibility, and safe reload behavior.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Create a dedicated unprivileged application user, restrict the working directory and `.env`, and place a reverse proxy in front of the application if it is externally reachable.
- **Supply chain and transport**: Chef installation uses a remote `curl | bash` script, and the application is cloned from an unpinned public branch. Replace both with pinned, verified artifacts where possible.
- **Per-module credential summary**: `cache` has a hardcoded Redis password; `fastapi-tutorial` has a hardcoded PostgreSQL password and environment file; `nginx-multisite` generates TLS private keys but has no external secret store; no encrypted data bags or Chef Vault usage were observed in the reviewed files.

### Technical Challenges

- **OS mismatch**: Fedora 42 is provisioned with Debian `apt-get` commands, while cookbook support lists Ubuntu and CentOS. Select and document the target OS, then make the Vagrant acceptance environment match it.
- **Chef resource semantics**: Chef notifications, recipe inclusion, node attributes, and the Redis Ruby-block workaround need explicit Ansible task ordering and handlers. Build idempotent configuration rather than translating shell edits literally.
- **Configuration source precedence**: Site paths differ between `attributes/default.rb` (`/opt/server/...`) and `solo.json` (`/var/www/...`). Establish one authoritative variable model and test all three virtual hosts.
- **Certificate lifecycle**: Current certificates are self-signed and generated only when absent. Define whether the target requires development self-signed certificates, pre-provisioned enterprise certificates, or ACME renewal.
- **Database idempotency and readiness**: The current `psql` commands use `|| true`, masking failures and possibly rerunning unsafe statements. Replace with module-based database/user management, explicit PostgreSQL readiness checks, and migrations if the application requires them.
- **Application service correctness**: The service runs as root, binds to all interfaces on port 8000, and relies on a mutable repository branch. Pin the release, create a service account, define health checks, and decide whether Nginx should proxy to it.
- **Unreviewed templates and custom resource**: The exact directives in the templates and whether `lineinfile.rb` is used need a targeted follow-up review before final parity testing.
- **Dependency drift**: Policyfile and Berksfile differ on the `ssl_certificate` declaration, and the lock includes transitive SELinux behavior. Capture the intended runtime dependency set before deleting Chef artifacts.

### Migration Order

1. **Foundation and test environment**: Resolve the Fedora/Debian mismatch, create Ansible inventory and collections requirements, establish Vault/secrets handling, and document the desired OS and network model.
2. **cache**: Migrate Memcached and Redis first because it is relatively self-contained, while fixing the exposed Redis password and validating service persistence and access controls.
3. **fastapi-tutorial**: Migrate package, PostgreSQL, application checkout, virtual environment, systemd, and database initialization. Make credentials and application ownership secure before enabling it.
4. **nginx-multisite security baseline**: Port packages, Nginx configuration, fail2ban, firewall, sysctl, and SSH hardening. Apply SSH changes only after out-of-band/key-based access is verified.
5. **nginx-multisite sites and TLS**: Port site variables, static content, templates, symlinks, and certificate delivery. Validate all hostnames, HTTP/HTTPS behavior, reloads, and permissions.
6. **Integrated acceptance and cutover**: Compare installed packages, enabled services, listeners, firewall rules, rendered files, TLS behavior, application health, and persistence across reboot. Perform staged rollout and retain Chef rollback procedures until sign-off.

### Assumptions

- The three local cookbook directories are the complete source modules in scope.
- The Policyfile lock is representative of the intended Chef dependency versions, although Berksfile and Policyfile declarations are not fully consistent.
- The external cookbooks are implementation dependencies and are not separate local migration modules.
- The three sites and their SSL-enabled behavior are required, but the exact production DNS and certificate authority are not specified.
- The target is a VM or host with systemd; this is implied by the current service unit and Vagrant VM.
- The final OS has not been selected. Fedora 42, Ubuntu >=18.04, CentOS >=7, and the requested default RHEL 9 direction are not interchangeable without testing.
- The intended production topology, number of hosts, inventory groups, and whether cache/database services are colocated are unknown.
- Redis and Memcached network bind settings are not visible in the reviewed local recipe; their required clients and exposure boundaries must be confirmed.
- PostgreSQL version, schema migration process, backup/restore requirements, and application release process are unspecified.
- The FastAPI repository’s runtime requirements, health endpoint, and deployment ownership are external to this repository and require confirmation.
- The custom `lineinfile` resource may be unused; usage must be confirmed before removal.
- The Nginx and security template contents require final directive-level review during implementation, even though their purpose and paths are known.
- Self-signed certificates are suitable only for the current development/test scenario unless explicitly approved otherwise.
- No cloud platform, external secret manager, monitoring, logging, backup, or CI/CD integration is defined in this repository.
- Secrets found in source control should be treated as compromised and rotated independently of the migration.
- Migration acceptance will be semantic rather than byte-for-byte: package/service state, security posture, rendered configuration, application behavior, and persistence must match the approved target design.
- Team coordination should assign separate owners for platform/OS, security/secrets, caching, PostgreSQL/application runtime, and Nginx/TLS; use a shared test inventory and review rendered configurations and rollback steps before production deployment.
