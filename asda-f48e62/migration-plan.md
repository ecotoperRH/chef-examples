# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through a Vagrant-managed Fedora 42 VM using `chef-solo`.

The run list executes three cookbooks in order: `nginx-multisite → cache → fastapi-tutorial`, deploying a hardened Nginx reverse proxy with three SSL-enabled virtual hosts, a dual-cache layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL.

**Overall Migration Complexity: Medium**
The infrastructure is well-structured and self-contained. The primary challenges are replacing Chef community cookbook abstractions (`nginx ~> 12.3.1`, `memcached ~> 6.1.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1.0`) with native Ansible modules, migrating a custom `lineinfile` LWRP to the built-in `ansible.builtin.lineinfile` module, and safely handling the hardcoded credentials present in the source recipes.

**Estimated Timeline: 5–8 days** for a single experienced Ansible engineer, broken down as:
- `nginx-multisite` cookbook: 2–3 days (most complex; security hardening, SSL, multi-site templating)
- `cache` cookbook: 1–2 days (Redis + Memcached service configuration)
- `fastapi-tutorial` cookbook: 1–2 days (Python venv, PostgreSQL, systemd service)
- Integration, testing, and Vagrant validation: 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that require individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), full security hardening via UFW firewall, Fail2Ban intrusion prevention, SSH hardening, and kernel-level sysctl security tuning. Generates self-signed TLS certificates per virtual host using OpenSSL. Serves static HTML content per site from cookbook-managed files.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - Multi-recipe structure: `default → security → nginx → ssl → sites`
    - Nginx global config (`nginx.conf.erb`) and per-site virtual host config (`site.conf.erb`) via ERB templates
    - Security headers: HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP, Referrer-Policy
    - TLS 1.2/1.3 only with strong cipher suites; HTTP-to-HTTPS redirect per site
    - UFW rules: default deny, allow SSH/HTTP/HTTPS
    - Fail2Ban jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
    - Nginx rate limiting zones (`login`: 10r/m, `api`: 30r/m) via `security.conf.erb`
    - Kernel hardening via `sysctl-security.conf.erb`: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` in-place edits
    - Custom LWRP `lineinfile` resource (reimplements Ansible's native `lineinfile` in Ruby)
    - Static site content files: `ci/index.html`, `status/index.html`, `test/index.html`

- **cache**:
  - Description: Dual-layer caching service configuration deploying both Memcached and Redis on a single node. Redis is configured with password authentication and a post-install config-file sanitization workaround to remove deprecated `replica-*` directives written by the `redisio` community cookbook.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Delegates Memcached installation to the `memcached ~> 6.1.0` community cookbook
    - Delegates Redis installation to the `redisio ~> 7.2.4` community cookbook with `redisio::enable`
    - Redis instance on port `6379` with `requirepass` authentication
    - `ruby_block "fix_redis_config"` hack: post-processes `/etc/redis/6379.conf` to strip deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that cause Redis startup failures on newer versions
    - Creates `/var/log/redis` directory with correct `redis:redis` ownership

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git-based source checkout, Python virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation for process supervision.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch to `/opt/fastapi-tutorial`
    - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs from `requirements.txt`
    - PostgreSQL service enabled and started; database `fastapi_db`, user `fastapi` provisioned via `psql` shell commands with `|| true` idempotency guards
    - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL` with embedded plaintext credentials
    - Systemd unit `/etc/systemd/system/fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, runs as `root`, `After=postgresql.service`
    - `systemctl daemon-reload` triggered via Chef notification on service file change

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local cookbook paths and external Supermarket sources with version constraints. Used by `vagrant-provision.sh` to vendor dependencies before `chef-solo` execution. Maps directly to Ansible Galaxy `requirements.yml` in the target state.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list and pinned cookbook versions. Defines the authoritative execution order: `nginx-multisite::default → cache::default → fastapi-tutorial::default`. Equivalent to an Ansible playbook's `roles:` or `tasks:` ordering.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Informs the exact community role/collection versions to pin in Ansible.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides: site definitions with document roots and SSL flags, SSL certificate/key paths, and security feature toggles (fail2ban, ufw, SSH hardening). This file is the primary source of truth for variable values and maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration file setting `file_cache_path`, `cookbook_path`, log level, and log destination. No direct Ansible equivalent needed; superseded by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, `libvirt` provider (2 vCPU, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of repo to `/chef-repo`. Defines the target test environment. Should be adapted to use the `ansible` Vagrant provisioner pointing at the migrated playbook.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, vendors cookbook dependencies, and runs `chef-solo`. In the Ansible world this is replaced by Vagrant's native `ansible_local` or `ansible` provisioner — no bootstrap script needed.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata listing the three cookbooks with descriptions. Used by the X2Ansible tooling; no migration action required.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/solo.json`: Duplicate of root `solo.json` with slightly different document root paths (`/var/www/` prefix vs `/opt/server/` prefix). The discrepancy between this file and the root `solo.json` must be resolved before migration — the canonical document root paths need to be confirmed.

