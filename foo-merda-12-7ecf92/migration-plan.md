# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-site web server environment composed of three local cookbooks and four external Supermarket dependencies. The stack deploys an Nginx reverse proxy with SSL-enabled virtual hosts, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL — all running on a Fedora 42 VM managed by Vagrant with libvirt.

The migration to Ansible is assessed as **medium complexity**. All three cookbooks follow conventional Chef patterns (package/template/service/execute resources) that map cleanly to Ansible built-in modules. The primary challenges are: a hardcoded credential pattern across two cookbooks, a Ruby-block config-patching workaround in the cache cookbook that requires a purpose-built Ansible equivalent, and a custom `lineinfile` LWRP that duplicates a native Ansible module. No Chef Server, encrypted data bags, or Chef Vault usage was detected — secrets are currently stored in plain text.

**Estimated migration effort: 3–4 weeks** for a single engineer, including playbook authoring, Ansible Vault integration for secrets, and functional testing against the Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation via OpenSSL, per-site document roots with static HTML content, and a comprehensive security hardening layer
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Multi-recipe structure: `default` → `security` → `nginx` → `ssl` → `sites`
        - Self-signed RSA-2048 certificate generation per virtual host (365-day validity, skipped if cert already exists)
        - SSL/TLS hardening: TLSv1.2/1.3 only, strong cipher suite, HSTS with `includeSubDomains`, session caching
        - HTTP security headers: `X-Frame-Options DENY`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, `Content-Security-Policy`
        - UFW firewall: default-deny, allow SSH/HTTP/HTTPS
        - Fail2ban: jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch` (3600s ban, 3 retries)
        - Kernel hardening via `sysctl`: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable, Martian logging
        - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` (driven by node attributes)
        - Nginx rate limiting zones: `login` (10 req/min), `api` (30 req/min)
        - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) — reimplements Ansible's native `lineinfile` module
        - Static site content for three subdomains: CI/CD dashboard, system status page, test environment page
        - Attribute-driven site map: document roots and SSL flags configurable via `node['nginx']['sites']`

- **cache**:
    - Description: Dual caching layer configuring Memcached (via community cookbook) and Redis (via `redisio` community cookbook) with password authentication, a custom log directory, and a post-install Ruby-block workaround to strip deprecated Redis config directives
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Memcached installation and configuration delegated to `memcached` community cookbook (v6.1.0)
        - Redis on port 6379 with `requirepass` authentication (`redis_secure_password_123` — hardcoded plain text)
        - Custom `/var/log/redis` directory with `redis:redis` ownership
        - Post-install `ruby_block` hack to strip five deprecated Redis config directives from `/etc/redis/6379.conf`: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
        - Redis service enabled via `redisio::enable`
        - SELinux dependency pulled transitively through `redisio` (community cookbook `selinux` v6.2.4)

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application from a public GitHub repository, including system package installation, Python virtual environment setup, PostgreSQL database and user provisioning, `.env` file generation with database URL, and systemd service unit creation
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone/sync from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) into `/opt/fastapi-tutorial`
        - Python venv at `/opt/fastapi-tutorial/venv`, dependencies installed from `requirements.txt`
        - PostgreSQL service enabled and started; database user `fastapi` with password `fastapi_password` (hardcoded plain text), database `fastapi_db` with full privileges
        - `.env` file at `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plain text, mode `0644`, owned by root)
        - Systemd unit `/etc/systemd/system/fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, `Restart=always`, `After=postgresql.service`
        - `systemctl daemon-reload` triggered on unit file change
        - Service runs as `root` (security concern — see Security Considerations)

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out in Berksfile but present in Policyfile). Not needed in Ansible; replace with `requirements.yml` for any community roles/collections.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and version constraints. Maps directly to an Ansible playbook with ordered roles.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 cookbooks (including transitive `selinux` v6.2.4 and `ssl_certificate` v2.1.0). Use as the authoritative version reference when selecting equivalent Ansible Galaxy roles or collections.
- `solo.json`: Chef Solo node JSON supplying runtime attributes: site definitions (document roots, SSL flags), SSL certificate/key paths, and security flags (fail2ban, ufw, SSH hardening). Migrate to Ansible `group_vars` or `host_vars` YAML files.
- `solo.rb`: Chef Solo configuration pointing to cookbook paths and cache directory. No Ansible equivalent needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant + libvirt VM definition for `generic/fedora42` (2 vCPU, 2 GB RAM, IP `192.168.121.10`, ports 80→8080 and 443→8443). Retain for local development; replace `chef_solo` provisioner block with `ansible_local` or `ansible` provisioner.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. Replace entirely with Ansible provisioner in Vagrantfile or a simple `ansible-playbook` invocation.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a prior draft `migration-plan.md`, `solo.json` copy, and `generated-project-metadata.json` with cookbook inventory. Not part of the Chef run; no migration action required.
- `x2a-rules/`: X2Ansible rules directory. Not part of the Chef run; no migration action required.
- `project-plan.md`: X2Ansible tool specification document. Not part of the Chef run; no migration action required.

