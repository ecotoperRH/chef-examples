# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment containing three local cookbooks and four primary runtime concerns: multi-site Nginx, Redis/Memcached caching, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in operational risk rather than code volume: the Chef code is compact, but it contains imperative shell commands, hardcoded credentials, generated TLS keys, firewall/SSH hardening, and an OS mismatch between the Vagrant image and the provisioning script. A focused team could complete an initial Ansible implementation in approximately 1–2 weeks, including validation and security remediation; production hardening, certificate integration, and application deployment testing may require an additional 1–2 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Configures Nginx as a multi-site web server for three SSL-enabled virtual hosts, creates their document roots and sample index pages, applies Nginx security settings, and manages host firewall and SSH hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management, templated `nginx.conf` and virtual hosts, `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, self-signed certificates, Fail2ban, UFW, sysctl settings, and root/password SSH restrictions.

- **cache**:
    - Description: Installs and configures Memcached and Redis services used as caching infrastructure, including a Redis listener on port 6379 and Redis authentication.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, Redisio integration, Redis password configuration, Redis log directory creation, service enablement, and an imperative post-configuration workaround that removes replication-related settings.

- **fastapi-tutorial**:
    - Description: Installs the Python and PostgreSQL prerequisites, checks out the FastAPI tutorial application, creates a virtual environment, installs Python requirements, creates a PostgreSQL database/user, and runs the application through systemd on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout from `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python virtualenv, PostgreSQL service, database initialization, `.env` generation, and an always-restarting Uvicorn systemd service.

**CRITICAL PATH VERIFICATION:**

The three cookbook paths above were present in the supplied repository tree and their primary entrypoints and metadata were reviewed. No Puppet modules, Salt states, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Resolves local cookbooks and external Supermarket cookbooks. In Ansible, replace Berkshelf resolution with a requirements file/collection requirements and pin tested artifact versions.
- `Policyfile.rb`: Defines the Chef policy run list and cookbook constraints. Its run list is `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`; convert this to an Ansible playbook/site entrypoint and explicit role ordering.
- `Policyfile.lock.json`: Records resolved versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SSL certificate 2.1.0, and SELinux 6.2.4, plus local cookbook revisions. Preserve this as migration input, not as an Ansible dependency format.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and ports 8080/8443 forwarded to guest ports 80/443. It currently provisions with the shell script and syncs the repository to `/chef-repo`.
- `vagrant-provision.sh`: Installs packages with `apt-get`, Chef, Berkshelf, and Chef Solo, then runs the policy-equivalent local JSON configuration. Replace this with Ansible installation/inventory/bootstrap logic and resolve the Fedora-versus-APT inconsistency.
- `solo.rb`: Chef Solo cache, cookbook path, and logging configuration. It has no direct Ansible equivalent beyond inventory, roles, logging, and execution configuration.
- `solo.json`: Defines the three sites, document roots, SSL paths, and security flags. Convert to group/host variables or vaulted environment variables, with structured per-site data.
- `project-plan.md`: Existing project documentation should be updated to reflect the Ansible architecture, test strategy, ownership, and cutover plan; its contents were not required to identify the cookbook inventory.

### Target Details

- **Operating System**: The Vagrant target is explicitly `generic/fedora42`, but `vagrant-provision.sh` uses `apt-get` and the cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The migration must choose and test a canonical OS. Fedora 42 implies DNF, firewalld, and likely SELinux; alternatively use an Ubuntu image if the existing APT/UFW behavior is intentional. Do not assume the current script provisions the declared Fedora image successfully.
- **Virtual Machine Technology**: libvirt, with Vagrant as the lifecycle wrapper. Resources are 2 CPUs and 2048 MB RAM.
- **Cloud Platform**: Not specified. The repository is oriented toward local Vagrant/libvirt testing.

## Migration Approach

Create an Ansible project with roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`, plus either a shared `security` role or security tasks owned by the Nginx role. Use a site playbook that applies roles in dependency order and a Vagrant inventory targeting the private VM IP. Preserve templates and static files where useful, but replace Chef resources with idempotent Ansible modules (`package`, `service`, `template`, `copy`, `file`, `user`, `community.postgresql`, `ansible.posix.firewalld`/`ufw`, `ansible.posix.sysctl`, and `ansible.builtin.systemd`). Use handlers for Nginx, Fail2ban, SSH, sysctl, and systemd reloads.

### Key Dependencies to Address

