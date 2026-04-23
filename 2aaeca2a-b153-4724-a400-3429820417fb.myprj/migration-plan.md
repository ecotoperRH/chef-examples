# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket cookbook dependencies**, orchestrated via a `Policyfile.rb` and executed through `chef-solo` inside a **Vagrant/libvirt** virtual machine running **Fedora 42**.

The run list executes three cookbooks in order: `nginx-multisite` → `cache` → `fastapi-tutorial`, collectively delivering:
- A hardened Nginx reverse proxy with three SSL-enabled virtual hosts
- Memcached and Redis caching services
- A Python FastAPI application backed by PostgreSQL

**Migration Complexity**: Medium — the cookbooks are well-structured, self-contained, and use standard Chef patterns. The primary challenges are replacing Chef community cookbook abstractions (`nginx ~> 12.3.1`, `memcached ~> 6.1.0`, `redisio ~> 7.2.4`) with native Ansible modules, managing a hardcoded credential in the `cache` recipe, and preserving the idempotency logic of the custom `lineinfile` resource.

**Estimated Timeline**: 2–3 weeks for a single engineer, or 1 week with a two-person team working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), security hardening via HTTP headers, rate limiting, and self-signed TLS certificate generation using OpenSSL. Includes UFW firewall rules, Fail2Ban intrusion prevention, and kernel-level sysctl security tuning.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - Four sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
    - Nginx global config (`nginx.conf.erb`) and per-site virtual host config (`site.conf.erb`) via ERB templates
    - Self-signed RSA-2048 certificate generation per virtual host (365-day validity) using `openssl req`
    - HTTP → HTTPS redirect, TLSv1.2/1.3 only, HSTS header, and full security header suite (X-Frame-Options, CSP, X-XSS-Protection, Referrer-Policy)
    - `security.conf.erb`: global Nginx rate-limiting zones (`login`, `api`), buffer overflow protections, SSL session settings
    - `fail2ban.jail.local.erb`: jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
    - `sysctl-security.conf.erb`: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
    - UFW firewall configured via `execute` resources (default deny, allow SSH/HTTP/HTTPS)
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` on `sshd_config`
    - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) that replicates Ansible's `lineinfile` module behaviour
    - Static `index.html` files deployed per site (ci, status, test) from `files/default/`
    - Document roots and `www-data` ownership managed per site

- **cache**:
  - Description: Caching services layer configuring both Memcached (via the `memcached ~> 6.1.0` community cookbook) and Redis (via `redisio ~> 7.2.4`) with password authentication. Includes a post-install Ruby block hack to strip deprecated Redis configuration directives that cause failures with newer Redis versions.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Delegates Memcached installation and configuration entirely to the `memcached` community cookbook
    - Configures Redis on port `6379` with `requirepass` authentication
    - Creates `/var/log/redis` directory with correct `redis:redis` ownership
    - Post-install `ruby_block` that patches `/etc/redis/6379.conf` to remove deprecated directives: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
    - Enables Redis via `redisio::enable` recipe
    - **Hardcoded credential**: Redis password `redis_secure_password_123` set directly in recipe attributes

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git-based source checkout, Python virtual environment setup, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation for process management.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch to `/opt/fastapi-tutorial`
    - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs from `requirements.txt`
    - Enables and starts `postgresql` service
    - Provisions PostgreSQL user `fastapi` and database `fastapi_db` via `sudo -u postgres psql` shell commands with `|| true` guards for idempotency
    - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
    - Creates `/etc/systemd/system/fastapi-tutorial.service` (Type=simple, User=root, uvicorn on `0.0.0.0:8000`)
    - Runs `systemctl daemon-reload` via notified `execute` resource
    - Enables and starts `fastapi-tutorial` systemd service
    - **Hardcoded credentials**: PostgreSQL password `fastapi_password` appears in both the recipe's `psql` command and the `.env` file content
    - **Security concern**: Service runs as `root` user

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all 3 local cookbook paths and 4 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — the latter commented out). Replaced entirely by Ansible Galaxy `requirements.yml` in the migrated project.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list and version constraints. Equivalent to an Ansible playbook's role/collection include list.
- `Policyfile.lock.json`: Locked dependency graph with resolved versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. Provides the authoritative version reference for selecting equivalent Ansible collections.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides — defines the 3 virtual host names with document roots and `ssl_enabled: true`, SSL certificate/key paths, and security flags (`fail2ban`, `ufw`, `ssh` hardening). Maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No Ansible equivalent needed.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, `libvirt` provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of repo to `/chef-repo`. Informs the Ansible inventory target OS and connection details.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, runs Berkshelf to vendor dependencies, then executes `chef-solo`. In the Ansible world this is replaced by the Ansible control node running `ansible-playbook` directly — no bootstrap script needed.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata listing the 3 cookbooks with descriptions. Useful as a reference during migration but has no Ansible equivalent.

---

### Target Details

- **Operating System**: The `Vagrantfile` explicitly specifies `generic/fedora42` (Fedora Linux 42). However, `metadata.rb` files for all three cookbooks declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `security.rb` recipe uses `ufw` (an Ubuntu/Debian-native tool) and references `/var/log/auth.log` (Debian path), while `vagrant-provision.sh` calls `apt-get update` — indicating the **actual runtime target is a Debian/Ubuntu-family OS** despite the Fedora Vagrant box declaration. This is a notable inconsistency. The Ansible migration should target **Ubuntu 22.04 LTS** as the primary platform, with the Fedora/RHEL path treated as a secondary concern pending clarification.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. The VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (Chef Supermarket ~> 12.3.1, resolved 12.3.1)**: This community cookbook abstracts Nginx installation, service management, and configuration. Replace with the `ansible.builtin.package` module for installation, `ansible.builtin.template` for `nginx.conf` and `security.conf` (ERB templates already exist and translate directly to Jinja2), and `ansible.builtin.service` for lifecycle management. The `nginxinc.nginx` Ansible Galaxy role is an option but the existing templates make a direct role implementation straightforward.

- **memcached (Chef Supermarket ~> 6.1.0, resolved 6.1.0)**: Handles Memcached package install, configuration, and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service`. The `memcached` Ansible role from Galaxy (`geerlingguy.memcached`) is a well-maintained drop-in, or implement directly with two tasks.

