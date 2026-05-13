# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is currently developed and tested locally via Vagrant on a **Fedora 42 / libvirt** VM, with cookbook support declared for Ubuntu 18.04+ and CentOS 7+.

The migration consists of **3 local cookbooks** and **5 external Chef Supermarket dependencies**, all of which have well-established Ansible equivalents. The cookbooks follow standard Chef patterns (package/template/service resources, attribute-driven configuration, ERB templates) with no Chef Server, encrypted data bags, or Chef Vault usage, which significantly reduces migration risk.

**Overall complexity: Medium.**
**Estimated timeline: 3–4 weeks** for a complete migration including testing, broken down as:
- Week 1: `nginx-multisite` role (Nginx, SSL, security hardening)
- Week 2: `cache` role (Memcached + Redis)
- Week 3: `fastapi-tutorial` role (Python, PostgreSQL, systemd service)
- Week 4: Integration testing, inventory/variable cleanup, documentation

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation per vhost, HTTP-to-HTTPS redirect, security response headers (HSTS, X-Frame-Options, CSP, X-XSS-Protection), gzip compression, and a global Nginx security hardening config (rate limiting zones, buffer overflow protections, timeout tuning, TLSv1.2/1.3 enforcement)
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
      - Attribute-driven multi-site loop (`node['nginx']['sites']`) generating one `sites-available/` config and symlink per vhost
      - Per-site `openssl req` self-signed certificate generation (RSA 2048, 365-day validity) with idempotency guard
      - `ssl-cert` group creation; private key directory restricted to `root:ssl-cert 0710`
      - Dedicated `security.conf` snippet: `server_tokens off`, rate-limit zones, client buffer limits, global SSL session cache
      - fail2ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`
      - UFW firewall: default-deny, allow SSH/HTTP/HTTPS via idempotent `execute` guards
      - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` on `/etc/ssh/sshd_config`
      - Kernel hardening via `/etc/sysctl.d/99-security.conf`: IP spoofing protection, ICMP redirect suppression, SYN-cookie flood protection, IPv6 disable
      - Custom `lineinfile` Chef resource (reimplements Ansible's native `lineinfile` module)
      - Static HTML content files for each vhost (`ci/index.html`, `status/index.html`, `test/index.html`)

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication, a dedicated log directory, and a post-install config-file sanitisation workaround
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
      - Delegates Memcached installation and service management entirely to the `memcached ~> 6.0` community cookbook
      - Configures a single Redis instance on port 6379 with `requirepass redis_secure_password_123` (hardcoded plaintext credential)
      - Creates `/var/log/redis` owned by `redis:redis 0755`
      - Delegates Redis installation to `redisio ~> 7.2.4` and enables it via `redisio::enable`
      - Contains a `ruby_block "fix_redis_config"` hack that post-processes `/etc/redis/6379.conf` to strip deprecated `replica-*` directives incompatible with the installed Redis version — this logic must be replicated in Ansible

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, with a Python 3 virtual environment, PostgreSQL database and user provisioning, a `.env` file containing the database DSN, and a systemd unit file for process supervision
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
      - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
      - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using Chef `git` resource with `:sync` action
      - Creates venv at `/opt/fastapi-tutorial/venv` and installs `requirements.txt` via pip
      - Starts and enables `postgresql` service
      - Provisions PostgreSQL role `fastapi` with password `fastapi_password` (hardcoded plaintext) and database `fastapi_db`
      - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plaintext credential in a world-readable file, mode `0644`)
      - Writes and enables a systemd unit `fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as `root` (privilege concern)
      - Calls `systemctl daemon-reload` via `execute` resource

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest listing all local and Supermarket cookbook sources with version constraints. Not needed in Ansible; replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and version constraints. Replaced by Ansible playbook `hosts`/`roles` declarations.
- `Policyfile.lock.json`: Locked dependency graph including transitive dependencies (`selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the authoritative version reference during migration; no direct Ansible equivalent (use `requirements.yml` with pinned versions).
- `solo.json`: Chef Solo node JSON providing runtime attributes: three vhost definitions with `document_root` and `ssl_enabled`, SSL certificate/key paths, and security flags (`fail2ban`, `ufw`, `ssh`). Migrates to Ansible `group_vars` or `host_vars` YAML files.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks`. No Ansible equivalent needed.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42`, libvirt provider (2 vCPU / 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. Migrates to an Ansible-compatible `Vagrantfile` using the `ansible` provisioner or a standalone inventory file.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf, vendors cookbooks, and runs `chef-solo`. Replaced by `vagrant` Ansible provisioner or a simple `ansible-playbook` invocation.

---

### Target Details

- **Operating System**: Fedora 42 (active Vagrant development target, libvirt box `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The `security.rb` recipe uses `ufw` and references `/var/log/auth.log`, which are Debian/Ubuntu conventions — these will require conditional handling for RHEL/Fedora targets (use `firewalld` instead of `ufw`; log path differs).
- **Virtual Machine Technology**: libvirt / KVM (explicitly set in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0, locked 12.3.1)**: The community `nginx` cookbook handles installation and basic service management. Replace with the `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` modules, or adopt the `nginxinc.nginx` Ansible Galaxy role. All ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) translate directly to Jinja2.
- **memcached (~> 6.0, locked 6.1.0)**: Thin wrapper around package/service. Replace with `ansible.builtin.package` (package name `memcached`) and `ansible.builtin.service`. No complex configuration is applied beyond defaults.
- **redisio (~> 7.2.4, locked 7.2.4)**: Manages Redis installation, per-instance config file generation, and service enablement. Replace with `ansible.builtin.package` (package name `redis` or `redis-server`), a Jinja2 template for `/etc/redis/6379.conf`, and `ansible.builtin.service`. The config-file sanitisation hack (stripping deprecated `replica-*` keys) must be replicated using `ansible.builtin.lineinfile` with `state: absent` or a `blockinfile`/template approach.
- **ssl_certificate (~> 2.1, locked 2.1.0)**: Used transitively (declared in `Policyfile.rb` but commented out in `Berksfile`). The `ssl.rb` recipe implements its own `openssl req` certificate generation directly. Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection.
- **selinux (6.2.4)**: Pulled in transitively by `redisio`. On Fedora/RHEL targets, use `ansible.posix.selinux` and `community.general.sefcontext` modules as needed. On Ubuntu targets, SELinux is not applicable.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`): This plaintext credential is embedded directly in the recipe source. **Must be migrated to Ansible Vault** (`ansible-vault encrypt_string`). Detected credential count: **1 plaintext password in source code**.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env`): Two occurrences — the `psql` provisioning command and the `.env` file content. **Both must be migrated to Ansible Vault**. The `.env` file permissions should be tightened from `0644` to `0600`. Detected credential count: **1 plaintext password (used in 2 locations)**.
- **`.env` file world-readable**: `/opt/fastapi-tutorial/.env` is written with mode `0644`, exposing `DATABASE_URL` (including password) to all local users. The Ansible task must set `mode: '0600'` and restrict ownership to the service account.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant privilege escalation risk. The Ansible migration should create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed TLS certificates**: Generated via `openssl req` for development use. The Ansible migration should use `community.crypto` modules for idempotent generation and document a clear path to replace with CA-signed or Let's Encrypt certificates for production.
- **SSH hardening** (`PermitRootLogin no`, `PasswordAuthentication no`): Currently applied via `sed` on `/etc/ssh/sshd_config`. Migrate using `ansible.builtin.lineinfile` or the `ansible.builtin.template` module for the full sshd_config. Ensure the Ansible control connection is key-based before applying, to avoid lockout.
- **UFW firewall rules**: Applied via raw `execute` resources with `not_if` guards. Migrate using the `community.general.ufw` module on Ubuntu/Debian targets. On Fedora/RHEL, use `ansible.posix.firewalld` instead — this is a **platform-conditional** requirement.
- **fail2ban configuration**: The `jail.local` template is fully self-contained and translates directly to an Ansible template task. Use `ansible.builtin.template` + `ansible.builtin.service`.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template maps directly to repeated `ansible.posix.sysctl` tasks or a single template deploy to `/etc/sysctl.d/99-security.conf` followed by `sysctl -p`.
- **No Chef Vault / encrypted data bags detected**: Zero encrypted data bag references found across all cookbooks. All secrets are currently plaintext in recipe source — this is the primary secrets management risk to address before or during migration.
- **SSL private key directory permissions**: `/etc/ssl/private` is set to `root:ssl-cert 0710`. The Ansible role must replicate the `ssl-cert` group creation and directory ACL.

---

### Technical Challenges

- **Platform duality (Debian vs. RHEL)**: The Vagrantfile targets Fedora 42 (DNF/RPM), but `metadata.rb` declares Ubuntu and CentOS support. The `security.rb` recipe uses `ufw` and references `/var/log/auth.log` — both Debian-specific. The Ansible roles must use `ansible_os_family` conditionals to select `ufw` vs. `firewalld`, correct log paths, and correct package names (e.g., `redis-server` on Debian vs. `redis` on RHEL). This is the most pervasive cross-cutting concern.
- **Redis config post-processing hack**: The `ruby_block "fix_redis_config"` in `cache/recipes/default.rb` strips deprecated `replica-*` directives from the generated Redis config file. This implies the `redisio` cookbook generates a config with directives unsupported by the installed Redis version. In Ansible, this should be solved by owning the full Redis config template rather than patching a generated file, using `ansible.builtin.template` to render `/etc/redis/6379.conf` directly and omitting the deprecated keys.
- **Attribute precedence and override layering**: `solo.json` overrides `document_root` paths relative to `attributes/default.rb` (e.g., `/var/www/test.cluster.local` vs. `/opt/server/test`). The Ansible migration must reconcile which path is canonical and define it clearly in `group_vars`. The `solo.json` values appear to be the intended runtime values.
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements line-in-file editing with backup support. This maps directly to Ansible's built-in `ansible.builtin.lineinfile` module — no custom work needed, but the backup behaviour (timestamped `.backup.<epoch>` files) differs from Ansible's `backup: yes` (single `.bak` file).
- **Git-based application deployment with `:sync` action**: The `git` resource in `fastapi-tutorial` uses `:sync`, which pulls updates on every Chef run. The Ansible `ansible.builtin.git` module equivalent is `update: yes` — ensure this is intentional and does not overwrite local changes in production.
- **`pip install -r requirements.txt` without version pinning**: The recipe runs pip install on every convergence without checking if dependencies are already satisfied. In Ansible, use `ansible.builtin.pip` with `state: present` and consider pinning the `requirements.txt` or using a `virtualenv_command`.
- **systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd before starting the service. In Ansible, use a `handler` for `systemctl daemon-reload` triggered by the unit file template task, with `listen` to ensure correct ordering.
- **Idempotency of PostgreSQL provisioning**: The recipe uses `|| true` to suppress errors on duplicate user/database creation. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **`www-data` user assumption**: `nginx.rb` sets document root ownership to `www-data:www-data`. On Fedora/RHEL, the Nginx worker user is `nginx`. The Ansible role must conditionally set the correct user/group based on OS family.

---

### Migration Order

The following order minimises dependency risk and allows incremental validation at each stage:

1. **`nginx-multisite` → Ansible role `nginx_multisite`** *(Week 1 — Medium complexity, no upstream service dependencies)*
   - Translate `nginx.conf.erb` and `security.conf.erb` to Jinja2 templates
   - Implement per-vhost `site.conf.erb` → Jinja2 loop over `nginx_sites` variable
   - Replace `openssl req` execute resource with `community.crypto` tasks
   - Implement `ssl-cert` group, directory permissions, and certificate idempotency
   - Migrate `security.rb` (fail2ban, UFW/firewalld, SSH hardening, sysctl) as a sub-role or tagged tasks
   - Copy static HTML files using `ansible.builtin.copy`
   - Validate with Vagrant + `ansible-playbook --check`

2. **`cache` → Ansible role `cache`** *(Week 2 — Low complexity, standalone services)*
   - Implement Memcached via `ansible.builtin.package` + `ansible.builtin.service`
   - Own the full Redis config template; eliminate the `fix_redis_config` hack
   - Store `redis_password` in Ansible Vault
   - Create `/var/log/redis` directory with correct ownership
   - Validate Redis AUTH with `redis-cli -a` in a smoke-test task

3. **`fastapi-tutorial` → Ansible role `fastapi_tutorial`** *(Week 3 — High complexity, depends on PostgreSQL)*
   - Create dedicated `fastapi` system user; remove `User=root` from systemd unit
   - Install system packages (conditionally handle `libpq-dev` vs. `postgresql-libs`)
   - Clone repository with `ansible.builtin.git`
   - Create venv and install pip dependencies with `ansible.builtin.pip`
   - Provision PostgreSQL with `community.postgresql` collection modules
   - Store `fastapi_db_password` in Ansible Vault; render `.env` with mode `0600`
   - Deploy systemd unit via `ansible.builtin.template` + handler for daemon-reload
   - Validate with HTTP health check against `http://localhost:8000`

4. **Integration & Cleanup** *(Week 4)*
   - Write top-level `site.yml` playbook combining all three roles
   - Define `group_vars/all.yml` with non-secret variables; `group_vars/all/vault.yml` for secrets
   - Update `Vagrantfile` to use `ansible` provisioner instead of `vagrant-provision.sh`
   - Write `requirements.yml` for Galaxy collections (`community.crypto`, `community.postgresql`, `ansible.posix`, `community.general`, `nginxinc.nginx` if adopted)
   - Run full idempotency test (apply twice, assert no changes on second run)
   - Document manual steps (DNS `/etc/hosts` entries, certificate replacement for production)

---

### Assumptions

1. **Target OS for Ansible**: Fedora 42 is the primary target based on the Vagrantfile. Ubuntu/CentOS support declared in `metadata.rb` is treated as a secondary goal; platform-conditional tasks will be added but not primary test targets unless confirmed by the team.
2. **Self-signed certificates are development-only**: It is assumed that production deployments will replace the self-signed certificates with CA-signed or Let's Encrypt certificates. The Ansible role will generate self-signed certs by default with a clearly documented variable (`nginx_ssl_self_signed: true`) to switch behaviour.
3. **`solo.json` document root paths are canonical**: The paths in `solo.json` (`/var/www/test.cluster.local`, etc.) override the cookbook attribute defaults (`/opt/server/test`, etc.). The Ansible `group_vars` will use the `solo.json` values as the baseline.
4. **No Chef Server or Chef Vault in use**: The entire stack runs via `chef-solo` with no Chef Server, encrypted data bags, or Chef Vault. There are no server-side secrets to migrate from Chef infrastructure — all secrets are currently plaintext in source and must be vaulted in Ansible from scratch.
5. **Redis single-instance, no clustering**: The `redisio` configuration defines a single Redis instance on port 6379. No Sentinel or Cluster configuration is present. The Ansible role will mirror this single-instance setup.
6. **FastAPI GitHub repository remains publicly accessible**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git`. It is assumed this repository will remain available and that `main` is a stable branch. If the repository becomes private, the Ansible role will need SSH key or token-based authentication.
7. **PostgreSQL version is OS-default**: No specific PostgreSQL version is pinned in the recipe. The Ansible role will install the distribution-default PostgreSQL package. If a specific version is required, this must be clarified before migration.
8. **`www-data` vs. `nginx` user**: The `nginx.rb` recipe hardcodes `www-data` as the document root owner. On Fedora, the correct user is `nginx`. The Ansible role will use `{{ nginx_user }}` defaulting to `nginx` on RHEL-family and `www-data` on Debian-family.
9. **UFW is not available on Fedora**: The `security.rb` recipe installs and configures `ufw`, which is a Debian/Ubuntu tool. On Fedora 42, `firewalld` is the native firewall manager. The Ansible security role will use `ansible_os_family == 'Debian'` to select `community.general.ufw` vs. `ansible.posix.firewalld`.
10. **The `lineinfile` custom Chef resource is fully replaced by Ansible built-ins**: The custom resource in `cookbooks/nginx-multisite/resources/lineinfile.rb` provides no functionality beyond what `ansible.builtin.lineinfile` natively offers. No custom Ansible module is required.
11. **Vagrant is retained for local development**: The `Vagrantfile` will be updated to use the Ansible provisioner rather than being replaced, preserving the existing local development workflow.
12. **Backup behaviour of the custom `lineinfile` resource is non-critical**: The Chef resource creates timestamped backup files (`.backup.<epoch>`). Ansible's `backup: yes` creates a single `.bak` file. This behavioural difference is assumed to be acceptable.
