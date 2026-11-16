# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a small Chef Solo application stack consisting of three local cookbooks, four pinned external cookbooks, and a Vagrant/libvirt test environment. The active Chef Policyfile run list provisions an Nginx multi-site web tier, Memcached/Redis caching, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in operational risk rather than size: the inventory is small, but it includes security hardening, TLS material, database credentials, service ordering, package-manager assumptions, and imperative configuration fixes.

A focused implementation should take approximately **1–2 weeks** for one engineer familiar with Ansible, including role development, test-environment correction, security review, and parity testing. Allow **2–3 weeks** if production certificate handling, application deployment ownership, CI validation, and a cloud/VM target design are not yet defined. The recommended target is an Ansible project with separate roles for security, Nginx, cache services, PostgreSQL/application deployment, and a top-level site playbook.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and runs Nginx as a multi-site web server, creates three document roots and static landing pages, configures per-site virtual hosts, and enables SSL for each site.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; Nginx service management; generated site links; Nginx and security templates; self-signed RSA certificates for development; fail2ban, UFW, sysctl, and SSH hardening.
    - Internal structure: `default` composes `security`, `nginx`, `ssl`, and `sites` recipes. Attributes define site and security defaults.

- **cache**:
    - Description: Installs Memcached and Redis, configures a Redis server on port 6379, creates its log directory, enables the service, and applies an imperative post-configuration cleanup.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion; RedisIO integration; Redis authentication; Redis replication-related configuration cleanup; Redis service enablement.
    - Security sensitivity: Contains a hardcoded Redis password in the recipe and must be redesigned around Ansible Vault or an external secret manager.

- **fastapi-tutorial**:
    - Description: Installs Python and PostgreSQL system dependencies, checks out the FastAPI tutorial application from GitHub, creates a virtual environment, installs Python requirements, creates a PostgreSQL database/user, writes application environment configuration, and manages a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv; Git-based application deployment; local PostgreSQL; `fastapi` database and user; Uvicorn on `0.0.0.0:8000`; systemd startup and restart behavior.
    - Security sensitivity: Contains hardcoded PostgreSQL credentials in shell commands and an application `.env` file, and runs the service as `root`.

**CRITICAL PATH VERIFICATION:**

All module paths above are present in the supplied repository tree. No Puppet, Salt, or PowerShell modules were identified. The external Chef cookbooks listed below are dependencies, not local modules and are therefore not included as module inventory entries.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, three local cookbooks, and external `nginx`, `memcached`, and `redisio` dependencies. The `ssl_certificate` declaration is commented out here, creating a dependency-source discrepancy with the Policyfile.
- `Policyfile.rb`: Defines policy `nginx-multisite-policy`, the active run list, local cookbook paths, and external version constraints including `ssl_certificate`.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions: Nginx 12.3.1, Memcached 6.1.0, RedisIO 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. It also records the cache cookbook's dependency graph.
- `solo.rb`: Chef Solo configuration, including cookbook search paths, cache path, and logging.
- `solo.json`: Standalone run list plus Nginx sites, certificate paths, fail2ban/UFW settings, and SSH hardening overrides. Its site document roots differ from the cookbook defaults.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt resources (2 GB RAM, 2 CPUs), private IP `192.168.121.10`, forwarded HTTP/HTTPS ports, rsync of the repository, and shell provisioning.
- `vagrant-provision.sh`: Uses `apt-get`, installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. This conflicts with the Fedora Vagrant box and is a likely test-environment failure that must be resolved before parity testing.
- `project-plan.md`: Describes the surrounding X2Ansible tool and its analysis/migration workflow; it is project documentation rather than deployable infrastructure.
- `cookbooks/nginx-multisite/templates/`: Contains Nginx, site, security, fail2ban, and sysctl templates that must be ported to Jinja2 or equivalent managed files.
- `cookbooks/nginx-multisite/files/`: Contains static `index.html` content for the three sites and should become role files or application artifacts.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource; inspect and explicitly account for its behavior if it is referenced by templates or omitted recipes during implementation.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The actual provisioning script assumes Debian/Ubuntu through `apt-get`, while Vagrant selects Fedora 42. The target OS is therefore unresolved. Confirm the intended production OS before implementation; if no authoritative target exists, use the requested default of Red Hat Enterprise Linux 9 and adapt package/service names, firewall, and SELinux behavior accordingly.
- **Virtual Machine Technology**: libvirt via Vagrant is explicitly configured. The VM has 2 CPUs, 2048 MB RAM, private networking, and host port forwarding.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration is present.
- **Network/application endpoints**: Nginx exposes ports 80/443; the FastAPI service listens on port 8000 locally to the VM. The documented host/IP values are inconsistent in places and need validation.

