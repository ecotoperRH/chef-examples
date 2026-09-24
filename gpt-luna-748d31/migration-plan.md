# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/PPolicyfile deployment for a Fedora 42 Vagrant/libvirt test VM, with three local cookbooks and four external cookbook dependencies. The migration is moderate in application impact but low in repository size: the core work is translating package/service/file orchestration, preserving nginx virtual-host behavior, and removing plaintext credentials and development-only certificate behavior. A focused team should allow approximately 2–4 weeks for implementation, testing, security review, and cutover; a production-ready migration with external-environment validation may require 4–6 weeks.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
    - Description: Installs and enables Memcached and Redis caching services, including a single Redis server on port 6379 and a post-configuration workaround for replication-related Redis directives.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached dependency, Redisio dependency, Redis authentication, Redis log directory, service enablement, configuration cleanup via Ruby block

- **fastapi-tutorial**:
    - Description: Provisions a FastAPI tutorial application from a GitHub repository, creates a Python virtual environment, installs Python dependencies, configures PostgreSQL, and runs the application with systemd and Uvicorn.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Python 3 and virtualenv, Git checkout of `dibanez/fastapi_tutorial` at `main`, PostgreSQL database/user creation, generated `.env`, root-owned systemd service listening on `0.0.0.0:8000`

- **nginx-multisite**:
    - Description: Configures nginx as a multi-site web server for three SSL-enabled cluster-local sites, deploys static test content, applies host security controls, and generates development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: nginx installation and service management, three sites (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), nginx templates and symlinked site definitions, fail2ban, UFW, SSH hardening, sysctl settings, self-signed RSA certificates

**CRITICAL PATH VERIFICATION:**

The three cookbook paths above are present in the supplied repository tree. Their primary entrypoints and relevant central recipes were reviewed. External cookbooks are dependencies, not local modules, and are therefore not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, three local cookbooks, and external cookbook constraints for nginx, Memcached, Redisio, and a commented-out ssl_certificate cookbook. It is a source dependency document only during migration; replace its role with Ansible Galaxy requirements or OS/application-specific role documentation.
- `Policyfile.rb`: Defines the policy name, run list, local cookbook paths, and dependency constraints. It is the authoritative declared Chef execution composition and should map to an Ansible site playbook and role dependency graph.
- `Policyfile.lock.json`: Captures resolved versions: nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, selinux 6.2.4, and ssl_certificate 2.1.0, alongside local cookbook revisions. Use it as a migration baseline, but do not assume equivalent behavior from modern Ansible roles.
- `Vagrantfile`: Defines a Fedora 42 box, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and HTTP/HTTPS port forwarding. It should be adapted to run `ansible-playbook` with an inventory rather than Chef provisioning.
- `vagrant-provision.sh`: Installs Chef, Berkshelf, and dependencies and runs Chef Solo. Replace it with Ansible installation/invocation or a host/bootstrap script that installs only required Ansible prerequisites.
- `solo.rb`: Defines the Chef Solo cache, cookbook paths, and logging. It has no direct Ansible equivalent beyond inventory, project layout, and logging configuration.
- `solo.json`: Provides the active run list, three nginx sites, SSL paths, and security settings. Convert these values into typed Ansible group/host variables, with secrets removed from source control.
- `project-plan.md`: Describes the X2Ansible analysis/migration workflow and expected generated artifacts. Keep it as process context, but update references from Chef migration outputs to the actual Ansible roles and validation reports.
- `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`: Repository-specific migration-tool specification/rules. Review it before implementation to align generated role naming, validation, and coordination practices.

### Target Details

- **Operating System:** The Vagrant box is explicitly Fedora 42, but the provisioning script runs `apt-get`, and cookbook metadata claims Ubuntu >=18.04 and CentOS >=7. The target OS is therefore unresolved. Establish a supported target before implementation; if no production target is supplied, use RHEL 9-compatible conventions as the default planning baseline and test Fedora separately. Package names, firewall tooling, SSH service names, nginx paths, and PostgreSQL service names must be validated per OS.
- **Virtual Machine Technology:** libvirt via Vagrant, with rsync synchronization. The development VM has 2 CPUs and 2048 MB RAM.
- **Cloud Platform:** Not specified. No AWS, Azure, or GCP integration is present.

## Migration Approach

