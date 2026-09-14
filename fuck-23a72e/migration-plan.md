# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions an Nginx multisite web server with caching services and a FastAPI application backend. The stack is composed of three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) and five external Chef Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`). The environment is currently validated via Vagrant on a Fedora 42 / libvirt VM.

**Migration scope**: 3 local cookbooks → 3 Ansible roles (plus supporting playbook and inventory scaffolding). External cookbook dependencies are replaced by native Ansible modules (`ansible.builtin.package`, `community.general`, `ansible.posix`), eliminating the Chef Supermarket dependency chain entirely.

**Complexity**: Medium. The cookbooks are well-structured and single-purpose. The primary challenges are: replacing the Chef `redisio` community cookbook (which includes a known config-patching hack), migrating self-signed SSL certificate generation logic, and safely externalising hardcoded credentials that currently live in recipe source code.

**Estimated timeline**: 2–3 sprints (4–6 weeks) for a single engineer, or 1–2 sprints with two engineers working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that require individual migration to Ansible roles, plus a set of infrastructure/orchestration files that need to be replaced with Ansible equivalents.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the repository tree and file reads. No paths have been inferred or invented.

---

- **nginx-multisite**:
  - Description: Nginx multisite web server with SSL termination, security hardening, and per-vhost configuration. Orchestrates four sub-recipes: `security` (fail2ban, UFW firewall, SSH hardening, kernel sysctl tuning), `nginx` (package install, main `nginx.conf`, security headers config), `ssl` (self-signed certificate generation via `openssl req` for each vhost), and `sites` (per-vhost `sites-available` config + `sites-enabled` symlinks). Serves three SSL-enabled virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, each with its own document root and static `index.html`.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: ERB-templated `nginx.conf` and per-site `site.conf`, TLSv1.2/1.3-only SSL with HSTS and full security header suite (X-Frame-Options, CSP, X-Content-Type-Options), fail2ban with nginx-specific jails, UFW default-deny with SSH/HTTP/HTTPS allow rules, sysctl kernel hardening (IP spoofing, ICMP redirect, SYN flood protection), SSH root login and password authentication disabled, `lineinfile` custom resource.

