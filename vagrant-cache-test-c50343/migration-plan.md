# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/local-mode demonstration environment containing three local cookbooks, orchestrated by a Policyfile and also runnable through Berkshelf. It provisions a Fedora 42 Vagrant/libvirt VM with hardened NGINX hosting three TLS-enabled static sites, Redis and Memcached caching services, and a FastAPI tutorial application backed by local PostgreSQL. Migration complexity is **moderate**: the resource types map well to Ansible, but cross-platform differences, imperative Chef workarounds, certificate handling, firewall compatibility, and exposed credentials require design changes rather than a literal translation. A small team can create and validate an initial Ansible role collection and Vagrant-compatible playbook in approximately **3–5 weeks**, including security remediation and acceptance testing.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Installs and enables NGINX, configures global and security configuration files, and serves static content for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It creates NGINX site definitions/symlinks, development self-signed TLS certificates, Fail2ban configuration, UFW rules, sysctl hardening, and SSH root/password-authentication restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Three attribute-driven virtual hosts; static site assets; TLS certificate/key generation; NGINX reload notification flow; Fail2ban; UFW default-deny policy with SSH/HTTP/HTTPS access; SSH and kernel-network hardening.

- **cache**:
  - Description: Installs/configures Memcached and Redis, enables Redis, configures Redis on port 6379 with authentication, ensures the Redis log directory, and applies an imperative post-processing workaround to remove selected replication-related Redis configuration lines.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis service configuration and enablement; Redis PID directory override for Fedora/SELinux path conventions; Redis log directory; configuration mutation workaround.

- **fastapi-tutorial**:
  - Description: Installs Python, Git, PostgreSQL, and build/client packages; clones the `dibanez/fastapi_tutorial` GitHub repository; creates a virtual environment; installs Python requirements; initializes PostgreSQL on RHEL/Fedora; creates a PostgreSQL database/user; writes application environment settings; and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Debian-family versus RHEL/Fedora package branching; Git application deployment from the `main` branch; local PostgreSQL database provisioning; Python virtualenv/pip dependency installation; systemd service lifecycle.

**CRITICAL PATH VERIFICATION:** All inventory paths above were present in the supplied repository tree. No Puppet modules, Salt states, PowerShell modules, or DSC configurations were identified.

### Infrastructure Files

- `Berksfile`: Defines Chef Supermarket source, local cookbook paths, and external cookbook constraints. It represents the legacy dependency-resolution path; Ansible dependencies should instead be captured in `requirements.yml`, Python collections/environment documentation, and role metadata as applicable.
- `Policyfile.rb`: Declares the `chef-examples` policy and the intended run list: `nginx-multisite`, `cache`, then `fastapi-tutorial`. Use this as the initial Ansible play/role ordering baseline.
- `Policyfile.local.json`: Locked Chef dependency snapshot. It resolves `memcached` 6.1.0, `redisio` 8.0.0, and transitive `selinux` 6.2.4; it is useful as migration evidence but is not an Ansible runtime input.
- `solo.rb`: Chef Solo local-mode paths and logging configuration. Replace with Ansible inventory, `ansible.cfg`, playbook configuration, privilege escalation, and logging/CI conventions.
- `solo.json`: Chef run list and environment-specific configuration for virtual hosts, certificate paths, Fail2ban/UFW, and SSH hardening. Convert these values into documented Ansible inventory/group variables, with environment-specific overrides.
- `Vagrantfile`: Defines the development target as `jtarpley/fedora42_base`, private address `192.168.121.10`, forwarded ports 80/443 to 8080/8443, and the libvirt provider. Retain or replace with an Ansible provisioner for repeatable developer validation.
- `vagrant-provision.sh`: Bootstraps Ruby, Chef 18.8.54, and Berkshelf, vendors cookbooks, and invokes Chef Solo. Replace with an Ansible bootstrap/provisioning path; no Chef client, Chef license acceptance, or Berkshelf installation should be required after cutover.
- `cookbooks/nginx-multisite/templates/`: Chef ERB templates for NGINX, site definitions, security controls, sysctl, and Fail2ban. Convert to Ansible Jinja2 templates while preserving reviewed configuration intent and validating generated syntax.
- `cookbooks/nginx-multisite/files/default/`: Static HTML assets for the three defined sites. Migrate with Ansible `copy` or `template` tasks and preserve ownership/permissions.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: A custom Chef resource exists but was not invoked by the reviewed default recipe chain. Assess its actual use before declaring it out of scope; use Ansible `lineinfile` only if a comparable requirement remains.
- `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`: Supplemental repository documentation/rules file. Review during implementation for project-specific conversion or validation rules; its contents were not required to establish cookbook inventory.