Create an Ansible project with a site playbook and separate roles such as `security`, `cache`, `fastapi_tutorial`, and `nginx_multisite`. Use inventories for the Vagrant test host and future environments, role defaults for safe non-secret configuration, group variables for site definitions, handlers for service reloads, and Molecule or equivalent disposable-VM tests. Preserve the Chef run-list ordering initially, then make explicit dependencies and readiness checks.

### Key Dependencies to Address

- **nginx cookbook 12.3.1:** Replace with native Ansible package/service/template tasks or a vetted Ansible Galaxy nginx role. Recreate the custom `nginx.conf`, security include, site files, enabled-site links, and reload handlers rather than assuming cookbook defaults.
- **memcached cookbook 6.1.0:** Replace with OS package installation, configuration, and service tasks, or a vetted role. Confirm bind address, persistence expectations, and firewall exposure because the reviewed local recipe only includes the cookbook.
- **redisio cookbook 7.2.4:** Replace with a vetted Redis role or explicit package/configuration tasks. Preserve port 6379, authentication, log directory, enablement, and the intended removal of replication directives, but first determine whether the Ruby workaround is still needed for the target Redis version.
- **selinux cookbook 6.2.4:** It is pulled transitively by Redisio in the lockfile, but no local SELinux policy intent was reviewed. Determine whether SELinux should remain enforcing and translate required booleans, contexts, and ports with Ansible SELinux modules rather than disabling it.
- **ssl_certificate cookbook 2.1.0:** It is locked by the Policyfile even though its Berksfile declaration is commented out and no local recipe explicitly uses it. Confirm whether it was incidental or expected. For production, use an ACME/certificate-management solution and Ansible Vault-backed private keys; retain self-signed generation only for isolated development.
- **PostgreSQL and Python runtime:** The FastAPI cookbook installs distribution PostgreSQL and Python packages directly and pulls application dependencies from an unpinned Git branch and `requirements.txt`. Use Ansible package/service tasks, a controlled application artifact or pinned Git commit, and a repeatable Python dependency process.
- **GitHub application source:** Replace the Chef `git` resource with `ansible.builtin.git`, but define commit/tag policy, network access, update behavior, and rollback handling.

### Security Considerations

