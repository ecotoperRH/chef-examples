# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and tested locally with Vagrant on a Fedora 42 / libvirt VM.

The overall migration complexity is **moderate**. The cookbooks are well-structured, self-contained, and free of Chef Server constructs (no data bags, no roles, no environments, no Chef Vault). The primary challenges are: replacing two community cookbooks (`memcached` ~> 6.1.0 and `redisio` ~> 7.2.4) with native Ansible modules, migrating a custom `lineinfile` LWRP to the built-in `ansible.builtin.lineinfile` module, and safely externalising the hardcoded credentials found in the `cache` and `fastapi-tutorial` cookbooks.

**Estimated migration timeline: 5–8 working days** for a single engineer familiar with Ansible, broken down as follows:

| Phase | Scope | Effort |
|---|---|---|
| 1 – Security & base hardening | `nginx-multisite::security` | 1 day |
| 2 – Nginx multisite | `nginx-multisite::nginx/ssl/sites` | 2 days |
| 3 – Caching services | `cache` (Memcached + Redis) | 1–2 days |
| 4 – FastAPI application | `fastapi-tutorial` | 1–2 days |
| 5 – Integration & validation | Inventory, group_vars, smoke tests | 1 day |

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that require individual migration planning, backed by **5 external cookbook dependencies** that map to native Ansible modules or Galaxy roles.

---

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server with multiple SSL-enabled virtual hosts (test, ci, status subdomains of `cluster.local`), security hardening via HTTP headers, rate limiting, and self-signed TLS certificate generation using OpenSSL. Manages the full Nginx lifecycle including `nginx.conf`, per-site `server {}` blocks, and the `sites-available` / `sites-enabled` symlink pattern.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - Four sub-recipes orchestrated from `default.rb`: `security`, `nginx`, `ssl`, `sites`
    - Per-site self-signed certificate generation (`openssl req -x509`, RSA 2048, 365-day validity)
    - TLS 1.2/1.3 only with hardened cipher suite; HSTS header (`max-age=31536000; includeSubDomains`)
    - Security HTTP headers: `X-Frame-Options DENY`, `X-Content-Type-Options`, `X-XSS-Protection`, `Content-Security-Policy`, `Referrer-Policy`
    - Nginx rate-limiting zones (`login`: 10 r/m, `api`: 30 r/m) via `security.conf`
    - UFW firewall rules (default deny, allow SSH/80/443) managed via `execute` resources
    - Fail2ban with four jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
    - Kernel hardening via `sysctl` (IP spoofing protection, ICMP redirect suppression, SYN-cookie flood protection, IPv6 disable)
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
    - Custom `lineinfile` LWRP (`resources/lineinfile.rb`) that replicates Ansible's built-in `lineinfile` module
    - Three static site document roots with pre-built `index.html` files (ci, status, test)
    - `www-data` ownership for document roots; `ssl-cert` group for private keys (mode `0710`)

- **cache**:
  - Description: Caching services layer that installs and configures both Memcached (via the `memcached` ~> 6.1.0 community cookbook) and Redis (via the `redisio` ~> 7.2.4 community cookbook) with password authentication. Includes a `ruby_block` workaround to strip deprecated Redis configuration directives written by the `redisio` cookbook.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Memcached installation delegated entirely to the `memcached` community cookbook (default configuration)
    - Redis server on port 6379 with `requirepass` authentication
    - Dedicated `/var/log/redis` directory (owner: `redis:redis`, mode `0755`)
    - Post-install config-file patch (`ruby_block "fix_redis_config"`) that removes five deprecated `replica-*` and `client-output-buffer-limit` directives from `/etc/redis/6379.conf` — a workaround for `redisio` 7.2.4 generating config incompatible with newer Redis versions
    - Redis service enabled via `redisio::enable`
    - **Hardcoded Redis password**: `redis_secure_password_123` (must be migrated to Ansible Vault)

