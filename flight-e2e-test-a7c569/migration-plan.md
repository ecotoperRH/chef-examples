# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment containing three local cookbooks and several external cookbook dependencies. The target migration is a moderate-small Ansible project, but it includes a meaningful security boundary: an nginx multi-site HTTPS front end, host firewall and SSH hardening, Redis authentication, PostgreSQL application credentials, and a FastAPI systemd service. A realistic delivery estimate is **2–4 engineer-weeks**, including implementation, Fedora/Ubuntu platform decisions, security remediation, and functional validation; a parallel team can shorten elapsed time if the nginx/security and application tracks are separated.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx reverse/static web hosting for three configured sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`) with per-site document roots, site enablement, HTTPS configuration, security hardening, fail2ban, UFW, and SSH settings.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx installation and service management, generated `nginx.conf` and site configurations, SSL certificate/key directories, development self-signed certificates, fail2ban, UFW default-deny rules, sysctl security settings, root-login and password-authentication hardening, and static site content.
    - Migration complexity: Moderate to high because it combines templating, loops over site data, service notifications, firewall state, SSH changes, certificate handling, and platform-specific paths.

- **cache**:
    - Description: Host caching services by including Memcached and Redis, configuring a Redis instance on port 6379, creating its log directory, enabling the service, and applying a post-configuration compatibility workaround.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, Redis via `redisio`, Redis authentication, Redis logging directory, service enablement, and removal of selected replication-related directives from `/etc/redis/6379.conf`.
    - Migration complexity: Moderate because the Redis password is currently embedded in source and the workaround directly edits generated configuration; the final Ansible role should own the configuration declaratively instead.

- **fastapi-tutorial**:
    - Description: Installs a FastAPI tutorial application from GitHub, prepares a Python virtual environment and dependencies, provisions local PostgreSQL, creates the application database/user, writes `.env`, and runs Uvicorn as a systemd service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3 tooling, Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, virtualenv and pip installation, PostgreSQL service, database initialization, systemd unit on port 8000, and automatic service startup.
    - Migration complexity: Moderate to high due to external source drift, database idempotency, package/repository differences, secret handling, service ordering, and the current root-run service model.

**CRITICAL PATH VERIFICATION:**
The three cookbook paths above were present in the supplied repository tree and their `recipes/default.rb` entrypoints were reviewed. External cookbooks are dependencies, not local modules, and are therefore not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef Supermarket source, local cookbook paths, and declared external cookbook constraints. It is replaced by Ansible collection/role requirements and project documentation.
- `Policyfile.rb`: Defines the policy name, run list, local cookbook sources, and external dependency constraints. Its run list becomes an Ansible site playbook and role ordering.
- `Policyfile.lock.json`: Resolved dependency graph and versions. It records nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, selinux 6.2.4, and ssl_certificate 2.1.0, plus local cookbook revisions. Preserve this as migration evidence while replacing behavior with tested Ansible roles.
- `Vagrantfile`: Defines a `generic/fedora42` VM, hostname `chef-nginx`, private IP `192.168.121.10`, forwarded ports 8080/8443, libvirt resources (2 GiB RAM and 2 CPUs), and an rsync-mounted repository. It is the primary local integration-test harness and should be updated to invoke Ansible.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. Replace this with Ansible installation/invocation or a host-side Ansible workflow; its `apt-get` commands conflict with the Fedora base box and must not be copied unchanged.
- `solo.rb`: Chef Solo cache and cookbook search paths plus logging. It has no direct Ansible equivalent beyond repository layout and logging configuration.
- `solo.json`: Chef run list, three site definitions, SSL paths, and security attributes. Convert it to structured Ansible inventory/group variables, preferably separating non-secret site topology from encrypted secrets.
- `project-plan.md`: Documents the surrounding X2Ansible tool and workflow. Use it as coordination context, but validate generated Ansible against actual runtime behavior rather than treating the tool specification as infrastructure configuration.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, SSL, and security data source. Its values should become documented role defaults and environment-specific variables.
- `cookbooks/nginx-multisite/templates/` and `files/`: Nginx, security, fail2ban, sysctl, and site templates plus static `index.html` content. These are migration inputs for Jinja2 templates, managed static files, and handlers.

### Target Details

