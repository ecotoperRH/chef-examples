# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service Linux server. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and tested locally with Vagrant on a Fedora 42 / libvirt VM.

The infrastructure covers four functional domains: a hardened multi-site Nginx reverse proxy with SSL, a Redis + Memcached caching layer, a Python FastAPI application backed by PostgreSQL, and OS-level security hardening (UFW firewall, fail2ban, SSH lockdown, sysctl kernel tuning).

**Migration complexity: Medium.** All three cookbooks follow conventional Chef patterns (package/template/service/execute resources) with direct Ansible equivalents. The main risks are a hardcoded credential set spread across two cookbooks, a Ruby-block config-patching hack in the cache cookbook, and a self-signed certificate generation workflow that must be reproduced faithfully. No Chef-specific primitives (LWRP, data bags, encrypted data bags, Chef Vault, Ohai attributes) are used beyond a single custom `lineinfile` resource that maps trivially to Ansible's built-in `lineinfile` module.

**Estimated migration timeline: 3–4 weeks** for a single engineer, including playbook authoring, Vault integration, and functional testing in Vagrant.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a global security hardening configuration, self-signed TLS certificate generation via OpenSSL, UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl hardening
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Per-site `sites-available`/`sites-enabled` symlink management; ERB-templated `nginx.conf`, `security.conf`, per-site `site.conf` with HTTP→HTTPS redirect, TLS 1.2/1.3 enforcement, HSTS, and full security-header suite; fail2ban jails for sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch; UFW default-deny with SSH/HTTP/HTTPS allow rules; sysctl hardening (IP spoofing, ICMP redirect, SYN-cookie, IPv6 disable); SSH root login and password authentication disabled; static HTML content files for each vhost (`ci/`, `status/`, `test/`); custom `lineinfile` LWRP (maps directly to Ansible `lineinfile` module)

- **cache**:
    - Description: Dual caching layer that installs and configures Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, a dedicated log directory, and a post-install Ruby-block hack that strips incompatible directives from the generated Redis config file
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached installed via `include_recipe 'memcached'`; Redis on port 6379 with `requirepass` set to a hardcoded password (`redis_secure_password_123`); `/var/log/redis` directory owned by the `redis` user; post-install `ruby_block` that removes five deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf`; `redisio::enable` recipe to register the Redis service

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application sourced from a public GitHub repository, including system package installation, Python virtual environment creation, PostgreSQL database and user provisioning, a `.env` configuration file with hardcoded database credentials, and a systemd unit file for process management
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`; Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial`; Python venv at `/opt/fastapi-tutorial/venv`; pip install from `requirements.txt`; PostgreSQL service enabled and started; `psql` commands to create user `fastapi` (password: `fastapi_password`), database `fastapi_db`, and grant all privileges — all wrapped in `|| true` guards; `.env` file at `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` with mode `0644` (world-readable — security risk); systemd unit `fastapi-tutorial.service` running uvicorn on `0.0.0.0:8000` as `root` (privilege escalation risk); `systemctl daemon-reload` triggered on unit file change

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest; declares all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out here but active in `Policyfile.rb`). Not needed in Ansible; replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints. Equivalent to an Ansible site playbook with role includes.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the authoritative version reference during migration.
- `solo.json`: Chef Solo node JSON providing the run list and all node attribute overrides (site definitions with document roots and SSL flags, SSL certificate/key paths, fail2ban/UFW/SSH security flags). This file is the primary source of truth for Ansible `group_vars` / `host_vars` variable files.
- `solo.rb`: Chef Solo runtime configuration (cache path `/var/chef-solo`, cookbook search paths). No migration equivalent needed.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. The same box and network config can be reused for Ansible testing by replacing the `shell` provisioner with an `ansible_local` or `ansible` provisioner.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. Will be replaced by a simple `ansible-playbook` invocation or Vagrant's built-in Ansible provisioner.

---

### Target Details

- **Operating System**: Fedora 42 (primary, as declared in `Vagrantfile` with `generic/fedora42`). Cookbook `metadata.rb` files additionally declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The `ufw` firewall package and `www-data` user references in `nginx-multisite` are Debian/Ubuntu-specific and will require conditional handling (`firewalld` + `nginx` user) for RHEL/Fedora targets.
- **Virtual Machine Technology**: KVM/libvirt (explicitly configured in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `nginxinc.nginx` Ansible Galaxy role or direct `ansible.builtin.package` + `ansible.builtin.template` tasks. All ERB templates (`nginx.conf.erb`, `security.conf.erb`, `site.conf.erb`) translate directly to Jinja2 with minimal syntax changes.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `geerlingguy.memcached` Ansible Galaxy role or simple `package` / `service` tasks. No complex configuration is applied beyond defaults.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `geerlingguy.redis` Ansible Galaxy role or direct `package` / `template` / `service` tasks. The post-install config-patching hack (see Technical Challenges) must be reproduced as an Ansible `lineinfile` or `replace` task loop.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection. The current self-signed certificate generation logic in `ssl.rb` maps directly to these modules.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with `ansible.posix.selinux` module or the `geerlingguy.selinux` role if SELinux policy management is required on RHEL/Fedora targets.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, `node['redisio']['servers'][0]['requirepass']`): This credential is stored in plain text in the recipe. **Must be migrated to Ansible Vault** as an encrypted variable (e.g., `vault_redis_password`). Count: 1 hardcoded secret.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb` and in the `.env` file content): The password appears in three locations — the `psql` CREATE USER command, the `DATABASE_URL` in the `.env` file template, and implicitly in the systemd environment. **Must be migrated to Ansible Vault**. Count: 1 hardcoded secret (used in 3 places).
- **World-readable `.env` file**: The `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644`, exposing `DATABASE_URL` (including the database password) to all local users. In Ansible, this file should be deployed with mode `0600` and owned by the application service user (not `root`).
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant privilege escalation risk. The Ansible migration should introduce a dedicated `fastapi` system user and update the unit accordingly.
- **Self-signed TLS certificates**: Generated via `openssl req -x509` with a 365-day validity and a hardcoded subject string (`/C=US/ST=Example/...`). Acceptable for development; production deployments must replace these with CA-signed or Let's Encrypt certificates. The `community.crypto` collection handles both cases.
- **SSH hardening via `sed`**: Root login and password authentication are disabled by direct `sed` manipulation of `/etc/ssh/sshd_config`. In Ansible, use the `ansible.builtin.lineinfile` module or the `devsec.hardening.ssh_hardening` role for idempotent, auditable SSH configuration.
- **UFW vs. firewalld**: The `security.rb` recipe uses `ufw` (Debian/Ubuntu). On Fedora 42 (the actual Vagrant target), `ufw` is not the default firewall manager — `firewalld` is. This mismatch means the current Chef code likely fails silently or requires `ufw` to be installed as an extra package. The Ansible migration should use `ansible.posix.firewalld` for Fedora/RHEL targets and `community.general.ufw` for Ubuntu, with a platform conditional.
- **fail2ban configuration**: The `jail.local` template is static (no node-attribute-driven customisation). Migrate as a plain Ansible `template` task. Ensure the `nginx-botsearch` filter is available on the target distribution.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template is fully static. Migrate using `ansible.posix.sysctl` module tasks (one task per parameter) for idempotency, or deploy the file as a template and notify a handler to run `sysctl -p`.

