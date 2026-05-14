# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-level security hardening, in-memory caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is currently exercised locally via Vagrant with a Fedora 42 libvirt VM and is managed through a `Policyfile.rb` / `Berksfile` dependency model.

The migration targets **Ansible** and is assessed as **medium complexity**. The three cookbooks are well-scoped, have clear single responsibilities, and map cleanly to Ansible roles. The primary challenges are: replacing two community Chef Supermarket cookbooks (`redisio`, `memcached`) with native Ansible modules, handling a Redis config post-processing hack currently implemented as a `ruby_block`, migrating self-signed certificate generation, and securing the several plaintext credentials that are currently embedded directly in recipe code and node attributes.

**Estimated timeline**: 3–4 weeks for a complete migration including unit testing and Vagrant-based validation.

| Cookbook | Complexity | Estimated Effort |
|---|---|---|
| `nginx-multisite` | Medium | 6–8 days |
| `cache` | Low–Medium | 3–4 days |
| `fastapi-tutorial` | Medium–High | 5–7 days |
| Integration & testing | — | 3–4 days |

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation per vhost, HTTP-to-HTTPS redirect, TLS 1.2/1.3 enforcement, security response headers (HSTS, X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection), gzip compression, and a global Nginx security hardening snippet with rate-limiting zones and buffer overflow protections. Also orchestrates the security sub-recipe.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features:
        - Dynamic multi-site loop driven by `node['nginx']['sites']` attribute hash (3 sites)
        - Per-site self-signed RSA-2048 certificate generation via `openssl req` shell command
        - `sites-available` / `sites-enabled` symlink pattern; default site removed
        - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) for idempotent file-line management
        - Separate sub-recipes: `nginx.rb`, `ssl.rb`, `sites.rb`, `security.rb`
        - ERB templates: `nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`
        - Static `index.html` files for each vhost (`files/default/{test,ci,status}/index.html`)
        - fail2ban with jails for sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch
        - UFW firewall: default-deny, allow SSH/HTTP/HTTPS
        - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` in-place edits
        - Kernel hardening via `sysctl.d/99-security.conf`: IP spoofing protection, ICMP redirect ignore, SYN flood protection, IPv6 disable

- **cache**:
    - Description: In-memory caching layer configuring both Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication, a custom log directory, and a post-processing `ruby_block` that strips deprecated Redis configuration directives from the generated `/etc/redis/6379.conf`.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached` community cookbook (v6.1.0)
        - Redis configured on port 6379 with `requirepass` set to a hardcoded password (`redis_secure_password_123`)
        - `ruby_block "fix_redis_config"` post-processes the generated config file to remove five deprecated `replica-*` and `client-output-buffer-limit` directives that cause errors with newer Redis versions
        - Creates `/var/log/redis` directory owned by `redis:redis`
        - Calls `redisio` and `redisio::enable` recipes (v7.2.4)
        - Transitive dependency on `selinux` cookbook (v6.2.4) pulled in by `redisio`

