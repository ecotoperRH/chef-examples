# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through Vagrant on a Fedora 42 / libvirt VM.

The run list executes three cookbooks in order: `nginx-multisite → cache → fastapi-tutorial`, delivering a fully hardened Nginx multi-virtual-host server, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL.

**Overall migration complexity: Medium** — the logic is well-structured and self-contained, but several areas require careful handling: hardcoded credentials, self-signed SSL certificate generation, a custom Chef resource (`lineinfile`) that maps directly to a native Ansible module, and a Redis config post-processing hack that must be cleanly re-expressed.

**Estimated migration timeline: 5–8 days** for a single experienced engineer, broken down as:
- `nginx-multisite` cookbook → 2–3 days (most complex: 4 sub-recipes, 5 templates, custom resource, security hardening)
- `cache` cookbook → 1 day (Memcached + Redis with credential and config-fix concerns)
- `fastapi-tutorial` cookbook → 1–2 days (Python venv, PostgreSQL setup, systemd service, hardcoded secrets)
- Integration testing and validation → 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that need individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server configured with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), full security hardening via UFW firewall, Fail2Ban intrusion prevention, kernel-level sysctl network hardening, and per-site self-signed TLS certificate generation. Includes a custom `lineinfile` Chef resource for idempotent file-line management.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef (version ≥ 16.0)
  - Key Features:
    - Four sub-recipes: `security.rb`, `nginx.rb`, `ssl.rb`, `sites.rb` (executed in that order via `default.rb`)
    - Per-site Nginx virtual host config generated from `site.conf.erb` (HTTP→HTTPS redirect, TLS 1.2/1.3, HSTS, CSP, X-Frame-Options, X-Content-Type-Options)
    - Global `nginx.conf.erb` with gzip, sendfile, and keepalive tuning
    - Global `security.conf.erb` with rate-limiting zones (`login`, `api`), buffer overflow protections, and SSL session settings
    - Self-signed RSA-2048 certificate generation via `openssl req` for each SSL-enabled site
    - UFW firewall rules: default deny, allow SSH/HTTP/HTTPS
    - Fail2Ban with four jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch` (configured via `fail2ban.jail.local.erb`)
    - Kernel hardening via `sysctl-security.conf.erb`: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` (driven by `solo.json` attributes)
    - Static `index.html` files deployed per site (ci, status, test)
    - Custom `lineinfile` resource (`resources/lineinfile.rb`) with regex match/replace and timestamped backup support
    - Document root ownership set to `www-data:www-data`
    - Default Nginx site (`sites-enabled/default`) removed

