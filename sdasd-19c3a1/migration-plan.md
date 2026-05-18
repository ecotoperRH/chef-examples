# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, dual caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The policy is named `nginx-multisite-policy` and is executed via `chef-solo` inside a Vagrant-managed libvirt VM running **Fedora 42**.

The migration encompasses **3 local cookbooks** and **5 external Supermarket cookbook dependencies**, all of which have well-established Ansible equivalents. The cookbooks follow clean, single-responsibility patterns with minimal cross-cookbook coupling, making this an excellent candidate for a phased, incremental migration.

**Estimated migration effort: 3–4 weeks** for a complete, tested Ansible implementation including role authoring, variable extraction, Vault integration, and functional validation against the same Vagrant target.

**Complexity rating: Medium** — The logic is straightforward, but several areas require careful attention: a hardcoded Redis password, self-signed certificate generation via raw `openssl` shell commands, a `ruby_block` config-patching hack in the cache cookbook, a custom `lineinfile` LWRP, and cross-platform (Debian/RHEL) compatibility declared in metadata but only partially exercised.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening (UFW firewall, fail2ban intrusion prevention, kernel sysctl tuning), and self-signed TLS certificate generation for three internal cluster subdomains
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Installs and configures Nginx with a custom `nginx.conf` (gzip, keepalive, logging)
        - Deploys a `security.conf` snippet enforcing rate-limiting zones, buffer limits, TLS 1.2/1.3-only cipher suites, and `server_tokens off`
        - Iterates over a node attribute hash (`node['nginx']['sites']`) to create per-site document roots, deploy static `index.html` files from cookbook files, generate `sites-available` virtual host configs from `site.conf.erb`, and symlink them into `sites-enabled`
        - Each virtual host enforces HTTP→HTTPS redirect, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy)
        - Generates self-signed RSA-2048 / 365-day certificates via `openssl req -x509` for each SSL-enabled site; stores certs in `/etc/ssl/certs` and keys in `/etc/ssl/private` (mode `0710`, group `ssl-cert`)
        - Installs and configures `fail2ban` with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` (bantime 3600 s, maxretry 2–10 depending on jail)
        - Configures UFW: default-deny, allow SSH/HTTP/HTTPS, then enables the firewall
        - Hardens SSH daemon: `PermitRootLogin no`, `PasswordAuthentication no`
        - Applies a comprehensive `sysctl` security profile (rp_filter, ICMP redirect suppression, source-route blocking, martian logging, SYN-cookie flood protection, IPv6 disable)
        - Provides a custom `lineinfile` LWRP (resource `cookbooks/nginx-multisite/resources/lineinfile.rb`) that replicates Ansible's `lineinfile` module behaviour including regex-match replacement and timestamped backup files
        - Three static site content files: `ci/index.html` (CI/CD dashboard), `status/index.html` (system status page), `test/index.html` (test environment landing page)
        - Default sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` — all SSL-enabled, document roots under `/opt/server/{test,ci,status}`; overridden in `solo.json` to `/var/www/{site}`

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the upstream `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication, custom log directory, and a post-install config-patching workaround
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached` community cookbook (version 6.1.0)
        - Configures a single Redis instance on port 6379 with `requirepass redis_secure_password_123` via `node['redisio']['servers']` attribute override
        - Creates `/var/log/redis` directory owned by the `redis` user
        - Delegates Redis installation and service enablement to `redisio` (version 7.2.4) and `redisio::enable`
        - Contains a `ruby_block "fix_redis_config"` hack that post-processes `/etc/redis/6379.conf` to strip out deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that cause the installed `redisio` version to fail on newer Redis binaries

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, with a Python virtual environment, pip dependency installation, PostgreSQL database and user provisioning, a `.env` configuration file containing the database URL, and a systemd unit for process supervision
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using the Chef `git` resource (`:sync` action)
        - Creates a Python venv at `/opt/fastapi-tutorial/venv` and installs `requirements.txt` via pip
        - Enables and starts the `postgresql` service
        - Provisions PostgreSQL role `fastapi` with password `fastapi_password`, database `fastapi_db`, and full privileges — executed via `sudo -u postgres psql` shell commands with `|| true` guards
        - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (world-readable, mode `0644`)
        - Writes a systemd unit `/etc/systemd/system/fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as `root`, with `After=postgresql.service`
        - Runs `systemctl daemon-reload` and enables/starts the `fastapi-tutorial` service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but present and locked in `Policyfile.rb`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Fully resolved and pinned dependency graph. Locks: `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4` (transitive dep of redisio), `ssl_certificate 2.1.0`. This file is the authoritative source of truth for dependency versions.
- `solo.json`: Chef Solo node JSON providing the run list and attribute overrides. Overrides document roots to `/var/www/{site}` (differing from cookbook attribute defaults of `/opt/server/{site}`), sets SSL cert/key paths, and enables all security features (`fail2ban`, `ufw`, SSH root-disable, password-auth-disable).
- `solo.rb`: Chef Solo configuration pointing `file_cache_path` to `/var/chef-solo` and `cookbook_path` to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks`.
- `Vagrantfile`: Vagrant configuration targeting `generic/fedora42` box, hostname `chef-nginx`, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, libvirt provider (2 vCPU, 2 GB RAM), rsync-based folder sync of the repo to `/chef-repo`, and shell provisioner invoking `vagrant-provision.sh`.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef-embedded gem, runs `berks install && berks vendor cookbooks` to resolve dependencies, then executes `chef-solo -c solo.rb -j solo.json`.

