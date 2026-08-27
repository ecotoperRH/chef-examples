# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo** infrastructure codebase that provisions a multi-service web stack on a single Vagrant-managed virtual machine. The policy (`nginx-multisite-policy`) orchestrates three local cookbooks — `nginx-multisite`, `cache`, and `fastapi-tutorial` — plus five external Chef Supermarket dependencies. The stack delivers: an Nginx reverse proxy serving three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a dual caching layer (Memcached + Redis), a FastAPI Python application backed by PostgreSQL, and a hardened OS baseline (UFW firewall, Fail2ban, SSH hardening, kernel sysctl tuning).

**Migration complexity: Medium.** The codebase is well-structured, self-contained, and uses no encrypted data bags or Chef Vault. The primary challenges are: replacing the `redisio` community cookbook's complex Redis configuration logic (including a documented config-file hack), translating the custom `lineinfile` Chef resource to the native Ansible `lineinfile` module, and managing two hardcoded credentials that must be moved to Ansible Vault. All Chef ERB templates translate directly to Jinja2 with minimal changes.

**Estimated timeline: 3–5 days** for a single engineer familiar with Ansible, or 1–2 days for a team of two.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that each require individual migration planning, plus **5 external Supermarket cookbook dependencies** that map to native Ansible modules or community roles.

---

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multi-virtual-host support, per-site SSL termination using self-signed certificates, HTTP-to-HTTPS redirect, security hardening headers (HSTS, X-Frame-Options, CSP, X-Content-Type-Options), gzip compression, OS-level firewall (UFW), Fail2ban intrusion prevention, SSH hardening, and kernel sysctl security tuning. Serves three subdomains: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, each with its own document root and static HTML landing page.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - `recipes/default.rb` — orchestrator that calls security → nginx → ssl → sites in order
    - `recipes/nginx.rb` — installs nginx, deploys `nginx.conf` and `security.conf` from ERB templates, creates per-site document roots, copies static `index.html` files, manages the `nginx` service
    - `recipes/ssl.rb` — creates `ssl-cert` group, manages `/etc/ssl/certs` and `/etc/ssl/private` directories, generates self-signed RSA-2048 certificates via `openssl req` for each SSL-enabled site
    - `recipes/sites.rb` — renders per-site `site.conf` from ERB template into `sites-available/`, creates symlinks in `sites-enabled/`, removes the default Nginx site
    - `recipes/security.rb` — installs and configures `fail2ban` (SSH, nginx-http-auth, nginx-limit-req, nginx-botsearch jails), configures UFW (default deny, allow SSH/HTTP/HTTPS), hardens `/etc/ssh/sshd_config` (PermitRootLogin no, PasswordAuthentication no), deploys sysctl security parameters (IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable)
    - `resources/lineinfile.rb` — custom Chef resource that replicates `lineinfile` behaviour (match-and-replace or append) with optional timestamped backup; maps directly to Ansible's built-in `lineinfile` module
    - `attributes/default.rb` — defines three virtual host entries, SSL certificate/key paths, and security feature flags (fail2ban, ufw, ssh hardening)
    - `templates/default/nginx.conf.erb` — global Nginx config (worker_processes auto, keepalive, gzip, mime types, includes sites-enabled)
    - `templates/default/site.conf.erb` — per-vhost config with conditional SSL block, TLS 1.2/1.3 ciphers, HSTS, security headers, gzip, location rules
    - `templates/default/security.conf.erb` — Nginx-level hardening (server_tokens off, rate-limit zones, buffer overflow protection, timeout settings, global SSL session cache)
    - `templates/default/fail2ban.jail.local.erb` — Fail2ban jail configuration (bantime 3600s, maxretry 3, four jails: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch)
    - `templates/default/sysctl-security.conf.erb` — 20+ kernel parameters for network hardening
    - `files/default/test/index.html`, `files/default/ci/index.html`, `files/default/status/index.html` — static landing pages for each virtual host