- **cache**:
  - Description: Dual caching layer provisioning Memcached (via community cookbook) and Redis (via `redisio` community cookbook) with password authentication. Includes a post-install Ruby block hack to strip deprecated Redis replica configuration directives that cause failures with newer Redis versions.
  - Path: `cookbooks/cache`
  - Technology: Chef (version ≥ 16.0)
  - Key Features:
    - Memcached installation delegated to `memcached` community cookbook (v6.1.0)
    - Redis server on port 6379 with `requirepass` authentication (`redis_secure_password_123` — hardcoded)
    - Redis log directory `/var/log/redis` created with `redis:redis` ownership
    - `redisio` community cookbook (v7.2.4) used for Redis install and service enablement
    - Post-install `ruby_block` hack strips five deprecated directives from `/etc/redis/6379.conf`: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`
    - `selinux` cookbook (v6.2.4) pulled in transitively by `redisio`

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git repository clone, Python virtual environment setup, pip dependency installation, PostgreSQL database and user provisioning, `.env` configuration file generation, and systemd service unit creation and enablement.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef (version ≥ 16.0)
  - Key Features:
    - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Application cloned from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) into `/opt/fastapi-tutorial`
    - Python venv created at `/opt/fastapi-tutorial/venv`; dependencies installed from `requirements.txt`
    - PostgreSQL service enabled and started
    - PostgreSQL user `fastapi` created with password `fastapi_password` (hardcoded); database `fastapi_db` created and granted
    - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (credentials in plaintext, mode `0644`)
    - systemd unit `/etc/systemd/system/fastapi-tutorial.service` created: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, runs as `root`, `After=postgresql.service`
    - `systemctl daemon-reload` triggered on unit file change
    - Service enabled and started

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local cookbook paths and external Supermarket dependencies with version constraints. References `nginx (~> 12.0)`, `memcached (~> 6.0)`, `redisio (~> 7.2.4)`, `ssl_certificate (~> 2.1)`. The `ssl_certificate` entry is commented out in the Berksfile but **active** in `Policyfile.rb` and resolved in `Policyfile.lock.json` — this inconsistency must be resolved during migration.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), run list, and all cookbook sources/version constraints. This is the authoritative dependency declaration.
- `Policyfile.lock.json`: Fully resolved dependency lock file. Pins: `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `nginx-multisite 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. Replaces with Ansible Galaxy `requirements.yml`.
- `solo.json`: Chef Solo JSON attributes file. Overrides default document roots to `/var/www/<site>` (vs. `/opt/server/<site>` in cookbook defaults), enables SSL for all three sites, sets SSL cert/key paths, and enables all security features. This file becomes Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration: sets `file_cache_path`, `cookbook_path`, log level. No Ansible equivalent needed — replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Provisions via `vagrant-provision.sh`. Becomes an Ansible inventory file + `ansible.cfg` for local testing, or a molecule test scenario.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. Replaced entirely by an Ansible playbook invocation. Note: the script references `192.168.56.10` in its output messages but the Vagrantfile uses `192.168.121.10` — a latent inconsistency.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata listing the three cookbooks with descriptions. Used by the X2Ansible tooling.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/solo.json`: Duplicate of root `solo.json` with identical content. Likely a project artifact; no separate migration action needed.
- `project-plan.md`: X2Ansible tool specification document. Not infrastructure code; no migration action needed.

---

### Target Details

- **Operating System**: Ubuntu (≥ 18.04) or CentOS (≥ 7.0) per `metadata.rb` `supports` declarations. The Vagrant box is `generic/fedora42`, indicating the active development/test target is **Fedora 42** (RPM-based). However, the recipes use Debian/Ubuntu conventions (`www-data` user, `ufw`, `apt`-style package names, `/etc/nginx/sites-available` layout), suggesting the **primary production target is Ubuntu/Debian**. The Ansible playbooks should target **Ubuntu 22.04 LTS** as the primary OS, with conditional task blocks for RPM-based systems if Fedora/CentOS support is required. Defaulting to **Red Hat Enterprise Linux 9** for any unspecified targets.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly declared in the Vagrantfile (`config.vm.provider "libvirt"`). VM title: `chef-nginx-multisite`, 2 vCPU, 2 GB RAM.
- **Cloud Platform**: Not specified. No cloud-provider-specific configurations, metadata endpoints, or SDK references are present. The infrastructure is designed for on-premises or local VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community `nginx` cookbook is referenced in the Policyfile and Berksfile but is **not directly `include_recipe`'d** in any local cookbook recipe — Nginx is installed via a plain `package 'nginx'` resource in `nginx-multisite::nginx`. Replace with the `ansible.builtin.package` module. The `nginx` Ansible collection (`nginxinc.nginx`) is available from Ansible Galaxy if more advanced management is needed, but the plain package approach is sufficient here.
- **memcached (6.1.0, Chef Supermarket)**: Fully delegated to the community cookbook via `include_recipe 'memcached'`. Replace with `ansible.builtin.package` to install `memcached`, `ansible.builtin.template` or `ansible.builtin.copy` for configuration, and `ansible.builtin.service` to enable/start. The `community.general` collection provides no dedicated Memcached module; direct task-based management is appropriate.
- **redisio (7.2.4, Chef Supermarket)**: Used for Redis installation, configuration (including `requirepass`), and service enablement. Replace with `ansible.builtin.package` (`redis` or `redis-server`), `ansible.builtin.template` for `redis.conf`, and `ansible.builtin.service`. The post-install config-stripping hack must be replaced with explicit `ansible.builtin.lineinfile` tasks removing the deprecated directives — this is cleaner and idempotent.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Present in `Policyfile.rb` and lock file but **not directly used** in any recipe (SSL cert generation is done inline via `openssl req` shell commands). No direct Ansible replacement needed; use `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` modules for idiomatic self-signed cert generation.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. On Ubuntu targets, SELinux is not active (AppArmor is used instead) so this dependency has no effect. On RHEL/Fedora targets, use the `ansible.posix.selinux` module and `community.general.seboolean` as needed for Redis/Nginx SELinux contexts.
- **Custom `lineinfile` Chef resource** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): A hand-rolled implementation of line-in-file editing with regex match/replace and backup. Replace directly with the native `ansible.builtin.lineinfile` module, which provides identical functionality natively.

