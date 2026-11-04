# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile configuration repository comprising three local cookbooks and four resolved Supermarket cookbook dependencies. It provisions a single development-style VM with an Nginx multi-site front end, host hardening controls, Redis and Memcached caches, and a FastAPI application backed by local PostgreSQL. The migration is moderate in scope but has material correctness and security remediation work: the declared Fedora 42 Vagrant box conflicts with Ubuntu/Debian-specific provisioning and configuration, and application/database/cache credentials are committed in plaintext. A two-person team can produce an initial, tested Ansible implementation in approximately 2–3 weeks, including platform decisions, role conversion, automated validation, and documentation; production certificate and secret-management integration may extend this estimate.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and configures Memcached through the external `memcached` cookbook and a Redis server through `redisio`; creates Redis logging storage and applies an in-place workaround to remove several replication-related Redis configuration directives before enabling Redis.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion, Redis on port 6379, password-based Redis authentication, `/var/log/redis` ownership, Redis configuration mutation, Redis enablement.

- **fastapi-tutorial**:
  - Description: Deploys the externally sourced `dibanez/fastapi_tutorial` Python application from its `main` Git branch, builds a virtual environment, installs Python dependencies, configures a local PostgreSQL database and user, writes application environment settings, and runs Uvicorn as a systemd service.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/pip/venv and Git packages, PostgreSQL service and database bootstrap, application checkout at `/opt/fastapi-tutorial`, systemd service on port 8000, `.env` database URL.

- **nginx-multisite**:
  - Description: Configures Nginx to host the `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` static sites, creates self-signed TLS certificates, redirects HTTP to HTTPS, and applies Fail2ban, UFW, kernel, SSH, and Nginx security configuration.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx virtual hosts and static content, HTTP-to-HTTPS redirects, TLS 1.2/1.3 and security headers, self-signed certificate creation, Fail2ban, UFW allow rules, SSH root/password-login disabling, sysctl hardening, rate-limit zone definitions.

**CRITICAL PATH VERIFICATION:** All paths above are present in the supplied repository tree, and each cookbook’s `recipes/default.rb` entrypoint was reviewed.

### Infrastructure Files

- `Berksfile`: Declares the Supermarket source, three local cookbook paths, and external Nginx, Memcached, and Redis cookbook constraints. Replace dependency resolution with Ansible collections where appropriate and OS-native package/service management.
- `Policyfile.rb`: Defines the Chef policy run list and repeats local/external cookbook declarations, including `ssl_certificate`. Translate its ordering into the Ansible site playbook and role dependencies.
- `Policyfile.lock.json`: Locks resolved external versions: Memcached 6.1.0, Nginx 12.3.1, Redisio 7.2.4, SELinux 6.2.4 (transitive), and ssl_certificate 2.1.0. Use it as provenance during functional comparison; Ansible should not reproduce obsolete Chef cookbook versions.
- `solo.json`: Chef Solo run list plus Nginx site, TLS path, Fail2ban/UFW, and SSH values. Convert these to inventory/group variables, with environment-specific site definitions and secret references separated from non-secret configuration.
- `solo.rb`: Chef Solo cache, cookbook-path, and logging configuration. Retire after moving to an Ansible inventory, `ansible.cfg`, requirements file, and CI execution method.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, private IP `192.168.121.10`, and HTTP/HTTPS port forwarding. Preserve only if local Ansible test development continues; use the libvirt Vagrant provisioner or a post-boot Ansible invocation.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with an Ansible bootstrap/provisioning path. It uses `apt-get`, which is incompatible with the Fedora box declared by the Vagrantfile.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, TLS directory, and hardening settings; translate into role defaults, allowing environment variables to override them.
- `cookbooks/nginx-multisite/templates/default/*.erb`: Nginx vhost/global-security, Fail2ban, and sysctl templates. Convert to Jinja2 templates and test rendered Nginx syntax before reload.
- `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html`: Static site assets to copy with Ansible.
- `project-plan.md` and `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`: Project/supporting documentation or rules. Review with stakeholders for acceptance criteria, but they do not define deployable Chef modules from the supplied tree.

### Target Details

- **Operating System**: Conflicting source evidence. Cookbook metadata supports Ubuntu 18.04+ and CentOS 7+, and recipes use Debian/Ubuntu conventions (`apt-get`, `ufw`, `www-data`, `/etc/nginx/sites-available`, `libpq-dev`, and a service named `ssh`). The Vagrant box is `generic/fedora42`, where those commands, packages, paths, and service names do not apply. Treat Ubuntu/Debian as the effective intended target until a platform decision is made; do not default to RHEL 9 because the source is explicitly Debian-oriented. If Fedora/RHEL is required, implement a separate tested variable set/tasks for firewalld, SELinux, Nginx include layout, package names, service accounts, and SSH service name.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; the box naming and private network suggest local KVM/libvirt development.
- **Cloud Platform**: Not specified. No cloud provider tooling or metadata integration was found in the reviewed migration-relevant files.

## Migration Approach