### Target Details

- **Operating System**: The active Vagrant configuration explicitly uses Fedora 42. Cookbook metadata also declares support for Ubuntu 18.04+ and CentOS 7+, and recipes branch between RHEL/Fedora and other package families. The first Ansible target should therefore be Fedora 42; support for Ubuntu and CentOS/RHEL must be explicitly tested rather than assumed.
- **Virtual Machine Technology**: Vagrant with the libvirt provider. The box and use of a private `192.168.121.x` address indicate local KVM/libvirt-oriented development.
- **Cloud Platform**: Not specified. No cloud provider tools, metadata endpoints, or cloud resource definitions were identified.

## Migration Approach

Create an Ansible collection or repository layout with separate roles matching the cookbook boundaries: `nginx_multisite`, `cache`, and `fastapi_tutorial`. Use a top-level playbook to preserve the Policyfile run order, group variables to replace `solo.json`/attributes, and a Fedora-specific variable map with supported-platform conditionals. Implement idempotent package, template, file, database, service, firewall, and certificate tasks. Build automated validation around NGINX configuration, service state, endpoint reachability, TLS, PostgreSQL connectivity, Redis authentication, and SSH access before decommissioning Chef.

Coordinate work through a shared variable contract: the platform/security owner should define firewall and hardening standards; application/database owners should approve application revisions, schema/bootstrap behavior, and credentials; and operations should own CI, inventory, release promotion, and rollback. Maintain a side-by-side validation period on disposable Vagrant/libvirt machines before applying the roles to persistent systems.

### Key Dependencies to Address

- **Chef Client 18.8.54 / Chef Solo / Berkshelf**: Remove the Chef bootstrap and local vendoring workflow. Use `ansible-core`, a pinned execution environment or Python virtual environment, `ansible-lint`, and a documented `requirements.yml` only for required collections.
- **Chef Supermarket `memcached` (~> 6.0; lock 6.1.0)**: Replace with native Ansible package/service tasks. Identify Fedora package/service names and set configuration explicitly if the previous cookbook applied defaults not visible in this repository.
- **Chef Supermarket `redisio` (~> 7.2.4 in Berksfile; lock 8.0.0) and transitive `selinux` (6.2.4)**: Replace with native Redis packages/services and Ansible SELinux modules (`ansible.posix.selinux`, `community.general.sefcontext`/`restorecon` where needed). Reconcile the declared versus locked Redis constraint before setting the target Redis version.
- **Chef Supermarket `nginx` (~> 12.0)**: It is declared in `Berksfile` but is not present in the policy lock or listed as a local cookbook dependency. The reviewed NGINX cookbook installs the OS package directly. Do not add an Ansible Galaxy NGINX dependency unless template/configuration review shows a real need.
- **PostgreSQL**: Replace shell SQL with idempotent database tasks, normally `community.postgresql.postgresql_user`, `postgresql_db`, and `postgresql_privs`, executed with appropriate PostgreSQL OS privileges. Install the matching Python PostgreSQL driver in the Ansible execution/target context as required.
- **GitHub `https://github.com/dibanez/fastapi_tutorial.git`**: Pin to a reviewed commit or release rather than the moving `main` branch. Define source verification, network/proxy requirements, and dependency artifact strategy.
- **Python/pip application requirements**: Build the virtual environment with `ansible.builtin.pip` and a pinned requirements lock if available. Validate package build prerequisites by OS family.
- **OpenSSL / local self-signed certificates**: Use `community.crypto` for idempotent development certificate/key generation, or integrate the organization’s certificate authority for non-development environments.
- **UFW and Fail2ban**: The source applies UFW commands while the primary target is Fedora 42, where firewalld is the conventional firewall and UFW availability/behavior must be verified. Use `ansible.posix.firewalld` for Fedora unless a deliberate UFW standard is approved; manage Fail2ban with packages, templates, and services.