- **redisio (Chef Supermarket ~> 7.2.4, resolved 7.2.4)**: Manages Redis installation, per-instance configuration file generation, and service enablement. The post-install config-patching `ruby_block` hack in `cache/recipes/default.rb` exists specifically because `redisio 7.2.4` generates deprecated directives. Replace with `geerlingguy.redis` Galaxy role or direct tasks using `ansible.builtin.template` for `/etc/redis/redis.conf` — this eliminates the need for the patching hack entirely since the Ansible template will only emit valid directives.

- **ssl_certificate (Chef Supermarket ~> 2.1.0, resolved 2.1.0)**: Present in `Policyfile.lock.json` but **not actively used** in any recipe (commented out in `Berksfile`). SSL certificate generation is handled directly in `nginx-multisite::ssl` via `openssl req` shell commands. Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection for idempotent, declarative self-signed certificate management.

- **selinux (Chef Supermarket ~> 6.2.4, resolved 6.2.4)**: Pulled in as a transitive dependency of `redisio`. Not directly invoked in any local recipe. In Ansible, SELinux context management is handled natively via `ansible.posix.seboolean` and `community.general.sefcontext` if the target is RHEL/Fedora. On Ubuntu (the apparent actual target) this dependency is irrelevant.

- **Custom `lineinfile` LWRP (`nginx-multisite/resources/lineinfile.rb`)**: This custom Chef resource reimplements Ansible's own `ansible.builtin.lineinfile` module. It can be **dropped entirely** — replace all usages with the native Ansible module.

---

### Security Considerations

- **Hardcoded Redis Password**: The string `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb` as a node attribute (`node.default['redisio']['servers'][0]['requirepass']`). **1 credential detected.** Migrate to `ansible-vault`-encrypted variable (`vault_redis_password`) stored in `group_vars/all/vault.yml`.

- **Hardcoded PostgreSQL Password**: The password `fastapi_password` appears twice in `cookbooks/fastapi-tutorial/recipes/default.rb` — once in the `psql` provisioning command and once embedded in the `.env` file content. **1 credential detected (used in 2 locations).** Migrate to a vaulted variable (`vault_postgres_fastapi_password`) and use `ansible.builtin.template` for the `.env` file with the variable substituted at render time.