---

### Security Considerations

- **Hardcoded Redis password** (`cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`): Plaintext credential embedded in recipe source code. **Must be migrated to Ansible Vault.** Create an encrypted variable `vault_redis_password` and reference it in the Redis configuration template. Count: **1 hardcoded service credential**.

- **Hardcoded PostgreSQL credentials** (`fastapi-tutorial/recipes/default.rb`): PostgreSQL user `fastapi` with password `fastapi_password` appears in three locations: the `psql` provisioning command, the `.env` file content, and implicitly in the `DATABASE_URL`. **Must be migrated to Ansible Vault.** Create `vault_fastapi_db_password` and use it in both the `postgresql_user` task and the `.env` template. Count: **1 hardcoded database credential (referenced in 3 places)**.

- **Plaintext `.env` file** (`fastapi-tutorial/recipes/default.rb`): The `.env` file is written with mode `0644` (world-readable) and contains the database URL with embedded password. In Ansible, use `ansible.builtin.template` with mode `0600`, owned by the application service user (not `root`). The service should not run as `root` (see Technical Challenges).

- **Self-signed SSL certificates**: Generated via inline `openssl req` shell commands with a hardcoded subject string (`/C=US/ST=Example/...`). These are development-only certificates. For production, integrate with Let's Encrypt via `community.crypto.acme_certificate` or deploy organization-issued certificates. For the development/test parity use case, replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` Ansible tasks.

- **SSL certificate private key permissions**: The Chef recipe sets `chmod 640` and `chown root:ssl-cert` on private keys — this is correct. Ensure the Ansible equivalent explicitly sets `owner: root`, `group: ssl-cert`, `mode: '0640'` on the key file task.

- **SSH hardening** (`nginx-multisite/recipes/security.rb`): `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` on `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` tasks (or the `devsec.hardening.ssh_hardening` role for a more comprehensive approach). Ensure the Ansible control node has a non-root SSH user with key-based auth configured **before** applying these restrictions, or the playbook will lock itself out.

- **UFW firewall management**: Managed via raw `ufw` shell commands with idempotency guards (`not_if` checks). Replace with `community.general.ufw` module for fully declarative, idempotent firewall management.

- **Fail2Ban configuration**: Deployed via template with four active jails. Replace with `ansible.builtin.template` for `jail.local` and `ansible.builtin.service` for the `fail2ban` service. The `community.general` collection has no dedicated Fail2Ban module; template-based management is appropriate.

- **Kernel sysctl hardening**: Applied via `sysctl-security.conf.erb` template to `/etc/sysctl.d/99-security.conf`. Replace with `ansible.posix.sysctl` module for each parameter, or deploy the template with `ansible.builtin.template` and notify a `sysctl -p` handler. Note: `net.ipv4.icmp_echo_ignore_all = 1` will block ICMP ping to the host — verify this is intentional in the target environment.

- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk. The Ansible migration should create a dedicated `fastapi` system user and update the service unit accordingly.