---

### Target Details

- **Operating System**: The `Vagrantfile` explicitly specifies `generic/fedora42` (Fedora Linux 42). However, `metadata.rb` files in all three cookbooks declare support for `ubuntu >= 18.04` and `centos >= 7.0` only — Fedora is not listed. The `vagrant-provision.sh` script uses `apt-get`, which is Debian/Ubuntu-specific and will fail on Fedora (which uses `dnf`). This is a critical inconsistency. The Ansible migration should target **Ubuntu 22.04 LTS** (aligning with the `apt`-based provisioning script and cookbook `supports` declarations) unless the team confirms Fedora/RHEL as the intended target, in which case all package names and service names must be audited for RPM equivalents.
- **Virtual Machine Technology**: **KVM/libvirt** — confirmed by `config.vm.provider "libvirt"` in the `Vagrantfile`. The VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references are present. The infrastructure is designed for local/on-premises deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook wrapping Nginx installation and service management. Replace with `ansible.builtin.package` (package name: `nginx`), `ansible.builtin.template` for `nginx.conf`, and `ansible.builtin.service`. The `nginxinc.nginx` Ansible Galaxy role is an optional drop-in if a community role is preferred.
- **memcached (6.1.0)** — Chef community cookbook for Memcached installation and service. Replace with `ansible.builtin.package` (package: `memcached`) and `ansible.builtin.service`. Configuration via `ansible.builtin.template` or `ansible.builtin.lineinfile`.
- **redisio (7.2.4)** — Chef community cookbook for Redis multi-instance management. Replace with `ansible.builtin.package` (package: `redis-server` on Ubuntu / `redis` on RHEL), `ansible.builtin.template` for `/etc/redis/redis.conf`, and `ansible.builtin.service`. The post-install config-file hack in `cache::default` becomes unnecessary since Ansible templates the config file directly — the deprecated directives simply will not be written.
- **ssl_certificate (2.1.0)** — Chef community cookbook for SSL certificate management. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection (`ansible-galaxy collection install community.crypto`). This provides idempotent, declarative self-signed certificate generation without shell `openssl` commands.
- **selinux (6.2.4)** — Transitive dependency of `redisio`; manages SELinux policy. On Ubuntu (the confirmed target), SELinux is not present — this dependency is a no-op and can be dropped entirely. If migrating to RHEL/Fedora, use `ansible.posix.selinux` from the `ansible.posix` collection.

### Security Considerations

- **Hardcoded Redis password**: The `cache::default` recipe hardcodes `requirepass redis_secure_password_123` directly in the recipe source. In Ansible, this must be extracted to an **Ansible Vault**-encrypted variable (e.g., `vault_redis_password`) stored in `group_vars/all/vault.yml`. The Redis config template should reference `{{ vault_redis_password }}`.
  - **Credentials detected in `cache` cookbook**: 1 hardcoded secret (Redis `requirepass`).

- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial::default` recipe hardcodes the PostgreSQL user password (`fastapi_password`) in three places: the `psql` provisioning commands, the `.env` file content, and implicitly in the `DATABASE_URL`. All three must be replaced with a single Vault-encrypted variable (e.g., `vault_fastapi_db_password`).
  - **Credentials detected in `fastapi-tutorial` cookbook**: 2 hardcoded secrets (PostgreSQL user password in `psql` commands + `.env` file `DATABASE_URL`).

- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated at runtime via `openssl req -x509`. The certificate subject is hardcoded with `emailAddress=admin@example.com` and a 365-day validity. In Ansible, use `community.crypto` modules for idempotent generation. For production, replace with Let's Encrypt via `community.crypto.acme_certificate` or the `geerlingguy.certbot` role. The certificate and key paths (`/etc/ssl/certs`, `/etc/ssl/private`) are parameterized in attributes and `solo.json` — map these to Ansible variables.
  - **Credentials detected in `nginx-multisite` cookbook**: 0 hardcoded secrets; certificate generation is runtime-computed. However, the private key file permissions (`chmod 640`, `chown root:ssl-cert`) must be faithfully reproduced in Ansible using `ansible.builtin.file`.

- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed -i` shell commands. This is fragile and non-idempotent if the file format changes. Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`, with a handler to restart `sshd`.

- **FastAPI service runs as `root`**: The systemd unit file sets `User=root`. This is a security risk and should be flagged for remediation during migration — create a dedicated `fastapi` system user and update `WorkingDirectory` and file ownership accordingly.

- **`.env` file permissions**: The `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded credentials to all local users. The Ansible task should set mode `0600` and ownership to the service account.