---

### Target Details

- **Operating System**: **Fedora 42** (primary, as declared in `Vagrantfile`: `config.vm.box = "generic/fedora42"`). Cookbook `metadata.rb` files additionally declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. Note: Fedora uses `dnf`/`rpm`, while the Chef recipes reference `www-data` user, `ufw`, `/var/log/auth.log`, and `apt`-style package names — indicating the recipes were primarily written and tested against **Ubuntu/Debian**. The Ansible playbooks should target **Ubuntu 22.04 LTS** or **Red Hat Enterprise Linux 9** depending on the production target, with platform-conditional tasks for package names and firewall tooling (`ufw` vs `firewalld`).
- **Virtual Machine Technology**: **libvirt / KVM** (declared in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references detected. Infrastructure appears designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (v12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module for Nginx installation, `ansible.builtin.template` for `nginx.conf` and per-site configs, and `ansible.builtin.service` for lifecycle management. The community `nginxinc.nginx` Galaxy role is an optional drop-in if a richer abstraction is desired.
- **memcached (v6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service` (enable/start). No complex configuration is applied beyond defaults; a simple role with package + service tasks suffices.
- **redisio (v7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `redis`), `ansible.builtin.template` for `/etc/redis/6379.conf` (authoring the config directly eliminates the post-install patching hack), and `ansible.builtin.service`. The `geerlingguy.redis` Galaxy role is a well-maintained alternative.
- **ssl_certificate (v2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` (or `openssl_certificate`) Ansible modules from the `community.crypto` collection. These provide idempotent self-signed certificate generation equivalent to the `openssl req -x509` shell command currently used.
- **selinux (v6.2.4, Chef Supermarket — transitive via redisio)**: Replace with `ansible.posix.selinux` module or the `linux-system-roles.selinux` role if SELinux policy management is required on RHEL/Fedora targets. On Ubuntu targets this dependency is irrelevant.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): **1 credential detected.** Migrate to `ansible-vault encrypt_string` and reference via a vaulted variable (e.g., `vault_redis_requirepass`). Never commit the plain-text value to the Ansible repository.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written verbatim into `/opt/fastapi-tutorial/.env`): **2 credential instances detected** (psql provisioning command + `.env` file content). Migrate both to Ansible Vault variables (e.g., `vault_fastapi_db_password`). The `.env` file template must use the vaulted variable and its file mode should be tightened to `0600` with a dedicated non-root owner.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk. During migration, create a dedicated `fastapi` system user and update the unit's `User=` and `WorkingDirectory` ownership accordingly.
- **Self-signed SSL certificates**: Currently generated with a 365-day validity and a static subject (`/C=US/ST=Example/...`). Acceptable for development; for production, replace with Let's Encrypt via `community.crypto.acme_certificate` or integrate with an internal CA. The subject fields should be parameterised as Ansible variables.
- **SSH hardening** (`PermitRootLogin no`, `PasswordAuthentication no`): Currently applied via `sed` in `security.rb`. Migrate to `ansible.builtin.lineinfile` or the `ansible.builtin.template` module managing `/etc/ssh/sshd_config` in full. Ensure the Ansible control node has a pre-deployed SSH key before disabling password auth to avoid lockout.
- **UFW firewall rules**: Applied via `execute` resources with idempotency guards. Migrate to `community.general.ufw` module (Ubuntu) or `ansible.posix.firewalld` (RHEL/Fedora). The default-deny posture and explicit allow rules for SSH/HTTP/HTTPS must be preserved.
- **Fail2ban configuration**: Templated `jail.local` with five active jails. Migrate using `ansible.builtin.template` for `/etc/fail2ban/jail.local` and `ansible.builtin.service` for lifecycle. The `geerlingguy.security` or `oefenweb.fail2ban` Galaxy roles are viable alternatives.
- **Kernel sysctl hardening**: 18 sysctl parameters covering IP spoofing, ICMP, SYN flood, source routing, and IPv6 disable. Migrate using the `ansible.posix.sysctl` module (one task per parameter) or a single `ansible.builtin.template` for `/etc/sysctl.d/99-security.conf` followed by `ansible.builtin.command: sysctl -p`.
- **`.env` file permissions**: Currently `mode '0644'` owned by root — the database password is world-readable. Tighten to `0600` and assign to the dedicated application user during migration.
- **No encrypted data bags or Chef Vault**: Secrets are entirely in plain text within recipe files. The migration to Ansible Vault represents a security improvement over the current state.

---

### Technical Challenges

- **Redis config post-install patching (`ruby_block "fix_redis_config"`)**: The cache cookbook strips five deprecated Redis directives from the generated config file after `redisio` writes it. This workaround exists because `redisio` v7.2.4 emits directives that older Redis versions do not recognise. In Ansible, this is eliminated entirely by templating `/etc/redis/6379.conf` directly (using `ansible.builtin.template`) rather than delegating to a community role that generates the file — giving full control over the config content from the outset.
- **Custom `lineinfile` LWRP** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): This custom Chef resource reimplements line-in-file editing with backup support. It maps directly and completely to Ansible's built-in `ansible.builtin.lineinfile` module. No custom logic needs to be ported; simply replace all `lineinfile` resource calls with the Ansible module.
- **Attribute-driven multi-site loop** (`node['nginx']['sites'].each`): The Chef recipes iterate over a hash of site definitions to generate per-site nginx configs, SSL certificates, document roots, and static files. In Ansible, this maps to a `loop` or `with_dict` construct over a `nginx_sites` variable (list of dicts). The Jinja2 template for `site.conf.erb` translates directly to a `.j2` template. Care must be taken to preserve the conditional SSL block logic (`<% if @ssl_enabled %>`).
- **Platform divergence (Fedora vs Ubuntu)**: The Vagrantfile targets Fedora 42, but the recipes use Ubuntu-specific artefacts: `www-data` user/group, `ufw` (not `firewalld`), `/var/log/auth.log` (Fail2ban logpath), `apt`-style package names (`libpq-dev`, `python3-venv`). Ansible playbooks must include `when: ansible_os_family == "Debian"` / `"RedHat"` conditionals, or the target OS must be standardised before migration begins.
- **PostgreSQL idempotency**: The `create_db_user` execute resource uses `|| true` to suppress errors on re-runs. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require error suppression hacks.
- **Git-based application deployment**: The `git` resource syncs from a public GitHub repository on every Chef run. In Ansible, `ansible.builtin.git` with `update: yes` replicates this. Consider pinning to a specific tag or commit SHA rather than `main` for reproducible deployments.
- **systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, use a handler (`ansible.builtin.systemd: daemon_reload: yes`) notified by the unit file task — this is idiomatic Ansible and preserves the same ordering guarantee.
- **`ssl-cert` group creation**: The `ssl.rb` recipe creates a system group `ssl-cert` and assigns private key ownership to it. Ansible's `ansible.builtin.group` module handles this; ensure the group is created before the certificate tasks run.

