# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Berkshelf environment containing three local cookbooks: an Nginx multi-site/security stack, cache services, and a FastAPI/PostgreSQL application. The intended target is a Vagrant/libvirt development VM, although the Vagrant box and provisioning script currently disagree on the operating system. The migration is moderate in implementation risk: there are only three cookbooks, but the Nginx cookbook combines TLS, firewall, SSH hardening, Fail2ban, templates, and custom resource behavior, while the application cookbook contains embedded credentials and imperative database setup.

A realistic first migration is approximately 2–4 engineer-weeks, including Ansible role development, secret redesign, Fedora/Ubuntu target decisions, functional testing, and parallel Chef/Ansible validation. A basic proof of concept could be produced in 3–5 days; production-ready parity should not be accepted until service, TLS, firewall, database, and application smoke tests pass.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web hosting for three SSL-enabled virtual hosts, with static site roots, HTTP-to-HTTPS redirects, security headers, rate limiting, hardened TLS settings, Fail2ban, UFW, sysctl settings, and SSH hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef cookbook
    - Key Features: `nginx-multisite::default` composes `security`, `nginx`, `ssl`, and `sites`; ERB templates for Nginx and Fail2ban; generated self-signed certificates; links in `sites-enabled`; static files for `test`, `ci`, and `status`; custom `lineinfile` resource.
    - Migration complexity: High relative to the repository because it spans web serving, host security, certificates, firewall state, service handlers, and OS-specific paths.

- **cache**:
    - Description: Installs and enables Memcached and Redis, configures a Redis server on port 6379 with password authentication, creates its log directory, and applies a post-configuration workaround to remove selected replication settings.
    - Path: `cookbooks/cache`
    - Technology: Chef cookbook
    - Key Features: External `memcached` and `redisio` cookbooks; Redis password; Redis service enablement; imperative `ruby_block` editing `/etc/redis/6379.conf`.
    - Migration complexity: Moderate; the service installation is straightforward, but the Redis configuration workaround must be understood and replaced with declarative configuration.

- **fastapi-tutorial**:
    - Description: Installs Python and PostgreSQL packages, clones the FastAPI tutorial application from GitHub, creates a virtual environment, installs requirements, creates a PostgreSQL user/database, writes an environment file, and manages a root-run Uvicorn systemd service on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef cookbook
    - Key Features: Git deployment from `https://github.com/dibanez/fastapi_tutorial.git` at `main`; Python virtualenv and pip installation; PostgreSQL service; database bootstrap; systemd unit; `.env` file.
    - Migration complexity: Moderate to high because application release reproducibility, database idempotence, privilege boundaries, and secrets need redesign.

**CRITICAL PATH VERIFICATION:**
The three paths above are present in the supplied repository tree and their metadata and primary recipes were reviewed. No Puppet, Salt, or PowerShell modules were identified.

### Infrastructure Files

- `Berksfile`: Chef dependency source and version constraints. It references the three local cookbooks plus `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`; a commented `ssl_certificate` dependency is also present.
- `Policyfile.rb`: Chef policy run list and dependency declarations. It includes `ssl_certificate ~> 2.1` even though it is not in the active run list.
- `Policyfile.lock.json`: Resolved dependency snapshot. It locks local cookbooks at 1.0.0, Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SELinux 6.2.4, and ssl_certificate 2.1.0. It shows `redisio` bringing in `selinux` and records local cookbook working trees as not clean.
- `Vagrantfile`: Defines a `generic/fedora42` VM named `chef-nginx`, 2 GB RAM/2 CPUs, libvirt provider, private IP `192.168.121.10`, and host forwards for ports 80/443. It syncs the repository to `/chef-repo` and invokes the shell provisioner.
- `vagrant-provision.sh`: Installs packages with `apt-get`, installs Chef from Omnitruck, installs Berkshelf, vendors dependencies, and runs Chef Solo. It documents test endpoints and self-signed TLS. This is a critical migration/test harness and is currently inconsistent with the Fedora box.
- `solo.rb`: Chef Solo cache, cookbook paths, and logging configuration. Replace with Ansible inventory, role paths, and execution documentation.
- `solo.json`: Chef run list plus Nginx sites, SSL paths, Fail2ban/UFW/SSH settings. These values should become reviewed Ansible group/host variables, with secrets removed from plaintext.
- `project-plan.md`: Describes the surrounding X2Ansible analysis/migration tool, not target host configuration. It may inform automation workflow but should not be treated as infrastructure intent.

