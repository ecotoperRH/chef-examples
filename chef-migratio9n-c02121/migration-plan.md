# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure project that provisions a multi-service application stack on a single virtual machine (Fedora 42 / generic libvirt box). The project is managed via a `Policyfile.rb` and `Berksfile`, and is exercised locally through Vagrant with a shell provisioner that installs Chef and runs `chef-solo`.

Three local cookbooks form the core of the stack: a hardened Nginx multisite web server, a dual caching layer (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL. These depend on four external Supermarket cookbooks (`nginx ~> 12.0`, `ssl_certificate ~> 2.1`, `memcached ~> 6.0`, `redisio ~> 7.2.4`).

**Migration scope**: 3 local Chef cookbooks → 3 Ansible roles (already partially scaffolded in the `weqe-d92f93/modules/` subtree). A standalone `nginx` Ansible role also exists in `123-fc2c2f/modules/nginx/` as a separate, independent artifact.

**Complexity**: Medium. The Chef logic is well-structured and maps cleanly to Ansible idioms. The main challenges are: replacing the `redisio` source-compile workflow with a package-based install, eliminating two hardcoded plaintext credentials, and replacing the `ssl_certificate` community cookbook with Ansible's `openssl_*` modules.

**Estimated timeline**: 3–4 weeks for a single engineer, including testing with Molecule (already scaffolded).

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that need individual migration planning, plus **1 pre-existing Ansible role** that is already complete:

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads.

---

- **nginx-multisite**:
  - Description: Hardened Nginx web server hosting three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`). Installs Nginx, deploys a global `nginx.conf` and a `security.conf` snippet (rate limiting, TLS 1.2/1.3 only, strict cipher suite), generates per-site self-signed RSA-2048 certificates via `openssl req`, creates sites-available/sites-enabled symlinks, and removes the default site. Also applies a full OS security baseline: UFW firewall (default-deny, allow 22/80/443), fail2ban with five jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch, DEFAULT), kernel sysctl hardening (IP spoofing protection, SYN cookies, IPv6 disable, ICMP ignore), and SSH hardening (PermitRootLogin no, PasswordAuthentication no).
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Multi-recipe structure (security → nginx → ssl → sites), ERB templates for all config files, attribute-driven site definitions, HTTP→HTTPS 301 redirects, HSTS, security headers (X-Frame-Options, X-Content-Type-Options, CSP), per-site access/error logs, `www-data` ownership of document roots, `ssl-cert` group for private key access.
  - Ansible Role (already scaffolded): `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite/`

---

- **cache**:
  - Description: Dual caching service provisioner deploying Memcached (port 11211, 64 MB RAM, 1024 max connections, bound to `0.0.0.0`) and Redis (port 6379, password-authenticated, source-compiled from Redis 3.2.11 tarball by default, systemd-managed via `redis@6379.service`). Includes a `ruby_block` post-processing hack that strips five deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` to work around version compatibility issues. Redis password is hardcoded as `redis_secure_password_123` in the recipe.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Depends on `memcached ~> 6.0` and `redisio ~> 7.2.4` (both Sous Chefs community cookbooks), Redis source-compile from `http://download.redis.io/releases/redis-3.2.11.tar.gz`, PAM ulimit configuration for the `redis` user (file descriptor limit 10032), OS-default Redis service stopped/disabled to prevent conflicts, breadcrumb file prevents config overwrite on re-runs.
  - Ansible Role (already scaffolded): `weqe-d92f93/modules/cache/ansible/roles/cache/`

---

- **fastapi-tutorial**:
  - Description: Full-stack Python application provisioner. Clones the FastAPI tutorial application from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs pip dependencies from `requirements.txt`, provisions a PostgreSQL database (`fastapi_db`) and user (`fastapi`) with hardcoded password `fastapi_password`, writes a `.env` file containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`, and registers a systemd service (`fastapi-tutorial.service`) running uvicorn on `0.0.0.0:8000` as root.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Git-based application deployment, Python venv management, PostgreSQL provisioning via raw `psql` shell commands (with `|| true` guards), systemd unit file deployed inline, service runs as root (security concern), `.env` file contains plaintext database credentials (mode 0644).
  - Ansible Role (already scaffolded): `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/`

---

- **nginx** *(pre-existing Ansible role — no migration required)*:
  - Description: Standalone Ansible role for Nginx web server installation and configuration with support for multiple sites, custom HTTP parameters, and platform-specific configurations. This role is already complete and is not derived from any Chef cookbook in this repository.
  - Path: `123-fc2c2f/modules/nginx/ansible/roles/nginx/`
  - Technology: Ansible (already migrated)
  - Key Features: Molecule test suite (converge/verify/destroy), Jinja2 templates (`nginx.conf.j2`, `site.j2`, `default.conf.j2`, `default.j2`), EPEL repo file for RHEL-family targets, role defaults and vars separation, argument specs defined.

---

### Infrastructure Files

- `Policyfile.rb`: Chef Policyfile defining the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all cookbook version constraints. This is the authoritative dependency manifest — its run list order directly maps to the Ansible playbook task order.
- `Policyfile.lock.json`: Locked dependency graph for the policy. Contains resolved cookbook artifact hashes. Reference this when verifying exact external cookbook versions during migration.
- `Berksfile`: Berkshelf dependency file mirroring the Policyfile. Used by the Vagrant provisioner (`berks install && berks vendor`) to download cookbooks before `chef-solo` runs.
- `solo.json`: Chef Solo node attributes JSON. Defines the run list and all node-level attribute overrides (site definitions, SSL paths, security flags). This file is the direct source of truth for Ansible `defaults/main.yml` variable values.
- `solo.rb`: Chef Solo configuration file. Sets `cookbook_path` to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks`. No migration action needed; documents the cookbook search path used during Vagrant runs.
- `Vagrantfile`: Vagrant configuration targeting `generic/fedora42` via libvirt (2 vCPUs, 2 GB RAM, private network `192.168.121.10`, forwarded ports 8080→80 and 8443→443). Provisions via `vagrant-provision.sh`. Defines the target OS and resource profile for the Ansible inventory.
- `vagrant-provision.sh`: Shell provisioner that installs Chef via the Omnitruck script, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo -c solo.rb -j solo.json`. This script will be replaced by an Ansible playbook invocation.
- `weqe-d92f93/modules/cache/migration-dependencies/`: Vendored copies of all external cookbook artifacts (`memcached`, `redisio`, `selinux`, `ssl_certificate`, `nginx`, `nginx-multisite`, `fastapi-tutorial`). These are the reference implementations for understanding what the external cookbooks do — essential reading before finalising the `cache` Ansible role.
- `weqe-d92f93/modules/*/ansible/roles/*/aap-configuration/`: AAP (Ansible Automation Platform) credential type and credential definitions for the `cache` and `fastapi_tutorial` roles. These define the Vault/AAP credential store integration points for the two hardcoded secrets.

---

### Target Details

- **Operating System**: Fedora 42 (from `Vagrantfile`: `config.vm.box = "generic/fedora42"`). Chef cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, indicating the cookbooks are cross-platform. The Ansible roles should target RHEL-family (Fedora/CentOS/RHEL) as the primary platform, with Ubuntu as a secondary target.
- **Virtual Machine Technology**: libvirt / KVM (from `Vagrantfile`: `config.vm.provider "libvirt"`). Private network IP `192.168.121.10`.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present. This is a local/on-premises Vagrant-based development environment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0, Sous Chefs)**: The `nginx-multisite` cookbook installs Nginx directly via the OS package manager (`package 'nginx'`) without calling the community `nginx` cookbook. The community cookbook is listed as a dependency in `Policyfile.rb` but is not `include_recipe`'d in any local cookbook recipe. Replace with `ansible.builtin.package` + `ansible.builtin.template` — already implemented in the scaffolded `nginx_multisite` role.

- **ssl_certificate (~> 2.1, Sous Chefs)**: Listed in `Policyfile.rb` but not directly called by any local cookbook recipe. SSL certificate generation is handled inline in `nginx-multisite::ssl` via raw `openssl req` shell commands. Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection, or retain the `ansible.builtin.command` approach for self-signed development certs.

- **memcached (~> 6.0, Sous Chefs)**: Installs the `memcached` OS package, creates the `memcached` system user/group, and manages the service. Replace with `ansible.builtin.package`, `ansible.builtin.user`, `ansible.builtin.group`, and `ansible.builtin.service` — already implemented in the scaffolded `cache` role (`memcached.yml` task file).

- **redisio (~> 7.2.4, Sous Chefs)**: The most complex external dependency. Compiles Redis 3.2.11 from source by default (downloads tarball, runs `make`, installs to `/usr/local/bin`), manages systemd unit files, PAM ulimit configuration, and a breadcrumb-based idempotency mechanism. The Ansible `cache` role replaces this with a package-based install (`cache_redis_package_install: false` by default, but the role's task files — `redisio_install.yml`, `redisio_configure.yml`, etc. — replicate the full workflow). **Decision required**: confirm whether source-compile (Redis 3.2.11) or OS package install is the target. Redis 3.2.11 is EOL; upgrading to a current version (7.x) is strongly recommended.

- **selinux (transitive, via redisio)**: The `redisio` cookbook depends on the `selinux` community cookbook. On Fedora 42 (the target OS), SELinux is enforcing by default. The Ansible migration must account for SELinux contexts for Redis data directories, config files, and the custom binary path (`/usr/local/bin/redis-server`). Use `community.general.sefcontext` or `ansible.builtin.command: restorecon` as needed.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123`): Defined in plaintext in `cookbooks/cache/recipes/default.rb` as `'requirepass' => 'redis_secure_password_123'`. This credential is written to `/etc/redis/6379.conf`. The AAP credential type `Redis Authentication Password` and credential `controller_credentials.yml` in `weqe-d92f93/modules/cache/ansible/roles/cache/aap-configuration/` are already defined to migrate this to `{{ vault_redis_password }}`. **Action**: populate `vault_redis_password` in AAP Credential Store or `ansible-vault` before first playbook run. Do not commit the plaintext value.

