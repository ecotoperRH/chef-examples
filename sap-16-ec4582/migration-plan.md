# MIGRATION FROM CHEF TO ANSIBLE

This is a small Chef Solo/Policyfile repository containing three local cookbooks, coordinated by a single policy run list, plus Vagrant/libvirt development provisioning. The functional scope is nevertheless moderately complex: it combines hardened multi-site Nginx with self-signed TLS, Redis and Memcached, and a Git-sourced FastAPI/PostgreSQL service. A phased migration by one infrastructure engineer with application/security review should take approximately 2–3 weeks, including role development, platform reconciliation, testing, and handover. The principal early decision is the supported OS: the Vagrant definition specifies Fedora 42 while the Chef implementation contains Ubuntu/Debian-specific package, service, user, firewall, and Nginx-layout assumptions.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Configures an Nginx web server hosting the `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` static sites. It installs and enables Nginx, renders global and security configuration, creates document roots and index pages, creates site-enabled links, removes the default site, generates development self-signed certificates, and applies host hardening.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Three SSL-enabled virtual hosts, Nginx templates and static page files, Fail2ban, UFW default-deny policy with SSH/HTTP/HTTPS allow rules, sysctl hardening, SSH root-login and password-authentication disablement, and per-site RSA-2048 self-signed certificates.

- **cache**:
  - Description: Installs and configures Memcached and Redis caching services through external Chef cookbooks. It defines a Redis server on port 6379 with authentication, creates the Redis log directory, enables Redis, and edits generated Redis configuration to remove several replica-related directives as a compatibility workaround.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion, Redis server activation, Redis authentication, `/var/log/redis` ownership, and an imperative post-processing workaround for `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from Git, provisions a Python virtual environment and dependencies, installs and starts PostgreSQL, creates the application database/user, writes application environment settings, and manages a systemd Uvicorn service.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/pip/venv provisioning, Git checkout at `main`, local PostgreSQL database and grants, `.env` configuration, and a root-run FastAPI/Uvicorn systemd unit on port 8000.

**CRITICAL PATH VERIFICATION:** All module paths above are local cookbook paths explicitly present in the supplied repository tree. External Supermarket cookbooks are addressed as dependencies below and are not represented as local migration modules.

### Infrastructure Files

- `Berksfile`: Defines local cookbook sources and Supermarket dependency constraints. It comments out `ssl_certificate`, unlike the Policyfile, so dependency resolution must be consolidated before migration.
- `Policyfile.rb`: Declares the authoritative intended Chef run order: `nginx-multisite`, `cache`, then `fastapi-tutorial`; also lists Nginx, SSL certificate, Memcached, and Redis dependencies.
- `Policyfile.lock.json`: Locks resolved versions: Memcached 6.1.0, Nginx 12.3.1, RedisIO 7.2.4, SELinux 6.2.4 transitively, and ssl_certificate 2.1.0. Preserve behavior rather than attempting a direct cookbook-to-collection conversion.
- `solo.json`: Chef Solo run list and runtime attributes. It overrides the cookbook default document roots to `/var/www/<site>` and supplies certificate paths and hardening flags; these should become documented Ansible defaults/group variables.
- `solo.rb`: Chef Solo cache and cookbook search-path configuration; it has no direct Ansible equivalent beyond repository layout and dependency management.
- `Vagrantfile`: Development VM definition using `generic/fedora42`, private IP `192.168.121.10`, HTTP/HTTPS port forwarding, rsync sync, and the libvirt provider (2 GiB RAM, 2 CPUs). Convert to an optional Ansible test inventory/provisioner or retain as a Molecule/libvirt integration environment.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef/Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with an Ansible bootstrap/test invocation; its Ubuntu-specific commands conflict with the Fedora Vagrant base box.
- `project-plan.md`: Project-support documentation; review and update it to point to the Ansible repository, inventory, execution workflow, and ownership model.

### Target Details

- **Operating System**: Conflicting evidence. Cookbook metadata supports Ubuntu 18.04+ and CentOS 7+, while recipes use Debian/Ubuntu conventions: `apt-get`, UFW, `www-data`, the `ssh` service name, `/etc/nginx/sites-available`/`sites-enabled`, and package names such as `libpq-dev`. The Vagrant base box is Fedora 42, and the locked Redis dependency pulls an SELinux cookbook. For the initial migration target, standardize on Ubuntu (a currently supported LTS release) unless Fedora support is explicitly required; implement a separately tested Red Hat-family variable set if it is.
- **Virtual Machine Technology**: Vagrant with the libvirt provider. The private network and forwarded ports define the current local test topology.
- **Cloud Platform**: Not specified. No cloud provider tooling or metadata integration is visible.

## Migration Approach

Build an Ansible project with an inventory, environment-specific `group_vars`, an encrypted secrets file, and roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`. Use idempotent package, template, service, firewall, database, Git, and certificate tasks; use handlers for Nginx, SSH, systemd, Fail2ban, and sysctl reloads. Establish CI validation on the selected OS before production rollout, with functional checks for all virtual hosts, cache listeners, PostgreSQL connectivity, and the FastAPI endpoint. Assign platform, application, and security owners to review their respective role acceptance criteria and retain the Chef configuration as rollback reference until parity is signed off.