- **Vault/Secrets summary by module**:
  - `nginx-multisite`: 0 hardcoded credentials; SSL subject fields are placeholder values (not secrets)
  - `cache`: 1 hardcoded credential (Redis `requirepass`)
  - `fastapi-tutorial`: 1 hardcoded credential (PostgreSQL password, used in 3 locations + `.env` file)
  - **Total: 2 credentials requiring Ansible Vault encryption**

---

### Technical Challenges

- **Berksfile / Policyfile `ssl_certificate` inconsistency**: The `ssl_certificate` cookbook is commented out in `Berksfile` but active in `Policyfile.rb` and fully resolved in the lock file. Since no recipe directly calls it, it is likely an unused transitive artifact. Confirm it is not needed and exclude it from the Ansible migration. If it was intended for future use, document the intent.

- **Document root path conflict between `attributes/default.rb` and `solo.json`**: The cookbook attributes define document roots as `/opt/server/{site}`, but `solo.json` overrides them to `/var/www/{site}`. The static `index.html` files are deployed to the path from `config['document_root']` (the overridden value), so the effective paths are `/var/www/test.cluster.local`, etc. In Ansible, this must be expressed as a single authoritative variable in `group_vars` — the dual-definition pattern does not exist.

- **Redis `ruby_block` config-stripping hack**: The post-install mutation of `/etc/redis/6379.conf` to remove deprecated directives is fragile and non-idempotent (it runs on every Chef converge). In Ansible, replace with a proper `redis.conf` template that never includes the deprecated directives, or use `ansible.builtin.lineinfile` with `state: absent` and a regex for each directive. The root cause is that `redisio 7.2.4` generates config for an older Redis version; the Ansible role should target the installed Redis version directly.

- **Custom `lineinfile` Chef resource**: The hand-rolled resource creates timestamped backup files (e.g., `/etc/ssh/sshd_config.backup.1234567890`) on every change. The native `ansible.builtin.lineinfile` module's `backup: yes` option creates a single `.bak` file. Ensure the backup behavior expectation is documented and agreed upon before migration.

- **Vagrant box is Fedora 42 but recipes target Ubuntu/Debian**: The `nginx-multisite` recipes use `www-data` as the Nginx user, `ufw` for firewall, and `/etc/nginx/sites-available` / `sites-enabled` directory layout — all Debian/Ubuntu conventions. On Fedora/RHEL, Nginx runs as `nginx`, the firewall is `firewalld`, and the sites directory layout differs. The Ansible roles must include OS-family conditionals (`when: ansible_os_family == "Debian"` vs. `"RedHat"`) or the target OS must be standardized. This is the single largest portability risk.

- **FastAPI application cloned from a public GitHub repository**: The `git` resource clones `https://github.com/dibanez/fastapi_tutorial.git` at the `main` branch on every converge (`:sync` action). This creates a runtime dependency on external internet access and branch stability. In Ansible, use `ansible.builtin.git` with a pinned `version` (commit SHA or tag) and consider mirroring the repository internally for production use.

- **PostgreSQL provisioning via raw `psql` shell commands**: The `execute 'create_db_user'` resource uses `sudo -u postgres psql -c "..."` with `|| true` to suppress errors. This is not idempotent in a meaningful way — it will silently succeed even if the user/database already exists with different settings. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are fully idempotent and handle existing objects correctly.

- **`systemctl daemon-reload` as a notified execute resource**: In Chef, this is triggered via `:nothing` + `notifies`. In Ansible, use a handler with `ansible.builtin.systemd: daemon_reload: yes` that is notified by the service unit file task — this is the idiomatic equivalent.

- **Vagrant IP address inconsistency**: `Vagrantfile` assigns `192.168.121.10` but `vagrant-provision.sh` prints `192.168.56.10` in its completion message. This is a latent bug in the existing codebase. The Ansible inventory should use the correct address from the Vagrantfile (`192.168.121.10`).

---

### Migration Order

The following order respects the run-list sequence and dependency graph, starting with the lowest-risk, highest-isolation module:

1. **`cache` cookbook** — Lowest external surface area; Memcached has no credentials and Redis credential migration to Vault is straightforward. Validates the Vault setup and Redis template approach before tackling more complex cookbooks. Resolves the `redisio` hack cleanly.

2. **`nginx-multisite` cookbook** — Core infrastructure module. Migrate in sub-recipe order:
   - `security` recipe first (UFW, Fail2Ban, sysctl, SSH hardening) — foundational, no service dependencies
   - `nginx` recipe (package, global config, document roots, static files)
   - `ssl` recipe (cert/key generation using `community.crypto` modules)
   - `sites` recipe (per-site virtual host configs, symlinks, default site removal)
   - Migrate the custom `lineinfile` resource → document its replacement with `ansible.builtin.lineinfile`

3. **`fastapi-tutorial` cookbook** — Most complex due to multi-step application deployment, external Git dependency, PostgreSQL provisioning, and the highest concentration of security issues (hardcoded credentials, root service user, world-readable `.env`). Should be migrated last after Vault patterns are established and PostgreSQL collection is confirmed available.

4. **Integration & validation** — Run the full playbook against a fresh Vagrant VM, validate all three sites are reachable over HTTPS, Redis and Memcached are responsive, and the FastAPI service is running. Compare against the original Chef Solo output.

---

### Assumptions

1. **Target OS for Ansible playbooks is Ubuntu 22.04 LTS** (Debian family), based on the Debian-specific conventions used throughout the recipes (`www-data`, `ufw`, `sites-available/sites-enabled`). The Fedora 42 Vagrant box is assumed to be a developer convenience, not the production target. If RHEL/Fedora is the true production target, significant OS-family branching will be required.

2. **The `ssl_certificate` community cookbook is unused** and its presence in the lock file is an artifact. No Ansible equivalent needs to be created for it.

3. **The `nginx` community cookbook (12.3.1) is not directly invoked** by any local recipe. Its presence in the Policyfile is either a transitive pull or a leftover. The Ansible migration will install Nginx via `ansible.builtin.package` without a dedicated Galaxy role unless confirmed otherwise.

4. **Self-signed certificates are acceptable for the target environment** (development/staging). If this is a production migration, the SSL recipe must be replaced with a proper CA-signed or Let's Encrypt certificate workflow.

5. **The FastAPI application at `https://github.com/dibanez/fastapi_tutorial.git` is the correct and intended source repository**, and internet access from the target host is available during provisioning.

6. **Ansible Vault will be used for all credentials**. It is assumed the team has an established Vault password management process (password file, `--vault-password-file`, or HashiCorp Vault integration).

7. **The `selinux` cookbook's transitive inclusion has no functional effect on Ubuntu targets**. If RHEL/Fedora is targeted, SELinux boolean and context management for Nginx and Redis must be explicitly added to the Ansible roles.

8. **The three virtual hostnames** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) are resolvable on the target network via `/etc/hosts` or internal DNS. The Ansible playbook should optionally manage `/etc/hosts` entries (the commented-out block in the Vagrantfile suggests this was intentional but deferred).

9. **The document root paths from `solo.json`** (`/var/www/<site>`) take precedence over the cookbook attribute defaults (`/opt/server/<site>`). The Ansible `group_vars` will use `/var/www/<site>` as the canonical value.

10. **The FastAPI service user will be changed from `root` to a dedicated `fastapi` system account** during migration. This is a security improvement, not a regression, but must be validated against the application's file permission requirements.

11. **Memcached is configured with default settings** (no authentication, default port 11211, localhost binding). The `memcached` community cookbook is called with no attribute overrides in `cache/recipes/default.rb`, so no custom configuration is assumed beyond package installation and service enablement.

12. **The `lineinfile` custom Chef resource** is used internally within the cookbook but is not called from any of the current recipes (no `lineinfile` resource calls appear in the recipe files). It may be dead code or intended for future use. It will be documented but not actively migrated unless a usage is discovered.
