# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment composed of three local cookbooks and several Supermarket dependencies. The migration scope is moderate rather than large: the inventory is limited, but it combines an Nginx multi-site edge layer, host hardening, Redis/Memcached, PostgreSQL, and a FastAPI application. A realistic initial migration is approximately **2–4 weeks** for one engineer familiar with Ansible, including implementation, testing in Vagrant/libvirt, secret remediation, and cutover validation. Add time if production certificate, database, DNS, or application deployment requirements are broader than the repository shows.

The migration should preserve the current functional boundaries while replacing Chef resources, recipe ordering, templates, and node attributes with Ansible roles, variables, handlers, and vaulted secrets. It should also resolve several source inconsistencies before production use: the Vagrant image is Fedora while provisioning uses `apt-get`, the checked-in site attributes differ from `solo.json`, and development credentials and self-signed certificate generation are embedded in cookbook code.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web-server and multi-site configuration for three SSL-enabled virtual hosts, with host hardening through Fail2ban, UFW, SSH restrictions, and sysctl settings.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx package/service management, generated virtual-host configurations, site document roots and static index files, certificate/key path configuration, self-signed RSA certificates for development, Fail2ban, UFW default-deny rules, and disabling root/password SSH authentication.
    - Ansible shape: A role with separate task files or roles for Nginx, sites, TLS, and host security; Jinja2 templates; handlers for Nginx, Fail2ban, SSH, and sysctl; data-driven site definitions.

- **cache**:
    - Description: Host caching services cookbook that installs and enables Memcached and Redis, configures a Redis server on port 6379, and applies a post-generation configuration workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, Redisio dependency, Redis password authentication, Redis log directory creation, service enablement, and removal of selected replication-related directives from the generated Redis configuration.
    - Ansible shape: A cache role using distribution-aware packages and service modules, explicit Redis configuration templates, and a documented compatibility decision for the current workaround rather than an opaque text mutation.

- **fastapi-tutorial**:
    - Description: FastAPI tutorial application deployment with Python tooling, PostgreSQL, a GitHub-sourced application checkout, a virtual environment, database/user creation, environment configuration, and a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3/pip/venv installation, PostgreSQL server and contrib packages, Git checkout of `dibanez/fastapi_tutorial` at `main`, Python dependency installation, `fastapi` PostgreSQL user/database, `.env` generation, and Uvicorn listening on all interfaces at port 8000.
    - Ansible shape: An application role using package, git, pip/virtualenv, PostgreSQL modules, a templated systemd unit, and handlers for daemon reload/restart. Pin the application revision and Python dependencies before production migration.