- **Nginx cookbook 12.3.1**: Replace with an Ansible Nginx role or native package/template/service tasks. Reproduce virtual-host links, document roots, security configuration, and reload handlers.
- **Memcached cookbook 6.1.0**: Replace with distribution package/service tasks and explicit cache configuration. Confirm whether Memcached is actually required by the application; the reviewed local code only includes the recipe.
- **Redisio cookbook 7.2.4**: Replace with a supported Redis package/repository strategy and a template-managed configuration. The current imperative workaround should become a deliberate, documented configuration model rather than a post-edit of generated files.
- **SELinux cookbook 6.2.4**: Account for Fedora's SELinux enforcement. Define required ports, file contexts, booleans, and policies with Ansible SELinux modules where needed; do not disable SELinux as a shortcut.
- **ssl_certificate cookbook 2.1.0**: The Policyfile lock includes it, but the Berksfile comments its declaration and the reviewed local recipes generate self-signed certificates directly. Decide whether development self-signed certificates remain supported or replace them with a real CA/ACME or externally managed certificate process.
- **PostgreSQL and Python runtime**: Replace Chef package/execute resources with OS-aware package tasks, `community.postgresql` database/user modules, Python virtualenv/pip tasks, and an explicit application release/update strategy.
- **Git-hosted application source**: Pin a commit or release rather than tracking `main` for reproducibility, and define an update/rollback procedure.
- **Ansible dependencies**: Use `collections/requirements.yml` for required community collections and pin versions tested against the chosen Ansible release and target OS.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, use restrictive Redis configuration permissions, and rotate it during migration.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes the same value into `/opt/fastapi-tutorial/.env` with mode `0644`. Generate/store the password in Vault, set `.env` to a restrictive mode such as `0600`, and avoid exposing credentials in command-line process listings or logs.
- **TLS private keys**: The Nginx recipe creates self-signed private keys under `/etc/ssl/private` and applies group access through `ssl-cert`. Preserve least privilege, ensure key material is not committed to source control, and define certificate renewal/replacement for non-development environments.
- **SSH hardening**: Root login and password authentication are disabled through `sed` edits. Implement this with an Ansible-managed SSH configuration fragment, validate syntax before restart, and ensure an authorized key-based administrative path exists to prevent lockout.
- **Firewall exposure**: UFW permits SSH, HTTP, and HTTPS and defaults to deny. On Fedora, map this to firewalld rather than assuming UFW is installed; restrict SSH source networks where possible and separately decide whether FastAPI port 8000 and Redis 6379 should remain localhost-only.
- **Fail2ban and sysctl**: Migrate the jail and sysctl templates with validation and handlers. Confirm the rules match the chosen logging paths and OS defaults.
- **Application privilege**: The systemd service runs Uvicorn as `root`. Create a dedicated non-root service account, restrict filesystem ownership, and bind through Nginx or otherwise assess the need for privileged access.
- **Supply chain**: Chef dependencies come from Supermarket and the application is cloned from GitHub. Pin versions/commits, verify artifacts, and add CI scanning and dependency review.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is declared while provisioning uses Debian/Ubuntu commands and UFW. Select a supported baseline, create molecule/Vagrant tests for it, and make package, service, firewall, and SELinux behavior OS-aware only if multi-OS support is required.
- **Chef imperative behavior**: Redis config mutation, PostgreSQL shell commands with `|| true`, `sed`-based SSH changes, and shell-driven UFW operations can hide failures or drift. Replace them with idempotent modules, explicit state checks, and failure handling.
- **Nginx template semantics**: Existing templates and resource code coordinate virtual-host links, certificate filenames, static files, and delayed reloads. Port these as a single role contract and validate with `nginx -t` before handlers reload the service.
- **Certificate lifecycle**: Self-signed certificates are suitable for the documented development warning but not production trust. Choose ACME, an enterprise PKI, or pre-provisioned certificates and document ownership/renewal.
- **Database/application lifecycle**: The current recipe installs from `main`, installs requirements on every converge path, and creates the service as root. Introduce release directories, pinned dependencies, migrations, health checks, non-root execution, and rollback before production use.
- **Dependency ambiguity**: `ssl_certificate` is locked in Policyfile but commented out in Berksfile, and `cache` depends on Redisio without a precise version in metadata. Reconcile the authoritative dependency set before implementation.
- **Testing coverage**: There are no visible automated tests in the supplied tree. Add syntax/lint checks, Molecule or Vagrant convergence tests, service health checks, TLS checks, firewall assertions, and repeat-run idempotence tests.

### Migration Order

1. **Foundation and target OS decision**: Rebuild Vagrant/inventory/bootstrap, select Fedora-compatible or Ubuntu-compatible behavior, install Ansible collections, and establish secrets handling and CI checks.
2. **Security baseline**: Implement SSH, firewall, sysctl, SELinux, Fail2ban, service accounts, and validation safeguards before exposing application services.
3. **cache**: Migrate Memcached and Redis with Vault-managed credentials and verify local binding, persistence requirements, and service health. This is relatively isolated but security-sensitive.
4. **fastapi-tutorial**: Migrate PostgreSQL, application checkout, virtualenv, dependency installation, database provisioning, non-root systemd service, and health checks. Coordinate with application owners on schema and release behavior.
5. **nginx-multisite**: Migrate Nginx templates, three sites, static content, certificate handling, and reverse-proxy/front-door behavior after backend and security contracts are known.
6. **Integration and cutover**: Run repeatable convergence and rollback tests, compare rendered configuration and endpoints, perform a staged VM/environment cutover, and retire Chef only after operational acceptance.

### Assumptions

- The intended deployment scope is the single Vagrant/libvirt VM described in `Vagrantfile`; production topology, load balancing, DNS, and certificate authority details are not supplied.
- The three local directories with `metadata.rb` and `recipes/default.rb` are the complete local cookbook inventory.
- `Policyfile.lock.json` is the best record of resolved external cookbook versions, although the Berksfile and Policyfile are not fully consistent.
- The Nginx site data in `solo.json` is authoritative for the initial environment and all three sites require SSL.
- Self-signed certificates are currently for development only, based on the provisioning warning; production certificate requirements remain unspecified.
- The application repository, its required environment variables, migrations, and runtime health endpoint were not inspected and must be confirmed with application owners.
- PostgreSQL is intended to run locally on the same host; backup, replication, persistence, and data retention requirements are unspecified.
- Redis persistence, replication, network exposure, and whether Memcached is consumed by the application are unspecified.
- The correct operating system is unresolved: Fedora 42 is configured in Vagrant, while the shell script and cookbook support statements target Debian/Ubuntu and CentOS-era systems.
- No cloud provider, external secret manager, monitoring, logging aggregation, DNS automation, or production inventory is defined.
- Existing Chef templates (`nginx.conf.erb`, `site.conf.erb`, security, Fail2ban, and sysctl templates) must be functionally reviewed during implementation even though this high-level survey did not read every template.
- Teams should assign owners for platform/OS, security/secrets, Nginx/networking, cache services, database/application runtime, and test/cutover coordination; migration completion requires shared acceptance criteria and documented rollback.