- **Self-Signed TLS Certificates**: All three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) use self-signed certificates generated at provision time via `openssl req`. Certificate paths are `/etc/ssl/certs/<site>.crt` and `/etc/ssl/private/<site>.key`. These are appropriate for development/internal use. In Ansible, replace the `execute` resource with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` tasks for idempotent generation. For production promotion, integrate `community.crypto.acme_certificate` (Let's Encrypt).

- **Private Key Permissions**: The `ssl.rb` recipe sets `chmod 640` and `chown root:ssl-cert` on private keys. This must be explicitly replicated in Ansible using `ansible.builtin.file` with `mode: '0640'`, `owner: root`, `group: ssl-cert` — do not rely on defaults.

- **SSH Hardening**: `security.rb` disables root login and password authentication by patching `/etc/ssh/sshd_config` with `sed`. Migrate to `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`, with a handler to restart `sshd`. Ensure the Ansible control node connection user is not `root` before applying this hardening, or the playbook will lock itself out.

- **UFW Firewall**: Configured via raw `execute` resources running `ufw` CLI commands. Migrate to `community.general.ufw` module for fully declarative, idempotent firewall management. Rules: default deny incoming, allow SSH (22/tcp), HTTP (80/tcp), HTTPS (443/tcp).

- **FastAPI Service Running as Root**: The systemd unit in `fastapi-tutorial/recipes/default.rb` sets `User=root`. This is a security risk and should be corrected during migration — create a dedicated `fastapi` system user and run the service under that account using `ansible.builtin.user` + updated `ansible.builtin.template` for the service unit.

- **`.env` File Permissions**: The `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded credentials. Migrate with `mode: '0600'` and `owner: fastapi` (after fixing the root-user issue above).

- **No Encrypted Data Bags or Chef Vault**: The repository does not use Chef encrypted data bags or Chef Vault. All secrets are plaintext in recipe files. This simplifies migration but means all credentials must be identified manually and moved to `ansible-vault` before the first playbook run.

---

### Technical Challenges

- **OS/Package Manager Mismatch**: The `Vagrantfile` targets `generic/fedora42` (DNF/RPM), but `vagrant-provision.sh` calls `apt-get update` and `apt-get install`, and `security.rb` installs `ufw` and `fail2ban` (Debian-native packages). This inconsistency means the Chef stack likely does not actually work on Fedora 42 as written. The Ansible migration must first resolve the target OS. If Ubuntu is the true target, the Ansible inventory should specify an Ubuntu host. If Fedora/RHEL is required, `ufw` must be replaced with `firewalld` (`ansible.posix.firewalld`) and `fail2ban` configuration paths adjusted.

- **`redisio` Config Patching Hack**: The `ruby_block "fix_redis_config"` in `cache/recipes/default.rb` exists to strip deprecated Redis directives written by `redisio 7.2.4`. This is a workaround for a community cookbook bug. In Ansible, since the Redis configuration is written directly from a template, this hack is unnecessary — the template simply omits the deprecated directives. However, if migrating to an existing host that already has the broken config, an initial cleanup task may be needed.

- **ERB → Jinja2 Template Conversion**: Five ERB templates exist in `nginx-multisite/templates/default/`. ERB syntax (`<%= @var %>`, `<% if condition %>`) must be converted to Jinja2 (`{{ var }}`, `{% if condition %}`). The templates are moderately complex (conditional SSL blocks, loops over sites) but are straightforward to convert. The `site.conf.erb` template has a structural quirk — the `<% if @ssl_enabled %>` block closes the HTTP server block and opens the HTTPS server block mid-template, which requires careful Jinja2 translation.

- **Chef `node` Attribute Hierarchy → Ansible Variables**: Chef's multi-level attribute system (`default` → `normal` → `override`) with `solo.json` overrides maps to Ansible's variable precedence (`role_vars` → `group_vars` → `host_vars` → `extra_vars`). The `solo.json` site definitions (document roots, SSL flags) and security flags must be translated into a structured `group_vars/all/main.yml` variable file. The attribute path `node['nginx']['sites']` becomes a YAML dict `nginx_sites`.

- **Idempotency of PostgreSQL Provisioning**: The `fastapi-tutorial` recipe uses raw `psql` shell commands with `|| true` to achieve idempotency. Ansible's `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules provide native idempotent PostgreSQL management and should replace these shell commands entirely.

- **Git Sync Idempotency**: The `git` Chef resource with `action :sync` maps to `ansible.builtin.git` with `update: yes`. Ensure the `version: main` is pinned to a specific tag or commit SHA in production to prevent uncontrolled updates on each playbook run.

- **`systemctl daemon-reload` Notification Chain**: The Chef recipe uses a `notifies :run, 'execute[systemd_reload]', :immediately` pattern. In Ansible this is handled by a handler (`ansible.builtin.systemd` with `daemon_reload: yes`) triggered by a `notify` directive on the service unit template task — a direct and clean equivalent.

- **Custom `lineinfile` Resource Deprecation**: The `nginx-multisite/resources/lineinfile.rb` LWRP creates timestamped backup files (e.g., `sshd_config.backup.1234567890`). Ansible's native `lineinfile` module also supports `backup: yes`. Ensure backup behaviour expectations are documented for the operations team.

---

### Migration Order

