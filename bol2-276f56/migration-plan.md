# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo infrastructure project with three local cookbooks: an Nginx multi-site/security stack, caching services, and a FastAPI tutorial application with PostgreSQL. The Ansible migration is moderate in operational risk despite the small module count because it includes public-facing TLS, firewall/SSH hardening, Redis credentials, database credentials, service deployment, and OS/distribution inconsistencies. A realistic initial migration is approximately 1–2 weeks for one engineer familiar with Ansible, including testing and security remediation; production hardening and rollout may require an additional 1–2 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server hosting three SSL-enabled virtual sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), with static content, security headers/configuration, fail2ban, UFW, sysctl hardening, and SSH hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Nginx configuration and service management, per-site document roots and symlinks, self-signed RSA certificates for development, fail2ban, UFW default-deny rules, root-login/password-authentication restrictions, and packaged static index pages.

- **cache**:
    - Description: Installs and configures Memcached and Redis, including a Redis listener on port 6379, logging directory creation, authentication, and service enablement.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Inclusion of external Memcached and Redis cookbooks, Redis password configuration, Redis log directory, and a post-generated configuration workaround that removes replication-related directives.

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI tutorial application from GitHub, installs Python and PostgreSQL prerequisites, creates a virtual environment, installs Python dependencies, creates a PostgreSQL database/user, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git checkout of `dibanez/fastapi_tutorial` at `main`, Python venv and pip installation, local PostgreSQL service, application `.env`, database bootstrap, and a root-owned systemd service listening on port 8000.

**CRITICAL PATH VERIFICATION:**
The three module paths above were present in the supplied repository tree and their primary `recipes/default.rb` entrypoints were reviewed. No Puppet, Salt, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef Supermarket and local cookbook dependency declarations. It includes local cookbooks and external `nginx`, `memcached`, and `redisio`; the `ssl_certificate` entry is commented out here.
- `Policyfile.rb`: Chef policy and run list. It also declares `ssl_certificate` and pins the three local cookbooks plus external dependencies.
- `Policyfile.lock.json`: Resolved dependency graph and versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0. It records a dirty local working tree for local cookbooks.
- `solo.rb`: Chef Solo configuration, cookbook paths, cache path, and logging.
- `solo.json`: Chef Solo run list and site/security attributes. Its document roots differ from the cookbook defaults and should be treated as the effective test inventory after verification.
- `Vagrantfile`: Fedora 42 Vagrant VM using libvirt, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and host port forwards for HTTP/HTTPS.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. It uses `apt-get` even though the Vagrant box is Fedora, which is a current provisioning defect or stale platform assumption.
- `project-plan.md`: Project documentation; review during migration for intended behavior, acceptance criteria, and ownership.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site map, TLS paths, and security settings.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, fail2ban, and sysctl configuration templates to convert into Ansible templates.
- `cookbooks/nginx-multisite/files/default/`: Static `index.html` content for the three sites.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource that should be assessed before migration; its use was not required by the reviewed default/central recipes.

### Target Details

- **Operating System**: The cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The Vagrant box is `generic/fedora42`, while `vagrant-provision.sh` assumes Debian/Ubuntu (`apt-get`). Ansible should explicitly support and test one chosen target first—preferably the production OS—and use platform-aware package/service/firewall variables. Do not assume Fedora behavior is equivalent to Ubuntu.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; the VM has 2 CPUs and 2048 MB memory.
- **Cloud Platform**: Not specified. No cloud provider integration is present.

## Migration Approach

