# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Vagrant infrastructure project with three local cookbooks and a locked set of external cookbooks. The migration is modest in module count but security-sensitive because it provisions a public-facing Nginx installation, firewall/SSH hardening, TLS keys, Redis authentication, and a FastAPI/PostgreSQL application. A focused team can reach a tested Ansible equivalent in approximately 2–4 weeks: 2–3 days for inventory and design, 5–8 engineering days for implementation, and 3–5 days for validation, hardening, and cutover. The estimate assumes that the existing application repository and site content remain unchanged.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx multi-site web serving for three SSL-enabled virtual hosts, with security hardening, firewall setup, Fail2ban, SSH restrictions, static site content, and development certificate generation.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: `nginx.conf` and security templates, sites-enabled symlinks, `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, UFW rules, Fail2ban, sysctl tuning, disabled root SSH login, disabled SSH password authentication, self-signed RSA certificates
    - Migration notes: Split into an Nginx role plus clearly scoped security/firewall tasks or roles. Preserve template variables and handler-driven reloads, but replace shell-based edits with Ansible modules where possible.

- **cache**:
    - Description: Memcached and Redis cache service provisioning, including Redis on port 6379, a configured Redis password, logging directory creation, service enablement, and a post-configuration workaround for Redis replication settings.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached cookbook inclusion, Redisio cookbook inclusion, `/var/log/redis`, Redis authentication, direct modification of `/etc/redis/6379.conf`
    - Migration notes: Use distribution packages or explicitly selected Ansible-compatible Redis/Memcached installation strategy. Model Redis settings as variables and replace the Ruby file-rewrite hack with a managed configuration template or targeted `lineinfile` tasks after confirming the required Redis version.

- **fastapi-tutorial**:
    - Description: Installs system Python and PostgreSQL dependencies, clones the FastAPI tutorial application, creates a virtual environment, installs Python requirements, creates a PostgreSQL database/user, and runs the application under systemd on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python virtualenv, PostgreSQL service, database initialization, `.env` generation, systemd unit, Uvicorn bound to `0.0.0.0:8000`
    - Migration notes: Use Ansible package, git, pip/virtualenv, PostgreSQL modules, template, systemd, and handler tasks. Pin the application revision and Python dependencies before production migration.

**CRITICAL PATH VERIFICATION:**

The three cookbook paths above were present in the provided repository tree and their primary entrypoints were reviewed. No Puppet manifests, Chef recipes outside these cookbooks, PowerShell modules, or Salt states were identified.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source and local cookbook declarations; lists external `nginx`, `memcached`, and `redisio` dependencies and a commented `ssl_certificate` dependency.
- `Policyfile.rb`: Defines the Chef policy run list and cookbook constraints. It includes the three local cookbooks plus `nginx`, `ssl_certificate`, `memcached`, and `redisio`.
- `Policyfile.lock.json`: Resolved dependency graph and versions. It locks `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0; it also records local cookbook revision `c7845a8...` and a dirty working tree.
- `Vagrantfile`: Fedora 42 `generic/fedora42` VM using libvirt, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and host forwards for ports 80/443. It syncs the repository to `/chef-repo`.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, runs `berks install/vendor`, and executes Chef Solo. It uses `apt-get`, which conflicts with the Fedora Vagrant box and must be corrected or removed in the Ansible workflow.
- `solo.rb`: Chef Solo cookbook path, cache path, and logging configuration; no direct Ansible equivalent is required beyond project inventory and execution configuration.
- `solo.json`: Chef run list and runtime overrides for sites, SSL paths, firewall settings, and SSH hardening. These values should become Ansible group/host variables, with secrets moved to Vault.
- `project-plan.md`: Describes the surrounding X2Ansible analysis/migration tool and its intended staged workflow; it is project documentation rather than deployable infrastructure.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates to port into Ansible role templates.
- `cookbooks/nginx-multisite/files/`: Static `index.html` content for the three site folders; transfer into role files or a separately managed content deployment.

### Target Details

- **Operating System**: The declared cookbook support is Ubuntu >=18.04 and CentOS >=7. The Vagrant target is Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu `apt-get`; therefore the effective target OS is unresolved. Ansible should explicitly support one chosen family initially, preferably the intended Ubuntu/Debian path or Fedora/RHEL-compatible path, rather than silently carrying both assumptions. Package names, service names, UFW availability, PostgreSQL paths, and Nginx layout require OS-specific variables.
- **Virtual Machine Technology**: libvirt via Vagrant, with a `generic/fedora42` box. The production virtualization platform is not specified.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP integration was found.

## Migration Approach

Create an Ansible project with an inventory, a site playbook, and roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`; optionally separate `security_baseline` and `firewall` roles for ownership and reuse. Convert Chef attributes and `solo.json` into environment/group variables. Convert ERB templates to Jinja2 templates, use handlers for Nginx/Fail2ban/SSH/systemd reloads, and use check mode plus Molecule or disposable Vagrant tests for idempotence. Keep the first rollout parallel to Chef in a test VM, then perform service-by-service comparison before cutover.

