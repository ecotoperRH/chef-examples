# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is developed and tested locally via Vagrant (libvirt/Fedora 42) and driven by a `Policyfile.rb` run-list of three local cookbooks plus four external Supermarket dependencies.

**Migration scope:** 3 local Chef cookbooks, 4 external cookbook dependencies, 5 ERB templates, 1 custom Chef resource, 3 static site assets, and supporting infrastructure files (Vagrantfile, solo.json, vagrant-provision.sh).

**Complexity assessment:** Medium. The cookbooks follow standard Chef patterns with direct Ansible equivalents. The main challenges are the Redis config post-processing hack, the multi-site Nginx loop-driven templating, and the need to replace Chef Supermarket community cookbooks with Ansible modules or Galaxy roles. No Chef Server, encrypted data bags, or Chef Vault are in use — secrets are currently stored in plaintext, which must be remediated during migration.

**Timeline estimate:** 3–4 weeks for a complete migration including testing:
- Week 1: Security hardening + Nginx multi-site role
- Week 2: Cache role (Memcached + Redis)
- Week 3: FastAPI + PostgreSQL role
- Week 4: Integration testing, Vagrant/CI validation, documentation

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation per vhost, HTTP-to-HTTPS redirect, security response headers (HSTS, X-Frame-Options, CSP, X-XSS-Protection), gzip compression, and a dedicated security hardening sub-recipe (fail2ban, UFW firewall, SSH hardening, sysctl kernel parameters)
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Loop-driven vhost templating from node attributes, per-site document root creation with static `index.html` assets, `sites-available`/`sites-enabled` symlink management, default site removal, `openssl req` self-signed certificate generation (RSA 2048, 365-day), TLSv1.2/1.3-only cipher suite, rate-limiting zones (`login`, `api`), fail2ban jails for sshd/nginx-http-auth/nginx-limit-req/nginx-botsearch, UFW default-deny with SSH/HTTP/HTTPS allow rules, sysctl hardening (rp_filter, SYN cookies, ICMP redirect suppression, IPv6 disable), SSH root login and password authentication disabled via `sed`, custom `lineinfile` LWRP

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication, plus a post-install Ruby block that surgically removes deprecated Redis config directives incompatible with the installed Redis version
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Redis password set to `redis_secure_password_123` (hardcoded plaintext), Redis listening on port 6379, `/var/log/redis` directory creation, `redisio::enable` for service management, post-processing hack via `ruby_block` to strip `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` directives from `/etc/redis/6379.conf`

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, including system package installation, Python virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database URL, and systemd unit file creation for the `uvicorn`-based service
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`), Python 3 venv at `/opt/fastapi-tutorial/venv`, PostgreSQL user `fastapi` with hardcoded password `fastapi_password` (plaintext), database `fastapi_db`, `.env` file containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plaintext, mode `0644`), systemd service running as `root` with `Restart=always`, `uvicorn` on `0.0.0.0:8000`

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring the three local cookbooks and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out in Berksfile but present and locked in `Policyfile.lock.json`). Must be replaced by an Ansible `requirements.yml` referencing Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy` and the ordered run-list `[nginx-multisite::default, cache::default, fastapi-tutorial::default]`. The run-list order encodes an implicit dependency: security/nginx must be ready before the app tier. This ordering must be preserved in Ansible playbook task ordering.
- `Policyfile.lock.json`: Pinned dependency graph locking `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4` (transitive dep of redisio). The `selinux` cookbook is a hidden transitive dependency not declared in `Berksfile` — its equivalent SELinux handling must be accounted for in Ansible (particularly relevant on Fedora/RHEL targets).
- `solo.json`: Chef Solo node JSON providing run-list and attribute overrides. Defines three vhosts with SSL enabled, SSL cert/key paths (`/etc/ssl/certs`, `/etc/ssl/private`), and security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth: false`). Note: document roots in `solo.json` (`/var/www/<site>`) differ from cookbook attribute defaults (`/opt/server/<site>`) — the `solo.json` values take precedence at runtime. This discrepancy must be resolved and a single canonical value chosen in Ansible `group_vars`.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks` (Berkshelf vendor output), with cache at `/var/chef-solo`. Replaced entirely by Ansible inventory and `ansible.cfg`.
- `Vagrantfile`: Vagrant configuration using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, forwarded ports 80→8080 and 443→8443, rsync sync of repo to `/chef-repo`. Commented-out `/etc/hosts` entries for the three vhosts indicate manual DNS resolution is required for local testing. The Vagrant setup should be replaced by an Ansible-compatible `Vagrantfile` using the `ansible` provisioner, or a molecule test scenario.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo`. This entire script is replaced by Ansible's agentless push model — no bootstrap script is needed.

---

### Target Details

- **Operating System**: Fedora 42 (primary runtime, as declared in `Vagrantfile` with `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. Ansible roles must handle both Debian/Ubuntu (`apt`, `ufw`, `www-data` user) and RHEL/Fedora (`dnf`, `firewalld`, `nginx` user) package and service name differences. Default to **Red Hat Enterprise Linux 9 / Fedora** as the primary target given the Vagrantfile evidence.
- **Virtual Machine Technology**: libvirt / KVM (explicitly declared in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role, or use the `ansible.builtin.package` + `ansible.builtin.template` modules directly. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) translate directly to Jinja2 templates with minimal variable substitution changes (`<%= @var %>` → `{{ var }}`).
- **memcached (6.1.0, Chef Supermarket)**: Replace with `geerlingguy.memcached` Galaxy role or direct `ansible.builtin.package` / `ansible.builtin.service` tasks. Memcached configuration in this stack is default (no custom `memcached.conf` overrides detected).
- **redisio (7.2.4, Chef Supermarket)**: Replace with `geerlingguy.redis` Galaxy role or `ansible.builtin.package` + `ansible.builtin.template`. The post-install config-stripping hack (removing deprecated directives) must be replicated — use `ansible.builtin.lineinfile` with `state: absent` and a `regexp` for each deprecated directive, or template the Redis config directly to avoid the issue entirely.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection. This is a cleaner and more idiomatic solution than the current `openssl req` shell command.
- **selinux (6.2.4, Chef Supermarket — transitive)**: Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` for any boolean adjustments. On Fedora 42, SELinux is enforcing by default; nginx and Redis may require policy adjustments (`httpd_can_network_connect`, file context labels on non-standard document roots).

---

### Security Considerations

- **Hardcoded Redis password (`redis_secure_password_123`)**: Found plaintext in `cookbooks/cache/recipes/default.rb` as a node attribute assignment. **1 credential detected.** Must be moved to Ansible Vault (`ansible-vault encrypt_string`) and referenced as a variable (e.g., `vault_redis_password`).
- **Hardcoded PostgreSQL credentials (`fastapi` / `fastapi_password`)**: Found plaintext in `cookbooks/fastapi-tutorial/recipes/default.rb` in both the `psql` provisioning commands and the `.env` file content. **2 credentials detected (username + password).** Must be stored in Ansible Vault. The `.env` file template must use a Jinja2 variable and the file permissions should be tightened from `0644` to `0600`.
- **FastAPI `.env` file permissions**: Currently created with mode `0644` and owned by `root:root`, meaning the database URL (including password) is world-readable. Must be changed to `0600` in the Ansible `ansible.builtin.template` task.
- **FastAPI service running as root**: The systemd unit file sets `User=root`. This is a significant security risk and should be remediated during migration by creating a dedicated `fastapi` system user and adjusting file ownership accordingly.
- **Self-signed SSL certificates**: Generated via `openssl req` shell command with a hardcoded subject string (`/C=US/ST=Example/...`). Acceptable for development but must be flagged for replacement with CA-signed or Let's Encrypt certificates in production. The `community.crypto` collection provides a clean migration path.
- **Private key permissions**: The SSL recipe sets `chmod 640` and `chown root:ssl-cert` on private keys. This must be replicated precisely in Ansible using `ansible.builtin.file` with `owner: root`, `group: ssl-cert`, `mode: '0640'`.
- **UFW firewall management**: The `security.rb` recipe uses raw `execute` resources with `ufw` CLI commands and idempotency guards via `not_if` shell checks. Replace with the `community.general.ufw` Ansible module for cleaner idempotency. Note: on Fedora/RHEL, `ufw` is not the default firewall — `firewalld` is standard. A platform-conditional approach (`when: ansible_os_family == "Debian"` / `"RedHat"`) will be required.
- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed` commands wrapped in `execute` resources. Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`, with a handler to restart `sshd`.
- **sysctl hardening**: The `sysctl-security.conf.erb` template disables IPv6 globally (`net.ipv6.conf.all.disable_ipv6 = 1`) and ignores all ICMP pings (`net.ipv4.icmp_echo_ignore_all = 1`). These are aggressive settings that may break monitoring or cloud metadata access — they should be reviewed and made configurable via Ansible variables before applying to production.
- **fail2ban jails**: The `fail2ban.jail.local.erb` template configures four jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch). The log path for `sshd` jail is `/var/log/auth.log` (Debian convention); on Fedora/RHEL this is `/var/log/secure`. The template must be parameterized by OS family in Ansible.
- **No Chef encrypted data bags or Chef Vault in use**: Secrets are entirely in plaintext recipe code and node JSON. This simplifies migration but means the Ansible Vault adoption represents a security improvement over the current state.

---

### Technical Challenges

- **Document root path discrepancy**: The cookbook `attributes/default.rb` defines document roots as `/opt/server/{test,ci,status}`, but both `solo.json` files (root and `.myprj/`) override these to `/var/www/{site-name}`. Chef attribute precedence resolves this at runtime, but the Ansible migration must pick one canonical path and set it consistently in `group_vars`. The static `index.html` files reference `/opt/server/` paths in their content, so those files will also need updating.
- **Redis post-install config hack**: `cache/recipes/default.rb` uses a `ruby_block` to strip deprecated directives from `/etc/redis/6379.conf` after `redisio` writes it. This workaround exists because `redisio 7.2.4` generates config keys not supported by the installed Redis version. In Ansible, the cleanest solution is to template the Redis configuration directly (bypassing the Galaxy role's template) or use `ansible.builtin.lineinfile` with `state: absent` for each offending directive. The specific directives to remove are: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom Chef resource that mimics Ansible's own `lineinfile` module (match-and-replace or append). This resource is not called anywhere in the current recipes (no `lineinfile` resource calls found in recipe files), suggesting it may be dead code or intended for future use. It can be dropped in the Ansible migration since `ansible.builtin.lineinfile` provides this functionality natively.
- **Loop-driven multi-site configuration**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, copy files, render templates, and create symlinks. In Ansible, this maps to `loop:` over a `nginx_sites` list variable defined in `group_vars`, with `ansible.builtin.template`, `ansible.builtin.file`, and `ansible.builtin.copy` tasks. The `site_folder = site_name.split('.').first` logic (extracting `test`, `ci`, `status` from FQDNs) must be replicated in Jinja2 (e.g., `{{ item.name.split('.')[0] }}`).
- **Nginx `sites-available`/`sites-enabled` pattern**: This is a Debian/Ubuntu convention. On Fedora/RHEL, Nginx uses `/etc/nginx/conf.d/` exclusively. The Ansible role must handle this difference — either standardize on `conf.d/` for all platforms or use `when:` conditionals.
- **FastAPI application running as root**: The systemd unit runs `uvicorn` as `root`. Creating a dedicated service account (`fastapi` user) during migration will require updating file ownership on `/opt/fastapi-tutorial/` and the `.env` file, and adjusting the systemd unit. This is a breaking change from the current Chef behavior and must be coordinated.
- **Git-based application deployment**: `fastapi-tutorial/recipes/default.rb` uses Chef's `git` resource to clone/sync the application. In Ansible, `ansible.builtin.git` is the direct equivalent. However, the `action :sync` behavior (which resets to the specified revision) must be replicated carefully — Ansible's `git` module with `force: yes` and `version: main` achieves this.
- **Platform package name differences**: `fail2ban` and `ufw` are Ubuntu/Debian package names. On Fedora, `fail2ban` is available but `ufw` is not — `firewalld` is the standard. The Ansible roles must use `ansible_os_family` or `ansible_distribution` conditionals to install the correct firewall package and configure the correct service.
- **Vagrant `/etc/hosts` entries are commented out**: The three vhosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) require DNS resolution. The Vagrantfile has the `/etc/hosts` provisioning block commented out. In the Ansible migration, an `ansible.builtin.lineinfile` task should manage these entries, or a dedicated DNS/hosts role should be added.

---

### Migration Order

1. **`nginx-multisite` — Security sub-recipe** (lowest risk, highest value as a standalone hardening baseline)
   - Translate `security.rb` to an Ansible `security` role with tasks for fail2ban, UFW/firewalld, SSH hardening, and sysctl
   - Parameterize all security flags via `group_vars` (mirroring `solo.json` security block)
   - Store no secrets (this recipe has none)
   - Validate with molecule or Vagrant + `ansible` provisioner

2. **`nginx-multisite` — Nginx + SSL + Sites sub-recipes** (moderate complexity, depends on security role being in place)
   - Create `nginx` Ansible role with Jinja2 equivalents of all five ERB templates
   - Implement `community.crypto` certificate generation loop
   - Implement vhost loop with `sites-available`/`sites-enabled` (Debian) or `conf.d/` (RHEL) handling
   - Resolve document root path discrepancy and update static `index.html` content accordingly
   - Validate all three vhosts respond correctly over HTTPS

3. **`cache` — Memcached** (low complexity, fully independent)
   - Add Memcached tasks to a `cache` Ansible role using `geerlingguy.memcached` or direct package/service tasks
   - No secrets involved

4. **`cache` — Redis** (moderate complexity due to config hack)
   - Add Redis tasks to the `cache` role
   - Move `redis_secure_password_123` to Ansible Vault
   - Template Redis config directly or use `lineinfile` to strip deprecated directives
   - Validate Redis authentication works post-deployment

5. **`fastapi-tutorial`** (highest complexity, depends on PostgreSQL and network access to GitHub)
   - Create `fastapi` Ansible role
   - Add dedicated `fastapi` system user (security remediation)
   - Implement `ansible.builtin.git` clone/sync task
   - Move PostgreSQL credentials to Ansible Vault
   - Implement PostgreSQL provisioning tasks (`community.postgresql` collection)
   - Template `.env` file with `mode: '0600'`
   - Deploy and enable systemd unit
   - Validate FastAPI service starts and responds on port 8000

---

### Assumptions

1. **Target OS is Fedora 42 / RHEL-family** as the primary deployment target based on the Vagrantfile (`generic/fedora42`), though cookbook metadata also declares Ubuntu ≥ 18.04 and CentOS ≥ 7 support. The Ansible roles should be written with OS-family conditionals to support both, but Fedora/RHEL is the primary test target.
2. **Self-signed certificates are acceptable for the initial Ansible migration** (development/staging context). Production deployments will require a separate decision on certificate authority (internal CA, Let's Encrypt via `certbot`, or imported certificates).
3. **The document root canonical path must be decided before migration begins.** The cookbook attributes say `/opt/server/{test,ci,status}` but `solo.json` overrides to `/var/www/{site}`. The static HTML files reference `/opt/server/` in their displayed content. A single value must be chosen and applied consistently across Ansible variables and static file content.
4. **The GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` is assumed to remain publicly accessible** during and after migration. If it becomes private or is moved, the `ansible.builtin.git` task will require credential configuration.
5. **No Chef Server, Chef Automate, or hosted Chef infrastructure is in use.** The stack runs entirely via `chef-solo`, so there is no Chef Server API, node object, or data bag infrastructure to decommission.
6. **Redis and Memcached are single-instance, non-clustered deployments.** No replication, Sentinel, or Cluster configuration is present. The Ansible migration should maintain this topology unless explicitly requested otherwise.
7. **The `ssl_certificate` Chef cookbook is locked in `Policyfile.lock.json` but commented out in `Berksfile`.** It is assumed this cookbook is not actively used in the current run and its functionality is handled by the `openssl req` shell command in `ssl.rb`. The `community.crypto` collection will cover both use cases.
8. **The custom `lineinfile` LWRP in `cookbooks/nginx-multisite/resources/lineinfile.rb` is dead code** (no calls to it found in any recipe). It will not be migrated.
9. **The `selinux` cookbook (transitive dependency via `redisio`) implies SELinux is enforcing on the target.** Ansible tasks for nginx (non-standard document roots under `/opt/server/`) and Redis will require `community.general.sefcontext` or `ansible.posix.seboolean` tasks to avoid permission denials.
10. **Vagrant is used only for local development and testing**, not production. The Ansible migration should produce a `Vagrantfile` using the `ansible` provisioner (replacing `vagrant-provision.sh`) as the local development workflow, and a separate inventory for production/staging targets.
11. **The FastAPI service account remediation (root → dedicated user) is treated as an in-scope security improvement** during migration, not a separate project. Stakeholders should be informed this is a behavioral change from the current Chef deployment.
12. **Ansible Vault will be used for all secrets** identified in this plan (Redis password, PostgreSQL password, PostgreSQL username). The vault password management strategy (vault password file, `--ask-vault-pass`, or integration with a secrets manager) must be decided by the team before migration begins.
