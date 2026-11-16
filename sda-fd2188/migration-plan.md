# MIGRATION FROM CHEF TO ANSIBLE

This is a small Chef Solo/Policyfile repository with three local cookbooks and a single Vagrant-based development target. The migration is modest in module count but contains several high-risk areas: plaintext application and Redis credentials, self-signed TLS generation, firewall/SSH hardening, mutable upstream application code, and shell-based database provisioning. A two- to four-week migration is a reasonable estimate for one engineer, including Ansible implementation, Molecule or equivalent testing, security remediation, and cutover validation; production hardening or unknown deployment requirements could extend this to four to six weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and configures Nginx as a three-site HTTPS web server, creates site document roots and sample content, applies host security controls, and generates development certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: `nginx::default`-style package/service management implemented locally, three `*.cluster.local` virtual hosts, Nginx and security templates, Fail2ban, UFW default-deny rules, SSH hardening, sysctl settings, site enablement links, and self-signed RSA certificates.
    - Internal recipes: `default`, `nginx`, `security`, `sites`, and `ssl` are included by the default recipe and should become coordinated Ansible role tasks/handlers rather than five unrelated roles.

- **cache**:
    - Description: Installs and enables Memcached and Redis, configures a Redis listener with authentication, creates the Redis log directory, and applies a post-generation configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, Redis via `redisio`, password-protected Redis on port 6379, Redis enablement, directory ownership, and a Ruby-based cleanup of replication-related settings.

- **fastapi-tutorial**:
    - Description: Provisions a FastAPI tutorial application from GitHub, installs Python/PostgreSQL prerequisites, creates a virtual environment, installs requirements, creates a PostgreSQL database/user, writes an environment file, and runs Uvicorn under systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3 and pip/venv, Git checkout of `dibanez/fastapi_tutorial` at `main`, local PostgreSQL, FastAPI database initialization, systemd service on port 8000, and root-owned application execution.

**CRITICAL PATH VERIFICATION:**
All module paths above are present in the supplied repository tree. No Puppet, Salt, or PowerShell modules were identified. `recipes/*.rb`, `metadata.rb`, Berkshelf, and Policyfile files establish Chef as the source technology.

### Infrastructure Files

- `Berksfile`: Declares the local cookbooks and external Supermarket dependencies. It includes Nginx `~> 12.0`, Memcached `~> 6.0`, and RedisIO `~> 7.2.4`; the SSL cookbook line is commented out here.
- `Policyfile.rb`: Defines the active run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and includes the SSL cookbook as an active dependency, unlike the Berksfile.
- `Policyfile.lock.json`: Locks local cookbooks at version 1.0.0 and external versions Nginx 12.3.1, Memcached 6.1.0, RedisIO 7.2.4, SELinux 6.2.4, and `ssl_certificate` 2.1.0. It also records the cache-to-Memcached/RedisIO and RedisIO-to-SELinux dependency edges. The local working tree was recorded as not clean.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and ports 80/443 forwarded to 8080/8443. It rsyncs the repository and invokes `vagrant-provision.sh`.
- `vagrant-provision.sh`: Installs Debian/Ubuntu packages with `apt-get`, installs Chef and Berkshelf dynamically, vendors cookbooks, and runs Chef Solo. This is inconsistent with the Fedora 42 Vagrant box and must be corrected or replaced by an Ansible provisioner.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration.
- `solo.json`: Alternate Chef Solo run list and overrides for Nginx sites/security. Its document roots differ from the cookbook defaults, so precedence and intended values must be resolved.
- `project-plan.md`: Describes the surrounding X2Ansible analyzer/exporter workflow and expected component-level migration and validation artifacts; it is planning context rather than deployable configuration.
- `cookbooks/nginx-multisite/attributes/default.rb`: Defines the three sites, SSL paths, and security defaults. These values should become documented Ansible role defaults/group variables.
- `cookbooks/nginx-multisite/templates/`: Contains Nginx, site, security, Fail2ban, and sysctl templates to port to Ansible templates after syntax and platform review.
- `cookbooks/nginx-multisite/files/`: Contains static `index.html` content for test, CI, and status sites.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom resource is present in the tree but was not invoked by the reviewed entrypoint; confirm whether it is dead code before migration.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The actual Vagrant target is Fedora 42, while the provisioning script uses `apt-get`, `www-data`, UFW, and Debian-style service/package assumptions. The target OS is therefore unresolved. Choose and test one supported family explicitly; if no production specification exists, use the requested planning default of RHEL 9 and adapt package names, firewalld, SELinux, users, and paths. Fedora compatibility should not be assumed.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; 2 vCPUs and 2 GB memory. The development VM uses a private network and forwarded HTTP/HTTPS ports.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was identified.

