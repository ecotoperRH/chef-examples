# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through a Vagrant-managed Fedora 42 VM using `chef-solo`.

The infrastructure provisions:
- A hardened **Nginx reverse proxy** serving three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`)
- A **caching layer** combining Memcached and Redis (with password authentication)
- A **FastAPI Python application** backed by PostgreSQL, deployed as a systemd service

The migration is of **moderate complexity**. The local cookbook logic is well-structured and maps cleanly to Ansible roles and tasks. The primary challenges are replacing Chef Supermarket community cookbook abstractions (`nginx`, `memcached`, `redisio`) with native Ansible modules, managing hardcoded credentials, and converting the custom `lineinfile` Chef resource to Ansible's built-in equivalent. A custom GitHub Actions CI pipeline enforcing `ansible-lint` is required per project rules.

**Estimated migration timeline: 5–8 days** for a single experienced Ansible engineer, broken down as:
- `nginx-multisite` role: 2–3 days (most complex; security hardening, SSL, multi-site templating)
- `cache` role: 1–2 days (Redis + Memcached, config patching workaround)
- `fastapi-tutorial` role: 1–2 days (Python venv, PostgreSQL setup, systemd service)
- Integration, testing, and CI setup: 1 day

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts, kernel-level security hardening, UFW firewall management, and Fail2Ban intrusion prevention. Serves three subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with self-signed TLS certificates, HTTP→HTTPS redirect, HSTS, and a full suite of security response headers (X-Frame-Options, CSP, X-Content-Type-Options). Includes a custom `lineinfile` Chef resource and a dedicated `security.conf` Nginx snippet for rate limiting and buffer overflow protection.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Multi-recipe structure (`default`, `nginx`, `ssl`, `sites`, `security`), ERB-templated `nginx.conf` and per-site `site.conf`, self-signed certificate generation via `openssl req`, UFW rule management via shell commands, Fail2Ban with custom `jail.local`, sysctl kernel hardening (`net.ipv4.*`/`net.ipv6.*`), SSH hardening (disable root login, disable password auth), custom `lineinfile` LWRP, per-site static `index.html` files deployed from cookbook files.

- **cache**:
  - Description: Caching services configuration that installs and configures both Memcached (via the community cookbook) and Redis (via the `redisio` community cookbook) with password-based authentication. Includes a post-install Ruby block workaround to strip deprecated Redis configuration directives from the generated config file.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Delegates Memcached setup to the `memcached` Supermarket cookbook (v6.1.0), configures Redis on port 6379 with `requirepass` authentication, creates `/var/log/redis` directory with correct ownership, applies a `ruby_block` hack to remove deprecated `replica-*` and `client-output-buffer-limit` directives from `/etc/redis/6379.conf` post-generation, enables Redis via `redisio::enable`.

- **fastapi-tutorial**:
  - Description: End-to-end deployment of a Python FastAPI application sourced from a public GitHub repository, with a PostgreSQL database backend, Python virtual environment, pip dependency installation, and systemd service management. Writes a `.env` file containing database credentials and application configuration directly to disk.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Installs system packages (`python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`), clones `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch, creates Python venv at `/opt/fastapi-tutorial/venv`, installs pip requirements, configures and starts `postgresql` service, creates PostgreSQL user `fastapi` and database `fastapi_db` via inline `psql` shell commands, writes plaintext `.env` file with `DATABASE_URL` containing credentials, deploys a systemd unit file for `uvicorn` running on `0.0.0.0:8000`, runs as `root` user.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local and external cookbook sources. References Chef Supermarket for `nginx (~> 12.0)`, `memcached (~> 6.0)`, `redisio (~> 7.2.4)`. The commented-out `ssl_certificate` entry indicates it was considered but replaced by inline `openssl` commands. Not needed in Ansible — replace with `requirements.yml` for any Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook versions. Maps directly to an Ansible playbook with ordered role application.
