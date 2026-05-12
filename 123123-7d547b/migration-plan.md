# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef-based infrastructure** managed via Chef Solo and Berkshelf, targeting a multi-service web stack. The policy (`nginx-multisite-policy`) orchestrates three local cookbooks — `nginx-multisite`, `cache`, and `fastapi-tutorial` — plus five external Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`).

The stack provisions:
- A hardened Nginx reverse proxy serving three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) with self-signed certificates, UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl security tuning.
- A dual caching layer combining Memcached and Redis (with password authentication).
- A Python FastAPI application backed by PostgreSQL, deployed from a public Git repository into a Python virtual environment and managed as a systemd service.

The development environment is a **Fedora 42 VM** running under **libvirt/KVM** via Vagrant, with port-forwarding for HTTP (8080→80) and HTTPS (8443→443).

**Migration complexity: Medium.** All three cookbooks follow conventional Chef patterns with direct Ansible equivalents. The main challenges are the Redis config post-processing hack, the cross-platform package naming differences (Debian vs. RHEL), and the need to vault-protect three sets of hardcoded credentials. A realistic timeline for a complete, tested migration is **3–4 weeks** for a single engineer, or **1.5–2 weeks** with two engineers working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains three Chef cookbooks that each require an individual Ansible role.

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation via OpenSSL, HTTP→HTTPS redirect, security header injection (HSTS, X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection), per-site access/error logging, and a custom `lineinfile` Chef resource for idempotent file-line management.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - **nginx.rb recipe**: Installs nginx package, deploys `nginx.conf` and `conf.d/security.conf` from ERB templates, creates per-site document roots under `/opt/server/{test,ci,status}` owned by `www-data`, copies static `index.html` files per site.
        - **ssl.rb recipe**: Installs `openssl` and `ca-certificates`, creates `ssl-cert` group, manages `/etc/ssl/certs` (0755) and `/etc/ssl/private` (0710 root:ssl-cert), generates a 2048-bit RSA self-signed certificate per site (365-day validity, idempotent via `not_if` file existence check).
        - **sites.rb recipe**: Renders per-site Nginx vhost configs from `site.conf.erb` into `/etc/nginx/sites-available/`, creates symlinks in `sites-enabled/`, removes the default site.
        - **security.rb recipe**: Installs `fail2ban` and `ufw`, deploys `fail2ban/jail.local` (banning SSH, nginx-http-auth, nginx-limit-req, nginx-botsearch jails), applies UFW rules (default deny, allow SSH/HTTP/HTTPS), deploys `sysctl.d/99-security.conf` (IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable), hardens SSH (`PermitRootLogin no`, `PasswordAuthentication no`).
        - **Custom resource**: `lineinfile` — a Chef LWRP that replicates Ansible's `lineinfile` module behaviour (match-and-replace or append, with timestamped backup).
        - **Attributes**: Sites, SSL paths, and all security flags are defined in `attributes/default.rb` and overridden at node level in `solo.json`.
        - **Templates**: `nginx.conf.erb`, `security.conf.erb`, `site.conf.erb` (SSL-conditional), `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`.
        - **Static files**: Per-site `index.html` pages for `test`, `ci`, and `status` virtual hosts.

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the community `memcached 6.1.0` cookbook) and Redis (via `redisio 7.2.4`) with password authentication, a dedicated `/var/log/redis` log directory, and a post-install Ruby block that surgically removes deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` to ensure compatibility with the installed Redis version.
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation entirely to the upstream `memcached` community cookbook.
        - Configures Redis on port 6379 with `requirepass redis_secure_password_123` (hardcoded credential — **must be vaulted**).
        - Uses `redisio` and `redisio::enable` recipes for installation and service enablement.
        - Post-install `ruby_block` hack strips incompatible config keys from the generated Redis config file — a fragile pattern that must be replaced with a clean Ansible template.
        - `selinux 6.2.4` is a transitive dependency pulled in by `redisio` (relevant for RHEL/Fedora targets).

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application sourced from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`), including Python 3 runtime setup, virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database URL, systemd unit file creation, and service lifecycle management.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.
        - Clones/syncs the application repository to `/opt/fastapi-tutorial` using the Chef `git` resource.
        - Creates a Python venv at `/opt/fastapi-tutorial/venv` (idempotent via `creates`).
        - Installs Python dependencies from `requirements.txt` inside the venv.
        - Enables and starts the `postgresql` service.
        - Provisions PostgreSQL user `fastapi` with password `fastapi_password` and database `fastapi_db` via inline `psql` commands with `|| true` guards (hardcoded credentials — **must be vaulted**).
        - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (credential in plaintext file — **must be vaulted and templated**).
        - Deploys a systemd unit (`fastapi-tutorial.service`) running uvicorn on `0.0.0.0:8000` as `root` (privilege concern — **should run as a dedicated service user**).
        - Reloads systemd daemon and enables/starts the service.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out here but active in `Policyfile.rb`). Not needed post-migration; replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all cookbook version constraints. Equivalent to an Ansible playbook's `roles:` list combined with `requirements.yml`.
