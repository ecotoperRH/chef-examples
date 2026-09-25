# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a multi-site Nginx web server with caching services and a FastAPI application backend. The stack is currently exercised via Vagrant (libvirt provider, Fedora 42 guest) and driven by `chef-solo` with a Policyfile/Berkshelf dependency model.

The migration scope covers **3 local cookbooks** and **5 external Supermarket cookbook dependencies**, translating into approximately **4–5 Ansible roles** plus a top-level playbook. The overall complexity is **moderate**: the logic is well-structured, the cookbook count is small, and there are no Chef Server, encrypted data bags, or complex LWRP chains. The primary challenges are the Redis config post-processing hack, the self-signed SSL certificate generation workflow, and the replacement of community Supermarket cookbooks (nginx, memcached, redisio) with Ansible equivalents.

**Estimated migration timeline: 2–3 weeks** for a single engineer, including testing in the existing Vagrant environment.

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** (local) that need individual migration planning, backed by 5 locked external cookbook dependencies.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads.

---

- **nginx-multisite**
  - **Description**: Core Nginx web server cookbook that provisions a hardened, multi-site Nginx installation with SSL termination, per-site virtual host configuration, firewall hardening, SSH hardening, and intrusion prevention. Orchestrates four sub-recipes: `security`, `nginx`, `ssl`, and `sites`.
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef
  - **Key Features**:
    - Installs and configures Nginx with a custom `nginx.conf.erb` template (gzip, keepalive, mime types)
    - Generates per-site virtual host configs from `site.conf.erb` (HTTP→HTTPS redirect, TLS 1.2/1.3, HSTS, CSP, X-Frame-Options, X-Content-Type-Options)
    - Generates self-signed RSA-2048 certificates via `openssl req -x509` for three subdomains: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
    - Deploys static `index.html` files per site from `files/default/{ci,status,test}/`
    - Configures UFW firewall (default deny, allow SSH/HTTP/HTTPS) via idempotent shell commands
    - Configures fail2ban with `jail.local.erb` covering sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch jails
    - Hardens SSH daemon (disables root login, disables password authentication)
    - Applies kernel-level network security via `sysctl-security.conf.erb` (IP spoofing protection, ICMP redirect blocking, SYN flood protection, IPv6 disable)
    - Includes a custom `lineinfile` LWRP resource (`resources/lineinfile.rb`)

- **cache**
  - **Description**: Caching layer cookbook that installs and configures both Memcached and Redis on the same host, delegating to the community `memcached` (~> 6.0) and `redisio` (7.2.4) Supermarket cookbooks. Includes a post-install Ruby block hack to strip incompatible Redis config directives from `/etc/redis/6379.conf`.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef
  - **Key Features**:
    - Installs Memcached via the community `memcached` cookbook
    - Installs Redis on port 6379 with password authentication (`requirepass redis_secure_password_123` — hardcoded plaintext credential)
    - Creates `/var/log/redis` directory with correct ownership
    - Post-install `ruby_block` that surgically removes deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) to work around `redisio` 7.2.4 generating config incompatible with the installed Redis version
    - Enables Redis via `redisio::enable`