### Security Considerations

- **Hardcoded Redis credential in `cache`**: `redis_secure_password_123` is embedded in the Chef recipe. Move it to Ansible Vault or an external secrets manager, rotate it during migration, ensure the Redis configuration and client consumers receive the rotated secret, and use `no_log` for secret-bearing tasks.
- **Hardcoded PostgreSQL/application credential in `fastapi-tutorial`**: `fastapi_password` is embedded in SQL and in `/opt/fastapi-tutorial/.env`. Move it to Vault/external secret management, rotate it, limit `.env` to the application account (not mode `0644`), and prevent it from appearing in logs or CI artifacts.
- **Vault/secrets management**: `nginx-multisite` references local TLS certificate/key paths and generates self-signed private keys; there are no Chef encrypted data bags or Chef Vault references in the reviewed files. Store production private keys and database/Redis secrets outside source control, use per-environment secret variables, and document rotation/backup ownership. The FastAPI systemd service currently runs as `root`; create and use a dedicated non-login service account with restricted file access.
- **TLS posture**: The source intentionally creates 365-day, RSA-2048, self-signed certificates and Vagrant warns of browser certificate warnings. Retain only for isolated development; use CA-issued certificates, renewal automation, key permission enforcement, and reviewed NGINX TLS settings for production.
- **Network exposure**: The FastAPI Uvicorn service binds to `0.0.0.0:8000`, while the firewall permits only SSH, HTTP, and HTTPS. Confirm whether port 8000 must remain internal behind NGINX and enforce the intended binding/firewall policy. Limit forwarded Vagrant ports to development needs.
- **Host hardening safety**: Disabling SSH root login and password authentication can lock out administrators if managed-key access is not established first. In Ansible, validate an authorized non-root administrative access path before changing `sshd_config`, use `validate`/syntax checks, and restart only after successful validation.
- **Firewall compatibility and change safety**: A default-deny firewall must preserve approved management access, existing remote automation access, and required service ports. Stage firewall changes with a console/recovery path and platform-specific tests.
- **Supply-chain controls**: The migration should pin Git revisions and Python dependencies and define trusted package repositories. The current implementation downloads Chef gems, Supermarket cookbooks, a Git branch, and pip dependencies at provisioning time.

### Technical Challenges