### Key Dependencies to Address

- **Chef Client/Solo and Berkshelf**: Retire after Ansible roles, inventories, and CI execution replace the Chef Solo bootstrap and cookbook vendoring flow.
- **memcached (Chef Supermarket 6.1.0)**: Replace with the distribution package and `ansible.builtin.service`/`ansible.builtin.systemd`; explicitly define any required Memcached settings because the local recipe only includes the external cookbook.
- **redisio (Chef Supermarket 7.2.4)**: Replace with Redis distribution packages, managed configuration template, directories, ownership, and service tasks. Model the declared port and authentication in variables and eliminate the Chef Ruby post-edit workaround by generating valid target-version configuration directly.
- **nginx (Chef Supermarket 12.3.1)**: The local cookbook actually installs the OS Nginx package itself rather than including this dependency. Use `ansible.builtin.package`, templates, and handlers; verify whether the Policyfile dependency is obsolete.
- **ssl_certificate (Chef Supermarket 2.1.0)**: Present in the Policyfile and lock but not used by the reviewed local recipes, and commented in `Berksfile`. Do not add an Ansible dependency until stakeholders confirm a required certificate workflow.
- **selinux (Chef Supermarket 6.2.4, transitive)**: Its presence follows RedisIO dependency resolution, not an explicit local policy. On Ubuntu it is not applicable; on Fedora/RHEL, define SELinux state, labels, and required port/file policies explicitly rather than carrying an implicit dependency.
- **FastAPI source and Python requirements**: The application is pulled from `https://github.com/dibanez/fastapi_tutorial.git` at mutable branch `main`, and pip installs its repository requirements. Pin a reviewed commit/tag and dependency versions or hashes before production deployment; use `ansible.builtin.git` and `ansible.builtin.pip` with the virtual environment.
- **PostgreSQL**: Replace shell `psql ... || true` commands with PostgreSQL Ansible modules (for example, `community.postgresql.postgresql_user`, `postgresql_db`, and privilege tasks), with required collection and Python database-driver dependencies documented.

### Security Considerations

- **Hardcoded database and Redis credentials**: `fastapi-tutorial` embeds `fastapi_password` in both PostgreSQL creation commands and a world-readable (`0644`) `.env`; `cache` embeds `redis_secure_password_123`. Move each credential to Ansible Vault or an approved external secret manager, generate/rotate values, mark secret-bearing tasks `no_log: true`, and restrict deployed environment files to the application account (normally `0600`).
- **TLS certificates and private keys**: `nginx-multisite` creates self-signed 2048-bit keys valid for 365 days beneath `/etc/ssl/private`, with key mode 0640 and group `ssl-cert`. Self-signed certificates are appropriate only for development/testing. For production, integrate the approved CA/ACME or secret-store process, retain restrictive key permissions, establish renewal/rotation, and ensure the Nginx worker can read keys without granting unnecessary access.
- **SSH lockout risk**: The security recipe disables root SSH login and password authentication by direct `sed` changes. Implement this through a validated `sshd_config` drop-in/template, check syntax before reload, confirm key-based break-glass access, and roll out in a controlled maintenance window.
- **Firewall and host hardening**: UFW default-deny exposes only SSH, HTTP, and HTTPS; Fail2ban and sysctl hardening are rendered from templates. Preserve intended controls but make them OS-aware (UFW is not Fedora-native), review the exact sysctl/Fail2ban/Nginx template settings with security, and include management/monitoring network requirements before enforcement.
- **Process privilege**: The FastAPI systemd unit runs as `root`. Create a dedicated non-login service account, give it only required application and configuration access, and update service ownership, deployment paths, and database-secret access accordingly.
- **Supply chain and mutable inputs**: Chef installation is fetched by `curl | bash`, Supermarket cookbooks are externally sourced, Git tracks `main`, and pip dependencies are installed without visible lock enforcement. The Ansible migration should use pinned collections, trusted package repositories, pinned Git revision, and a reviewed Python lock/requirements process.