- **fastapi-tutorial**
  - **Description**: Application deployment cookbook that clones a FastAPI Python application from GitHub, sets up a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database with a dedicated user, writes a `.env` configuration file with database credentials, and registers the application as a systemd service running under uvicorn.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef
  - **Key Features**:
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial`
    - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs from `requirements.txt`
    - Enables and starts the `postgresql` service
    - Creates PostgreSQL user `fastapi` with password `fastapi_password` (hardcoded plaintext) and database `fastapi_db`
    - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plaintext credential in file, mode 0644)
    - Creates and enables a systemd unit `fastapi-tutorial.service` running uvicorn on `0.0.0.0:8000` as `root` (privilege concern)
    - Triggers `systemctl daemon-reload` via Chef notification on service file change

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all local and Supermarket cookbook sources. Maps directly to an Ansible `requirements.yml` for Galaxy roles. The commented-out `ssl_certificate` entry indicates an abandoned dependency.
- `Policyfile.rb`: Chef Policyfile defining the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and version constraints. Defines the execution order that must be preserved in the Ansible playbook's role/task ordering.
- `Policyfile.lock.json`: Locked dependency graph with exact versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. Confirms `selinux` is a transitive dependency of `redisio`. Useful as a reference for pinning Ansible Galaxy role versions.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No direct Ansible equivalent needed; replaced by inventory and `ansible.cfg`.
- `solo.json`: Chef Solo node JSON providing attribute overrides for site definitions (document roots, SSL flags), SSL paths, and security settings (fail2ban, UFW, SSH hardening). This becomes the Ansible **host_vars** or **group_vars** file.
- `Vagrantfile`: Vagrant configuration for a Fedora 42 libvirt VM (`generic/fedora42`, 2 vCPU, 2 GB RAM, private IP `192.168.121.10`, ports 80→8080 and 443→8443). Provisions via `vagrant-provision.sh`. Reusable as-is for Ansible testing by replacing the Chef provisioner block with `ansible_local` or `ansible` provisioner.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. In the Ansible world this is replaced by the Vagrant `ansible` provisioner or a simple `ansible-playbook` call; the `apt-get update` and `build-essential` steps may need to be retained as a pre-task.
- `x2a-rules/cbbb21c1-fa2c-417e-a1d6-42b822782fbd.md`: Internal migration rule noting that a GitHub Actions CI pipeline should be created for each Ansible project. This is a project-specific requirement to implement during migration.
- `project-plan.md`: Project planning document (not read; likely contains human-readable notes about the project scope).

---

### Target Details

- **Operating System**: Ubuntu 18.04+ or CentOS 7+ per `metadata.rb` `supports` declarations. The Vagrant development environment uses **Fedora 42** (`generic/fedora42`), which implies the Ansible roles must handle both Debian/Ubuntu (apt, `www-data` user, UFW) and RHEL/CentOS/Fedora (dnf/yum, `nginx` user, firewalld) package managers. The `vagrant-provision.sh` script calls `apt-get`, suggesting the primary target is **Ubuntu**. Default to **Ubuntu 22.04 LTS** for production unless otherwise specified.
- **Virtual Machine Technology**: **libvirt/KVM** — confirmed by `config.vm.provider "libvirt"` in the Vagrantfile. No cloud-specific tooling detected.
- **Cloud Platform**: Not specified. No AWS, Azure, or GCP SDK references found in any file.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Community Supermarket cookbook wrapping Nginx installation and base configuration. Replace with the `ansible.builtin.package` module (`nginx`) plus Jinja2 templates for `nginx.conf` (already available as `nginx.conf.erb`). Alternatively use the `nginxinc.nginx` Ansible Galaxy role.
- **memcached (6.1.0)** — Community cookbook for Memcached installation and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service` tasks. No complex configuration is applied beyond defaults in this repo.
- **redisio (7.2.4)** — Community cookbook for Redis installation with per-instance configuration. Replace with `ansible.builtin.package` (redis-server) + `ansible.builtin.template` for `/etc/redis/6379.conf`. The post-install config-stripping hack in `cache::default` must be replicated as an `ansible.builtin.lineinfile` (with `state: absent` + regexp) or by generating a clean template that never emits the deprecated directives — the template approach is strongly preferred.
- **ssl_certificate (2.1.0)** — Locked in `Policyfile.lock.json` but commented out in `Berksfile` and unused in any recipe. No migration action required; confirm and discard.
- **selinux (6.2.4)** — Transitive dependency of `redisio`; manages SELinux policy for Redis on RHEL-family systems. Replace with `ansible.posix.selinux` or `community.general.selinux_permissive` tasks, scoped to RHEL/Fedora hosts via `when: ansible_os_family == "RedHat"`.

---

### Security Considerations