## Migration Approach

Create an Ansible project with a site playbook and three roles, preferably `nginx_multisite`, `cache`, and `fastapi_tutorial`, plus shared handlers and explicit inventory/group variables. Preserve the Chef execution order initially, then improve it: base packages and security prerequisites, cache services, PostgreSQL/application, and finally Nginx sites/TLS. Convert Chef templates and static files directly where appropriate, but replace shell/ruby workarounds with idempotent Ansible modules and validated configuration.

### Key Dependencies to Address

- **Nginx 12.3.1 Chef cookbook**: Replace with Ansible `ansible.builtin.package`, `template`, `file`, `service`, and `community.general.sefcontext`/SELinux tasks as required. Do not assume the Chef cookbook's defaults; explicitly manage Nginx package and service behavior.
- **Memcached 6.1.0**: Replace with distribution package/service tasks and an explicit configuration model. Decide whether Memcached is required by the application, bind it safely, and avoid exposing it beyond the private interface.
- **RedisIO 7.2.4 and SELinux 6.2.4**: Replace with OS packages or a vetted Redis role, explicit Redis configuration, service management, and SELinux policy/port/file-label tasks. Validate the Redis version and replication semantics before removing the current cleanup workaround.
- **ssl_certificate 2.1.0**: It is locked and listed in Policyfile but not visibly used by the reviewed local recipes; determine whether it was intended for certificate deployment. In Ansible, use vaulted certificate material, an approved ACME role, or an external certificate platform rather than generating production self-signed keys.
- **FastAPI Git repository and Python requirements**: Replace Chef `git` and `execute` resources with `ansible.builtin.git`, package/venv tasks, and a pinned dependency strategy. Pin a commit or release rather than tracking `main` for repeatable deployments.
- **PostgreSQL**: Use distribution-specific packages and `community.postgresql.postgresql_db`/`postgresql_user` with a local connection or carefully managed peer authentication. Remove `|| true` behavior and make database creation verifiable and idempotent.
- **systemd, UFW/Fail2ban, and sysctl**: Use `ansible.builtin.systemd_service`, `community.general.ufw` where Ubuntu is selected, `ansible.posix.firewalld` for RHEL/Fedora, `community.general.sysctl`, and template-driven Fail2ban configuration. These are platform-dependent and require OS-specific task branches.

### Security Considerations

