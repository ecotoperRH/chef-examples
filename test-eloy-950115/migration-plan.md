# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks: a multi-site Nginx edge service, cache services (Memcached and Redis), and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in risk despite the small module count because the source mixes development VM assumptions, Ubuntu/Debian commands, Fedora Vagrant packaging, hardcoded credentials, self-signed TLS generation, firewall/SSH hardening, and imperative configuration edits. A focused team should be able to produce an initial Ansible implementation in approximately 1–2 weeks, with another 1–2 weeks for target-OS decisions, security remediation, integration testing, and cutover. This estimate assumes no production-only behavior is hidden outside the reviewed repository.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and runs Nginx as a three-site web server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, with per-site document roots, static landing pages, TLS configuration, and Nginx security settings.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx package and service management, generated virtual hosts, enabled-site symlinks, default-site removal, site-specific static files, self-signed RSA certificates, Fail2ban, UFW, SSH hardening, and sysctl security configuration.
    - Migration complexity: High relative to the repository because it combines web-server templating, certificates, firewall policy, SSH changes, service handlers, and OS-specific assumptions.

- **cache**:
    - Description: Configures Memcached and Redis as local caching services, including Redis authentication, log-directory creation, service enablement, and a post-install workaround that edits generated Redis configuration.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Inclusion of the external Memcached cookbook, Redisio integration, Redis password configuration, Redis log directory, and imperative removal of replication-related Redis directives.
    - Migration complexity: Moderate; service installation is straightforward, but Redis secret handling and the non-idempotent-looking configuration workaround require redesign and testing.

- **fastapi-tutorial**:
    - Description: Deploys a FastAPI tutorial application from GitHub, installs Python and PostgreSQL system dependencies, creates a Python virtual environment, installs application requirements, provisions a PostgreSQL database/user, writes a `.env` file, and manages a systemd service running Uvicorn on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python virtualenv, pip dependency installation, PostgreSQL service, database initialization, systemd unit, automatic service startup, and root-owned application execution.
    - Migration complexity: Moderate to high; it crosses OS packages, application deployment, database lifecycle, credentials, systemd, and external source reproducibility.

**CRITICAL PATH VERIFICATION:**

The three cookbook paths above are present in the supplied repository tree and their primary entrypoints (`recipes/default.rb`) were reviewed. External cookbooks are dependencies, not local modules, and are intentionally not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source and local cookbook declarations; it also declares external `nginx`, `memcached`, and `redisio` dependencies and contains a commented `ssl_certificate` declaration. Replace dependency resolution with an Ansible collection/role policy and explicit package/service tasks.
- `Policyfile.rb`: Defines the Chef policy name, run list, local cookbooks, and pinned external cookbook constraints. Its run list is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`; use it as the starting point for Ansible play/role orchestration.
- `Policyfile.lock.json`: Resolved dependency snapshot. It pins `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0, in addition to the three local cookbooks. Preserve this as migration evidence, but independently validate current Ansible modules and target package versions.
- `Vagrantfile`: Defines a `generic/fedora42` VM named `chef-nginx`, with libvirt, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 80/443. It rsyncs the repository to `/chef-repo` and invokes `vagrant-provision.sh`. Convert or replace this with an Ansible-compatible inventory and a test VM workflow.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef and Berkshelf via remote installers, vendors dependencies, and runs Chef Solo. It documents the current bootstrap flow but is not a suitable production Ansible bootstrap without OS and supply-chain hardening.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Its cookbook path assumptions should be replaced by Ansible project layout and inventory configuration.
- `solo.json`: Chef Solo run list plus site, TLS, and security overrides. It changes the cookbook attribute document roots to `/var/www/...`, while the cookbook defaults use `/opt/server/...`; reconcile this precedence explicitly in Ansible variables.
- `project-plan.md`: Describes the surrounding X2Ansible analysis/migration workflow. Coordinate generated plans and validation artifacts with this workflow, but treat the actual cookbook behavior as authoritative for implementation.

## Target Details