- **cache**:
  - Description: Dual in-memory caching layer that installs and configures both Memcached (via the `memcached` community cookbook) and Redis (via the `redisio` community cookbook). Redis is configured on port 6379 with password authentication. Includes a `ruby_block` workaround that post-processes the generated Redis config file to strip deprecated `replica-*` directives that cause startup failures on newer Redis versions.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Delegates Memcached installation to the `memcached ~> 6.0` community cookbook
    - Configures Redis via `redisio` node attributes: port 6379, `requirepass` set to a hardcoded password (`redis_secure_password_123`)
    - Creates `/var/log/redis` directory with correct `redis:redis` ownership
    - `ruby_block "fix_redis_config"` — post-processes `/etc/redis/6379.conf` to remove five deprecated config keys (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the `redisio` cookbook writes but newer Redis versions reject
    - Calls `redisio::enable` to create and enable the systemd/init service

- **fastapi-tutorial**:
  - Description: Full-stack Python web application deployment that installs system packages (Python 3, pip, venv, git, PostgreSQL with libpq-dev), clones the FastAPI tutorial application from GitHub, creates a Python virtual environment, installs pip dependencies, configures and starts PostgreSQL, provisions a dedicated database user and database, writes a `.env` configuration file with the database connection string, and registers the application as a systemd service managed by Uvicorn.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - Installs: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial` using the Chef `git` resource (`:sync` action)
    - Creates virtualenv at `/opt/fastapi-tutorial/venv` and installs from `requirements.txt`
    - Enables and starts the `postgresql` service
    - Provisions PostgreSQL user `fastapi` with hardcoded password `fastapi_password`, database `fastapi_db`, and full privileges — executed via `sudo -u postgres psql` shell commands with `|| true` guards
    - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plaintext credential in a world-readable file, mode `0644`)
    - Creates `/etc/systemd/system/fastapi-tutorial.service` running Uvicorn on `0.0.0.0:8000` as `root` (security concern)
    - Calls `systemctl daemon-reload` and enables/starts the `fastapi-tutorial` service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbook paths and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out in Berksfile but present and locked in `Policyfile.rb` and `Policyfile.lock.json`. Migration consideration: replace with `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook sources. Maps directly to an Ansible playbook with three roles applied in sequence.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (including transitive dependencies `selinux 6.2.4` pulled in by `redisio`). Provides the authoritative version reference for selecting equivalent Ansible Galaxy roles.
- `Vagrantfile`: Vagrant configuration targeting `generic/fedora42` via the `libvirt` provider (2 vCPU, 2 GB RAM). Exposes ports 80→8080 and 443→8443. Uses rsync to sync the repo to `/chef-repo` inside the VM. Migration consideration: the `generic/fedora42` box indicates a Fedora/RHEL-family target; package names and service names in Ansible tasks must use `dnf`/`yum` equivalents (e.g., `python3-psycopg2` instead of `libpq-dev`, `sshd` instead of `ssh`). The Vagrantfile can be updated to use the `ansible` provisioner instead of the shell provisioner.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks`. Migration consideration: replaced entirely by Ansible inventory and `ansible.cfg`.
- `solo.json`: Chef Solo node JSON providing run list and attribute overrides (three virtual host definitions with SSL enabled, SSL cert/key paths, and security feature flags). Maps to Ansible `group_vars` or `host_vars` variable files.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo`. Migration consideration: replaced by a simple `ansible-playbook` invocation; the Vagrant `ansible` provisioner handles all bootstrapping natively.
- `project-plan.md`: Internal specification document for the X2Ansible migration tooling project. Not part of the infrastructure being migrated; no action required.

---

### Target Details

- **Operating System**: The `Vagrantfile` explicitly uses `generic/fedora42` (Fedora Linux 42). The cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`, indicating the cookbooks were written to be cross-platform but the actual test target is Fedora. Ansible tasks must account for Fedora-specific package names (e.g., `nginx` from the default Fedora repos, `python3-pip` available natively, `firewalld` may conflict with UFW which is Ubuntu-centric). The `security.rb` recipe uses `ufw` and references `/var/log/auth.log` — both Ubuntu conventions that do not exist on Fedora (Fedora uses `firewalld` and `journald`). This is the single most significant platform-compatibility challenge.
- **Virtual Machine Technology**: libvirt/KVM, as declared in the `Vagrantfile` (`config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. This is a local development/test environment only.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install `nginx` from the OS package manager, plus `ansible.builtin.template` for `nginx.conf` and `security.conf`. No Galaxy role required — the configuration is fully custom and already expressed as ERB templates that translate directly to Jinja2.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` to install `memcached` and `ansible.builtin.service` to enable/start it. The community cookbook performs only basic install-and-start; no complex configuration is used. Consider the `geerlingguy.memcached` Galaxy role for a drop-in equivalent.
- **redisio (7.2.4, Chef Supermarket)**: This is the most complex external dependency. The cookbook generates a Redis config file that requires post-processing to remove deprecated directives (the `fix_redis_config` ruby_block hack). Replace with the `geerlingguy.redis` Galaxy role or manage Redis directly via `ansible.builtin.package`, `ansible.builtin.template` (for `redis.conf`), and `ansible.builtin.service`. Using a template-based approach avoids the deprecated-directive problem entirely.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Present in `Policyfile.lock.json` as a resolved dependency but not directly called in any recipe (SSL cert generation is handled inline in `ssl.rb` via `openssl req`). No Ansible equivalent needed — the `openssl_certificate` or `community.crypto.x509_certificate` Ansible module handles self-signed cert generation natively.
- **selinux (6.2.4, Chef Supermarket)**: Transitive dependency pulled in by `redisio`. Not directly invoked. On Fedora, SELinux is active by default; Ansible tasks for nginx and Redis may need `community.general.sefcontext` or `ansible.posix.seboolean` calls to set correct SELinux contexts (e.g., `httpd_can_network_connect` for Nginx proxying).

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): This credential is stored in plaintext in the recipe source. During migration, move to an Ansible Vault-encrypted variable (e.g., `vault_redis_password`) referenced in the role's `vars/main.yml` or `group_vars/all/vault.yml`. **1 credential detected.**
- **Hardcoded PostgreSQL password** (`fastapi_password` appears in three locations in `cookbooks/fastapi-tutorial/recipes/default.rb`): used in the `CREATE USER` psql command, in the `DATABASE_URL` written to `/opt/fastapi-tutorial/.env`, and implicitly in the systemd service environment. Move to Ansible Vault. The `.env` file's mode must be changed from `0644` to `0600` and ownership changed from `root:root` to the application service user. **1 credential detected (referenced 3 times).**
- **Self-signed SSL certificates**: The `ssl.rb` recipe generates self-signed certificates at provisioning time using `openssl req`. These are appropriate for development but must not be used in production. In Ansible, use `community.crypto.x509_certificate` with `provider: selfsigned` for dev parity, or integrate with Let's Encrypt via `community.crypto.acme_certificate` for production. Certificate private keys are stored at `/etc/ssl/private/` with mode `0640` and `root:ssl-cert` ownership — replicate this in Ansible with `ansible.builtin.file`.
- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using raw `sed` commands. Replace with the `ansible.builtin.lineinfile` module (which is the direct equivalent of the custom `lineinfile` Chef resource) or the `devsec.hardening.ssh_hardening` Galaxy role for a more comprehensive baseline.
- **UFW firewall (Ubuntu-specific)**: The `security.rb` recipe uses `ufw` commands. On the actual Fedora 42 target, `ufw` is not the default firewall — `firewalld` is. This is a latent bug in the existing Chef code. In Ansible, use `ansible.posix.firewalld` for Fedora/RHEL targets, or add a conditional that selects `community.general.ufw` for Ubuntu and `ansible.posix.firewalld` for Fedora.
- **FastAPI service running as root**: The systemd unit file sets `User=root`. This is a security risk. During migration, create a dedicated `fastapi` system user and update the service definition accordingly.
- **Fail2ban log path**: `jail.local` references `/var/log/auth.log` for the `sshd` jail — this path is Ubuntu-specific. On Fedora, the correct path is `journald` backend (`backend = systemd`). Update the Jinja2 template with an OS-family conditional.
- **No secrets management system in use**: The repository uses no Chef Vault, encrypted data bags, or external secrets manager. All secrets are plaintext in recipe files. Ansible Vault is the direct migration target for both credentials identified above.

---

### Technical Challenges

- **Fedora vs. Ubuntu platform mismatch**: The `metadata.rb` files declare Ubuntu/CentOS support, but the Vagrantfile targets Fedora 42. Several recipe assumptions are Ubuntu-specific: `ufw` (not available by default on Fedora), `/var/log/auth.log` (does not exist on Fedora), the `ssh` service name (Fedora uses `sshd`), `www-data` user/group (Fedora nginx uses `nginx:nginx`), and `apt-get` in `vagrant-provision.sh`. Ansible tasks must use `ansible_os_family` or `ansible_distribution` conditionals, or the migration must commit to a single target OS. **Mitigation**: Define the Fedora 42 target as canonical; audit every package name, service name, user/group, and log path against Fedora conventions before writing Ansible tasks.
- **`redisio` config-file hack**: The `fix_redis_config` ruby_block is an acknowledged workaround (`# HACK` comment) for a bug in the `redisio` cookbook that writes deprecated Redis config directives. This logic has no direct Chef-to-Ansible translation. **Mitigation**: Replace the entire `redisio` dependency with a direct Ansible `template` task that renders a clean `redis.conf` from scratch, eliminating the need for post-processing entirely.
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements file line-editing with backup support. **Mitigation**: Replace all usages with Ansible's built-in `ansible.builtin.lineinfile` module, which provides identical functionality natively (including `backup: yes`).
- **ERB → Jinja2 template conversion**: Five ERB templates use `<%= @variable %>` and `<% if @ssl_enabled %>` syntax. These translate mechanically to `{{ variable }}` and `{% if ssl_enabled %}` in Jinja2. The `site.conf.erb` template has a structural quirk: the `<% if @ssl_enabled %>` block closes the HTTP server block and opens the HTTPS server block mid-template, which requires careful Jinja2 block placement. **Mitigation**: Manually review the rendered output of `site.conf.erb` against the Jinja2 equivalent before deploying.
- **Chef `git` resource `:sync` action**: The `fastapi-tutorial` recipe uses `:sync` which performs a `git pull` on every Chef run. Ansible's `ansible.builtin.git` module with `update: yes` is the equivalent, but care must be taken with idempotency if local changes exist in `/opt/fastapi-tutorial`. **Mitigation**: Set `force: yes` only if the deployment is always expected to be clean, or use `update: no` after initial clone for immutable deployments.
- **PostgreSQL provisioning via raw psql commands**: The `create_db_user` execute block runs three `psql` commands with `|| true` guards for idempotency. **Mitigation**: Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` Ansible modules, which are natively idempotent and do not require shell escaping.
- **Berkshelf vendoring workflow**: The `vagrant-provision.sh` script installs Berkshelf as a Chef embedded gem and runs `berks vendor` to download external cookbooks into the `cookbooks/` directory at runtime. In Ansible, the equivalent is `ansible-galaxy install -r requirements.yml`, which should be run once before `ansible-playbook`. **Mitigation**: Create a `requirements.yml` listing Galaxy roles and document the two-step workflow (`galaxy install` then `ansible-playbook`) in the project README.

---

### Migration Order

The following order respects the internal dependency chain (security baseline → web server → caching → application) and sequences simpler, lower-risk cookbooks first to build team confidence before tackling the most complex one.

1. **cache cookbook → Ansible `cache` role** *(Low complexity)*
   Straightforward install-and-configure for Memcached and Redis. Resolves the `redisio` hack by using a clean Redis template. Establishes the Ansible Vault pattern for the Redis password that will be reused in step 3. No template conversion required.

2. **nginx-multisite / security recipe → Ansible `security` role** *(Low-Medium complexity)*
   Isolate the OS hardening logic (UFW/firewalld, Fail2ban, SSH, sysctl) into a standalone role. This is the best place to resolve the Fedora vs. Ubuntu platform mismatch, as all the platform-specific divergences are concentrated here. Completing this step validates the target OS assumptions for all subsequent roles.

3. **nginx-multisite / nginx + ssl + sites recipes → Ansible `nginx_multisite` role** *(Medium complexity)*
   Convert the five ERB templates to Jinja2, implement the per-site loop using `ansible.builtin.template` with `loop`, handle SSL cert generation via `community.crypto`, and manage the `sites-available`/`sites-enabled` symlink pattern. Depends on the security role being complete (firewall must be open for ports 80/443).

4. **fastapi-tutorial cookbook → Ansible `fastapi_app` role** *(Medium-High complexity)*
   Most complex migration due to: PostgreSQL provisioning (replace shell commands with `community.postgresql` modules), Git clone + virtualenv + pip install chain, systemd service creation, `.env` file with Vault-encrypted credentials, and the `root` user security issue. Depends on the nginx role being complete if Nginx is intended to proxy to Uvicorn on port 8000.

---

### Assumptions

1. **Target OS is Fedora 42** (as declared in `Vagrantfile`), not Ubuntu or CentOS as suggested by `metadata.rb`. All Ansible tasks will be written for Fedora/RHEL conventions unless explicitly noted. If Ubuntu support is required, OS-family conditionals must be added.
2. **Self-signed certificates are acceptable** for the target environment. The migration will replicate the `openssl req` self-signed certificate generation using `community.crypto.x509_certificate`. If production-grade certificates are needed, Let's Encrypt or an internal CA integration must be scoped separately.
3. **The `ssl_certificate` community cookbook** (present in `Policyfile.lock.json`, commented out in `Berksfile`) is not actively used by any recipe. It will not be migrated.
4. **The `selinux` cookbook** is a transitive dependency of `redisio` and is not directly invoked. SELinux policy management on Fedora will be handled inline within the relevant roles (nginx, redis) using `ansible.posix.seboolean` or `community.general.sefcontext` as needed.
5. **The FastAPI application source** (`https://github.com/dibanez/fastapi_tutorial.git`) is assumed to be accessible from the target host at provisioning time. If the environment is air-gapped, an artifact repository or pre-bundled deployment package must be substituted.
6. **Memcached requires no authentication** configuration beyond what the `memcached` community cookbook provides (install + start). If authentication or binding to a non-default interface is required, this must be scoped as additional work.
7. **The `www-data` user/group** referenced in `nginx.rb` for document root ownership is Ubuntu-specific. On Fedora, Nginx runs as `nginx:nginx`. The Ansible role will use `nginx:nginx` as the canonical owner; if Ubuntu support is added later, a variable override will be needed.
8. **The `ssh` service name** used in `security.rb` (`service 'ssh'`) is Ubuntu-specific. On Fedora the service is named `sshd`. The Ansible role will use `sshd` as the service name for the Fedora target.
9. **Redis is a standalone single-instance deployment** (no replication, no Sentinel, no Cluster). The `replicaservestaledata: nil` attribute in the `cache` recipe and the removal of `replica-*` directives in the hack block confirm this. The Ansible Redis role will configure a standalone instance only.
10. **The FastAPI application listens on port 8000** and is not proxied through Nginx in the current configuration (no Nginx upstream or proxy_pass directive exists). If Nginx-to-Uvicorn proxying is desired, an additional `location /` proxy block must be added to `site.conf.j2` — this is out of scope for a like-for-like migration.
11. **Vagrant + libvirt** is the only deployment target described. No CI/CD pipeline, no cloud provider, and no configuration management server (Chef Server) is in use. The Ansible equivalent will use `ansible-playbook` with a static inventory file targeting the Vagrant VM.
12. **Both hardcoded credentials** (`redis_secure_password_123` and `fastapi_password`) are development placeholders. They will be migrated into Ansible Vault as-is for development parity, with a clear note in the migration documentation that they must be rotated before any non-development use.
13. **The `project-plan.md` file** describes the X2Ansible tooling project itself and is not part of the infrastructure being migrated. It requires no action.
14. **No Chef Server, Chef Automate, or Policyfile push workflow** is in use — this is a pure Chef Solo setup. There is no server-side state to migrate or decommission.