- **Vault/secrets summary**:
  | Module | Secret | Current Location | Ansible Vault Key |
  |---|---|---|---|
  | cache | Redis password (`redis_secure_password_123`) | `recipes/default.rb` line 7 | `vault_redis_password` |
  | fastapi-tutorial | PostgreSQL password (`fastapi_password`) | `recipes/default.rb` lines 34–36, 43 | `vault_fastapi_db_password` |
  | nginx-multisite | SSL cert subject email (`admin@example.com`) | `recipes/ssl.rb` line 22 | `nginx_ssl_cert_email` (non-sensitive, but parameterize) |

### Technical Challenges

- **OS/package manager mismatch**: The `Vagrantfile` targets Fedora 42 (`dnf`-based) while `vagrant-provision.sh` calls `apt-get` and all `metadata.rb` files declare Ubuntu/CentOS support. This will cause the current Chef setup to fail on Fedora as-is. The Ansible migration must first resolve the target OS. If Ubuntu is chosen, package names are straightforward (`nginx`, `redis-server`, `memcached`, `postgresql`). If Fedora/RHEL is chosen, package names differ (`redis`, `postgresql-server`) and service initialization differs (`postgresql-setup --initdb` is required on RHEL before first start).

- **`redisio` config-file hack**: The `ruby_block "fix_redis_config"` in `cache::default` is a workaround for the `redisio` community cookbook writing deprecated Redis directives. Since Ansible will template the Redis config file directly (not delegate to a community cookbook), this workaround is entirely unnecessary — the Ansible template simply omits the deprecated directives. This simplifies the migration but requires careful review of the full Redis configuration to ensure no other `redisio`-managed settings are missed.

- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` resource (`resources/lineinfile.rb`) that reimplements line-in-file editing with backup support. This maps directly and completely to `ansible.builtin.lineinfile`. The custom resource is not called anywhere in the current recipes (it appears to be a utility resource available for use), so no active usage needs to be migrated — but its existence should be noted for completeness.

- **Chef attribute precedence vs. Ansible variable precedence**: The `solo.json` overrides default attributes from `attributes/default.rb` (e.g., document roots differ: `attributes/default.rb` uses `/opt/server/{site}` while `solo.json` uses `/var/www/{site}` and the project's `solo.json` uses `/var/www/{site}`). In Ansible, this maps to `defaults/main.yml` (cookbook defaults) overridden by `group_vars` or `host_vars` (node JSON). The canonical document root paths must be confirmed before migration.

- **Git-based application deployment**: The `fastapi-tutorial` recipe uses Chef's `git` resource to clone and sync `https://github.com/dibanez/fastapi_tutorial.git`. In Ansible, `ansible.builtin.git` provides equivalent functionality. The `revision: main` tracking means every Chef run may pull new commits — the Ansible equivalent should use `update: yes` with `version: main`, but teams should consider pinning to a specific tag or commit SHA for reproducibility in production.

- **Idempotency of PostgreSQL provisioning**: The `create_db_user` execute block uses `|| true` to suppress errors on duplicate user/database creation. Ansible's `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules are natively idempotent and should replace the raw `psql` shell commands entirely. The `community.postgresql` collection must be installed (`ansible-galaxy collection install community.postgresql`).

- **Nginx `sites-available` / `sites-enabled` pattern**: The `sites.rb` recipe uses symlinks (`link` resource) to enable sites. Ansible's `ansible.builtin.file` with `state: link` handles this directly. The default site deletion (`file '/etc/nginx/sites-enabled/default' do action :delete`) maps to `ansible.builtin.file` with `state: absent`.

- **`www-data` vs. service user**: The `nginx.rb` recipe hardcodes `owner 'www-data'` for document roots. On RHEL/Fedora, the Nginx user is `nginx`, not `www-data`. This must be parameterized as a variable (e.g., `nginx_user`) in the Ansible role.

### Migration Order

1. **`nginx-multisite` — Security sub-role** (`recipes/security.rb`): Migrate UFW, Fail2Ban, sysctl hardening, and SSH configuration first. These are foundational, have no inter-cookbook dependencies, and establish the security baseline. Low risk; maps cleanly to `ansible.builtin.package`, `ansible.builtin.template`, `ansible.builtin.sysctl`, `ansible.builtin.lineinfile`, and `ansible.posix.ufw` (from `ansible.posix` collection).

