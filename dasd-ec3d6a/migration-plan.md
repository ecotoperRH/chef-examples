# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo** infrastructure-as-code project that provisions a multi-service web stack on a single node (Vagrant/libvirt VM running Fedora 42). The policy (`nginx-multisite-policy`) orchestrates three local cookbooks — `nginx-multisite`, `cache`, and `fastapi-tutorial` — plus five external Chef Supermarket dependencies. The overall migration scope is **moderate**: the logic is well-structured, the node count is small, and no Chef Server or encrypted data bags are in use. However, several security-sensitive items (hardcoded credentials, self-signed TLS certificate generation, SSH hardening, firewall rules) require careful handling during the Ansible rewrite.

**Estimated migration effort:** 3–5 engineer-days for a like-for-like Ansible port, plus an additional 1–2 days to introduce proper secrets management (Ansible Vault) and idempotency hardening.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by **5 external Supermarket cookbook dependencies** that must be replaced with native Ansible modules or community roles.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads. No paths have been inferred or invented.

---

- **nginx-multisite**
  - **Description:** Core Nginx web server cookbook that configures a multi-site reverse proxy with SSL termination, security hardening, and firewall management. Orchestrates four sub-recipes: `security` (fail2ban, ufw, sysctl, SSH hardening), `nginx` (package install, nginx.conf template, per-site document roots and static files), `ssl` (self-signed certificate generation via `openssl req`), and `sites` (per-vhost `sites-available`/`sites-enabled` configuration with HTTP→HTTPS redirect). Serves three named virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, each with TLS 1.2/1.3, HSTS, and a full set of security response headers.
  - **Path:** `cookbooks/nginx-multisite`
  - **Technology:** Chef (Chef Solo, `chef_version >= 16.0`)
  - **Key Features:** ERB-templated `nginx.conf` and per-site `site.conf`; self-signed RSA-2048 certificate generation; fail2ban `jail.local` template; ufw default-deny with SSH/HTTP/HTTPS allow rules; sysctl security tuning; SSH root-login and password-auth disablement; `www-data` document root ownership; static `index.html` files per site served from cookbook `files/`.

---

- **cache**
  - **Description:** Caching layer cookbook that installs and configures both Memcached and Redis on the same node. Delegates Memcached setup entirely to the upstream `memcached` Supermarket cookbook, then configures a single Redis instance on port 6379 via the `redisio` Supermarket cookbook. Includes a `ruby_block` workaround that post-processes `/etc/redis/6379.conf` to strip deprecated `replica-*` directives that cause `redisio 7.2.4` to emit invalid configuration on newer Redis versions.
  - **Path:** `cookbooks/cache`
  - **Technology:** Chef (Chef Solo, `chef_version >= 16.0`)
  - **Key Features:** Memcached installation (delegated to `memcached ~> 6.0`); Redis on port 6379 with `requirepass` authentication; `/var/log/redis` directory with correct ownership; post-install config-file patching hack to remove deprecated Redis replica directives; `redisio::enable` for systemd service activation.

---

- **fastapi-tutorial**
  - **Description:** Application deployment cookbook that clones a FastAPI Python application from GitHub, sets up a Python 3 virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with database credentials, and registers a systemd service (`fastapi-tutorial.service`) to run the app via `uvicorn` on port 8000.
  - **Path:** `cookbooks/fastapi-tutorial`
  - **Technology:** Chef (Chef Solo, `chef_version >= 16.0`)
  - **Key Features:** System package installation (`python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`); `git` resource syncing `https://github.com/dibanez/fastapi_tutorial.git` at `main`; Python venv creation and `pip install -r requirements.txt`; PostgreSQL service management; idempotent `psql` user/database/grant commands; plaintext `.env` file containing `DATABASE_URL` with embedded credentials; systemd unit file templated inline; `systemctl daemon-reload` on change.

---

### Infrastructure Files

