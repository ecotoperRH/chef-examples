# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The entire stack is driven by three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) and four external Chef Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`), all pinned in `Policyfile.lock.json`.

The local development environment is a **Fedora 42** VM managed by Vagrant with libvirt, provisioned via a shell bootstrap script that installs Chef and Berkshelf, then runs `chef-solo`. The run-list order is `nginx-multisite → cache → fastapi-tutorial`.

**Migration complexity: Medium.** The three cookbooks are well-scoped, have no circular dependencies, and map cleanly to Ansible roles. The primary challenges are: (1) replacing the `redisio` community cookbook's post-install config-file patching hack with idiomatic Ansible tasks, (2) managing two sets of hardcoded credentials (Redis password, PostgreSQL user/password) with Ansible Vault, and (3) preserving the per-site Nginx virtual-host loop logic in Jinja2 templates. A realistic timeline for a complete, tested migration is **3–4 weeks** for a single engineer, or **1.5–2 weeks** with two engineers working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains three Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx reverse proxy and static-file server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation per vhost, HTTP→HTTPS redirect, HSTS, and a full suite of security hardening (UFW firewall, fail2ban with nginx and sshd jails, kernel sysctl hardening, SSH root-login and password-auth lockdown).
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Five sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
        - Per-site document roots with static `index.html` files deployed from cookbook `files/`
        - ERB templates for `nginx.conf`, per-site `site.conf`, `conf.d/security.conf`, `fail2ban/jail.local`, and `sysctl.d/99-security.conf`
        - Self-signed RSA-2048 certificates generated with `openssl req -x509` (idempotent via `not_if` file-existence check)
        - UFW rules: default deny, allow SSH/HTTP/HTTPS
        - fail2ban jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
        - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) that replicates Ansible's own `lineinfile` module behaviour
        - Attribute-driven site list (document root, SSL flag) overridable via `solo.json`

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the `memcached` community cookbook) and Redis (via the `redisio` community cookbook) with password authentication, plus a post-install Ruby block that surgically removes deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf`.
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached` community cookbook
        - Configures Redis on port 6379 with `requirepass` set to a hardcoded password
        - Creates `/var/log/redis` directory with correct ownership
        - Applies a `ruby_block` hack to strip incompatible directives from the redisio-generated config (compatibility shim for newer Redis versions)
        - Enables Redis via `redisio::enable`

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running under a Python 3 virtual environment managed by `uvicorn`, with a PostgreSQL database backend, a `.env` file for runtime configuration, and a systemd unit file for service lifecycle management.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using the Chef `git` resource (sync action)
        - Creates a Python venv at `/opt/fastapi-tutorial/venv` and installs `requirements.txt`
        - Enables and starts the `postgresql` service
        - Creates PostgreSQL role `fastapi` with password `fastapi_password` and database `fastapi_db` via inline `psql` commands (idempotent with `|| true`)
        - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
        - Writes and enables a systemd unit `fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as root

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest listing all three local cookbooks by path and four external Supermarket cookbooks with version constraints. Used by `vagrant-provision.sh` to vendor dependencies before `chef-solo` runs. **Migration note**: no direct Ansible equivalent; external role dependencies will be expressed in `requirements.yml` for `ansible-galaxy`.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), the run-list, and cookbook sources. Supersedes `Berksfile` for policy-based workflows. **Migration note**: the run-list order (`nginx-multisite → cache → fastapi-tutorial`) must be preserved as Ansible play/role ordering.
- `Policyfile.lock.json`: Fully resolved, pinned dependency graph including transitive dependencies (`selinux 6.2.4` pulled in by `redisio`). Documents exact cookbook versions in use. **Migration note**: reference this file to identify all transitive Chef dependencies that need Ansible equivalents.
- `solo.json`: Node JSON attributes passed to `chef-solo -j`. Overrides default site document roots to `/var/www/<site>` and explicitly sets all security flags. **Migration note**: these values become Ansible `group_vars` or `host_vars`; the document-root discrepancy between `solo.json` (`/var/www/`) and `attributes/default.rb` (`/opt/server/`) must be resolved before migration.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks`. **Migration note**: no Ansible equivalent needed; superseded by the Ansible inventory and role paths.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync-synced folder. **Migration note**: the Fedora 42 target OS is the authoritative platform for Ansible role development and testing; the commented-out `/etc/hosts` entries for the three vhosts must be added to the Ansible inventory or a pre-task.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef-embedded gem, vendors cookbooks, and runs `chef-solo`. **Migration note**: replace entirely with `ansible-playbook`; the `apt-get update` call confirms the Vagrant box uses an apt-based layer or the script is partially incorrect for Fedora (dnf-based) — this inconsistency must be investigated.