## Migration Approach

Create an Ansible repository with an inventory and environment-specific variables, for example:

- `playbooks/site.yml`: ordered orchestration for security, cache, database/application, and Nginx.
- `roles/security`: firewall, fail2ban, sysctl, SSH policy, and SELinux policy.
- `roles/cache`: Memcached and Redis installation/configuration, password handling, directories, and services.
- `roles/fastapi_tutorial`: OS packages, checkout/version pinning, virtualenv, dependencies, PostgreSQL database/user, `.env`, systemd unit, and handlers.
- `roles/nginx_multisite`: Nginx packages, templates, static files, certificates, virtual hosts, symlinks, and handlers.
- `group_vars/`: non-secret settings; encrypted values in Ansible Vault or an approved secret backend.

Use idempotent Ansible modules (`package`, `apt`, `dnf`, `service`, `systemd`, `template`, `copy`, `file`, `user`, `git`, `community.postgresql.postgresql_db`, and `community.postgresql.postgresql_user`) instead of shell commands wherever possible. Preserve notification semantics with handlers and validate Nginx configuration before reload.

### Key Dependencies to Address

- **Chef Infra/Chef Solo >=16 and Berkshelf**: Remove Chef bootstrap and replace with Ansible controller execution, inventory, collections, and CI linting/testing.
- **nginx 12.3.1 Chef cookbook**: Replace with an Ansible Nginx role or native tasks/templates. Preserve the repository's local Nginx templates rather than assuming the Chef cookbook's defaults.
- **memcached 6.1.0 Chef cookbook**: Replace with OS package/service tasks and explicit configuration; verify bind address and firewall exposure.
- **redisio 7.2.4 and SELinux 6.2.4**: Replace with a supported Ansible Redis approach and explicit SELinux tasks/policies for the selected OS. Validate Redis configuration syntax and service layout.
- **ssl_certificate 2.1.0**: The lock file includes it, but the Berksfile declaration is commented and the local recipes generate self-signed certificates directly. Decide whether development self-signed certificates remain or production certificates are supplied by Vault, a PKI, or ACME.
- **PostgreSQL packages and application repository**: The application cookbook has no Chef metadata dependency; Ansible must manage PostgreSQL version compatibility, Git revision policy, Python dependencies, and database migrations separately from infrastructure provisioning.
- **GitHub repository `dibanez/fastapi_tutorial`, branch `main`**: Replace floating branch deployment with a reviewed commit or release pin and define availability/proxy requirements.
- **Python requirements**: Install in a virtualenv with controlled package versions and preferably a lock file; test the remote application's current requirements against the chosen OS/Python version.
- **Vagrant/libvirt**: Either correct the test image/provisioning to match the target OS or use an Ansible Vagrant provisioner and a compatible Fedora/RHEL or Ubuntu box.

### Security Considerations