### Key Dependencies to Address

- **nginx 12.3.1 Chef cookbook**: Replace with Ansible package/service tasks and the repository's Nginx Jinja2 templates. Confirm whether any behavior from the external cookbook beyond package installation is required.
- **memcached 6.1.0 Chef cookbook**: Replace with distribution package/service tasks and an explicit configuration template if non-default settings are required.
- **redisio 7.2.4 plus selinux 6.2.4**: Replace with an OS-supported Redis installation, managed Redis configuration, service enablement, and explicit SELinux policy/context tasks where the selected OS enforces SELinux.
- **ssl_certificate 2.1.0**: It is locked but not directly included by the local run list; the local SSL recipe currently generates self-signed certificates with OpenSSL. Decide whether this is development-only or replace it with a certificate authority/ACME process and Ansible certificate deployment.
- **PostgreSQL and Python runtime**: Use Ansible package, community.postgresql, `ansible.builtin.git`, `pip`, and systemd modules. The application repository currently supplies its own `requirements.txt`; pin the Git revision and dependency versions for reproducibility.
- **Chef/Berkshelf/Policyfile**: Remove from the runtime path after parity validation. Preserve the lock file as migration evidence, not as an Ansible dependency mechanism.

### Security Considerations

- **Hardcoded Redis credential**: `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Replace it immediately with an Ansible Vault secret, rotate it, and ensure Redis configuration and application consumers use the same vaulted value.
- **Hardcoded PostgreSQL credential**: `fastapi_password` appears in SQL commands and the generated `.env`, including a plaintext database URL. Generate/rotate the credential and store it in Vault; set restrictive ownership and mode on `.env` (not `0644`).
- **Application privilege**: The FastAPI systemd service runs as `root`. Create a dedicated non-root service account, restrict filesystem permissions, and assess whether the application actually needs any privileged operation.
- **TLS certificates and private keys**: Self-signed 365-day certificates are generated under `/etc/ssl/certs` and keys under `/etc/ssl/private`, with key mode 0640 and group `ssl-cert`. Keep private keys out of Git and Vault where appropriate; use trusted certificates for production and verify renewal, ownership, and Nginx reload behavior.
- **SSH hardening**: Root login and password authentication are disabled by shell edits. Implement validated `sshd_config` management with a safe connection strategy, authorized key provisioning, syntax checks, and an explicit break-glass procedure before applying changes.
- **Firewall exposure**: UFW defaults to deny and allows SSH, HTTP, and HTTPS. Reconcile this with the FastAPI listener on port 8000, which should normally remain bound to localhost or be reachable only through Nginx. Confirm the intended SSH source ranges rather than allowing unrestricted SSH.
- **Fail2ban and sysctl**: Port the provided templates and verify they match the selected OS and service log formats. Validate sysctl values in a disposable host before broad rollout.
- **Supply chain and transport**: The provisioning script downloads Chef via `curl` and clones the application from an unpinned `main` branch. Use signed/approved Ansible collections, pinned package/application revisions, checksum or repository verification, and controlled execution environments.
- **Per-module credential patterns**: `cache` contains a Redis password; `fastapi-tutorial` contains a PostgreSQL password and database URL; `nginx-multisite` contains private-key paths and self-signed certificate generation but no external secret store. No Chef encrypted data bags or Chef Vault usage were found in the reviewed files.

### Technical Challenges

- **OS mismatch**: Fedora 42 is declared by Vagrant while the provisioning script calls `apt-get`, and cookbook support lists Ubuntu/CentOS. Select and test a canonical OS first; use Ansible OS-family conditionals only when there is a confirmed requirement.
- **Chef dependency behavior is implicit**: The local Nginx cookbook directly installs packages and templates, while the Policyfile also locks external cookbooks. Establish which external cookbook behavior is actually relied upon before deleting it.
- **Non-idempotent database bootstrap**: Shell commands use `|| true`, hiding failures and making state unclear. Use PostgreSQL modules with explicit database/user ownership and password handling, and add migration tests.
- **Redis configuration hack**: A Ruby block removes several generated directives after Redisio runs. Determine why those directives are incompatible, then manage the final configuration declaratively rather than reproducing the text rewrite blindly.
- **Configuration source conflict**: `attributes/default.rb` uses `/opt/server/...` roots, while `solo.json` overrides them with `/var/www/...`; tests and expected content paths must decide which is authoritative.
- **DNS and test reachability**: The intended cluster-local names are commented out in Vagrant, and the provisioning output advertises both `192.168.56.10` and `192.168.121.10`. Add explicit test DNS/hosts setup and correct the documented addresses.
- **Template and service semantics**: Nginx site layouts, distribution-specific service names, UFW, SSH, PostgreSQL, and Redis paths vary by OS. Validate rendered configuration with `nginx -t`, SSH syntax checks, and service health probes.

### Migration Order

1. **Foundation and test harness**: Choose the target OS, create inventory/group variables, establish Ansible Vault and CI lint/check-mode testing, and reproduce the Vagrant/libvirt test topology.
2. **`nginx-multisite` security and web role**: Port packages, templates, static files, virtual hosts, handlers, firewall, Fail2ban, sysctl, SSH hardening, and certificate handling. This is the externally visible critical path.
3. **`cache`**: Migrate Memcached and Redis after deciding package/version policy and replacing hardcoded credentials and the Redis workaround.
4. **`fastapi-tutorial`**: Migrate application runtime and PostgreSQL using dedicated accounts and idempotent database modules; validate application health through Nginx.
5. **Integration and cutover**: Compare ports, rendered files, TLS behavior, service enablement, cache authentication, database connectivity, and reboot recovery; then retire Chef provisioning.

### Assumptions

- The three local cookbooks in the tree are the complete deployable source modules; no hidden Chef roles, environments, data bags, or external templates were reviewed.
- The Policyfile lock is authoritative for resolved external cookbook versions, although the lock records a dirty local working tree.
- The intended deployment is a single or small number of Linux VMs, not a cloud-native or container platform.
- The three cluster-local hostnames and static content are development/test examples unless stakeholders confirm production use.
- The intended production TLS model is not specified; self-signed certificates are assumed unsuitable for production.
- The target OS must be selected before implementation because Fedora, Ubuntu, and CentOS assumptions conflict.
- The FastAPI repository, its `requirements.txt`, database schema/migrations, and application health contract were not inspected; additional application-specific work may be required.
- The exact contents and semantics of the ERB templates were not fully reviewed here; template parity testing is required during implementation.
- PostgreSQL is expected to run locally with the application, but backup, replication, upgrade, and data-retention requirements are unspecified.
- Redis and Memcached persistence, high availability, network exposure, and resource sizing are unspecified.
- Ansible collection versions, control-node execution environment, inventory source, and secret-management platform are not specified and must be agreed by the delivery team.
- A staged rollout with rollback to the Chef-managed VM is available while validation is performed.

Team coordination should assign separate owners for OS/inventory and secrets, Nginx/security, cache services, and application/PostgreSQL migration. Require a shared acceptance checklist covering rendered configuration, service health, idempotence, reboot behavior, TLS, firewall reachability, and credential rotation before production cutover.