Create an Ansible project with separate roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`, plus a site-specific playbook and environment/group variable files. Preserve the Chef run-list dependency order while making dependencies explicit: base packages and security prerequisites, cache/database services, application deployment, then Nginx sites and TLS. Convert Chef templates and static files directly to Jinja2/templates and `ansible.builtin.copy`, replacing shell-heavy Chef resources with idempotent Ansible modules wherever possible.

Use Molecule or equivalent disposable VM testing for the selected OS, and retain a Vagrant/libvirt test path if the team still needs local browser testing. Validate service state, listening ports, virtual-host routing, certificate/key permissions, firewall behavior, SSH access, application health, Redis authentication, and repeatability of a second Ansible run.

### Key Dependencies to Address

- **nginx cookbook 12.3.1**: Replace with an Ansible Nginx role or an internally owned role using package, template, file, and service modules. Reproduce the repository’s custom site layout rather than depending on Chef cookbook conventions.
- **memcached cookbook 6.1.0**: Replace with an Ansible cache role or native package/service tasks; define bind address, port, and exposure explicitly.
- **redisio cookbook 7.2.4**: Replace with a supported Redis role or native tasks/templates. Preserve port and service behavior, but eliminate the post-generation text-edit workaround by owning the Redis configuration template.
- **selinux cookbook 6.2.4**: The lock graph includes it through `redisio`, but reviewed local recipes do not directly configure SELinux. Determine whether enforcing mode, ports, labels, and policy booleans are required on the chosen OS; use `ansible.posix.selinux` and labeling tasks where necessary.
- **ssl_certificate 2.1.0**: Locked by Policyfile but not used in the reviewed local recipes; decide whether to remove it or replace it with managed CA/ACME certificates. Do not carry forward unused dependency behavior.
- **Python 3, pip, venv, Git, PostgreSQL, libpq-dev**: Install with OS-aware Ansible package tasks. Pin application dependencies from the application repository where possible instead of installing an uncontrolled `requirements.txt` from a moving `main` branch.
- **systemd, UFW, fail2ban, OpenSSL, CA certificates**: Use Ansible modules and templates, with distro-specific service names and firewall implementation. UFW is not a safe default assumption on Fedora/RHEL.

### Security Considerations

- **Hardcoded Redis credential**: `cache::default` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and template Redis configuration with restrictive permissions. Avoid exposing it in logs, facts, command arguments, or generated reports.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial::default` creates user `fastapi` with password `fastapi_password` and writes it into `.env` and `DATABASE_URL`. Treat this as compromised test material, rotate it, store it in Vault, and use `community.postgresql` modules with `no_log` where appropriate.
- **TLS certificates and private keys**: The SSL recipe generates self-signed 2048-bit RSA certificates valid for 365 days under `/etc/ssl/certs` and keys under `/etc/ssl/private`. This is explicitly development-oriented and causes browser warnings. Use an approved CA/ACME process for real environments, protect private keys, and define renewal and reload workflows. Confirm certificate SANs for each hostname.
- **SSH hardening**: Root login and password authentication are disabled based on attributes. Implement with `ansible.builtin.lineinfile` or a managed drop-in, validate `sshd -t` before restart, and ensure a tested administrative key/user exists to prevent lockout.
- **Firewall exposure**: UFW is configured default-deny with SSH, HTTP, and HTTPS allowed. Reconcile this with the Fedora target and explicitly restrict Redis, Memcached, PostgreSQL, and application port 8000 to localhost or trusted networks; the current recipes do not show equivalent network restrictions for all services.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Create a dedicated non-privileged service account, restrict the application directory and `.env`, and consider a reverse proxy binding public traffic instead of exposing port 8000 directly.
- **Supply-chain and reproducibility**: Git clones the application from `main`, and pip installs its current requirements. Pin a commit/release and use hashes or a controlled package repository. Review external cookbook provenance and replace obsolete Chef dependencies with maintained Ansible content.
- **Configuration permissions**: Nginx and fail2ban templates are mode 0644; verify that no secrets are embedded. Private key directories and files need least-privilege ownership and modes.

### Technical Challenges