- **Operating System:** The declared cookbook support is Ubuntu >= 18.04 and CentOS >= 7, but the actual Vagrant box is `generic/fedora42`. The provisioning script uses `apt-get`, while recipes use package/service names such as `ufw`, `www-data`, `postgresql`, and `ssh`; therefore the current repository has an unresolved platform mismatch. Treat Fedora 42 as the explicit test target only after implementing Fedora equivalents (for example, `dnf`, firewalld or a deliberate UFW package strategy, `nginx`, PostgreSQL, `sshd`, and Fedora users/groups), or change the box to a supported Ubuntu image. Do not silently assume Ubuntu.
- **Virtual Machine Technology:** Vagrant with the libvirt provider; 2 CPUs and 2048 MB memory. The private network and forwarded ports are explicitly defined.
- **Cloud Platform:** Not specified. No AWS, Azure, or GCP integration is present.

## Migration Approach

Create an Ansible project with a site playbook and separate roles such as `nginx_multisite`, `cache`, `fastapi_tutorial`, and possibly a shared `host_security` role. Use inventory/group variables for the three sites and platform-specific values. Use handlers for nginx, fail2ban, SSH, sysctl, Redis, and systemd reloads. Run Molecule or equivalent VM tests against the selected OS before cutover, then compare rendered configuration, open ports, service status, TLS behavior, application health, and database connectivity with the Chef-managed VM.

### Key Dependencies to Address

- **Chef 16+, Chef Solo, Berkshelf, Policyfile:** Remove the Chef runtime and replace the run list with an Ansible site playbook. Keep the locked versions as a behavior/reference baseline, not as Ansible runtime dependencies.
- **nginx 12.3.1 cookbook:** Replace with Ansible `ansible.builtin.package`, service, template, file, and handler tasks, or a vetted Ansible nginx role. Preserve the site loop, enabled-site links, default-site removal, and reload semantics.
- **memcached 6.1.0:** Replace with native package/service tasks or a vetted collection role. Confirm the required bind address, memory, and firewall exposure because the reviewed local recipe delegates defaults to the external cookbook.
- **redisio 7.2.4 and selinux 6.2.4:** Replace with an OS-appropriate Redis role/tasks, explicit configuration, service enablement, and SELinux policy/labels. Reimplement the intended compatibility settings declaratively rather than using a Ruby text rewrite.
- **ssl_certificate 2.1.0:** It is locked but not explicitly enabled in `Berksfile`; the local SSL recipe actually generates self-signed certificates with OpenSSL. For production, replace development certificates with an approved PKI, ACME workflow, or Ansible Vault-protected certificate deployment.
- **PostgreSQL and Python runtime:** Use distribution packages or a tested PostgreSQL role, `ansible.builtin.git`, `ansible.builtin.pip`/virtualenv handling, and a systemd template. Pin the application revision and Python dependencies to make deployments reproducible.
- **External GitHub application:** The `main` branch is mutable. Select a commit/tag and verify the repository's requirements and runtime before migration.

### Security Considerations