- **Hardcoded Redis password**: `cache::default.rb` sets `requirepass redis_secure_password_123` directly in the recipe source. In Ansible, this must be moved to **Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable (e.g., `{{ redis_requirepass }}`).
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial::default.rb` embeds `fastapi_password` in both the `psql` provisioning commands and the `.env` file written to disk at mode `0644`. In Ansible: store the password in Vault, use `community.postgresql.postgresql_user` with `password: "{{ fastapi_db_password }}"`, tighten the `.env` file permissions to `0600`, and change ownership away from root.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant privilege escalation risk. The Ansible role should create a dedicated `fastapi` system user and update the unit accordingly.
- **Self-signed SSL certificates**: The `ssl::` recipe generates self-signed certificates at provision time using `openssl req -x509`. These are appropriate only for development/staging. The Ansible migration should introduce a variable flag (e.g., `nginx_ssl_self_signed: true`) to gate this behavior, with a production path that expects certificates to be provided via Vault or an external PKI (e.g., Let's Encrypt via `community.crypto.acme_certificate`).
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` in `security.rb`. In Ansible, use `ansible.builtin.lineinfile` or `ansible.builtin.template` for `/etc/ssh/sshd_config` with a handler to restart `sshd`. Ensure the Ansible control connection uses key-based auth before applying this change to avoid lockout.
- **UFW firewall rules**: Applied via raw `execute` blocks with `not_if` guards. Replace with `community.general.ufw` module tasks, which are idempotent by design.
- **Fail2ban configuration**: Deployed via ERB template. Translate `fail2ban.jail.local.erb` to a Jinja2 template (`jail.local.j2`) with equivalent variable substitution. No secrets involved.
- **Kernel sysctl hardening**: `sysctl-security.conf.erb` disables IPv6 globally and applies network hardening parameters. Translate to `ansible.posix.sysctl` tasks or deploy the file via `ansible.builtin.template` with a handler calling `sysctl -p`.
- **`.env` file on disk**: `/opt/fastapi-tutorial/.env` contains `DATABASE_URL` with embedded credentials written at mode `0644`. Must be tightened to `0600` and the password sourced from Vault.

---

### Technical Challenges

- **Redis config post-processing hack**: The `ruby_block "fix_redis_config"` in `cache::default.rb` strips deprecated directives from the generated Redis config after `redisio` writes it. This is a workaround for a community cookbook generating config incompatible with the installed Redis version. In Ansible, the correct fix is to write the Redis config directly from a clean Jinja2 template, bypassing the need for post-processing entirely. The template must be validated against the Redis version available on the target OS.
- **Chef LWRP `lineinfile` resource**: `nginx-multisite` ships a custom `resources/lineinfile.rb` LWRP. Its usage within the cookbook's recipes must be audited to determine if it is actually called (it does not appear in the recipes reviewed). If unused, discard it. If used, replace with `ansible.builtin.lineinfile`.
- **Dual OS support (Ubuntu + CentOS/Fedora)**: `metadata.rb` declares support for both Ubuntu ≥ 18.04 and CentOS ≥ 7, but `vagrant-provision.sh` uses `apt-get` and the Vagrantfile targets Fedora 42. Ansible roles must use `ansible_os_family` / `ansible_distribution` conditionals or a vars file per OS family to handle package names (`ufw` vs `firewalld`), service names (`ssh` vs `sshd`), and user names (`www-data` vs `nginx`).
- **Vagrant provisioner replacement**: The current `vagrant-provision.sh` bootstraps Chef and Berkshelf before running `chef-solo`. For Ansible, the Vagrantfile should be updated to use the `ansible` or `ansible_local` provisioner, pointing at the new playbook. The `apt-get update` and `build-essential` pre-steps should become Ansible pre-tasks.
- **Run list ordering**: The Policyfile run list (`nginx-multisite` → `cache` → `fastapi-tutorial`) encodes an implicit dependency order. The Ansible playbook must preserve this: security/nginx first, then caching services, then the application. The FastAPI app depends on PostgreSQL being running, and Nginx must be configured before the app service starts (for reverse proxy, if applicable).
- **GitHub Actions CI pipeline**: The `x2a-rules` file specifies that a GitHub Actions workflow must be created for each Ansible project. This is an additional deliverable beyond the role/playbook migration itself.
- **`ssl_certificate` cookbook ambiguity**: The cookbook is commented out in `Berksfile` but present and locked in `Policyfile.lock.json`. Its role in the current setup is unclear. Confirm with the team whether it was intentionally removed or is still needed before finalizing the Ansible SSL strategy.