- **OS mismatch**: Fedora 42 is provisioned with `apt-get`, while cookbook support lists Ubuntu/CentOS. Select the supported target and create a compatibility matrix before implementation; otherwise the migration may reproduce a broken lab environment.
- **Chef attribute precedence and divergent paths**: Cookbook defaults use `/opt/server/...`, while `solo.json` uses `/var/www/...`. Build a single Ansible inventory model and confirm which paths are intended before conversion.
- **Template behavior and site data**: The Nginx recipes dynamically iterate over site attributes and derive static file names from hostnames. Model sites as structured variables and test every server name, document root, symlink, redirect, and reload notification.
- **Self-signed certificate lifecycle**: The current `not_if` behavior does not renew certificates. Define development-only generation versus production issuance, SAN requirements, renewal, and safe Nginx reloads.
- **Non-idempotent shell commands**: Database creation uses `psql` commands with `|| true`, and Redis uses direct file manipulation. Replace these with idempotent PostgreSQL and configuration modules, with migration handling for already-existing installations.
- **Service ordering and readiness**: PostgreSQL must be available before database creation, Redis must be configured before dependent applications, and systemd must be reloaded after unit changes. Express these with handlers, `become`, and readiness checks.
- **Firewall implementation**: UFW tasks will not translate directly to Fedora. Use the selected platform’s supported firewall modules and test lockout/recovery procedures.
- **External application contract**: The repository does not include the FastAPI source; its branch, requirements, application module, and expected health endpoint are external dependencies. Establish an artifact/version ownership agreement with the application team.

### Migration Order

1. **Foundation and test harness**: Decide the target OS, inventory structure, privilege model, Vault integration, Molecule/Vagrant testing, and acceptance checks. Correct the existing Fedora/`apt-get` ambiguity first.
2. **cache**: Migrate Memcached and Redis with secret handling and explicit bind/firewall rules. It is relatively isolated but provides an early test of external-role replacement and service idempotency.
3. **fastapi-tutorial**: Deploy packages, PostgreSQL, application artifact, venv, non-root systemd service, database schema/user, and environment secrets. Validate application health independently.
4. **nginx-multisite security layer**: Implement SSH, firewall, sysctl, fail2ban, and Nginx base configuration with safe validation and rollback.
5. **nginx-multisite sites and TLS**: Convert virtual hosts, static files, certificate management, and reload handlers; test all three hostnames and forwarded/local access paths.
6. **Cutover and decommissioning**: Run Chef and Ansible in a controlled comparison window, document drift, perform staged replacement, and retire Berkshelf/Policyfile/Chef provisioning only after rollback criteria are met.

### Assumptions

- The source technology is Chef/Chef Solo, not Puppet, Salt, or PowerShell.
- The three local cookbook directories are the complete migration module inventory.
- The Policyfile lock is authoritative for resolved external cookbook versions, although Berksfile and Policyfile declarations differ for `ssl_certificate`.
- `solo.json` is intended to override cookbook defaults, but the conflicting document-root paths require owner confirmation.
- The Vagrant Fedora 42 box represents a development target, not necessarily production; production OS, hostnames, DNS, and cloud placement are unspecified.
- The `cluster.local` names are test names and may require local DNS or `/etc/hosts`; the commented Vagrant host entries are not active.
- The FastAPI GitHub repository and its `main` branch are available and compatible with the target Python/PostgreSQL versions.
- PostgreSQL is intended to run locally on the same host; HA, backups, migrations, and production database operations are out of scope until confirmed.
- Redis replication is not required; the recipe explicitly removes several replication directives, but the intended cache topology is undocumented.
- Memcached and Redis should not be publicly reachable, although exact application bind requirements are not documented.
- Self-signed certificates are acceptable only for development; production certificate authority, DNS validation, and renewal ownership are not supplied.
- No secrets backend, SSH key provisioning process, monitoring, backups, CI pipeline, or rollback procedure is shown.
- The custom `lineinfile` resource and all templates not read in detail may contain additional behavior that must be checked during implementation if they are invoked by omitted recipes.
- The migration estimate assumes one environment and three roles; multiple environments, compliance controls, HA, or production-grade certificate/database operations will increase scope.

Team coordination should assign separate owners for platform/OS compatibility, security and secrets, application/PostgreSQL, Nginx/TLS, and test/cutover. Agree on variable names and service ownership early, review Vault changes through security, and require a documented rollback and SSH recovery test before applying the hardening role broadly.