- **`Policyfile.rb`**: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all cookbook version constraints. This is the authoritative dependency manifest — maps directly to an Ansible playbook with ordered roles.
- **`Policyfile.lock.json`**: Locked dependency graph with exact versions and SHA identifiers for all cookbooks (local and Supermarket). Provides the definitive version baseline for selecting equivalent Ansible Galaxy roles or native module implementations.
- **`Berksfile`**: Berkshelf dependency file used during Vagrant provisioning to vendor external cookbooks. Lists the same constraints as `Policyfile.rb`; used by `vagrant-provision.sh` to run `berks vendor`.
- **`solo.rb`**: Chef Solo configuration pointing `cookbook_path` to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks` (the Berkshelf vendor output). Sets `file_cache_path` to `/var/chef-solo`. Maps to Ansible inventory and `ansible.cfg` settings.
- **`solo.json`**: Chef Solo node JSON supplying the run list and all node attribute overrides (site definitions, SSL paths, security flags). This is the primary source of truth for variable values — maps directly to Ansible `group_vars` or `host_vars`.
- **`Vagrantfile`**: Vagrant configuration targeting `generic/fedora42` with libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, and port forwards 80→8080 / 443→8443. Provisions via `vagrant-provision.sh`. Informs the Ansible inventory target OS and connection settings.
- **`vagrant-provision.sh`**: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. In an Ansible workflow this script is replaced entirely by `ansible-playbook`; a minimal bootstrap (Python install) may still be needed for the Fedora target.
- **`cookbooks/nginx-multisite/attributes/default.rb`**: Node attribute defaults for site definitions, SSL paths, and security flags. All values migrate to Ansible `defaults/main.yml` or `group_vars`.
- **`cookbooks/nginx-multisite/templates/default/nginx.conf.erb`**: ERB template for the global Nginx configuration. Migrates to a Jinja2 `.j2` template (already partially done in `modules/nginx/ansible/roles/nginx/templates/nginx.conf.j2`).
- **`cookbooks/nginx-multisite/templates/default/site.conf.erb`**: Per-vhost ERB template with conditional SSL block, security headers, HSTS, and gzip. Migrates to a Jinja2 template with `{% if ssl_enabled %}` blocks.
- **`cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb`**: fail2ban jail configuration template. Migrates to a Jinja2 template deployed by an Ansible task.
- **`cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb`**: Kernel parameter hardening template. Migrates to an Ansible `template` task writing to `/etc/sysctl.d/99-security.conf`, followed by `ansible.posix.sysctl` or a `command` handler.
- **`cookbooks/nginx-multisite/templates/default/security.conf.erb`**: Nginx security headers configuration fragment. Migrates to a Jinja2 template deployed to `/etc/nginx/conf.d/security.conf`.
- **`cookbooks/nginx-multisite/resources/lineinfile.rb`**: Custom Chef LWRP providing `lineinfile` functionality (analogous to Ansible's `lineinfile` module). This resource is a direct native capability in Ansible — no custom code needed.
- **`modules/nginx/ansible/roles/nginx/`**: Partially completed Ansible role for Nginx (output of a prior migration pass). Contains `defaults/main.yml`, `tasks/main.yml`, `templates/` (nginx.conf.j2, site.j2, default.conf.j2, default.j2), `handlers/main.yml`, `vars/main.yml`, `meta/`, and a Molecule test suite. This work should be reviewed and reconciled with the full `nginx-multisite` cookbook scope before being used as the migration baseline.
- **`project-plan.md`**: Existing project planning document (not read; not a source configuration artifact).

---

### Target Details

- **Operating System:** Fedora 42 (confirmed via `Vagrantfile`: `config.vm.box = "generic/fedora42"`). Cookbooks also declare support for Ubuntu >= 18.04 and CentOS >= 7.0, suggesting the Ansible roles should be written for cross-platform compatibility or at minimum tested on Fedora/RHEL. Package manager is `dnf`/`apt` depending on target — the Chef recipes use `package` (platform-agnostic) but the `vagrant-provision.sh` bootstrap uses `apt-get`, indicating the primary development target is Debian-family despite the Fedora Vagrant box. **Assumption: primary Ansible target is Fedora 42 / RHEL-family; Ubuntu compatibility is a secondary goal.**
- **Virtual Machine Technology:** libvirt / KVM (confirmed via `Vagrantfile` `config.vm.provider "libvirt"`). Vagrant is used solely for local development provisioning.
- **Cloud Platform:** Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present in any reviewed file.

---

## Migration Approach

### Key Dependencies to Address

The following external Chef Supermarket cookbooks must be replaced. No direct Ansible equivalents exist as drop-in replacements; each requires a native-module implementation or a vetted Galaxy role:

- **nginx (12.3.1):** Used as a dependency by `nginx-multisite` for the upstream community cookbook. In Ansible, replace with the `ansible.builtin.package` module (`nginx`) plus direct template/service tasks — or adopt `nginxinc.nginx` from Ansible Galaxy. A partial Ansible role already exists at `modules/nginx/ansible/roles/nginx/`.
- **memcached (6.1.0):** Installs and configures Memcached. Replace with `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` tasks, or use the `geerlingguy.memcached` Galaxy role.
- **redisio (7.2.4):** Installs Redis and manages per-instance configuration files. Replace with `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` tasks, or use `geerlingguy.redis`. The config-patching hack in `cache::default` must be re-evaluated — if targeting a current Redis version, the deprecated directives may not be generated at all, eliminating the need for the workaround.
- **ssl_certificate (2.1.0):** Manages SSL certificate files. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` Ansible modules for self-signed cert generation, or integrate Let's Encrypt via `community.crypto.acme_certificate`.
- **selinux (6.2.4):** Pulled in transitively by `redisio`. Replace with `ansible.posix.selinux` and `community.general.sefcontext` / `ansible.posix.seboolean` tasks as needed for the target platform.