### Target Details

- **Operating System:** Intended runtime is ambiguous. `Vagrantfile` selects Fedora 42, but `vagrant-provision.sh` uses Debian/Ubuntu commands (`apt-get`, `www-data`, `/var/log/auth.log`, UFW) and the cookbooks declare support for Ubuntu >=18.04 and CentOS >=7. The current configuration most closely assumes Ubuntu/Debian. Decide explicitly between Fedora/RHEL-family and Ubuntu before implementation. If no decision is made, use the repository's explicit Vagrant box as the test target but port package names, firewall, service names, SELinux, web-user, and log paths for Fedora.
- **Virtual Machine Technology:** Vagrant with the libvirt provider; 2 CPUs and 2048 MB memory. No production VM platform is specified.
- **Cloud Platform:** Not specified. No AWS, Azure, or GCP configuration was found.
- **Networking:** Development private address is `192.168.121.10`; forwarded host ports are 8080→80 and 8443→443. The application listens on guest port 8000 but no corresponding Vagrant forward or Nginx reverse proxy is configured in reviewed files.

## Migration Approach

Create an Ansible project with an inventory for the chosen OS and Vagrant test host, then split the source into roles: `nginx_multisite`, `host_security`, `cache`, and `fastapi_tutorial`. Preserve the current composition through a top-level site playbook, but make variables explicit and environment-specific. Use handlers for Nginx/Fail2ban/SSH/systemd reloads, `ansible.builtin.template` for the reviewed ERB templates converted to Jinja2, `ansible.builtin.package/service/file`, `community.general.ufw` or `ansible.posix.firewalld`, `ansible.posix.sysctl`, `community.postgresql`, and `ansible.builtin.systemd`.

First establish a baseline by running the existing Chef setup where feasible and recording packages, services, rendered files, listening ports, certificates, firewall rules, and application behavior. Then implement roles in dependency order and run both implementations against disposable VMs. Do not copy Chef imperative shell behavior blindly: every command should have an idempotence condition or be replaced by a purpose-built Ansible module.

### Key Dependencies to Address

- **Chef Solo/Berkshelf/Policyfile:** Replace with Ansible collections, roles, `requirements.yml`, inventory, and pinned collection versions. Retain the lock file as a migration reference only.
- **nginx cookbook 12.3.1:** Replace with an internal `nginx_multisite` role or a vetted Ansible role; render and validate Nginx configuration with `nginx -t` before reload.
- **memcached cookbook 6.1.0:** Replace with distribution packages and service tasks, or a pinned Ansible role. Confirm bind address and exposure, since the source does not show a dedicated Memcached configuration.
- **redisio cookbook 7.2.4 plus SELinux 6.2.4:** Replace with distribution Redis packages and an Ansible-managed config. Model the password using Vault and handle SELinux labels/booleans on Fedora/RHEL rather than assuming Debian paths.
- **ssl_certificate 2.1.0:** It is locked but not used by the reviewed active recipe; determine whether it is legacy or required elsewhere. Replace development self-signed certificates with Ansible-managed test certificates and production certificates from an approved PKI/ACME process.
- **Python, pip, virtualenv, Git, PostgreSQL:** Use package/module tasks and a pinned application dependency strategy. Avoid installing an unpinned `main` branch in production; prefer a commit/tag and a checksum or artifact repository.
- **PostgreSQL database provisioning:** Replace shell `psql` commands with `community.postgresql.postgresql_user` and `postgresql_db`, with explicit idempotence and authentication handling.
- **Systemd:** Convert the inline unit to a Jinja2 template and use `daemon_reload` plus service enable/start handlers.
- **Custom Chef `lineinfile` resource:** No caller was observed in the reviewed primary recipes. Do not migrate it automatically; search for usage during implementation and use `ansible.builtin.lineinfile` only where behavior is actually required.