---

### Target Details

- **Operating System**: **Fedora 42** (primary, as declared in `Vagrantfile` `config.vm.box = "generic/fedora42"`). Cookbook `metadata.rb` files additionally declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The `vagrant-provision.sh` script calls `apt-get`, which is inconsistent with Fedora (which uses `dnf`/`rpm`). The Ansible roles must use the `ansible.builtin.package` module with OS-family conditionals, or target a single OS family. Default to **Red Hat Enterprise Linux 9 / Fedora** as the primary target.
- **Virtual Machine Technology**: **libvirt / KVM** (declared in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider metadata endpoints, CLI tools, or cloud-init configurations are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community cookbook wraps package installation and service management. Replace with `ansible.builtin.package` (install `nginx`), `ansible.builtin.template` for `nginx.conf` and vhost configs, and `ansible.builtin.service` for enable/start. The ERB templates already exist and need straightforward conversion to Jinja2.
- **memcached (6.1.0, Chef Supermarket)**: Wraps package install and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service`. Memcached configuration is minimal (no custom config file in this repo); a simple install-and-enable task suffices.
- **redisio (7.2.4, Chef Supermarket)**: Installs Redis from source or package, generates `/etc/redis/6379.conf`, and manages the service. Replace with `ansible.builtin.package` (install `redis`), `ansible.builtin.template` for `/etc/redis/6379.conf` (directly authoring the correct config eliminates the post-install patching hack entirely), and `ansible.builtin.service`. The `requirepass` directive must be templated from an Ansible Vault variable.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Referenced in `Policyfile.rb` but commented out in `Berksfile`; SSL certificate generation is handled inline in `ssl.rb` via `openssl` shell commands. Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. No explicit SELinux configuration is present in the local cookbooks. Verify whether SELinux policy adjustments are needed for Redis on the target OS; if so, use `ansible.posix.selinux` and `community.general.sefcontext`.

### Security Considerations

- **Hardcoded Redis password**: `cookbooks/cache/recipes/default.rb` line `'requirepass' => 'redis_secure_password_123'` contains a plaintext credential committed to the repository. **Action**: create an Ansible Vault-encrypted variable `redis_requirepass` and reference it in the Redis config template. Rotate the password at migration time.
- **Hardcoded PostgreSQL credentials**: `cookbooks/fastapi-tutorial/recipes/default.rb` contains `PASSWORD 'fastapi_password'` in an inline `psql` command and writes the same password to `/opt/fastapi-tutorial/.env` in plaintext. **Action**: create Vault-encrypted variables `fastapi_db_user`, `fastapi_db_password`, and `fastapi_db_name`; use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules; render `.env` from a Jinja2 template referencing Vault variables.
- **Self-signed SSL certificates**: All three vhosts use self-signed certificates generated at provision time. Certificates are stored at `/etc/ssl/certs/<site>.crt` and `/etc/ssl/private/<site>.key`. **Action**: replicate generation with `community.crypto` modules; for production, replace with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA. The private key directory permissions (`0710`, group `ssl-cert`) must be explicitly set in Ansible tasks.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` commands in `security.rb`. **Action**: use `ansible.builtin.lineinfile` (the custom Chef LWRP in this repo is a direct analogue) or `ansible.builtin.template` for `/etc/ssh/sshd_config`; notify an `sshd` handler to restart.
- **UFW firewall**: Rules are applied via `execute` resources wrapping `ufw` CLI commands. **Action**: use `community.general.ufw` module; the idempotency guards (`not_if 'ufw status | grep -q ...'`) are handled natively by the module.
- **fail2ban**: Configuration is template-driven with four active jails. **Action**: use `ansible.builtin.package` + `ansible.builtin.template` for `jail.local` + `ansible.builtin.service`; the ERB template converts directly to Jinja2 with no variable substitution needed (the template is fully static).
- **Kernel sysctl hardening**: `sysctl.d/99-security.conf` disables IPv6, enables SYN cookies, disables ICMP redirects, etc. **Action**: use `ansible.posix.sysctl` module for each parameter, or deploy the file via `ansible.builtin.template` and notify a `sysctl -p` handler. Note that disabling IPv6 globally (`net.ipv6.conf.all.disable_ipv6 = 1`) may conflict with some cloud or container networking stacks — verify before applying in non-Vagrant environments.
- **FastAPI service running as root**: The systemd unit sets `User=root`. **Action**: flag this as a security risk during migration; create a dedicated `fastapi` system user and update the unit file accordingly.
- **Credential count summary**:
  - `cache` cookbook: 1 hardcoded password (`redis_secure_password_123`)
  - `fastapi-tutorial` cookbook: 2 hardcoded credentials (PostgreSQL user password `fastapi_password` appears twice — in the `psql` command and in the `.env` file)
  - `nginx-multisite` cookbook: 0 runtime credentials (SSL cert subject uses placeholder values only)
  - **Total: 3 credential instances across 2 cookbooks** — all must be migrated to Ansible Vault.

### Technical Challenges

- **Document root path inconsistency**: `cookbooks/nginx-multisite/attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, while both `solo.json` files (root and `.myprj/`) override them to `/var/www/{test,ci,status}.cluster.local`. The Ansible role must define a single canonical path in `defaults/main.yml` and the discrepancy must be resolved with the team before migration.
- **Redis post-install config patching**: The `ruby_block "fix_redis_config"` in `cache/recipes/default.rb` strips five deprecated directives from the redisio-generated config file. This is a workaround for `redisio` generating configs incompatible with the installed Redis version. In Ansible, the Redis config file will be fully owned by a Jinja2 template, so these directives simply will not be present — eliminating the need for the hack entirely. However, the correct Redis version and its supported directives on Fedora 42 must be verified before writing the template.
- **Multi-site Nginx vhost loop**: The Chef recipes iterate over `node['nginx']['sites']` hash to create directories, deploy static files, generate SSL certs, create vhost configs, and symlink `sites-enabled`. In Ansible this becomes a `loop` over a `nginx_sites` list variable, with `ansible.builtin.template`, `community.crypto` modules, and `ansible.builtin.file` (symlink) tasks — all straightforward but requiring careful variable structure design.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom resource that mirrors Ansible's `ansible.builtin.lineinfile` module. This resource does not appear to be called anywhere in the current recipes (no `lineinfile` calls found in recipe files), but its presence suggests it may have been intended for SSH config hardening. The `security.rb` recipe uses raw `sed` commands instead. **Action**: replace `sed` commands with `ansible.builtin.lineinfile`; the custom LWRP can be discarded.
- **`apt-get` in `vagrant-provision.sh` on Fedora**: The provisioning script calls `apt-get update` and `apt-get install -y build-essential`, which will fail on Fedora 42 (which uses `dnf`). This suggests the Vagrant box may have been changed from Ubuntu to Fedora at some point without updating the script, or the script is never actually used (the Vagrantfile also has a commented-out `chef_solo` provisioner block). **Action**: clarify the actual target OS before writing Ansible tasks; if Fedora is the target, all package names must use `dnf`-compatible names (e.g., `gcc` instead of `build-essential`, `python3-devel` instead of `libpq-dev`).
- **Git-based application deployment**: The `fastapi-tutorial` cookbook uses the Chef `git` resource with `action :sync` to keep `/opt/fastapi-tutorial` in sync with the `main` branch. In Ansible, `ansible.builtin.git` with `update: yes` provides equivalent behaviour. The `pip install -r requirements.txt` step must be re-run on each deployment if `requirements.txt` changes — consider using a handler triggered by the git task's changed state.
- **PostgreSQL idempotency**: The `create_db_user` execute resource uses `|| true` to suppress errors on duplicate creation. The `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` Ansible modules handle idempotency natively and are the correct replacement.
- **Platform package name differences**: Package names differ between Debian/Ubuntu and RHEL/Fedora (e.g., `libpq-dev` vs `postgresql-devel`, `python3-venv` may not exist as a separate package on Fedora). The Ansible roles must include `vars/` files per OS family or use `ansible.builtin.package_facts` with conditionals.

### Migration Order

1. **`cache` cookbook → Ansible role `cache`** *(Low complexity, fully independent, no inbound dependencies)*
   - Install and configure Memcached via package + service tasks
   - Install Redis, deploy `/etc/redis/6379.conf` from a Jinja2 template (with `requirepass` from Vault), enable and start service
   - No dependency on other roles; can be developed and tested in isolation first

2. **`nginx-multisite` cookbook → Ansible role `nginx_multisite`** *(Medium complexity, security-critical, no runtime dependency on other roles)*
   - Sub-tasks mirroring the four sub-recipes: `security.yml`, `nginx.yml`, `ssl.yml`, `sites.yml`
   - Convert all five ERB templates to Jinja2
   - Implement vhost loop with `community.crypto` for cert generation
   - Implement UFW, fail2ban, sysctl, and SSH hardening tasks
   - Deploy static site content files

3. **`fastapi-tutorial` cookbook → Ansible role `fastapi_tutorial`** *(High complexity, depends on PostgreSQL being available, involves application deployment and secrets)*
   - Install system packages (OS-family conditional)
   - Deploy application via `ansible.builtin.git`
   - Create venv and install Python dependencies
   - Configure PostgreSQL (user, database, privileges) using `community.postgresql` collection
   - Render `.env` from Vault-backed template
   - Deploy and enable systemd unit (with `User` changed from `root` to a dedicated service account)

### Assumptions

1. **Target OS is Fedora 42** (as declared in `Vagrantfile`). The `apt-get` calls in `vagrant-provision.sh` are assumed to be a leftover artefact from an earlier Ubuntu-based setup and will not be carried forward. All package names in Ansible tasks will use Fedora/RHEL equivalents unless the team confirms a dual-platform requirement.
2. **Self-signed certificates are acceptable** for the target environment (development/staging). If this stack is intended for production, the SSL recipe must be replaced with a proper CA-signed or Let's Encrypt certificate workflow before go-live.
3. **The canonical document root** for the three Nginx vhosts will be `/var/www/<site>` (as set in `solo.json`), not `/opt/server/<site>` (as set in `attributes/default.rb`). This must be confirmed with the team.
4. **The FastAPI GitHub repository** (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) will remain publicly accessible and stable during and after migration. If the repository is private or the branch name changes, the `ansible.builtin.git` task will need credentials and/or a branch variable.
5. **Redis and Memcached are single-node** with no clustering, replication, or Sentinel configuration required. The `redisio` cookbook's server list contains exactly one entry.
6. **The `ssl_certificate` community cookbook** (present in `Policyfile.rb` and `Policyfile.lock.json` but commented out in `Berksfile`) is not actively used. SSL certificate generation is handled entirely by inline `openssl` commands in `ssl.rb`. The `community.crypto` Ansible collection will replace this inline approach.
7. **The custom `lineinfile` LWRP** (`resources/lineinfile.rb`) is not called by any recipe in the current codebase and will not be migrated. Its intended functionality is covered natively by `ansible.builtin.lineinfile`.
8. **SELinux** is a transitive dependency via `redisio → selinux 6.2.4`, but no explicit SELinux policy changes are made in the local cookbooks. It is assumed SELinux is either permissive or that the default policies on Fedora 42 permit Redis operation on port 6379. This must be verified on the target system.
9. **The three vhosts** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) require `/etc/hosts` entries on client machines for name resolution. The Vagrantfile has these entries commented out. The Ansible playbook should include a pre-task or a separate play to manage `/etc/hosts` on the target host, or DNS must be configured externally.
10. **Ansible Vault** will be used for all secrets. The vault file will contain at minimum: `redis_requirepass`, `fastapi_db_password`, `fastapi_db_user`, `fastapi_db_name`. The vault password must be distributed to all engineers running the playbook via a vault password file or CI/CD secret store.
11. **The `fastapi-tutorial` service running as `root`** is assumed to be intentional for the current development environment but will be flagged as a security risk. The migration plan includes creating a dedicated `fastapi` system user; whether this change is applied immediately or deferred is a team decision.
12. **Chef Solo** (not Chef Infra Client with a server) is the current execution model. There is no Chef Server, data bags, encrypted data bags, or Chef Vault in use. All configuration is attribute-driven via `solo.json` and cookbook `attributes/`. This simplifies migration as there are no server-side constructs to replicate.
