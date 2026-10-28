# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment with three local cookbooks and four resolved external cookbooks. The target state should be an Ansible project that provisions a Linux VM with Nginx multi-site HTTPS, host security controls, Redis/Memcached, and a FastAPI tutorial application backed by PostgreSQL. The implementation size is modest, but the migration is security-sensitive because credentials are embedded in recipes, TLS keys are generated locally, and the current provisioning scripts contain an operating-system mismatch. A focused migration is estimated at **2–4 engineering weeks**, including role development, Fedora/Ubuntu compatibility decisions, testing, and security remediation; production hardening and certificate integration may extend this to **4–6 weeks**.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web-server cookbook that configures three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), publishes static index pages, applies host and Nginx security settings, and generates development self-signed certificates.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Nginx installation and service management; per-site document roots and enabled-site symlinks; Nginx and security templates; Fail2ban; UFW default-deny firewall rules; SSH root/password-login restrictions; sysctl hardening; OpenSSL-generated certificates.

- **cache**:
    - Description: Cache-service cookbook that installs and enables Memcached and Redis, configures a Redis instance on port 6379, creates its log directory, and applies a post-generation configuration workaround for replication-related Redis settings.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Inclusion of the external `memcached` and `redisio` recipes; Redis password configuration; Redis log-directory ownership; custom `ruby_block` editing of `/etc/redis/6379.conf`; Redis service enablement.

- **fastapi-tutorial**:
    - Description: Application cookbook that installs Python and PostgreSQL prerequisites, clones `https://github.com/dibanez/fastapi_tutorial.git`, creates a Python virtual environment, installs application requirements, initializes a PostgreSQL database/user, writes an application `.env`, and runs Uvicorn under systemd.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Python 3/pip/venv setup; Git-based application deployment from the `main` branch; PostgreSQL service; `fastapi` database and user; systemd unit listening on `0.0.0.0:8000`; automatic service restart.