1. **`nginx-multisite` (security sub-recipe)** — Migrate the security hardening tasks first (UFW, Fail2Ban, sysctl, SSH hardening) as a standalone `security` Ansible role. This is self-contained, has no external cookbook dependencies, and establishes the baseline hardened host that all other roles depend on. Low risk, high value.

2. **`cache` (Memcached component)** — Migrate Memcached installation and service management as a simple `memcached` role. No credentials involved, straightforward package + service pattern. Validates the Ansible execution environment before tackling Redis.

3. **`cache` (Redis component)** — Migrate Redis configuration as a `redis` role. Requires vault setup for `vault_redis_password`. The config-patching hack is eliminated by using a clean Jinja2 template. Medium complexity due to credential handling.

4. **`nginx-multisite` (nginx + ssl + sites sub-recipes)** — Migrate Nginx installation, SSL certificate generation, virtual host configuration, and static file deployment as an `nginx_multisite` role. Requires Jinja2 template conversion of all 5 ERB templates and `community.crypto` collection for certificate tasks. Medium-high complexity due to template work and multi-site loop logic.

5. **`fastapi-tutorial`** — Migrate last due to the highest number of concerns: credential vaulting (PostgreSQL password), service user fix (root → fastapi), `.env` file permission hardening, PostgreSQL module adoption, and Git checkout management. Depends on PostgreSQL being available (installed as part of this cookbook itself). High complexity.

---

### Assumptions

1. **Target OS is Ubuntu (likely 22.04 LTS)**, not Fedora 42 as declared in the `Vagrantfile`. Evidence: `apt-get` in `vagrant-provision.sh`, `ufw`/`fail2ban` packages in `security.rb`, `/var/log/auth.log` path in `fail2ban.jail.local.erb`. This must be confirmed with the repository owner before migration begins. If Fedora/RHEL is genuinely required, `ufw` → `firewalld`, `fail2ban` log paths, and package names must all be adjusted.

2. **The `ssl_certificate` community cookbook is not in use**. It appears in `Policyfile.rb` and `Policyfile.lock.json` but is commented out in `Berksfile` and not referenced in any recipe. It is assumed safe to exclude from the migration scope.

3. **The three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) are internal/development hostnames** resolvable only via `/etc/hosts` or a local DNS server. The migration plan assumes this pattern continues in the Ansible environment. No public DNS or Let's Encrypt integration is assumed unless explicitly requested.

4. **Self-signed certificates are acceptable for the target environment**. The `ssl.rb` recipe generates self-signed certificates with a 365-day validity. If this is a production migration, the team must decide whether to integrate a CA or ACME/Let's Encrypt workflow before the Ansible role is finalised.

5. **The `fastapi_tutorial` Git repository (`https://github.com/dibanez/fastapi_tutorial.git`) is publicly accessible** and the `main` branch is stable. If the repository is private or the branch has changed, the `ansible.builtin.git` task will require SSH key configuration or a token.

6. **No existing Redis or Memcached data needs to be preserved**. The migration is assumed to be a fresh provisioning operation. If migrating in-place on a live host, cache warm-up and service restart windows must be planned separately.

7. **The `www-data` user and group exist on the target system** (standard on Ubuntu/Debian). The `nginx.rb` recipe assigns document root ownership to `www-data`. If targeting RHEL/Fedora, the equivalent is `nginx:nginx`.

8. **`solo.json` attribute overrides take precedence over cookbook defaults**. The `solo.json` defines document roots as `/var/www/<site>` while `attributes/default.rb` defines them as `/opt/server/<site>`. The `solo.json` values are the runtime-effective values and should be used as the canonical source for Ansible `group_vars`.

9. **The `selinux` cookbook (transitive dependency of `redisio`) is not actively configured** in any local recipe. It is assumed that SELinux is either disabled or permissive on the target host, consistent with the Ubuntu target assumption. No SELinux policy tasks are included in the migration scope.

10. **Ansible control node connectivity** to the target VM will use SSH key-based authentication. The SSH hardening applied by `security.rb` (disabling password auth) means the Ansible inventory must be configured with `ansible_ssh_private_key_file` before the security role is applied, or the hardening tasks must be run last in the play order.

11. **The `client_max_body_size 1k` setting in `security.conf.erb`** is extremely restrictive and will break any file upload or form submission larger than 1 KB. This appears to be a security-focused development configuration. It is assumed this value will be reviewed and adjusted per-site during migration rather than carried over verbatim.

12. **No Chef Server, Chef Automate, or Berkshelf API server** is in use. The stack runs entirely with `chef-solo` and local/vendored cookbooks. There is no server-side state to migrate — only the cookbook logic itself.