**CRITICAL PATH VERIFICATION:**
All module paths above were present in the supplied repository tree and their primary entrypoint files were reviewed. No Puppet, Salt, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef dependency source and local cookbook declarations. It references Supermarket cookbooks `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; an `ssl_certificate` declaration is commented out. Replace the dependency resolution process with Ansible role/collection requirements and OS package repositories.
- `Policyfile.rb`: Chef policy and run list. It runs `nginx-multisite::default`, `cache::default`, and `fastapi-tutorial::default`, and explicitly declares `ssl_certificate ~> 2.1` in addition to the Berksfile dependencies.
- `Policyfile.lock.json`: Resolved versions include Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. It also records local cookbook revisions and a dirty working tree; use it as a baseline for behavior, not as an Ansible dependency format.
- `solo.rb`: Chef Solo configuration, including `/var/chef-solo` cache and cookbook paths. It has no direct Ansible equivalent; replace with inventory, `ansible.cfg`, role paths, and execution environment configuration.
- `solo.json`: Chef node attributes and run list. It defines the three cluster.local sites, SSL directories, and security flags. It conflicts with `cookbooks/nginx-multisite/attributes/default.rb` for document roots (`/var/www/...` here versus `/opt/server/...` in cookbook defaults); establish one authoritative variable set.
- `Vagrantfile`: Local test environment using `generic/fedora42`, hostname `chef-nginx`, libvirt with 2 GB RAM and 2 CPUs, private IP `192.168.121.10`, forwarded ports 8080/8443, and rsync to `/chef-repo`. Adapt provisioning to invoke `ansible-playbook` against the guest and retain this as the first integration test target.
- `vagrant-provision.sh`: Installs Chef through a remote installer, Berkshelf, cookbook dependencies, and runs Chef Solo. Replace it with a minimal Ansible bootstrap or use Ansible from the host with SSH; do not retain the remote shell installer pattern without supply-chain review.
- `cookbooks/nginx-multisite/templates/`: Source configuration for Nginx, sites, security, Fail2ban, and sysctl. Convert ERB to Jinja2 and preserve file ownership, modes, and handler notifications.
- `cookbooks/nginx-multisite/files/`: Static `index.html` content for `ci`, `status`, and `test` sites. Move to the corresponding Ansible role `files/` tree or, preferably, deploy application content from a versioned artifact.
- `project-plan.md`: Existing project documentation should be updated after the Ansible design is agreed; it was not used as an implementation authority because the source manifests and policy files define the effective Chef behavior.

### Target Details

- **Operating System**: The declared Vagrant target is Fedora 42, but `vagrant-provision.sh` uses `apt-get`, and the cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The actual target OS is therefore unresolved. Select and test a supported target explicitly; if Fedora 42 is retained, use `dnf`, Fedora service names, firewalld/SELinux conventions, and Fedora PostgreSQL package behavior. Do not assume Ubuntu merely because the script uses `apt-get`.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync-based source synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP integration was identified.
- **Network/application endpoints**: The source expects HTTP/HTTPS virtual hosts for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; the FastAPI service listens on port 8000, although the reviewed Nginx recipe does not clearly establish a reverse-proxy relationship to it. Confirm intended routing.

## Migration Approach

1. Freeze the effective Chef baseline by testing the current policy and recording the actual OS, package versions, generated Nginx configuration, site roots, service state, firewall rules, Redis configuration, and application health.
2. Resolve source ambiguities before translating: authoritative document roots, intended OS, whether Redis authentication is a real production secret, certificate ownership/provisioning, and whether Nginx should proxy to FastAPI.
3. Create an Ansible project with `inventories/`, `group_vars/`, `host_vars/`, and roles for `nginx_multisite`, `host_security`, `cache`, and `fastapi_tutorial`. Keep application, cache, and edge concerns independently testable.
4. Translate Chef attributes into typed group variables. Use handlers instead of Chef notifications and use Ansible modules rather than shell commands wherever possible.
5. Implement and test the low-risk service roles first, then security controls, then the application/database role, and finally the integrated Nginx/TLS path.
6. Run idempotence tests and service-level checks in Fedora (or the selected final OS), including repeat playbook execution, virtual-host responses, TLS validation, Redis/Memcached connectivity, PostgreSQL login, and FastAPI systemd health.
7. Perform a staged cutover with rollback to the Chef-managed host until configuration parity and application data migration are confirmed.

### Key Dependencies to Address

- **Nginx 12.3.1 Chef cookbook**: Replace with Ansible `ansible.builtin.package`, `template`, `file`, `service`, and validation commands such as `nginx -t`; decide whether to use an Ansible Galaxy Nginx role or maintain a focused local role.
- **Memcached 6.1.0 Chef cookbook**: Replace with distribution packages and an explicit Memcached configuration/service task set. Verify bind address and exposure; the reviewed cookbook does not show a required authentication model.
- **Redisio 7.2.4 and SELinux 6.2.4**: Replace with OS Redis packages or a vetted Ansible role, explicit configuration, service enablement, and SELinux policy/labels. Preserve only the required Redis directives after validating why the Chef `ruby_block` removes them.
- **ssl_certificate 2.1.0**: It is locked by the Policyfile but not actively declared in the Berksfile and the reviewed local cookbook directly generates self-signed certificates instead. Replace it with Ansible-managed certificates, ACME automation, or externally provisioned production certificates; do not assume the locked Chef dependency is used.
- **PostgreSQL**: The application cookbook installs the distribution PostgreSQL packages and creates a database/user through raw `psql` commands. Use `community.postgresql` modules, define desired state idempotently, and validate server version and authentication behavior.
- **FastAPI Git repository and Python requirements**: The source tracks `main` and installs an unpinned requirements file. Pin a commit/tag and lock Python dependencies in the deployment process; decide whether Git checkout is appropriate for production.
- **Chef Supermarket/Omnibus installation**: Remove Chef and Berkshelf from the target build. Establish Ansible execution environments and collection versions in CI.

### Security Considerations

- **Hardcoded Redis credential**: `cache/recipes/default.rb` contains `redis_secure_password_123`. Move the Redis password to Ansible Vault or an external secret manager, render it with restrictive permissions, and avoid exposing it in command output or logs.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` in SQL and in a world-readable `.env` file (`0644`). Generate/store the credential in Vault, use PostgreSQL modules, set `.env` to a least-privilege mode such as `0600`, and avoid putting secrets in process arguments.
- **TLS certificates and private keys**: The source creates self-signed certificates for each site under `/etc/ssl/certs` and keys under `/etc/ssl/private`, with keys mode `0640` and group `ssl-cert`. This is suitable only for development. Production certificates must come from an approved PKI/ACME process, with private-key rotation, restricted access, and renewal monitoring.
- **SSH hardening**: Root login is disabled and password authentication is disabled using `sed`. Translate to `ansible.builtin.lineinfile` or a managed drop-in, validate `sshd -t` before restart, and ensure an administrative key-based access path exists before applying the change.
- **Firewall and exposure**: UFW is configured to deny by default while allowing SSH, HTTP, and HTTPS. On Fedora, UFW may not be the platform standard; use firewalld or explicitly install and support UFW. Confirm whether port 8000, Redis, Memcached, and PostgreSQL must remain localhost-only.
- **Fail2ban and sysctl**: Preserve the reviewed jail and sysctl intent, but validate distro-specific paths and settings. Apply least privilege and test that changes do not lock out operators.
- **Application privilege**: The FastAPI systemd service runs as `root`. Create a dedicated non-root service account, constrain filesystem access, and review writable directories before migration.
- **Supply-chain controls**: The provision script downloads and executes Chef’s installer via `curl`, and the application clones `main` from GitHub. Replace both with pinned, verified artifacts and controlled CI dependencies.
- **Per-module credential summary**: `nginx-multisite` handles private keys and self-signed certificate material; `cache` contains a Redis password; `fastapi-tutorial` contains PostgreSQL credentials in SQL and `.env`. No encrypted data bags, Chef Vault usage, or external secret manager configuration was identified in the reviewed files.