Create an Ansible repository with a site playbook and roles such as `baseline_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep site definitions in group variables, use role defaults for portable configuration, and use handlers for daemon reload/restart only after configuration validation. Establish Molecule/Vagrant or equivalent integration tests against the selected OS before retiring Chef.

### Key Dependencies to Address

- **Chef Infra Client/Solo and Berkshelf**: Eliminate runtime Chef installation, Berkshelf vendoring, `solo.rb`, and policy execution. Replace with `ansible-core`, a pinned `collections/requirements.yml` only where modules are needed, inventories, playbooks, and CI lint/test tooling.
- **Chef Policyfile (`nginx-multisite-policy`)**: Replace its ordered run list with a site playbook ordering baseline security, Nginx/TLS/site content, cache services, PostgreSQL, and the FastAPI service, while retaining idempotent dependency relationships via role dependencies and handlers.
- **Chef Supermarket `memcached` 6.1.0**: Use `ansible.builtin.package`, `ansible.builtin.service`, and a managed Memcached configuration only if the desired settings are identified. The reviewed local cookbook only includes it and supplies no Memcached tuning.
- **Chef Supermarket `redisio` 7.2.4**: Replace with OS Redis packages and an explicitly managed Redis configuration/template. Model port, authentication, log directory, daemon settings, and service state directly rather than carrying forward the Chef Ruby text-edit workaround.
- **Chef Supermarket `nginx` 12.3.1**: The local cookbook directly installs and manages Nginx rather than including this dependency. Use native packages plus Jinja2 configuration deployment; assess whether this locked but apparently unused dependency can be removed.
- **Chef Supermarket `ssl_certificate` 2.1.0**: Resolved and listed in the Policyfile but not invoked by the reviewed local recipe, which instead runs OpenSSL directly. Remove it unless another omitted runtime requirement proves it necessary; use `community.crypto` for development self-signed certificates or integrate the approved production PKI/ACME process.
- **Chef Supermarket `selinux` 6.2.4**: A transitive dependency of Redisio. It is relevant only if the chosen target is SELinux-enabled; implement SELinux booleans, contexts, and ports deliberately on RHEL-family systems rather than inheriting this Chef dependency.
- **Git repository `https://github.com/dibanez/fastapi_tutorial.git` (`main`)**: Use `ansible.builtin.git` with a reviewed immutable tag or commit SHA, not the mutable `main` branch. Coordinate ownership of application releases and Python dependency pinning.
- **PostgreSQL/Python/Uvicorn runtime**: Use platform packages, a dedicated non-root application account, `ansible.builtin.pip` using the virtual environment, PostgreSQL modules/commands designed for idempotency, and a managed systemd unit.

### Security Considerations

- **Hardcoded Redis password**: `cache` embeds `redis_secure_password_123` in a node attribute. Store the Redis password in Ansible Vault or an approved external secret manager, render it with restrictive ownership/mode, and rotate it during migration.
- **Hardcoded PostgreSQL and application credentials**: `fastapi-tutorial` creates `fastapi` with password `fastapi_password` and writes it in the application `.env` and database URL. Replace with a generated/managed vaulted secret, avoid command-line password exposure, set the environment file to the application user with mode `0600`, and rotate the database role credential.
- **Application runs as root**: The FastAPI systemd unit specifies `User=root` and the checkout is root-owned. Create a dedicated non-login service account; make the application and environment readable only as necessary; add systemd hardening appropriate to application needs (`NoNewPrivileges`, filesystem restrictions, and capability minimization after testing).
- **TLS certificate handling**: `nginx-multisite` generates 2048-bit RSA self-signed certificates valid for 365 days and stores private keys under `/etc/ssl/private` mode `0710`, group `ssl-cert`; individual keys are mode `0640`. This is acceptable only for development. Use a production CA/ACME or enterprise PKI workflow, Vault/secret-manager delivery where needed, renewal automation, and certificate/key ownership validated against the Nginx worker account.
- **SSH lockout risk**: The configuration disables root login and password authentication with direct `sed` edits. Use `ansible.builtin.lineinfile`/templates with `sshd -t` validation and a handler, verify key-based administrative access before enforcement, and retain a console/break-glass recovery route.
- **Firewall and host hardening**: The source enables UFW default-deny while permitting SSH/HTTP/HTTPS, deploys Fail2ban, and applies sysctl settings. Make rules, trusted management networks, and sysctl values explicit per environment; validate that application/database/cache ports remain private. Use `community.general.ufw` on Ubuntu or firewalld tasks on RHEL-family hosts.
- **Nginx security controls**: Preserve reviewed TLS minimums, HSTS, framing/content-type/referrer/CSP headers, hidden dotfile rules, and server-token suppression. Reassess the CSP’s `unsafe-inline` allowances, header compatibility, and the extremely small 1 KiB request-body/header limits against FastAPI/API requirements before production.
- **Supply-chain controls**: Chef bootstrap is downloaded using `curl | bash`, Berkshelf downloads public Supermarket content, and the application tracks an unpinned Git branch. Replace with pinned Ansible collections, approved repositories, checksum/signature verification where available, and pinned application/Python dependency artifacts.
- **Per-module credential patterns**: `cache` contains a plaintext Redis password; `fastapi-tutorial` contains a plaintext PostgreSQL password and a `.env` database URL; `nginx-multisite` references/generated TLS private keys but contains no external credential. No Chef encrypted data bags, Chef Vault, or environment-variable secret-provider integration was found in the reviewed files.

