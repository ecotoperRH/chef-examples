# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack managing three cookbooks that together provision a hardened Nginx multi-site web server, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL. The policy is named `nginx-multisite-policy` and the full run list is `nginx-multisite::default → cache::default → fastapi-tutorial::default`.

The migration is of **medium complexity**. All three cookbooks follow conventional Chef patterns (package/template/service resources, attribute-driven configuration, ERB templates) that map cleanly to Ansible equivalents. The most notable complications are: a hardcoded Redis password in a recipe, hardcoded PostgreSQL credentials written to a `.env` file, a custom `lineinfile` LWRP that must be replaced with the native Ansible `lineinfile` module, and a `ruby_block` hack that patches the Redis config file post-install. None of these are blockers, but each requires deliberate handling.

**Estimated migration effort: 3–4 weeks** for a single engineer, including playbook authoring, Ansible Vault integration for secrets, and functional testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), full security hardening (fail2ban, UFW firewall, kernel sysctl tuning), and self-signed TLS certificate generation via OpenSSL
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features: Per-site `sites-available`/`sites-enabled` symlink management, HTTP→HTTPS redirect, TLSv1.2/1.3-only cipher suite, HSTS + security response headers (X-Frame-Options, CSP, X-Content-Type-Options), gzip compression, fail2ban jails for sshd / nginx-http-auth / nginx-limit-req / nginx-botsearch, UFW default-deny with SSH/HTTP/HTTPS allow rules, sysctl hardening (IP spoofing protection, ICMP redirect blocking, SYN-cookie flood protection, IPv6 disable), SSH root login and password authentication disabled, custom `lineinfile` LWRP, five ERB templates, three static site `index.html` files

