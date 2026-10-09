# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile infrastructure project with three local cookbooks and four externally resolved cookbooks. The active convergence config provisions an Nginx multi-site host, Redis and Memcached, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in operational risk despite the small module count because it contains hardcoded credentials, shell-based database provisioning, custom Redis configuration repair logic, self-signed TLS generation, firewall/SSH hardening, and a source-OS inconsistency. A focused implementation can be completed in approximately **2–4 weeks**: one week for inventory and role scaffolding, one to two weeks for implementation and testing, and several days for security review, cutover rehearsal, and documentation. The estimate assumes one target Linux distribution and no production-only behavior hidden outside this repository.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server configuration for multiple virtual hosts, static document roots, security headers/configuration, firewall and SSH hardening, and SSL-enabled site definitions.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Composed default recipe; Nginx installation and service management; three site definitions from `solo.json`; per-site document roots and bundled static pages; fail2ban; UFW default-deny rules; sysctl security settings; disabling root SSH login and password authentication; generated self-signed certificates.
    - Migration shape: An Ansible role with separate task files for Nginx, sites, TLS, and host security, plus Jinja2 templates and handlers for Nginx/fail2ban/SSH/sysctl changes.

- **cache**:
    - Description: Redis and Memcached cache-service setup, including Redis authentication, log-directory creation, service enablement, and a compatibility cleanup of generated Redis replication settings.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached cookbook inclusion; Redis server on port 6379; Redis `requirepass`; `/var/log/redis` ownership and permissions; custom post-configuration removal of replication directives; Redis enablement.
    - Migration shape: An Ansible role using distribution-appropriate Redis and Memcached packages/services, a managed Redis configuration template, and an explicit decision about whether the existing configuration workaround remains necessary.

- **fastapi-tutorial**:
    - Description: Host installation and deployment of the FastAPI tutorial application with Python virtualenv, PostgreSQL service, database/user creation, environment configuration, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Python 3 tooling, Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, virtual environment under `/opt/fastapi-tutorial`, pip installation, PostgreSQL and `postgresql-contrib` packages, `fastapi` database/user, root-run Uvicorn service on port 8000, and `.env` generation.
    - Migration shape: An application role with package, checkout, virtualenv, dependency, PostgreSQL, secret, systemd, and health-validation tasks. Pin the application revision and Python dependencies before production migration.

**CRITICAL PATH VERIFICATION:**
Only modules whose paths are present in the supplied repository tree are listed above. The external cookbooks resolved in the Policyfile are dependencies, not local modules and are not included in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source, local cookbook paths, and external dependency constraints. It is replaced by `collections/requirements.yml`, role dependencies, and Ansible Galaxy/private automation content as appropriate.
- `Policyfile.rb`: Defines the Chef policy name, active run list, local cookbooks, and intended external cookbook versions. Its run list becomes an Ansible site playbook and role ordering.
- `Policyfile.lock.json`: Records the resolved versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0, plus local cookbook revisions. Preserve this as migration evidence and use it to build an explicit Ansible dependency/version matrix.
- `Vagrantfile`: Defines the development VM as `generic/fedora42`, hostname `chef-nginx`, libvirt provider, 2 GiB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 8080/8443. Replace the Chef provisioning hook with an Ansible provisioner or an external `ansible-playbook` invocation.
- `vagrant-provision.sh`: Installs Chef and Berkshelf with a remote curl installer, vendors dependencies, and runs Chef Solo. It should be removed or reduced to VM bootstrap only; Ansible installation and execution should be version-pinned and preferably run from the control node.
- `solo.rb`: Chef Solo cache and cookbook paths. No direct Ansible equivalent is required beyond inventory, project layout, and role search paths.
- `solo.json`: Effective run list, three virtual hosts, SSL paths, and security switches. Convert these values into group/host variables, with secrets moved to Ansible Vault or an external secret manager.
- `project-plan.md`: Existing project coordination context; review it during implementation to reconcile stated goals with the actual Chef behavior.
- `cookbooks/nginx-multisite/attributes/default.rb`: Attribute defaults and likely variable contract for Nginx/security should be mapped to role defaults/vars after confirming any values not repeated in `solo.json`.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, fail2ban, and sysctl templates become Ansible Jinja2 templates and should be reviewed for variable names and distribution-specific syntax.
- `cookbooks/nginx-multisite/files/`: Static `index.html` files for `ci`, `status`, and `test` sites become role files or application content managed by a dedicated content role.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource requiring behavior review; replace with `ansible.builtin.lineinfile` only if it is used by the retained configuration path.

### Target Details