- **cache**:
  - Description: Caching layer that installs and configures both Memcached and Redis on the same host. Delegates Memcached setup to the `memcached` community cookbook and Redis to `redisio`, then applies a post-install Ruby block hack to strip incompatible directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` before enabling the service.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached via community cookbook, Redis 6379 with password authentication (`requirepass`), post-install config-file patching workaround for `redisio` compatibility, `/var/log/redis` directory management, `redisio::enable` service activation.

- **fastapi-tutorial**:
  - Description: Full-stack Python application provisioner that deploys a FastAPI application from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, `main` branch) with a PostgreSQL backend. Installs system packages, creates a Python virtual environment, installs pip dependencies, configures PostgreSQL (service + database + user), writes a `.env` file with database credentials, and installs a systemd unit file for the `uvicorn` application server.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3 venv at `/opt/fastapi-tutorial/venv`, PostgreSQL database `fastapi_db` with user `fastapi`, uvicorn ASGI server on port 8000 managed by systemd, `.env` file with `DATABASE_URL`, git-based deployment (`action :sync`), `systemctl daemon-reload` on unit file change.

---

### Infrastructure Files

- `Policyfile.rb`: Chef Policyfile defining the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all cookbook version constraints. **Migration action**: Replace with an Ansible playbook (`site.yml`) that imports the three roles in the same order.
- `Policyfile.lock.json`: Locked dependency graph with exact versions for all 8 cookbooks (3 local + 5 external). **Migration action**: Reference document for identifying exact external cookbook versions being replaced; no direct Ansible equivalent needed.
- `Berksfile`: Berkshelf dependency file listing local cookbook paths and external Supermarket sources. **Migration action**: Replace with `requirements.yml` for any needed Ansible Galaxy collections (`community.general`, `ansible.posix`).
- `solo.json`: Chef Solo node attributes (site definitions, SSL paths, security flags). **Migration action**: Migrate to Ansible `group_vars/all.yml` or role `defaults/main.yml`; the site list maps directly to an Ansible variable dictionary.
- `solo.rb`: Chef Solo configuration (cache path, cookbook path, log level). **Migration action**: No direct equivalent; superseded by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. **Migration action**: Retain for local development testing; replace the `shell` provisioner block with an `ansible_local` or `ansible` provisioner pointing to the new `site.yml` playbook.
- `vagrant-provision.sh`: Shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. **Migration action**: Replace entirely with Ansible provisioner in Vagrantfile; script becomes obsolete post-migration.

---

### Target Details

- **Operating System**: Ubuntu 18.04+ / CentOS 7+ per `metadata.rb` `supports` declarations. The Vagrant development environment uses **Fedora 42** (`generic/fedora42`). The nginx.conf template uses `www-data` as the worker user (Debian/Ubuntu convention), and the security recipe references `/var/log/auth.log` (Debian/Ubuntu path). Primary target is **Debian/Ubuntu family**; CentOS/RHEL support is declared but not fully exercised in templates.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`.
- **Cloud Platform**: Not specified. No cloud-provider-specific configurations, metadata endpoints, or SDK references are present.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` to install the OS-packaged nginx, plus `ansible.builtin.template` for `nginx.conf` and per-site configs. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) map directly to Jinja2 (`.j2`) templates with minor syntax changes.
- **memcached (6.1.0)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (install `memcached`) + `ansible.builtin.service` (enable/start). The community cookbook provides minimal abstraction; a short Ansible task file is sufficient.
- **redisio (7.2.4)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (install `redis-server`) + `ansible.builtin.template` for `/etc/redis/6379.conf` + `ansible.builtin.service`. The existing post-install config-patching hack in `cache::default` can be eliminated entirely by writing a clean Jinja2 Redis config template, removing the technical debt.
- **ssl_certificate (2.1.0)** — Chef Supermarket community cookbook: Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` Ansible modules (from `community.crypto` collection) for self-signed certificate generation. This is a direct functional equivalent and removes the shell `openssl req` execute resource.
- **selinux (6.2.4)** — Transitive dependency of `redisio`: Replace with `ansible.posix.selinux` module if SELinux management is required on RHEL targets. Not needed for Ubuntu/Debian targets.
- **fail2ban / UFW** — Managed inline in `nginx-multisite::security`: Replace with `ansible.builtin.package`, `ansible.builtin.template`, `ansible.builtin.service`, and `community.general.ufw` module. The `community.general.ufw` module provides idempotent UFW rule management, replacing the `execute` resources with `not_if` guards.

### Security Considerations

- **Hardcoded Redis password**: The Redis `requirepass` value `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb`. **Migration action**: Move to an Ansible Vault-encrypted variable (`vault_redis_password`) referenced in `group_vars/all.yml`. Do not commit the plaintext value to the Ansible repository.
- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial` recipe hardcodes both the database username (`fastapi`) and password (`fastapi_password`) in the recipe source and writes them in plaintext to `/opt/fastapi-tutorial/.env` (mode `0644`, owned by root). **Migration action**: Encrypt credentials with Ansible Vault; set `.env` file mode to `0600` and restrict ownership to the application service user (not root).
- **FastAPI service running as root**: The systemd unit file sets `User=root`. **Migration action**: Create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed SSL certificates**: All three vhosts use self-signed certificates generated at provision time via `openssl req`. Certificates are valid for 365 days. **Migration action**: Retain self-signed generation for development/staging using `community.crypto`; document a path to Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA for production.
- **SSL private key permissions**: The `ssl.rb` recipe sets private key permissions to `640` with `root:ssl-cert` ownership. This is correct and should be preserved in the Ansible equivalent.
- **SSH hardening**: Root login and password authentication are disabled via `sed` on `/etc/ssh/sshd_config`. **Migration action**: Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`; use `validate` parameter to check sshd config syntax before applying.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template disables IPv6, enables SYN cookie protection, disables ICMP redirects and source routing. **Migration action**: Use `ansible.posix.sysctl` module for each parameter to ensure idempotency, rather than a raw template drop.
- **`.env` file with DATABASE_URL**: Written to `/opt/fastapi-tutorial/.env` with plaintext `postgresql://fastapi:fastapi_password@localhost/fastapi_db`. **Migration action**: Generate via Ansible Vault-backed template; restrict file permissions to `0600`.
- **Vault/secrets summary by cookbook**:
  - `cache`: Redis `requirepass` — hardcoded string in recipe source.
  - `fastapi-tutorial`: PostgreSQL user password — hardcoded in recipe source and written to `.env`; `DATABASE_URL` in `.env` file.
  - `nginx-multisite`: No application secrets; SSL private keys generated at runtime.

