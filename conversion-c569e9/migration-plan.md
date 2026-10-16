# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Vagrant environment containing three local cookbooks: an Nginx multi-site/security stack, caching services, and a FastAPI tutorial application with PostgreSQL. The migration is moderate in operational risk despite the small module count because the source embeds credentials, generates development certificates, modifies host firewall/SSH settings, and uses imperative shell commands. A focused migration can be completed in approximately 2–4 weeks, including Ansible implementation, secure variable redesign, Fedora/Ubuntu validation, and functional/security testing. Production hardening and certificate/secret integration may extend this to 4–6 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and manages Nginx for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), publishes static index pages, and applies HTTP, TLS, header, compression, and request-hardening settings.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management, templated virtual hosts, HTTP-to-HTTPS redirects, self-signed RSA certificates for development, UFW firewall rules, Fail2ban jails, SSH hardening, sysctl settings, and security headers.

- **cache**:
    - Description: Configures Memcached and Redis, including a Redis listener on port 6379, log directory creation, service enablement, and a post-configuration workaround that removes selected replication directives.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion, Redis authentication, Redis log directory, Redis configuration workaround, and Redis service enablement.

- **fastapi-tutorial**:
    - Description: Installs the Python/PostgreSQL runtime for a FastAPI tutorial application, checks out the application from GitHub, creates a virtual environment, installs requirements, creates a PostgreSQL database/user, writes environment configuration, and runs Uvicorn under systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3 and virtualenv setup, PostgreSQL packages/service, Git deployment from `https://github.com/dibanez/fastapi_tutorial.git` at `main`, database bootstrap, `.env` generation, and systemd service management on port 8000.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree and their primary `recipes/default.rb` entrypoints were reviewed. No Puppet, Salt, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and external cookbook constraints. It includes Nginx `~> 12.0`, Memcached `~> 6.0`, and RedisIO `~> 7.2.4`; the SSL cookbook line is commented out here.
- `Policyfile.rb`: Defines the policy run list and dependencies. It explicitly includes `ssl_certificate ~> 2.1` in addition to the other external cookbooks.
- `Policyfile.lock.json`: Locks local cookbooks and external dependencies, including Nginx 12.3.1, Memcached 6.1.0, RedisIO 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. This is the best source snapshot for dependency baselining during migration.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, 2 CPUs, private address `192.168.121.10`, and forwarded ports 8080/8443. It syncs the repository and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. This conflicts with the Fedora base box and must be replaced with an Ansible-compatible bootstrap.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration.
- `solo.json`: Chef Solo run list and overrides for sites, paths, SSL, firewall, and SSH behavior. Its document roots differ from the cookbook attribute defaults and should be resolved explicitly in Ansible.
- `cookbooks/nginx-multisite/attributes/default.rb`: Defines the three sites, document roots, certificate paths, and security defaults.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates to be converted to Jinja2 templates or native Ansible modules.
- `cookbooks/nginx-multisite/files/default/`: Static `index.html` content for the test, CI, and status sites.
- `project-plan.md`: Existing project context should be reviewed by the migration team before implementation, but it was not required to identify the Chef modules.

### Target Details

- **Operating System**: The Chef metadata supports Ubuntu >=18.04 and CentOS >=7. The Vagrant target is Fedora 42, while `vagrant-provision.sh` assumes Debian/Ubuntu (`apt-get`, `/var/log/auth.log`, and UFW). The migration must select and document a supported target; Fedora 42 is the explicit test target, but an initial implementation should account for `dnf`, firewalld/ nftables, Fedora service/package names, and SELinux. Do not assume the current Ubuntu-oriented commands work on Fedora.
- **Virtual Machine Technology**: Vagrant using the libvirt provider; 2 CPUs and 2048 MB memory.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP integration was found.

## Migration Approach

### Key Dependencies to Address

- **Nginx 12.3.1 Chef cookbook**: Replace with `ansible.builtin.package`, `service`, `template`, `file`, and `ansible.builtin.validate`/`nginx -t` handlers. Preserve virtual-host generation, static content, TLS settings, and reload behavior.
- **Memcached 6.1.0**: Replace with distribution packages and an Ansible service task, with explicit bind/listen and firewall policy. Confirm whether the application actually consumes Memcached.
- **RedisIO 7.2.4 and SELinux 6.2.4**: Replace RedisIO with OS packages or an approved Redis role/collection. Model Redis configuration declaratively rather than editing the generated file with a Ruby block. Add SELinux policy/context tasks for Fedora or document a supported Ubuntu target.
- **ssl_certificate 2.1.0**: The lock and Policyfile include it, but the active local SSL recipe generates self-signed certificates directly and does not visibly invoke the dependency. Decide whether development self-signed certificates remain acceptable or replace them with Ansible-managed CA/ACME or externally provisioned certificates.
- **PostgreSQL and Python system packages**: Use OS-family-specific package variables and Ansible modules. Add explicit PostgreSQL role/database/user tasks and idempotent password handling.
- **FastAPI Git repository and Python requirements**: Pin a commit or release rather than tracking `main`; use `ansible.builtin.git`, `pip`/virtualenv tasks, and a managed systemd unit. Review upstream requirements for reproducibility and supply-chain controls.
- **Vagrant/libvirt test harness**: Replace Chef shell provisioning with `ansible_local` or host-driven Ansible provisioning. Keep the private address and port forwarding, but add host-name resolution for all three domains.

### Security Considerations

