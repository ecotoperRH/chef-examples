# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure project that provisions a multi-service web stack on a single virtual machine (Fedora 42 / libvirt via Vagrant). It contains **3 local Chef cookbooks** and relies on **5 external Chef Supermarket cookbooks** resolved via Berkshelf and a Policyfile. The run-list executes all three local cookbooks in sequence: `nginx-multisite → cache → fastapi-tutorial`.

The overall migration complexity is **moderate**. The codebase is well-structured, self-contained, and small in scope. The primary challenges are: replacing a custom Chef LWRP (`lineinfile`), migrating a Redis configuration workaround (a `ruby_block` hack), converting ERB templates to Jinja2, and safely externalising hardcoded credentials. No Chef Server, encrypted data bags, or Chef Vault usage is present — all state is local Chef Solo, which simplifies the transition significantly.

**Estimated migration timeline: 5–8 engineer-days** for a single experienced Ansible practitioner, or 2–3 days for a two-person team.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by 5 external community cookbooks whose functionality must be replicated with native Ansible modules or community roles.

---

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server provisioning with multi-site virtual host management, self-signed SSL certificate generation per vhost, HTTP-to-HTTPS redirect enforcement, hardened security headers (HSTS, X-Frame-Options, CSP, X-Content-Type-Options), rate limiting zones, and per-site static HTML content deployment for three subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`).
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features:
        - Four sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
        - ERB templates: `nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`
        - Static site files: three `index.html` files (test, ci, status) deployed via `cookbook_file`
        - Custom LWRP `lineinfile` resource (`resources/lineinfile.rb`) — a Ruby-based line-in-file editor with backup support
        - Attribute-driven vhost loop: iterates `node['nginx']['sites']` hash to create document roots, deploy content, generate SSL certs, and write vhost configs
        - Nginx security hardening: `server_tokens off`, buffer overflow protections, timeout tuning, TLS 1.2/1.3 only with strong cipher suites
        - UFW firewall: default-deny policy, explicit allow for SSH/HTTP/HTTPS
        - fail2ban: jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
        - sysctl hardening: IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable
        - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` on `sshd_config`
        - Depends on community cookbook `nginx ~> 12.0` (package install only — the local recipe overrides nginx.conf directly)