- **Hardcoded Redis credential**: `cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and ensure Redis is bound only to intended interfaces.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial/recipes/default.rb` embeds the `fastapi` password in SQL and the `.env` file. Rotate it, store it encrypted, set restrictive file permissions, and avoid credentials on command lines where possible.
- **Root application service**: The systemd unit runs Uvicorn as `root`. Create a dedicated non-privileged service account, restrict ownership and permissions, and assess whether port 8000 should be private behind Nginx.
- **TLS certificates and private keys**: Self-signed certificates are generated for three sites under `/etc/ssl`; private keys receive restrictive group permissions. Do not generate production keys in ordinary tasks or commit them. Define certificate delivery, renewal, ownership, SANs, and rotation.
- **SSH hardening**: Root login is disabled and password authentication is disabled. Apply through `ansible.builtin.sshd`-compatible managed configuration or a carefully validated drop-in, preserve console/break-glass access, and restart only after syntax validation.
- **Firewall and fail2ban**: Current UFW rules allow SSH, HTTP, and HTTPS after default deny. On RHEL-family systems use `ansible.posix.firewalld` rather than UFW; retain fail2ban jail behavior and confirm logs/jails for the selected distribution.
- **SELinux**: The locked Redis dependency includes SELinux support, but the local recipes do not expose its policy. Enforce or permissively validate SELinux according to the target OS and add required labels/ports rather than disabling it.
- **Supply-chain controls**: The app is cloned from a public `main` branch and Python dependencies are installed at runtime. Pin source revisions, review dependencies, and use trusted package indexes/artifacts.
- **Secrets management by module**: `cache` uses a Redis password; `fastapi-tutorial` uses PostgreSQL credentials and a database URL; `nginx-multisite` references private TLS keys and generates development certificates. No Chef encrypted data bags or Chef Vault usage were found in the reviewed files.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is selected but provisioning calls `apt-get`, and cookbook support covers Ubuntu/CentOS rather than Fedora explicitly. Select one supported OS and update package names, service names, firewall implementation, SELinux handling, and PostgreSQL defaults.
- **Configuration precedence and path drift**: `solo.json` overrides site roots to `/var/www/...`, while cookbook attributes default to `/opt/server/...`; static files and templates must be reconciled. Build a single documented variable model and test the effective configuration.
- **Imperative Chef fixes**: Redis uses a Ruby block to remove several generated directives. Reproduce the intended final configuration declaratively with a managed template or supported Redis variables, and add convergence tests.
- **Certificate lifecycle**: Current certificates are development-only and generated once based on file existence. Production migration needs a clear certificate source, renewal mechanism, secure permissions, and Nginx reload handling.
- **Application/database idempotence**: Shell SQL commands use `|| true`, which hides errors and does not robustly manage existing users/databases. Use PostgreSQL modules, explicit privileges, and migration readiness checks.
- **Service ordering and readiness**: PostgreSQL must be available before database creation and the FastAPI service; Nginx should validate configuration before reload. Implement handlers, retries, health checks, and explicit dependencies.
- **External application behavior**: The remote tutorial repository and its requirements are outside this repository. Confirm its expected startup module (`app.main:app`), database schema behavior, and production settings.
- **Testing gaps**: No test suite or CI configuration is visible. Add Molecule or equivalent disposable-VM tests, Ansible-lint, YAML checks, Nginx config tests, TLS checks, and endpoint smoke tests.

### Migration Order

1. **Foundation and target definition**: Resolve OS, inventory, VM image, network addressing, certificate policy, and secret ownership. Correct the Fedora/`apt-get` mismatch before using the environment as a test oracle.
2. **Security baseline**: Implement SSH policy, firewall, fail2ban, sysctl, SELinux, service-account standards, and secret storage. Validate break-glass access before enabling restrictive settings.
3. **Cache role**: Migrate Memcached and Redis, including the password, log directory, service enablement, final configuration, and port exposure. This is relatively isolated but security-sensitive.
4. **PostgreSQL and FastAPI role**: Provision database packages and credentials with idempotent PostgreSQL modules, pin the application revision, create the virtualenv, install dependencies, and run the service as a dedicated user.
5. **Nginx multi-site role**: Port templates and static files, reconcile effective document roots, configure three sites, install certificates, and add syntax-validated reload handlers.
6. **Integrated validation and cutover**: Run the complete playbook repeatedly, compare package/service/filesystem/network behavior with the intended Chef result, test all HTTP/HTTPS sites and FastAPI proxy behavior, then decommission Chef/Berkshelf provisioning.

### Assumptions

- The three local cookbook directories are the complete set of source modules requiring migration.
- The Policyfile run list is authoritative for active deployment, although `solo.json` is also used by the Vagrant shell provisioner.
- `Policyfile.lock.json` is the authoritative record of resolved external versions where it conflicts with loose dependency declarations.
- The intended deployment is a Linux VM, but the production OS has not been selected.
- The Vagrant environment is a development/test environment, not proof of the production network or certificate design.
- The self-signed certificates are suitable only for development unless explicitly approved otherwise.
- The application repository, its `requirements.txt`, and its runtime behavior were not inspected; application-level migration and schema migrations require owner validation.
- The intended Nginx document roots are ambiguous because cookbook defaults and `solo.json` differ; this must be resolved before implementation.
- The `ssl_certificate` cookbook is locked but not active in the Berksfile declaration and is not used by the reviewed local recipes.
- The custom `lineinfile` resource and unreviewed templates may contain behavior not captured by the high-level survey; validate references during implementation.
- No cloud provider, production inventory, DNS automation, external secret manager, monitoring, backup policy, or CI pipeline is specified.
- No Chef encrypted data bags, Chef Vault data, or other encrypted secret files were found in the reviewed source files.
- The migration estimate assumes one environment and three local roles; multiple environments, high-availability Redis/PostgreSQL, or production PKI will increase schedule and testing effort.
- Team coordination should assign an Ansible owner, an application/database owner, and a security/platform reviewer; review each role independently, maintain a source-to-target behavior matrix, and require deployment approval after integration tests.