- **Hardcoded Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, avoid exposing it in task output, and rotate it during migration.
- **Hardcoded PostgreSQL credentials**: The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes the same value into a world-readable (`0644`) root-owned `.env`. Replace with Vault-managed credentials, set restrictive permissions such as `0600`, and use PostgreSQL-specific Ansible modules instead of shell commands with `|| true`.
- **TLS private keys and certificates**: Self-signed keys are generated under `/etc/ssl/private` with group `ssl-cert`; certificate lifecycle, ownership, permissions, renewal, and trust distribution must be defined. Self-signed certificates are suitable only for development. Validate that the key directory and service access model work on Fedora/SELinux.
- **TLS configuration**: Preserve TLS 1.2/1.3 and security headers, but have the security team revalidate the cipher list, HSTS scope, CSP (which currently permits inline scripts/styles), and whether `X-XSS-Protection` is still appropriate.
- **Firewall and SSH hardening**: The cookbook defaults to deny inbound traffic, allows SSH/HTTP/HTTPS, disables root login, and disables password authentication. Implement with `ansible.posix.firewalld` on Fedora or `community.general.ufw` on Ubuntu, with a recovery/console plan to prevent lockout. Manage `sshd_config` with `lineinfile`/drop-ins and validate before restart.
- **Fail2ban and logging**: Preserve SSH and Nginx jails, but verify log paths (`/var/log/auth.log` is Debian-oriented and Fedora commonly uses journald or `/var/log/secure`). Test filters and ban behavior before enabling in shared environments.
- **Application privilege**: The systemd service currently runs FastAPI as `root`. Create a dedicated non-root service account, constrain filesystem access, and define systemd hardening options where compatible.
- **Input and repository integrity**: Pin the Git revision and Python dependencies, verify TLS/signatures where possible, and review all downloaded artifacts before production use.

### Technical Challenges

- **OS mismatch**: Fedora 42 is provisioned using Debian commands and UFW assumptions. Mitigate with an explicit OS support matrix, family-specific variables/tasks, and tests on the chosen platform.
- **Chef attribute precedence and conflicting paths**: Cookbook defaults use `/opt/server/{test,ci,status}`, while `solo.json` overrides them to `/var/www/{site}`. Establish one Ansible inventory/group variable model and confirm expected document roots with stakeholders.
- **Imperative, non-idempotent database setup**: Shell `psql` commands use `|| true`, masking failures and making drift difficult to detect. Use `community.postgresql.postgresql_user` and `postgresql_db`, with migrations/ownership verified separately.
- **Redis configuration workaround**: The Ruby block deletes generated replication settings after RedisIO runs. Reproduce only the intended final configuration using a managed template/drop-in and test compatibility with the selected Redis package.
- **Template correctness and reload safety**: Convert ERB conditionals and variables to Jinja2, preserve site symlinks and static assets, and run `nginx -t` before reload. The current site template should be syntax-tested because it builds multiple server blocks conditionally.
- **Certificate lifecycle**: Generated certificates are one-time, 365-day development certificates. Production migration needs certificate issuance, renewal, deployment, and rollback ownership.
- **Dependency ambiguity**: Berksfile and Policyfile differ on the SSL cookbook, and locked transitive dependencies include SELinux even though it is not a local cookbook. Record only the behavior actually required rather than mechanically porting Chef dependencies.
- **Application readiness**: The FastAPI service is started but no health check, migration command, or application deployment version is defined. Add service health validation and clarify PostgreSQL schema initialization.

### Migration Order

1. **Foundation and test harness**: Select the target OS, convert Vagrant provisioning to Ansible, define inventory/group variables, Vault policy, handlers, and molecule or equivalent verification. Confirm network and hostname behavior.
2. **nginx-multisite**: Migrate package/service, Nginx templates, static files, sites, TLS development behavior, firewall, Fail2ban, SSH, and sysctl. This establishes the shared web/security patterns and is independently testable.
3. **cache**: Migrate Memcached and Redis after secret handling and OS/SELinux decisions are established. Validate local connectivity, authentication, persistence expectations, and firewall exposure.
4. **fastapi-tutorial**: Migrate PostgreSQL, application checkout, virtualenv/dependencies, secret file, dedicated service account, systemd unit, and port 8000 service. Integrate application-to-database and end-to-end checks.
5. **Hardening and cutover**: Replace self-signed certificates where needed, pin artifacts, run idempotence/security tests, compare Chef and Ansible states, and decommission Chef/Berkshelf artifacts only after rollback criteria are met.

### Assumptions

- The three local cookbooks listed in the tree are the complete migration scope; external Chef cookbooks are dependencies to replace, not separately owned local modules.
- The intended runtime is a single Vagrant/libvirt test VM, with no production inventory or cloud topology supplied.
- Fedora 42 is the explicit VM target, but the cookbook metadata indicates Ubuntu/CentOS intent; the target OS must be confirmed before final role design.
- The application repository, its `requirements.txt`, and its runtime behavior were not included, so dependency and database migration requirements remain to be validated.
- `solo.json` is intended to override cookbook defaults, but the conflicting document roots must be resolved with the service owner.
- The three hostnames require DNS or `/etc/hosts`; the commented Vagrant host entries indicate this is not currently automated.
- Port 8000 is used by FastAPI internally, but no Vagrant forwarding or Nginx reverse-proxy route to it is configured in the reviewed files.
- Self-signed certificates are for development only; production certificate authority and renewal requirements are unknown.
- Redis authentication is required, but persistence, bind address, replication, and external client requirements are unspecified.
- No Chef encrypted data bags, Chef Vault, environment-variable secret store, or external secret manager was found in the reviewed files; visible credentials are hardcoded and must be treated as compromised.
- Existing `project-plan.md` may contain additional business requirements and should be reconciled with this technical plan before implementation.
- Estimated effort assumes one platform, three Ansible roles, basic CI/idempotence tests, and one migration rehearsal; multi-OS production support or HA databases/caches require additional design.