**CRITICAL PATH VERIFICATION:**
The three module paths above are present in the supplied repository tree and were confirmed by reading each cookbook's `metadata.rb` and primary `recipes/default.rb`. External cookbooks are dependencies, not local modules, and are therefore not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef dependency source and constraints. It references the three local cookbooks plus `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; the `ssl_certificate` declaration is commented out here.
- `Policyfile.rb`: Chef policy name, run list, local cookbook paths, and external dependency declarations. It includes `ssl_certificate ~> 2.1` even though the Berksfile line is commented.
- `Policyfile.lock.json`: Resolved dependency baseline. It records local cookbook version `1.0.0`, `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, and `ssl_certificate 2.1.0`. The lock also shows `cache` depending on Memcached/Redis and Redis depending on SELinux.
- `Vagrantfile`: Local test harness using the `generic/fedora42` box, libvirt, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, forwarded ports 8080/8443, and an rsync-mounted repository at `/chef-repo`.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. It prints an outdated/different address (`192.168.56.10`) than the Vagrant private network configuration.
- `solo.rb`: Chef Solo cache, cookbook paths, and console logging configuration.
- `solo.json`: Alternate Chef Solo run list and runtime attributes for the three sites, SSL paths, Fail2ban/UFW, and SSH controls. Its document roots (`/var/www/...`) differ from the cookbook defaults (`/opt/server/...`) and should be reconciled during migration.
- `project-plan.md`: Repository/tool specification describing a staged analysis, migration, and validation workflow; it is useful as coordination context rather than deployable configuration.

### Target Details

- **Operating System:** The declared Vagrant box is Fedora 42, implying a Fedora/RHEL-family target for the current test environment. However, `vagrant-provision.sh` uses Debian/Ubuntu-only `apt-get`, and cookbook metadata supports Ubuntu >=18.04 and CentOS >=7. The target OS must be selected explicitly before implementation. If no production target is supplied, use Fedora/RHEL-family tasks as the primary path and document Ubuntu support separately; do not assume the current script works on Fedora.
- **Virtual Machine Technology:** libvirt through Vagrant, with a 2-vCPU/2-GB development VM. Production virtualization is not specified.
- **Cloud Platform:** Not specified. No AWS, Azure, or GCP-specific configuration is present.
- **Network/application endpoints:** Nginx is intended to serve ports 80/443; the FastAPI service listens on port 8000 locally to the VM interface (`0.0.0.0`). The Vagrant host forwards guest 80/443 to host 8080/8443. The expected hostnames are the three `*.cluster.local` names, but the commented `/etc/hosts` setup and current forwarded-address output need correction.

## Migration Approach

Create an Ansible project with a top-level site playbook and roles such as `nginx_multisite`, `cache`, `fastapi_tutorial`, and `security` (or keep security tasks within the Nginx role if ownership is preferred). Convert Chef node attributes and `solo.json` into group/host variables, with environment-specific values separated from role defaults. Use handlers for Nginx, Fail2ban, SSH, sysctl, Redis, and systemd reloads. Use Ansible collections/modules rather than shell commands wherever possible, and preserve idempotence with database modules, `ansible.builtin.systemd`, `ansible.posix.firewalld`/UFW-compatible strategy, and templated configuration.

First establish the supported OS and test matrix. Then implement security and foundational service roles, followed by the cache and application roles, and finally integrate Nginx virtual hosts and TLS. Keep the existing Vagrant/libvirt scenario as an acceptance environment only after its provisioning commands, IPs, and hostnames are corrected.

### Key Dependencies to Address

- **Nginx Chef cookbook 12.3.1 (`~> 12.0`)**: Replace with an Ansible Nginx role/tasks, package installation, service management, `nginx.conf`, security include, virtual-host templates, and validation with `nginx -t`. Do not replicate Chef cookbook behavior blindly; define the supported Nginx package/version per OS.
- **Memcached cookbook 6.1.0 (`~> 6.0`)**: Replace with package/service tasks and an explicit Memcached configuration. Confirm whether the application actually consumes Memcached; no consumer configuration is visible in the reviewed files.
- **RedisIO cookbook 7.2.4**: Replace with an Ansible Redis role or curated tasks. Model the port, password, log path, service, and configuration as variables. Reassess the Chef `ruby_block` workaround against the target Redis version rather than carrying forward direct text deletion.
- **SELinux cookbook 6.2.4**: Its presence is transitive through RedisIO. For Fedora/RHEL, use Ansible SELinux modules and package/context tasks; decide whether enforcing mode, ports, and file contexts are required. For Ubuntu, this dependency is not equivalent and should not be installed automatically.
- **`ssl_certificate` 2.1.0**: It is locked by the Policyfile but not used by the reviewed local recipes; the local cookbook generates certificates with OpenSSL instead. Decide whether to remove the unused dependency or replace development certificates with organization-managed certificates, Ansible Vault, or an external PKI/ACME process.
- **PostgreSQL packages and application Git repository**: These are direct dependencies of `fastapi-tutorial`, not captured in the Chef lock as a separate cookbook. Pin or otherwise govern the Git revision, Python dependency set, PostgreSQL major version, and required system packages in Ansible.
- **Vagrant/libvirt and base image**: Preserve as a development test harness only if Fedora support is selected. Replace `vagrant-provision.sh` with an Ansible provisioner or an explicit `ansible_local`/remote playbook invocation.

### Security Considerations

- **Hardcoded Redis credential:** `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move the password to Ansible Vault or an approved secret manager, avoid exposing it in task output, and rotate it before any shared or production deployment.
- **Hardcoded PostgreSQL credentials:** `fastapi-tutorial` embeds the database password `fastapi_password` in SQL commands and in `/opt/fastapi-tutorial/.env`, whose mode is `0644`. Use Vault/secret-manager data, create the database and role with PostgreSQL Ansible modules, set restrictive ownership/mode (for example, application user and `0600`), and rotate the credential.
- **TLS private keys and certificates:** The Nginx role creates per-site self-signed RSA certificates and stores keys under `/etc/ssl/private` with `0640` and group `ssl-cert`. This is appropriate only for development. Production migration should use managed certificate issuance/storage, preserve private-key permissions, avoid logging key material, and define renewal/reload behavior.
- **SSH hardening:** Root login and password authentication are disabled using `sed` against `sshd_config`. Replace with structured Ansible configuration, validate the effective SSH configuration before restarting, and ensure an administrative key-based access path exists to prevent lockout.
- **Firewall exposure:** UFW allows SSH, HTTP, and HTTPS after default deny. On Fedora, UFW may not be the native firewall; use firewalld or explicitly install/support UFW. Decide whether port 8000 should remain local-only; the application currently binds all interfaces even though Nginx is the apparent front end.
- **Fail2ban and sysctl:** Port the supplied templates and preserve notification/restart ordering, but review their assumptions for Fedora versus Ubuntu and verify that sysctl values are safe for the target kernel.
- **Application execution identity:** The systemd unit runs Uvicorn as `root` and clones the application into a root-owned directory. Create a dedicated non-root service account, define writable paths explicitly, and restrict environment-file access.
- **Supply-chain controls:** The application is cloned from a moving `main` branch and installs unpinned requirements. Pin a reviewed commit/tag and use a controlled Python dependency lock or artifact repository. Review external Ansible collections and role sources before adoption.

**Vault/secrets management by module:** `cache` contains a Redis password; `fastapi-tutorial` contains PostgreSQL username/password and a database URL; `nginx-multisite` contains no password but creates private TLS keys and self-signed certificates. No Chef encrypted data bags or Chef Vault references were observed in the reviewed files. Treat all currently embedded values as compromised until confirmed otherwise.

### Technical Challenges

