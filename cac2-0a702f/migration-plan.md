# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile environment containing three local cookbooks and four external cookbook dependencies. The effective deployment combines an Nginx multi-site reverse/static-web configuration, Redis and memcached, and a FastAPI tutorial application backed by PostgreSQL. The migration is moderate in implementation risk despite the small module count because it contains hardcoded credentials, generated TLS keys, imperative configuration edits, application bootstrapping from a moving Git branch, and a mismatch between the declared Fedora Vagrant image and the Debian/Ubuntu-oriented provisioning commands.

A focused team could produce an initial Ansible implementation in approximately 2–3 weeks, including validation on a replacement VM; production hardening, secret integration, certificate ownership decisions, and application deployment testing should be planned for an additional 1–2 weeks. The estimate assumes one target host role and no requirement to preserve Chef during a long dual-run period.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Installs and configures Nginx for three configured SSL-enabled sites, creates their document roots and static landing pages, removes the default site, and applies host security controls.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management; templated `nginx.conf`, security and virtual-host configuration; `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; self-signed RSA certificates; Fail2ban; UFW default-deny rules; SSH hardening; sysctl settings.
    - Ansible shape: A role with `apt`/`package`, `template`, `copy`, `file`, `service`, `community.general.ufw`, `ansible.posix.sysctl`, and certificate-management tasks. Site definitions should become structured role variables rather than Chef node attributes.

- **cache**:
    - Description: Installs memcached and Redis, configures a Redis listener on port 6379 with password authentication, creates the Redis log directory, and enables Redis.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: `memcached` cookbook inclusion; `redisio` cookbook inclusion; Redis password; a post-generation configuration rewrite removing replication-related directives.
    - Ansible shape: A role using distribution packages or explicitly selected Redis/memcached roles, with a managed Redis configuration template and a handler-driven restart. The current Ruby post-processing hack should be replaced rather than translated literally.

- **fastapi-tutorial**:
    - Description: Installs Python and PostgreSQL prerequisites, clones the FastAPI tutorial application, creates a virtual environment, installs its requirements, creates a PostgreSQL database/user, writes application environment settings, and runs Uvicorn through systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git checkout from `https://github.com/dibanez/fastapi_tutorial.git` at `main`; Python virtualenv; PostgreSQL service and database; systemd unit on port 8000; application runs as root; database URL in a world-readable `.env` file.
    - Ansible shape: An application role with package, git, `ansible.builtin.pip`, PostgreSQL modules, a systemd template, and secret-backed environment configuration. Pin the application revision and dependency versions before cutover.

**CRITICAL PATH VERIFICATION:**

Only the three local cookbook paths above were identified in the supplied repository tree and confirmed by their `metadata.rb` and `recipes/default.rb` files. `nginx`, `memcached`, `redisio`, `selinux`, and `ssl_certificate` are external Chef dependencies, not local modules, and are therefore not listed as modules in this inventory.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, three local cookbooks, and external cookbook constraints for Nginx, memcached, Redis, and the commented SSL certificate cookbook. Replace dependency resolution with Ansible collections/roles and pinned Galaxy or internal artifacts.
- `Policyfile.rb`: Defines the active policy run list and dependency constraints, including `ssl_certificate` even though it is commented out in the Berksfile. This is the authoritative Chef composition to compare against the Ansible playbook.
- `Policyfile.lock.json`: Locks local cookbook revisions and external versions: Nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, selinux 6.2.4, and ssl_certificate 2.1.0. Preserve this as migration evidence and create equivalent Ansible collection/package pins.
- `Vagrantfile`: Builds `generic/fedora42` under libvirt with 2 GiB RAM, 2 CPUs, private IP `192.168.121.10`, and ports 8080/8443 forwarded to guest ports 80/443. It syncs the repository and invokes the shell provisioner. Convert the test harness to an Ansible provisioner or a separate Ansible Molecule/libvirt scenario.
- `vagrant-provision.sh`: Installs Chef from an internet bootstrap script, installs Berkshelf, vendors dependencies, and runs Chef Solo. It also calls `apt-get`, which conflicts with the Fedora Vagrant box and must not be carried into the Ansible bootstrap unchanged.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Replace with Ansible inventory, `ansible.cfg`, role paths, and group variables.
- `solo.json`: Supplies the three sites, SSL paths, security switches, and the Chef run list. Its values should become version-controlled non-secret Ansible defaults; credentials must be removed and supplied through Vault.
- `project-plan.md`: Existing project context should be reviewed by the migration team, but it was not used as a source module entrypoint.