2. **`nginx-multisite` — Nginx + SSL + Sites sub-roles** (`recipes/nginx.rb`, `recipes/ssl.rb`, `recipes/sites.rb`): Migrate Nginx installation, global config, SSL certificate generation, virtual host templating, and static file deployment. Medium complexity due to the multi-site loop and `community.crypto` collection requirement. Depends on step 1 (security baseline must be in place).

3. **`cache` cookbook** (`recipes/default.rb`): Migrate Memcached and Redis installation and configuration. Medium complexity due to the Redis password secret and the need to replace the `redisio` community cookbook with direct Ansible tasks. The config-file hack is eliminated. Depends on nothing from the other cookbooks — can be developed in parallel with step 2.

4. **`fastapi-tutorial` cookbook** (`recipes/default.rb`): Migrate Python environment setup, Git checkout, PostgreSQL provisioning, `.env` file, and systemd service. Medium complexity due to PostgreSQL community collection requirement, secret management for DB credentials, and the service-runs-as-root security issue that should be remediated during migration. Depends on nothing from the other cookbooks but logically runs after the web server is in place.

5. **Integration & Vagrant validation**: Update `Vagrantfile` to use the `ansible_local` provisioner pointing at the new `site.yml` playbook. Remove `vagrant-provision.sh`. Validate all three virtual hosts respond correctly over HTTPS, Redis and Memcached are reachable, and the FastAPI service starts successfully.

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS**, not Fedora 42. The `vagrant-provision.sh` script uses `apt-get`, all `metadata.rb` files declare Ubuntu support, and package names throughout the recipes are Debian-style. The `generic/fedora42` Vagrant box appears to be an environment inconsistency. This assumption must be confirmed with the team — if Fedora/RHEL is the true target, package names, service names, and the PostgreSQL initialization procedure all require adjustment.

2. **Document root paths**: The root `solo.json` and the project `solo.json` both use `/var/www/{site}` as document roots, while `attributes/default.rb` uses `/opt/server/{site}`. The `solo.json` runtime override takes precedence in Chef. The Ansible migration will use `/var/www/{site}` as the default, matching the `solo.json` values, but this should be confirmed.

3. **Self-signed certificates are acceptable for the target environment**. The current setup generates self-signed certificates with a 365-day validity. If this is a production environment, Let's Encrypt or an internal CA should be used instead. The migration plan assumes self-signed certificates are intentional (development/staging environment).

4. **The FastAPI application source at `https://github.com/dibanez/fastapi_tutorial.git` is accessible** from the target environment at provisioning time. If the environment is air-gapped or the repository is private, an alternative artifact delivery mechanism (e.g., pre-packaged archive, internal Git mirror) must be arranged.

5. **Redis is a single-instance deployment** on port 6379 with no replication. The `redisio` cookbook supports multi-instance Redis, but only one instance is configured. The Ansible migration targets a single Redis instance.

6. **Memcached configuration is default**. The `cache` cookbook delegates entirely to `include_recipe 'memcached'` with no attribute overrides. The Ansible migration will install Memcached with default settings (port 11211, localhost binding). If custom Memcached settings are needed, they must be sourced from the `memcached 6.1.0` cookbook's default attributes.

7. **PostgreSQL version is OS-default**. The `fastapi-tutorial` recipe installs `postgresql` and `postgresql-contrib` without specifying a version, relying on the OS package manager's default. On Ubuntu 22.04 this is PostgreSQL 14. If a specific version is required, the Ansible role must add the official PostgreSQL APT repository.

8. **The `ssl-cert` group** used in `ssl.rb` (`group 'ssl-cert'`) is a standard Ubuntu group created by the `ssl-cert` package. On other distributions this group may not exist and must be created explicitly. The Ansible role should include a task to ensure the group exists.

9. **Fail2Ban log paths** in `fail2ban.jail.local.erb` reference `/var/log/auth.log` (Debian/Ubuntu path). On RHEL/Fedora the equivalent is `/var/log/secure`. If the target OS changes, the Fail2Ban jail configuration must be updated accordingly.

10. **The `lineinfile` custom LWRP** in `resources/lineinfile.rb` is defined but not called by any recipe in this repository. It is treated as dead code and will not be actively migrated, but its existence is documented for completeness.

11. **No Chef encrypted data bags or Chef Vault** are used in this repository. All secrets are stored as plaintext in recipe source code. The migration to Ansible Vault represents a security improvement over the current state.

12. **IPv6 is intentionally disabled** via `sysctl-security.conf.erb` (`net.ipv6.conf.all.disable_ipv6 = 1`). This is carried forward into the Ansible `sysctl` tasks. If IPv6 is required in the target environment, this setting must be removed.