- **cache**:
    - Description: Dual caching layer provisioning — Memcached (via community cookbook) and Redis (via `redisio` community cookbook) with password authentication, custom log directory, and a post-install configuration fixup that strips deprecated Redis replica directives from the generated config file.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached ~> 6.0` community cookbook via `include_recipe 'memcached'`
        - Configures Redis server on port 6379 with `requirepass` set to a hardcoded password (`redis_secure_password_123`)
        - Creates `/var/log/redis` directory with `redis:redis` ownership
        - Delegates Redis installation to `redisio` community cookbook, then calls `redisio::enable`
        - Contains a `ruby_block "fix_redis_config"` hack that post-processes `/etc/redis/6379.conf` to remove five deprecated `replica-*` and `client-output-buffer-limit` directives that the `redisio` cookbook writes but the installed Redis version rejects
        - Depends on community cookbooks: `memcached ~> 6.0`, `redisio >= 0.0.0` (locked at 7.2.4); `redisio` itself depends on `selinux ~> 6.2.4`

- **fastapi-tutorial**:
    - Description: Full-stack Python FastAPI application deployment — installs system packages, clones the application from GitHub, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database with a dedicated user, writes a `.env` configuration file with hardcoded database credentials, creates and enables a systemd service unit running uvicorn, and starts the application on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features:
        - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone of `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch into `/opt/fastapi-tutorial`
        - Python venv at `/opt/fastapi-tutorial/venv` with `pip install -r requirements.txt`
        - PostgreSQL service enabled and started; database `fastapi_db` and user `fastapi` created via inline `psql` shell commands with `|| true` guards
        - Hardcoded credentials written to `/opt/fastapi-tutorial/.env`: `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`
        - Systemd unit `/etc/systemd/system/fastapi-tutorial.service` written inline: `ExecStart` runs uvicorn as `root` on `0.0.0.0:8000`
        - `systemctl daemon-reload` triggered via Chef notification on service file change
        - No external cookbook dependencies declared in `metadata.rb`

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all 3 local cookbook paths and 4 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`; `ssl_certificate ~> 2.1` is commented out). **Migration action**: retire entirely — replaced by `requirements.yml` for Ansible Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run-list, and version constraints. Mirrors Berksfile but also includes `ssl_certificate ~> 2.1` (uncommented). **Migration action**: retire — run-list order becomes Ansible playbook task order.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (including transitive deps `selinux 6.2.4`, `ssl_certificate 2.1.0`). **Migration action**: use locked versions as reference when selecting equivalent Ansible Galaxy roles or native module implementations.
- `solo.rb`: Chef Solo configuration — sets `file_cache_path`, `cookbook_path` (two paths: `/chef-repo/cookbooks` and a glob for vendored cookbooks), log level, and log destination. **Migration action**: retire — replaced by `ansible.cfg`.
- `solo.json`: Chef Solo node JSON — defines the run-list and all node attribute overrides (nginx sites with SSL paths, security settings for fail2ban/ufw/ssh). **Migration action**: content becomes Ansible `group_vars/all.yml` or role `defaults/main.yml` variables.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, forwarded ports 80→8080 and 443→8443, rsync of the repo to `/chef-repo`, and shell provisioner calling `vagrant-provision.sh`. **Migration action**: update to use `ansible_local` or `ansible` provisioner; replace shell provisioner with `ansible.playbook`.
- `vagrant-provision.sh`: Bootstrap shell script — runs `apt-get update`, installs `build-essential`, installs Chef via omnitruck, installs Berkshelf gem, runs `berks install && berks vendor`, then executes `chef-solo -c solo.rb -j solo.json`. **Migration action**: replace entirely with Ansible provisioner block in Vagrantfile; no equivalent script needed.

---

### Target Details

- **Operating System**: The `Vagrantfile` specifies `generic/fedora42` (Fedora Linux 42). `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `vagrant-provision.sh` script uses `apt-get`, which is Debian/Ubuntu-specific and would fail on Fedora — indicating the Vagrant box and the cookbook OS support declarations are misaligned. The actual runtime target is **Fedora 42** (RPM-based, `dnf`). Migration should target **Red Hat Enterprise Linux 9 / Fedora 42** and use the `ansible.builtin.dnf` module; package names will need verification against RPM equivalents (e.g., `libpq-dev` → `libpq-devel`, `ufw` is not available on Fedora — `firewalld` is the native alternative).
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured via `config.vm.provider "libvirt"` in the Vagrantfile with `lv.memory = 2048` and `lv.cpus = 2`.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present. This is a local development/test environment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1 — Chef Supermarket)**: The community cookbook is used only for the package install step; the local cookbook overrides `nginx.conf` directly via template. Replace with `ansible.builtin.package` (`nginx`) + Jinja2 templates for `nginx.conf` and `security.conf`. No Galaxy role required.
- **memcached (6.1.0 — Chef Supermarket)**: Handles full Memcached install and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service`. The community cookbook has no complex logic that requires a Galaxy role equivalent.
- **redisio (7.2.4 — Chef Supermarket)**: Manages Redis installation, config file generation, and service enablement. Replace with `ansible.builtin.package` (`redis`), `ansible.builtin.template` for `redis.conf`, and `ansible.builtin.service`. The `ruby_block` config-fixup hack (removing deprecated directives) becomes unnecessary if the Redis config is written directly via Ansible template rather than post-processed.
- **selinux (6.2.4 — Chef Supermarket)**: Transitive dependency of `redisio`; manages SELinux policy. On Fedora/RHEL targets, use `ansible.posix.selinux` or `ansible.builtin.command` with `setsebool`/`semanage` as needed. On Ubuntu targets, this is a no-op.
- **ssl_certificate (2.1.0 — Chef Supermarket)**: Present in `Policyfile.lock.json` but commented out in `Berksfile` and not called in any recipe. SSL cert generation is handled inline in `ssl.rb` via `openssl` shell commands. Replace with `ansible.builtin.command` running `openssl req -x509 ...` or the `community.crypto.x509_certificate` module for idempotent self-signed cert generation.

### Security Considerations

- **Hardcoded Redis password** (`cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`): Plaintext credential embedded directly in recipe code. **Migration action**: move to `ansible-vault`-encrypted variable (`vault_redis_password`); reference via `vars/main.yml` → `"{{ vault_redis_password }}"`.
- **Hardcoded PostgreSQL credentials** (`fastapi-tutorial/recipes/default.rb`): Database user password `fastapi_password` appears in two places — the `psql` CREATE USER command and the `.env` file content. **Migration action**: encrypt both with `ansible-vault`; use `community.postgresql.postgresql_user` module instead of raw shell `psql` commands; template the `.env` file with `ansible.builtin.template`.
- **`.env` file world-readable** (`mode '0644'`, owner `root`): The `.env` file containing `DATABASE_URL` with embedded credentials is written with mode `0644`, making it readable by all users on the system. **Migration action**: set mode to `0600` and assign ownership to the application service account (not `root`).
- **FastAPI service runs as root**: The systemd unit sets `User=root`. **Migration action**: create a dedicated `fastapi` system user and group; update `WorkingDirectory`, `ExecStart`, and file ownership accordingly.
- **Self-signed SSL certificates**: Generated via `openssl req -x509` with a 365-day validity and a hardcoded subject string (`/C=US/ST=Example/...`). Suitable for development only. **Migration action**: document that production deployments must replace with CA-signed certificates; use `community.crypto.x509_certificate` with `provider: selfsigned` for dev, parameterise the subject fields as variables.
- **SSH hardening via `sed`**: `security.rb` modifies `sshd_config` using `sed` shell commands — fragile and not idempotent if the file format changes. **Migration action**: use `ansible.builtin.lineinfile` (the native module, which directly replaces the custom `lineinfile` LWRP) with `regexp` and `line` parameters for `PermitRootLogin` and `PasswordAuthentication`.
- **UFW firewall**: UFW is a Debian/Ubuntu tool and is **not available on Fedora 42**. The `security.rb` recipe calls `ufw` commands directly. **Migration action**: replace with `ansible.posix.firewalld` for RPM-based targets; use `ansible.builtin.package` to install `firewalld` and `ansible.posix.firewalld` to manage zones and services. If Ubuntu support is retained, use a conditional (`when: ansible_os_family == "Debian"`) to branch between `ufw` and `firewalld`.
- **Credential count summary**:
  - `cache` cookbook: 1 hardcoded password (`redis_secure_password_123`)
  - `fastapi-tutorial` cookbook: 2 hardcoded credential occurrences (PostgreSQL user password in `psql` command + `DATABASE_URL` in `.env`)
  - `nginx-multisite` cookbook: 0 hardcoded credentials (SSL cert subject uses placeholder org data only)
  - **Total: 3 credential instances** requiring `ansible-vault` protection

### Technical Challenges

- **OS/package manager mismatch**: The Vagrantfile targets Fedora 42 (`dnf`/RPM) but `vagrant-provision.sh` calls `apt-get` (Debian/Ubuntu). Several package names differ between distros (`libpq-dev` vs `libpq-devel`, `python3-venv` may be `python3` on Fedora, `ufw` does not exist on Fedora). **Mitigation**: audit all package names against the Fedora 42 package index; use `ansible_pkg_mgr` or `ansible_os_family` facts to conditionally set package names, or standardise on a single target OS.
- **Custom `lineinfile` LWRP** (`nginx-multisite/resources/lineinfile.rb`): A hand-rolled Ruby resource that replicates `ansible.builtin.lineinfile` behaviour (match-and-replace with backup). **Mitigation**: replace all usages with the native `ansible.builtin.lineinfile` module — direct 1:1 mapping with `regexp`, `line`, and `backup` parameters. No custom logic needs to be ported.
- **Redis config post-processing hack** (`cache/recipes/default.rb`, `ruby_block "fix_redis_config"`): The `redisio` cookbook generates a Redis config containing deprecated directives that cause the Redis daemon to fail. The hack strips them with `gsub!`. **Mitigation**: since Ansible will write the Redis config directly via `ansible.builtin.template`, the deprecated directives are simply never written — the hack becomes obsolete. Ensure the Jinja2 template for `redis.conf` omits `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`.
- **ERB → Jinja2 template conversion**: Five ERB templates use `<%= @variable %>` and `<% if @condition %>` syntax. **Mitigation**: convert to Jinja2 (`{{ variable }}` / `{% if condition %}`). The `site.conf.erb` template has a structural quirk — the `<% if @ssl_enabled %>` block closes the first `server {}` block and opens a second one, meaning the template produces either one or two server blocks depending on the flag. This conditional structure must be carefully reproduced in Jinja2.
- **Attribute-driven vhost loop**: The `nginx.rb` and `sites.rb` recipes iterate over `node['nginx']['sites']` hash to create directories, deploy files, generate certs, and write vhost configs. **Mitigation**: represent the sites as a YAML list of dicts in `group_vars/all.yml` and use `ansible.builtin.loop` (or `with_items`) in tasks. The document root path discrepancy between `attributes/default.rb` (`/opt/server/<site>`) and `solo.json` (`/var/www/<site>`) must be resolved — `solo.json` overrides take precedence at runtime, so `/var/www/<site>` is the effective value.
- **Git-based application deployment**: `fastapi-tutorial` clones from a public GitHub repo at the `main` branch with `action :sync`. **Mitigation**: use `ansible.builtin.git` with `update: yes` and `version: main`. Consider pinning to a specific commit SHA for reproducibility in production.
- **PostgreSQL provisioning via raw shell**: Database and user creation uses `sudo -u postgres psql -c "..."` with `|| true` error suppression. **Mitigation**: use `community.postgresql.postgresql_db` and `community.postgresql.postgresql_user` modules for idempotent, declarative database provisioning. Requires `psycopg2` Python library on the target host (`python3-psycopg2` package).
- **`ssl_certificate` cookbook discrepancy**: The cookbook is locked in `Policyfile.lock.json` (version 2.1.0) but commented out in `Berksfile` and never called in any recipe. **Mitigation**: ignore — no migration action required. Document as dead dependency.

### Migration Order

The following order minimises risk by establishing foundational services before dependent ones:

1. **`nginx-multisite` → security sub-role** (low risk, self-contained): Migrate `security.rb` first — UFW/firewalld, fail2ban, sysctl hardening, and SSH config. These have no dependencies on other cookbooks and establish the security baseline. Validates `ansible.builtin.lineinfile`, `ansible.posix.firewalld`, `ansible.builtin.sysctl`, and `ansible.builtin.template` usage.
2. **`nginx-multisite` → nginx sub-role** (low-moderate risk): Migrate `nginx.rb`, `ssl.rb`, and `sites.rb` together as a single Ansible role (`nginx_multisite`). Validates Jinja2 template conversion, vhost loop logic, `community.crypto.x509_certificate` for SSL, and `ansible.builtin.copy` for static site files.
3. **`cache` → memcached sub-role** (low risk): Simple package + service, no configuration templating required. Validates `ansible.builtin.package` and `ansible.builtin.service` on the target OS.
4. **`cache` → redis sub-role** (moderate risk): Redis config templating, password variable vaulting, and elimination of the config-fixup hack. Validates `ansible-vault` workflow and `ansible.builtin.template` for Redis config.
5. **`fastapi-tutorial` role** (highest risk): Most complex — involves git clone, Python venv, pip install, PostgreSQL provisioning, `.env` file with vaulted credentials, and systemd service. Migrate last after all supporting services are confirmed working. Validates `ansible.builtin.git`, `ansible.builtin.pip`, `community.postgresql.*` modules, and `ansible.builtin.systemd`.

### Assumptions

1. **Target OS is Fedora 42 (RPM/dnf)** based on the Vagrantfile `generic/fedora42` box, despite `vagrant-provision.sh` using `apt-get` and `metadata.rb` declaring Ubuntu/CentOS support. The migration plan assumes Fedora 42 as the primary target; all package names and firewall tooling are chosen accordingly. If Ubuntu is also a required target, conditional task blocks per `ansible_os_family` will be needed.
2. **Chef Solo (no Chef Server)**: The entire stack runs via `chef-solo` with a local `solo.json` node file. There is no Chef Server, no encrypted data bags, no Chef Vault, and no node search functionality to replicate. All configuration is attribute-driven from local files.
3. **Development/test environment only**: Self-signed certificates, hardcoded passwords, a service running as `root`, and `|| true` guards on database creation all indicate this is not a production-grade deployment. The Ansible migration should introduce production-readiness improvements (dedicated service user, vaulted secrets, cert parameterisation) as part of the migration rather than faithfully replicating insecure patterns.
4. **`ssl_certificate` community cookbook is unused**: It appears in `Policyfile.lock.json` as a locked dependency but is commented out in `Berksfile` and never referenced in any recipe. It is assumed to be a leftover from an earlier iteration and requires no migration action.
5. **The `nginx` community cookbook is used only for package installation**: The local `nginx-multisite` cookbook overrides `nginx.conf` entirely via its own template. The community cookbook's service management, config generation, and site management features are not used. The Ansible equivalent is a plain `ansible.builtin.package` task.
6. **Document root path is `/var/www/<site>`**: `solo.json` overrides the `attributes/default.rb` defaults (`/opt/server/<site>`) with `/var/www/<site>`. Since `solo.json` node attributes take precedence over cookbook defaults in Chef Solo, the effective document roots are `/var/www/test.cluster.local`, `/var/www/ci.cluster.local`, and `/var/www/status.cluster.local`. The Ansible role variables should use the `solo.json` values.
7. **`www-data` user exists on the target**: `nginx.rb` sets `owner 'www-data'` on document root directories. On Fedora, Nginx runs as `nginx` user by default, not `www-data`. The Ansible role should use `nginx` as the web server user on RPM-based systems, or parameterise it via a variable.
8. **No CI/CD pipeline integration is required**: The repository is provisioned manually via `vagrant up`. The Ansible migration plan does not assume integration with any CI/CD system, though the `ci.cluster.local` vhost name suggests one may be intended in future.
9. **The FastAPI application source is publicly accessible**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git` without authentication. It is assumed this repository remains public and accessible from the target host during provisioning.
10. **`psycopg2` will be available**: The `community.postgresql` Ansible collection requires the `psycopg2` Python library on the managed host. It is assumed this can be installed via `python3-psycopg2` (Fedora) or `python3-psycopg2` (Ubuntu) as a pre-task before PostgreSQL provisioning tasks run.
11. **Berkshelf vendoring is not replicated**: The `vagrant-provision.sh` runs `berks vendor cookbooks` to download external cookbooks into the local `cookbooks/` directory. In Ansible, external role dependencies are declared in `requirements.yml` and installed via `ansible-galaxy install -r requirements.yml`. The `cookbooks/` directory structure has no Ansible equivalent.
12. **The `lineinfile` custom LWRP has no callers in the current codebase**: A search of all recipe files shows the `lineinfile` resource defined in `resources/lineinfile.rb` is not explicitly called by any recipe in this repository (SSH hardening uses `sed` via `execute` instead). It is assumed the resource was created for future use or is called by an external cookbook. No migration of call sites is required beyond replacing the resource definition with `ansible.builtin.lineinfile`.