- **fastapi-tutorial**:
  - Description: End-to-end deployment of a Python FastAPI application (`github.com/dibanez/fastapi_tutorial`) with a PostgreSQL backend. Covers system package installation, Python virtual environment creation, Git-based source deployment, PostgreSQL database and user provisioning, `.env` file generation, and systemd service unit creation.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial`
    - Python venv at `/opt/fastapi-tutorial/venv`; dependencies installed from `requirements.txt`
    - PostgreSQL service enabled and started; database user `fastapi` and database `fastapi_db` created via `psql` shell commands with `|| true` guards
    - `.env` file at `/opt/fastapi-tutorial/.env` containing `DATABASE_URL` with embedded credentials (mode `0644`, owned by `root`)
    - systemd unit `fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, `Restart=always`, `After=postgresql.service`
    - Service runs as `root` (security concern — see Security Considerations)
    - **Hardcoded PostgreSQL password**: `fastapi_password` in both the `psql` provisioning command and the `.env` file (must be migrated to Ansible Vault)

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external Supermarket cookbooks (`nginx` ~> 12.0, `memcached` ~> 6.0, `redisio` ~> 7.2.4; `ssl_certificate` ~> 2.1 is commented out). Replaced in Ansible by `requirements.yml` (Galaxy roles) or direct module usage.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy` and the run list `[nginx-multisite::default, cache::default, fastapi-tutorial::default]`. The Ansible equivalent is a top-level playbook (e.g., `site.yml`) with an ordered `roles:` or `tasks:` list.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Ansible equivalent is a committed `requirements.yml` with pinned Galaxy role versions.
- `solo.json`: Chef Solo node JSON providing run list and attribute overrides. Defines the three virtual host names (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) with `ssl_enabled: true`, SSL certificate/key paths, and security flags (fail2ban, UFW, SSH hardening). Migrates to Ansible `group_vars/all.yml` or a host-specific `host_vars` file.
- `solo.rb`: Chef Solo configuration file pointing to `/var/chef-solo` as the cache path and `/chef-repo/cookbooks` as the cookbook path. No Ansible equivalent needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Provisions via `vagrant-provision.sh`. Migrates to an Ansible inventory file with a `vagrant` group and a corresponding `ansible.cfg` pointing at the Vagrant SSH key.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. Replaced entirely by `ansible-playbook` invocation; no equivalent needed in the Ansible project.
- `project-plan.md`: Internal tooling specification for the X2Ansible migration tool. Not part of the infrastructure; no migration action required.

---

### Target Details

- **Operating System**: Ubuntu (primary target, confirmed by `www-data` user for Nginx, `ufw` firewall, `/var/log/auth.log` path in Fail2ban jail, `apt-get` in `vagrant-provision.sh`). The `metadata.rb` files declare support for Ubuntu >= 18.04 and CentOS >= 7.0. The Vagrant box is `generic/fedora42` (used for local development only). Production target should be treated as **Ubuntu 22.04 LTS** unless explicitly overridden; tasks using `ufw` and `www-data` will need conditional handling for RHEL/Fedora targets.
- **Virtual Machine Technology**: **KVM/libvirt** (confirmed by `config.vm.provider "libvirt"` in `Vagrantfile`). Private network IP `192.168.121.10`.
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (Chef Supermarket ~> 12.3.1)**: The community cookbook is used only as a package source; the `nginx-multisite` cookbook manages all configuration files directly via its own templates. Replace with `ansible.builtin.package: name=nginx` and the existing Jinja2-converted templates. No Galaxy role required.
- **memcached (Chef Supermarket ~> 6.1.0)**: Installs and configures Memcached with default settings. Replace with `ansible.builtin.package: name=memcached` + `ansible.builtin.service` + an optional `memcached.conf` template if non-default settings are needed in future. Alternatively, use the `geerlingguy.memcached` Galaxy role for a drop-in equivalent.
- **redisio (Chef Supermarket ~> 7.2.4)**: Installs Redis, writes `/etc/redis/6379.conf`, and manages the service. The cookbook has a known incompatibility with newer Redis config directives (worked around by the `ruby_block "fix_redis_config"` hack). Replace with `ansible.builtin.package: name=redis-server` + a fully-managed `redis.conf` Jinja2 template that omits the deprecated directives entirely, plus `ansible.builtin.service`. The `geerlingguy.redis` Galaxy role is a well-maintained alternative.
- **selinux (Chef Supermarket ~> 6.2.4)**: Pulled in transitively by `redisio`. Only relevant on RHEL/CentOS/Fedora targets. Replace with `ansible.posix.selinux` module or the `geerlingguy.security` role if SELinux management is required on the target OS.
- **ssl_certificate (Chef Supermarket ~> 2.1.0)**: Present in `Policyfile.rb` and `Policyfile.lock.json` but **commented out** in `Berksfile` and not referenced in any recipe. The `nginx-multisite::ssl` recipe implements its own self-signed certificate generation via `openssl` shell commands. No direct replacement needed; migrate the `execute "generate-ssl-cert-*"` resources to `ansible.builtin.command` with `creates:` idempotency guard, or use the `community.crypto.x509_certificate` module for a fully declarative approach.
- **Custom `lineinfile` LWRP** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): A hand-rolled Chef resource that replicates line-in-file editing with match/replace and backup logic. Replace directly with `ansible.builtin.lineinfile`, which provides identical semantics natively. No custom code needed.

---

### Security Considerations

- **Hardcoded Redis password** (`cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`): This credential is stored in plain text in the recipe source. **Action**: Remove from source, store in `ansible/group_vars/all/vault.yml` encrypted with `ansible-vault`, and reference as `{{ redis_requirepass }}`.
- **Hardcoded PostgreSQL password** (`fastapi-tutorial/recipes/default.rb`, `psql` command and `.env` file content: `fastapi_password`): Appears twice — once in the database provisioning shell command and once in the `.env` file written to disk. **Action**: Externalise to Ansible Vault as `{{ fastapi_db_password }}`. The `.env` file template must use `mode: '0600'` (currently `0644`) and should be owned by the application service user, not `root`.
- **FastAPI service running as root** (`fastapi-tutorial/recipes/default.rb`, systemd unit `User=root`): The application process has full root privileges. **Action**: Create a dedicated `fastapi` system user and group during the Ansible role setup; update the systemd unit template to `User=fastapi`.
- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated at provision time (`openssl req -x509`, 365-day validity, hardcoded subject `/C=US/ST=Example/...`). These are appropriate for development/staging but must be replaced with CA-signed or Let's Encrypt certificates for production. **Action**: Parameterise the certificate subject fields; add a boolean variable `nginx_use_selfsigned_cert` to gate between self-signed (dev) and production certificate paths. Consider `community.crypto.x509_certificate` + `community.crypto.acme_certificate` for production.
- **SSL private key permissions**: The `ssl.rb` recipe correctly sets `chmod 640` and `chown root:ssl-cert` on private keys. Replicate this exactly in Ansible using `ansible.builtin.file` with `owner: root`, `group: ssl-cert`, `mode: '0640'`.
- **SSH hardening** (`security.rb`): `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` on `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` tasks (or `ansible.builtin.template` for the full sshd_config). **Caution**: Disabling password auth before confirming SSH key delivery to the target host will lock out access. Ensure the Ansible control node's public key is in `authorized_keys` before applying this task.
- **UFW firewall management via raw `execute` resources**: The `security.rb` recipe uses shell `ufw` commands with `not_if` guards. Replace with `community.general.ufw` module for idempotent, declarative firewall management.
- **Fail2ban configuration**: The `jail.local` template bans IPs for 3600 seconds after 3 retries (2 for botsearch). These values are hardcoded in the template. **Action**: Parameterise `bantime`, `findtime`, and `maxretry` as Ansible variables to allow environment-specific tuning.
- **Kernel sysctl hardening**: IPv6 is globally disabled (`net.ipv6.conf.all.disable_ipv6 = 1`). This may conflict with some cloud or dual-stack environments. **Action**: Gate behind a variable `sysctl_disable_ipv6: true` defaulting to `false` in production group_vars.
- **Credential count summary**:
  - `cache` cookbook: **1 hardcoded secret** (Redis password)
  - `fastapi-tutorial` cookbook: **2 hardcoded secrets** (PostgreSQL password appears in provisioning command and `.env` file content)
  - `nginx-multisite` cookbook: **0 runtime secrets** (certificate subject fields contain placeholder values only)
  - Total: **3 secret values** requiring Ansible Vault protection

---

### Technical Challenges

- **`ruby_block "fix_redis_config"` workaround**: The `cache` cookbook patches the Redis config file post-install to remove deprecated directives written by `redisio` 7.2.4. This is a code smell indicating a version mismatch between the cookbook and the installed Redis binary. In Ansible, this is best resolved by owning the entire `redis.conf` via a Jinja2 template that never includes the deprecated directives, making the workaround unnecessary. Verify the Redis version available on the target OS (`redis-server` package version on Ubuntu 22.04 is 6.x or 7.x) and ensure the template is compatible.
- **Chef attribute precedence vs. Ansible variable precedence**: The `nginx-multisite` cookbook defines default attributes in `attributes/default.rb` that are overridden by `solo.json` node attributes (e.g., `document_root` paths differ: cookbook defaults use `/opt/server/*`, `solo.json` uses `/var/www/*`). When migrating to Ansible, these must be consolidated into a clear variable hierarchy: role defaults → group_vars → host_vars. The `solo.json` values should become `group_vars/all.yml` or playbook `vars:`.
- **Nginx `sites-available` / `sites-enabled` symlink pattern**: The `sites.rb` recipe creates symlinks from `sites-enabled/` to `sites-available/`. Ansible's `ansible.builtin.file` module with `state: link` handles this cleanly, but the default Nginx site deletion (`file '/etc/nginx/sites-enabled/default' do action :delete end`) must also be replicated to avoid the default vhost intercepting traffic.
- **Idempotency of PostgreSQL provisioning**: The `fastapi-tutorial` recipe uses `sudo -u postgres psql -c "..." || true` shell commands to create the database user and database. The `|| true` suppresses errors on re-runs but is not truly idempotent. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **Git-based application deployment**: The `git` resource syncs `https://github.com/dibanez/fastapi_tutorial.git` on every Chef run. In Ansible, `ansible.builtin.git` with `update: yes` provides the same behaviour. Consider whether the deployment should pin to a specific commit SHA or tag rather than tracking `main` for production stability.
- **`pip install -r requirements.txt` idempotency**: The `execute 'install_dependencies'` resource runs unconditionally on every Chef run (no `not_if` guard). In Ansible, use `ansible.builtin.pip` with `virtualenv:` and `requirements:` parameters; it is idempotent by default.
- **systemd daemon-reload notification chain**: The `fastapi-tutorial` recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, use a handler with `ansible.builtin.systemd: daemon_reload: yes` triggered by a `notify:` on the unit file task.
- **Vagrant-specific network configuration**: The `Vagrantfile` uses libvirt with a private network IP (`192.168.121.10`). The Ansible inventory for local development should use this IP with `ansible_user=vagrant` and the Vagrant-generated SSH key. A separate production inventory will be needed.
- **`ssl_certificate` cookbook discrepancy**: The cookbook is present in `Policyfile.rb` and `Policyfile.lock.json` (version 2.1.0, locked) but is commented out in `Berksfile` and unused in any recipe. This suggests it was planned but never implemented, or was removed mid-development. No migration action is required, but the discrepancy should be noted and the lock file entry cleaned up.

---

### Migration Order

The following order minimises risk by establishing foundational layers before dependent services:

1. **`nginx-multisite::security`** — Base OS hardening (UFW, Fail2ban, sysctl, SSH) has no dependencies on other cookbooks and should be migrated first as a standalone `security` role. This establishes the firewall and intrusion-prevention baseline before any services are exposed.

2. **`nginx-multisite::nginx` + `::ssl` + `::sites`** — Nginx installation, TLS certificate generation, virtual host configuration, and static site content deployment. Depends only on the security layer being in place. Migrate as a single `nginx_multisite` role with sub-task files mirroring the recipe structure. Convert all five ERB templates to Jinja2.

3. **`cache` (Memcached + Redis)** — Caching services are independent of Nginx and FastAPI at the infrastructure level. Migrate as a `cache` role with two sub-roles or task files (`memcached.yml`, `redis.yml`). Resolve the `redisio` workaround by using a clean Redis config template. Externalise the Redis password to Vault before this step.

4. **`fastapi-tutorial`** — Application deployment depends on PostgreSQL (installed as part of this cookbook) and optionally on Redis/Memcached being available. Migrate as a `fastapi` role. Resolve the root-user service issue, externalise the PostgreSQL password to Vault, and replace shell-based DB provisioning with `community.postgresql` modules.

5. **Integration, inventory, and validation** — Write the top-level `site.yml` playbook, finalise `group_vars/` and `host_vars/`, create the Vagrant development inventory and a production inventory skeleton, and run end-to-end smoke tests against the Vagrant VM.

---

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS** for production. The Vagrant box (`generic/fedora42`) is used only for local development. Tasks using `ufw`, `www-data`, and `/var/log/auth.log` are Ubuntu-specific and will require `when: ansible_os_family == "Debian"` guards if RHEL/Fedora support is needed.
2. **Chef Server is not in use.** The repository uses Chef Solo exclusively (`solo.rb`, `solo.json`, `vagrant-provision.sh`). There are no data bags, roles, environments, Chef Vault references, or Ohai-driven conditionals beyond basic `node['security']` attribute lookups. The migration does not need to account for any Chef Server constructs.
3. **The `ssl_certificate` community cookbook is intentionally unused.** It appears in `Policyfile.rb` and the lock file but is commented out in `Berksfile`. It is assumed this was a planned dependency that was never activated. No Ansible equivalent is needed.
4. **Self-signed certificates are acceptable for the initial Ansible migration target** (development/staging). Production certificate management (Let's Encrypt or internal CA) is out of scope for this migration but should be addressed before production rollout.
5. **The Redis password (`redis_secure_password_123`) and PostgreSQL password (`fastapi_password`) are development/example credentials** and are not used in any production environment. They will be replaced with strong, Vault-managed secrets during migration.
6. **The FastAPI application source (`github.com/dibanez/fastapi_tutorial`, branch `main`) is publicly accessible** and does not require authentication for `git clone`. If the repository is moved to a private host, an SSH deploy key or token will need to be provisioned.
7. **Memcached is deployed with default configuration.** The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides. It is assumed the default Memcached port (11211), memory limit, and bind address are acceptable. If custom configuration is required, it must be specified as Ansible variables.
8. **The `lineinfile` custom LWRP is used only internally** within the `nginx-multisite` cookbook and is not called from any recipe in this repository. It appears to be a utility resource available for future use. It will be dropped in favour of `ansible.builtin.lineinfile`.
9. **The three virtual host document roots differ between `attributes/default.rb` (`/opt/server/*`) and `solo.json` (`/var/www/*`).** The `solo.json` values take precedence at runtime. The Ansible migration will use `/var/www/<site>` as the canonical document root, matching the runtime behaviour. The `/opt/server/*` defaults will be discarded.
10. **No monitoring, alerting, or log aggregation integration is present** in the current cookbooks. The `status.cluster.local` site is a static HTML page, not a live monitoring dashboard. Any observability tooling is out of scope for this migration.
11. **The `selinux` cookbook is a transitive dependency of `redisio`** and is not explicitly configured. It is assumed SELinux is either disabled or in permissive mode on the target Ubuntu host (SELinux is not the default MAC system on Ubuntu; AppArmor is). No SELinux Ansible tasks are required unless the target is RHEL/Fedora.
12. **Port 8000 (uvicorn/FastAPI) is not exposed via UFW** in the current `security.rb` recipe. It is assumed the FastAPI service is accessed internally (e.g., proxied through Nginx) rather than directly. If direct external access is needed, a UFW rule must be added to the Ansible security role.