- `Policyfile.lock.json`: Locked dependency graph including transitive dependencies (`selinux 6.2.4` pulled in by `redisio`). Documents exact resolved versions for all 8 cookbooks. Useful as a reference for identifying all implicit behaviors inherited from community cookbooks.
- `solo.json`: Chef Solo node JSON providing runtime attributes — site definitions (document roots, SSL flags), SSL certificate/key paths, and security flags (Fail2Ban, UFW, SSH hardening). Maps directly to Ansible `group_vars` or role `vars`.
- `solo.rb`: Chef Solo configuration pointing to cookbook paths and cache directory. No Ansible equivalent needed; replaced by `ansible.cfg` and inventory.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box with `libvirt` provider, 2 vCPUs, 2 GB RAM, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443. Indicates the **target OS is Fedora 42** (RHEL-family). The Ansible inventory should target this same host configuration.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. In Ansible, this is replaced by running `ansible-playbook` directly. The script also reveals that `apt-get` is called inside the VM — a discrepancy with the Fedora/RHEL base box that must be resolved (see Technical Challenges).
- `x2a-rules/c0dd620f-0b0e-4cd0-9fe9-e0d67449b466.md`: Project-level rule requiring all migrated Ansible projects to include a GitHub Actions workflow (`.github/workflows/ansible-ci.yml`) that runs `ansible-lint roles/ --strict` on every pull request targeting `main`.

---

### Target Details

- **Operating System**: **Fedora 42** (RHEL/DNF family), as declared by `config.vm.box = "generic/fedora42"` in the `Vagrantfile`. The `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`, and the `vagrant-provision.sh` script incorrectly calls `apt-get` — indicating the cookbooks were originally developed for Debian/Ubuntu but the Vagrant environment targets Fedora. The Ansible migration must resolve this OS family conflict and use `dnf`/`yum` module where appropriate, or explicitly target Ubuntu if that is the intended production OS.
- **Virtual Machine Technology**: **KVM/libvirt**, as specified by `config.vm.provider "libvirt"` in the `Vagrantfile`. VM is configured with 2 vCPUs and 2048 MB RAM.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook: Replace with Ansible's `ansible.builtin.package` module to install `nginx` from the OS package manager, and `ansible.builtin.template` for `nginx.conf` and `security.conf`. The ERB templates already exist and need only minor syntax conversion to Jinja2.
- **memcached (6.1.0)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` to install `memcached` and `ansible.builtin.service` to enable/start it. Default configuration is sufficient for the current use case; no custom `memcached.conf` is present in the local cookbook.
- **redisio (7.2.4)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (`redis` or `redis-server` depending on OS), `ansible.builtin.template` for `/etc/redis/6379.conf`, and `ansible.builtin.service`. The post-install config-patching `ruby_block` hack (stripping deprecated directives) must be replicated using `ansible.builtin.lineinfile` with `state: absent` or `ansible.builtin.replace` — this is a direct and clean mapping.
- **selinux (6.2.4)** — Transitive dependency of `redisio`: On Fedora/RHEL targets, SELinux management is needed. Use the `ansible.posix.selinux` module or the `community.general.selinux_permissive` module. On Ubuntu targets, this dependency is irrelevant.
- **ssl_certificate (2.1.0)** — Present in `Policyfile.lock.json` but commented out in `Berksfile`; SSL is handled inline via `openssl req` shell commands. Replicate with `ansible.builtin.command` or the `community.crypto.x509_certificate` + `community.crypto.openssl_privatekey` modules for idempotent self-signed certificate generation.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123`) in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`): This plaintext credential must be moved to **Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable (e.g., `{{ redis_password }}`). **1 credential detected.**
- **Hardcoded PostgreSQL credentials** in `cookbooks/fastapi-tutorial/recipes/default.rb`: The `psql` commands embed `PASSWORD 'fastapi_password'` and the `.env` file contains `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`. Both must be vaulted. **2 credentials detected** (DB user password + DATABASE_URL connection string).
- **Plaintext `.env` file** written to `/opt/fastapi-tutorial/.env` with mode `0644` (world-readable): In Ansible, use `ansible.builtin.template` with mode `0600` and populate credentials from Ansible Vault variables. The file owner should be changed from `root` to a dedicated service account.
- **FastAPI service runs as root**: The systemd unit file sets `User=root`. This is a significant security risk. The Ansible migration should create a dedicated `fastapi` system user and update the service definition accordingly.
- **Self-signed SSL certificates**: Generated via `openssl req` with a hardcoded subject (`/C=US/ST=Example/...`). These are appropriate for development/test but must be flagged for replacement with CA-signed or Let's Encrypt certificates in production. Use `community.crypto` collection modules for idempotent certificate management.
- **SSL private key permissions**: The `ssl.rb` recipe sets `chmod 640` and `chown root:ssl-cert` on private keys — this correct practice must be preserved in the Ansible equivalent using `ansible.builtin.file` with `owner: root`, `group: ssl-cert`, `mode: '0640'`.
- **SSH hardening** (disable root login, disable password authentication): Implemented via `sed` commands in `security.rb`. Replace with `ansible.builtin.lineinfile` targeting `/etc/ssh/sshd_config` with proper `regexp`/`line` parameters and a handler to restart `sshd`.
- **UFW firewall rules**: Managed via raw `ufw` shell commands with `not_if` guards. Replace with `community.general.ufw` module for idempotent firewall management.
- **Fail2Ban configuration**: Templated `jail.local` with bans for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`. Migrate the ERB template to Jinja2 and deploy with `ansible.builtin.template`.
- **Sysctl kernel hardening**: 20+ kernel parameters set via `/etc/sysctl.d/99-security.conf`. Use `ansible.posix.sysctl` module for each parameter rather than a raw template, enabling idempotent per-parameter management.
- **No Chef Vault or encrypted data bags detected**: Secrets are stored as plaintext node attributes and inline strings — all must be migrated to Ansible Vault before the playbook is committed to version control.

