# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile estate containing three local Chef cookbooks, executed in the order **nginx-multisite**, **cache**, and **fastapi-tutorial**. It provisions a single-host development-style web stack: hardened Nginx serving three TLS virtual hosts, Memcached and password-protected Redis, plus a FastAPI application backed by a local PostgreSQL database. The source is compact, but migration complexity is **moderate** because it combines OS hardening, firewall enforcement, TLS private-key lifecycle, third-party cookbook behavior, and an application/database deployment with exposed hardcoded credentials.

A two-engineer implementation with platform/security review is realistically **2–4 weeks**: approximately one week for discovery and target-baseline decisions, one to two weeks to implement and test roles, and up to one week for security remediation, acceptance testing, and cutover documentation. The schedule depends on resolving the OS inconsistency and deciding how certificates and secrets will be supplied in the target environment.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs Memcached and configures a Redis server on port 6379, creates Redis logging storage, enables Redis, and post-processes the generated Redis configuration to remove several replication-related directives.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis authentication; Redis log directory ownership; Redis service enablement; imperative cleanup of replication/client-buffer configuration lines.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` Git application into `/opt/fastapi-tutorial`, builds a Python virtual environment, installs the application's Python requirements, runs a local PostgreSQL service, creates an application database/user, writes application environment settings, and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3 and PostgreSQL package installation; Git checkout of the `main` branch; pip requirements installation; local PostgreSQL database provisioning; `.env` generation; persistent root-run systemd application service.

- **nginx-multisite**:
  - Description: Builds a security-hardened Nginx static multi-site host for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It configures Nginx, site content and virtual-host files, locally generated self-signed TLS certificates, Fail2ban, UFW, kernel network hardening, and SSH access restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Three TLS-enabled virtual hosts and HTTP-to-HTTPS redirects; Nginx security headers/rate-limit zones/TLS configuration; static index files; self-signed RSA-2048 certificates; Fail2ban jails; default-deny UFW with SSH/HTTP/HTTPS allowed; SSH root-login and password-authentication disablement; sysctl security configuration.

**CRITICAL PATH VERIFICATION:** All module paths above were present in the supplied repository tree, and each description is based on its Chef metadata and primary/default recipe (with the four recipes invoked by `nginx-multisite::default` reviewed to establish that module's scope).

### Infrastructure Files

- `Berksfile`: Declares the Chef Supermarket source, the three local cookbooks, and external Nginx, Memcached, and Redis cookbooks. Replace Berkshelf resolution with pinned Ansible collection/role requirements and documented OS package versions.
- `Policyfile.rb`: Defines the authoritative Chef run list and externally requested cookbook constraints, including `nginx`, `ssl_certificate`, `memcached`, and `redisio`. Translate its run order into a top-level Ansible playbook with explicit role dependencies.
- `Policyfile.lock.json`: Locks the tested Chef dependency set: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SSL Certificate 2.1.0, and transitive Selinux 6.2.4. It is the best source for reproducing behavior and recording the Chef baseline; it is not itself consumed by Ansible.
- `solo.rb`: Chef Solo configuration defining cookbook search paths and logging. Replace with an Ansible project configuration, inventories, `requirements.yml`, and CI lint/test configuration.
- `solo.json`: Chef node data/run list that overrides the cookbook default web roots to `/var/www/...`, declares certificate paths, and enables security controls. Convert this to environment/group variables; reconcile it with cookbook defaults before migration.
- `Vagrantfile`: Defines a `generic/fedora42` Vagrant guest, Libvirt provider, 2 GB RAM/2 CPUs, private address `192.168.121.10`, and host forwarding for ports 80/443. Retain only as a local Ansible test target after reconciling OS-specific behavior.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef via Omnitruck, vendors Berkshelf cookbooks, and invokes Chef Solo. Replace it with a minimal Ansible bootstrap/provisioner; it currently conflicts with the Fedora Vagrant box.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, TLS-path, firewall, Fail2ban, and SSH-hardening variables. Convert to role defaults and environment-specific overrides.
- `cookbooks/nginx-multisite/templates/default/*.erb`: Nginx global, security, vhost, Fail2ban, and sysctl templates. Convert to Jinja2 templates and validate rendered Nginx/Fail2ban/sysctl syntax in CI.
- `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html`: Static per-site web content. Manage as role files or application-content artifacts with explicit ownership and deployment policy.
- `project-plan.md`: Documentation for an X2Ansible migration-tool concept, not active provisioning input. It can inform workflow discussions but should not be treated as deployed infrastructure.

### Target Details

- **Operating System**: The Chef cookbook metadata claims Ubuntu 18.04+ and CentOS 7+, but the implemented resources are predominantly Debian/Ubuntu-specific: `apt-get`, UFW, service name `ssh`, `/var/log/auth.log`, Nginx `sites-available/sites-enabled`, and owner/group `www-data`. Conversely, `Vagrantfile` selects Fedora 42, where these assumptions do not hold. The target OS must be selected before implementation. Recommended baseline for behavior parity is a supported Ubuntu LTS release; create an OS abstraction only if Red Hat-family support is an explicit requirement. RHEL 9 is not assumed because the source provides materially incompatible Debian-specific configuration.
- **Virtual Machine Technology**: Vagrant with the Libvirt provider (typically KVM/QEMU) is explicitly configured for local testing.
- **Cloud Platform**: Not specified. No cloud-provider tooling, metadata endpoints, or cloud configuration is present.

## Migration Approach

Establish a conventional Ansible repository with a top-level playbook, inventories for development/test/production, and roles such as `baseline_security`, `nginx_multisite`, `cache`, and `fastapi_tutorial`. Use role defaults for portable settings and group/host variables for site lists, hostnames, network policy, and non-secret environment parameters. Pin collection versions in `collections/requirements.yml`, use `ansible-lint`, Molecule or a Vagrant/Libvirt test scenario, and staged idempotence tests. Build and validate roles independently, then integrate them in the Chef Policyfile order after service dependency checks.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Retire Chef bootstrap, Solo configuration, Berkshelf vendoring, and Policyfile execution. Replace with Ansible Core, SSH/WinRM-free Linux inventory access as applicable, a version-pinned execution environment or controller virtual environment, and standard playbook runs.
- **Chef Supermarket `nginx` (locked 12.3.1)**: Replace with direct package management plus managed Jinja2 templates, `ansible.builtin.template`, `service`, and `command`/`nginx -t` validation. The local cookbook installs Nginx directly and does not visibly include the external `nginx` recipe, so confirm whether the dependency is legacy before reproducing it.
- **Chef Supermarket `memcached` (locked 6.1.0)**: Replace `include_recipe 'memcached'` with OS package installation, explicit configuration if required, and enabled/started service management. The reviewed local recipe does not specify Memcached configuration, so capture the effective Chef-generated configuration from a reference node before cutover.
- **Chef Supermarket `redisio` (locked 7.2.4)**: Replace with distribution Redis packages and a fully managed Redis configuration/template, enforcing port, authentication, log path, service state, and any desired replication settings. Do not reproduce the Chef `ruby_block` text deletion; model the intended final Redis configuration declaratively.
- **Chef Supermarket `ssl_certificate` (locked 2.1.0)**: It is declared/locked but is not visibly invoked by the local recipes reviewed. Determine whether it is unused or required indirectly. Replace development self-signed generation with `community.crypto` modules or, preferably, an enterprise certificate/ACME/PKI workflow.
- **Chef Supermarket `selinux` (locked 6.2.4)**: Transitive dependency of `redisio`; no local SELinux resources were found. On a Red Hat target, explicitly define SELinux mode, port labeling, file contexts, and firewall policy rather than relying on transitive Chef behavior. It is not needed for Ubuntu parity.
- **Python/FastAPI application dependencies**: The requirements file is cloned from a remote repository at deployment time and was not part of this repository. Pin the Git revision to a reviewed immutable tag/commit and lock Python dependencies with hashes or a vetted artifact repository. Use `ansible.builtin.pip` with a virtual environment rather than unconditional shell pip installation.
- **PostgreSQL**: Replace shell `psql` operations with `community.postgresql.postgresql_user`, `postgresql_db`, and privilege modules, executed with appropriate PostgreSQL administrative access. Confirm PostgreSQL major version, authentication method, extensions, backups, and schema migrations; none are defined here.
- **OpenSSL, Fail2ban, UFW, and sysctl**: Use OS-specific package tasks and declarative modules (`community.crypto`, `community.general.ufw`, `ansible.posix.sysctl`) on Ubuntu. Map to `firewalld` and distribution-specific SSH/Fail2ban locations only if supporting Red Hat targets.
- **GitHub repository `https://github.com/dibanez/fastapi_tutorial.git`**: Treat as a supply-chain dependency. Define authentication/proxy requirements, immutable revision, availability strategy, and ownership/release process before production migration.

### Security Considerations

- **Hardcoded Redis password in `cache`**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Remove it from source history where feasible, rotate it, store its replacement in Ansible Vault or an approved external secrets manager, render Redis configuration with restrictive permissions, and prevent secret output with `no_log` where applicable.
- **Hardcoded PostgreSQL/application credentials in `fastapi-tutorial`**: The `fastapi` database password and `DATABASE_URL` containing that password are in the default recipe and are written to `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate the credentials, use Ansible Vault/external secret lookup, create a least-privilege database role, and make the environment file readable only by the non-root application account/service group (normally `0600` or equivalent).
- **TLS certificates and private keys in `nginx-multisite`**: The module creates self-signed, 365-day RSA-2048 private keys under `/etc/ssl/private`, assigned `root:ssl-cert` with mode `0640`. Preserve protected private-key permissions but replace self-signed development certificates before production with centrally issued certificates, automated renewal, expiry monitoring, and a documented reload handler. Certificate subject values are hardcoded example data and must be environment variables.
- **SSH hardening in `nginx-multisite`**: Root login and password authentication are disabled by in-place `sed`. Implement with a managed SSH drop-in where supported, validation (`sshd -t`), a rollback/break-glass plan, and confirmation that key-based administrative access exists before applying it. The service is named `ssh`, which needs OS-specific mapping.
- **Host firewall and Fail2ban in `nginx-multisite`**: UFW sets default deny and opens only 22/80/443, while Fail2ban protects SSH and Nginx patterns. Apply firewall changes only through staged inventory groups/console access to avoid lockout; parameterize management networks and required application/monitoring ports. Validate logs and filters because `/var/log/auth.log` is Ubuntu-specific.
- **Nginx web security**: Preserve the configured TLS 1.2/1.3, HSTS, anti-framing/content-type/referrer/CSP headers, server-token suppression, and sensitive dotfile denial after reviewing their compatibility with the actual FastAPI application. The CSP permits `unsafe-inline` for scripts/styles and should be tightened if application requirements permit. The configured rate-limit zones exist, but the reviewed templates do not show `limit_req` use in locations; verify intended enforcement rather than assuming it is active.
- **Application privilege**: The FastAPI systemd unit runs as `root`, which is inappropriate for a web application. Create a dedicated non-login service account, restrict application, `.env`, and log ownership, and consider systemd sandboxing options (`NoNewPrivileges`, filesystem protections, capability restrictions).
- **Supply chain and remote execution**: The current bootstrap pipes a remote Chef installer to Bash and deploys the moving `main` branch from GitHub. Eliminate both patterns: pin/package Ansible dependencies and application source, verify artifacts, and use controlled repositories.
- **Credentials summary by module**: `cache` contains a Redis password; `fastapi-tutorial` contains a PostgreSQL password and a database URL embedding it; `nginx-multisite` manages TLS certificate/private-key material but contains no credential value. No Chef encrypted data bags, Chef Vault usage, or external secret-management integration is visible in the reviewed files.

### Technical Challenges

- **Contradictory operating-system assumptions**: Fedora 42 is selected in Vagrant, while bootstrap and most configuration target Ubuntu/Debian; metadata also claims CentOS support. Select the supported target first and test from a clean image. If multi-OS support is required, isolate package names, service names, firewall, Nginx layout, user/group, log paths, and PostgreSQL behavior using per-OS variable files.
- **Configuration drift between attributes and node JSON**: Nginx cookbook defaults use `/opt/server/{site}`, while `solo.json` changes web roots to `/var/www/{site}`. Establish an approved configuration matrix and source of truth before translating defaults/overrides to Ansible inventory variables.
- **Opaque third-party Chef cookbook behavior**: Memcached and Redis behavior depends on external cookbooks, and Redis is subsequently altered by an imperative Ruby text edit. Baseline package versions, rendered `/etc/redis/6379.conf`, service units, ports, and effective Memcached configuration on a Chef-provisioned reference VM before implementing Ansible roles.
- **Application deployment is not fully reproducible from this repository**: FastAPI requirements, runtime interface, migrations, and desired production revision reside in an external Git repository. Coordinate with application owners to provide a release artifact, immutable version, database migration procedure, health endpoint, and rollback plan.
- **Nginx and TLS validation**: The Nginx role must safely render three dependent configuration layers, remove the default site, provision static content, and activate certificates before reload. Use handler notifications only after `nginx -t`; test HTTP redirects, TLS chains, headers, content, and virtual-host resolution.
- **Stateful database/caches**: Chef setup creates a database/user but does not define backups, data migration, Redis persistence, cache sizing, access binding, or network segmentation. Treat data retention, backup/recovery, and exposure of ports 5432/6379/11211 as explicit target design decisions, not automatic parity items.
- **Team coordination and acceptance**: Assign a platform engineer to common OS/service roles, a security engineer to SSH/firewall/TLS controls, and an application/database owner to FastAPI/PostgreSQL validation. Use a shared parity checklist, peer review of secret handling, a tested staging environment, and documented cutover/rollback ownership.

### Migration Order

1. **Foundation and baseline security (from nginx-multisite)**: Decide Ubuntu-versus-multi-OS scope; build inventory, variables, secret backend, package baseline, dedicated service identities, SSH safeguards, sysctl, Fail2ban, and firewall with console-access rollback testing. This creates the secure, testable host foundation.
2. **Nginx multi-site and TLS (nginx-multisite)**: Implement Nginx configuration, static content, virtual hosts, validated handlers, and production certificate integration. Verify network ingress, redirects, headers, and all three hostnames before application exposure.
3. **Cache services (cache)**: Implement and test Memcached and Redis declaratively; rotate/protect Redis credentials and confirm service bind addresses, persistence requirements, and compatibility with the application. Complete this before application integration if the FastAPI application consumes either cache.
4. **FastAPI and PostgreSQL (fastapi-tutorial)**: Implement the dedicated application account, immutable application release, virtual environment, PostgreSQL role/database, protected environment configuration, systemd hardening, application migrations, and health checks. Conduct end-to-end functional, security, and rollback tests.
5. **Integrated cutover and Chef retirement**: Run Ansible in staging and production change windows, compare effective configuration to the Chef reference, monitor services/logs/certificates, archive Policyfile evidence, and remove Chef/Berkshelf bootstrap only after acceptance.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks because they are the only cookbook directories shown in the supplied tree.
- No Puppet manifests, Salt states, or PowerShell modules/scripts are present in the provided tree; Chef is the sole active infrastructure-as-code technology.
- `Policyfile.rb` and `Policyfile.lock.json` are treated as the intended dependency/run-list baseline; the lock file is more precise for external cookbook versions.
- `ssl_certificate` is declared in the Policyfile and lock but is not directly included in the reviewed local recipes; its actual need must be confirmed from a Chef reference run before excluding it.
- The Vagrant environment is a development/test harness, not proof of the production VM platform, IP plan, DNS, or operating system.
- The target is assumed to be a single host because all services are locally installed and the only Vagrant guest is one VM. Separating database, cache, and web/application tiers would be an architectural change requiring separate design.
- The Nginx sites are intended to serve static content as shown; no reverse proxy from Nginx to FastAPI is configured in the reviewed templates. The FastAPI service listens directly on port 8000, and desired ingress/exposure must be clarified.
- The source's self-signed certificates are development-only based on the provisioning-script warning; a production certificate authority and renewal ownership are not specified.
- PostgreSQL version, database schema migration process, backup/restore policy, Redis persistence/bind settings, Memcached tuning, monitoring, and logging retention are not defined in the reviewed source and require design decisions.
- The `fastapi_tutorial` Git repository, its `main` branch, and its `requirements.txt` are reachable and compatible with the selected target Python/OS only in the current development context; immutable releases and dependency controls are required for production.
- Existing hardcoded passwords are examples or active credentials of unknown status. They must be considered compromised for migration planning and rotated rather than copied into Ansible variables.