### Target Details

- **Operating System:** The cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The intended commands and paths are primarily Debian/Ubuntu-oriented (`apt-get`, `ufw`, `www-data`, `libpq-dev`, and the `ssh` service), while `Vagrantfile` selects Fedora 42. Resolve this contradiction before implementation. A supported target should be explicitly selected; if no decision is available, use Red Hat Enterprise Linux 9 as the default planning target and adapt firewall, package, service, web-user, and PostgreSQL details accordingly.
- **Virtual Machine Technology:** libvirt via Vagrant is explicitly configured. The VM has 2 CPUs and 2048 MB RAM and uses a private network plus forwarded HTTP/HTTPS ports.
- **Cloud Platform:** Not specified. No AWS, Azure, or GCP integration is present.

## Migration Approach

### Key Dependencies to Address

- **Chef Supermarket cookbooks:** Replace `nginx` 12.3.1 with an Ansible Nginx role or an internally maintained role; implement only the required configuration rather than reproducing cookbook internals.
- **memcached 6.1.0:** Use the target OS package and an Ansible service/configuration task, or a pinned community role. Confirm whether memcached needs a bind address, authentication, or firewall exposure.
- **redisio 7.2.4 and selinux 6.2.4:** Replace with OS Redis packages/configuration and explicit SELinux tasks or policies. Validate the current Redis configuration against the target Redis version; do not rely on the Chef post-processing workaround.
- **ssl_certificate 2.1.0:** The lock contains it, but the local SSL recipe generates self-signed certificates directly and the Berksfile comments the dependency. Decide whether development self-signed certificates remain acceptable or whether Ansible should deploy ACME/enterprise certificates from a secure store.
- **Python 3, pip, venv, Git, PostgreSQL and libpq:** Use target-OS package modules and `ansible.builtin.pip`. Pin the Git revision and preferably a requirements lock file; `main` is mutable and the remote repository is an external availability and supply-chain dependency.
- **systemd, UFW, Fail2ban, OpenSSL and sysctl:** Map these to target-compatible Ansible modules and handlers. On RHEL-like systems, use `firewalld` rather than UFW unless UFW is deliberately installed and supported.
- **Application database provisioning:** Replace shell `psql` commands with `community.postgresql.postgresql_user` and `postgresql_db`, with idempotent password handling and explicit privilege requirements.

### Security Considerations

- **Hardcoded Redis credential:** `redis_secure_password_123` is embedded in `cookbooks/cache/recipes/default.rb`. Rotate it, store it in Ansible Vault or an enterprise secret manager, and render Redis configuration with restrictive permissions.
- **Hardcoded PostgreSQL credentials:** The FastAPI recipe creates user `fastapi` with password `fastapi_password` and writes the same value into `/opt/fastapi-tutorial/.env`. Treat it as compromised, rotate it, use Vault, and set the environment file to a least-privilege mode such as 0600 owned by the service account.
- **TLS private keys and certificates:** The Nginx recipe creates private keys under `/etc/ssl/private` with `root:ssl-cert` and mode 0640, but generates self-signed certificates valid for 365 days. Preserve key access controls, decide on certificate lifecycle/renewal, and avoid generating production keys on every host without approved entropy, naming, and backup procedures.
- **Nginx and firewall exposure:** The configuration exposes HTTP/HTTPS and enables default-deny UFW while allowing SSH, HTTP, and HTTPS. Confirm the intended management source ranges, IPv6 behavior, application port 8000 exposure, and whether Redis/memcached remain localhost-only.
- **SSH hardening:** Root login and password authentication are disabled based on node attributes. Validate that key-based access, emergency access, and the actual SSH service name are available before applying the change; use a managed `sshd_config` fragment rather than `sed` edits.
- **Application privilege:** The systemd unit runs the FastAPI process as `root`. Create a dedicated non-root account, restrict filesystem ownership, and explicitly define writable directories.
- **Supply chain and bootstrap:** The provisioner downloads Chef and dependencies over the network and clones an unpinned public repository. Pin package/repository sources, validate checksums or signatures where possible, and use controlled CI artifacts.
- **Secrets management:** No Chef encrypted data bags or Chef Vault references were visible in the reviewed files. Credentials are plainly embedded in recipes and generated environment/configuration content. Ansible Vault or an external secret manager must be a migration prerequisite, not a later cleanup.