---

### Migration Order

1. **nginx-multisite** (security sub-role first, then nginx, ssl, sites) — This is the foundational role. Migrating it first establishes the Ansible role structure, Jinja2 template patterns, and handler conventions that the other roles will follow. The security hardening tasks (UFW, fail2ban, sysctl, SSH) are self-contained and low-risk to migrate independently.
2. **cache** — Moderate complexity due to the Redis config hack. Migrate Memcached first (trivial: install + service), then Redis with a clean Jinja2 template that eliminates the post-processing workaround. Validate Redis connectivity before proceeding.
3. **fastapi-tutorial** — Highest complexity and most security remediation required (hardcoded credentials, root service user, plaintext `.env`). Depends on PostgreSQL (installed within this cookbook) and should be migrated last. Vault integration for credentials must be completed before this role is production-ready.

---

### Assumptions

1. **Target OS for production is Ubuntu** (likely 22.04 LTS), inferred from `apt-get` usage in `vagrant-provision.sh` and `www-data` user references in `nginx.rb`. CentOS/Fedora support declared in `metadata.rb` may be aspirational rather than actively tested.
2. **The Vagrant environment (Fedora 42 / libvirt) is the development/testing environment only** and is not representative of the production target OS. Ansible roles should be tested against Ubuntu in CI.
3. **Self-signed certificates are acceptable for development** but the production SSL strategy (Let's Encrypt, internal CA, or externally managed certificates) has not been defined. A variable-gated approach is assumed.
4. **The `ssl_certificate` Supermarket cookbook is not actively used** — it is commented out in `Berksfile` and no recipe calls it. It will be excluded from the Ansible migration unless confirmed otherwise.
5. **The custom `lineinfile` LWRP** in `resources/lineinfile.rb` does not appear to be called by any recipe in the reviewed files. It is assumed to be dead code and will be discarded unless confirmed otherwise.
6. **No Chef Server, encrypted data bags, or Chef Vault** are in use. This is a pure `chef-solo` setup, which simplifies secrets migration — there is no Chef-side secrets store to extract from.
7. **The GitHub repository `https://github.com/dibanez/fastapi_tutorial.git`** is publicly accessible and the `main` branch is stable. If this is a private repository, SSH key or token management will need to be addressed in the Ansible role (e.g., `ansible.builtin.git` with `key_file` or token-based HTTPS URL).
8. **Redis and Memcached run on the same host** as Nginx and the FastAPI application. This is a single-node topology. The Ansible inventory will reflect a single host group unless the team intends to split services across nodes during migration.
9. **The `project-plan.md` file** does not contain machine-readable configuration and is assumed to be human documentation only; it has not been read and is not expected to affect the migration plan.
10. **The `x2a-rules` GitHub Actions requirement** is interpreted as: one GitHub Actions workflow file per Ansible role repository (or per playbook, if roles are co-located). The exact workflow structure is not defined in the rule file and must be agreed upon with the team.
11. **No reverse proxy configuration** exists between Nginx and the FastAPI uvicorn process (port 8000). The current setup serves them independently. If Nginx is intended to proxy to FastAPI, an additional `location /api` block will need to be added to `site.conf.j2` during migration.
12. **Memcached requires no authentication** in the current setup (the `memcached` cookbook is included with defaults). This is assumed to be intentional for an internal-only service.