- **Hardcoded PostgreSQL credentials** (`fastapi_password` / `DATABASE_URL`): Defined in plaintext in `cookbooks/fastapi-tutorial/recipes/default.rb` in both the `psql` shell commands and the inline `.env` file content. The `.env` file is written with mode `0644` (world-readable). The AAP credential type `FastAPI PostgreSQL Database` and credential in `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/aap-configuration/` are already defined, mapping to `{{ vault_db_password }}` and `{{ vault_database_url }}`. **Action**: rotate the `fastapi_password` credential before migration, store in AAP/Vault, and tighten the `.env` file permissions to `0600` in the Ansible template.

- **FastAPI service running as root**: The Chef recipe creates `/etc/systemd/system/fastapi-tutorial.service` with `User=root`. This is a significant security risk. The Ansible role's `fastapi-tutorial.service.j2` template should be reviewed and updated to run under a dedicated non-root service account.

- **Self-signed SSL certificates**: All three Nginx virtual hosts use self-signed RSA-2048 certificates with a 365-day validity and a placeholder subject (`/C=US/ST=Example/O=Example Org`). These are appropriate for development but must be replaced with CA-signed certificates (Let's Encrypt or internal PKI) before any production deployment. The `ssl_certificate` community cookbook (already in the Policyfile) provides a production-ready path; alternatively, use `community.crypto` Ansible modules.

- **SSH hardening applied by nginx-multisite**: The `security` recipe disables root login and password authentication in `sshd_config`. Ensure the Ansible control node has key-based SSH access configured before running the playbook, or the playbook will lock itself out.

- **UFW firewall**: The `security` recipe enables UFW with default-deny and only allows ports 22, 80, and 443. Port 8000 (FastAPI/uvicorn) is **not** opened in the firewall. If the FastAPI service needs to be externally accessible, a UFW rule for port 8000 must be added to the `nginx_multisite` Ansible role or a new firewall task.

- **Memcached bound to `0.0.0.0`**: Memcached has no authentication and listens on all interfaces. On the target VM this is mitigated by UFW (port 11211 is not opened), but this should be explicitly documented and the bind address should be restricted to `127.0.0.1` in the Ansible role defaults if Memcached is only consumed locally.

- **Redis bound to all interfaces**: Similarly, Redis listens on `0.0.0.0:6379`. While password-protected, restricting the bind address to `127.0.0.1` in `cache_redis_default_settings` is recommended.

---

### Technical Challenges

- **Redis source-compile vs. package install**: The `redisio` cookbook compiles Redis 3.2.11 from source by default, requiring `build-essential` / `gcc`/`make` toolchain. Redis 3.2.11 reached end-of-life in 2019. The Ansible `cache` role defaults (`cache_redis_version: 3.2.11`, `cache_redis_package_install: false`) replicate this behaviour. A decision is needed on whether to continue with source-compile (preserving exact version parity) or switch to an OS package install of a current Redis version. Switching versions will require re-testing the `ruby_block` compatibility hack (now implemented as `ansible.builtin.lineinfile` removals in the Ansible role).

- **`ruby_block` post-processing hack**: The Chef recipe uses a `ruby_block` to strip deprecated directives from `/etc/redis/6379.conf` after the `redisio` cookbook generates it. This is already translated to `ansible.builtin.lineinfile` with `state: absent` in the Ansible `cache` role's `main.yml`. Verify that the Jinja2 Redis config template (`redis.conf.j2`) does not emit these directives in the first place, which would make the lineinfile cleanup redundant.

- **Chef `notify`/`subscribe` → Ansible `handlers`**: Chef's delayed notification system (e.g., `notifies :reload, 'service[nginx]', :delayed`) maps to Ansible handlers. The scaffolded roles already define handlers (`handlers/main.yml`). Verify that all notify chains are correctly represented, particularly the `systemctl daemon-reload` → `restart fastapi-tutorial` sequence in the `fastapi_tutorial` role (already handled via `ansible.builtin.meta: flush_handlers`).

- **Idempotency of `openssl req` certificate generation**: The Chef recipe uses `not_if { ::File.exist?(cert_file) && ::File.exist?(key_file) }` to skip certificate generation if files already exist. The Ansible equivalent must use `creates:` or `ansible.builtin.stat` + `when:` conditions to preserve this behaviour. The `community.crypto` modules handle this natively.

- **PostgreSQL provisioning via raw `psql` shell commands**: The Chef recipe uses `execute` resources with `sudo -u postgres psql -c "..." || true` for idempotency. The Ansible role replicates this with `ansible.builtin.shell` + `changed_when: false`. For production, replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` collection for proper idempotency and error handling.

- **`lineinfile` custom resource in nginx-multisite**: The cookbook defines a custom `resources/lineinfile.rb` resource. Review whether this is used in any recipe (it does not appear to be called in the recipes reviewed); if unused, no migration action is needed.

- **Vagrant/libvirt → Ansible inventory**: The current workflow is entirely Vagrant-driven. The Ansible migration requires defining a proper inventory (static or dynamic) with the target host (`192.168.121.10` or hostname `chef-nginx`), SSH credentials, and `become: true` for privilege escalation. The `vagrant-provision.sh` script will be replaced by an Ansible playbook.

- **Cross-platform support**: Chef `metadata.rb` declares support for both Ubuntu ≥ 18.04 and CentOS ≥ 7.0, but the Vagrant target is Fedora 42. The Ansible roles must handle package name differences (e.g., `libpq-dev` on Debian vs. `postgresql-devel` on RHEL, `python3-pip` availability, `www-data` vs. `nginx` web user) using `ansible_os_family` conditionals or role variables.

---

### Migration Order

1. **nginx-multisite** *(Priority 1 — low risk, self-contained, no external credential dependencies)*
   - No hardcoded secrets. All configuration is attribute-driven and maps directly to Ansible `defaults/main.yml` variables already scaffolded. The Ansible role is the most complete of the three. Validate with Molecule before proceeding.
   - Prerequisite: Confirm `community.crypto` collection availability for SSL certificate generation, or retain `openssl` shell command approach.

2. **fastapi-tutorial** *(Priority 2 — moderate complexity, credential migration required)*
   - Depends on PostgreSQL being available (installed by the recipe itself). The Ansible role is well-scaffolded. Main actions: populate `vault_db_password` and `vault_database_url` in AAP/Vault, fix the service user (root → dedicated account), tighten `.env` file permissions to `0600`, and replace raw `psql` shell commands with `community.postgresql` modules.
   - Prerequisite: AAP Credential Store or `ansible-vault` configured with PostgreSQL credentials.

3. **cache** *(Priority 3 — highest complexity, credential migration + Redis version decision required)*
   - Most complex due to the `redisio` source-compile workflow, SELinux considerations on Fedora 42, PAM ulimit configuration, and the Redis version EOL issue. Resolve the source-compile vs. package-install decision first. Populate `vault_redis_password` in AAP/Vault. Validate the `lineinfile` compatibility-fix tasks against the actual generated config.
   - Prerequisite: Redis version decision, AAP Credential Store configured with Redis password, SELinux policy review for custom binary paths.

---

### Assumptions

1. **Target OS is Fedora 42** (from `Vagrantfile`), but the Chef cookbooks were written for Ubuntu/CentOS. The Ansible roles must be validated on Fedora 42 specifically — package names, service names, and paths may differ from what the Chef cookbook attributes assume (e.g., `www-data` user does not exist on Fedora; the web user is `nginx`).

2. **Chef Solo workflow is the only provisioner** — there is no Chef Server, no data bags in use (the `redisio` cookbook supports data bag credential lookup but it is not configured here), and no Chef environments or roles beyond what is in `solo.json`.

3. **The `ssl_certificate` community cookbook** is listed in `Policyfile.rb` but is not called by any local cookbook recipe. It is assumed to be an unused/vestigial dependency and does not require direct migration.

4. **The `nginx` community cookbook** (~> 12.0) is similarly listed in `Policyfile.rb` but not called by any local recipe. The `nginx-multisite` cookbook installs Nginx directly via the OS package manager. No migration action is required for this dependency.

5. **Redis 3.2.11 source-compile** is the current behaviour. It is assumed that the migration team will decide whether to upgrade Redis to a supported version (7.x) or preserve the exact version. This plan assumes the decision has not yet been made and flags it as a required pre-migration decision.

6. **The `weqe-d92f93/modules/` Ansible roles are partially scaffolded** (task files, defaults, templates, handlers, Molecule tests, and AAP credential definitions exist) but are not yet complete or validated. They represent migration work-in-progress, not finished artifacts.

7. **The `123-fc2c2f/modules/nginx/` Ansible role** is a standalone, independent artifact unrelated to the Chef cookbooks in this repository. It is assumed to be complete and requires no further migration work.

8. **Molecule test infrastructure** is scaffolded for all three Ansible roles (`molecule/default/` directories with `converge.yml`, `verify.yml`, `create.yml`, `destroy.yml`, `molecule.yml`). It is assumed that a container or VM driver is available in the CI environment to run these tests.

9. **AAP (Ansible Automation Platform)** is the target execution environment, as evidenced by the `aap-configuration/` directories with `controller_credential_types.yml` and `controller_credentials.yml`. It is assumed that an AAP instance is available and that the `infra.controller_configuration` collection is installed for applying these credential definitions.

10. **No DNS infrastructure** is configured for `*.cluster.local` hostnames. The `Vagrantfile` has the `/etc/hosts` provisioning block commented out. It is assumed that DNS or `/etc/hosts` entries will be managed separately and are not part of the Ansible role scope.

11. **The FastAPI application source** (`https://github.com/dibanez/fastapi_tutorial.git`) is a public GitHub repository. It is assumed this repository remains accessible and that the `main` branch is stable. If the target environment has no internet access, a local mirror or artifact repository must be configured.

12. **Privilege escalation**: All Chef recipes run as root (Chef Solo default). The Ansible playbook will require `become: true` for all roles. It is assumed that the Ansible SSH user has passwordless sudo or that `become_password` is configured.