---

### Migration Order

The following order minimises dependency risk and allows incremental validation at each stage:

1. **`nginx-multisite` — Security sub-recipe** (`security.rb`): Migrate UFW, Fail2ban, sysctl hardening, and SSH hardening first. These are self-contained, have no inter-cookbook dependencies, and establish the security baseline. Validate with `ufw status`, `fail2ban-client status`, and `sshd -T` checks.

2. **`nginx-multisite` — Nginx + SSL + Sites sub-recipes** (`nginx.rb`, `ssl.rb`, `sites.rb`): Migrate Nginx installation, `nginx.conf` template, self-signed certificate generation, and per-site virtual host configuration. Validate by curling each subdomain over HTTPS and confirming HTTP→HTTPS redirect and security header presence.

3. **`cache` — Memcached**: Migrate Memcached installation and service. Low complexity, no credentials. Validate with `memcached-tool 127.0.0.1:11211 stats`.

4. **`cache` — Redis**: Migrate Redis installation, direct config templating (eliminating the patching hack), and password authentication. Migrate the Redis password to Ansible Vault at this stage. Validate with `redis-cli -a <password> ping`.

5. **`fastapi-tutorial`**: Migrate PostgreSQL provisioning, application git deployment, Python venv setup, `.env` file generation (using vaulted DB password), and systemd service unit. This is the highest-complexity cookbook and depends on PostgreSQL being functional. Validate by querying the FastAPI health endpoint (`curl http://localhost:8000/`) and confirming the systemd service is active.