- **fastapi-tutorial**:
    - Description: Full-stack Python web application deployment: installs system packages (Python 3, pip, venv, git, PostgreSQL client/server, libpq-dev), clones the FastAPI tutorial application from GitHub, creates a Python virtual environment, installs pip dependencies, configures and starts PostgreSQL, provisions a database user and database, writes a `.env` configuration file with the database URL, and registers a systemd unit (`fastapi-tutorial.service`) running uvicorn on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features:
        - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch into `/opt/fastapi-tutorial`
        - Python venv at `/opt/fastapi-tutorial/venv`; pip install from `requirements.txt`
        - PostgreSQL service enabled and started; database user `fastapi` with hardcoded password `fastapi_password`; database `fastapi_db` created and granted
        - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL` with embedded credentials (mode `0644`, owned by root — security concern)
        - systemd unit file written inline; `ExecStart` runs uvicorn as `root` (security concern)
        - `systemctl daemon-reload` triggered via `notifies :run` on the service file resource
        - No idempotency guard on `create_db_user` execute block (uses `|| true` workaround)

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbooks by path and four Supermarket dependencies (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out in Berksfile but present in Policyfile). Will be superseded by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and version constraints for all cookbooks. Equivalent to an Ansible playbook + `requirements.yml` combined.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the source of truth for pinned versions during Ansible role selection.
- `solo.json`: Chef Solo node attribute JSON — the primary runtime configuration input. Defines the run list, three vhost site definitions with document roots and SSL flags, SSL certificate/key paths, and security feature toggles (fail2ban, ufw, SSH hardening). This file's structure maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` as the file cache and `/chef-repo/cookbooks` as the cookbook path. No migration artifact needed; replaced by `ansible.cfg` and inventory.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of repo to `/chef-repo`. The VM definition should be adapted to use the `ansible_local` or `ansible` Vagrant provisioner after migration.
- `vagrant-provision.sh`: Bash bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo`. After migration this script is replaced by a simple `ansible-playbook` invocation or the Vagrant `ansible` provisioner block.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory containing a duplicate `solo.json`, a `Policyfile.lock.json`, a `generated-project-metadata.json` (cookbook inventory), and a prior draft `migration-plan.md`. This directory appears to be tooling scaffolding and has no runtime role; it should not be migrated.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` as the development target. Cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The provisioning script uses `apt-get`, indicating the primary tested runtime is **Debian/Ubuntu**. Ansible roles must handle both Debian (apt) and RHEL/Fedora (dnf) package managers via `ansible_os_family` conditionals, or the target OS must be standardised. **Recommended target for migration: Ubuntu 22.04 LTS** (aligns with `apt-get` usage in `vagrant-provision.sh`) or **Red Hat Enterprise Linux 9** if the Fedora 42 Vagrant box is representative of production.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the Vagrantfile (`config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community `nginx` cookbook is used only as a package provider by `nginx-multisite`. Replace with the `ansible.builtin.package` module (`nginx`) and manage all configuration via Ansible templates — a direct 1:1 replacement. Consider the `nginxinc.nginx` Ansible Galaxy role for production-grade management.
- **memcached (6.1.0, Chef Supermarket)**: Used wholesale by the `cache` cookbook. Replace with `ansible.builtin.package` (install `memcached`), `ansible.builtin.service` (enable/start), and a Jinja2 template for `memcached.conf`. The `geerlingguy.memcached` Galaxy role is a well-maintained drop-in.
- **redisio (7.2.4, Chef Supermarket)**: Manages Redis installation, configuration file generation, and service enablement. Replace with `ansible.builtin.package` (install `redis` / `redis-server`), a Jinja2 template for `redis.conf` (directly setting `requirepass`, eliminating the post-processing hack), and `ansible.builtin.service`. The `geerlingguy.redis` Galaxy role covers this cleanly.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Referenced in `Policyfile.rb` but not directly called in any recipe (certificate generation is done inline via `openssl` shell commands in `ssl.rb`). Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection — provides idempotent, declarative self-signed certificate management without shell commands.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. On Fedora/RHEL targets, use the `ansible.posix.selinux` module and `community.general.seboolean` as needed. On Ubuntu targets this dependency is irrelevant.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): This plaintext credential must be moved to **Ansible Vault** as `vault_redis_password` and referenced via a variable. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb` and in the inline `.env` file content): Both the `psql` provisioning command and the `DATABASE_URL` in `.env` embed the password in plaintext. Must be vaulted as `vault_fastapi_db_password`. **2 credential instances detected (DB provisioning + .env file).**
- **`.env` file permissions**: The `.env` file at `/opt/fastapi-tutorial/.env` is written with mode `0644` (world-readable), exposing `DATABASE_URL` including the database password to all local users. In the Ansible role this file must be created with mode `0600` and owned by the application service user (not root).
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk. The Ansible role should create a dedicated `fastapi` system user and run the service under that account.
- **SSH hardening via `sed`**: `security.rb` uses raw `sed -i` commands to modify `/etc/ssh/sshd_config`. Replace with the `ansible.builtin.lineinfile` module (a direct equivalent of the custom `lineinfile` LWRP) for idempotent, auditable SSH configuration management.
- **Self-signed TLS certificates**: Certificates are generated with a 365-day validity using `openssl req` shell commands with a hardcoded subject (`/C=US/ST=Example/...`). The `not_if` guard checks only for file existence, not certificate expiry. The Ansible `community.crypto.x509_certificate` module supports expiry-aware renewal. For production, a Let's Encrypt / ACME workflow (`community.crypto.acme_certificate`) should be considered.
- **Private key permissions**: `ssl.rb` sets the private key to mode `640`, owned `root:ssl-cert`. This must be replicated precisely in the Ansible role using `ansible.builtin.file` with `owner: root`, `group: ssl-cert`, `mode: '0640'`.
- **UFW firewall management**: `security.rb` uses raw `ufw` shell commands with `not_if` guards. Replace with the `community.general.ufw` Ansible module for fully declarative, idempotent firewall rule management.
- **fail2ban configuration**: The `jail.local` template is static (no Chef attribute interpolation). It can be copied directly as an Ansible `files/` static file or a minimal Jinja2 template. Ensure the `ansible.builtin.service` handler restarts fail2ban on config change.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template is also fully static. Use the `ansible.posix.sysctl` module to manage each parameter individually (preferred for auditability) or copy the file via `ansible.builtin.copy` with a `sysctl -p` handler.
- **Vault/secrets summary by module**:
  - `cache`: 1 secret — Redis `requirepass` password
  - `fastapi-tutorial`: 2 secret instances — PostgreSQL user password (provisioning) + `DATABASE_URL` in `.env`
  - `nginx-multisite`: 0 runtime secrets (certificates are generated on-host; no pre-shared keys)

