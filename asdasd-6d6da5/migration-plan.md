# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and tested locally with a **Vagrant + libvirt** development environment targeting **Fedora 42**.

The run list executes three cookbooks in order: `nginx-multisite → cache → fastapi-tutorial`, deploying a hardened Nginx reverse proxy with three SSL-enabled virtual hosts, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL.

**Overall migration complexity: Medium.** The cookbooks are well-structured, self-contained, and free of Chef Server dependencies (Chef Solo only). The primary challenges are replacing external Supermarket cookbook wrappers (`nginx`, `memcached`, `redisio`) with native Ansible modules, managing hardcoded credentials, and replicating a custom `lineinfile` resource and Redis config post-processing hack.

**Estimated timeline: 5–8 working days** for a single experienced Ansible engineer, broken down as:
- `nginx-multisite` cookbook → 2–3 days (most complex: 4 sub-recipes, 5 templates, security hardening)
- `cache` cookbook → 1–2 days (Redis auth, config patching hack, Memcached)
- `fastapi-tutorial` cookbook → 1–2 days (Python venv, PostgreSQL, systemd service, `.env` secrets)
- Integration testing and Vagrant/inventory parity → 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that require individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), security hardening via UFW firewall, Fail2Ban intrusion prevention, SSH hardening, and kernel-level sysctl security tuning. Generates self-signed TLS certificates per virtual host using OpenSSL. Includes a custom `lineinfile` Chef resource (reimplementing Ansible's own `lineinfile` module natively).
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Per-site Nginx virtual host templating with HTTP→HTTPS redirect, TLSv1.2/1.3-only cipher suites, HSTS headers, CSP/XSS/X-Frame security headers, Gzip compression, UFW default-deny with SSH/HTTP/HTTPS allowlist, Fail2Ban with `sshd`/`nginx-http-auth`/`nginx-limit-req`/`nginx-botsearch` jails, sysctl hardening (IP spoofing protection, SYN flood mitigation, ICMP suppression, IPv6 disable), SSH root login and password authentication disabled, rate-limiting zones (`login:10r/m`, `api:30r/m`), static site content deployment for three virtual hosts.

- **cache**:
  - Description: Dual caching layer configuration deploying Memcached (via the `memcached` Supermarket cookbook wrapper) and Redis (via the `redisio` Supermarket cookbook wrapper) with password authentication. Includes a `ruby_block` post-processing hack to strip deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` after `redisio` writes it.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached installation and service management, Redis on port 6379 with `requirepass` authentication, `/var/log/redis` directory provisioning, Redis service enablement via `redisio::enable`, config file post-processing to remove deprecated directives incompatible with the target Redis version.

- **fastapi-tutorial**:
  - Description: Full-stack Python FastAPI application deployment including system package installation, Git-based source code checkout from a public GitHub repository, Python virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd service unit creation for process management.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`; Git sync from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`); Python venv at `/opt/fastapi-tutorial/venv`; PostgreSQL user `fastapi` with password, database `fastapi_db`; `.env` file with `DATABASE_URL`; systemd unit running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as `root`; `systemctl daemon-reload` handler on service file change.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local and external cookbook sources. References Chef Supermarket for `nginx (~> 12.0)`, `memcached (~> 6.0)`, `redisio (~> 7.2.4)`. Note: `ssl_certificate (~> 2.1)` is commented out in the Berksfile but **present and locked** in `Policyfile.lock.json` (v2.1.0) — it is pulled in as a transitive dependency. Migration consideration: all external cookbook logic must be replaced with native Ansible modules or community roles.
- `Policyfile.rb`: Chef Policyfile defining the run list (`nginx-multisite::default → cache::default → fastapi-tutorial::default`) and pinning external cookbook versions. This defines the authoritative execution order for Ansible playbook task sequencing.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 cookbooks (3 local + 5 external: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). The `selinux` cookbook is a transitive dependency of `redisio` — relevant for RHEL/CentOS targets but not Ubuntu/Fedora in this Vagrant setup.
- `solo.json`: Chef Solo node attributes JSON. Overrides default document roots to `/var/www/<site>` (vs. `/opt/server/<site>` in cookbook defaults), enables SSL for all three virtual hosts, sets SSL cert/key paths, and enables all security features. This file is the **source of truth for variable values** and maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No migration action needed; replaced by Ansible inventory and `ansible.cfg`.
- `Vagrantfile`: Vagrant development environment using `generic/fedora42` box with libvirt provider (2 vCPUs, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync-based folder sync. Migration consideration: the Ansible inventory should reflect this host definition; the libvirt provider indicates a **KVM/QEMU** virtualization environment.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, then executes `chef-solo`. Migration consideration: replaced entirely by `ansible-playbook` invocation; the `apt-get update` call confirms the **Vagrant box uses an apt-based package manager** despite being Fedora-branded (or the script is not OS-aware — see Assumptions).
- `project-plan.md`: Internal X2Ansible tool specification document. Not part of the infrastructure being migrated; no migration action required.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Auto-generated project metadata directory containing a prior migration plan draft, a `solo.json` copy, and a locked Policyfile. Not part of the infrastructure being migrated.

---

### Target Details

- **Operating System**: The `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `vagrant-provision.sh` script uses `apt-get`, indicating an **Ubuntu/Debian** runtime assumption. The `Vagrantfile` specifies `generic/fedora42` as the Vagrant box, which is a **Fedora 42** guest — this is a conflict (see Assumptions). The `security.rb` recipe references `/var/log/auth.log` (Debian/Ubuntu path) and the `ufw`/`fail2ban` packages, further confirming an **Ubuntu** runtime target. The `nginx.rb` recipe uses `www-data` as the web server user (Debian/Ubuntu convention). **Recommended Ansible target: Ubuntu 22.04 LTS**, with RHEL 9 support as a secondary target if `centos >= 7.0` support is required.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. The VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present in any cookbook or configuration file.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook wrapping Nginx installation and service management. Replace with: `ansible.builtin.package` (install `nginx`), `ansible.builtin.template` (render `nginx.conf` and `security.conf` from existing `.erb` templates converted to Jinja2), `ansible.builtin.service` (enable/start), and `ansible.builtin.file` for document root directories. The existing `.erb` templates are straightforward and translate directly to Jinja2 with minimal changes (`<%= @var %>` → `{{ var }}`).

- **memcached (6.1.0)** — Chef Supermarket cookbook for Memcached installation. Replace with: `ansible.builtin.package` to install `memcached`, `ansible.builtin.service` to enable and start it. No complex configuration is applied beyond defaults in this stack.

- **redisio (7.2.4)** — Chef Supermarket cookbook for Redis installation and multi-instance management. Replace with: `ansible.builtin.package` to install `redis-server` (or `redis` on RHEL), `ansible.builtin.template` or `ansible.builtin.lineinfile` to write `/etc/redis/6379.conf` with `requirepass redis_secure_password_123`, `ansible.builtin.service` to enable/start. The `ruby_block` post-processing hack (stripping deprecated directives) becomes unnecessary if the Ansible-managed config template is written cleanly from scratch — this is a direct improvement over the Chef approach.

- **ssl_certificate (2.1.0)** — Locked transitive dependency (pulled in via `redisio` → `selinux` chain or directly). In this stack, SSL certificate generation is handled directly in `nginx-multisite::ssl` via `openssl req` shell commands, not via this cookbook. Replace with: `ansible.builtin.command` or `community.crypto.x509_certificate` + `community.crypto.openssl_privatekey` for self-signed certificate generation. The `community.crypto` collection is the idiomatic Ansible approach.

- **selinux (6.2.4)** — Transitive dependency of `redisio`. Not explicitly invoked in any local recipe. On Ubuntu targets, SELinux is not active (AppArmor is used instead). No direct migration action required for Ubuntu; if RHEL 9 is targeted, use `ansible.posix.selinux` module.

### Security Considerations

- **Hardcoded Redis password**: The Redis `requirepass` value `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`). **1 hardcoded credential detected in `cache` cookbook.** Migration action: move to `ansible-vault`-encrypted variable (e.g., `vault_redis_password`) stored in `group_vars/all/vault.yml`.

- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial` recipe hardcodes the PostgreSQL username (`fastapi`), password (`fastapi_password`), and database name (`fastapi_db`) in both the `execute` shell block and the `.env` file content. **2 hardcoded credentials detected in `fastapi-tutorial` cookbook** (DB password appears in both the `psql` command and the `DATABASE_URL` in `.env`). Migration action: parameterize as `vault_fastapi_db_password` in Ansible Vault; render the `.env` file via a Jinja2 template.

- **Self-signed TLS certificates**: All three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) use self-signed certificates generated at provision time via `openssl req -x509`. Certificate paths are `/etc/ssl/certs/<site>.crt` and `/etc/ssl/private/<site>.key`. The private key directory is mode `0710`, owned `root:ssl-cert`. Migration action: replicate with `community.crypto.x509_certificate` + `community.crypto.openssl_privatekey`, or retain the `ansible.builtin.command` approach with `creates:` idempotency guard. For production, replace with Let's Encrypt via `community.crypto.acme_certificate`.

- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` in `security.rb`. Migration action: use `ansible.builtin.lineinfile` (the module that the cookbook's custom `lineinfile` resource was reimplementing) with `regexp:` and `line:` parameters, followed by a `notify` handler to restart `sshd`. Ensure the Ansible control node has a non-root SSH key configured before applying this task, or it will lock out the provisioner.

- **UFW firewall**: Default-deny policy with explicit allow rules for SSH (22/tcp), HTTP (80/tcp), HTTPS (443/tcp). Migration action: use `community.general.ufw` module. Ensure SSH allow rule is applied **before** enabling the default-deny policy to avoid lockout — the Chef recipe already handles this ordering; replicate it in Ansible task order.

- **Fail2Ban**: Four active jails (`sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`) configured via `/etc/fail2ban/jail.local`. Migration action: convert `fail2ban.jail.local.erb` template to Jinja2 and deploy with `ansible.builtin.template`; manage service with `ansible.builtin.service`.

- **Sysctl kernel hardening**: 18 kernel parameters set via `/etc/sysctl.d/99-security.conf` (IP spoofing protection, ICMP suppression, SYN flood mitigation, IPv6 disable, source routing disable). Migration action: use `ansible.posix.sysctl` module for each parameter, or deploy the template file and notify a `sysctl -p` handler. The `ansible.posix` collection must be installed.

- **FastAPI service running as root**: The systemd unit in `fastapi-tutorial` sets `User=root`. This is a security risk. Migration action: flag for remediation — create a dedicated `fastapi` system user and run the service under that account in the Ansible role.

- **`.env` file permissions**: The `/opt/fastapi-tutorial/.env` file containing `DATABASE_URL` with plaintext credentials is created with mode `0644` (world-readable). Migration action: set mode to `0600` and owner to the service account in the Ansible task.

### Technical Challenges

- **Chef `ruby_block` Redis config hack**: The `cache` cookbook uses a `ruby_block` to post-process the Redis config file generated by `redisio`, stripping deprecated directives. This pattern has no direct Ansible equivalent and indicates the `redisio` cookbook generates a config incompatible with the installed Redis version. Migration action: write the Redis configuration template from scratch in Ansible, including only valid directives for the target Redis version. This eliminates the hack entirely and is the correct long-term fix.

- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements Ansible's `lineinfile` module as a Chef custom resource (with backup file creation). This resource does not appear to be called in any recipe in this repository (no `lineinfile` calls found in the recipes). Migration action: discard — Ansible's native `ansible.builtin.lineinfile` module provides this functionality out of the box.

- **Attribute precedence and `solo.json` overrides**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/<site>`, but `solo.json` overrides them to `/var/www/<site>`. In Ansible, this maps to role defaults vs. playbook/inventory variables. Migration action: define document roots in `group_vars` or `host_vars` to mirror the `solo.json` override behavior; role `defaults/main.yml` should hold the `/opt/server/<site>` fallback values.

- **ERB template to Jinja2 conversion**: Five ERB templates exist in `nginx-multisite`. The `site.conf.erb` template uses a conditional block (`<% if @ssl_enabled %>`) that spans multiple `server {}` blocks — the SSL-disabled branch leaves the HTTP server block unclosed before the conditional. This is valid ERB but requires careful Jinja2 translation using `{% if ssl_enabled %}` blocks. Review the template logic closely during conversion to avoid generating invalid Nginx config.

- **Vagrant box vs. provisioner OS mismatch**: The `Vagrantfile` uses `generic/fedora42` (RPM-based, uses `dnf`), but `vagrant-provision.sh` calls `apt-get update` and `apt-get install -y build-essential` (Debian/Ubuntu package manager). This will fail on Fedora 42. The cookbook `metadata.rb` supports Ubuntu and CentOS. Migration action: clarify the actual target OS before writing Ansible tasks; use `ansible_os_family` conditionals if multi-distro support is required. See Assumptions.

- **Git-based application deployment**: `fastapi-tutorial` clones from a public GitHub repository at provision time. This creates a runtime dependency on external network access and GitHub availability. Migration action: use `ansible.builtin.git` module with `version: main`; consider pinning to a specific commit SHA for reproducibility, or pre-packaging the application artifact.

- **`systemctl daemon-reload` handler**: The Chef recipe triggers `systemctl daemon-reload` via a `notifies :run` on the service file resource. In Ansible, this is handled by a handler using `ansible.builtin.systemd` with `daemon_reload: true`. Ensure the handler is defined in the role's `handlers/main.yml` and notified correctly from the service file template task.

- **PostgreSQL initialization idempotency**: The `create_db_user` execute block uses `|| true` to suppress errors on duplicate user/database creation. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent. The `community.postgresql` collection must be installed.

### Migration Order

1. **`nginx-multisite` — Security sub-recipe** (`security.rb`): Migrate UFW, Fail2Ban, sysctl hardening, and SSH configuration first. This is foundational and has no dependencies on other cookbooks. Establishes the security baseline before any services are exposed. Low risk of service disruption on a fresh host.

2. **`nginx-multisite` — Nginx + SSL + Sites sub-recipes** (`nginx.rb`, `ssl.rb`, `sites.rb`): Migrate Nginx installation, configuration templating, self-signed certificate generation, and virtual host activation. Depends on security baseline (UFW must allow ports 80/443 before Nginx is tested). Medium complexity due to template conversion and multi-site loop logic.

3. **`cache` — Redis**: Migrate Redis installation and configuration with authentication. Depends on nothing else in the stack. The config-patching hack is eliminated by writing a clean template. Low-to-medium complexity.

4. **`cache` — Memcached**: Migrate Memcached installation and service management. Trivial complexity; no configuration beyond defaults.

5. **`fastapi-tutorial`**: Migrate last as it depends on PostgreSQL (self-contained in the cookbook) and should be validated against a running Nginx proxy. Requires Ansible Vault setup for DB credentials before this role is applied. Medium complexity due to Python venv, Git checkout, PostgreSQL provisioning, and systemd service management.

### Assumptions

1. **Target OS ambiguity**: The `Vagrantfile` specifies `generic/fedora42` but `vagrant-provision.sh` uses `apt-get`, which is incompatible with Fedora. It is assumed the **actual production target is Ubuntu 22.04 LTS** (consistent with `www-data` user, `ufw`, `fail2ban`, `/var/log/auth.log`, and `apt`-based provisioning). The Fedora box may be a misconfiguration in the Vagrant development environment. This must be confirmed before writing Ansible tasks with OS-specific package names.

2. **Chef Solo only — no Chef Server**: The repository uses `chef-solo` with a local `solo.rb` and `solo.json`. There is no Chef Server, Knife configuration, data bags, Chef Vault, or encrypted data bags present. All node attributes are sourced from `solo.json` and cookbook `attributes/` files.

3. **Self-signed certificates are intentional**: All three virtual hosts use self-signed TLS certificates. This is assumed to be intentional for the development/internal cluster environment (`*.cluster.local` domains). No Let's Encrypt or CA-signed certificate workflow exists in the current codebase.

4. **`ssl_certificate` cookbook is unused at runtime**: Despite being locked in `Policyfile.lock.json`, the `ssl_certificate` Supermarket cookbook is not included in any recipe's `include_recipe` call. It is a transitive lock artifact. No migration action is required for this dependency.

5. **`selinux` cookbook is a no-op on Ubuntu**: The `selinux` cookbook (v6.2.4, transitive dependency of `redisio`) is not called in any local recipe. On Ubuntu, SELinux is not present. This dependency is safely ignored for the Ubuntu migration target.

6. **Redis runs on default port 6379 only**: The `redisio` configuration defines a single Redis instance on port 6379. No Redis Sentinel, clustering, or replication is configured.

7. **Memcached uses default configuration**: The `cache` cookbook calls `include_recipe 'memcached'` with no attribute overrides. Memcached is assumed to run on its default port (11211) with default memory allocation.

8. **FastAPI application `requirements.txt` exists in the repository**: The `fastapi-tutorial` recipe runs `pip install -r /opt/fastapi-tutorial/requirements.txt` after cloning. It is assumed this file exists in the `dibanez/fastapi_tutorial` GitHub repository at the `main` branch.

9. **PostgreSQL version is distribution-default**: No specific PostgreSQL version is pinned. The `postgresql` and `postgresql-contrib` packages installed are whatever the OS package manager provides. The Ansible migration should match this behavior unless a specific version is required.

10. **Document root path discrepancy is intentional**: The cookbook `attributes/default.rb` defines document roots as `/opt/server/<site>`, while `solo.json` overrides them to `/var/www/<site>`. The `solo.json` values are treated as the authoritative runtime configuration and will be used as the default values in the Ansible role variables.

11. **No multi-environment support required**: There is no Chef environment file, role file, or environment-specific attribute layering. The migration targets a single environment equivalent to the current `solo.json` configuration.

12. **The `lineinfile` custom resource is dead code**: No recipe in the repository calls the custom `lineinfile` resource defined in `cookbooks/nginx-multisite/resources/lineinfile.rb`. It will not be migrated.
