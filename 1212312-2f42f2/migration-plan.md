# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Chef Supermarket dependencies**, orchestrated via a `Policyfile.rb` and tested locally with Vagrant on a Fedora 42 / libvirt VM.

The overall migration complexity is **moderate**. The cookbooks are well-scoped, self-contained, and follow standard Chef patterns. The primary challenges are: replacing Chef community cookbooks (`nginx`, `memcached`, `redisio`) with native Ansible modules, migrating a custom `lineinfile` LWRP to the built-in `ansible.builtin.lineinfile` module, and safely handling the several hardcoded credentials found in the source recipes.

**Estimated migration timeline: 5–8 engineer-days** for a single experienced Ansible practitioner, or 3–5 days with two engineers working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that require individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server configured with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation via OpenSSL, HTTP→HTTPS redirect, security hardening via a dedicated `security.conf`, UFW firewall rules, Fail2Ban intrusion prevention with four active jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch), kernel-level network hardening via `sysctl`, and SSH hardening (root login disabled, password authentication disabled).
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Multi-recipe structure (default → security → nginx → ssl → sites), ERB-templated `nginx.conf` and per-site `site.conf`, custom `lineinfile` LWRP resource, per-site static `index.html` content files, TLSv1.2/1.3-only cipher suite, HSTS and full security header set (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP, Referrer-Policy), rate-limiting zones, attribute-driven site inventory.

- **cache**:
  - Description: Dual caching layer provisioning Memcached (via the `memcached` community cookbook) and Redis (via the `redisio` community cookbook) with password authentication enabled. Includes a `ruby_block` workaround to strip deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the `redisio` 7.2.4 cookbook writes but the installed Redis version rejects.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Redis listening on port 6379 with `requirepass` authentication, dedicated `/var/log/redis` directory, Memcached default configuration, post-install config-file patching hack to ensure Redis starts cleanly.

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation (Python 3, pip, venv, git, PostgreSQL client/server), Git repository clone from GitHub (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`), Python virtual environment creation, pip dependency installation, PostgreSQL service enablement, database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation for the `uvicorn` application server.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Idempotent venv creation (`creates` guard), PostgreSQL user `fastapi` with hardcoded password, database `fastapi_db`, `DATABASE_URL` written to `.env` file, uvicorn bound to `0.0.0.0:8000`, systemd service runs as `root` (security concern), `systemctl daemon-reload` triggered via notification chain.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local and Supermarket cookbook sources with version constraints. Superseded by `Policyfile.rb` for resolution but used by `berks vendor` in the provisioning script. No direct Ansible equivalent needed — replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list and pinned cookbook versions. Equivalent function is served by an Ansible playbook with an ordered `roles:` or `tasks:` list.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 cookbooks (including transitive deps: `selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the source of truth for exact dependency versions during migration.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides — site definitions (document roots, SSL flags), SSL certificate/key paths, and security flags (fail2ban, ufw, SSH hardening). Maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration file setting cache path and cookbook search paths. No Ansible equivalent needed.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 vCPUs / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Informs the target environment specification and can be adapted into an Ansible inventory with `ansible_host` variables, or retained as a local test harness with the Chef provisioner replaced by `ansible_local`.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef via the Omnitruck installer, runs `berks vendor`, and executes `chef-solo`. To be replaced by a Vagrant `ansible_local` provisioner block pointing at the new Ansible playbook.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a prior `migration-plan.md`, `generated-project-metadata.json` (module inventory), and a copy of `solo.json`. Not part of the Chef run; no migration action required.

---

### Target Details

- **Operating System**: Ubuntu (primary target, inferred from `www-data` user/group for Nginx, `ufw` and `fail2ban` package names, `/var/log/auth.log` path in Fail2Ban config, and `apt-get` usage in `vagrant-provision.sh`). `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The Vagrant box is `generic/fedora42`, indicating the local dev environment diverges from the declared production targets. **Recommended Ansible target: Ubuntu 22.04 LTS**, with conditional task guards (`when: ansible_os_family == "Debian"`) if RedHat/CentOS support must be retained.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. VM title set to `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community cookbook handles package install, service management, and config scaffolding. Replace entirely with `ansible.builtin.package` (install `nginx`), `ansible.builtin.template` for `nginx.conf` and `security.conf`, `ansible.builtin.service` for lifecycle management, and `ansible.builtin.file` for document root directories. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) translate directly to Jinja2 with minimal syntax changes (`<%= @var %>` → `{{ var }}`).