- **cache**:
    - Description: Dual in-memory caching layer installing and configuring Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication enabled
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features: Redis listening on port 6379 with `requirepass redis_secure_password_123` (hardcoded), dedicated `/var/log/redis` log directory, post-install `ruby_block` that strips deprecated `replica-*` and `client-output-buffer-limit` directives from the generated Redis config to work around a `redisio` 7.2.4 compatibility issue, Memcached installed with community cookbook defaults

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running inside a Python virtual environment under systemd, backed by a locally provisioned PostgreSQL database with a dedicated user and database
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features: System packages (`python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`), `git` resource syncing `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch to `/opt/fastapi-tutorial`, Python venv creation and `pip install -r requirements.txt`, PostgreSQL service management, `psql` commands to create user `fastapi` with password `fastapi_password` and database `fastapi_db` (both hardcoded), `.env` file written to disk with `DATABASE_URL` containing plaintext credentials, systemd unit file for `uvicorn` on port 8000, `systemctl daemon-reload` on change

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring the three local cookbooks plus four Supermarket dependencies (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1`). The `ssl_certificate` entry is commented out in the Berksfile but present and locked in the Policyfile — this discrepancy should be resolved before migration.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the ordered run list, and pinned cookbook sources. This is the authoritative dependency declaration and maps directly to an Ansible playbook task order.
- `Policyfile.lock.json`: Fully resolved and locked dependency graph including transitive dependency `selinux 6.2.4` (pulled in by `redisio`). Confirms exact versions: nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, ssl_certificate 2.1.0, selinux 6.2.4.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides — site definitions with document roots and SSL flags, SSL certificate/key paths, and security flags (fail2ban, UFW, SSH hardening). These values become Ansible host/group variables.
- `solo.rb`: Chef Solo runtime configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No migration artifact needed; replaced by `ansible.cfg` and inventory.
- `Vagrantfile`: Vagrant environment using `generic/fedora42` box, libvirt provider, 2 vCPUs / 2 GB RAM, private network `192.168.121.10`, ports 80→8080 and 443→8443 forwarded, rsync-based folder sync. Defines the target development environment; can be adapted to use the `ansible` Vagrant provisioner instead of the shell provisioner.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks vendor`, and executes `chef-solo`. This entire script is replaced by a single `ansible-playbook` invocation after migration.

---

### Target Details

- **Operating System**: **Fedora 42** is the active development target (declared in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files additionally declare support for **Ubuntu ≥ 18.04** and **CentOS ≥ 7.0**. The security recipe uses `ufw` and references `/var/log/auth.log`, which are Debian/Ubuntu conventions — these will need conditional handling (`ansible_os_family`) for RHEL/Fedora targets where `firewalld` and `/var/log/secure` are the norm.
- **Virtual Machine Technology**: **libvirt / KVM** (explicitly set as the Vagrant provider with `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. The infrastructure is designed for on-premises or generic VM deployment with no cloud-provider-specific tooling present.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install the distro-provided nginx package, plus Jinja2 templates converted from the existing ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`). The community `nginxinc.nginx` Ansible Galaxy role is an alternative for more complex scenarios.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.service` modules. Memcached is installed with defaults; no custom configuration is present in the cookbook, so a simple install-and-enable task is sufficient.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/6379.conf` (or the distro default path). The `ruby_block` hack that strips deprecated directives is unnecessary when generating the config from scratch with Ansible — simply omit those directives from the Jinja2 template.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` (or `openssl_certificate`) Ansible modules from the `community.crypto` collection. The existing `ssl.rb` recipe logic (generate self-signed cert if files do not exist) maps directly to these modules' idempotent behaviour.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with the `ansible.posix.selinux` module or the `ansible.posix` collection's SELinux tasks. On Fedora/RHEL targets, SELinux context management for Redis and Nginx paths must be addressed explicitly.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`): This credential is embedded directly in the recipe source. **1 hardcoded secret detected.** Migrate to an Ansible Vault-encrypted variable (e.g., `vault_redis_password`) referenced in the Redis config template.
- **Hardcoded PostgreSQL credentials** (`fastapi` / `fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env`): Both the `psql` provisioning commands and the `.env` file contain plaintext credentials. **2 hardcoded secrets detected.** Migrate to Ansible Vault variables (`vault_fastapi_db_user`, `vault_fastapi_db_password`) and render the `.env` file from a Jinja2 template.
- **`.env` file permissions**: The `.env` file is currently created with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded password to all local users. In Ansible, set mode to `0600` and owner to the service account running uvicorn (currently `root` — see service hardening note below).
- **Self-signed TLS certificates**: Generated via `openssl req -x509` shell command in `ssl.rb`. Acceptable for development; for production, replace with `community.crypto` modules and integrate a CA or Let's Encrypt (`community.crypto.acme_certificate`). Certificate paths (`/etc/ssl/certs/<site>.crt`, `/etc/ssl/private/<site>.key`) are parameterised and should become Ansible variables.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` commands in `security.rb`. Replace with the `ansible.builtin.lineinfile` module targeting `/etc/ssh/sshd_config`, with a handler to restart `sshd`. Ensure the Ansible control node has key-based access configured before applying this hardening, or the playbook will lock itself out.
- **UFW firewall**: Default-deny with SSH/HTTP/HTTPS allow rules managed via `execute` resources. Replace with the `community.general.ufw` module. On Fedora targets, `ufw` is not installed by default — either install it explicitly or use `ansible.posix.firewalld` with a conditional based on `ansible_os_family`.
- **fail2ban**: Configured via template `fail2ban.jail.local.erb` with jails for sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch. Replace with `ansible.builtin.package` + `ansible.builtin.template` (converting the ERB to Jinja2) + `ansible.builtin.service`. The template content is static (no Chef variables used) so conversion is straightforward.
- **Sysctl kernel hardening**: Managed via `sysctl-security.conf.erb` (also fully static). Replace with the `ansible.posix.sysctl` module or deploy the file via `ansible.builtin.copy`/`ansible.builtin.template` and notify a `sysctl -p` handler.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a security risk and should be corrected during migration — create a dedicated `fastapi` system user and update the service definition accordingly.
- **Ansible Vault summary**: A minimum of **3 secrets** must be vaulted before the Ansible playbooks are production-ready: Redis password, PostgreSQL user password, and the `DATABASE_URL` connection string (or its component parts).