---

### Security Considerations

- **Hardcoded Redis password:** `cookbooks/cache/recipes/default.rb` sets `requirepass` to the literal string `redis_secure_password_123` directly in the recipe. This credential must be extracted into **Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable in the migrated role.
- **Hardcoded PostgreSQL credentials:** `cookbooks/fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` in both the `psql` provisioning commands and the `.env` file written to disk (`DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`). Both occurrences must be replaced with Vault-encrypted variables. The `.env` file itself should be deployed via `ansible.builtin.template` with a Vault-sourced variable.
- **Self-signed TLS certificates:** `ssl.rb` generates RSA-2048 self-signed certificates via `openssl req` shell commands. For production, replace with `community.crypto` modules and integrate a proper CA or ACME/Let's Encrypt workflow. For development parity, use `community.crypto.x509_certificate` with `provider: selfsigned`.
- **SSH hardening:** `security.rb` disables root login and password authentication by `sed`-patching `/etc/ssh/sshd_config`. In Ansible, use `ansible.builtin.lineinfile` (or `ansible.builtin.template` for the full sshd_config) with a handler to restart `sshd`. Ensure the Ansible control connection uses key-based auth before applying these changes to avoid locking out the automation user.
- **UFW firewall rules:** `security.rb` configures ufw via shell `execute` resources with `not_if` guards. Replace with `community.general.ufw` module tasks, which are idempotent by design.
- **fail2ban configuration:** Deployed via ERB template. Migrate to a Jinja2 template task. No credentials involved, but the jail configuration should be reviewed for accuracy against the target Nginx log paths.
- **Sysctl kernel hardening:** Applied via `sysctl -p` on a template file. Replace with `ansible.posix.sysctl` module tasks for proper idempotency, or retain the template + handler pattern.
- **Service running as root:** The `fastapi-tutorial.service` systemd unit sets `User=root`. This is a security risk and should be corrected during migration — create a dedicated `fastapi` system user and run the service under that account.
- **`.env` file permissions:** The `.env` file containing the database URL is written with mode `0644` (world-readable). This must be tightened to `0600` or `0640` in the Ansible task.

---

### Technical Challenges

- **Package manager mismatch (Fedora vs. Debian):** The `vagrant-provision.sh` bootstrap uses `apt-get`, but the Vagrant box is `generic/fedora42` (dnf/rpm). The Chef `package` resource abstracts this, but Ansible tasks that reference package names directly (e.g., `libpq-dev` on Debian vs. `libpq-devel` on RHEL/Fedora) will need platform conditionals (`when: ansible_os_family == ...`) or a vars file per OS family.
- **Redis config-patching hack:** The `ruby_block` in `cache::default` that strips deprecated Redis directives from `/etc/redis/6379.conf` is a workaround for `redisio 7.2.4` generating invalid config for newer Redis. When migrating, verify whether the target Redis package version still emits these directives. If not, the hack can be dropped entirely; if so, use `ansible.builtin.lineinfile` with `regexp`/`state: absent` to replicate the behavior cleanly.
- **Partial Ansible role already exists:** `modules/nginx/ansible/roles/nginx/` contains a prior migration attempt for Nginx. Before starting fresh, this role must be audited against the full `nginx-multisite` cookbook scope (security recipe, SSL recipe, sites recipe, fail2ban, ufw) to determine what is complete, what is missing, and whether the existing Molecule tests cover the required scenarios.
- **Idempotency of PostgreSQL provisioning:** The `fastapi-tutorial` recipe uses raw `psql` shell commands with `|| true` to suppress errors on re-run. In Ansible, replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **Git-based application deployment:** The recipe uses Chef's `git` resource to sync the application repository. In Ansible, use `ansible.builtin.git` with `version: main`. Consider pinning to a specific commit SHA rather than a branch tip for reproducibility.
- **Inline systemd unit file:** The `fastapi-tutorial` recipe writes the systemd service file as a heredoc inside the recipe. Migrate this to a dedicated Jinja2 template file for maintainability and to allow variable substitution (e.g., the `User` field, working directory, port).
- **Berkshelf vendoring workflow:** The current provisioning flow requires `berks vendor` to download external cookbooks at runtime. In Ansible, all role dependencies are declared in `requirements.yml` and installed via `ansible-galaxy install -r requirements.yml` — this step must be documented in the project README and CI pipeline.
- **Vagrant/libvirt target vs. production:** The entire stack is currently validated only in a local Vagrant/libvirt environment. The Ansible migration should introduce a proper inventory structure (`inventories/vagrant/`, `inventories/production/`) with environment-specific `group_vars` to support promotion beyond local development.