### Technical Challenges

- **OS mismatch:** Fedora 42 is selected by Vagrant, but provisioning starts with `apt-get` and the cookbook supports Ubuntu/CentOS rather than explicitly Fedora. Establish the supported OS first, then test package names, users, firewall tooling, SELinux behavior, PostgreSQL service names, and Nginx layout.
- **Chef attribute behavior:** The Nginx site map and security switches come from `solo.json` node attributes. Build a clear Ansible variable contract, including validation for site names, document roots, certificate paths, and `ssl_enabled`.
- **Imperative Redis workaround:** The recipe removes several generated directives with a Ruby block. Identify the underlying Redis/redisio compatibility problem and manage a complete validated configuration template instead of using fragile text mutation.
- **Non-idempotent database shell commands:** `|| true` hides failures and can leave partially configured accounts/databases. Replace with PostgreSQL modules and migration tests for repeat runs.
- **Service ordering and reloads:** Nginx, Fail2ban, PostgreSQL, Redis, and the FastAPI unit depend on configuration ordering. Use handlers, explicit `daemon-reload`, service dependencies, and health checks.
- **Static content and virtual hosts:** The cookbook maps a site name to a file path based on the first DNS label and uses cookbook files. Preserve the three supplied files, test the enabled-site symlinks, and verify hostname resolution in the Vagrant test environment.
- **Certificate trust and hostname testing:** Self-signed certificates will produce client warnings and require correct SANs for modern clients. Decide whether development-only certificates are sufficient and test with the actual hostnames, not only forwarded localhost ports.

### Migration Order

1. **Foundation and target platform:** Decide Ubuntu versus RHEL/Fedora, reproduce the Vagrant/libvirt test VM, create Ansible inventory, establish linting/idempotence checks, and introduce Vault/secret inputs.
2. **nginx-multisite:** Migrate Nginx, static content, virtual hosts, firewall, SSH hardening, Fail2ban, and sysctl. This establishes the primary ingress and security baseline.
3. **cache:** Migrate memcached and Redis with corrected configuration, secret handling, service health checks, and any SELinux/firewall requirements.
4. **fastapi-tutorial:** Migrate PostgreSQL and application deployment after the host baseline is stable; use a dedicated service account, pinned application revision, secure database credentials, and a systemd health check.
5. **Validation and cutover:** Run twice for idempotence, compare ports/configuration/site responses, test reboot persistence and certificate behavior, then retire Chef bootstrap and document operations ownership.

### Assumptions

- The three local cookbooks in the Policyfile run list represent the complete intended deployment scope.
- `Policyfile.lock.json` is the best record of resolved external dependency versions; the Berksfile and Policyfile are not fully consistent because SSL is commented in one and active in the other.
- The Vagrant VM is a development/test target, not proof of a production OS standard.
- The public FastAPI repository and its `main` branch are intentional dependencies; production migration will require a pinned revision and artifact strategy.
- The three DNS names are expected to resolve to the VM or load balancer; the commented `/etc/hosts` entries show that local name resolution may otherwise be missing.
- Self-signed certificates are currently development behavior. Production certificate authority, renewal, SAN, and secret distribution requirements are unspecified.
- Redis authentication is required, but the intended client set, bind address, TLS requirement, and rotation process are unspecified.
- Memcached security and network binding requirements are unspecified.
- PostgreSQL version, authentication method, backup/restore policy, schema migration process, and data persistence requirements are unspecified.
- No persistent storage, monitoring, log shipping, alerting, rollback, or disaster recovery configuration is present in the reviewed source.
- The target Ansible control node, inventory source, CI system, secret manager, and deployment ownership are unspecified.
- The migration team should agree on role boundaries, variable ownership, change review, and an acceptance checklist covering all three sites, Redis, PostgreSQL, FastAPI, firewall, SSH, and repeatability.