### Technical Challenges

- **`redisio` config-patching hack**: The `cache` cookbook uses a `ruby_block` to post-process the Redis config file generated by `redisio`, stripping directives that cause the older cookbook to emit invalid Redis 6+ configuration. This is a code smell that indicates the `redisio 7.2.4` cookbook is not fully compatible with the Redis version on the target OS. **Mitigation**: Write a clean Jinja2 Redis config template in the Ansible role, bypassing the community cookbook entirely and eliminating the hack.
- **ERB → Jinja2 template conversion**: Five ERB templates need conversion (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`). The `site.conf.erb` template uses conditional blocks (`<% if @ssl_enabled %>`) and variable interpolation (`<%= @server_name %>`) that map cleanly to Jinja2 `{% if %}` and `{{ }}` syntax. **Mitigation**: Straightforward one-to-one conversion; no complex Ruby logic is embedded in the templates.
- **Chef node attributes → Ansible variables**: The `solo.json` node attributes (site dictionary, SSL paths, security flags) and `attributes/default.rb` defaults need to be mapped to Ansible `group_vars` or role `defaults/main.yml`. The nested attribute structure (`node['nginx']['sites']`) maps to a YAML dictionary. **Mitigation**: Direct structural translation; use `group_vars/all.yml` for shared values and role defaults for per-role defaults.
- **`lineinfile` custom resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` defines a custom Chef resource. **Mitigation**: Replace with `ansible.builtin.lineinfile`, which provides the same functionality natively.
- **Idempotency of `execute` resources**: Several `execute` resources in `security.rb` use `not_if` shell guards (e.g., `ufw status | grep -q`). These are functional but fragile. **Mitigation**: Replace with purpose-built Ansible modules (`community.general.ufw`, `ansible.builtin.lineinfile`) that are natively idempotent.
- **Git-based application deployment**: The `fastapi-tutorial` cookbook uses `git` resource with `action :sync` to deploy from a public GitHub repository. **Mitigation**: Use `ansible.builtin.git` module with `update: yes`; consider pinning to a specific commit SHA rather than the `main` branch for reproducibility.
- **Multi-OS support gap**: `metadata.rb` declares support for both Ubuntu ≥18.04 and CentOS ≥7, but the templates and recipes use Ubuntu-specific paths (`/var/log/auth.log`, `www-data` user, `ufw`, `apt`). CentOS equivalents (`/var/log/secure`, `nginx` user, `firewalld`, `yum`) are not implemented. **Mitigation**: Decide on a primary target OS for the Ansible migration; use `ansible_facts['os_family']` conditionals only if multi-OS support is genuinely required.
- **Vagrant development environment**: The `Vagrantfile` uses a shell provisioner (`vagrant-provision.sh`) that installs Chef at runtime. **Mitigation**: Replace the shell provisioner with `config.vm.provision "ansible_local"` pointing to the new `site.yml` playbook, keeping the same VM definition (Fedora 42, libvirt, same network/port-forward settings).

### Migration Order

1. **`nginx-multisite`** — Highest value, self-contained, no external service dependencies at the OS level. Establishes the Ansible role structure, Jinja2 template patterns, and variable conventions that the other roles will follow. The security sub-recipe (fail2ban, UFW, sysctl, SSH hardening) should be extracted into a dedicated `security` role for reusability.
2. **`cache`** — Medium complexity. Depends on Redis and Memcached packages only; no inter-cookbook dependencies with `nginx-multisite` or `fastapi-tutorial`. Migrate after `nginx-multisite` so the role/variable conventions are established. Eliminates the `redisio` hack as part of migration.
3. **`fastapi-tutorial`** — Highest complexity due to hardcoded credentials, root service user, git-based deployment, and PostgreSQL provisioning. Migrate last; requires Ansible Vault setup to be in place before credentials can be safely migrated. Coordinate with application team to confirm the target GitHub repository and branch strategy.

### Assumptions

1. **Target OS is Ubuntu/Debian**: The templates and recipes are written for Ubuntu conventions (`www-data`, `ufw`, `apt`, `/var/log/auth.log`). The CentOS support declared in `metadata.rb` is assumed to be aspirational and not actively tested. The migration plan targets Ubuntu 22.04 LTS (Jammy) unless the team specifies otherwise.
2. **Chef Solo, not Chef Server**: The repository uses `chef-solo` with `solo.rb`/`solo.json` and no Chef Server references. There is no Ohai data bag, encrypted data bag, or Chef Vault usage — secrets are currently stored as plaintext in recipe source code.
3. **Self-signed certificates are acceptable for the target environment**: The SSL recipe generates self-signed certificates. It is assumed this is intentional for a development/staging environment. Production certificate management strategy (Let's Encrypt, internal CA, or pre-provisioned certs) is out of scope for this migration and must be decided separately.
4. **The `redisio` config-patching hack is a known issue**: The `ruby_block "fix_redis_config"` in `cache::default.rb` is treated as technical debt to be eliminated during migration, not replicated in Ansible.
5. **The FastAPI application repository is publicly accessible**: The `git` resource clones from `https://github.com/dibanez/fastapi_tutorial.git`. It is assumed this repository remains public and accessible from the target host. If it moves to a private repository, SSH key or token management will need to be added to the Ansible role.
6. **Ansible Vault will be adopted for secrets management**: The migration assumes the team will adopt Ansible Vault to replace the plaintext credentials currently in recipe source. The vault password management strategy (vault password file, `--ask-vault-pass`, or a secrets manager integration) is a team decision outside this plan's scope.
7. **libvirt/KVM is the only VM provider in use**: The `Vagrantfile` only configures a `libvirt` provider block. No VirtualBox or VMware provider configuration is present. The Ansible migration retains this assumption.
8. **The `ssl_certificate` community cookbook is used for self-signed cert generation only**: The `Policyfile.rb` includes `ssl_certificate ~> 2.1` but the `nginx-multisite` cookbook does not call `include_recipe 'ssl_certificate'` — it generates certificates directly via `openssl req` execute resources. The community cookbook dependency appears to be unused in the local cookbooks and can be dropped entirely.
9. **Port 8000 (uvicorn) is intentionally not exposed via Nginx reverse proxy**: The `fastapi-tutorial` cookbook starts uvicorn on `0.0.0.0:8000` but no Nginx upstream/proxy_pass configuration exists in `nginx-multisite`. It is assumed this is intentional (direct access) or a gap to be addressed post-migration.
10. **The `modules/nginx/ansible/roles/nginx` directory is a pre-existing partial migration artifact**: The `123-fc2c2f/` directory contains an already-migrated Ansible role for a generic Nginx role (from a prior migration effort) and a `migration-plan-nginx.md`. This role is distinct from the `nginx-multisite` cookbook and should be reviewed for reuse or consolidation during the migration of the `nginx-multisite` cookbook.