- **OS mismatch and package/service naming:** Fedora 42 is the declared VM, while provisioning uses `apt-get`, Ubuntu-style `www-data`, UFW, and service assumptions. Resolve the target OS first, then use OS-family variables and handlers; test package names, PostgreSQL service names, firewall implementation, SELinux contexts, and web-user ownership.
- **Configuration precedence conflict:** Cookbook defaults use `/opt/server/test`, `/opt/server/ci`, and `/opt/server/status`, while `solo.json` overrides them to `/var/www/...`; the JSON run-list syntax also differs between Policyfile and Solo. Establish one authoritative Ansible variable model and document environment overrides.
- **Chef resource ordering and implicit behavior:** Recipe inclusion, notifications, cookbook file paths, and the Redis post-processing `ruby_block` encode ordering. Recreate this explicitly with task ordering, handlers, `notify`, service dependencies, and idempotent configuration rather than shell edits.
- **TLS lifecycle:** Existing certificates are generated once and never renewed or replaced. Define development versus production certificate behavior, SAN coverage for all hostnames, renewal, ownership, and Nginx reload testing.
- **Database initialization idempotence:** Chef uses `psql` commands with `|| true`, which can hide failures and does not safely manage password changes. Use PostgreSQL modules with explicit state and migration policy, and decide whether the application owns schema migrations.
- **Application service readiness:** The cookbook installs requirements on every converge command and uses a moving Git branch. Add deployment versioning, virtualenv ownership, health checks, systemd hardening, and controlled restart behavior.
- **Missing application/runtime context:** The repository does not show the FastAPI source, its complete requirements, expected schema migrations, or Nginx upstream/proxy behavior. Inspect the application repository and templates before finalizing the role contract.
- **Test harness inconsistencies:** Vagrant’s private IP is `192.168.121.10`, but the provisioning output refers to `192.168.56.10`; hostname entries are commented out. Correct these and add Molecule or equivalent converged-state tests for each role.

### Migration Order

1. **Foundation and decision record:** Confirm supported OS, inventory model, privilege/escalation policy, network/hostname requirements, PostgreSQL/Redis versions, and secret-management integration. Repair the Vagrant test path.
2. **Security baseline (`nginx-multisite` security behavior):** Implement SSH, firewall, sysctl, Fail2ban, SELinux/firewall variants, and access-safe validation. This establishes the platform without yet exposing application services.
3. **Cache services (`cache`):** Install/configure Redis and Memcached, move Redis credentials to Vault, replace the Redis workaround with supported configuration, and validate service health.
4. **Application platform (`fastapi-tutorial`):** Install Python/PostgreSQL, create a non-root service account, deploy a pinned application revision, manage database credentials securely, and create a hardened systemd unit.
5. **Nginx multisite and TLS (`nginx-multisite`):** Configure virtual hosts, static files, security headers/configuration, certificate integration, symlinks or equivalent site activation, and reload handlers. Integrate the FastAPI upstream only after the application contract is confirmed.
6. **End-to-end validation and cutover:** Compare package/service/file/firewall/TLS behavior with the Chef VM, run idempotence tests twice, test all three hostnames and forwarded ports, perform security review, then retire Chef provisioning or keep it only as a rollback reference.

A practical schedule is approximately 2–3 days for discovery/OS decisions, 3–5 days for foundation/security, 2–3 days for cache, 4–6 days for the application/database role, 3–5 days for Nginx/TLS, and 3–5 days for integration, remediation, documentation, and handover. Parallel work is possible after the OS and variable contract are agreed: one engineer can own security/platform, one cache/application, and one Nginx/testing workstream.

### Assumptions

- Chef is the source technology; no Puppet, Salt, or PowerShell modules are present in the supplied tree.
- The three local cookbook directories are the complete migration scope; external cookbooks are dependency behavior to replace, not separately owned local modules.
- The Fedora 42 Vagrant box is the intended development target, but production OS requirements are currently unknown.
- Ubuntu/CentOS support declarations in cookbook metadata are historical compatibility claims, not proof that all paths work on those systems.
- The three cluster-local hostnames and three sites are required, although the actual DNS or `/etc/hosts` ownership is unspecified.
- Self-signed certificates are for development only; production certificate authority, certificate storage, and renewal requirements are not provided.
- The FastAPI Git repository remains an application dependency, but its source, release policy, health endpoint, migrations, and dependency lockfile were not reviewed.
- PostgreSQL is local to the application VM and the `fastapi` database/user are intended to be retained, but PostgreSQL version and backup/restore requirements are unspecified.
- Redis authentication is required because the source sets `requirepass`, but TLS, network binding, ACLs, persistence, backup, and high availability requirements are unspecified.
- Memcached is required by the `cache` cookbook dependency, but no application usage or memory/eviction policy is visible.
- The Chef `ssl_certificate` lock entry is unused by the local recipes and may be removable after dependency validation.
- The current direct shell commands, hardcoded credentials, root-run application service, and moving Git branch are not acceptable production defaults and will be remediated rather than reproduced.
- Ansible controller connectivity, inventory grouping, CI platform, secret manager, and deployment/cutover strategy have not been specified; the migration team must agree these before implementation.
- Success means semantic equivalence for intended services and security behavior, not literal reproduction of Chef implementation details or known defects.
