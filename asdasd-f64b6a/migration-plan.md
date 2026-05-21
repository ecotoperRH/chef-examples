# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through Vagrant on a Fedora 42 / libvirt VM.

The run list executes three cookbooks in order: `nginx-multisite → cache → fastapi-tutorial`, deploying a hardened Nginx reverse proxy with three SSL-enabled virtual hosts, a dual-layer caching tier (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL.

**Overall Migration Complexity: Medium**
The cookbooks are well-structured and self-contained. The primary complexity drivers are:
- A custom `lineinfile` Chef resource that must be replaced with Ansible's native `lineinfile` module.
- Hardcoded credentials in recipe source code (Redis password, PostgreSQL user/password, `.env` file contents).
- Self-signed SSL certificate generation via `openssl` shell commands that must be translated to Ansible's `openssl_*` modules.
- A post-install Ruby hack (`ruby_block "fix_redis_config"`) patching the `redisio` cookbook's generated config, which requires a targeted Ansible workaround.
- Attribute precedence and `solo.json` overrides that must be mapped to Ansible variable precedence (`group_vars`, `host_vars`, extra vars).

**Estimated Migration Timeline: 5–8 working days** for a single engineer familiar with Ansible, broken down as:
- `nginx-multisite`: 2–3 days (most complex: templates, SSL, security hardening, multi-recipe structure)
- `cache`: 1–2 days (Redis config hack, credential handling)
- `fastapi-tutorial`: 1–2 days (Python venv, PostgreSQL setup, systemd service, credential handling)
- Integration, testing, and inventory setup: 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that require individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), full security hardening including UFW firewall, Fail2Ban intrusion prevention, SSH hardening, and kernel-level sysctl security tuning. Generates self-signed TLS certificates per virtual host using `openssl`. Deploys static HTML content per site from cookbook files.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - Multi-recipe structure: `default` → `security` → `nginx` → `ssl` → `sites`
    - Nginx installed from OS package manager; custom `nginx.conf` and per-site `site.conf` via ERB templates
    - TLS 1.2/1.3 only; strong cipher suite; HSTS; HTTP→HTTPS redirect per vhost
    - Security headers: `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, `Content-Security-Policy`
    - Nginx rate limiting zones (`login`: 10r/m, `api`: 30r/m); buffer overflow protections; timeout hardening
    - UFW firewall: default deny, allow SSH/HTTP/HTTPS
    - Fail2Ban: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch` jails; 1-hour ban, 3 retries
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` in-place edits
    - Sysctl hardening: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
    - Custom `lineinfile` Chef resource (LWRP) for idempotent line-in-file operations
    - Static site content for three virtual hosts deployed from `files/default/{ci,status,test}/index.html`
    - Document root ownership: `www-data:www-data`

- **cache**:
  - Description: Dual-layer caching tier configuring Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication. Includes a post-install Ruby block hack to strip incompatible directives from the `redisio`-generated Redis config file.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Memcached provisioned via `include_recipe 'memcached'` (Supermarket cookbook v6.1.0, no custom configuration)
    - Redis on port 6379 with `requirepass` authentication (hardcoded password: `redis_secure_password_123`)
    - Redis log directory `/var/log/redis` created with `redis:redis` ownership
    - Post-install `ruby_block "fix_redis_config"` strips five deprecated directives from `/etc/redis/6379.conf`: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
    - `redisio::enable` recipe called to create and enable the Redis systemd service
    - Depends on external cookbooks: `memcached ~> 6.0` (resolved: 6.1.0), `redisio >= 0.0.0` (resolved: 7.2.4), which in turn depends on `selinux` (resolved: 6.2.4)

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git repository clone, Python virtual environment setup, pip dependency installation, PostgreSQL database and user provisioning, `.env` configuration file generation, and systemd service unit creation and enablement.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Application cloned from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial`
    - Python venv at `/opt/fastapi-tutorial/venv`; dependencies installed from `requirements.txt`
    - PostgreSQL service enabled and started; database user `fastapi` with hardcoded password `fastapi_password`; database `fastapi_db` created and granted
    - `.env` file at `/opt/fastapi-tutorial/.env` with hardcoded `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
    - Systemd unit `/etc/systemd/system/fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, `Restart=always`, runs as `root` (security concern)
    - `systemctl daemon-reload` triggered on service file change via `notifies`
    - No external cookbook dependencies declared in `metadata.rb`

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local and Supermarket cookbook sources with version constraints. References `nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, and `ssl_certificate ~> 2.1` (the last is commented out in Berksfile but present in Policyfile). Must be replaced by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list and pinned cookbook versions. Equivalent to an Ansible playbook with role includes. The run order (`nginx-multisite → cache → fastapi-tutorial`) must be preserved in Ansible play task ordering.
- `Policyfile.lock.json`: Fully resolved dependency lock file. Documents exact resolved versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. Use as the authoritative reference for pinning Ansible Galaxy role versions.
- `solo.json` (root): Chef Solo JSON attributes file. Overrides default cookbook attributes: sets document roots to `/var/www/<site>` (overriding the cookbook default of `/opt/server/<site>`), enables SSL for all three sites, sets SSL cert/key paths, and enables all security features. These overrides must become Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration file pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No migration artifact needed; replaced by Ansible inventory and `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 vCPUs, 2 GB RAM, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443. Defines the target test environment. Migrate to an Ansible inventory file with equivalent host variables, or retain Vagrant with an Ansible provisioner replacing the shell provisioner.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef, Berkshelf, vendors cookbook dependencies, and runs `chef-solo`. Replace entirely with `ansible-playbook` invocation from the Vagrantfile's `ansible` provisioner block.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata listing the three cookbooks with descriptions. Reference only; no migration action required.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/solo.json`: Duplicate of root `solo.json` with identical content. Confirms attribute overrides; no separate migration action needed.
- `project-plan.md`: X2Ansible tool specification document. Not an infrastructure artifact; no migration action required.

