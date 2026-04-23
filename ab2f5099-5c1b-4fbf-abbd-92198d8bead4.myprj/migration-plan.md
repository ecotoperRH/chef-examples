# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack composed of **3 local cookbooks** and **5 external Supermarket dependencies**, all orchestrated by a single `Policyfile.rb` (`nginx-multisite-policy`). The stack provisions a multi-site Nginx web server with SSL termination, a Redis + Memcached caching layer, and a Python FastAPI application backed by PostgreSQL — all running on a single Vagrant-managed VM (Fedora 42 / libvirt).

The migration to Ansible is **straightforward to moderate in complexity**. All three cookbooks are self-contained, well-scoped, and free of Chef Server dependencies (Chef Solo only). The external cookbook dependencies (`nginx`, `memcached`, `redisio`, `ssl_certificate`, `selinux`) map cleanly to native Ansible modules (`ansible.builtin`, `community.general`), eliminating the need for any third-party Ansible Galaxy roles. The primary challenges are: replacing the custom `lineinfile` Chef resource with Ansible's native equivalent, migrating hardcoded credentials to Ansible Vault, and replicating the Redis config post-processing hack currently done via a `ruby_block`.

**Estimated migration timeline: 3–5 days** for a single engineer familiar with Ansible, broken down as:
- `nginx-multisite`: ~2 days (most complex — 5 recipes, 5 templates, custom resource, security hardening)
- `cache`: ~1 day (Redis + Memcached, includes credential and config-patch logic)
- `fastapi-tutorial`: ~1 day (Python app deployment, PostgreSQL setup, systemd service)
- Integration, testing, and Vagrant re-wiring: ~0.5–1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server configured with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), full security hardening via UFW firewall, Fail2Ban intrusion prevention, SSH hardening, and kernel-level sysctl security tuning. Generates self-signed TLS certificates per virtual host using OpenSSL. Serves static HTML content per site from cookbook files.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef (v1.0.0, Chef >= 16.0)
  - Key Features:
    - 5 sub-recipes: `default`, `nginx`, `security`, `ssl`, `sites`
    - Per-site Nginx virtual host config via ERB template (`site.conf.erb`) with HTTP→HTTPS redirect, TLS 1.2/1.3, HSTS, and full security headers (X-Frame-Options, CSP, X-XSS-Protection, Referrer-Policy)
    - Global `nginx.conf.erb` with gzip, logging, and virtual host includes
    - `security.conf.erb` with rate limiting zones (`login`, `api`), buffer overflow protections, and global SSL settings
    - Self-signed certificate generation per site via `openssl req -x509` (RSA 2048, 365-day validity)
    - UFW firewall: default deny, allow SSH/HTTP/HTTPS
    - Fail2Ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch` (`fail2ban.jail.local.erb`)
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` on `sshd_config`
    - Kernel hardening via `sysctl-security.conf.erb`: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
    - Custom `lineinfile` Chef resource (reimplements Ansible's native `lineinfile` module)
    - Static site content: 3 HTML files (`ci/index.html`, `status/index.html`, `test/index.html`)
    - Attribute-driven site definitions with configurable `document_root` and `ssl_enabled` per site

- **cache**:
  - Description: Caching services layer configuring both Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication. Includes a post-install Ruby block hack to strip deprecated Redis configuration directives that the `redisio` cookbook writes but the installed Redis version rejects.
  - Path: `cookbooks/cache`
  - Technology: Chef (v1.0.0, Chef >= 16.0)
  - Key Features:
    - Delegates Memcached installation and configuration to the `memcached ~> 6.0` community cookbook
    - Configures Redis on port 6379 with `requirepass` authentication
    - Creates `/var/log/redis` directory with correct `redis:redis` ownership
    - Delegates Redis installation to `redisio ~> 7.2.4` community cookbook, then calls `redisio::enable`
    - Post-install `ruby_block` that patches `/etc/redis/6379.conf` by stripping deprecated directives: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
    - **Hardcoded Redis password**: `redis_secure_password_123` (must be migrated to Ansible Vault)

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git-based source checkout, Python virtual environment setup, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation and enablement.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef (v1.0.0, Chef >= 16.0)
  - Key Features:
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial`
    - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs from `requirements.txt`
    - Enables and starts `postgresql` service
    - Provisions PostgreSQL user `fastapi` with password `fastapi_password` and database `fastapi_db` via `sudo -u postgres psql` shell commands (idempotent with `|| true`)
    - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (mode `0644` — **insecure, world-readable**)
    - Creates systemd unit `/etc/systemd/system/fastapi-tutorial.service`: runs `uvicorn app.main:app --host 0.0.0.0 --port 8000` as `root` (security concern)
    - Runs `systemctl daemon-reload` on service file change
    - Enables and starts `fastapi-tutorial` service
    - **Hardcoded PostgreSQL credentials**: `fastapi` / `fastapi_password` (must be migrated to Ansible Vault)

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all 3 local cookbooks and 4 external Supermarket dependencies (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out in Berksfile but active in Policyfile). Migration consideration: replaced entirely by Ansible Galaxy `requirements.yml` or eliminated if using only built-in modules.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook versions. Migration equivalent: Ansible playbook with `roles:` list or `import_role` tasks.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Migration consideration: version pinning should be replicated in Ansible role `meta/main.yml` and `requirements.yml`.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides — defines the 3 Nginx virtual hosts with their document roots and SSL flags, SSL certificate/key paths, and security settings (fail2ban, ufw, SSH hardening). Migration equivalent: Ansible `group_vars/all.yml` or host-specific `host_vars/`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No direct Ansible equivalent needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync-based folder sync. Migration consideration: the Vagrantfile can be adapted to use the `ansible_local` or `ansible` Vagrant provisioner instead of the shell provisioner, pointing at the new playbook.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef, Berkshelf, runs `berks vendor`, and executes `chef-solo`. Migration equivalent: replaced by a simple `ansible-playbook` invocation or Vagrant's built-in Ansible provisioner block.
- `project-plan.md`: Internal X2Ansible tool specification document. Not part of the infrastructure; no migration action required.

---

### Target Details

- **Operating System**: Ubuntu (>= 18.04) or CentOS (>= 7.0) per `metadata.rb` `supports` declarations. The Vagrant environment uses **Fedora 42** (`generic/fedora42`). Security recipes use `ufw` and reference `/var/log/auth.log`, which are Debian/Ubuntu conventions — indicating the **primary target is Ubuntu**. The `www-data` user in `nginx.rb` also confirms a Debian/Ubuntu assumption. For Ansible migration, target **Ubuntu 22.04 LTS** unless the team explicitly requires RHEL/Fedora (which would require substituting `ufw` → `firewalld`, `www-data` → `nginx`, and `apt` → `dnf`).
- **Virtual Machine Technology**: **KVM/libvirt** via Vagrant (`config.vm.provider "libvirt"`). VM is named `chef-nginx-multisite`, 2 vCPU, 2 GB RAM, private network `192.168.121.10`.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs detected. This is a local/on-premises development environment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with `ansible.builtin.package` to install `nginx` from the OS package manager, `ansible.builtin.template` for `nginx.conf` and `security.conf`, and `ansible.builtin.service` for lifecycle management. No Galaxy role needed.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` (`memcached`) and `ansible.builtin.service`. Configuration is minimal (default settings used); add `ansible.builtin.lineinfile` or a template if tuning is needed.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (`redis-server` on Ubuntu), `ansible.builtin.template` for `/etc/redis/6379.conf` (write the config directly and correctly, eliminating the post-install patch hack entirely), and `ansible.builtin.service`. The `requirepass` directive is set directly in the template.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` (or `openssl_certificate`) Ansible modules for self-signed cert generation. Alternatively, use `ansible.builtin.command` with `openssl req -x509` and `creates:` for idempotency, matching the current Chef behavior exactly.
- **selinux (6.2.4, Chef Supermarket)**: Transitive dependency of `redisio`. On Ubuntu targets, SELinux is not active — this dependency can be dropped entirely. If migrating to RHEL/Fedora, use `ansible.posix.selinux` and `community.general.selinux_permissive`.

### Security Considerations

- **Hardcoded Redis password (`redis_secure_password_123`)** in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`): This credential must be extracted and stored in **Ansible Vault** as `vault_redis_password`. Referenced in the Redis config template and any application connecting to Redis.
- **Hardcoded PostgreSQL credentials (`fastapi` / `fastapi_password`)** in `cookbooks/fastapi-tutorial/recipes/default.rb`: Appear in 3 places — the `psql` provisioning commands, the `.env` file content, and the `DATABASE_URL`. Must be stored in Ansible Vault as `vault_postgres_user` and `vault_postgres_password`.
- **World-readable `.env` file**: `/opt/fastapi-tutorial/.env` is created with mode `0644`, exposing `DATABASE_URL` (including the password) to all local users. In Ansible, this file should be deployed with mode `0600` and owned by the service user (not `root`).
- **FastAPI service running as `root`**: The systemd unit sets `User=root`. In Ansible, create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed TLS certificates**: Generated via `openssl req -x509` with a 365-day validity and hardcoded subject fields (`/C=US/ST=Example/...`). These are development-only certificates. In Ansible, parameterize the subject fields as variables. For production, integrate `community.crypto.acme_certificate` (Let's Encrypt) or a proper PKI.
- **SSH hardening via `sed`**: The current approach uses raw `sed` on `/etc/ssh/sshd_config`. In Ansible, use `ansible.builtin.lineinfile` with `regexp:` for idempotent, auditable SSH config management.
- **UFW firewall management**: Currently driven by `execute` resources with `not_if` guards. In Ansible, use `community.general.ufw` module for fully declarative, idempotent firewall rule management.
- **Fail2Ban configuration**: Templated `jail.local` with 4 active jails. Migrate the ERB template directly to a Jinja2 template (`.j2`) — the conversion is 1:1 since no Ruby logic is used inside the template.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template contains no ERB logic (pure static content). Migrate as a static `ansible.builtin.copy` file or use `ansible.posix.sysctl` module for individual parameter management.
- **Credentials detected per module**:
  - `cache`: 1 credential (Redis password — hardcoded string in recipe)
  - `fastapi-tutorial`: 2 credentials (PostgreSQL username + password — hardcoded in recipe and `.env` file, 3 occurrences total)
  - `nginx-multisite`: 0 runtime credentials (SSL cert subject fields are non-sensitive placeholder values)

### Technical Challenges

- **Redis config post-install patch (`ruby_block "fix_redis_config"`)**: The `cache` cookbook uses a Ruby block to strip deprecated directives written by the `redisio` cookbook. This is a workaround for a version mismatch between `redisio 7.2.4` and the installed Redis server. In Ansible, this problem is eliminated entirely by writing the Redis configuration template directly (without delegating to a community cookbook), including only the directives supported by the target Redis version. No patching needed.
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements line-in-file editing with backup support. This maps directly and completely to Ansible's built-in `ansible.builtin.lineinfile` module, which is more robust and idempotent. The custom resource is not called anywhere in the current recipes (it appears to be a utility resource available for use), so migration impact is low — simply document its Ansible equivalent.
- **Attribute override between `attributes/default.rb` and `solo.json`**: The cookbook defines default document roots as `/opt/server/{site}` in `attributes/default.rb`, but `solo.json` overrides them to `/var/www/{site}`. Ansible does not have this two-layer attribute system. The migration must pick one canonical source of truth — recommend `group_vars/all.yml` for defaults and `host_vars/` for overrides, clearly documenting the precedence.
- **`node['nginx']['sites']` hash iteration**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, deploy files, and generate per-site Nginx configs. In Ansible, this maps to `loop:` or `with_dict:` over a `nginx_sites` variable defined in `group_vars`. The Jinja2 template for `site.conf.j2` is a near-direct port of `site.conf.erb`.
- **Vagrant provisioner swap**: `vagrant-provision.sh` installs Chef and runs `chef-solo`. This must be replaced with either the Vagrant `ansible` provisioner (requires Ansible on the host) or `ansible_local` provisioner (installs Ansible inside the VM). The `Vagrantfile` already contains a commented-out `chef_solo` provisioner block as a reference point.
- **OS mismatch — Fedora 42 vs. Ubuntu target**: The cookbooks declare Ubuntu/CentOS support, but the Vagrant box is `generic/fedora42`. The security recipes use `ufw` (Debian/Ubuntu tool) and reference `www-data` (Debian/Ubuntu Nginx user). On Fedora, `ufw` is not the default firewall (`firewalld` is). The Ansible migration should either: (a) switch the Vagrant box to `generic/ubuntu2204` to match the declared OS support, or (b) add conditional tasks using `ansible_os_family` to handle both Debian and RedHat families. **This is the highest-risk compatibility issue in the migration.**
- **PostgreSQL provisioning via shell**: `fastapi-tutorial` uses `sudo -u postgres psql -c "..."` with `|| true` for idempotency. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules for proper idempotent database and user management.
- **Git-based application deployment**: The cookbook uses Chef's `git` resource to sync `https://github.com/dibanez/fastapi_tutorial.git`. In Ansible, use `ansible.builtin.git` with `version: main` and `update: yes`. Ensure the target host has outbound internet access to GitHub, or mirror the repository internally.

### Migration Order

1. **`nginx-multisite` role** — Highest value, most visible component. Establishes the Ansible role skeleton, variable structure (`nginx_sites` dict, SSL paths), and Jinja2 template patterns that the other roles will follow. Security hardening sub-tasks (UFW, Fail2Ban, sysctl, SSH) can be extracted into a standalone `security` role for reuse. Migrate in this sub-order: `security` tasks → `nginx` install + config → `ssl` cert generation → `sites` virtual host loop.
2. **`cache` role** — Medium complexity. Migrate Memcached first (trivial: install + service), then Redis (template-based config, Vault-protected password, service). Eliminates the `ruby_block` hack by writing a clean Redis config template. Validate Redis authentication works before proceeding.
3. **`fastapi-tutorial` role** — Depends on PostgreSQL being available (installed within the same role). Migrate in this sub-order: system packages → PostgreSQL service + provisioning (using `community.postgresql` modules) → Git checkout → venv + pip install → `.env` file (Vault-protected, mode `0600`) → systemd unit (non-root user) → service enable/start.
4. **Integration playbook + Vagrant re-wiring** — Combine all 3 roles into a single `site.yml` playbook mirroring the original `run_list`. Update `Vagrantfile` to use the `ansible_local` provisioner pointing at `site.yml`. Validate all 3 sites are reachable over HTTPS and the FastAPI service responds on port 8000.

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS**, not Fedora 42. The cookbooks' `supports` declarations, use of `ufw`, `www-data` user, and `/var/log/auth.log` path all point to a Debian/Ubuntu environment. The Fedora Vagrant box appears to be an infrastructure convenience choice, not the intended production OS. If Fedora/RHEL is actually required, firewall and user management tasks must be adapted.
2. **Chef Solo only — no Chef Server**. The `solo.rb` and `vagrant-provision.sh` confirm this is a Chef Solo setup. There are no encrypted data bags, Chef Vault calls, or node search queries to migrate.
3. **The `ssl_certificate` Supermarket cookbook** is listed in `Policyfile.rb` and resolved in `Policyfile.lock.json` but is **commented out in `Berksfile`** and not called in any recipe. It is assumed to be an unused/planned dependency and will not be migrated.
4. **The custom `lineinfile` resource** (`cookbooks/nginx-multisite/resources/lineinfile.rb`) is defined but **never called** in any of the cookbook's recipes. It is assumed to be dead code or a utility left for future use. It will be documented as mapping to `ansible.builtin.lineinfile` but no active migration task is required.
5. **Self-signed certificates are acceptable** for the target environment (development/staging). No Let's Encrypt or internal CA integration is assumed. If production use is intended, certificate management must be redesigned.
6. **The FastAPI application source** (`https://github.com/dibanez/fastapi_tutorial.git`) is publicly accessible and the `main` branch is stable. If the repository is private or the branch name changes, the `ansible.builtin.git` task will need SSH key configuration or a deploy token.
7. **`solo.json` is the authoritative attribute source** for the 3 virtual host definitions (document roots `/var/www/{site}`), overriding the cookbook's `attributes/default.rb` defaults (`/opt/server/{site}`). The Ansible migration will use the `solo.json` values as the canonical defaults in `group_vars/all.yml`.
8. **Memcached requires no authentication** and uses default configuration. The `memcached` cookbook is included without any attribute overrides in `cache/recipes/default.rb`, implying default port (11211) and no SASL auth. This assumption should be confirmed before migration.
9. **The FastAPI application listens on port 8000** and is not fronted by Nginx in the current configuration (no Nginx proxy_pass to port 8000 exists in any recipe or template). It is assumed the application is accessed directly on port 8000, not through the Nginx virtual hosts. If a reverse proxy setup is intended, an additional Nginx location block must be added during migration.
10. **`www-data` is the Nginx worker user**. This is hardcoded in `nginx.conf.erb`. On RHEL/Fedora systems, the Nginx user is `nginx`. The Ansible template should parameterize this as `{{ nginx_user }}` with a default of `www-data`.
11. **No existing Ansible inventory or infrastructure** is assumed. The migration produces a greenfield Ansible project structure. If an existing Ansible setup is present, role naming and variable namespacing must be coordinated to avoid conflicts.