- **Operating System**: The cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The Vagrant box is explicitly Fedora 42, while `vagrant-provision.sh` uses `apt-get`, and the Chef recipes use Debian-oriented names such as `www-data`, `ufw`, and `postgresql`. The practical current test target is therefore ambiguous and likely Debian/Ubuntu rather than the declared Fedora box. Select and document one supported target before implementation; use OS-specific Ansible variables/tasks where necessary. If no decision is available, establish RHEL 9 as the migration baseline, but do not assume the current recipes will run unchanged there.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 vCPUs and 2048 MB memory. The private network and port forwarding are for local development/testing.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud-init configuration was found in the reviewed files.

## Migration Approach

Create an Ansible project with an inventory for the Vagrant target and separate roles named `nginx_multisite`, `cache`, and `fastapi_tutorial`. A site playbook should apply them in dependency order: base packages/host security, cache services, PostgreSQL/application, then Nginx and virtual hosts. Preserve the existing three-site test data as non-secret group variables, but make production sites, certificates, firewall allowlists, application revision, and service users configurable. Use handlers rather than shell reloads wherever Ansible modules can express the desired state. Add Molecule or equivalent VM integration tests for idempotence, service state, listening ports, virtual host rendering, and security settings.

### Key Dependencies to Address

- **Chef Supermarket `nginx` 12.3.1**: Replace with native Ansible package/service/configuration tasks or a vetted Ansible Nginx role. Do not attempt to translate cookbook internals blindly.
- **Chef Supermarket `memcached` 6.1.0**: Replace with distribution package installation, managed configuration, service enablement, and port/listening validation.
- **Chef Supermarket `redisio` 7.2.4**: Replace with a maintained Redis Ansible role or native package/configuration tasks. Explicitly model authentication and Redis version compatibility.
- **Chef Supermarket `selinux` 6.2.4**: If the selected target is Fedora/RHEL, use `ansible.posix.selinux`, policy packages, and filesystem labels. If Ubuntu is the target, document that SELinux behavior is not equivalent and validate AppArmor/UFW alternatives.
- **Chef Supermarket `ssl_certificate` 2.1.0**: The active local recipe generates certificates directly and the dependency is not visibly invoked. Replace development certificates with a controlled certificate source; use ACME/Let's Encrypt or enterprise PKI for real environments and Vault for private keys.
- **PostgreSQL packages and client tooling**: The FastAPI cookbook installs PostgreSQL locally but has no pinned PostgreSQL version or declarative schema migration. Use an Ansible PostgreSQL role/modules and idempotent database/user tasks.
- **Python/Git application source**: Replace the unpinned `main` branch checkout and unrestricted `pip install` with a pinned commit/tag, controlled requirements lock, checksum/repository trust policy, and a deployment strategy.
- **Chef run list and local cookbook composition**: Convert `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default` to explicit Ansible role order; ensure cache and application dependencies are not hidden in task includes.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Store the password in Ansible Vault or an external secret manager, rotate it, avoid exposing it in logs, and render Redis configuration with restrictive permissions.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes the same value to a world-readable (`0644`) `.env` file and service configuration context. Treat it as compromised, rotate it, use Vault, set restrictive ownership/mode, and preferably pass credentials through a protected environment file or secret mechanism.
- **TLS private keys and certificates**: The Nginx role writes keys beneath `/etc/ssl/private`, currently with group `ssl-cert` and mode `0710` on the directory and `0640` on generated keys. Preserve least privilege, ensure the Nginx worker can read keys without broad group access, and use managed production certificates rather than self-signed certificates. Never commit private keys.
- **Self-signed certificate generation**: Certificates are generated for 365 days with a fixed example subject and are intended for development. Make certificate issuance an explicit environment-specific choice and add expiry monitoring.
- **Firewall policy**: UFW is set to default deny and permits SSH, HTTP, and HTTPS, but application/database/cache ports are not explicitly modeled. Recreate rules with `community.general.ufw` or native firewalld/nftables modules, define administrative source networks, and test remote access before enabling deny policy.
- **SSH hardening**: Root login and password authentication are disabled based on `solo.json`. Apply through `ansible.posix.authorized_key`/`sshd_config` management with validation and a rollback-safe handler; confirm a non-root key-based administrative account exists before changing SSH.
- **Service privilege**: FastAPI runs Uvicorn as `root`. Create a dedicated system user, restrict filesystem ownership, and bind through Nginx or an appropriate service socket where possible.
- **Supply-chain and execution risk**: The provisioner installs Chef via a remote curl script, checks out an unpinned public Git branch, and executes pip installation. Replace with signed/version-pinned tooling and reviewed artifacts.
- **Secrets management by module**: `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials and a database URL; `nginx-multisite` handles TLS private keys but does not show an external secret store. No encrypted data bags or Chef Vault use are visible in the reviewed files. Treat any certificates or secrets supplied outside this repository as migration inputs requiring inventory and rotation.

### Technical Challenges

- **OS mismatch**: Fedora 42 in Vagrant conflicts with `apt-get`, UFW, Debian service/user conventions, and cookbook support declarations. Select Ubuntu or RHEL/Fedora as the supported target, then implement package names, service names, firewall, web-user, and security-policy differences explicitly.
- **Imperative shell behavior**: PostgreSQL setup uses `psql` commands followed by `|| true`, making failures indistinguishable from already-existing resources. Replace with idempotent PostgreSQL modules and verify ownership/privileges.
- **Redis configuration hack**: The Chef `ruby_block` edits `/etc/redis/6379.conf` by deleting replication directives after the cookbook renders it. Determine why those directives are emitted, then own the final configuration with an Ansible template or a narrowly scoped validated task.
- **Template and variable contract**: Nginx sites are generated from `node['nginx']['sites']`, while defaults may come from attributes and `solo.json`. Inventory all template variables and test rendered configuration with `nginx -t` before reload.
- **Certificate lifecycle**: Current certificates are generated only when files do not exist, with no renewal or trust distribution. Define development versus production certificate ownership, renewal, deployment, and rollback processes.
- **Application availability and repeatability**: Cloning `main`, installing dependencies on every convergence, and running as root can cause drift and outages. Introduce immutable/pinned releases, virtualenv ownership, systemd hardening, and a health check.
- **Legacy dependency assumptions**: Chef cookbook versions are locked but their Ansible replacements may have different defaults, Redis/PostgreSQL versions, and SELinux behavior. Build a compatibility matrix and test on a clean VM.
- **Port and hostname validation**: The Vagrant script advertises both `192.168.56.10` and `192.168.121.10`, while the Vagrantfile defines only the latter. Correct documentation and test DNS/hosts mappings for all three virtual hosts.

### Migration Order

1. **Baseline and security prerequisites**: Choose the target OS, create inventory/group variables, establish a non-root Ansible user, add Vault/external secret integration, and reproduce safe SSH/firewall prerequisites with rollback testing.
2. **cache**: Migrate Memcached and Redis because it is a relatively contained service role, while resolving credential handling and validating the Redis workaround.
3. **fastapi-tutorial data layer**: Install PostgreSQL, create the database/user securely, deploy the pinned application and virtualenv, and establish a dedicated system account and systemd unit. Validate application health before exposing it.
4. **nginx-multisite core**: Install and configure Nginx, migrate the three sites and static files, and add handlers/config validation.
5. **nginx-multisite security and TLS**: Apply fail2ban, firewall, sysctl, SSH hardening, and certificate integration after access paths are proven. Perform end-to-end HTTPS and renewal/rotation tests.
6. **Cutover and decommissioning**: Run Chef and Ansible in a comparison environment, verify idempotence and service behavior, then remove Chef provisioning from Vagrant and archive the locked Chef dependency record.

Estimated delivery for the three local roles is **2–4 weeks**, with a further contingency period if the target OS, production PKI, application deployment policy, or external secret platform is not already selected.

### Assumptions

- The supplied tree is complete for the migration scope and contains no hidden Chef environments, roles, data bags, encrypted secrets, CI pipelines, or production overrides.
- The three local cookbook directories are the complete module inventory; external Policyfile cookbooks are dependencies rather than locally customized modules.
- `solo.json` represents the effective development configuration, including the three sites and security flags.
- The external cookbook lock versions are historical implementation inputs, not a requirement to reproduce Chef cookbook behavior byte-for-byte.
- PostgreSQL is intended to run on the same host as FastAPI, because the recipe installs and starts a local PostgreSQL service.
- The public FastAPI Git repository is reachable from target hosts or will be mirrored into an approved artifact repository.
- The application should continue to listen on port 8000 behind Nginx, although the current Nginx site templates must be checked to confirm proxy behavior.
- The target operating system has not been resolved: Fedora 42, Ubuntu >=18.04, and CentOS >=7 are all implied by different files. OS selection is a prerequisite, not an implementation detail.
- The existing self-signed certificates are development-only; production certificate authority, DNS, and renewal requirements are not specified.
- No cloud provider or production load balancer is part of this repository.
- No backup, monitoring, log shipping, PostgreSQL schema migration, Redis persistence, or Memcached persistence requirements are documented and must be elicited before production cutover.
- The exact contents and variable contracts of the Nginx templates and attributes require validation during implementation; the migration should not assume that `solo.json` contains every default.
- Teams should designate owners for OS/platform, application, database, network/security, and certificate management; review rendered configuration and secret handling jointly before merge.
- Migration acceptance requires clean-host convergence, second-run idempotence, service health checks, `nginx -t`, firewall/SSH access verification, TLS validation, and a documented rollback to the prior Chef/Vagrant workflow.
