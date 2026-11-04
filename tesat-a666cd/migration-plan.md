# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile deployment containing three local cookbooks: an Nginx multi-site/security stack, caching services, and a FastAPI tutorial application with PostgreSQL. The migration is moderate in operational risk despite the small module count because it includes firewall and SSH hardening, self-signed TLS generation, plaintext application/database credentials, service orchestration, and a custom Chef resource. A focused team should be able to produce a tested Ansible implementation in approximately 2–4 weeks, including platform reconciliation, secret remediation, functional testing, and documentation. A minimal proof of concept could be completed in 3–5 working days, but should not be treated as production-ready.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx installation and configuration for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), with static content, security hardening, firewall configuration, SSH restrictions, Fail2ban, sysctl settings, and development certificate generation.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: Nginx service management; generated per-site configuration and enablement links; configurable document roots and certificate paths; UFW default-deny rules for SSH/HTTP/HTTPS; Fail2ban; root-login and password-authentication disabling; self-signed RSA certificates; custom security and Nginx templates.

- **cache**:
    - Description: Installs and enables Memcached and Redis, configures a Redis server on port 6379, and applies a post-configuration workaround to remove selected replication and client-buffer directives.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: Memcached inclusion; Redisio integration; Redis password authentication; Redis log directory; service enablement; custom Ruby-based configuration mutation.

- **fastapi-tutorial**:
    - Description: Installs Python and PostgreSQL prerequisites, checks out the FastAPI tutorial application, creates a Python virtual environment, installs application requirements, provisions a PostgreSQL database/user, writes an application environment file, and manages a systemd service running Uvicorn.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git-based application deployment from `https://github.com/dibanez/fastapi_tutorial.git` at `main`; Python virtualenv; PostgreSQL service and database bootstrap; `.env` generation; systemd unit; Uvicorn on `0.0.0.0:8000`.

**CRITICAL PATH VERIFICATION:**

The module paths above were present in the supplied repository tree and their primary entrypoints were reviewed. External cookbooks are dependencies, not local modules, and are therefore not listed in the module inventory.

### Infrastructure Files

- `Berksfile`: Chef dependency source and local cookbook declarations. It references local cookbooks plus Supermarket dependencies for Nginx, Memcached, Redisio, and an optionally commented SSL cookbook. Replace this dependency-resolution workflow with Ansible Collections/roles and explicit platform package/service tasks.
- `Policyfile.rb`: Defines the Chef policy name, run list, local cookbook paths, and external version constraints. Its run order should become an Ansible playbook role order, with explicit handlers and dependencies.
- `Policyfile.lock.json`: Captures resolved versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `selinux` 6.2.4, and `ssl_certificate` 2.1.0, plus local cookbook revisions. Preserve this as migration evidence, but do not assume the old cookbook behavior maps directly to current Ansible modules.
- `solo.json`: Chef node attributes and run list. It overrides the three site document roots to `/var/www/...`, supplies SSL directories, and enables Fail2ban/UFW/SSH hardening. These values should be converted into group/host variables with environment-specific overlays.
- `solo.rb`: Chef Solo cache, cookbook search paths, and logging configuration. Replace with Ansible inventory, `ansible.cfg`, role paths, and execution logging conventions.
- `Vagrantfile`: Local Fedora 42 VM using the libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded ports 8080/8443. It rsyncs the repository to `/chef-repo` and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef/Berkshelf, vendors dependencies, and runs Chef Solo. It should be replaced by an Ansible provisioner or an Ansible command against the Vagrant guest; package/bootstrap logic must be made compatible with the selected OS.
- `project-plan.md`: Existing project planning context should be reconciled with the Ansible implementation plan and acceptance criteria before migration work begins.
- `cookbooks/nginx-multisite/templates/`: Source templates for Nginx, virtual hosts, Fail2ban, and sysctl security settings. These should become Ansible role templates, with syntax and variable validation added.
- `cookbooks/nginx-multisite/files/`: Static `index.html` content for the test, CI, and status sites. These should be deployed with `ansible.builtin.copy` or packaged as role files.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource that edits a line and optionally writes timestamped backups. Replace with `ansible.builtin.lineinfile` or, preferably, managed templates where the full configuration is owned by Ansible.

### Target Details

- **Operating System**: The Vagrant box is `generic/fedora42`, indicating Fedora 42 for the development target. The cookbook metadata claims Ubuntu >=18.04 and CentOS >=7, while `vagrant-provision.sh` uses Debian/Ubuntu `apt-get`. The target OS is therefore unresolved and must be selected before implementation. If no production specification exists, default the migration design to Red Hat Enterprise Linux 9 as required by the migration standard, while retaining a Fedora-compatible development profile. UFW is Debian-oriented; RHEL 9 should use firewalld unless UFW is explicitly mandated.
- **Virtual Machine Technology**: libvirt via Vagrant, with rsync-based source synchronization.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP configuration was identified.

## Migration Approach