---

### Technical Challenges

- **`ruby_block` Redis config patch**: The `cache` cookbook uses a `ruby_block` to post-process the Redis config file generated by `redisio`, stripping directives that cause errors on newer Redis versions. In Ansible, this is a non-issue — the Redis config file should be managed entirely by an Ansible template that never emits those directives in the first place. However, if the target system has a pre-existing Redis config from a previous Chef run, an Ansible `lineinfile` or `blockinfile` task may be needed to clean it up on first run.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook ships its own `lineinfile` custom resource (`resources/lineinfile.rb`) that replicates the behaviour of Ansible's built-in `lineinfile` module. This resource does not appear to be called anywhere in the current recipes (no `lineinfile` calls found in recipe files), but its presence suggests it was intended for future use or is a leftover. No migration action required beyond confirming it is unused; the Ansible `ansible.builtin.lineinfile` module covers the same functionality natively.
- **Cross-platform OS family handling**: The cookbook metadata declares support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, but the active Vagrant target is Fedora 42. Several resources use Debian-specific conventions: `www-data` user/group for Nginx, `ufw` for firewall, `/var/log/auth.log` for fail2ban's sshd jail, and `service 'ssh'` (vs `sshd` on RHEL). Ansible playbooks must use `when: ansible_os_family == "Debian"` / `"RedHat"` conditionals, or the scope must be narrowed to a single OS family.
- **`sites-available`/`sites-enabled` pattern**: This Nginx pattern is native to Debian/Ubuntu packages. On Fedora/RHEL, the nginx package uses `conf.d/` only. The Ansible role must either install nginx from a non-distro source that preserves this layout, or adapt the site configuration tasks to use `conf.d/` on RHEL-family systems.
- **Git-based application deployment**: The `fastapi-tutorial` cookbook uses Chef's `git` resource to sync the application from GitHub. The Ansible `ansible.builtin.git` module is a direct equivalent, but the `revision: main` tracking means every converge will pull the latest commit. A pinned commit SHA or tag should be introduced for reproducibility.
- **PostgreSQL idempotency**: The `create_db_user` execute resource uses `|| true` to suppress errors on re-runs, which is fragile. In Ansible, use the `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require error suppression.
- **`systemctl daemon-reload` ordering**: The Chef recipe triggers `daemon-reload` immediately (`:immediately`) when the systemd unit file changes, then enables and starts the service. In Ansible, this maps to a handler notified by the unit file task, with `meta: flush_handlers` before the `service` task to preserve the ordering guarantee.
- **Berksfile vs Policyfile discrepancy**: `ssl_certificate` is commented out in `Berksfile` but is present and locked in `Policyfile.lock.json`. The `ssl.rb` recipe generates certificates using raw `openssl` shell commands rather than the `ssl_certificate` cookbook's resources, so the cookbook dependency appears unused. Confirm and remove it from the Policyfile before migration to avoid confusion.

---

### Migration Order

1. **`nginx-multisite` — Security sub-component** (low risk, self-contained, high operational value): Migrate the `security.rb` recipe first — fail2ban, UFW, sysctl hardening, and SSH configuration. These tasks have no dependencies on other cookbooks and establish the security baseline. Corresponding Ansible role: `security`.

2. **`nginx-multisite` — Nginx core and SSL** (moderate complexity, depends on security baseline): Migrate `nginx.rb` and `ssl.rb` — package install, `nginx.conf` and `security.conf` templates, self-signed certificate generation, and service management. Corresponding Ansible role: `nginx`.

3. **`nginx-multisite` — Virtual host sites** (low complexity, depends on Nginx core): Migrate `sites.rb` — per-site config templates, `sites-available`/`sites-enabled` symlinks, document root directories, and static `index.html` files. Corresponding Ansible role: `nginx` (tasks/sites.yml).

4. **`cache` — Memcached** (low complexity, fully independent): Install and enable Memcached using package and service modules. No custom configuration to migrate. Corresponding Ansible role: `memcached`.

5. **`cache` — Redis** (moderate complexity, requires Vault integration): Install Redis, deploy config template with vaulted password, remove deprecated directives, enable service. Corresponding Ansible role: `redis`.

6. **`fastapi-tutorial`** (highest complexity, depends on PostgreSQL and requires Vault integration): Install system packages, provision PostgreSQL with vaulted credentials, clone application from Git, create venv, install Python dependencies, deploy `.env` template with vaulted credentials, deploy and enable systemd service. Corresponding Ansible role: `fastapi`.

---

### Assumptions

1. **Target OS for Ansible**: The Vagrant environment uses Fedora 42, but cookbook metadata also declares Ubuntu and CentOS support. It is assumed that the primary Ansible target will be **Fedora / RHEL-family**, and that Debian/Ubuntu support is secondary. If both families must be supported simultaneously, additional `when` conditionals and variable files will be required, increasing effort by approximately one week.

2. **Self-signed certificates are acceptable for the target environment**: The `ssl.rb` recipe explicitly generates self-signed certificates for development. It is assumed this remains acceptable for the migrated environment. If production-grade certificates (Let's Encrypt or internal CA) are required, the `community.crypto.acme_certificate` module or a certificate distribution mechanism must be added to scope.

3. **The FastAPI GitHub repository remains publicly accessible**: The `fastapi-tutorial` cookbook clones `https://github.com/dibanez/fastapi_tutorial.git` at the `main` branch. It is assumed this repository is available and that `main` is a stable reference. If the repository is private or the branch is unstable, SSH deploy keys and a pinned revision will be needed.