---

### Technical Challenges

- **OS family mismatch**: The `Vagrantfile` targets `generic/fedora42` (DNF/RPM), but `vagrant-provision.sh` calls `apt-get update` and `apt-get install -y build-essential`, and the cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The package names (`nginx`, `redis`, `memcached`, `postgresql`, `libpq-dev`) differ between Debian and RHEL families. The Ansible migration must make a definitive OS target decision and use the correct package names, or implement `when: ansible_os_family == "..."` conditionals. **This is the highest-priority clarification needed before migration begins.**
- **`www-data` user on Fedora**: The `nginx.rb` recipe sets Nginx document root ownership to `www-data:www-data`, which is the Debian/Ubuntu Nginx user. On Fedora/RHEL, the Nginx user is `nginx`. The Ansible role must use the correct user, either hardcoded or via a variable conditioned on `ansible_os_family`.
- **`redisio` config-patching hack**: The `ruby_block "fix_redis_config"` in `cache/recipes/default.rb` strips deprecated Redis directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated config. This implies the `redisio` community cookbook generates a config with directives unsupported by the installed Redis version. In Ansible, write the Redis config directly via template (bypassing the community cookbook entirely), eliminating the need for this workaround.
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom LWRP that appends or replaces lines in files, with timestamped backup creation. This maps directly to Ansible's built-in `ansible.builtin.lineinfile` module, which is more robust. The backup behavior (timestamped `.backup.<epoch>` files) is non-standard and should be reviewed — Ansible's `backup: yes` creates a single timestamped backup.
- **`git` resource with `action :sync`**: The `fastapi-tutorial` recipe clones a public GitHub repo (`https://github.com/dibanez/fastapi_tutorial.git`) at the `main` branch and syncs on every run. Use `ansible.builtin.git` with `update: yes` and `version: main`. Ensure the target host has `git` installed before this task runs.
- **Idempotency of PostgreSQL setup**: The `create_db_user` execute block uses `|| true` to suppress errors on duplicate user/database creation. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **`systemctl daemon-reload` notification**: The Chef recipe notifies `execute[systemd_reload]` immediately after writing the systemd unit file. In Ansible, use a handler with `ansible.builtin.systemd` (`daemon_reload: yes`) triggered by a `notify` on the template task.
- **Document root path discrepancy**: `solo.json` defines document roots as `/var/www/<site>` (e.g., `/var/www/test.cluster.local`), while `attributes/default.rb` defines them as `/opt/server/<site>` (e.g., `/opt/server/test`). The `solo.json` values override the cookbook defaults at runtime. The Ansible `group_vars` must use the `/var/www/<site>` paths to match the runtime behavior.
- **`ssl_certificate` cookbook in lock but commented in Berksfile**: The `Policyfile.lock.json` includes `ssl_certificate 2.1.0` as a resolved dependency, but it is commented out in `Berksfile`. This suggests it may be an indirect dependency or a leftover. No direct usage of `ssl_certificate` resources was found in the local cookbooks — SSL is handled via raw `openssl` commands. No action needed in Ansible beyond the `community.crypto` approach.

---

### Migration Order

1. **`nginx-multisite` → Ansible role: `nginx_multisite`** *(Priority 1 — foundational, highest value, self-contained)*
   Migrate security hardening (UFW, Fail2Ban, sysctl, SSH), Nginx installation, template conversion (ERB→Jinja2 for `nginx.conf`, `security.conf`, `site.conf`, `fail2ban.jail.local`, `sysctl-security.conf`), SSL certificate generation, and multi-site virtual host management. This role has no dependencies on the other two cookbooks and delivers the most visible infrastructure outcome. Establish the Ansible role directory structure, `group_vars`, and GitHub Actions CI workflow here.