Create an Ansible project with an inventory, `group_vars`/`host_vars`, and separate roles such as `nginx_multisite`, `cache`, `fastapi_tutorial`, and possibly `common_security`. Keep application, cache, web, and host-security ownership clear so teams can test and release them independently. Use handlers for Nginx/Fail2ban/SSH/systemd reloads and use check mode, Molecule or equivalent disposable-VM tests, and service-level smoke tests.

Translate Chef resources as follows:

- Chef `package`, `service`, `directory`, `file`, `template`, `link`, and `execute` resources become corresponding Ansible modules.
- Chef recipe inclusion becomes role dependencies or explicit role ordering in the main playbook.
- Chef node attributes become typed defaults and environment-specific variables.
- The custom Redis Ruby block should be eliminated by managing the Redis configuration declaratively. If compatibility requires edits, use `lineinfile` with carefully bounded regular expressions and notify Redis.
- Replace shell-based database creation with PostgreSQL modules (`community.postgresql.postgresql_user`, `postgresql_db`, and privilege modules), using idempotent state rather than `|| true` commands.
- Replace hand-written systemd file management with a managed template plus `systemd_service`/`service` handlers, or package the service unit as a role template.

### Key Dependencies to Address

- **nginx cookbook 12.3.1**: Replace with `ansible.builtin.package`, templated Nginx configuration, virtual-host tasks, symlinks, and service handlers. Validate configuration with `nginx -t` before reload.
- **memcached cookbook 6.1.0**: Replace with platform package/service tasks and an explicit configuration policy. Confirm bind address, memory limits, and firewall exposure.
- **redisio cookbook 7.2.4**: Replace with a supported Redis role or internally maintained Ansible role. Preserve port 6379 and authentication behavior, but do not carry over the plaintext password. Decide whether the legacy directive-removal workaround is still required for the selected Redis version.
- **selinux cookbook 6.2.4**: On RHEL/Fedora, use `ansible.posix.selinux`, package policy tools, and appropriate SELinux contexts/booleans. Test Nginx, Redis, PostgreSQL, and application access under enforcing mode.
- **ssl_certificate cookbook 2.1.0**: The local cookbook actually generates self-signed certificates directly; decide whether to use Ansible `community.crypto` for development certificates or an enterprise CA/ACME workflow for real environments.
- **Python 3, pip, venv, Git, PostgreSQL, libpq-dev**: Map package names by OS. Use `ansible.builtin.git`, `ansible.builtin.pip` or a virtualenv-aware installation strategy, and PostgreSQL collection modules.
- **Uvicorn/FastAPI application repository**: Pin a commit or release rather than deploying the mutable `main` branch. Verify that `requirements.txt` and the `app.main:app` entrypoint remain valid.
- **Vagrant/libvirt**: Replace the shell Chef provisioner with Ansible provisioning and retain the VM as an integration-test target, after correcting the OS/package-manager mismatch.

### Security Considerations

- **Plaintext Redis credential**: `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123` in source. Rotate it, remove it from Git history where policy requires, and store the replacement in Ansible Vault or an external secret manager. Restrict Redis binding and firewall exposure.
- **Plaintext PostgreSQL credentials**: The FastAPI recipe embeds `fastapi_password` in SQL commands and writes it into `/opt/fastapi-tutorial/.env` with mode `0644`; the connection string repeats it. Generate/rotate a strong credential, use Vault, set the file to a restrictive mode such as `0600`, and avoid exposing it in command-line process listings or logs.
- **Application execution privileges**: The systemd service runs Uvicorn as `root`. Create a dedicated non-login application user, assign ownership appropriately, and use systemd hardening options where compatible.
- **TLS certificates and private keys**: Certificates are self-signed for development and private keys are placed under `/etc/ssl/private` with group `ssl-cert` and mode 0640. Production migration must use managed certificates, secure key distribution, correct SANs, rotation, and validation. Never commit private keys.
- **SSH hardening**: The cookbook disables root login and password authentication through `sed`. Implement with a managed `sshd_config` drop-in or validated template, ensure a tested administrative key path exists first, and use `sshd -t` before restarting to avoid lockout.
- **Firewall policy**: UFW is configured default-deny with SSH/HTTP/HTTPS allowed. On RHEL/Fedora, translate this to firewalld and explicitly decide whether application port 8000 or cache ports should remain internal only. Test connectivity before enabling the firewall.
- **Fail2ban and sysctl**: Preserve the security intent of the Fail2ban jail and sysctl template, but review rules for the target OS and current service log formats. Apply least privilege and validate before enabling enforcement.
- **Remote code and dependency integrity**: The application is cloned from GitHub at `main`, and pip requirements are installed without a visible lock file or hash policy. Pin source revisions and dependency hashes, use trusted package indexes, and scan dependencies.
- **TLS and Nginx exposure**: The three hostnames are development names and certificates are generated with a one-year lifetime. Confirm DNS/hosts behavior, protocol/cipher policy, and whether the default Nginx site is safely removed.

### Technical Challenges