---

### Target Details

- **Operating System**: Fedora 42 (primary runtime target per `Vagrantfile`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, but the provisioning script uses `apt-get` (Debian/Ubuntu package manager), indicating the Vagrant box may actually be Debian-family despite the `generic/fedora42` box name, or the script is partially incorrect. The `ufw` firewall tool is Debian/Ubuntu-native and is not available on Fedora/RHEL by default. **Ansible playbooks must account for this ambiguity.**
- **Virtual Machine Technology**: libvirt / KVM (explicitly configured in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references are present. Designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install the distro-provided nginx package, combined with `ansible.builtin.template` for `nginx.conf` and `security.conf`, and `ansible.builtin.file` for site symlinks. Consider the community `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role as a drop-in accelerator.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service` (enable/start). The `geerlingguy.memcached` Galaxy role covers this fully.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `redis`) and `ansible.builtin.template` for `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`). The `geerlingguy.redis` Galaxy role is a suitable replacement. The config-patching `ruby_block` hack must be replaced with explicit Ansible `lineinfile` or `template` tasks that never write the deprecated directives in the first place.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection. This provides idempotent, declarative certificate management without shelling out to `openssl`.
- **selinux (6.2.4, Chef Supermarket — transitive)**: Replace with `ansible.posix.selinux` module if the target is RHEL/Fedora. On Ubuntu targets this dependency is irrelevant.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`): This credential is committed in plaintext to the repository. It must be extracted into an **Ansible Vault**-encrypted variable (`vault_redis_password`) before migration. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written verbatim into `/opt/fastapi-tutorial/.env`): Two occurrences of the same plaintext password in source code. Must be moved to Ansible Vault (`vault_postgres_fastapi_password`). The `.env` file must be templated with mode `0600` and owned by the application service user (not `root`). **1 credential detected (used in 2 places).**
- **Self-signed TLS certificates**: The `ssl.rb` recipe generates certificates via a raw `openssl req -x509` shell command with a hardcoded subject string (`/C=US/ST=Example/...`). In Ansible, replace with `community.crypto` collection tasks. For production, integrate with a CA or Let's Encrypt (`community.crypto.acme_certificate`). Certificate subject fields should be parameterised as variables.
- **SSH hardening** (`PermitRootLogin no`, `PasswordAuthentication no`): Currently applied via `sed` shell commands. Replace with the `ansible.builtin.lineinfile` module targeting `/etc/ssh/sshd_config`, with a handler to restart `sshd`. Consider using the `devsec.hardening.ssh_hardening` Galaxy role for a more comprehensive baseline.
- **UFW firewall rules**: UFW is Debian/Ubuntu-specific. Use the `community.general.ufw` module on Ubuntu targets. On Fedora/RHEL targets, replace with `ansible.posix.firewalld`. The migration must resolve the OS-family ambiguity (see Target Details) before choosing the correct firewall module.
- **fail2ban configuration**: The `jail.local` template is fully static (no Chef variables are interpolated). It can be migrated as a verbatim `ansible.builtin.copy` task or a minimal `ansible.builtin.template`. The `geerlingguy.security` or `oefenweb.fail2ban` Galaxy role can manage the full lifecycle.
- **sysctl kernel hardening**: Replace the `sysctl-security.conf.erb` template deployment and `sysctl -p` execute resource with `ansible.posix.sysctl` module tasks, one per parameter, for full idempotency. Alternatively, deploy the file with `ansible.builtin.template` and notify a handler running `sysctl --system`.
- **FastAPI `.env` file permissions**: Currently written as mode `0644` owned by `root`. This exposes the database password to all local users. In Ansible, set mode to `0600` and run the application as a dedicated non-root service account.
- **FastAPI systemd service running as root**: The unit file sets `User=root`. This is a significant security risk. The Ansible migration should create a dedicated `fastapi` system user and update the service unit accordingly.
- **Vault/Secrets summary**:
  - `vault_redis_password` — Redis `requirepass` value (currently `redis_secure_password_123`)
  - `vault_postgres_fastapi_password` — PostgreSQL role password and `DATABASE_URL` credential (currently `fastapi_password`)
  - Total: **2 secrets** requiring Ansible Vault protection

---

### Technical Challenges

- **OS-family ambiguity**: The `Vagrantfile` specifies `generic/fedora42` (RPM-based), but `vagrant-provision.sh` calls `apt-get update` and `apt-get install` (Debian/Ubuntu package manager). The `ufw` firewall is also Debian-native. This contradiction must be resolved before writing Ansible tasks. If the actual target is Ubuntu/Debian, the `ansible_os_family == "Debian"` branch applies throughout; if Fedora/RHEL, `dnf`/`firewalld`/`selinux` must be used instead. Ansible's `when: ansible_os_family == "..."` conditionals can handle both, but the primary target must be confirmed.
- **`ruby_block` Redis config patch**: The `fix_redis_config` block in `cache/recipes/default.rb` strips deprecated Redis directives from the generated config file after `redisio` writes it. This is a workaround for an incompatibility between the `redisio` cookbook and the installed Redis version. In Ansible, this hack is unnecessary: write the Redis configuration template directly without the deprecated keys, bypassing the need for post-processing entirely.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook ships its own `lineinfile` resource (`resources/lineinfile.rb`) that mimics Ansible's built-in `lineinfile` module. This resource does not appear to be called anywhere in the current recipes (no `lineinfile` resource calls were found in the recipe files), suggesting it may be dead code or intended for future use. It can be dropped entirely in the Ansible migration since `ansible.builtin.lineinfile` is natively available.
- **Attribute precedence and `solo.json` overrides**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{site}`, but `solo.json` overrides them to `/var/www/{site}`. Ansible does not have a Chef-style attribute precedence system. The correct values must be determined and set as a single source of truth in Ansible group/host vars, with the `solo.json` values taking precedence as the intended runtime configuration.
- **Dynamic site loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, deploy files, and render templates. In Ansible, this maps to `loop:` over a `nginx_sites` list variable. The loop logic is straightforward but requires careful variable structure design to preserve all per-site attributes (`document_root`, `ssl_enabled`, `cert_file`, `key_file`).
- **Git-based application deployment**: The `fastapi-tutorial` cookbook uses Chef's `git` resource with `:sync` action. The Ansible equivalent is `ansible.builtin.git` with `update: yes`. Care must be taken to handle the case where local modifications exist (the Chef resource's `working_tree_clean: false` SCM state noted in `Policyfile.lock.json` suggests the working tree may be dirty).
- **PostgreSQL provisioning via shell**: Database and user creation is done with raw `psql` shell commands and `|| true` error suppression. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` Ansible collection for proper idempotency.
- **`ssl_certificate` cookbook in lock but commented in Berksfile**: `ssl_certificate 2.1.0` is present in `Policyfile.lock.json` and `Policyfile.rb` but commented out in `Berksfile`. It is not directly called in any recipe. Its presence in the lock file may be a leftover. Verify whether any template or resource implicitly depends on it before discarding.
- **Service user for Nginx**: The `nginx.conf.erb` template sets `user www-data`, which is the Debian/Ubuntu Nginx user. On Fedora/RHEL the Nginx process user is `nginx`. This must be parameterised in the Ansible template.

---

### Migration Order

The following order minimises risk by starting with the most self-contained cookbook and ending with the one that has the most external dependencies and security concerns:

1. **`cache` cookbook** — Lowest complexity; no templates, no custom resources, no cross-cookbook calls beyond delegating to community cookbooks. Migrating this first validates the Ansible Redis and Memcached role patterns and forces early resolution of the Redis password Vault secret. Estimated effort: **3–4 days**.

2. **`nginx-multisite` cookbook** — Medium complexity; the largest cookbook with 5 recipes, 5 templates, 3 static files, and a custom LWRP. Migrating this second establishes the core Ansible role structure, the site-loop variable pattern, the SSL certificate generation tasks, and the security hardening tasks (UFW/firewalld, fail2ban, sysctl, SSH). The OS-family ambiguity must be resolved before this step. Estimated effort: **1–1.5 weeks**.

3. **`fastapi-tutorial` cookbook** — Highest complexity due to: external Git dependency, Python venv management, PostgreSQL provisioning, systemd unit authoring, and two plaintext secrets requiring Vault. Should be migrated last after the security patterns established in step 2 are in place. Estimated effort: **1 week**.

---

### Assumptions

1. **Primary target OS is Ubuntu/Debian**, not Fedora, based on the use of `apt-get` in `vagrant-provision.sh` and the presence of `ufw` and `www-data` user references. The `generic/fedora42` Vagrant box name may be incorrect or the box may be a Fedora box used with an incorrect provisioning script. This must be confirmed with the team before writing any Ansible tasks.
2. **Self-signed certificates are acceptable for all target environments** covered by this repository. If any environment is production-facing, a CA-signed or Let's Encrypt certificate workflow must be designed separately.
3. **The FastAPI GitHub repository** (`https://github.com/dibanez/fastapi_tutorial.git`) will remain publicly accessible and the `main` branch will remain stable during and after migration.
4. **Redis does not require clustering or Sentinel**; a single-instance configuration with password authentication is sufficient.
5. **Memcached does not require SASL authentication** or any configuration beyond the defaults provided by the community cookbook.
6. **The `ssl_certificate` Supermarket cookbook** (locked at 2.1.0) is not actively used by any recipe and can be dropped from the Ansible dependency list.
7. **The custom `lineinfile` LWRP** in `nginx-multisite/resources/lineinfile.rb` is dead code and will not be migrated; `ansible.builtin.lineinfile` covers the intended use case natively.
8. **Document root paths from `solo.json`** (`/var/www/{site}`) take precedence over cookbook attribute defaults (`/opt/server/{site}`) and will be used as the canonical values in Ansible variables.
9. **The FastAPI application will be run as a dedicated non-root service user** in the Ansible migration, correcting the current `User=root` security issue in the systemd unit.
10. **Ansible Vault will be used** for all secrets (`vault_redis_password`, `vault_postgres_fastapi_password`). The team must establish a Vault password management process (e.g., `ansible-vault` with a password file stored in a secrets manager) before migration begins.
11. **The `selinux` Supermarket cookbook** (a transitive dependency of `redisio`) is only relevant on RHEL/Fedora targets. If the confirmed target is Ubuntu/Debian, SELinux management tasks can be omitted entirely.
12. **Chef Solo run order** (`nginx-multisite` → `cache` → `fastapi-tutorial`) does not imply a strict runtime dependency between the three services; they can be deployed as independent Ansible roles applied in any order, though `fastapi-tutorial` logically depends on PostgreSQL being available.