- **Operating System**: The Vagrant box is explicitly `generic/fedora42`, but the provisioning script uses Debian/Ubuntu `apt-get`, and cookbook behavior assumes Ubuntu-style details such as `ufw`, `www-data`, and the `postgresql` service name. Cookbook metadata supports Ubuntu >=18.04 and CentOS >=7, not Fedora 42 specifically. The target OS is therefore unresolved and must be decided before implementation. If no decision is available, use Red Hat Enterprise Linux 9 as the Ansible baseline and adapt firewall, package, user/group, SELinux, and service behavior accordingly; alternatively standardize on Ubuntu 22.04/24.04 to retain the current UFW and `www-data` assumptions.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 vCPUs and 2 GB memory are specified.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was found.
- **Network/application endpoints**: Nginx serves ports 80 and 443; Vagrant forwards these to host ports 8080 and 8443. FastAPI listens on all interfaces at port 8000, but no Vagrant forwarding for 8000 is defined. The configured test hostnames are `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.

## Migration Approach

Create an Ansible project with a tested inventory and separate roles such as `nginx_multisite`, `cache`, `fastapi_tutorial`, and optionally `host_security`. Keep application, caching, and edge/security responsibilities separable even though Chef currently nests security inside `nginx-multisite`. Use handlers for Nginx, Redis, Fail2ban, SSH, sysctl, and systemd reloads; use templates for Nginx, Fail2ban, sysctl, virtual hosts, and the FastAPI unit; use `ansible.builtin.package`, `service`, `user`, `file`, `git`, `template`, `systemd`, `community.postgresql`, and a supported firewall module rather than shell commands where possible.

First establish the supported OS and desired production topology. Then implement host security and base package prerequisites, followed by caching, application/database deployment, and finally Nginx/TLS integration. Validate each role in an isolated Fedora/RHEL or Ubuntu test VM matching the selected target, then run end-to-end checks for all hostnames, ports, service health, database connectivity, Redis authentication, and reboot persistence.

### Key Dependencies to Address

- **Chef Policyfile/Berkshelf**: Replace with `ansible-core` version pinning, `collections/requirements.yml`, role requirements, and a reproducible CI/test dependency process.
- **nginx 12.3.1 Chef cookbook**: Replace with native Ansible package/service/template tasks or an internally owned Nginx role. Preserve only the required behavior rather than translating cookbook internals.
- **memcached 6.1.0 Chef cookbook**: Replace with OS package installation, configuration, and service management. Confirm bind address and firewall exposure before enabling it.
- **redisio 7.2.4 and selinux 6.2.4**: Replace with a supported Redis package/role and explicit SELinux policy/booleans/ports on RHEL-family systems. Do not assume the Chef workaround is needed until the generated Redis configuration is understood on the selected version.
- **ssl_certificate 2.1.0**: It is locked by Policyfile but not directly used by the reviewed local recipes; determine whether it is historical or expected for certificate provisioning. Replace with Ansible-managed certificates, an ACME role, or externally issued secrets.
- **PostgreSQL and Python runtime**: The FastAPI cookbook installs distribution PostgreSQL, Python 3, pip, venv, Git, and `libpq-dev`. Use OS-specific package mappings and preferably a pinned Python dependency lock file and a versioned application revision.
- **GitHub application source**: Replace the mutable `main` revision with a commit or release tag and define network/proxy/credential requirements for deployment.
- **Vagrant/libvirt**: Retain Vagrant for local validation if useful, but make Ansible the provisioner and provide an inventory for the VM. Resolve the Fedora-versus-APT mismatch first.

### Security Considerations

- **Hardcoded Redis credential**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Move it to Ansible Vault or an external secret manager, rotate it, and avoid exposing it in logs, generated files, or command arguments. Define Redis bind/network policy explicitly.
- **Hardcoded PostgreSQL credentials**: The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes the same value into a world-readable (`0644`) root-owned `.env` file and database URL. Treat the credentials as compromised, rotate them, store them in Vault, set restrictive file permissions, and use `community.postgresql` modules with secure password handling.
- **TLS private keys and certificates**: The Nginx role creates private keys under `/etc/ssl/private` with `0640` and group `ssl-cert`, but the source generates self-signed certificates. Keep development certificates separate from production, use ACME or an approved certificate source for production, protect private keys with Vault/secret distribution, and verify ownership and renewal behavior.
- **SSH hardening**: Root login is disabled and password authentication is disabled by editing `sshd_config` with `sed`. Implement a managed SSH drop-in or validated template, ensure administrator keys and console/recovery access exist before applying it, validate with `sshd -t`, and use the correct service name (`ssh` versus `sshd`) per OS.
- **Firewall and exposure**: UFW defaults to deny and allows SSH, HTTP, and HTTPS. Recreate equivalent policy using `community.general.ufw` on Debian or `ansible.posix.firewalld` on RHEL. Do not expose Redis, Memcached, PostgreSQL, or FastAPI broadly unless required; the current FastAPI service binds to `0.0.0.0`.
- **Fail2ban and sysctl**: Preserve the jail and kernel hardening intent, but review the templates for target-OS compatibility and apply changes through idempotent modules with safe handlers and rollback procedures.
- **Privilege and service identity**: FastAPI runs as `root`; migrate it to a dedicated unprivileged application user with narrowly scoped filesystem permissions. Review Nginx document-root ownership and avoid making application artifacts writable by the web service unnecessarily.
- **Supply chain**: The provisioning script downloads Chef installation code with `curl | bash`, Berkshelf dependencies from Supermarket, and an unpinned GitHub `main` branch. Replace these with verified, pinned artifacts and controlled CI dependencies.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is provisioned with `apt-get`, while recipes expect Debian-style tools and identities. Mitigation: choose and document one supported OS matrix, add molecule/VM tests for it, and make package names, firewall, SELinux, and service names variables or OS-specific task files.
- **Chef attribute precedence and path drift**: `solo.json` uses `/var/www/test.cluster.local` paths, while cookbook defaults use `/opt/server/test`; static files are selected by hostname prefix. Mitigation: define one explicit `sites` data model in group/host variables and verify content placement and Nginx roots.
- **Non-idempotent imperative commands**: Redis config cleanup, PostgreSQL `psql` commands with `|| true`, UFW shell checks, and `sed` edits can hide failures or drift. Mitigation: replace with Ansible modules, controlled templates, changed notifications, and explicit convergence tests.
- **Certificate lifecycle**: Self-signed certificates are generated only when files are absent and have no renewal or trust-distribution workflow. Mitigation: distinguish development from production and implement ACME/enterprise PKI renewal and service reload handlers.
- **Application deployment reproducibility**: A mutable Git branch and unpinned pip requirements can produce different deployments. Mitigation: pin the source revision and Python dependencies, add health checks, and define rollback/version retention.
- **Database initialization and ownership**: Shell-created database objects are not safely modeled as state and may mask partial failure. Mitigation: use PostgreSQL Ansible collections, explicit idempotent database/user tasks, and migration tooling if the application has schema migrations.
- **Ordering and integration**: FastAPI requires PostgreSQL and Nginx/TLS sites may depend on files and certificates. Mitigation: role dependencies and handlers should express ordering while avoiding unnecessary coupling; validate services after every role.

### Migration Order

1. **Platform and test baseline**: Decide Ubuntu versus RHEL/Fedora, create inventory, establish Ansible version/collection pins, and reproduce the VM with Ansible connectivity.
2. **Host security and common prerequisites**: Implement package mappings, time/basic facts as needed, SSH hardening safeguards, firewall policy, sysctl, Fail2ban, and dedicated service users. Roll out cautiously because SSH/firewall changes can lock out operators.
3. **cache**: Migrate Memcached and Redis installation, authentication, filesystem permissions, service enablement, and any required Redis configuration using Vault-backed variables.
4. **fastapi-tutorial**: Pin the application revision, create the virtualenv and unprivileged systemd service, provision PostgreSQL idempotently, and add application/DB health checks.
5. **nginx-multisite and TLS**: Implement Nginx, the three site definitions, static content, certificate/key handling, security headers, Fail2ban integration, and reload handlers. Integrate upstream routing only if later requirements require proxying to FastAPI.
6. **End-to-end cutover and cleanup**: Compare rendered configuration and service behavior with Chef, test reboot and repeat convergence, rotate all exposed credentials, and retire Chef/Berkshelf only after rollback artifacts are available.

### Assumptions

- The supplied tree is complete for the relevant Chef configuration; no hidden roles, environments, data bags, CI pipelines, or production inventories were reviewed.
- The three local cookbooks are the only components intended for migration; locked external cookbooks are implementation dependencies rather than separately customized local modules.
- `Policyfile.lock.json` represents the dependency state to preserve for comparison, although the local working tree is marked dirty in its SCM metadata.
- The desired deployment has three Nginx virtual hosts and the site files included under `cookbooks/nginx-multisite/files/default` are the intended static content.
- The actual target OS is ambiguous. The plan assumes that an explicit OS decision will be made before coding; RHEL 9 is the fallback baseline required by the migration brief, not a fact established by the repository.
- The Vagrant Fedora box may be a development convenience rather than the production OS. Its current provisioning is internally inconsistent and may not work without modification.
- The FastAPI repository, its `requirements.txt`, application schema, and runtime behavior were not inspected; dependency versions, migrations, health endpoints, and required environment variables remain unknown.
- PostgreSQL is intended to run locally on the application host, and Redis/Memcached are intended to run locally, but this should be confirmed before designing multi-host inventories.
- The source uses self-signed certificates for development. Production certificate authority, DNS ownership, renewal, and secret distribution are unspecified.
- The source exposes FastAPI on all interfaces and configures only Nginx ports in Vagrant; whether FastAPI should be directly reachable or reverse-proxied is unresolved.
- The exact contents of Nginx, Fail2ban, security, sysctl, and site templates were not required to identify the module inventory; those templates must be reviewed during implementation to preserve their detailed behavior.
- No cloud platform, external secret manager, monitoring, backup, disaster-recovery, or CI deployment target is specified.
- Timeline is an engineering estimate for one small repository and must be recalibrated after OS selection, production requirements, template review, and application inspection.