- `Policyfile.lock.json`: Pinned dependency graph with exact versions and SHA identifiers for all eight resolved cookbooks. Provides the authoritative version reference for mapping to Ansible Galaxy role versions during migration.
- `solo.json`: Chef Solo node attribute JSON. Overrides site document roots (to `/var/www/…` paths, differing from the cookbook attribute defaults of `/opt/server/…`), SSL certificate/key paths, and all security flags. This file is the primary source of environment-specific variable values and maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo runtime configuration. Sets `file_cache_path`, `cookbook_path` (including a glob for vendored cookbooks), log level, and log destination. Equivalent to `ansible.cfg` settings.
- `Vagrantfile`: Vagrant VM definition. Specifies `generic/fedora42` box, hostname `chef-nginx`, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, libvirt provider with 2 vCPUs / 2 GB RAM, rsync folder sync excluding `.git/`, and shell provisioner invoking `vagrant-provision.sh`. Maps to an Ansible inventory file with `ansible_host`, `ansible_user`, and connection variables.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef-embedded gem, vendors cookbook dependencies, and runs `chef-solo`. Post-migration this is replaced by `ansible-playbook` invocation, eliminating the need for Chef and Berkshelf entirely.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `Policyfile.lock.json`, `generated-project-metadata.json` (cookbook inventory), `solo.json` (node attributes), and a prior draft `migration-plan.md`. These files are reference artefacts and do not need to be migrated.

---

### Target Details