### Technical Challenges

- **OS mismatch**: Fedora 42 is provisioned with Debian/Ubuntu `apt-get` commands. Decide the target OS first and implement package names, firewall, SELinux, PostgreSQL, SSH, and service differences accordingly.
- **Conflicting site roots**: cookbook defaults use `/opt/server/{test,ci,status}`, while `solo.json` uses `/var/www/{...}`. The migration must establish precedence and test the selected paths against static file deployment and Nginx templates.
- **Chef resource ordering and idempotence**: Raw `execute`, `ruby_block`, `sed`, and `psql` commands are less declarative than Ansible modules. Replace them with state-aware modules and handlers; use shell only where no suitable module exists and guard it carefully.
- **Redis compatibility workaround**: The post-processing removes multiple replication and buffer directives. Determine the Redis version and intended topology before translating; blindly copying the workaround could produce an invalid or insecure configuration.
- **Certificate lifecycle**: The current certificates are generated only when absent and are self-signed for 365 days. Production migration needs certificate issuance, renewal, SAN validation, reload behavior, and rollback.
- **Application deployment ambiguity**: The repository does not show the FastAPI application source, migration commands, health checks, or a production process model beyond Uvicorn. Validate database schema initialization, expected environment variables, and reverse-proxy requirements.
- **External cookbook behavior**: Important behavior comes from locked `nginx`, `memcached`, `redisio`, `selinux`, and `ssl_certificate` cookbooks, but their source is not present. Use the local recipes as the primary contract and capture any required behavior through black-box tests rather than assuming Chef defaults.
- **Testing and DNS**: The Vagrant comments show optional `/etc/hosts` entries, while the provision script prints a different IP (`192.168.56.10`) from the Vagrant private IP (`192.168.121.10`). Correct endpoint documentation and add deterministic host-resolution tests.

### Migration Order

1. **Baseline and platform decision**: Confirm Fedora versus Ubuntu/RHEL-family target, correct Vagrant/provisioning endpoint documentation, and capture Chef-generated state.
2. **cache**: Implement Memcached and Redis with vaulted credentials and service checks. It has limited local logic but must resolve the Redis workaround securely.
3. **nginx-multisite static/site foundation**: Implement package, document roots, static files, Nginx service, site templates, and data-driven variables without initially enabling production TLS.
4. **host security portion of nginx-multisite**: Apply SSH, firewall, sysctl, Fail2ban, and SELinux-compatible controls after console/key-based recovery is proven.
5. **fastapi-tutorial**: Implement PostgreSQL, least-privilege application account, pinned application checkout/dependencies, secret-backed environment configuration, and systemd service.
6. **TLS and integrated routing**: Deploy approved certificates, validate all three hostnames, determine whether Nginx proxies to FastAPI, and test HTTP/HTTPS behavior and reloads.
7. **Cutover and decommissioning**: Run idempotence and regression tests, perform staged production deployment, monitor services, and remove Chef only after rollback criteria are met.

### Assumptions

- The three local cookbook directories are the complete source modules requiring migration.
- Chef Solo is the effective execution model; no Chef Server, encrypted data bags, roles, environments, or node management files were identified.
- The Policyfile lock is a dependency baseline, but the exact behavior of external cookbooks is not available in this repository and must be validated separately.
- `solo.json` is intended to override cookbook defaults, but the document-root conflict is unresolved.
- The Vagrant Fedora 42 image reflects the desired development target, although the shell script strongly suggests an Ubuntu-oriented implementation.
- The target deployment may be a VM or on-premises host; no cloud provider, load balancer, DNS automation, or external database is specified.
- The `cluster.local` names are test names and require DNS or `/etc/hosts`; no production DNS ownership is documented.
- Self-signed certificates are for development only; production certificate sources, domains, and renewal ownership must be supplied by the platform/security team.
- The FastAPI Git repository, its `requirements.txt`, schema/migrations, and runtime behavior are external to this repository and require application-team validation.
- PostgreSQL is intended to run locally on the same host as FastAPI; high availability, backup, restore, and data migration requirements are not specified.
- Redis is intended as a single local server, not a replicated production topology; the source’s removed replication directives make this particularly important to confirm.
- The current firewall policy is intended to expose only SSH, HTTP, and HTTPS; whether application, cache, or database ports need network access is not documented.
- Existing static HTML files are representative site content and not necessarily the complete application content.
- The migration team should include platform/Ansible ownership, application ownership for FastAPI/PostgreSQL, and security ownership for SSH/firewall/TLS/secrets. Agree on code review, Vault access, CI idempotence tests, acceptance criteria, and rollback responsibility before implementation.