---

### Migration Order

The following order minimizes risk by starting with the most self-contained cookbook and ending with the most security-sensitive:

1. **`cache` cookbook** — Lowest external surface area once `memcached` and `redisio` Supermarket dependencies are replaced with native Ansible tasks. The Redis password must be Vaulted before this role is considered complete. Resolving the Redis config-patching hack here also validates the approach for the rest of the migration.
2. **`fastapi-tutorial` cookbook** — Self-contained application deployment with no Nginx dependency. Migrating this second allows PostgreSQL provisioning and the systemd service to be validated independently. Credential extraction (DB password, `.env` file) and the `User=root` service fix should be addressed in this phase.
3. **`nginx-multisite` cookbook** — Most complex cookbook; depends on the SSL certificate strategy being decided (self-signed vs. ACME), the existing partial Ansible role being reconciled, and the security hardening tasks (ufw, fail2ban, sysctl, SSH) being ported. Should be migrated last so the full stack can be integration-tested end-to-end once all three roles are complete.

---

### Assumptions

1. **Target OS is Fedora 42** based on the Vagrantfile box, despite `vagrant-provision.sh` using `apt-get` and cookbook metadata declaring Ubuntu/CentOS support. The Ansible roles should be written for Fedora/RHEL-family first, with Ubuntu compatibility added if explicitly required.
2. **Chef Server is not in use.** The entire stack runs via `chef-solo` with a local `solo.json` node file. There is no Chef Server, data bags, environments, or roles to migrate beyond what is in this repository.
3. **No encrypted data bags or Chef Vault.** All credentials found in the repository are stored in plaintext (recipe source code, `solo.json`). Ansible Vault must be introduced as a net-new security control during migration.
4. **Self-signed certificates are acceptable for the current environment.** The SSL recipe generates self-signed certs and the `vagrant-provision.sh` output explicitly warns about SSL warnings. If this is intended for production use, a proper certificate authority or ACME integration must be scoped as additional work.
5. **The partial Ansible role at `modules/nginx/ansible/roles/nginx/`** represents prior migration work for the Nginx component only. It does not cover the `cache` or `fastapi-tutorial` cookbooks, nor the security/firewall/fail2ban sub-recipes of `nginx-multisite`. Its completeness and test coverage must be verified before it is used as the migration baseline.
6. **The `fastapi-tutorial` application source** is pulled from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`) at the `main` branch tip. No version pinning is in place. The migration should introduce a pinned commit SHA or tag for reproducibility.
7. **Single-node deployment.** All services (Nginx, Memcached, Redis, PostgreSQL, FastAPI) run on the same host. The Ansible playbook should be structured to support future separation into multiple host groups without a full rewrite (i.e., use roles, not a monolithic playbook).
8. **`libpq-dev` package name** is Debian-specific. On Fedora 42 the equivalent is `libpq-devel`. The Chef `package` resource resolves this transparently; Ansible tasks will need explicit platform handling.
9. **The `lineinfile` custom Chef resource** in `cookbooks/nginx-multisite/resources/lineinfile.rb` is a local reimplementation of a built-in Ansible capability. It can be dropped entirely in the Ansible migration.
10. **No CI/CD pipeline** is currently defined for this repository. The Molecule test suite present in `modules/nginx/ansible/roles/nginx/molecule/` is the only automated testing artifact. Establishing a CI pipeline (e.g., GitHub Actions running `molecule test`) should be considered part of the migration deliverables.