4. **Ansible Vault will be used for all secrets**: It is assumed the team will adopt Ansible Vault to replace the three hardcoded credentials found in the Chef recipes. The vault file structure and key management process are outside the scope of this plan but must be established before the playbooks are run in any shared or production environment.

5. **The `lineinfile` custom resource is unused**: No calls to the custom `lineinfile` resource were found in any recipe. It is assumed this resource is dead code and does not need to be migrated.

6. **The `ssl_certificate` community cookbook is unused**: Despite being locked in `Policyfile.lock.json`, the `ssl_certificate` cookbook's resources are never called in any recipe. Certificate generation is handled entirely by raw `openssl` shell commands. It is assumed this dependency can be dropped.

7. **Memcached requires no custom configuration**: The `cache` cookbook delegates entirely to `include_recipe 'memcached'` with no attribute overrides. It is assumed the Memcached defaults (port 11211, 64 MB memory, localhost binding) are intentional and sufficient.

8. **The FastAPI service user will be changed from `root`**: The current systemd unit runs uvicorn as `root`, which is a security risk. It is assumed the migration is an appropriate time to introduce a dedicated `fastapi` system user, and that this change is acceptable to the application team.

9. **Document root paths**: `solo.json` defines document roots under `/var/www/<site>`, while `attributes/default.rb` defines them under `/opt/server/<site>`. The `solo.json` values override the attribute defaults at runtime. It is assumed `/var/www/<site>` is the intended production path and will be used as the default in Ansible group variables.

10. **No Chef Server or encrypted data bags are in use**: The repository uses Chef Solo exclusively (`solo.rb`, `solo.json`, `vagrant-provision.sh`). There is no evidence of Chef Server, encrypted data bags, or Chef Vault usage. All secrets are currently stored in plaintext in recipe files. It is assumed no secret migration from Chef Vault is required — only extraction of hardcoded values into Ansible Vault.

11. **Vagrant remains the local development environment**: It is assumed the `Vagrantfile` will be updated to use the `ansible` provisioner (replacing the `shell` provisioner and `vagrant-provision.sh`) rather than being replaced entirely, preserving the existing developer workflow.