### Technical Challenges

- **OS and layout inconsistency**: Fedora 42 is provisioned, but the bootstrap and Nginx/security implementation require Debian conventions. Decide the production OS first; otherwise every role needs conditionals for package names, service names, Nginx virtual-host layout, firewall backend, users/groups, and SELinux.
- **Configuration precedence**: Cookbook defaults use `/opt/server/*`, but `solo.json` overrides all site roots to `/var/www/*`. Preserve the effective Chef Solo configuration as the initial Ansible environment variable set and document precedence to avoid deploying content to the wrong directories.
- **External cookbook behavior is not local**: Memcached/RedisIO implement behavior beyond the local `include_recipe` calls. Validate the converged Chef host or cookbook documentation to establish required package versions, Redis config, service names, and Memcached defaults before declaring parity.
- **Imperative and non-idempotence-masking commands**: Redis configuration is modified with a Ruby text substitution, and database commands use `|| true`, which can hide failed or incomplete configuration. Replace both with declarative Ansible resources and explicit verification.
- **Application deployment lifecycle**: A mutable Git branch, unpinned pip install, root service, and no visible migration/health-check strategy make reproducibility and rollback difficult. Introduce a release revision variable, application health checks, service restart handlers, and a rollback procedure.
- **Network/name resolution**: TLS virtual hosts are internal `.cluster.local` names and Vagrant host entries are commented out. Define DNS, test inventory aliases, certificates/SANs, and port exposure for the target environment.

### Migration Order

1. **Foundation and target-platform decision**: Select Ubuntu LTS or define dual-platform support; create inventory, variable hierarchy, Vault/secrets workflow, CI lint/syntax checks, and a Vagrant/libvirt or equivalent integration test path. Confirm effective values from `solo.json`.
2. **cache**: Migrate Memcached and Redis as isolated roles, replace the hardcoded Redis password, and test service enablement, listener access, authentication, and persistence/configuration requirements. This has limited application coupling but must be understood because functionality currently comes from external cookbooks.
3. **nginx-multisite**: Migrate Nginx, static sites, hardened configuration, firewall, Fail2ban, sysctl, SSH controls, and development TLS. Validate configuration syntax, all three hostnames, redirects/TLS behavior, and access rules; coordinate security approval before SSH/firewall enforcement.
4. **fastapi-tutorial**: Migrate PostgreSQL and the FastAPI release deployment after secret management and service-account design are approved. Validate database provisioning, virtual-environment dependency installation, Uvicorn/systemd startup, application health, and Nginx upstream/reverse-proxy requirements if those are intended (the reviewed Chef configuration does not explicitly proxy Nginx to port 8000).
5. **Integrated cutover and decommissioning**: Run a parallel validation against the Ansible-managed node, compare service/configuration behavior, document operations and rollback, transfer ownership, then retire Chef Solo, Berkshelf, and policy-lock workflow after acceptance.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks; no Puppet, Salt, or PowerShell module structure is present in the supplied tree.
- `Policyfile.rb` represents the intended run order, while `solo.json` is the current Chef Solo runtime input; the differing `ssl_certificate` entries between dependency files require confirmation.
- The plan is based on reviewed entry/default and central Nginx recipes, metadata, dependency manifests, and provisioning files; template contents and external cookbook internals were not exhaustively audited.
- Ubuntu LTS is recommended as the initial target because the effective implementation is Debian-oriented, but this is a recommendation—not confirmation of the required production platform. Fedora 42/libvirt appears to be a development target and is incompatible with the provided `apt-get` bootstrap as written.
- No production DNS, cloud provider, production inventory, certificate authority, secrets manager, CI system, monitoring stack, backup/restore policy, or high-availability requirement is specified.
- Self-signed certificates, local Redis/Memcached/PostgreSQL, and the static virtual-host content are assumed to be development/tutorial-oriented until stakeholders define production requirements.
- The externally referenced FastAPI Git repository, its requirements file, and its database schema/migration behavior must be reviewed by the application owner; no application migration task is visible in the local Chef recipe.