- **Plaintext Redis credential:** `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, template it into Redis configuration with restrictive permissions, and rotate it during migration.
- **Plaintext PostgreSQL credentials:** `fastapi-tutorial` embeds `fastapi_password` in SQL commands and in `/opt/fastapi-tutorial/.env`, which is created mode 0644 and root-owned. Replace with Vault-managed credentials, use idempotent PostgreSQL modules, restrict `.env` to the service account, and avoid passwords in command-line arguments where possible.
- **TLS certificates and private keys:** nginx references `/etc/ssl/certs` and `/etc/ssl/private`; the cookbook generates self-signed 2048-bit RSA certificates for 365 days. Protect private keys, define ownership/modes explicitly, and decide between managed certificates and development certificates. Validate renewal and hostname coverage for all three sites.
- **Firewall and network exposure:** UFW defaults to deny and permits SSH, HTTP, and HTTPS. The FastAPI service listens on all interfaces at port 8000, but the reviewed security recipe does not allow or deny that port explicitly. Decide whether Uvicorn should be localhost-only behind nginx or whether port 8000 needs a controlled rule.
- **SSH hardening:** Root login is disabled and password authentication is disabled through `sed` edits. Reimplement with Ansible SSH configuration management, validate an alternate administrative key/user before applying, and use a handler to restart/reload safely to avoid lockout.
- **fail2ban and sysctl:** Preserve the fail2ban jail and sysctl template semantics, review them for Fedora/RHEL versus Debian differences, and test that service restart/reload handlers work.
- **Application privilege:** The systemd service runs FastAPI as `root`; create a dedicated non-root user, set ownership and permissions, and use systemd hardening options where compatible.
- **Repository and dependency trust:** The application is fetched from a public GitHub `main` branch and pip dependencies are not visibly pinned in this repository. Pin immutable revisions and verify package/source integrity in CI.
- **Secret inventory uncertainty:** No Chef encrypted data bags or Chef Vault references were found in the reviewed files. The visible credentials are hardcoded values, not encrypted secrets. Inspect deployment systems and omitted application files before production cutover.

### Technical Challenges

- **OS inconsistency:** Fedora 42 is the explicit VM image, while `apt-get` is used for bootstrap and cookbook metadata supports Ubuntu/CentOS. Resolve the platform matrix first; implement distribution-aware variables for package names, firewall, service names, and nginx layout.
- **Chef attribute precedence and path drift:** `solo.json` uses document roots under `/var/www`, while cookbook defaults use `/opt/server`; the active JSON likely overrides the defaults. Model the final desired values explicitly in Ansible and test rendered nginx configs and content locations.
- **Idempotency gaps in source:** Redis configuration is modified using a Ruby text rewrite, PostgreSQL creation is an `execute` block with `|| true`, and pip installation runs as an imperative command. Replace these with Ansible modules and explicit changed/failed conditions.
- **Template semantics not fully visible in this survey:** nginx, fail2ban, sysctl, and site template contents must be ported and behaviorally tested during implementation. Treat them as configuration contracts, not simple filename conversions.
- **Certificate lifecycle:** The current certificate task only checks file existence and does not renew certificates. Define development versus production certificate ownership, renewal, and deployment procedures.
- **Service ordering:** FastAPI depends on PostgreSQL, and nginx depends operationally on site files/certificates. Use handlers, `notify`, health checks, and explicit systemd dependencies to avoid startup races.
- **External cookbook behavior:** Locked cookbook versions encode implementation details that are not visible in local files. Compare the deployed Chef behavior before replacing them with Ansible roles, especially Redis defaults, nginx defaults, and SELinux behavior.
- **Testing and cutover:** Vagrant forwards ports 8080/8443 but the shell output also references an inconsistent private address (`192.168.56.10` versus Vagrant's `192.168.121.10`). Correct the test documentation and validate DNS/hosts resolution for all three names.

### Migration Order

1. **Baseline and platform decision:** Freeze the Chef lockfile, document the actual target OS, correct Vagrant/test addressing, and establish an Ansible inventory and CI lint/test pipeline.
2. **Security foundation:** Implement SSH hardening, firewall policy, fail2ban, sysctl settings, certificate/key permissions, and an administrative access recovery test.
3. **Cache services:** Migrate Memcached and Redis, handling the Redis secret through Vault and verifying service health and persistence expectations.
4. **FastAPI and PostgreSQL:** Create the dedicated application user, PostgreSQL database/role, pinned application deployment, secure environment configuration, and systemd service; test database connectivity and restart behavior.
5. **nginx multisite:** Migrate nginx package/configuration, static content, virtual hosts, TLS, and proxy/front-end behavior after the application and certificate strategy are settled.
6. **Integration and cutover:** Run parallel validation against Chef and Ansible on disposable VMs, compare packages/services/files/listening ports, perform security review, then schedule staged environment promotion and Chef decommissioning.

Estimated implementation effort is roughly 3–5 engineering days for the cache role, 4–7 days for FastAPI/PostgreSQL, 4–7 days for nginx/TLS, 3–5 days for security and platform abstraction, and 5–10 days for integration, testing, documentation, and review. These estimates exclude remediation discovered in the external application repository or production infrastructure.

### Assumptions

- The intended deployment scope is the three local cookbooks in the Policyfile run list; external cookbooks are dependencies to replace, not additional local modules to migrate.
- Fedora 42 is a development target, not necessarily the production operating system.
- The three `cluster.local` names are test/development names unless a real DNS and certificate plan is supplied.
- The `solo.json` values represent the intended active configuration, including `/var/www` document roots and enabled security controls.
- The nginx and security template contents are authoritative but were not exhaustively audited in this high-level plan.
- The FastAPI GitHub repository and its `requirements.txt` remain available; its application internals, migrations, and runtime requirements require a separate review.
- PostgreSQL is intended to run locally on the same host as FastAPI, as shown by the localhost connection string.
- Redis authentication is required, but the existing password is a placeholder or development secret and must not be reused.
- Self-signed certificates are acceptable only for development; production certificate requirements are not specified.
- No cloud provider, external inventory, load balancer, DNS automation, monitoring, backup, or disaster-recovery configuration is present in the supplied tree.
- No encrypted Chef data bags, Chef Vault configuration, or external secret-manager integration was found in the reviewed files; hidden deployment configuration may change this conclusion.
- The locked `ssl_certificate` dependency may be unused; its intended role must be confirmed before removing it.
- The custom `resources/lineinfile.rb` was reviewed as a local resource but no reviewed central recipe invokes it; determine whether other cookbook files or operational usage depend on it before omitting it.
- The migration will preserve functional intent rather than reproduce Chef implementation details, including replacing imperative shell/Ruby operations with idempotent Ansible modules.
- Teams will jointly approve the OS matrix, secret handling, certificate lifecycle, application release strategy, and production cutover criteria before implementation is considered complete.