---

### Assumptions

1. **Target OS standardisation**: It is assumed the production target OS will be clarified before migration begins. The Vagrantfile uses Fedora 42, but the recipe code is written for Ubuntu/Debian. The migration plan assumes **Ubuntu 22.04 LTS** as the primary target unless otherwise specified; platform conditionals will be added for RHEL/Fedora compatibility.
2. **Self-signed certificates in development**: It is assumed self-signed certificates remain acceptable for the Vagrant/development environment. Production certificate strategy (Let's Encrypt, internal CA, or pre-provisioned certs) is out of scope for this migration and must be decided separately.
3. **Redis single-instance, no clustering**: The current configuration deploys a single Redis instance on port 6379. No Sentinel, Cluster, or replication configuration is present. The Ansible migration will replicate this single-instance topology.
4. **Memcached default configuration**: The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides. It is assumed default Memcached settings (port 11211, 64 MB memory, localhost binding) are intentional and will be preserved.
5. **FastAPI application repository availability**: It is assumed `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) remains publicly accessible and that `requirements.txt` is present at the repository root. If the repository becomes private or is relocated, the `ansible.builtin.git` task will require credential configuration.
6. **No Chef Server or Chef Vault in use**: The repository uses Chef Solo exclusively (`solo.rb`, `solo.json`, `vagrant-provision.sh`). No Chef Server API, encrypted data bags, or Chef Vault items were detected. All secrets are currently plain text in recipe files.
7. **`ssl_certificate` community cookbook not actively used**: The `ssl_certificate` cookbook is commented out in `Berksfile` but present in `Policyfile.rb` and locked in `Policyfile.lock.json`. The `ssl.rb` recipe uses raw `openssl` shell commands rather than the cookbook's resources. It is assumed this cookbook is vestigial and will not be migrated.
8. **`www-data` user pre-exists**: The nginx recipes assign document root ownership to `www-data:www-data`. On Ubuntu this user is created by the `nginx` package. On Fedora/RHEL, nginx runs as `nginx:nginx`. The Ansible playbooks must handle this divergence with a variable for the web server user/group.
9. **Vagrant environment retained for testing**: It is assumed the Vagrant + libvirt environment will be retained as the local testing target during migration, with the `chef_solo` provisioner replaced by an `ansible` or `ansible_local` provisioner.
10. **SELinux policy management scope**: The `selinux` cookbook is a transitive dependency of `redisio` but no explicit SELinux policy customisations are present in the local cookbooks. It is assumed SELinux is either permissive or that the default policies for Redis, Nginx, and PostgreSQL are sufficient on RHEL/Fedora targets.
11. **Port 8000 accessibility**: The FastAPI service binds to `0.0.0.0:8000`. No firewall rule for port 8000 is present in the `security.rb` recipe. It is assumed this port is intentionally not exposed externally (accessed only via Nginx proxy or internally), and no UFW rule for it will be added during migration unless explicitly requested.
12. **Nginx document root path discrepancy**: `solo.json` defines document roots under `/var/www/<site>/` while `attributes/default.rb` defines them under `/opt/server/<site>/`. The `solo.json` values override the cookbook defaults at runtime. The Ansible `group_vars` will use the `/var/www/<site>/` paths from `solo.json` as the authoritative values.