- **OS inconsistency**: Fedora 42 is provisioned with `apt-get`, while cookbook metadata supports Ubuntu/CentOS. Resolve the target matrix first; provide separate variable maps and firewall/SELinux implementations if multiple families must remain supported.
- **Configuration drift between attributes and JSON**: Attribute defaults use `/opt/server/{test,ci,status}`, while `solo.json` overrides them to `/var/www/{...}`. Treat `solo.json` as the effective current test configuration and explicitly document the desired target values.
- **Nginx template behavior and site content**: The reviewed recipes create content paths and deploy files, but template correctness and exact security directives live in unreviewed templates. Port templates carefully, validate with `nginx -t`, and test all three hostnames over HTTP/HTTPS.
- **Certificate lifecycle**: Self-signed generation is suitable only for development and is not a production certificate-management process. Establish CA/ACME ownership and renewal before cutover.
- **Database idempotency**: Shell SQL commands use `|| true`, which can mask failures and do not manage password rotation cleanly. Use PostgreSQL modules and migration/initialization steps with explicit ownership and privileges.
- **Redis compatibility workaround**: The Ruby block removes multiple directives after Redis configuration. Determine the underlying version/configuration issue before reproducing it; otherwise the Ansible role may preserve an obsolete or unsafe workaround.
- **Application deployment reliability**: Mutable Git `main`, pip installation at converge time, root execution, and no visible health check create repeatability risks. Introduce version pinning, artifact promotion, non-root execution, and a readiness check.
- **Chef dependency lock translation**: The lock includes transitive `selinux` and `ssl_certificate` cookbooks even though the local recipes do not directly include all of them. Map only behavior actually required, then pin Ansible collection versions in `requirements.yml`.
- **Vagrant networking/name resolution**: The Vagrantfile comments out `/etc/hosts` entries, yet virtual hosts use cluster-local names. Add deterministic test name resolution and verify forwarded ports versus the documented addresses, which currently contain inconsistent IP/port examples.

### Migration Order

1. **Platform and test foundation**: Decide the supported OS, correct the Vagrant/Ansible provisioning path, establish inventory, Vault policy, collection pins, and baseline connectivity tests.
2. **FastAPI/PostgreSQL application role**: Implement packages, repository pinning, virtualenv, database modules, secure `.env`, dedicated service account, systemd unit, and health checks. This establishes application dependencies and exposes secret issues early.
3. **Cache role**: Implement Memcached and Redis with secure credentials, internal binding, idempotent configuration, service checks, and SELinux/firewall tests. Validate application connectivity.
4. **Nginx multi-site role**: Port templates, document roots, static files, site links, service handlers, and upstream/application integration. Test all three sites and SSL behavior.
5. **Host security hardening**: Apply SSH, firewall, Fail2ban, sysctl, SELinux, and certificate controls after access recovery and service tests are proven. Roll out in a staged environment to avoid administrative lockout.
6. **Integration and cutover**: Run convergence twice, check mode, reboot persistence, TLS/certificate tests, database/cache/application smoke tests, and rollback rehearsal before replacing Chef.

Estimated effort: 1–2 days for inventory and platform decisions, 3–5 days for application and cache roles, 3–5 days for Nginx/security roles, and 3–7 days for testing, secret rotation, documentation, and team review. Add time if production certificate issuance, multi-OS support, or external secret-manager integration is required.

### Assumptions

- The three local cookbook directories are the complete source module inventory for this repository.
- `Policyfile.lock.json` represents the effective resolved dependency versions, although local cookbook working trees were recorded as not clean.
- `solo.json` values are intended to override the attribute defaults for the current deployment; this must be confirmed because the paths conflict.
- The migration target is server configuration managed by Ansible, not a redesign of the FastAPI application itself.
- The external GitHub repository and its runtime contract are available during migration; no application source is included locally.
- PostgreSQL is intended to run locally on the same host as the FastAPI service, and Redis/Memcached are intended as local services unless deployment owners specify otherwise.
- The three `.cluster.local` names are development/test names; production DNS, certificate names, and traffic topology are not supplied.
- Self-signed certificates are for development only. Production certificate authority, renewal, and secret distribution are unresolved.
- No external secret manager, Chef encrypted data bag, Chef Vault, or encrypted attribute source was found in the reviewed files; visible credentials are plaintext and require remediation.
- The desired production OS and firewall implementation are unspecified. RHEL 9 is the default design target, but Fedora 42 is the current Vagrant box and Ubuntu-style provisioning is present.
- The exact contents and directives of the Nginx, Fail2ban, sysctl, and site templates require validation during implementation; this plan does not assume their unreviewed details.
- The existing project has no stated CI, monitoring, backup, PostgreSQL schema migration, or rollback process; these must be assigned and documented by the owning teams.
- Team coordination should assign separate owners for platform/inventory, application/PostgreSQL, cache, Nginx/TLS, and security review. Agree on variable contracts, secret ownership, acceptance tests, and a Chef-to-Ansible cutover window before production deployment.
