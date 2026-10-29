# MIGRATION FROM CHEF TO ANSIBLE

This is a small Chef Solo/Policyfile repository containing three local cookbooks: an Nginx multisite/security layer, cache services, and a FastAPI/PostgreSQL application. The target Ansible implementation should preserve the current single-host development topology while separating reusable roles, environment data, and secrets. The migration is moderate in operational risk rather than repository size because it includes firewall and SSH hardening, TLS key handling, database credentials, service orchestration, and several shell-based/non-idempotent operations. A realistic delivery estimate is approximately 2–4 engineer-weeks for implementation, testing, hardening, and documentation, assuming no production-only behavior is hidden outside this repository.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web serving for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), with static content, HTTP-to-HTTPS redirects, security headers, compression, logging, and development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: `nginx`, `security`, `ssl`, and `sites` recipes; Nginx configuration templates; per-site document roots; UFW default-deny rules; Fail2ban; SSH root-login/password-auth hardening; sysctl settings; self-signed RSA certificates.

- **cache**:
    - Description: Installs and enables Memcached and Redis, configures a Redis server on port 6379 with password authentication, creates the Redis log directory, and applies a post-generation configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, Redisio inclusion and enablement, Redis password configuration, log directory management, and a `ruby_block` that removes selected replication-related directives from `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
    - Description: Provisions a Python FastAPI tutorial application from GitHub, creates a Python virtual environment, installs requirements, starts PostgreSQL, creates the application database/user, writes a `.env` file, and manages a systemd service running Uvicorn on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv setup, Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, PostgreSQL packages and service, database bootstrap commands, systemd unit creation, and service enablement.

**CRITICAL PATH VERIFICATION:**
All three paths above were present in the supplied repository tree and their primary `recipes/default.rb` entrypoints were reviewed. External cookbooks are dependencies, not local modules, and are therefore not listed in the inventory.

### Infrastructure Files

- `Berksfile`: Declares the Chef Supermarket source, three local cookbooks, and external `nginx`, `memcached`, and `redisio` dependencies. The commented `ssl_certificate` line indicates an earlier or optional dependency.
- `Policyfile.rb`: Defines the policy name, run list, local cookbook paths, and version constraints, including `ssl_certificate` even though the local cookbook generates certificates directly.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0. It is the authoritative dependency snapshot for this migration.
- `Vagrantfile`: Defines the development VM as `generic/fedora42`, hostname `chef-nginx`, private IP `192.168.121.10`, forwarded ports 80/443 to host ports 8080/8443, and a libvirt VM with 2 GB RAM and 2 CPUs. It rsyncs the repository to `/chef-repo` and invokes `vagrant-provision.sh`.
- `vagrant-provision.sh`: Installs packages using `apt-get`, installs Chef and Berkshelf from remote installers, vendors dependencies, and runs Chef Solo. It contains the current provisioning workflow and needs replacement with an Ansible installation/inventory/playbook workflow.
- `solo.rb`: Chef Solo configuration defining the cache directory, cookbook paths, and logging.
- `solo.json`: Runtime attributes and run list. It defines the three virtual hosts, SSL directories, and security flags. It conflicts with cookbook defaults for document roots (`/var/www/...` versus `/opt/server/...`) and should become explicit Ansible group/host variables.
- `project-plan.md`: Describes the surrounding X2Ansible tool and expected analysis/migration/validation workflow. It is project documentation rather than infrastructure configuration, but should be updated or linked to the actual Ansible deliverables.
- `cookbooks/nginx-multisite/files/default/*`: Static `index.html` files for the three sites; these should be copied by the Ansible role.
- `cookbooks/nginx-multisite/templates/default/*`: Source templates for Nginx, Fail2ban, site virtual hosts, and sysctl security configuration; these are the primary configuration assets to port.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The actual Vagrant box is Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu-specific `apt-get`, `/var/log/auth.log`, UFW, `www-data`, and Debian-style Nginx paths. The Ansible target must be decided explicitly. For migration compatibility, use Debian/Ubuntu as the initial supported target, or add a Fedora/RHEL variable layer and replace UFW/user/path assumptions. If no production specification exists, default planning should document RHEL 9 as the standard enterprise target, but it will require adaptation rather than a direct lift-and-shift.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 CPUs and 2048 MB RAM. The Ansible test harness should retain Vagrant/libvirt where feasible.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud metadata integration was found.
- **Network/application endpoints**: Development exposes HTTP/HTTPS through forwarded ports 8080/8443 and the FastAPI service listens on all interfaces at port 8000. The application port is not forwarded in the Vagrantfile and should be tested locally on the guest or exposed intentionally.

## Migration Approach

Create an Ansible project with a top-level site playbook and separate roles, for example:

- `roles/nginx_multisite`: packages, directories, static files, Nginx templates, virtual-host links, TLS material, validation, and handlers.
- `roles/security`: Fail2ban, firewall policy, sysctl, and SSH configuration. This may be kept within the Nginx role for the first increment but should remain independently testable.
- `roles/cache`: Memcached and Redis packages/services, configuration, permissions, and password handling.
- `roles/fastapi_tutorial`: Python packages/venv, Git checkout, PostgreSQL, database/user provisioning, environment file, systemd unit, and service handlers.
- `site.yml` or an equivalent composition playbook: enforce ordering and host targeting.
- `inventories/dev/host_vars` and `group_vars`: move `solo.json` values into structured variables, with secrets encrypted using Ansible Vault or an external secret manager.

Use Ansible modules instead of shell commands wherever practical: `package`, `service`, `template`, `copy`, `file`, `git`, `community.postgresql.postgresql_db`, `community.postgresql.postgresql_user`, `ansible.posix.firewalld` or `community.general.ufw`, `ansible.posix.sysctl`, `ansible.builtin.lineinfile`/`blockinfile`, and `ansible.builtin.systemd`. Add handlers for Nginx reload, Fail2ban restart, SSH restart, sysctl reload, and systemd daemon reload. Run `nginx -t` before reloads.

### Key Dependencies to Address

- **Chef Solo and Berkshelf**: Replace `solo.rb`, `solo.json`, Chef installation, and `berks vendor` with Ansible inventory, collections requirements, role dependencies, and `ansible-playbook` execution.
- **nginx cookbook 12.3.1**: Replace with native Ansible package/service/template tasks. The local cookbook mostly manages Nginx directly and does not clearly consume cookbook resources from the external Nginx cookbook.
- **memcached cookbook 6.1.0**: Replace with distribution packages, service management, and explicit Memcached configuration; verify bind address and exposure defaults.
- **redisio cookbook 7.2.4 plus selinux 6.2.4**: Replace with an OS-supported Redis role or distribution packages and explicit configuration. Preserve password authentication and validate the replication-directive workaround rather than copying the brittle file-edit behavior.
- **ssl_certificate 2.1.0**: Locked in `Policyfile.lock.json` and included in `Policyfile.rb`, but not used by the reviewed local recipes. Decide whether to remove it or replace it with managed certificate files, ACME/Let's Encrypt automation, or externally supplied certificates.
- **PostgreSQL and Python dependencies**: The application cookbook installs distribution PostgreSQL and `requirements.txt` from the cloned repository. Pin the application revision and Python dependencies for repeatability, and choose the appropriate Ansible PostgreSQL collection.
- **GitHub repository**: `https://github.com/dibanez/fastapi_tutorial.git` at `main` is mutable. Pin a commit/tag in Ansible after confirming the required application version.
- **Vagrant/libvirt**: Retain as the development acceptance environment, but make its OS and provisioning path consistent with the selected target distribution.

### Security Considerations

- **Hardcoded credentials**: `cookbooks/cache/recipes/default.rb` contains the Redis password `redis_secure_password_123`. `fastapi-tutorial/recipes/default.rb` contains PostgreSQL password `fastapi_password` in both SQL commands and a world-readable (`0644`) `.env` file. Remove these values from source, use Ansible Vault or an approved secret manager, set restrictive ownership/mode (for example, application-only access and `0600`), and rotate them during migration.
- **TLS private keys and certificates**: Self-signed certificates are generated under `/etc/ssl/certs` and `/etc/ssl/private`, with keys owned by `root:ssl-cert` and mode 0640. Preserve restrictive permissions, avoid committing generated keys, and clarify whether production requires a CA-issued certificate. Validate certificate subject/SANs, renewal, and deployment without exposing private material in logs.
- **TLS policy**: The templates allow TLS 1.2/1.3 and specify a static cipher list, HSTS, and security headers. Revalidate the cipher policy against current organizational standards; do not blindly preserve obsolete choices. HSTS should only be enabled when HTTPS is guaranteed for all intended subdomains.
- **Firewall and SSH hardening**: The security recipe sets UFW default deny, allows SSH/HTTP/HTTPS, disables root login, and disables password authentication. Confirm the administrative access path before applying these tasks to avoid lockout. On Fedora/RHEL, translate UFW rules to firewalld and account for SELinux rather than assuming Debian behavior.
- **Fail2ban**: Preserve SSH and Nginx jails, but validate filters, log paths, backend behavior, and package names on the target OS. Ensure the firewall integration is compatible with the selected firewall implementation.
- **Nginx exposure and headers**: Nginx listens on HTTP/HTTPS, while the FastAPI service runs as `root` and binds to `0.0.0.0:8000`. The application should run under a dedicated unprivileged account, and port 8000 should not be externally exposed unless required. Review the CSP's `unsafe-inline`, request-size limit of 1 KB, access/error log permissions, and the absence of an Nginx reverse-proxy configuration for FastAPI.
- **Supply chain**: Chef is installed using a remote script and the application is cloned from an unpinned Git branch. Replace with verified package repositories, checksums/signatures where possible, pinned revisions, and CI dependency scanning.
- **Credential patterns by module**: `cache` has a hardcoded Redis password; `fastapi-tutorial` has hardcoded database credentials and a plaintext environment file; `nginx-multisite` has no visible secret value but manages private TLS keys and generates self-signed certificates. No encrypted data bags or Chef Vault usage were found in reviewed files.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is declared by Vagrant, but provisioning and recipes assume Debian/Ubuntu conventions. Mitigation: choose a supported target matrix first, build OS-specific defaults, and test the selected image in CI.
- **Chef attribute precedence and drift**: Cookbook defaults use `/opt/server/...`, while `solo.json` overrides them with `/var/www/...`; the runtime source of truth is therefore not obvious. Mitigation: create an explicit variable contract and acceptance tests for all three hostnames, paths, and ports.
- **Non-idempotent database bootstrap**: `CREATE USER` and `CREATE DATABASE` are wrapped in `|| true`, hiding real failures. Mitigation: use PostgreSQL modules with explicit existence/state checks and validate ownership, privileges, and password rotation.
- **Shell-based configuration edits**: Redis uses a Ruby file rewrite and SSH uses `sed`; these can be brittle and may remove valid settings. Mitigation: model intended configuration with templates or targeted idempotent parameters, then test resulting service configuration.
- **TLS lifecycle**: The current self-signed certificates are generated only if files do not exist and have no renewal or deployment source. Mitigation: define development certificate behavior separately from production certificate injection/ACME renewal.
- **Missing application integration**: FastAPI runs on port 8000 but the reviewed Nginx site templates serve static files and do not proxy to it. Mitigation: confirm intended architecture before adding a reverse proxy or treating the application as a separate endpoint.
- **Dependency ambiguity**: `ssl_certificate` is locked but not visibly used, and the external Nginx cookbook is declared although local recipes install/manage Nginx directly. Mitigation: inventory actual runtime dependencies and remove unused components after a clean-room test.
- **Static site/resource path mismatch**: The recipe derives `test`, `ci`, and `status` file names from hostnames, while document roots vary by attributes. Mitigation: use explicit site objects in Ansible and verify all content files and symlinks.
- **Service ordering**: Redis, PostgreSQL, systemd reloads, Nginx, firewall, and Fail2ban have implicit Chef ordering. Mitigation: express role dependencies and handlers explicitly, then run convergence twice to prove idempotence.

### Migration Order

1. **Baseline and target decision**: Freeze the Chef lock state, choose Ubuntu/Debian versus Fedora/RHEL, document expected ports/URLs, and create a Vagrant/CI acceptance matrix.
2. **Security foundation**: Implement inventory access controls, Vault integration, package repositories, SSH safeguards, sysctl, firewall, and Fail2ban with a safe rollback path. Test from a second administrative session before enforcing lockout settings.
3. **nginx-multisite**: Port static files, Nginx configuration, site templates, links, headers, TLS behavior, and service handlers. Validate HTTP redirect, HTTPS, certificate permissions, and all three hostnames.
4. **cache**: Implement Memcached and Redis, move the Redis password to Vault, replace the configuration workaround, and verify service health and network exposure.
5. **fastapi-tutorial**: Pin the Git revision, install Python/PostgreSQL dependencies, create the database declaratively, run the service as a dedicated user, and decide whether Nginx should proxy to Uvicorn.
6. **Integration and cutover**: Apply the complete playbook repeatedly, compare package/service/file/database outcomes with Chef, run security checks, and retire Chef only after rollback and operational runbooks are approved.

Estimated effort: 2–4 engineer-weeks for the three local roles and test harness; add 1–2 weeks if Fedora/RHEL support, production certificate automation, cloud deployment, or a full application reverse-proxy design is required.

### Assumptions

- The supplied tree is the complete relevant Chef repository; no hidden roles, environments, encrypted data bags, production certificates, or external dashboards are assumed.
- The three local cookbooks are the migration scope; external cookbook behavior is represented only where the reviewed recipes and lockfile reveal it.
- `solo.json` is intended to override cookbook defaults, making `/var/www/test.cluster.local`, `/var/www/ci.cluster.local`, and `/var/www/status.cluster.local` the expected runtime document roots, although the Vagrant comments and cookbook defaults show conflicting values.
- The intended development host is the Vagrant libvirt VM, but the declared Fedora 42 image is not compatible with the current `apt-get` provisioning script without changes.
- Production OS, inventory, DNS, certificate authority, database backup requirements, monitoring, and cloud platform are unspecified.
- The FastAPI repository's `requirements.txt` and application behavior are external to this tree and were not audited; its exact runtime dependencies and migration requirements must be verified.
- The database is local PostgreSQL and the application database/user should remain local unless deployment architecture discovery says otherwise.
- The hardcoded passwords are examples or current development credentials, but they must be treated as compromised and rotated before any production use.
- The self-signed certificates are intended for development, as stated by the provisioning output; production certificate issuance and renewal are not defined.
- The three Nginx sites are static sites in the current recipes; whether any should proxy to FastAPI is unresolved.
- Port 8000 is intentionally local or guest-only because it is not forwarded by Vagrant; this must be confirmed.
- SELinux behavior is not defined by the local cookbooks; a Fedora/RHEL target will need explicit contexts, booleans, and service policy validation.
- Ansible collection versions, controller version, execution environment, CI system, and secret manager have not been specified and must be standardized by the migration team.
- Validation will compare effective service state and externally observable behavior, not reproduce Chef implementation details such as Ruby blocks or cookbook resource names.
- Team coordination should assign separate owners for OS/platform compatibility, security/secrets, Nginx/TLS, cache services, and application/PostgreSQL, with shared acceptance tests and a documented cutover/rollback decision.