---

### Technical Challenges

- **Redis `ruby_block` post-processing hack**: The `cache` cookbook uses a `ruby_block` to strip five deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the `redisio`-generated config file. This hack exists because `redisio 7.2.4` generates directives that are invalid in newer Redis versions. In Ansible, since the Redis config file will be managed directly via a Jinja2 template (not delegated to a community cookbook), these directives simply will not be included — eliminating the need for the hack entirely. The template must be carefully authored to include only directives valid for the target Redis version.
- **Dynamic multi-site Nginx loop**: The `nginx.rb` and `sites.rb` recipes iterate over `node['nginx']['sites']` to create document roots, copy static files, generate per-site Nginx configs, and create symlinks. In Ansible this maps to a `loop` over a `nginx_sites` list variable in `group_vars`. The Jinja2 `site.conf.j2` template will be identical in structure to `site.conf.erb`. The `sites-available`/`sites-enabled` symlink pattern is handled by `ansible.builtin.file` with `state: link`.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` resource (`resources/lineinfile.rb`) that provides match-and-replace or append-if-absent file-line management with optional backup. This is a direct functional equivalent of Ansible's built-in `ansible.builtin.lineinfile` module — no custom implementation is needed in Ansible.
- **`sed`-based sshd_config modification**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed -i` shell commands. While functional, this is fragile. The Ansible `ansible.builtin.lineinfile` module with `regexp` and `line` parameters provides an exact semantic equivalent and is idempotent by design.
- **PostgreSQL idempotency**: The `create_db_user` execute block uses `|| true` to suppress errors on re-runs, which is not truly idempotent (it will attempt the `CREATE USER` and `CREATE DATABASE` commands every run). In Ansible, use the `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **Git-based application deployment**: The `fastapi-tutorial` cookbook uses Chef's `git` resource to clone/sync the application. The Ansible `ansible.builtin.git` module is a direct equivalent. Care must be taken with the `update` parameter to avoid overwriting local changes, and the `version: main` pin should be reviewed for production stability (a tagged release is preferable).
- **systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, use `ansible.builtin.systemd` with `daemon_reload: true` in the task that deploys the unit file, or trigger it via a handler.
- **Cross-platform package names**: Package names differ between Debian (`redis-server`, `python3-pip`, `libpq-dev`) and RHEL/Fedora (`redis`, `python3-pip`, `postgresql-devel`). Ansible roles must use `vars/Debian.yml` and `vars/RedHat.yml` variable files loaded via `include_vars` with `ansible_os_family` to abstract package name differences.
- **`www-data` vs. `nginx` user**: The `nginx.rb` recipe sets document root ownership to `www-data:www-data`, which is the Debian/Ubuntu Nginx user. On RHEL/Fedora the Nginx process runs as `nginx:nginx`. The Ansible role must conditionally set the web user based on `ansible_os_family`.

---

### Migration Order

The following order minimises dependency risk and allows incremental validation at each stage:

1. **`nginx-multisite` → Ansible role `nginx_multisite`** *(Foundation — no upstream service dependencies)*
   - Implement security hardening tasks first (UFW, fail2ban, sysctl, SSH) as a standalone `security` role that can be reused
   - Implement Nginx installation, global config, and security snippet
   - Implement SSL certificate generation using `community.crypto` modules
   - Implement per-site virtual host configuration loop
   - Validate with Vagrant: confirm all three HTTPS vhosts respond, security headers present, fail2ban active

2. **`cache` → Ansible role `cache`** *(Independent service, no dependency on nginx or fastapi)*
   - Implement Memcached installation and service management
   - Implement Redis installation with Jinja2-templated `redis.conf` (password from Vault, no deprecated directives)
   - Validate Redis authentication and Memcached connectivity

3. **`fastapi-tutorial` → Ansible role `fastapi_tutorial`** *(Highest complexity; depends on PostgreSQL being available)*
   - Create dedicated `fastapi` system user and group
   - Install system packages (Python 3, venv, git, PostgreSQL)
   - Configure and start PostgreSQL service
   - Provision database and user via `community.postgresql` modules (credentials from Vault)
   - Clone application repository and set up virtual environment
   - Deploy `.env` file (mode `0600`, owned by `fastapi` user, credentials from Vault)
   - Deploy and enable systemd unit running as `fastapi` user
   - Validate API endpoint responds on port 8000

4. **Integration playbook + Vagrant validation** *(Combines all three roles)*
   - Write top-level `site.yml` playbook applying all roles in order
   - Migrate `solo.json` site/security attributes to `group_vars/all.yml`
   - Update `Vagrantfile` to use `ansible_local` provisioner pointing to `site.yml`
   - Replace `vagrant-provision.sh` with Vagrant Ansible provisioner block
   - End-to-end smoke test: all vhosts reachable, FastAPI API functional, Redis/Memcached responding

---

### Assumptions

1. **Target OS standardisation**: The Vagrantfile uses Fedora 42 but `vagrant-provision.sh` uses `apt-get`, suggesting the development environment may be inconsistent. It is assumed the team will standardise on either Ubuntu 22.04 LTS or Fedora/RHEL 9 before migration begins. The migration plan should be revisited once the target OS is confirmed, as package names and service user names differ.
2. **Self-signed certificates are acceptable for all environments**: The current setup generates self-signed certificates for all three vhosts. It is assumed this is intentional for the development/internal cluster use case. If any vhost is publicly accessible, a Let's Encrypt ACME workflow must be added to the migration scope.
3. **Redis single-instance, no clustering**: The `cache` cookbook configures a single Redis instance on port 6379. No Sentinel or Cluster configuration is present. It is assumed this single-instance model is sufficient and no HA Redis topology is required.
4. **Memcached default configuration is sufficient**: The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides, implying default Memcached settings (port 11211, 64 MB memory, localhost binding) are acceptable. This assumption should be confirmed before writing the Ansible role.
5. **The FastAPI GitHub repository remains publicly accessible**: The `fastapi-tutorial` cookbook clones `https://github.com/dibanez/fastapi_tutorial.git` at the `main` branch. It is assumed this repository will remain available and that `main` is a stable reference. For production use, a pinned tag or commit SHA is strongly recommended.
6. **PostgreSQL version is OS-default**: No specific PostgreSQL version is pinned in the cookbook. It is assumed the OS-default PostgreSQL package version is acceptable. If a specific version is required, the Ansible role must add the official PostgreSQL apt/yum repository.
7. **No Chef Server or Chef Automate in use**: The stack uses Chef Solo exclusively (`chef-solo`, `solo.rb`, `solo.json`). There is no Chef Server, data bags, Chef Vault, or encrypted data bags to migrate. All node attributes come from `solo.json`.
8. **The `ssl_certificate` community cookbook is not actively used**: It appears in `Policyfile.rb` and `Policyfile.lock.json` but is commented out in `Berksfile` and not called in any recipe. It is assumed this dependency is vestigial and can be dropped entirely in the Ansible migration.
9. **The `selinux` cookbook is a no-op on Ubuntu**: The `selinux` cookbook is pulled in transitively by `redisio` but has no effect on Debian/Ubuntu systems. If the target is RHEL/Fedora, SELinux policy for Redis (allowing port 6379, log directory access) must be explicitly handled in the Ansible `cache` role.
10. **The `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/` directory is tooling scaffolding**: This directory contains duplicate configuration files and a prior draft migration plan. It is assumed this is generated by the X2Ansible tooling (as described in `project-plan.md`) and has no runtime role. It will not be migrated.
11. **Document root path discrepancy**: `solo.json` defines document roots as `/var/www/{site}` while `attributes/default.rb` defines them as `/opt/server/{test,ci,status}`. The `solo.json` values override cookbook defaults at runtime. It is assumed `/var/www/` paths are the intended production values and will be used in Ansible `group_vars`.
12. **No monitoring or log aggregation is in scope**: The current stack has no monitoring agent, log shipper, or alerting configuration. It is assumed these are out of scope for this migration.