---

### Technical Challenges

- **Redis config post-install patching hack**: `cache/recipes/default.rb` uses a `ruby_block` to strip five deprecated directives from `/etc/redis/6379.conf` after `redisio` generates it. This is a workaround for an incompatibility between `redisio 7.2.4` and the installed Redis version. In Ansible, this should be replaced by a loop of `ansible.builtin.replace` or `ansible.builtin.lineinfile` tasks with `regexp` patterns, or — better — by templating the Redis configuration file directly and bypassing the community role's template entirely.
- **Multi-site Nginx vhost loop**: The `sites.rb` and `nginx.rb` recipes iterate over `node['nginx']['sites']` to create document root directories, deploy static HTML files, generate per-site `site.conf` files, and create `sites-enabled` symlinks. In Ansible, this maps to a `loop` over a `nginx_sites` list variable, using `ansible.builtin.template`, `ansible.builtin.file` (for symlinks), and `ansible.builtin.copy` tasks. The Jinja2 template for `site.conf` must replicate the conditional SSL block from the ERB original.
- **Platform divergence (UFW on Fedora)**: As noted above, the Chef code targets Ubuntu conventions (`ufw`, `www-data` user) but the Vagrant box is Fedora 42. The Ansible migration must resolve this ambiguity with explicit platform conditionals (`when: ansible_os_family == 'Debian'` / `when: ansible_os_family == 'RedHat'`) or by committing to a single target OS.
- **PostgreSQL idempotency**: The `fastapi-tutorial` recipe uses `psql` shell commands with `|| true` guards to create the database user and database. These are not truly idempotent (they suppress errors but do not check state). In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **Git-based application deployment**: The recipe uses Chef's `git` resource with `action :sync` to keep `/opt/fastapi-tutorial` up to date. In Ansible, `ansible.builtin.git` with `update: yes` provides equivalent behaviour. Care must be taken around the `pip install` step — it should only re-run when `requirements.txt` changes, which can be achieved with a handler triggered by the git task's `changed` state.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook ships a custom `lineinfile` resource (`resources/lineinfile.rb`) that replicates basic line-in-file editing with optional backup. This maps directly and completely to Ansible's built-in `ansible.builtin.lineinfile` module — no custom logic is needed.
- **`ssl_certificate` cookbook discrepancy**: `ssl_certificate ~> 2.1` is listed in `Policyfile.rb` and resolved in `Policyfile.lock.json` but is commented out in `Berksfile`. The cookbook does not appear to be called in any recipe. Verify whether it is a vestigial dependency before migration; if unused, omit it from the Ansible `requirements.yml`.
- **`selinux` transitive dependency**: The `selinux 6.2.4` cookbook is pulled in transitively by `redisio`. On Fedora 42, SELinux is enforcing by default. Ensure the Ansible Redis role or tasks include the necessary SELinux boolean/policy adjustments (e.g., allowing Redis to bind to its port and write to `/var/log/redis`).