- **Hardcoded Redis credential:** `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and template Redis configuration with restrictive permissions.
- **Hardcoded PostgreSQL credentials:** `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes it into `.env` and `DATABASE_URL` with mode `0644`. Rotate the credential, store it in Vault, set restrictive file permissions, and use idempotent PostgreSQL modules rather than shell commands with `|| true`.
- **TLS certificates and private keys:** The SSL recipe creates self-signed 2048-bit RSA certificates for 365 days under `/etc/ssl/certs` and keys under `/etc/ssl/private`. This is acceptable only for development; production needs trusted certificates, renewal, SAN validation, key backup/rotation, and no private keys in Git. Preserve root ownership and least-privilege group access.
- **Firewall exposure:** UFW is set to default deny and allows SSH, HTTP, and HTTPS. Reproduce this policy using the selected OS firewall tooling, define an SSH source allowlist where possible, and validate that Ansible does not lock out the operator during SSH hardening.
- **SSH hardening:** Root login and password authentication are disabled conditionally. Use `ansible.builtin.lineinfile` or a managed `sshd_config.d` drop-in with syntax validation and a safe connection strategy; test key-based access before restarting sshd.
- **Fail2ban and sysctl:** Migrate the jail and kernel settings with explicit templates, validation, and handlers. Confirm that the rules match the target OS logs and that sysctl values are appropriate rather than blindly copying development settings.
- **Application privilege:** The FastAPI systemd service currently runs as `root` and listens on `0.0.0.0:8000`. Create a dedicated unprivileged service account, bind internally or restrict the port with firewall policy, and place nginx in front if external access is required.
- **Secret patterns by module:** `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials and a plaintext `.env`; `nginx-multisite` has private-key material generated on host and certificate references. No Chef encrypted data bags or Chef Vault usage were found in the reviewed files.
- **Supply chain:** The provisioning script downloads and executes the Chef Omnitruck installer, Berkshelf dependencies, a mutable GitHub branch, and pip requirements. Replace with pinned, verified packages and CI checks where practical.

### Technical Challenges

- **OS inconsistency:** Fedora 42 is provisioned with Debian/Ubuntu commands and cookbook assumptions. Decide the supported target first, then add OS-family variables and tests; this is the main migration blocker.
- **Chef resource semantics:** `include_recipe`, delayed notifications, cookbook files, symlinks, and Ruby blocks need explicit Ansible task ordering and handlers. Build idempotence tests for repeated runs.
- **Nginx site model:** The site configuration is data-driven and combines static content, templates, SSL flags, and symlinks. Preserve the three current sites in inventory variables and verify generated server names, roots, certificate paths, and reload behavior.
- **Certificate lifecycle:** Self-signed generation is guarded only by file existence and does not provide renewal or trust distribution. Define separate development and production certificate strategies before cutover.
- **Redis workaround:** Directly deleting directives from generated Redis configuration is fragile and may reflect a version-specific issue. Identify why those settings are removed, test the selected Redis version, and manage the complete configuration instead.
- **Database idempotency and application readiness:** Shell-based SQL with `|| true` hides failures and does not safely distinguish an existing user/database from a failed operation. Use PostgreSQL Ansible modules, explicit privileges, migrations if required, and health checks before starting FastAPI.
- **Dependency drift:** The lock file is not clean (`working_tree_clean: false` for local cookbooks), and the application tracks `main`. Record the exact source revisions and expected package versions as part of the migration baseline.
- **Validation of network behavior:** The documented host access includes both forwarded ports and hostnames that require `/etc/hosts` entries, while the Vagrant hosts block is commented out. Make DNS/hosts prerequisites explicit in tests.

### Migration Order

1. **Platform and test harness:** Decide Fedora versus Ubuntu, update Vagrant to run Ansible, establish inventory, connectivity, linting, idempotence, and rollback checks.
2. **Base security and OS services:** Implement package repositories, users/groups, SSH hardening, sysctl, firewall, and fail2ban with safe handlers. Validate access before proceeding.
3. **Cache services:** Migrate Memcached and Redis, immediately removing hardcoded credentials and validating Redis configuration and service behavior.
4. **FastAPI and PostgreSQL:** Pin the application revision, provision PostgreSQL and credentials securely, create the virtualenv, install dependencies, deploy the systemd unit under a non-root user, and add health checks.
5. **Nginx multisite and TLS:** Deploy nginx templates, static content, site links, certificates, and reverse/static hosting after backend and security prerequisites are known. Validate all three names and HTTP/HTTPS behavior.
6. **Integrated cutover and decommissioning:** Run Chef and Ansible comparison tests in an isolated environment, perform a controlled cutover, document operations, and remove Chef/Berkshelf provisioning only after rollback criteria are met.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local modules; no additional recipes or environments are required outside the supplied tree.
- `solo.json` is the effective source of site and security attributes; there are no external Chef server roles, environments, data bags, or encrypted data bags in scope.
- The locked external cookbook versions describe the intended baseline, although their implementation details were not opened and must be behavior-tested during migration.
- The Vagrant Fedora 42 box is either the intended deployment OS or a development mistake; the project owner must resolve this ambiguity before implementation is considered complete.
- The current self-signed certificates are for development only. Production certificate ownership, CA, renewal, and secret distribution are not specified.
- The FastAPI GitHub repository, its `requirements.txt`, database schema, and application health endpoint were not reviewed; application-specific deployment requirements may add effort.
- PostgreSQL is intended to run locally on the same host as FastAPI, based on the localhost connection string and service ordering.
- Redis and Memcached are intended as local services; their bind addresses and application consumers are not specified in the reviewed files.
- The required DNS or `/etc/hosts` records for the three cluster names are not managed by the current Vagrant configuration.
- No cloud platform, production inventory, HA topology, backup policy, monitoring, logging aggregation, or disaster recovery requirements are defined.
- The target Ansible control-node version, collection policy, CI system, secret manager, and deployment ownership remain to be selected.
- Existing data and certificates must be backed up or reissued before any production cutover; the repository does not define migration of persistent Redis/PostgreSQL data.
- Timeline estimate assumes one small team, a single environment, and no major changes to application behavior; production PKI, multi-host deployment, or data migration would increase the estimate.