---

### Target Details

- **Operating System**: Ubuntu (primary target inferred from `www-data` user/group for Nginx, `ufw` firewall, `/var/log/auth.log` path in Fail2Ban config, `apt-get` in `vagrant-provision.sh`, and `supports 'ubuntu', '>= 18.04'` in all `metadata.rb` files). CentOS 7+ is also declared as supported. The Vagrant box is `generic/fedora42`, indicating the development/test environment runs Fedora 42, but production targets are Ubuntu ≥ 18.04 or CentOS ≥ 7. **Recommend targeting Ubuntu 22.04 LTS** as the primary Ansible target, with conditional task blocks for RHEL/CentOS compatibility where needed.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in `Vagrantfile` via `config.vm.provider "libvirt"`. VM title: `chef-nginx-multisite`, 2 vCPUs, 2 GB RAM.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are referenced anywhere in the repository. Infrastructure appears to be on-premises or local virtualization only.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (Chef Supermarket, ~> 12.0, resolved: 12.3.1)**: The `nginx-multisite` cookbook does **not** use the `nginx` Supermarket cookbook in its recipes — it installs Nginx directly via the `package` resource and manages all configuration through its own ERB templates. The Berksfile/Policyfile dependency appears to be a declared-but-unused upstream reference. Replace with `ansible.builtin.package` to install `nginx` from the OS package manager, and migrate all ERB templates to Jinja2 (`.j2`) templates for `ansible.builtin.template`.
- **memcached (Chef Supermarket, ~> 6.0, resolved: 6.1.0)**: Used via `include_recipe 'memcached'` in `cache::default`. Replace with the `geerlingguy.memcached` Ansible Galaxy role (or equivalent), or implement directly using `ansible.builtin.package` + `ansible.builtin.service` + `ansible.builtin.template` for `memcached.conf`. No custom configuration is applied beyond the cookbook defaults.
- **redisio (Chef Supermarket, >= 0.0.0, resolved: 7.2.4)**: Used to install and configure Redis with a password. Replace with the `geerlingguy.redis` Ansible Galaxy role or implement natively. The post-install config-patching `ruby_block` must be replaced with `ansible.builtin.lineinfile` (with `state: absent` or `regexp`/`line` pairs) to remove the five deprecated directives from `/etc/redis/6379.conf` after the role runs.
- **selinux (Chef Supermarket, resolved: 6.2.4)**: Pulled in as a transitive dependency of `redisio`. On Ubuntu targets, SELinux is not used (AppArmor is the default MAC system). On RHEL/CentOS targets, use the `ansible.posix.selinux` module or the `geerlingguy.ansible-role-selinux` Galaxy role. Add a conditional block (`when: ansible_os_family == "RedHat"`) to scope SELinux tasks.
- **ssl_certificate (Chef Supermarket, ~> 2.1, resolved: 2.1.0)**: Present in `Policyfile.rb` and lock file but commented out in `Berksfile` and not referenced in any recipe. The `nginx-multisite::ssl` recipe handles certificate generation directly via `openssl` shell commands. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` Ansible modules for idempotent self-signed certificate generation.
- **PostgreSQL (OS package, no cookbook)**: Installed via `package` resource in `fastapi-tutorial`. Replace with `ansible.builtin.package` for `postgresql` and `postgresql-contrib`, `ansible.builtin.service` for the PostgreSQL daemon, and `community.postgresql.postgresql_user` + `community.postgresql.postgresql_db` + `community.postgresql.postgresql_privs` modules for database/user provisioning. Requires `community.postgresql` collection (`ansible-galaxy collection install community.postgresql`).

---

### Security Considerations

- **Hardcoded Redis Password**: The string `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`). **1 credential detected.** Migrate to an Ansible Vault-encrypted variable (e.g., `vault_redis_password`) stored in `group_vars/all/vault.yml`. Reference as `{{ redis_password }}` in the Redis configuration template.
- **Hardcoded PostgreSQL Credentials**: The password `fastapi_password` appears three times in `cookbooks/fastapi-tutorial/recipes/default.rb`: in the `psql` provisioning command, in the `.env` file content, and implicitly in the `DATABASE_URL`. **1 credential (used in 3 locations) detected.** Migrate to `vault_fastapi_db_password` in Ansible Vault. The `.env` file should be rendered via `ansible.builtin.template` with the vaulted variable substituted at deploy time.
- **`.env` File Permissions**: The `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded credentials to all local users. Change to mode `0600` or `0640` with appropriate owner/group in the Ansible `template` task.
- **FastAPI Service Running as Root**: The systemd unit runs `uvicorn` as `User=root`. This is a significant security risk. Create a dedicated `fastapi` system user and group during migration, and update the service unit's `User=` and `WorkingDirectory` ownership accordingly.
- **Self-Signed SSL Certificates**: All three virtual hosts use self-signed certificates generated by `openssl req -x509` with a 365-day validity and a hardcoded subject (`/C=US/ST=Example/...`). These are appropriate for development but must be replaced with CA-signed or Let's Encrypt certificates for production. The Ansible migration should parameterize the subject fields and certificate validity period as variables, and provide a clear hook for swapping in production certificates.
- **SSL Private Key Permissions**: The `ssl.rb` recipe sets the private key directory (`/etc/ssl/private`) to mode `0710` with `root:ssl-cert` ownership, and individual key files to mode `0640` with `root:ssl-cert`. This must be faithfully reproduced in Ansible using `ansible.builtin.file` with explicit `owner`, `group`, and `mode` parameters. The `ssl-cert` group must be created before the directory task runs.
- **SSH Hardening via `sed`**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced by `sed -i` shell commands with `not_if` guards. Replace with `ansible.builtin.lineinfile` tasks using `regexp` and `line` parameters, with a handler to restart the `sshd` service. This is a direct, idempotent equivalent.
- **UFW Firewall Management**: UFW rules are applied via `execute` resources with `not_if` shell guards. Replace with the `community.general.ufw` Ansible module for fully idempotent firewall management. Ensure the `ufw` package is installed before any rule tasks.
- **Fail2Ban Configuration**: The `fail2ban.jail.local.erb` template is static (no ERB variables used). It can be migrated as a plain `ansible.builtin.copy` task or a minimal `ansible.builtin.template` task. The four active jails (`sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`) must all be preserved.
- **Sysctl Hardening**: The `sysctl-security.conf.erb` template is also fully static. Migrate using `ansible.posix.sysctl` module for each parameter (preferred for idempotency) or `ansible.builtin.copy` for the conf file with a handler calling `sysctl -p`. Note: `net.ipv4.icmp_echo_ignore_all = 1` (ICMP ping disabled) and `net.ipv6.conf.all.disable_ipv6 = 1` may conflict with cloud or monitoring infrastructure — flag for review.
- **No Chef Encrypted Data Bags or Chef Vault**: The repository does not use Chef encrypted data bags, Chef Vault, or any secrets management backend. All secrets are plaintext in recipe source code. This simplifies migration but means **all credentials must be moved to Ansible Vault** before the first production run.