- **memcached (6.1.0, Chef Supermarket)**: Used with default configuration only. Replace with `ansible.builtin.package` to install `memcached` and `ansible.builtin.service` to enable and start it. No custom configuration is applied in the `cache` cookbook, so no template migration is required.

- **redisio (7.2.4, Chef Supermarket)**: Handles Redis installation, configuration file generation at `/etc/redis/6379.conf`, service management, and SELinux policy (via the `selinux 6.2.4` transitive dependency). Replace with `ansible.builtin.package` (install `redis-server`), `ansible.builtin.template` or `ansible.builtin.lineinfile` for `requirepass` injection into `/etc/redis/redis.conf`, and `ansible.builtin.service`. The `ruby_block` config-patching hack becomes unnecessary because Ansible will render a clean, version-appropriate config file directly — eliminating the need to strip deprecated directives post-install.

- **ssl_certificate (2.1.0, Chef Supermarket)**: Locked in `Policyfile.lock.json` but commented out in `Berksfile` and not called in any recipe. Self-signed certificate generation is handled inline in `nginx-multisite::ssl` via `openssl req`. Replace with `ansible.builtin.command` (or the `community.crypto.x509_certificate` + `community.crypto.openssl_privatekey` modules from `community.crypto` collection) for idempotent self-signed cert generation.

- **selinux (6.2.4, Chef Supermarket)**: Transitive dependency of `redisio`. Only relevant if the target is a RHEL/CentOS host. On Ubuntu the SELinux cookbook is a no-op. If RHEL support is required, use `ansible.posix.selinux` and `community.general.seboolean` modules.

- **Custom `lineinfile` LWRP** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): A hand-rolled Chef resource that replicates `ansible.builtin.lineinfile` behaviour (match-and-replace or append, with optional backup). Replace directly with `ansible.builtin.lineinfile`. No logic is lost; the Ansible module is a strict superset of the custom resource's capabilities.

---

### Security Considerations

- **Hardcoded Redis password** (`cookbooks/cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`): Plaintext credential embedded in recipe source. **Migrate to `ansible-vault`**: store the password in an encrypted `group_vars/all/vault.yml` variable (e.g., `vault_redis_password`) and reference it in the Redis configuration template. **1 credential detected.**

- **Hardcoded PostgreSQL credentials** (`cookbooks/fastapi-tutorial/recipes/default.rb`): Two occurrences — the `CREATE USER fastapi WITH PASSWORD 'fastapi_password'` SQL statement and the `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` value written to `/opt/fastapi-tutorial/.env`. **Migrate both to `ansible-vault`** encrypted variables. The `.env` file should be rendered from a Jinja2 template referencing vault variables. **2 credentials detected.**

- **Self-signed TLS certificates**: The `ssl.rb` recipe generates self-signed certificates with a hardcoded subject (`/C=US/ST=Example/...`). In Ansible, use `community.crypto.x509_certificate` with `provider: selfsigned` for development, and document a clear upgrade path to Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA for production. Certificate subject fields should be parameterised as variables.

- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using raw `sed` commands. Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`, which are idempotent and auditable. Ensure the `sshd` handler is notified on change.

- **UFW firewall management via shell commands**: The `security.rb` recipe uses `execute` resources with raw `ufw` CLI commands and `not_if` shell guards. Replace with the `community.general.ufw` module, which is fully idempotent and does not require shell guards.

- **FastAPI service running as root**: The systemd unit file sets `User=root`. This is a significant security risk. The Ansible migration is an opportunity to create a dedicated `fastapi` system user and update the service unit accordingly. Flag this for the application team.

- **`.env` file permissions**: The `.env` file containing `DATABASE_URL` (with embedded password) is created with mode `0644` (world-readable). In Ansible, set `mode: '0600'` and `owner: fastapi` (after creating the dedicated service user).

- **No secrets management currently in use**: There are no Chef encrypted data bags, Chef Vault references, or environment variable injection patterns in the source. All secrets are plaintext in recipe files. The Ansible migration must introduce `ansible-vault` as the secrets management baseline. **Total credentials requiring vaulting: 3** (Redis password, PostgreSQL user password × 2 occurrences).

---

### Technical Challenges

- **`ruby_block` Redis config patching hack**: The `cache` cookbook contains a `ruby_block` that post-processes `/etc/redis/6379.conf` to strip directives that `redisio` 7.2.4 writes but the installed Redis version rejects. This is a workaround for a community cookbook bug. In Ansible, this entire pattern is eliminated by rendering the Redis configuration file directly from a Jinja2 template that only includes directives valid for the target Redis version. However, the team must verify the exact Redis package version available on the target OS and ensure the template is compatible.

- **Attribute precedence and `solo.json` overrides**: The `solo.json` file overrides the cookbook's `attributes/default.rb` values (notably the `document_root` paths: cookbook defaults use `/opt/server/*`, while `solo.json` uses `/var/www/*`). In Ansible, this maps to variable precedence between `roles/nginx-multisite/defaults/main.yml` (low precedence, equivalent to `default` attributes) and `group_vars` or `host_vars` (higher precedence, equivalent to `solo.json` overrides). The migration must explicitly document which values are defaults and which are environment-specific overrides.

- **Chef `include_recipe` ordering**: The `nginx-multisite::default` recipe enforces a strict execution order: `security` → `nginx` → `ssl` → `sites`. In Ansible, this maps to task ordering within a role's `tasks/main.yml` or to a playbook with ordered role includes. The dependency between `ssl.rb` (cert generation) and `sites.rb` (cert path references in vhost config) must be preserved — the SSL tasks must complete before the Nginx vhost templates are rendered.

- **`not_if` / `only_if` guard translation**: Several `execute` resources in `security.rb` use shell-based `not_if` guards (e.g., `not_if 'ufw status | grep -q "Status: active"'`). These translate to Ansible `when:` conditionals combined with registered `command` output or dedicated module state checks. Using `community.general.ufw` eliminates most of these guards entirely.

- **Vagrant/Fedora42 vs. Ubuntu production target mismatch**: The local development environment uses Fedora 42 (RPM-based, `dnf`), but the cookbooks declare Ubuntu/CentOS support and use `apt-get` in the provisioning script. The `www-data` user, `ufw`, and `/var/log/auth.log` are Debian/Ubuntu-specific. The Ansible playbook should target Ubuntu explicitly, and the Vagrant box should be updated to `generic/ubuntu2204` for local testing consistency. If Fedora/RHEL support is genuinely required, OS-family conditionals must be added throughout.

- **Git-based application deployment**: The `fastapi-tutorial` cookbook clones a public GitHub repository at converge time. In a production Ansible context, this introduces a runtime dependency on external network access and GitHub availability. Consider using `ansible.builtin.git` with a pinned `version:` (commit SHA or tag) rather than `main`, and evaluate whether the application artefact should be pre-built and distributed via an artefact repository instead.

- **`systemctl daemon-reload` notification chain**: The Chef recipe triggers `daemon-reload` via a notification from the service unit file resource. In Ansible, this is handled by a handler (`ansible.builtin.systemd: daemon_reload: yes`) notified by the template task that writes the unit file — a direct and clean equivalent.

---

### Migration Order

1. **`nginx-multisite` — Security sub-recipe** (low risk, no external cookbook dependency): Migrate UFW, Fail2Ban, sysctl hardening, and SSH hardening first. These are self-contained, use only system packages, and establish the security baseline that all other services depend on. Validates the Ansible inventory, connection, and privilege escalation setup.

2. **`nginx-multisite` — Nginx core + SSL + Sites sub-recipes** (moderate complexity): Migrate Nginx installation, `nginx.conf` template, self-signed certificate generation, and per-site vhost configuration. Validates Jinja2 template rendering, handler notification chains, and the `community.crypto` collection. Depends on step 1 (UFW must allow ports 80/443 before Nginx is tested).

3. **`cache` — Memcached** (low complexity): Install and enable Memcached with default configuration. No templates, no credentials. Quick win to validate the package/service pattern in Ansible.

4. **`cache` — Redis** (moderate complexity): Install Redis, render configuration with `requirepass` from vault, enable service. Requires `ansible-vault` to be set up before this step. Eliminates the `ruby_block` patching hack.

5. **`fastapi-tutorial`** (highest complexity, depends on steps 1–4): Migrate Python environment setup, Git clone, venv, pip install, PostgreSQL provisioning, `.env` file rendering, and systemd service. This step requires vault variables for PostgreSQL credentials, a dedicated service user, corrected file permissions, and a pinned Git revision. Should be migrated last due to the highest number of moving parts and security remediation items.

---

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS** for production. The Vagrant `generic/fedora42` box is assumed to be a developer convenience that does not reflect the production target. If Fedora/RHEL is the actual production target, significant rework is needed (package names, service names, `ufw` → `firewalld`, `www-data` → `nginx` user, `auth.log` path).

2. **The `ssl_certificate` community cookbook** is intentionally unused (commented out in `Berksfile`, present only in `Policyfile.lock.json` as a locked but unreferenced dependency). It will not be migrated.

3. **Self-signed certificates are acceptable for the target environment** (development/staging). If this is a production migration, the SSL recipe must be replaced with a proper CA-signed or Let's Encrypt certificate workflow, which is out of scope for a direct 1:1 migration.

4. **The FastAPI application source** at `https://github.com/dibanez/fastapi_tutorial.git` is assumed to be accessible from the target host at provisioning time. If the environment is air-gapped, an alternative artefact delivery mechanism must be designed.

5. **Memcached requires no authentication** and no custom configuration beyond installation. The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides, implying default settings are intentional.

6. **The `redisio` cookbook's SELinux integration** (via the `selinux 6.2.4` transitive dependency) is a no-op on Ubuntu and is not migrated. If RHEL/CentOS is added as a target later, SELinux policy for Redis must be addressed separately.

7. **The custom `lineinfile` LWRP** in `nginx-multisite/resources/lineinfile.rb` is not called anywhere in the cookbook's own recipes (no `lineinfile` resource calls were found in the recipe files). It appears to be a utility resource available for external use. It will be documented but not actively migrated unless a calling recipe is discovered.

8. **The `www-data` user and group** used as the Nginx document root owner is assumed to be created automatically by the `nginx` package on Ubuntu. The Ansible role should include an explicit `ansible.builtin.user` task to ensure idempotency if the package installation order changes.

9. **Port 8000** (uvicorn/FastAPI) is not opened in the UFW rules defined in `security.rb`. It is assumed that FastAPI is accessed internally (e.g., proxied through Nginx) and does not require a public firewall rule. If direct external access is needed, a UFW rule must be added.

10. **The `solo.json` document root paths** (`/var/www/<site>`) are treated as the authoritative values, overriding the cookbook attribute defaults (`/opt/server/<site>`). The Ansible `group_vars` will use the `solo.json` values as the baseline.

11. **No CI/CD pipeline** exists in this repository for the Chef code. The Ansible migration should introduce a basic pipeline (e.g., GitHub Actions with `ansible-lint` and `molecule` for local VM testing) as part of the migration deliverable.

12. **Chef version >= 16.0** is required per all `metadata.rb` files. This implies modern Chef resource syntax is used throughout, with no legacy LWRP patterns (except the custom `lineinfile` resource, which uses the modern `custom_resource` style). No compatibility shims are needed during analysis.