- **Operating System**: **Fedora 42** is the active development target (declared in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for **Ubuntu ≥ 18.04** and **CentOS ≥ 7.0**, indicating the intent to support both Debian and RHEL OS families. For Ansible migration, the primary target should be treated as **Red Hat family (Fedora 42 / RHEL 9-equivalent)**, with conditional task blocks added for Debian/Ubuntu compatibility where package names differ (e.g., `libpq-dev` vs. `postgresql-libs`, `ufw` availability, `www-data` vs. `nginx` user).
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the Vagrantfile (`config.vm.provider "libvirt"`). VM is allocated 2 vCPUs and 2 GB RAM.
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK packages are referenced. The infrastructure is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `nginxinc.nginx` Ansible Galaxy role or the `geerlingguy.nginx` role. Alternatively, manage nginx entirely with native Ansible `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service` modules — preferred given the cookbook's straightforward configuration. The `security.conf.erb` and `nginx.conf.erb` templates translate directly to Ansible Jinja2 templates.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `geerlingguy.memcached` Galaxy role or native `ansible.builtin.package` / `ansible.builtin.service` tasks. The upstream cookbook performs only package install and service enable — a trivial two-task Ansible role.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `geerlingguy.redis` Galaxy role or native tasks. The post-install config-stripping `ruby_block` hack must be replaced with a clean Ansible `ansible.builtin.template` that renders only the supported Redis directives for the installed version, eliminating the fragile sed-equivalent logic entirely.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with Ansible's built-in `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules. These provide idempotent, declarative self-signed certificate generation with full control over subject fields, key size, and validity period — a direct functional equivalent.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with the `ansible.posix.selinux` module and `ansible.posix.seboolean` for any required SELinux boolean adjustments. On Fedora 42, SELinux is enforcing by default; Redis and nginx may require policy adjustments (`httpd_can_network_connect`, Redis port labelling).

### Security Considerations

- **Hardcoded Redis password (`redis_secure_password_123`)**: Found in `cookbooks/cache/recipes/default.rb` as a plain string in the `node.default['redisio']['servers']` attribute block. **1 credential detected.** Must be migrated to an Ansible Vault-encrypted variable (e.g., `vault_redis_password`) and referenced in the Redis configuration template.
- **Hardcoded PostgreSQL credentials (`fastapi` / `fastapi_password`)**: Found in two locations within `cookbooks/fastapi-tutorial/recipes/default.rb` — once in the `psql` provisioning command and once in the `.env` file content block. **2 credential instances (1 logical secret).** Must be migrated to Ansible Vault. The `.env` file must be rendered from a Jinja2 template referencing the vaulted variable rather than containing the literal password.
- **Plaintext `.env` file**: `/opt/fastapi-tutorial/.env` is written with mode `0644` (world-readable) and contains the full database URL including password. In Ansible, this file must be templated with mode `0600` and owned by the service account.
- **Self-signed SSL certificates**: Generated via inline `openssl req` shell commands in `ssl.rb`. Certificates are 2048-bit RSA, 365-day validity, with a hardcoded subject (`/C=US/ST=Example/…/emailAddress=admin@example.com`). In Ansible, use `community.crypto` modules for idempotent generation. For production, replace with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA. The subject fields should be parameterised as Ansible variables.
- **SSL private key permissions**: The Chef recipe sets the key file to mode `0640`, owned `root:ssl-cert`. This must be preserved exactly in the Ansible equivalent tasks.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` commands in `security.rb`. In Ansible, use `ansible.builtin.lineinfile` (the very module the cookbook's custom `lineinfile` resource was mimicking) or the `ansible.builtin.template` module for `/etc/ssh/sshd_config`. Ensure the Ansible control connection is not broken by disabling password auth before SSH key distribution is confirmed.
- **UFW firewall**: Managed via `execute` resources running `ufw` CLI commands. Replace with the `community.general.ufw` Ansible module for fully declarative, idempotent firewall management. On RHEL/Fedora targets, `ufw` may not be available — consider `ansible.posix.firewalld` as the RHEL-native alternative, with OS-family conditionals.
- **fail2ban**: Configured via template (`jail.local`) with four active jails. Replace with `ansible.builtin.template` for `jail.local` and `ansible.builtin.service` for the daemon. The log path `/var/log/auth.log` is Debian-specific; on Fedora/RHEL the equivalent is `/var/log/secure` — this must be parameterised.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk and should be corrected during migration by creating a dedicated `fastapi` system user and updating the `WorkingDirectory`, `ExecStart`, and file ownership accordingly.
- **Sysctl hardening**: 18 kernel parameters are set via `sysctl.d/99-security.conf`. Replace with the `ansible.posix.sysctl` module (one task per parameter) or deploy the file via `ansible.builtin.template` and notify a handler to run `sysctl --system`.

### Technical Challenges

- **Redis config post-processing hack**: The `ruby_block "fix_redis_config"` in `cache/recipes/default.rb` reads and rewrites `/etc/redis/6379.conf` to strip deprecated directives that the `redisio` cookbook emits but the installed Redis version rejects. This is a symptom of using an outdated community cookbook against a newer Redis package. In Ansible, this is resolved cleanly by either (a) using `geerlingguy.redis` which generates a correct config for the detected Redis version, or (b) writing a full Jinja2 template for `redis.conf` that only includes supported directives, bypassing the community role's template entirely.
- **Cross-platform package name divergence**: The `fastapi-tutorial` cookbook installs `libpq-dev` (Debian name) but the active target is Fedora 42, where the equivalent is `libpq-devel` (from `postgresql-devel`). Similarly, `ufw` is not in Fedora's default repos. Ansible tasks must use `ansible_os_family` or `ansible_distribution` conditionals and a variable map for OS-specific package names.
- **`www-data` user on Fedora**: Nginx on Fedora runs as the `nginx` user, not `www-data`. The cookbook hardcodes `owner 'www-data'` for document root directories and static files. Ansible tasks must use a variable (e.g., `nginx_user`) resolved per OS family.
- **Nginx `sites-available` / `sites-enabled` pattern**: This Debian/Ubuntu convention is not present in the default Fedora nginx package layout (which uses `conf.d/`). The Ansible role must either install nginx from a source that supports this layout or adapt the vhost management to use `conf.d/` with conditional includes.
- **Chef `git` resource sync behaviour**: The `git` resource with `action :sync` performs a `git fetch` + `git reset --hard` on every Chef run. The Ansible `ansible.builtin.git` module with `update: yes` and `force: yes` is the equivalent, but care must be taken to avoid overwriting local changes if the deployment workflow allows in-place edits.
- **Attribute precedence and `solo.json` overrides**: The `solo.json` file overrides the cookbook's `attributes/default.rb` values for document roots (`/var/www/…` vs. `/opt/server/…`). In Ansible, this maps to `group_vars` (cookbook defaults) overridden by `host_vars` or extra vars. The migration must explicitly decide which path convention is canonical and document it.
- **Idempotency of `execute` resources**: Several Chef `execute` resources use `not_if` shell guards (e.g., checking `ufw status`, `grep` on sshd_config). Ansible's native modules (`community.general.ufw`, `ansible.builtin.lineinfile`) are inherently idempotent and eliminate the need for these guards, but the migration must verify that the Ansible module semantics match the intended Chef behaviour exactly.
- **systemd daemon-reload ordering**: The Chef recipe notifies `execute[systemd_reload]` with `:immediately` when the unit file changes. In Ansible, this is handled by a handler (`ansible.builtin.systemd: daemon_reload: yes`) triggered by a `notify:` directive on the template task — the ordering is equivalent but the mechanism differs.

### Migration Order

1. **`cache` cookbook → Ansible `cache` role** *(Low complexity, fully independent, no inbound dependencies)*
   - Tasks: Install and configure Memcached (package + service); install and configure Redis with vaulted password using a clean Jinja2 template (eliminating the ruby_block hack); create `/var/log/redis`; enable and start both services.
   - Estimated effort: 2–3 days including testing.

2. **`nginx-multisite` cookbook → Ansible `nginx_multisite` role** *(Medium complexity, depends on SSL tooling, forms the web-serving foundation)*
   - Tasks: Install nginx; deploy `nginx.conf` and `security.conf` templates; generate SSL certificates via `community.crypto` modules; render per-site vhost configs; manage `sites-available`/`sites-enabled` symlinks (or `conf.d/` on Fedora); deploy static site content; configure fail2ban with OS-aware log paths; apply UFW/firewalld rules; harden SSH; apply sysctl parameters.
   - Estimated effort: 5–7 days including cross-platform testing.

3. **`fastapi-tutorial` cookbook → Ansible `fastapi_tutorial` role** *(High complexity, depends on PostgreSQL, involves application deployment, vaulted credentials, and service user creation)*
   - Tasks: Create `fastapi` system user; install system packages (with OS-family package name map); clone/sync Git repository; create Python venv; install pip dependencies; enable and start PostgreSQL; provision database user and database (using `community.postgresql` modules instead of raw `psql` shell commands); template `.env` file with vaulted credentials (mode 0600); deploy systemd unit running as `fastapi` user; reload daemon and start service.
   - Estimated effort: 5–7 days including testing and security remediation.

### Assumptions

1. **Target OS is Fedora 42 (RHEL family)** for the primary deployment environment, matching the Vagrantfile. Ubuntu/CentOS compatibility declared in `metadata.rb` is treated as a secondary concern; OS-family conditionals will be added but not exhaustively tested in the initial migration.
2. **Self-signed certificates are acceptable** for the migrated environment. The `ssl.rb` recipe generates development-grade certificates; no production CA or Let's Encrypt integration exists in the source. If production use is intended, the Ansible role should be extended with an ACME/Let's Encrypt task guarded by a variable flag.
3. **The document root path discrepancy** between `attributes/default.rb` (`/opt/server/{test,ci,status}`) and `solo.json` (`/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}`) will be resolved in favour of the `solo.json` values (`/var/www/…`) as these represent the runtime-applied configuration. This must be confirmed with the team before migration.
4. **Redis is a standalone single-instance deployment** on port 6379 with no replication, clustering, or Sentinel configuration. The `redisio` cookbook's `servers` array contains exactly one entry.
5. **Memcached configuration is entirely delegated** to the upstream community cookbook with no custom attributes set in the `cache` cookbook. Default port (11211), default memory allocation, and localhost binding are assumed.
6. **The FastAPI application repository** (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) is publicly accessible and will remain available. No authentication or SSH key management is required for the `git clone` operation.
7. **PostgreSQL version** is not pinned in the cookbook; the distro-default version will be installed. On Fedora 42 this is PostgreSQL 16. The `community.postgresql` Ansible collection must be version-compatible with the installed PostgreSQL.
8. **The `ssl_certificate` community cookbook** is referenced in `Policyfile.rb` and locked in `Policyfile.lock.json` but is commented out in `Berksfile`. It does not appear to be called by any recipe in the local cookbooks. It is assumed to be an unused dependency and will not be migrated.
9. **The `selinux` cookbook** is a transitive dependency of `redisio` and is not directly invoked by local recipes. SELinux policy management for Redis and nginx on Fedora 42 must be explicitly addressed in the Ansible roles (boolean settings, port labelling) as this was previously handled implicitly by the community cookbook.
10. **Ansible Vault** will be used for all secrets. The three credential sets (Redis password, PostgreSQL user password, PostgreSQL database URL) will each be stored as vault-encrypted variables. A `vault_password_file` or `--ask-vault-pass` workflow must be established before the first playbook run.
11. **The custom `lineinfile` Chef resource** in `cookbooks/nginx-multisite/resources/lineinfile.rb` is a reimplementation of Ansible's native `ansible.builtin.lineinfile` module. It is not called by any recipe in this repository (the SSH hardening in `security.rb` uses raw `execute` + `sed` instead). It will not be migrated; the Ansible native module will be used directly.
12. **Vagrant and libvirt** will be retained as the local development environment. The `vagrant-provision.sh` bootstrap script will be replaced with a Vagrant shell provisioner that installs Ansible and runs `ansible-playbook` against a local inventory, or the Vagrant Ansible provisioner (`config.vm.provision "ansible_local"`) will be used directly.
