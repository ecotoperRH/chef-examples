# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through a Vagrant/libvirt development environment running **Fedora 42**.

The infrastructure covers four distinct functional areas: a hardened multi-site Nginx reverse proxy with SSL, a Redis + Memcached caching layer, a Python FastAPI application backed by PostgreSQL, and OS-level security hardening (UFW, fail2ban, sysctl, SSH). All three cookbooks are version-locked at `1.0.0` and are self-contained with no cross-cookbook dependencies, making them strong candidates for independent, parallel migration tracks.

**Overall migration complexity: Medium.** The Chef resources used throughout are idiomatic and map cleanly to Ansible built-in modules. The primary challenges are: a hardcoded Redis config post-processing hack, self-signed certificate generation logic, multi-platform support (Ubuntu 18.04+, CentOS 7+, Fedora 42), and several plaintext credentials embedded directly in recipe code that must be moved to Ansible Vault before migration is considered complete.

**Estimated timeline: 3–4 weeks** for a full migration including testing, broken down as:
- Week 1: `nginx-multisite` role (security hardening + Nginx + SSL + virtual hosts)
- Week 2: `cache` role (Memcached + Redis with auth)
- Week 3: `fastapi-tutorial` role (PostgreSQL + Python app + systemd)
- Week 4: Integration testing, CI pipeline setup, validation, and documentation

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server provisioning with multi-site virtual host configuration, per-site SSL/TLS self-signed certificate generation, HTTP-to-HTTPS redirect enforcement, and comprehensive OS-level security hardening
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - Installs and configures Nginx from the OS package manager (not the Chef `nginx` Supermarket cookbook — the community cookbook is declared as a dependency in `Policyfile.rb` but the actual recipe installs via `package 'nginx'` directly)
        - Renders `nginx.conf` and a global `security.conf` from ERB templates (rate limiting zones, buffer overflow protections, SSL session settings, `server_tokens off`)
        - Manages three named virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) each with SSL enabled, HTTP→HTTPS redirect, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy)
        - Generates per-site self-signed RSA-2048 certificates via `openssl req -x509` with a 365-day validity; certificates stored under `/etc/ssl/certs`, private keys under `/etc/ssl/private` with `0710` permissions and `ssl-cert` group ownership
        - Deploys static `index.html` files for each virtual host from cookbook `files/default/{ci,status,test}/index.html`
        - Installs and configures `fail2ban` with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` (3600s ban, 3 retries)
        - Configures `ufw` firewall: default deny, allow SSH/HTTP/HTTPS
        - Applies kernel-level security hardening via `sysctl.d/99-security.conf` (IP spoofing protection, ICMP redirect blocking, TCP SYN cookie protection, IPv6 disable, martian logging)
        - Conditionally disables SSH root login and password authentication based on node attributes
        - Includes a custom `lineinfile` LWRP resource (equivalent to Ansible's `lineinfile` module)

- **cache**:
    - Description: Dual caching layer provisioning Memcached (via the community cookbook) and Redis (via the `redisio` community cookbook) with password authentication and a post-install configuration sanitisation workaround
    - Path: `cookbooks/cache`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - Delegates Memcached installation and service management entirely to the `memcached` (~> 6.0) community cookbook via `include_recipe 'memcached'`
        - Configures a single Redis instance on port `6379` with `requirepass` authentication via the `redisio` (~> 7.2.4) community cookbook
        - Creates `/var/log/redis` directory with `redis:redis` ownership
        - Applies a `ruby_block` post-processing hack to `/etc/redis/6379.conf` that strips deprecated `replica-*` and `client-output-buffer-limit` directives that the `redisio` cookbook writes but the installed Redis version rejects — this is the most complex migration challenge in the entire repository
        - Enables the Redis service via `include_recipe 'redisio::enable'`
        - Depends on the `selinux` cookbook (pulled transitively through `redisio`) — relevant for CentOS/RHEL targets

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI web application from a public GitHub repository, including system package installation, Python virtual environment setup, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial` using the Chef `git` resource with `:sync` action
        - Creates a Python virtual environment at `/opt/fastapi-tutorial/venv` and installs dependencies from `requirements.txt`
        - Enables and starts the `postgresql` service
        - Provisions PostgreSQL user `fastapi` with password `fastapi_password`, database `fastapi_db`, and full privileges — executed via `sudo -u postgres psql` shell commands with `|| true` guards for idempotency
        - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` with mode `0644` (world-readable — security issue)
        - Creates `/etc/systemd/system/fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as `root` user (privilege issue)
        - Triggers `systemctl daemon-reload` via notification and enables/starts the `fastapi-tutorial` service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Lists all 3 local cookbooks by path and 3 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but active in `Policyfile.rb`. Not needed post-migration; replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`. This is the authoritative source of truth for execution order and dependency versions.
- `Policyfile.lock.json`: Fully resolved and pinned dependency graph. Locks: `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. Serves as the reference for exact versions to replicate in Ansible Galaxy `requirements.yml`.
- `solo.json`: Chef Solo node JSON. Defines the run list and all node attribute overrides: three virtual host definitions (document roots under `/var/www/`, SSL enabled), SSL certificate/key paths, and security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth`). This file maps directly to Ansible `group_vars` or role `vars`.
- `solo.rb`: Chef Solo configuration. Sets `file_cache_path`, `cookbook_path` (supports vendored cookbooks under `cookbooks-*/cookbooks`), log level, and log destination. No migration artifact needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant development environment definition. Specifies `generic/fedora42` box, hostname `chef-nginx`, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, libvirt provider with 2 vCPUs and 2 GB RAM, rsync folder sync, and shell provisioner. For Ansible migration, this can be updated to use the `ansible` provisioner pointing at the new playbook, or replaced with a standalone `ansible-playbook` invocation.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, vendors cookbook dependencies, and runs `chef-solo`. Post-migration this script should be replaced with an Ansible provisioner block or a simple `ansible-playbook` call.
- `x2a-rules/c0dd620f-0b0e-4cd0-9fe9-e0d67449b466.md`: Project-level migration rule requiring that all migrated Ansible projects include a GitHub Actions CI workflow (`.github/workflows/ansible-ci.yml`) that runs `ansible-lint roles/ --strict` on every pull request targeting `main`. **This rule is mandatory and must be implemented as part of the migration.**

---

### Target Details

- **Operating System**: The Vagrant box is `generic/fedora42` (Fedora 42), making it the primary tested target. Cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `ufw` firewall and `www-data` user references in `nginx-multisite` are Debian/Ubuntu-specific; `firewalld` and the `nginx` user are the RHEL/Fedora equivalents. The Ansible roles must handle both families via `ansible_os_family` conditionals, or the scope must be narrowed to Fedora/RHEL only.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. The `generic/fedora42` Vagrant box is a libvirt-compatible image.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoint references, or cloud-init configurations are present. The infrastructure is designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0, locked 12.3.1)**: The community cookbook is declared as a dependency but the `nginx-multisite` recipes install Nginx directly via `package 'nginx'` and manage all configuration through local ERB templates. Replace with Ansible `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service` modules. No Galaxy role required; all templates already exist in the cookbook and can be converted to Jinja2.
- **memcached (~> 6.0, locked 6.1.0)**: Fully delegated via `include_recipe 'memcached'`. Replace with the `geerlingguy.memcached` Ansible Galaxy role or direct `ansible.builtin.package` + `ansible.builtin.service` tasks. Configuration is minimal (default settings), so a Galaxy role may be overkill.
- **redisio (~> 7.2.4, locked 7.2.4)**: Handles Redis installation, configuration file generation, and service enablement. Replace with `geerlingguy.redis` Galaxy role or direct package/template/service tasks. The post-install config-stripping hack (see Technical Challenges) must be replicated using `ansible.builtin.lineinfile` with `regexp` + `state: absent` or a custom template that never emits the deprecated directives.
- **ssl_certificate (~> 2.1, locked 2.1.0)**: Declared in `Policyfile.rb` but not explicitly called in any recipe (certificate generation is done inline via `openssl` shell commands in `ssl.rb`). Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection for idiomatic, idempotent certificate management.
- **selinux (locked 6.2.4)**: Pulled transitively by `redisio` for RHEL/CentOS targets. Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` for any required SELinux boolean adjustments (e.g., allowing Redis network connections).

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line 6): This plaintext credential is embedded directly in recipe source code. **Must be extracted to Ansible Vault** before migration. Create a vault variable `vault_redis_password` and reference it in the role's `vars/main.yml`. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`fastapi_password` appears 3 times in `cookbooks/fastapi-tutorial/recipes/default.rb`): The password is used in the `psql` provisioning command and written verbatim into `/opt/fastapi-tutorial/.env`. **Must be extracted to Ansible Vault** as `vault_fastapi_db_password`. **1 credential (used in 3 locations) detected.**
- **World-readable `.env` file**: `/opt/fastapi-tutorial/.env` is created with mode `0644`, exposing `DATABASE_URL` (including the password) to all local users. The Ansible equivalent must set mode `0600` and assign ownership to the application service user (not `root`).
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant privilege escalation risk. The Ansible migration should create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed SSL certificates**: Generated via inline `openssl` shell commands with a 365-day validity and a hardcoded subject (`/C=US/ST=Example/...`). Acceptable for development; production deployments must replace with CA-signed or Let's Encrypt certificates. The Ansible migration should use `community.crypto` modules and parameterise the subject fields. Certificate subject details (org, country, etc.) should be stored as role variables.
- **SSH hardening**: `security.rb` conditionally disables root login and password authentication by directly `sed`-ing `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` or the `devsec.hardening.ssh_hardening` Galaxy role for a more robust approach.
- **UFW firewall management**: `ufw` is Debian/Ubuntu-specific. On Fedora 42 (the actual Vagrant target), `firewalld` is the default. The migration must implement an `ansible_os_family`-based conditional: `community.general.ufw` for Debian/Ubuntu, `ansible.posix.firewalld` for RedHat/Fedora.
- **fail2ban configuration**: The `jail.local` template is static (no node attribute interpolation). Migrate directly as an Ansible `files/` static file or a minimal Jinja2 template. Ensure the `nginx-botsearch` filter is available on the target OS.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template is also static. Migrate using `ansible.posix.sysctl` module tasks (one task per parameter) for full idempotency, or deploy the file via `ansible.builtin.copy` and notify a handler to run `sysctl -p`.
- **No encrypted data bags or Chef Vault usage detected**: Secrets are stored as plaintext in recipe code, not in Chef's secret management systems. This makes extraction straightforward but underscores the urgency of moving to Ansible Vault.
- **Total credentials requiring Ansible Vault protection: 2** (Redis password, PostgreSQL/FastAPI DB password).