---

### Migration Order

1. **security (extracted from nginx-multisite)** — Migrate OS-level hardening first as it is a prerequisite for all other services and has no upstream dependencies. Covers: UFW/firewalld rules, fail2ban, SSH hardening, sysctl kernel parameters. Low risk; all tasks have direct Ansible module equivalents.

2. **cache** — Migrate Memcached and Redis next. Both are standalone services with no dependency on nginx or the FastAPI app. The Redis config-patching hack is the only non-trivial element. Resolving it early validates the approach for the rest of the migration. Medium risk.

3. **nginx-multisite** — Migrate the Nginx multi-site configuration after the security layer is in place. Requires careful Jinja2 templating of the vhost loop and SSL certificate generation. The static HTML content files copy over unchanged. Medium-high risk due to the vhost loop and platform firewall divergence.

4. **fastapi-tutorial** — Migrate last, as it depends on PostgreSQL (which must be running) and is the most complex cookbook. Address the security issues (root service user, world-readable `.env`) during migration. High risk due to credential management, service user creation, and PostgreSQL idempotency requirements.

---

### Assumptions

1. **Target OS commitment**: The Vagrantfile uses `generic/fedora42`, but cookbook metadata declares Ubuntu ≥ 18.04 and CentOS ≥ 7 support. It is assumed the primary migration target is **Fedora 42 / RHEL-family**, and Ubuntu support is secondary. Platform conditionals will be added but Fedora will be the tested path.
2. **`ufw` on Fedora**: It is assumed that the current Chef run either installs `ufw` explicitly on Fedora or that this part of the recipe is currently broken/untested. The Ansible migration will use `firewalld` as the canonical firewall manager on Fedora/RHEL.
3. **Self-signed certificates are intentional for this environment**: The `openssl req -x509` certificate generation is assumed to be the desired behaviour for the development/test environment described. No Let's Encrypt or external CA integration is in scope unless explicitly requested.
4. **`ssl_certificate` cookbook is unused**: Based on code inspection, no recipe calls `ssl_certificate`. It is assumed this is a vestigial dependency and will be omitted from the Ansible migration.
5. **Redis version compatibility**: The Ruby-block hack in `cache/recipes/default.rb` strips directives that are invalid in the installed Redis version. It is assumed the target Redis package version (from the OS default repository) is the same one that triggered this incompatibility, and the Ansible migration must preserve the directive-removal logic.
6. **FastAPI application repository availability**: The application is cloned from `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`). It is assumed this repository remains publicly accessible and that `main` is the correct deployment branch.
7. **No Chef data bags or encrypted secrets in use**: Inspection of all recipe files confirms no `data_bag_item`, `Chef::EncryptedDataBagItem`, or Chef Vault calls. All secrets are hardcoded in recipe files. Ansible Vault will be introduced during migration as the secrets management solution.
8. **`www-data` nginx worker user**: The `nginx.conf.erb` template hardcodes `user www-data;`. On Fedora/RHEL, the nginx worker user is `nginx`. The Ansible template must parameterise this value or apply a platform conditional.
9. **Document root paths differ between `solo.json` and `attributes/default.rb`**: `attributes/default.rb` sets document roots under `/opt/server/<site>/`, while `solo.json` overrides them to `/var/www/<site>/`. The `solo.json` values take precedence at runtime. The Ansible `group_vars` will use the `/var/www/<site>/` paths from `solo.json` as the canonical values.
10. **No clustering or high-availability requirements**: Redis and Memcached are configured as single-node instances. No Redis Sentinel, Cluster, or Memcached consistent-hashing pool configuration is present or assumed to be needed.
11. **Vagrant is used for local development only**: The Ansible playbooks will be structured for general-purpose deployment (not Vagrant-specific), with a Vagrant-compatible inventory provided as a convenience for local testing.
12. **`selinux` policy management scope**: It is assumed that basic SELinux boolean adjustments (e.g., `httpd_can_network_connect`, Redis port labelling) are sufficient and that no custom SELinux policy modules need to be compiled.