- **OS-family inconsistency**: Fedora 42 is the actual Vagrant target, yet cookbook metadata claims Ubuntu and CentOS support and the code uses UFW plus service/package assumptions that may not be portable. Create tested Fedora-first task files and separate Debian/RHEL-family mappings; treat CentOS 7 support as a business decision because it is end-of-life.
- **Chef attribute precedence to Ansible variables**: Site and security settings occur both in cookbook attributes and `solo.json`, with `solo.json` values overriding document roots. Establish explicit variable precedence and an environment variable schema so Ansible does not silently deploy different roots or security settings.
- **Imperative/non-idempotent shell logic**: The cache cookbook edits Redis configuration with a Ruby block, and the application cookbook uses SQL commands with `|| true`. Replace these with managed configuration templates/structured Ansible modules and verification, so errors are not suppressed and repeat runs converge predictably.
- **Application lifecycle ambiguity**: The source pulls an external tutorial application without a pinned revision, does not show a reverse-proxy upstream in the reviewed recipes, and runs Uvicorn as root. Confirm application configuration, expected NGINX proxy behavior, ownership, health endpoint, migrations, and deployment/restart strategy with the application team.
- **NGINX template conversion and validation**: Multiple ERB templates define NGINX and hardening behavior. Convert them to Jinja2 and use `nginx -t` prior to reload. Preserve handler semantics so changes are batched and services are reloaded only when valid configuration changed.
- **SELinux and filesystem labeling**: Redis explicitly changes the PID directory to `/run/redis` because of Fedora/SELinux behavior. Validate file contexts, ports, and service access under enforcing SELinux rather than disabling enforcement; codify any required labels/booleans.
- **Database initialization differences**: The Chef recipe invokes `postgresql-setup --initdb` only for RHEL/Fedora and assumes `postgresql` as the service name. Make versioned PostgreSQL paths/service names configurable and test clean-host bootstrap and repeatability.

### Migration Order

1. **Foundation and configuration contract**: Establish Ansible repository/collection structure, inventory, encrypted secrets, Fedora 42 Vagrant/libvirt provisioning, CI linting, Molecule or equivalent test strategy, and group variables translated from `solo.json`. Confirm administration access and the firewall standard before host hardening.
2. **nginx-multisite**: Migrate NGINX packages, static content, templated virtual hosts, development TLS, and service handlers. Then implement and validate the platform-appropriate firewall, Fail2ban, sysctl, and SSH hardening with a safe access rollback plan.
3. **cache**: Migrate Memcached and Redis using native packages/services, managed Redis configuration, SELinux handling, encrypted Redis authentication, and functional authentication tests. Remove the Chef configuration-text workaround by defining desired Redis settings directly.
4. **fastapi-tutorial**: Migrate PostgreSQL initialization and idempotent user/database provisioning, application checkout at a pinned revision, virtualenv dependencies, secret environment file, unprivileged systemd unit, and application health/reverse-proxy integration tests.
5. **Integrated acceptance and Chef retirement**: Run the complete playbook repeatedly on a fresh Fedora VM, test all sites/TLS/services and hardening controls, compare intended behavior to the Chef deployment, document operations, and remove Chef/Berkshelf bootstrap dependencies only after sign-off.

### Assumptions

- The supplied tree is complete; no additional Chef cookbooks, roles, environments, data bags, Test Kitchen configuration, or remote Chef Server policy sources are in scope.
- Chef is the only source configuration technology present; no Puppet, Salt, PowerShell, or DSC modules were identified.
- The Policyfile and `solo.json` run lists represent the intended deployment scope and ordering.
- Fedora 42 Vagrant/libvirt is the primary initial migration target. Ubuntu and CentOS/RHEL compatibility is desired by cookbook metadata but has not been validated from the reviewed configuration.
- The NGINX certificate generation is intended for development/test only. Production certificate issuance, DNS ownership, and renewal requirements are not specified.
- The three `cluster.local` virtual-host names and their static content are development/test identifiers; DNS/hosts-file management is outside the active provisioning because the Vagrant host-entry block is commented out.
- It is not confirmed whether NGINX should proxy traffic to the FastAPI service; the reviewed NGINX recipe clearly creates static sites, while FastAPI listens on port 8000 independently.
- The required persistence, backup, replication, monitoring, and recovery policy for PostgreSQL, Redis, and Memcached is not defined in the reviewed source and must be agreed before production migration.
- Redis and PostgreSQL credentials found in source are insecure example values and can be rotated without an unrecorded external consumer dependency; confirm consumers before rotation.
- The custom Chef `lineinfile` resource may be unused in the current run list; its usage must be searched/confirmed during implementation before it is omitted.
- Exact package versions, PostgreSQL version, application Python dependency versions, network egress controls, and organizational CA/secrets-manager choices are not specified and require architecture decisions.