### Technical Challenges

- **Redis config post-processing hack**: `cache/recipes/default.rb` uses a `ruby_block` to read, regex-substitute, and rewrite `/etc/redis/6379.conf` after `redisio` generates it, removing deprecated `replica-*`, `client-output-buffer-limit`, and `replica-priority` directives. In Ansible, the cleanest equivalent is to manage the Redis configuration file entirely via a custom Jinja2 template (bypassing the Galaxy role's template), or to use multiple `ansible.builtin.lineinfile` tasks with `regexp` and `state: absent`. The root cause (redisio writing directives unsupported by the installed Redis version) should be investigated — if the target Redis package version is known, the template can simply omit those directives.
- **Multi-platform support (Debian vs. RHEL/Fedora)**: Several resources are OS-family-specific: `ufw` vs. `firewalld`, `www-data` user vs. `nginx` user, `apt` vs. `dnf` package names (e.g., `libpq-dev` on Debian vs. `postgresql-devel` on RHEL), and `sshd` service name differences. All Ansible roles must use `ansible_os_family` or `ansible_distribution` conditionals, or the scope must be explicitly narrowed to Fedora 42 only (matching the Vagrantfile).
- **Custom `lineinfile` LWRP**: `nginx-multisite` defines a custom `lineinfile` resource in `resources/lineinfile.rb` that replicates Ansible's own `lineinfile` module behaviour (match-and-replace or append, with optional backup). This resource has no usages detected in the current recipes — it appears to be a utility resource. It can be safely dropped in the Ansible migration since `ansible.builtin.lineinfile` provides identical functionality natively.
- **Nginx `sites-available` / `sites-enabled` symlink pattern**: The `sites.rb` recipe creates config files in `/etc/nginx/sites-available/` and symlinks them into `/etc/nginx/sites-enabled/`. This pattern is native to Debian/Ubuntu Nginx packages but is absent from the RHEL/Fedora Nginx package layout (which uses `/etc/nginx/conf.d/`). The Ansible role must handle this difference, either by standardising on `conf.d/` or by creating the `sites-available`/`sites-enabled` directories on RHEL targets.
- **Git-based application deployment with `pip install`**: The `fastapi-tutorial` recipe clones a public GitHub repository and runs `pip install -r requirements.txt` on every Chef run (no version pinning on the pip step). In Ansible, use `ansible.builtin.git` with a pinned `version` (commit SHA or tag, not just `main`) and `ansible.builtin.pip` with `virtualenv` parameter. Consider whether the application should be deployed from a versioned artifact (wheel/tarball) rather than a live Git clone for production stability.
- **PostgreSQL provisioning via raw psql shell commands**: The recipe uses `sudo -u postgres psql -c "..."` with `|| true` for idempotency. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` collection, which provide proper idempotency, privilege management, and no shell injection risk.
- **`systemctl daemon-reload` notification ordering**: The Chef recipe uses `:immediately` notification to reload systemd before enabling the service. In Ansible, `ansible.builtin.systemd` with `daemon_reload: true` handles this atomically. Ensure the handler fires before the service enable/start task.
- **Document root path discrepancy**: The `attributes/default.rb` defines document roots as `/opt/server/{test,ci,status}`, but `solo.json` overrides them to `/var/www/{test,ci,status}.cluster.local`. The Ansible role variables must use the `solo.json` values (`/var/www/`) as the canonical source of truth, since that is what Chef Solo actually applies at runtime.

### Migration Order

The three cookbooks have no cross-dependencies and can theoretically be migrated in parallel. However, the following sequential order is recommended to build confidence and reuse patterns:

1. **`nginx-multisite` → Ansible role: `nginx_multisite`** *(Week 1 — Medium complexity, highest value)*
   - Establishes the security hardening baseline (UFW/firewalld, fail2ban, sysctl, SSH) that all other roles benefit from
   - Converts 5 ERB templates to Jinja2 (straightforward, templates are already mostly static)
   - Implements `community.crypto` certificate generation replacing inline `openssl` shell commands
   - Resolves the `www-data` vs. `nginx` user and `sites-enabled` vs. `conf.d` platform differences
   - Deliverable: `roles/nginx_multisite/` with tasks split into `security.yml`, `nginx.yml`, `ssl.yml`, `sites.yml` mirroring the original recipe structure

2. **`cache` → Ansible role: `cache`** *(Week 2 — Low-to-medium complexity)*
   - Migrate Memcached first (simplest: package + service, no configuration customisation detected)
   - Migrate Redis second, resolving the config post-processing hack via a custom template
   - Extract `redis_secure_password_123` to Ansible Vault
   - Deliverable: `roles/cache/` with `tasks/memcached.yml` and `tasks/redis.yml`, `vars/main.yml` referencing vault variable

3. **`fastapi-tutorial` → Ansible role: `fastapi_tutorial`** *(Week 3 — High complexity)*
   - Most complex role: involves PostgreSQL provisioning, Python venv management, Git deployment, and systemd service
   - Extract `fastapi_password` to Ansible Vault
   - Fix `.env` file permissions (0644 → 0600) and service user (root → dedicated `fastapi` user)
   - Use `community.postgresql` collection modules instead of raw psql shell commands
   - Deliverable: `roles/fastapi_tutorial/` with handlers for daemon-reload and service restart

4. **Integration & CI** *(Week 4)*
   - Write a top-level `site.yml` playbook mirroring the `Policyfile.rb` run list order
   - Update `Vagrantfile` to use the `ansible` provisioner instead of `vagrant-provision.sh`
   - Implement the mandatory `.github/workflows/ansible-ci.yml` GitHub Actions workflow running `ansible-lint roles/ --strict` (required by `x2a-rules/c0dd620f-0b0e-4cd0-9fe9-e0d67449b466.md`)
   - Run full end-to-end validation against the Fedora 42 Vagrant box
   - Document any manual steps (e.g., `/etc/hosts` entries for `*.cluster.local` resolution)

### Assumptions

1. **Fedora 42 is the primary target OS** for the Ansible migration, matching the `generic/fedora42` Vagrant box. Ubuntu/CentOS support declared in `metadata.rb` is treated as secondary; platform conditionals will be added where feasible but Fedora 42 is the acceptance test environment.
2. **`ufw` is not available on Fedora 42** by default; `firewalld` is the native firewall manager. The `nginx-multisite` security recipe's `ufw` tasks must be replaced with `ansible.posix.firewalld` tasks for the Fedora target. If Ubuntu support is required, an `ansible_os_family == "Debian"` branch using `community.general.ufw` must also be implemented.
3. **The `www-data` user does not exist on Fedora 42**; Nginx runs as the `nginx` user on RHEL-family systems. All file ownership tasks in `nginx.rb` that reference `www-data` must be conditionalised or replaced with `nginx`.
4. **Self-signed certificates are acceptable** for the development/test environment represented by this repository. No production certificate management (Let's Encrypt, internal CA) is in scope for this migration unless explicitly requested.
5. **The FastAPI application source at `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) remains publicly accessible** and contains a valid `requirements.txt`. If the repository becomes private or the branch is renamed, the `fastapi_tutorial` role will require credential configuration and a `version` pin update.
6. **No Redis clustering or Sentinel configuration is required**; the single-instance setup on port 6379 with password authentication is the complete target state.
7. **No Memcached configuration customisation is required** beyond what the default `memcached` cookbook provides (default port 11211, default memory allocation). If tuning is needed, it must be scoped separately.
8. **The document roots defined in `solo.json`** (`/var/www/{test,ci,status}.cluster.local`) are the canonical values, overriding the `attributes/default.rb` defaults (`/opt/server/{test,ci,status}`). Ansible role defaults will use the `solo.json` values.
9. **The `ssl_certificate` community cookbook** (locked at 2.1.0) is declared in `Policyfile.rb` but never explicitly called in any recipe. It is assumed to be an unused/vestigial dependency and will not be migrated.
10. **The custom `lineinfile` LWRP** in `cookbooks/nginx-multisite/resources/lineinfile.rb` has no detected call sites in the current recipes and is assumed to be dead code. It will not be migrated; `ansible.builtin.lineinfile` is available natively.
11. **`/etc/hosts` entries** for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` are commented out in the `Vagrantfile`. It is assumed that DNS resolution for these names is handled externally (e.g., local `/etc/hosts` on the developer's machine) and is out of scope for the Ansible role. An optional task or documentation note will be included.
12. **The GitHub Actions CI rule** in `x2a-rules/c0dd620f-0b0e-4cd0-9fe9-e0d67449b466.md` is treated as a hard requirement: the migrated repository must include `.github/workflows/ansible-ci.yml` running `ansible-lint roles/ --strict` on all pull requests to `main`.
13. **No Ansible Tower / AWX integration** is assumed. The migration targets `ansible-playbook` CLI execution, consistent with the current Chef Solo (agentless, push-based) model.
14. **The `selinux` cookbook** (pulled transitively by `redisio`) implies SELinux may be enforcing on CentOS/RHEL targets. On Fedora 42, SELinux is enabled by default in enforcing mode. The `cache` role must account for SELinux contexts for Redis data directories and log paths, using `ansible.posix.seboolean` or `community.general.sefcontext` as needed.