### Technical Challenges

- **OS/platform contradiction**: Fedora 42/libvirt is declared, but the provisioning script and cookbook implementation assume Ubuntu/Debian. Resolve the supported OS and test matrix before translating tasks; otherwise an Ansible port will reproduce a nonfunctional build.
- **Incomplete/overlapping dependency intent**: Both Berksfile and Policyfile declare external Nginx-related dependencies, while local recipes directly manage Nginx and generate certificates. The lock includes dependencies not clearly invoked. Perform a functional baseline run and remove unneeded dependencies/configuration rather than blindly mapping every lock entry.
- **Configuration drift between defaults and Chef Solo JSON**: Attributes set document roots to `/opt/server/...`, while `solo.json` overrides them with `/var/www/...`; migration must define the intended authoritative inventory/group-variable hierarchy and acceptance paths.
- **Redis workaround**: The cache cookbook mutates an installed Redis configuration by deleting directives after `redisio` writes it. Replace this non-declarative behavior with a complete, version-appropriate Redis template and service validation; determine why those directives were removed before preserving the behavior.
- **Database and app idempotency**: Chef shell commands suppress SQL failures using `|| true`, masking failed or partial database creation. Use PostgreSQL-aware Ansible modules or guarded SQL checks, explicit privilege definitions, and service health checks.
- **Application deployment reproducibility**: The application repository, its Python requirements, schema/migration lifecycle, and desired process model are external to this repository. Pin artifacts, clarify whether database migrations are required, and coordinate release ownership before production rollout.
- **Service exposure and Nginx integration ambiguity**: Nginx serves static files and no reviewed vhost proxies to FastAPI port 8000. Confirm whether FastAPI is intended for direct access, a future reverse proxy, or separate testing; do not invent proxy behavior without stakeholder approval.
- **Team coordination and validation**: Assign an infrastructure owner for platform/security roles, an application owner for FastAPI/PostgreSQL release behavior, and a security owner for firewall/SSH/TLS approval. Document role interfaces and variable schemas, conduct peer reviews, and compare Chef versus Ansible convergence results in disposable VMs before cutover.

### Migration Order

1. **Foundation and baseline verification (priority 1)**: Decide Ubuntu/Debian versus Fedora/RHEL support, build inventory/variable conventions, create the Vagrant/libvirt Ansible test path, and capture expected services, ports, site content, and configuration results from the current intended build.
2. **`nginx-multisite` (priority 2)**: Convert static content, Nginx configuration, certificates, and security hardening into independently testable roles. Validate rendered configuration with `nginx -t`, test UFW/SSH safety, and replace development TLS handling as required.
3. **`cache` (priority 3)**: Migrate Memcached and Redis with a declarative Redis configuration, vaulted authentication, private network binding/firewall rules, and functional cache/service tests.
4. **`fastapi-tutorial` and PostgreSQL (priority 4)**: Introduce a non-root service account, pinned application deployment, vaulted database credentials, idempotent PostgreSQL provisioning, environment-file protection, systemd hardening, and application health validation. Integrate an Nginx proxy only if confirmed as a requirement.
5. **Cutover and decommissioning (priority 5)**: Run parity and security tests, obtain application/security sign-off, deploy Ansible through the chosen CI/CD process, rotate exposed credentials, archive Chef lockfiles for audit evidence, and remove Chef/Berkshelf provisioning after rollback criteria expire.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks because each has `metadata.rb` and `recipes/default.rb` in the supplied tree.
- Chef is the only infrastructure-as-code technology present; no Puppet manifests, Salt states, or PowerShell module/script files were supplied.
- The Policyfile run list represents the desired aggregate deployment order: Nginx/security/sites, cache services, then the FastAPI application.
- Ubuntu/Debian is treated as the intended operating-system family due to concrete command, package, user, firewall, and filesystem conventions, despite the contradictory Fedora 42 Vagrant box. Final target OS/version remains an explicit decision required before implementation.
- The Vagrant/libvirt definition is a development/test environment, not evidence of a production VM platform.
- The three configured DNS names are development/test names and DNS/hosts management is outside the reviewed Chef content; no DNS automation should be added without confirmation.
- Self-signed certificates are development-only because the source explicitly labels them as such; a production certificate authority and renewal ownership are not specified.
- No automated PostgreSQL schema migrations, application health endpoint, process manager beyond systemd/Uvicorn, backup policy, monitoring, log forwarding, or high-availability topology was found in the reviewed files.
- The external application repository and unreviewed `requirements.txt` determine application-level dependencies; their contents, compatibility with Fedora/Ubuntu versions, and release discipline are not established here.
- `ssl_certificate` and `nginx` are included in the Policyfile lock but are not called by the reviewed local cookbook recipes; their runtime necessity must be verified with an actual baseline convergence.
- The existing plaintext passwords are examples/development credentials, but they must be treated as exposed and rotated rather than copied into Ansible variables.