- **Plaintext Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123` in source and writes it into Redis configuration. Move it to Ansible Vault or an external secret manager, rotate it, restrict Redis bind/listen access, and ensure rendered files have restrictive permissions.
- **Plaintext PostgreSQL credentials**: `fastapi-tutorial` embeds `fastapi_password` in SQL commands, `.env`, and the database URL. Treat it as compromised, rotate it, store it in Vault, use `no_log: true` for credential-bearing tasks, and set `.env` to a private mode rather than 0644.
- **TLS certificates and keys**: The SSL recipe generates one-year self-signed RSA keys under `/etc/ssl`; private keys are group-readable by `ssl-cert`. This is acceptable only for development. For production, define certificate ownership, renewal, SANs, chain handling, key rotation, and secret distribution. Never commit private keys.
- **SSH hardening**: Root login and password authentication are disabled by default. Preserve this only after ensuring an administrative key-based account and console/recovery path exist; validate sshd syntax before restart to avoid lockout.
- **Firewall exposure**: UFW allows SSH, HTTP, and HTTPS and defaults to deny, but the target may be Fedora/RHEL where firewalld is the native mechanism. Define allowed source networks and avoid opening Redis, Memcached, PostgreSQL, or port 8000 externally.
- **Nginx and host security**: Port the security and sysctl templates with a review of headers, TLS protocols, kernel settings, and Fail2ban filters. Use Ansible validation (`nginx -t`, `sshd -t`, and syntax checks) before handlers restart services.
- **Application privilege**: The FastAPI service runs as root. Create a dedicated non-login service account, make only required paths writable, and separate deployment from runtime ownership.
- **Supply chain and execution**: The bootstrap downloads Chef from a live URL and the application tracks a public Git `main` branch. Replace with pinned, verified artifacts and CI checks; review Python requirements for hashes and known vulnerabilities.

### Technical Challenges

- **OS mismatch**: Fedora 42 is declared but the script uses `apt-get`, UFW, and Debian conventions. Resolve the production OS first, then implement OS-specific Ansible vars/tasks and test on the selected image.
- **Conflicting configuration sources**: Cookbook defaults use `/opt/server/{test,ci,status}`, while `solo.json` uses `/var/www/{site}`. Establish one authoritative inventory/variables model and document per-environment overrides.
- **Hidden template behavior**: Nginx, security, Fail2ban, and sysctl templates were not expanded in the high-level review. Port them only after reviewing their directives, then validate with service-native syntax checks and functional HTTP/TLS tests.
- **Non-idempotent shell commands**: PostgreSQL creation uses `|| true`; certificate generation and Redis file mutation depend on shell/file content. Replace with modules and explicit changed/failed states, including migrations for existing hosts.
- **Dependency and role semantics**: Chef external cookbooks provide behavior not visible in local recipes. Reproduce only the required behavior, pin Ansible collections/role versions, and maintain a dependency lock or requirements file.
- **Service ordering**: FastAPI depends on PostgreSQL and Nginx sites may depend on application availability. Use handlers, service dependencies, health checks, and a defined deployment order rather than relying on Chef convergence order.
- **Domain and certificate testing**: The three `cluster.local` names need DNS or `/etc/hosts` entries; the Vagrant host-entry block is commented out. Add test inventory resolution and verify forwarded-port behavior separately from guest-port behavior.

### Migration Order

1. **Foundation and target contract**: Decide OS, inventory topology, credentials backend, DNS/certificate ownership, and whether the Vagrant/libvirt environment remains the acceptance target.
2. **Cache role**: Implement Memcached and Redis with vaulted credentials, safe binds, service checks, and platform-specific SELinux/firewall handling. This is relatively isolated but security-sensitive.
3. **FastAPI/PostgreSQL role**: Implement packages, pinned source, virtualenv, database objects, non-root systemd service, secrets, and health checks. Validate application connectivity before exposing it.
4. **Nginx multisite and security role**: Port templates/static files, virtual hosts, TLS deployment, Fail2ban, sysctl, SSH, and firewall rules. Test certificate paths and all three hostnames.
5. **Integration and cutover**: Run the complete site playbook in a disposable VM, compare package/service/configuration outcomes with Chef, perform rollback testing, then migrate environments incrementally.

### Assumptions

- The three local cookbooks are the complete active source scope; external cookbook internals are not being migrated wholesale.
- The Policyfile run list is authoritative over the alternate `solo.json` run list, and the locked versions are the baseline dependency versions.
- The application is intended to run locally with PostgreSQL and is reachable behind Nginx, although the reviewed recipe does not explicitly configure an Nginx reverse proxy to port 8000; this must be confirmed.
- The three `cluster.local` names are development/test names and do not represent production DNS.
- Self-signed certificates are development-only; production certificate requirements and the intended use of `ssl_certificate` are unknown.
- The plaintext credentials are examples but must nevertheless be rotated and treated as exposed.
- The contents and intended behavior of the Nginx/security templates require a follow-up review before exact parity claims can be made.
- The intended production OS is not specified. Ubuntu/CentOS metadata, Fedora Vagrant, and Debian bootstrap assumptions conflict; no OS should be selected for production without owner confirmation.
- There is no evidence of cloud infrastructure, load balancing, external secret management, CI pipeline, backup policy, monitoring, or high availability.
- `resources/lineinfile.rb` may be unused; its migration is conditional on confirming references outside the reviewed entrypoint.
- The Vagrant provisioning script's displayed `192.168.56.10` URL conflicts with the Vagrant private IP `192.168.121.10`; acceptance tests should use the actual configured address.
- Timeline assumes one engineer familiar with Ansible, Chef, Linux security, and PostgreSQL, with application and security owners available for decisions and validation.

Team coordination should assign an infrastructure owner for the role structure and inventory, a security owner for secrets/SSH/firewall/TLS review, and an application owner for FastAPI/PostgreSQL behavior. Require pull requests per role, CI linting and molecule-style tests on the selected OS, a configuration parity checklist, and an approved rollback plan before decommissioning Chef.