2. **`cache` → Ansible role: `cache`** *(Priority 2 — moderate complexity, depends on OS package resolution)*
   Migrate Memcached installation and Redis installation/configuration. Write the Redis config directly via Jinja2 template (eliminating the `ruby_block` hack). Vault the Redis password. Validate idempotency of service management. This role depends on the OS family decision made during the `nginx-multisite` migration.

3. **`fastapi-tutorial` → Ansible role: `fastapi_tutorial`** *(Priority 3 — highest credential risk, depends on PostgreSQL and network access)*
   Migrate Python package installation, git clone, venv creation, pip install, PostgreSQL user/database provisioning (using `community.postgresql` modules), `.env` file templating with vaulted credentials, and systemd service deployment. Address the `root` user security issue by introducing a dedicated `fastapi` system account. This role has the most security remediation work and should be migrated last after vault patterns are established.

---

### Assumptions

1. **Target OS must be confirmed**: The repository contains a fundamental contradiction — the Vagrant box is `generic/fedora42` (RPM/DNF) but the provisioning script uses `apt-get` and the metadata declares Ubuntu/CentOS support. It is assumed the **intended production target is Ubuntu 22.04 LTS** (given `apt-get`, `www-data` user, `ufw`, and `/etc/ssh/sshd_config` patterns), and the Fedora Vagrant box may be an environment-specific choice. This must be confirmed with the team before package names and service names are finalized in Ansible.

2. **Self-signed certificates are acceptable for the target environment**: The SSL recipe generates self-signed certificates with a hardcoded example subject. It is assumed this is intentional for the current (development/test) environment. Production deployments will require a separate certificate provisioning strategy (e.g., Let's Encrypt via `community.crypto.acme_certificate`).

3. **The FastAPI application repository is publicly accessible**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git` without authentication. It is assumed this repository remains public and accessible from the target hosts. If it becomes private, SSH key or token-based authentication will need to be added to the Ansible role.

4. **PostgreSQL is installed from OS packages**: No specific PostgreSQL version is pinned in the Chef recipe. It is assumed the version provided by the OS package manager is acceptable. If a specific version is required, the Ansible role will need to configure the official PostgreSQL APT/YUM repository.

5. **Memcached requires no custom configuration**: The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides. It is assumed default Memcached settings (port 11211, 64 MB memory, localhost binding) are sufficient. If custom settings are needed, they must be identified before migration.

6. **The `lineinfile` custom resource is not used outside of `nginx-multisite`**: No calls to the custom `lineinfile` resource were found in any recipe. It appears to be defined but unused in the current run list. It is assumed it can be safely dropped and replaced by `ansible.builtin.lineinfile` if needed in future tasks.

7. **No Chef Server or data bags are in use**: The infrastructure uses `chef-solo` exclusively. There are no encrypted data bags, Chef Vault items, or Chef Server API calls. All configuration is self-contained in the repository.

8. **The `selinux` transitive dependency requires no active configuration**: `selinux 6.2.4` is pulled in by `redisio` but no explicit SELinux resource calls appear in the local cookbooks. It is assumed SELinux is either disabled or in permissive mode on the target hosts. If enforcing mode is required, `ansible.posix.selinux` and appropriate boolean/context tasks must be added.

9. **The three virtual hosts (`test`, `ci`, `status`) are the complete set of sites**: No dynamic site generation beyond the three defined in `attributes/default.rb` and `solo.json` is present. The Ansible role will manage exactly these three sites unless the inventory variables are extended.

10. **GitHub Actions is the target CI platform**: Per the `x2a-rules` project rule, a `.github/workflows/ansible-ci.yml` workflow running `ansible-lint roles/ --strict` on pull requests to `main` must be included. It is assumed the migrated repository will be hosted on GitHub.

11. **The document root paths from `solo.json` (`/var/www/<site>`) take precedence** over the cookbook attribute defaults (`/opt/server/<site>`), as `solo.json` represents the actual runtime node configuration. The Ansible `group_vars` will use `/var/www/<site>` paths.

12. **Redis authentication password and PostgreSQL credentials will be rotated** before being stored in Ansible Vault. The current plaintext values (`redis_secure_password_123`, `fastapi_password`) are assumed to be development placeholders and must not be vaulted as-is for any non-development environment.
