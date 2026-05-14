# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The entire stack is driven by three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) and four external Chef Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`), all pinned in `Policyfile.lock.json`.

The development environment is a **Fedora 42** VM managed by Vagrant with the libvirt provider. Cookbook metadata also declares support for Ubuntu ≥ 18.04 and CentOS ≥ 7, so the Ansible equivalent must be cross-platform.

**Migration complexity: Medium.** The three cookbooks are well-scoped, have no circular dependencies, and map cleanly to Ansible roles. The main challenges are: replacing the `redisio` community cookbook's config-patching `ruby_block` hack, managing hardcoded credentials currently embedded in recipe code, and preserving the multi-site Nginx templating flexibility. A realistic end-to-end migration (including testing) is estimated at **3–4 weeks** for a small team.

---

## Module Migration Plan

This repository contains three Chef cookbooks that each require an individual Ansible role migration:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx reverse proxy and static-site server with per-vhost SSL termination, self-signed certificate generation, HTTP→HTTPS redirect, and a full security-hardening layer (UFW firewall, fail2ban intrusion prevention, kernel sysctl tuning, SSH hardening)
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef (version 1.0.0, requires Chef ≥ 16.0)
    - Key Features:
        - Three SSL-enabled virtual hosts: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`, each with a dedicated document root under `/opt/server/<site>/`
        - Per-site Nginx vhost templates (`site.conf.erb`) with TLSv1.2/1.3-only cipher suites, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy)
        - Global Nginx hardening via `security.conf.erb`: rate-limiting zones, buffer-overflow mitigations, hidden server tokens
        - Self-signed RSA-2048 certificate generation via `openssl req` for each SSL-enabled site; certificates stored in `/etc/ssl/certs/` and private keys in `/etc/ssl/private/` (mode `0710`, group `ssl-cert`)
        - UFW firewall: default-deny policy, explicit allow for SSH/HTTP/HTTPS
        - fail2ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`; ban time 3600 s, max-retry 3
        - Kernel hardening via `/etc/sysctl.d/99-security.conf`: IP spoofing protection, ICMP redirect rejection, SYN-cookie flood protection, IPv6 disable, Martian packet logging
        - SSH daemon hardening: `PermitRootLogin no`, `PasswordAuthentication no`
        - Custom `lineinfile` LWRP resource (mirrors Ansible's `lineinfile` module)
        - Static HTML landing pages for each site (test, ci, status) deployed as cookbook files

- **cache**:
    - Description: Caching tier configuration that installs and configures both Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, plus a post-install config-patching workaround for deprecated Redis replica directives
    - Path: `cookbooks/cache`
    - Technology: Chef (version 1.0.0, requires Chef ≥ 16.0)
    - Key Features:
        - Memcached installed and started via the upstream `memcached` community cookbook (version 6.1.0)
        - Redis server on port 6379 with `requirepass` authentication (password hardcoded in recipe as `redis_secure_password_123`)
        - Dedicated `/var/log/redis` directory (owner `redis:redis`, mode `0755`)
        - Post-install `ruby_block` hack that strips deprecated Redis 7 directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` to prevent startup failures
        - Redis service enabled via `redisio::enable` recipe
        - Transitive dependency on `selinux` cookbook (pulled in by `redisio 7.2.4`) indicating RHEL/SELinux awareness

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI web application cloned from GitHub, running inside a Python virtual environment under `/opt/fastapi-tutorial/`, backed by a locally provisioned PostgreSQL database, and managed as a systemd service
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef (version 1.0.0, requires Chef ≥ 16.0)
    - Key Features:
        - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial/`
        - Python venv creation at `/opt/fastapi-tutorial/venv` and `pip install -r requirements.txt`
        - PostgreSQL service enabled and started; database user `fastapi` with password `fastapi_password` and database `fastapi_db` created via inline `psql` commands (idempotent with `|| true`)
        - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (mode `0644`, owned by root — **security gap**)
        - systemd unit file `/etc/systemd/system/fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, `Restart=always`, runs as `root` (**security gap**)
        - `systemctl daemon-reload` triggered on unit file change; service enabled and started

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest; declares all three local cookbooks by path and pins external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but active in `Policyfile.rb`. Replaced entirely by Ansible Galaxy `requirements.yml` in the migrated project.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`. Replaced by Ansible playbook(s) and inventory.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all eight resolved cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Used as the authoritative version reference during migration.
- `solo.json`: Chef Solo node JSON; overrides default attributes for the three virtual-host sites (document roots under `/var/www/<site>/`, all SSL-enabled) and security settings (fail2ban, UFW, SSH hardening). **Note:** document root paths here (`/var/www/…`) differ from cookbook attribute defaults (`/opt/server/…`) — the `solo.json` values take precedence at runtime. This discrepancy must be resolved during migration.
- `solo.rb`: Chef Solo configuration; sets `file_cache_path /var/chef-solo` and `cookbook_path ["/chef-repo/cookbooks", "/chef-repo/cookbooks-*/cookbooks"]`. No direct Ansible equivalent needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of repo to `/chef-repo`. Informs the Ansible inventory host definition and connection variables.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and then executes `chef-solo -c solo.rb -j solo.json`. Replaced by `ansible-playbook` invocation in the migrated workflow.

---

### Target Details

- **Operating System**: Fedora 42 (primary, as declared in `Vagrantfile` with `generic/fedora42`). Cookbook `metadata.rb` files additionally declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7. The Ansible roles must handle both Debian-family (`apt`, `ufw`) and RedHat-family (`dnf`/`yum`, `firewalld`) package managers and service names. Default target for production migration: **Red Hat Enterprise Linux 9** (closest supported RHEL-family equivalent to Fedora 42).
- **Virtual Machine Technology**: **libvirt / KVM** (explicitly set as the Vagrant provider: `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or SDK references are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community cookbook handles package install, service management, and basic config. Replace with the `ansible.builtin.package` module for installation, `ansible.builtin.template` for `nginx.conf` and vhost configs, and `ansible.builtin.service` for lifecycle management. Consider the `nginxinc.nginx` Ansible Galaxy role as a drop-in if a community role is preferred.
- **memcached (6.1.0, Chef Supermarket)**: Straightforward package-and-service cookbook. Replace with `ansible.builtin.package` + `ansible.builtin.service`. The `geerlingguy.memcached` Galaxy role is a well-maintained equivalent.
- **redisio (7.2.4, Chef Supermarket)**: Installs Redis from source or package and manages per-instance config files. Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`). The `geerlingguy.redis` Galaxy role covers this use case. The config-patching `ruby_block` hack becomes unnecessary if the Ansible template is written directly against the installed Redis version's supported directives.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Provides helpers for SSL cert/key management. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection for self-signed certificate generation.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio` for RHEL/CentOS SELinux management. Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` for any required SELinux boolean adjustments on RHEL-family targets.

---

### Security Considerations

- **Hardcoded Redis password**: The `cache` cookbook recipe (`cookbooks/cache/recipes/default.rb`) contains `'requirepass' => 'redis_secure_password_123'` in plain text. This credential **must** be extracted into an Ansible Vault-encrypted variable (`vault_redis_password`) before migration. **1 hardcoded credential detected.**
- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial` recipe contains `PASSWORD 'fastapi_password'` in an inline `psql` command and `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` written to a `.env` file. Both must be moved to Ansible Vault (`vault_postgres_password`). **2 hardcoded credential instances detected.**
- **`.env` file permissions**: `/opt/fastapi-tutorial/.env` is written with mode `0644` (world-readable) and owned by `root`. In Ansible, this file should be templated with mode `0600` and owned by a dedicated service account, not root.
- **FastAPI service running as root**: The systemd unit sets `User=root`. The Ansible migration must create a dedicated unprivileged system user (e.g., `fastapi`) and run the service under that account.
- **Self-signed SSL certificates**: The `ssl.rb` recipe generates self-signed RSA-2048 certificates valid for 365 days using `openssl req`. These are appropriate for development but must be replaced with CA-signed certificates (e.g., Let's Encrypt via `community.crypto.acme_certificate`) for any production deployment. The Ansible role should parameterise the certificate source.
- **SSL private key permissions**: Keys are stored in `/etc/ssl/private/` with mode `0640`, group `ssl-cert`. The Ansible `community.crypto.openssl_privatekey` module must replicate these exact permissions.
- **UFW firewall management**: `ufw` is Debian/Ubuntu-specific. On Fedora/RHEL targets, `firewalld` must be used instead. The Ansible role must branch on `ansible_os_family` to call either `community.general.ufw` or `ansible.posix.firewalld`.
- **SSH hardening via `sed`**: The `security.rb` recipe uses raw `sed` commands to modify `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` (the cookbook even ships a custom `lineinfile` LWRP that mirrors this module exactly) for idempotent, auditable SSH config management.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template disables IPv6 globally (`net.ipv6.conf.all.disable_ipv6 = 1`) and ignores all ICMP pings (`net.ipv4.icmp_echo_ignore_all = 1`). These are aggressive settings that may break monitoring or cloud-platform health checks. Review before applying in production. Use `ansible.posix.sysctl` module for idempotent management.
- **fail2ban configuration**: The `fail2ban.jail.local.erb` template enables four jails. Migrate using `ansible.builtin.template` for `jail.local` and `ansible.builtin.service` for the fail2ban daemon. Ensure the `nginx-botsearch` filter file exists on the target OS before enabling that jail.
- **Vault / secrets summary**:
  - `cache` cookbook: 1 credential (Redis `requirepass`) — migrate to `vault_redis_password`
  - `fastapi-tutorial` cookbook: 2 credentials (PostgreSQL user password in `psql` command + `.env` file) — migrate to `vault_postgres_password`
  - `nginx-multisite` cookbook: 0 runtime credentials; SSL key material is generated on-host

---

### Technical Challenges

- **Document root path discrepancy**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/<site>/`, but `solo.json` (and the project-level `solo.json` in the `.myprj` directory) overrides them to `/var/www/<site>/`. The static HTML files in `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html` reference `/opt/server/…` in their content. The Ansible migration must pick one canonical path, update all references consistently, and parameterise it as a role variable.
- **Redis config-patching `ruby_block`**: The `cache` cookbook uses a `ruby_block` to post-process `/etc/redis/6379.conf` and strip directives that are invalid in the installed Redis version. This is a fragile workaround. In Ansible, the Redis config should be managed entirely via a Jinja2 template that only emits directives supported by the target Redis version, eliminating the need for post-processing.
- **Cross-platform firewall abstraction**: `ufw` (used in `security.rb`) is only available on Debian/Ubuntu. Fedora 42 and RHEL 9 use `firewalld`. The Ansible role must implement a conditional block: `when: ansible_os_family == 'Debian'` for `community.general.ufw` tasks and `when: ansible_os_family == 'RedHat'` for `ansible.posix.firewalld` tasks.
- **Multi-site Nginx vhost loop**: The Chef recipe iterates over `node['nginx']['sites']` to generate vhost configs, symlinks, and document roots. In Ansible, this maps to a `loop` over a `nginx_sites` list variable, using `ansible.builtin.template` and `ansible.builtin.file` (for symlinks). The data structure must be translated from the Chef hash format to an Ansible list-of-dicts format.
- **Git-based application deployment**: The `fastapi-tutorial` recipe uses Chef's `git` resource to clone/sync the application. The Ansible `ansible.builtin.git` module is a direct equivalent, but care must be taken with `force` and `update` flags to avoid overwriting local changes in non-idempotent deployments.
- **`systemctl daemon-reload` ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd before starting the service. In Ansible, this is handled by a handler (`ansible.builtin.systemd: daemon_reload: yes`) triggered by the unit file template task — the ordering must be verified to avoid a race condition on first deploy.
- **`ssl_certificate` cookbook commented out in Berksfile**: The `ssl_certificate` dependency is commented out in `Berksfile` but active in `Policyfile.rb` and resolved in `Policyfile.lock.json`. The actual SSL logic in `ssl.rb` uses raw `openssl` shell commands rather than the cookbook's resources, so the dependency is effectively unused at runtime. No migration action needed for this cookbook, but the discrepancy should be documented and the unused dependency removed.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook ships a custom `lineinfile` resource (`resources/lineinfile.rb`) that replicates Ansible's built-in `lineinfile` module. This resource is defined but not called anywhere in the cookbook's own recipes (SSH hardening uses raw `sed` instead). It can be dropped entirely in the Ansible migration since `ansible.builtin.lineinfile` is natively available.
- **Vagrant-specific network assumptions**: The `vagrant-provision.sh` script references IP `192.168.56.10` in its output messages, while the `Vagrantfile` assigns `192.168.121.10`. This inconsistency suggests the network configuration has drifted. The Ansible inventory must use the correct, verified IP address.

---

### Migration Order

The following order minimises risk by migrating independent, lower-complexity components first and leaving the most complex, credential-heavy component for last:

1. **`cache` role** — Lowest structural complexity; installs two independent services (Memcached, Redis) with no web-facing configuration. Migrating this first validates the Ansible project scaffold, Galaxy role integration, and Vault credential workflow with minimal blast radius. The Redis config-patching workaround is the only notable challenge.

2. **`nginx-multisite` role** — Medium complexity; depends on no other local cookbook. Establishes the core web-serving infrastructure, SSL certificate generation, and the full security-hardening layer (UFW/firewalld, fail2ban, sysctl, SSH). Migrating this second allows the security baseline to be validated in isolation before application workloads are added. The cross-platform firewall abstraction and multi-site vhost loop are the primary challenges.

3. **`fastapi-tutorial` role** — Highest complexity; depends on PostgreSQL (installed as part of this cookbook), involves Git-based deployment, Python venv management, credential handling, and systemd service configuration. Migrated last so that the underlying infrastructure (web server, caching, security) is already validated. Requires Vault integration for PostgreSQL credentials and a dedicated service account to be created as part of this role.

---

### Assumptions

1. **Target OS for production**: The Vagrantfile uses Fedora 42, but no production OS is explicitly declared. This plan assumes **Red Hat Enterprise Linux 9** as the production target, with Fedora 42 retained for local development. Ansible roles must be tested against both.
2. **Self-signed certificates are development-only**: The `ssl.rb` recipe generates self-signed certificates. It is assumed that production deployments will require CA-signed certificates. The Ansible role will be parameterised to support both modes (`ssl_cert_mode: selfsigned | letsencrypt | provided`).
3. **Single-node deployment**: The current Chef Solo setup provisions a single VM. No clustering, load balancing, or HA configuration is present for any service (Nginx, Redis, Memcached, PostgreSQL). The Ansible migration will target the same single-node topology unless explicitly expanded.
4. **Redis is standalone, not clustered**: `redisio` is configured with a single server instance on port 6379. No replication or Sentinel configuration is present. The Ansible `geerlingguy.redis` role will be configured for standalone mode.
5. **Memcached default configuration**: The `cache` cookbook delegates entirely to the upstream `memcached` cookbook with no attribute overrides. It is assumed that default Memcached settings (port 11211, 64 MB memory limit, localhost binding) are acceptable for the target environment.
6. **FastAPI application repository availability**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git` from a public GitHub repository. It is assumed this repository will remain publicly accessible. If it becomes private or is moved, the Ansible role's `git` task will need updated credentials or a mirrored source.
7. **PostgreSQL version**: The recipe installs `postgresql` and `postgresql-contrib` from the OS default package repositories without specifying a version. The exact version will vary by OS (e.g., PostgreSQL 15 on RHEL 9). The Ansible role should pin a specific major version via a variable (`postgresql_version: 15`) for reproducibility.
8. **No existing Ansible infrastructure**: It is assumed the team is starting the Ansible project from scratch. A standard role-based directory layout (`roles/`, `playbooks/`, `inventory/`, `group_vars/`) will be created as part of the migration.
9. **Ansible Vault will be used for all secrets**: All credentials currently hardcoded in Chef recipes (`redis_secure_password_123`, `fastapi_password`) will be migrated to Ansible Vault. The team must establish a Vault password management process (e.g., `ansible-vault` with a password file stored in a secrets manager) before migration begins.
10. **Document root canonical path**: The discrepancy between `/opt/server/<site>/` (cookbook attributes) and `/var/www/<site>/` (solo.json overrides) must be resolved by the team before migration. This plan assumes `/var/www/<site>/` as the canonical path, matching the `solo.json` runtime behaviour, but this must be confirmed.
11. **`ssl_certificate` community cookbook is unused at runtime**: Despite being declared in `Policyfile.rb` and resolved in the lock file, the actual SSL logic uses raw `openssl` shell commands. The `ssl_certificate` cookbook resources are never called. No Ansible equivalent for this cookbook is required.
12. **IPv6 disable is intentional**: The `sysctl-security.conf.erb` template disables IPv6 system-wide. It is assumed this is a deliberate security decision for the target environment and not an oversight. This setting will be preserved in the Ansible `sysctl` tasks but flagged for review before production deployment.