---

### Technical Challenges

- **Chef `ruby_block "fix_redis_config"` Hack**: The `cache` cookbook patches the `redisio`-generated `/etc/redis/6379.conf` by stripping five deprecated directives using Ruby regex substitution. This is a workaround for an incompatibility between `redisio 7.2.4` and the installed Redis version. In Ansible, if using `geerlingguy.redis`, the role's variables should be used to suppress these directives at template-render time. If the directives still appear, use five `ansible.builtin.lineinfile` tasks with `state: absent` and `regexp` patterns to remove them after the role runs. The root cause (Redis version vs. config directive compatibility) should be investigated and resolved rather than patched.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` Chef resource (`resources/lineinfile.rb`) that replicates Ansible's built-in `lineinfile` module behavior (match-and-replace or append, with backup). This resource does not appear to be called anywhere in the cookbook's own recipes (it is defined but unused in the current recipe set). No migration action is needed for its usage, but the resource definition itself should be discarded — Ansible's `ansible.builtin.lineinfile` is a direct native equivalent.
- **Attribute Override Discrepancy (Document Roots)**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, but `solo.json` overrides them to `/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}`. The static HTML files in `files/default/{ci,status,test}/index.html` reference `/opt/server/` paths in their content. This inconsistency must be resolved: choose one canonical document root path, update the static HTML content accordingly, and define the path as a single Ansible variable.
- **ERB Template to Jinja2 Conversion**: Five ERB templates must be converted to Jinja2: `nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`. The `site.conf.erb` template uses conditional ERB blocks (`<% if @ssl_enabled %>`) that map directly to Jinja2 `{% if ssl_enabled %}` blocks. Variable references (`<%= @server_name %>`) map to `{{ server_name }}`. The conversion is straightforward but must be tested carefully for the SSL conditional branch.
- **Nginx `sites-available` / `sites-enabled` Pattern**: The `sites.rb` recipe uses the Debian/Ubuntu `sites-available` + `sites-enabled` symlink pattern. This pattern is not present on RHEL/CentOS (which uses `conf.d/`). If multi-OS support is required, add a conditional in the Ansible role to create the `sites-available` and `sites-enabled` directories on RHEL, or restrict the role to Ubuntu targets only.
- **Git Clone Idempotency**: The `fastapi-tutorial` recipe uses Chef's `git` resource with `action :sync`, which is idempotent. The Ansible equivalent `ansible.builtin.git` with `update: yes` is also idempotent but will overwrite local changes. Ensure the `version: main` branch tracking behavior is explicitly set and that the deploy key or public repo access is confirmed.
- **PostgreSQL Provisioning Idempotency**: The `fastapi-tutorial` recipe uses `|| true` shell guards on `psql` commands to prevent failures on re-runs. The Ansible `community.postgresql` modules are natively idempotent and should replace these shell commands entirely. Requires the `psycopg2` Python library on the target host (`python3-psycopg2` package) for the Ansible PostgreSQL modules to function.
- **`systemctl daemon-reload` Trigger**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` on the service file resource. In Ansible, use a handler with `ansible.builtin.systemd: daemon_reload: yes` triggered by a `notify` on the template task that writes the service unit file.
- **Vagrant Box OS Mismatch**: The Vagrantfile uses `generic/fedora42`, but all cookbooks declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7. Fedora 42 uses `dnf` (not `apt`), does not have `ufw` by default, and uses `firewalld`. The `vagrant-provision.sh` script calls `apt-get`, which will fail on Fedora. This is an existing inconsistency in the repository. For the Ansible migration, either switch the Vagrant box to `generic/ubuntu2204` to match the declared OS support, or add full Fedora/RHEL compatibility to the Ansible roles.
- **`www-data` User on Non-Debian Systems**: Nginx document root ownership is set to `www-data:www-data`, which is the Debian/Ubuntu default Nginx user. On RHEL/CentOS/Fedora, the Nginx user is `nginx`. Parameterize the web server user/group as Ansible variables with OS-family-based defaults.

---

### Migration Order

The following order is recommended based on dependency relationships and risk profile:

1. **`nginx-multisite` (security sub-role first)** — The security hardening tasks (UFW, Fail2Ban, SSH, sysctl) are self-contained and have no dependencies on other cookbooks. Migrating them first establishes the security baseline and validates the Ansible connection and privilege escalation setup. Complexity: Medium.
2. **`nginx-multisite` (nginx + ssl + sites sub-roles)** — After security is validated, migrate the Nginx installation, template rendering, SSL certificate generation, and virtual host configuration. This is the most template-heavy component and benefits from the security role already being tested. Complexity: Medium-High.
3. **`cache` (Memcached)** — Memcached has no custom configuration and maps directly to a Galaxy role or a simple package+service play. Low risk, validates the Galaxy role workflow. Complexity: Low.
4. **`cache` (Redis + config patch)** — Redis requires credential handling (Ansible Vault) and the config-patching workaround. Migrate after Memcached to isolate any Redis-specific issues. Complexity: Medium.
5. **`fastapi-tutorial`** — Most complex single cookbook: involves Git, Python venv, pip, PostgreSQL provisioning, `.env` file with secrets, and systemd service management. Migrate last to benefit from all prior Vault and module patterns being established. Complexity: Medium-High.
6. **Integration & Inventory** — Assemble the full playbook, define `group_vars`/`host_vars`, encrypt all credentials with `ansible-vault encrypt_string`, update the Vagrantfile to use the Ansible provisioner, and run end-to-end validation.

---

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS** for production, despite the Vagrant box being `generic/fedora42`. The `apt-get` call in `vagrant-provision.sh` and `www-data` user references confirm Ubuntu as the intended target. The Vagrant box should be changed to `generic/ubuntu2204` for consistent local testing.
2. **The `nginx` Supermarket cookbook (v12.3.1) is not actually used** in any recipe. The `nginx-multisite` cookbook installs Nginx directly via `package 'nginx'`. The Berksfile/Policyfile dependency is vestigial and can be dropped entirely in the Ansible migration.
3. **The `ssl_certificate` Supermarket cookbook (v2.1.0) is not used** in any recipe (commented out in Berksfile, present in Policyfile lock). It can be safely ignored during migration.
4. **The custom `lineinfile` LWRP is not called** by any recipe in this repository. It is defined in `resources/lineinfile.rb` but has no `lineinfile` resource calls in any `.rb` recipe file. It will not be migrated as active logic.
5. **Self-signed certificates are acceptable for the target environment** (development/staging). The migration plan preserves self-signed certificate generation. If this is a production environment, a separate task to integrate Let's Encrypt (via `community.crypto.acme_certificate`) or an internal CA should be added.
6. **The FastAPI application repository (`https://github.com/dibanez/fastapi_tutorial.git`) is publicly accessible** and does not require a deploy key or authentication token. If the repository is private, an SSH deploy key or GitHub token must be provisioned and stored in Ansible Vault.
7. **The `requirements.txt` file exists** in the cloned FastAPI repository at `/opt/fastapi-tutorial/requirements.txt`. The recipe assumes its presence without checking. The Ansible task should include a `stat` pre-check or rely on the `pip` module's `requirements` parameter with a `failed_when` guard.
8. **PostgreSQL is installed from the OS default package repository**, not from the PostgreSQL Global Development Group (PGDG) apt repository. No specific PostgreSQL version is pinned. If a specific version is required, the PGDG repository must be added as a pre-task.
9. **Memcached requires no custom configuration** beyond what the `memcached` Supermarket cookbook provides by default. No `memcached.conf` attributes are set in any recipe or `solo.json`. The Ansible migration will use default role/package settings.
10. **The `selinux` cookbook dependency is a no-op on Ubuntu** targets. It is pulled in transitively by `redisio` for RHEL/CentOS compatibility. On Ubuntu, SELinux tasks should be skipped via `when: ansible_os_family == "RedHat"`.
11. **The document root path discrepancy** between `attributes/default.rb` (`/opt/server/`) and `solo.json` (`/var/www/`) is intentional: `solo.json` represents the runtime override. The Ansible migration will use `/var/www/<site>` as the canonical path (matching `solo.json`), and the static HTML file content referencing `/opt/server/` will be updated to reflect the correct path.
12. **No load balancer, CDN, or upstream proxy** is present. Nginx serves as the edge server directly. No upstream `proxy_pass` configuration exists in the current templates.
13. **The `redisio` cookbook's `replicaservestaledata: nil` attribute** (set in `cache::default`) combined with the `ruby_block` config patch suggests the installed Redis version does not support replica-related directives. The target Redis version should be confirmed and the Ansible Redis role configured to match, avoiding the need for post-install patching entirely.
14. **No monitoring, alerting, or log shipping** is configured in any cookbook. The status page (`status.cluster.local`) is a static HTML file, not a live monitoring dashboard. These concerns are out of scope for this migration.