### Security Considerations

- **Hardcoded Redis credential:** `cookbooks/cache/recipes/default.rb` contains `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager, rotate it, and ensure Redis is not exposed beyond required interfaces.
- **Hardcoded PostgreSQL credentials:** `fastapi-tutorial` creates user `fastapi` with password `fastapi_password` and writes it into `/opt/fastapi-tutorial/.env` mode 0644. Treat it as compromised, rotate it, store it in Vault, set restrictive ownership/mode, and avoid logging it in task output.
- **TLS private keys:** The source writes keys under `/etc/ssl/private` with `root:ssl-cert` and mode 0640, but generates self-signed certificates. Preserve least privilege, protect key material, and use trusted certificates in non-development environments. Do not commit generated keys.
- **TLS policy:** Nginx permits TLS 1.2/1.3 and a narrow cipher list, enables HSTS, and sets security headers. Validate compatibility and modernize the cipher policy deliberately rather than changing it unintentionally during templating.
- **SSH hardening:** Root login and password authentication are disabled through `sed`. Use `ansible.builtin.lineinfile`/`sshd_config` fragments with validation (`sshd -t`) and maintain an out-of-band access/recovery plan before applying.
- **Firewall:** UFW defaults to deny and permits SSH/HTTP/HTTPS. Reproduce this with the target OS firewall module, account for Vagrant/libvirt access, and test lockout prevention. Fedora may require firewalld rather than UFW.
- **Fail2ban:** The source enables SSH and Nginx jails and references Debian-style `/var/log/auth.log`. Adapt log paths and filters to the chosen OS, and test that filters do not block legitimate operators.
- **Application privilege:** The systemd service runs Uvicorn as `root`. Create a dedicated unprivileged service account, define writable directories explicitly, and limit capabilities.
- **Network exposure:** Uvicorn binds to `0.0.0.0:8000` without an Nginx proxy in the reviewed configuration. Bind internally or explicitly firewall the port; decide whether the service is meant to be publicly reachable.
- **Supply chain:** GitHub `main` and pip requirements are mutable unless pinned. Pin source revisions and dependencies, scan artifacts, and establish trusted package indexes.
- **Secrets management by module:** `cache` has a Redis password; `fastapi-tutorial` has PostgreSQL credentials and a database URL; `nginx-multisite` handles TLS private keys/certificates but no encrypted data bags or Chef Vault usage were found. `solo.json` contains site and security settings but no credentials.

### Technical Challenges

- **OS mismatch is a migration blocker:** Fedora 42 is provisioned with `apt-get`, while templates and service/log assumptions are Ubuntu/Debian-oriented. Select a canonical OS, add OS-family variables, and test package names, service names, users, paths, firewall, SELinux, and Fail2ban logs.
- **Nginx template semantics:** The ERB site template creates paired HTTP/HTTPS server blocks and per-site links. Convert loop variables carefully, preserve all three hostnames and document roots, and run `nginx -t` before handlers reload the service.
- **Certificate lifecycle:** Chef generates certificates only when files are absent. Ansible must define renewal/rotation behavior, avoid overwriting production certificates, and distinguish development self-signed material from production PKI.
- **Imperative configuration workarounds:** Redis uses a Ruby block that deletes selected lines from a generated config. Identify the Redis version-specific reason, express the desired final settings in one managed template/drop-in, and test upgrades.
- **Database idempotence and bootstrapping:** The Chef shell uses `|| true`, hiding failures and making partial state likely. Use PostgreSQL modules, explicit privileges, readiness checks, and migrations/health checks.
- **Application deployment reliability:** Cloning `main` and running pip on every convergence is not a controlled release model. Pin an artifact/commit, use a dedicated user, add a virtualenv ownership strategy, and define restart behavior when code or dependencies change.
- **Static content mapping:** The cookbook maps the first hostname segment to files under `files/default/{test,ci,status}` while attributes use `/opt/server/...` and `solo.json` overrides use `/var/www/...`. Resolve the authoritative document roots and verify content placement.
- **Configuration divergence:** `Policyfile.rb` and `Berksfile` differ on `ssl_certificate`, and the lock records a non-clean local working tree. Establish a clean baseline and dependency policy before comparing behavior.
- **Testing and rollback:** Firewall and SSH changes can remove access; use snapshots, serial rollout, `--check` where meaningful, syntax/lint checks, service validation, and an explicit rollback playbook.

### Migration Order

1. **Baseline and platform decision:** Reproduce or document the current Chef behavior, choose Ubuntu/Debian versus Fedora/RHEL, pin source/dependency versions, and create inventory plus Ansible Vault structure.
2. **Host security foundation:** Implement package facts, SSH hardening with validation, sysctl, firewall, and Fail2ban. Test access and rollback before proceeding.
3. **cache:** Migrate Memcached and Redis with declarative configuration, secret injection, service checks, and OS-specific paths. This is relatively isolated and validates dependency/secret patterns.
4. **nginx-multisite:** Migrate Nginx installation, templates, static files, certificates, virtual hosts, headers, rate limits, and handlers. Validate all three sites and TLS before enabling production traffic.
5. **fastapi-tutorial:** Migrate PostgreSQL, application checkout/artifact, virtualenv, secret-backed `.env`, systemd, and health checks. Integrate with Nginx only after the desired proxy/public exposure is decided.
6. **Cutover and decommissioning:** Run Chef and Ansible comparison tests, perform staged cutover, retain Vagrant snapshots/rollback, and remove Chef-only dependency and provisioning paths after acceptance.

### Assumptions

- The repository is a Chef Solo repository, not a Chef Server environment; no roles, environments, encrypted data bags, or Chef Vault files were found in the supplied tree.
- The three local cookbooks are the complete active module inventory; external cookbooks are dependencies, not separately migrated local modules.
- `Policyfile.lock.json` is the authoritative resolved dependency snapshot, despite the recorded dirty local working trees.
- The intended test machine is the Vagrant/libvirt VM, but the Fedora/Ubuntu mismatch must be resolved rather than assumed away.
- The application Git repository and its `requirements.txt` are external inputs and were not inspected; runtime compatibility and dependency security remain open validation tasks.
- PostgreSQL package/service names, database authentication defaults, and the exact installed version are not specified.
- The source does not configure Redis or Memcached bind addresses, persistence, memory limits, or production replication semantics beyond the Redis password and workaround.
- The source's `solo.json` document roots override the cookbook defaults; the migration must confirm whether `/var/www/...` or `/opt/server/...` is intended.
- The source creates self-signed certificates for development; no production certificate issuer or renewal process is specified.
- Nginx is configured for static content only in reviewed files; no application reverse-proxy relationship is defined for FastAPI.
- UFW, Debian users (`www-data`), Debian log paths, and `apt-get` suggest Ubuntu/Debian intent, but the explicit Fedora 42 box may represent a planned future target.
- No cloud platform, production inventory, DNS automation, load balancer, monitoring, backup, or disaster-recovery requirements are present.
- A secret rotation and external secret-management decision is required before any non-development deployment.
- Timeline estimate assumes one platform/Ansible engineer and one application/security reviewer working in parallel; additional OS targets or production integrations will extend it.
