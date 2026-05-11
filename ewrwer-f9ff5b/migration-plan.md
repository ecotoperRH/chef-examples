# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, dual caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The entire stack is driven by three local cookbooks and four external Chef Supermarket dependencies, orchestrated via a `Policyfile.rb` and exercised locally through a Vagrant/libvirt development environment targeting Fedora 42.

**Migration scope:** 3 local cookbooks, 5 external cookbook dependencies (nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, ssl_certificate 2.1.0, selinux 6.2.4), 5 ERB templates, 1 custom Chef resource, 3 static site assets, and a full security hardening layer.

**Complexity assessment:** Medium. The cookbooks follow conventional Chef patterns with direct Ansible equivalents. The main challenges are the data-driven multi-site loop, a Redis config post-processing hack, hardcoded credentials, and cross-platform (Debian/RHEL) compatibility that must be preserved.

**Estimated timeline:** 3–4 weeks for a complete migration including unit testing and a Vagrant-based smoke test.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts, security hardening (UFW firewall, fail2ban intrusion prevention, kernel sysctl tuning), and self-signed TLS certificate generation for three internal cluster subdomains
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Data-driven virtual-host loop over `node['nginx']['sites']` hash — creates document roots, deploys static `index.html` files, generates per-site Nginx `sites-available` configs, and symlinks them into `sites-enabled`
        - Per-site self-signed RSA-2048 certificate generation via `openssl req -x509` (idempotent: skips if cert+key already exist)
        - Strict TLS policy: TLSv1.2/1.3 only, strong cipher suite, HSTS header, HTTP→HTTPS redirect
        - Security headers on every vhost: `X-Frame-Options DENY`, `X-Content-Type-Options nosniff`, `X-XSS-Protection`, `Referrer-Policy`, `Content-Security-Policy`
        - UFW firewall: default-deny, allow SSH/HTTP/HTTPS via idempotent `execute` guards
        - fail2ban with four jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
        - Nginx rate-limiting zones (`login`: 10 r/m, `api`: 30 r/m) defined in `security.conf`
        - Kernel hardening via `/etc/sysctl.d/99-security.conf`: IP spoofing protection, ICMP redirect suppression, SYN-cookie flood protection, IPv6 disable
        - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` in-place edits
        - Custom `lineinfile` Chef resource (reimplements Ansible's `lineinfile` module in Ruby)
        - Three static HTML sites: `test.cluster.local` (test env), `ci.cluster.local` (CI/CD dashboard), `status.cluster.local` (service status page)

- **cache**:
    - Description: Dual caching layer configuring Memcached (via community cookbook) and Redis (via redisio community cookbook) with password authentication and a post-install config-file sanitisation workaround
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation and service management entirely to the `memcached` community cookbook
        - Configures Redis on port 6379 with `requirepass` authentication via `node['redisio']['servers']` attribute override
        - Creates `/var/log/redis` directory with correct `redis:redis` ownership
        - Post-install `ruby_block` hack strips deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` to prevent startup failures on newer Redis versions
        - Calls `redisio::enable` to activate the Redis systemd service

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running under a Python virtual environment with uvicorn, backed by a locally provisioned PostgreSQL database, and managed as a systemd service
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using Chef `git` resource with `:sync` action
        - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs `requirements.txt` dependencies
        - Enables and starts the `postgresql` service
        - Creates PostgreSQL role `fastapi` with password `fastapi_password`, database `fastapi_db`, and grants all privileges — using `|| true` guards for idempotency
        - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (world-readable `0644`)
        - Deploys `/etc/systemd/system/fastapi-tutorial.service` running uvicorn on `0.0.0.0:8000` as `root`, with `After=postgresql.service`
        - Reloads systemd daemon and enables/starts the `fastapi-tutorial` service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbooks and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but present in `Policyfile.rb` and resolved in the lock file. Replaced entirely by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and version constraints. Replaced by Ansible playbook + inventory.
- `Policyfile.lock.json`: Pinned dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks. Serves as the authoritative version reference during Ansible role selection.
- `solo.json`: Chef Solo node JSON supplying runtime attributes: three virtual-host definitions with document roots and `ssl_enabled: true`, SSL certificate/key paths, and security flags (`fail2ban`, `ufw`, SSH hardening). These attributes become Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks`. No migration artifact needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant configuration for a Fedora 42 VM (`generic/fedora42`) on libvirt with 2 vCPUs / 2 GB RAM, private IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. The VM spec directly informs the Ansible target environment and inventory.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks vendor`, and executes `chef-solo`. Replaced by an Ansible provisioner block in the Vagrantfile or a direct `ansible-playbook` invocation.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `generated-project-metadata.json` module inventory, and a preliminary `migration-plan.md`. Used as supplementary reference only; not part of the Chef run.

---

### Target Details

- **Operating System**: Fedora 42 (primary runtime as declared in `Vagrantfile`: `config.vm.box = "generic/fedora42"`). Cookbook `metadata.rb` files additionally declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, indicating cross-platform intent. Ansible roles must handle both `dnf`/`firewalld` (Fedora/RHEL family) and `apt`/`ufw` (Debian/Ubuntu family). Default target for Ansible role development: **Fedora 42 / Red Hat Enterprise Linux 9**.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the Vagrantfile (`config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module for installation and Jinja2 templates for `nginx.conf` and per-site vhost configs. Consider the `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role as a drop-in foundation.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.service` modules. The `geerlingguy.memcached` Galaxy role covers the full lifecycle.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`). The `geerlingguy.redis` Galaxy role is a suitable equivalent. The post-install config-strip hack must be reproduced with `ansible.builtin.lineinfile` (removing deprecated directives) or by owning the full config template.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` collection for self-signed certificate generation.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` for any required SELinux boolean adjustments on RHEL/Fedora targets.

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`): This credential is committed in plaintext. **Must be migrated to Ansible Vault** (`ansible-vault encrypt_string`). 1 credential detected.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for role `fastapi`, and `DATABASE_URL` written to `/opt/fastapi-tutorial/.env` with mode `0644`): Two plaintext secrets committed in source. **Must be migrated to Ansible Vault**. The `.env` file template must be rendered with `mode: '0600'` and owned by the service account, not root. 2 credentials detected.
- **Self-signed TLS certificates**: The current approach generates certificates at provision time using `openssl req -x509` with a hardcoded subject (`/C=US/ST=Example/...`). In Ansible, use `community.crypto` modules with variables for subject fields. For production, replace with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA.
- **SSL private key directory permissions**: The Chef recipe sets `/etc/ssl/private` to mode `0710` owned `root:ssl-cert`. This must be explicitly reproduced in the Ansible `file` task.
- **SSH hardening via `sed`**: The Chef recipe uses raw `sed` commands to modify `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` tasks for `PermitRootLogin no` and `PasswordAuthentication no`, or use the `devsec.hardening.ssh_hardening` Galaxy role for a comprehensive baseline.
- **UFW firewall management**: UFW is Debian/Ubuntu-native. On Fedora/RHEL targets, `firewalld` must be used instead. The Ansible role must branch on `ansible_os_family` to invoke either `community.general.ufw` or `ansible.posix.firewalld`.
- **fail2ban jail configuration**: The `fail2ban.jail.local.erb` template is static (no Chef variables). It can be migrated as a verbatim Ansible `copy` or `template` task. The `logpath` for `sshd` (`/var/log/auth.log`) is Debian-specific; on Fedora/RHEL it is `/var/log/secure` — this must be conditionally set.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template is also static. Use `ansible.posix.sysctl` module tasks (one per key) or deploy the file via `ansible.builtin.copy` and notify a handler to run `sysctl -p`. Note: `net.ipv4.icmp_echo_ignore_all = 1` will break ICMP-based health checks — document this as a deliberate policy decision.
- **FastAPI service running as root**: The systemd unit file sets `User=root`. This is a security risk and should be corrected during migration by creating a dedicated `fastapi` system account.
- **Nginx `server_tokens off`**: Already present in `security.conf.erb`; ensure it is preserved in the Ansible template.

### Technical Challenges

- **Data-driven multi-site loop**: The Chef recipes iterate over `node['nginx']['sites']` to create document roots, deploy static files, generate SSL certificates, and write vhost configs. In Ansible this maps to a `loop` over a `nginx_sites` list variable. The variable structure must be carefully designed to carry all per-site attributes (`server_name`, `document_root`, `ssl_enabled`, `cert_file`, `key_file`). The Jinja2 `site.conf.j2` template must replicate the conditional HTTP→HTTPS redirect block from `site.conf.erb`.
- **Redis config post-processing hack**: `cookbooks/cache/recipes/default.rb` uses a `ruby_block` to strip deprecated directives from `/etc/redis/6379.conf` after the `redisio` cookbook writes it. In Ansible, the cleanest solution is to own the entire Redis config via a managed Jinja2 template, eliminating the need for post-processing. If using the `geerlingguy.redis` role, override `redis_conf_path` and supply a custom template.
- **Cross-platform package and service names**: `ufw` is not available on Fedora; `firewalld` must be used. The `fail2ban` log path for SSH differs between distros. The `www-data` user (Nginx worker on Debian) is `nginx` on RHEL/Fedora. All tasks that reference these must use `ansible_os_family` or `ansible_distribution` conditionals.
- **Chef `git` resource `:sync` action**: This performs a `git pull` on every Chef run. The Ansible `ansible.builtin.git` module with `update: yes` replicates this, but care must be taken with `force` and `version` parameters to avoid overwriting local changes.
- **Systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd before enabling the service. In Ansible, use a `notify` handler with `ansible.builtin.systemd: daemon_reload: yes` and ensure handler ordering is correct (reload before enable/start).
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements Ansible's own `lineinfile` module. This resource is not called anywhere in the current recipes (it appears to be unused scaffolding), but its presence should be verified — if it is used, the migration is trivial since `ansible.builtin.lineinfile` is a direct replacement.
- **Document root path discrepancy**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, but `solo.json` overrides them to `/var/www/{test,ci,status}.cluster.local`. The Ansible variable definition must resolve this conflict explicitly and use a single authoritative source.
- **`ssl_certificate` cookbook in Policyfile but commented out in Berksfile**: The lock file resolves `ssl_certificate 2.1.0`, but the Berksfile has it commented out. The actual SSL certificate generation is done inline in `ssl.rb` via raw `openssl` commands, not via the community cookbook. The community cookbook dependency appears unused and can be dropped.

### Migration Order

1. **`cache` cookbook** — Low complexity, fully independent, no inbound dependencies from the other cookbooks. Establishes the Ansible role skeleton and Vault patterns for the Redis password. Delivers immediate value as a standalone role.
2. **`nginx-multisite` cookbook** — Medium-high complexity. Depends on no other local cookbook but contains the most logic (5 recipes, 5 templates, 1 custom resource, security hardening). Should be broken into sub-roles or tagged tasks: `nginx_install` → `ssl_certs` → `vhosts` → `security_hardening`. Migrate after `cache` so Vault and variable patterns are established.
3. **`fastapi-tutorial` cookbook** — High complexity. Depends on PostgreSQL (not managed by any other cookbook — it is installed and started inline), the GitHub repository availability, and correct Python/venv toolchain. Contains the most security debt (hardcoded credentials, root service user, world-readable `.env`). Migrate last, after patterns from the previous two roles are proven.

### Assumptions

1. **Target OS for Ansible development is Fedora 42** (matching the Vagrantfile), with secondary support for Ubuntu 22.04 LTS and RHEL 9 as declared in cookbook metadata. Any OS-conditional logic must be validated on all three.
2. **Self-signed certificates are acceptable for the development/staging environment.** Production deployments are assumed to require a separate certificate provisioning strategy (Let's Encrypt or internal CA) that is out of scope for this migration but should be noted in role documentation.
3. **The three virtual hosts (`test`, `ci`, `status`) are static sites** with no server-side processing beyond Nginx. No application server (PHP-FPM, etc.) is needed for these sites.
4. **The FastAPI GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) will remain publicly accessible** during and after migration. If the repository becomes private, an SSH deploy key or token must be added to Ansible Vault.
5. **Redis does not require clustering, Sentinel, or persistence** beyond the single-instance configuration currently in place. The `requirepass` directive is the only Redis security control.
6. **Memcached requires no authentication** (consistent with the current cookbook, which delegates entirely to the community cookbook defaults). If the environment requires SASL authentication, this is out of scope.
7. **The `ssl_certificate` community cookbook is not functionally used** — SSL generation is handled inline in `ssl.rb`. The dependency can be dropped in the Ansible migration.
8. **The `lineinfile` custom Chef resource is not called** by any recipe in this repository. It will not be migrated unless a future audit reveals hidden usage.
9. **The document root paths in `solo.json`** (`/var/www/<site>`) take precedence over the cookbook attribute defaults (`/opt/server/<site>`). The Ansible `group_vars` will use the `solo.json` values as the authoritative source.
10. **The FastAPI service will be migrated to run as a dedicated non-root system user** (`fastapi`) rather than `root` as currently configured. This is a deliberate security improvement introduced during migration.
11. **Ansible Vault will be used for all secrets**: Redis password, PostgreSQL password, and the `DATABASE_URL` connection string. The `.env` file will be rendered from a Vault-encrypted variable with restrictive file permissions (`0600`).
12. **The Vagrant/libvirt development environment will be retained** for local testing of the migrated Ansible playbooks, replacing `vagrant-provision.sh` with an Ansible provisioner block in the Vagrantfile.
13. **No Chef Server, Chef Automate, or Policyfile push workflow is in use** — the stack runs exclusively via `chef-solo`, simplifying the migration since there is no server-side state to reconcile.
14. **The `selinux` cookbook (transitive dependency of `redisio`) implies SELinux may be enforcing on RHEL/Fedora targets.** The Ansible migration must account for SELinux contexts for Redis data directories, Nginx port bindings, and the FastAPI service if deploying to RHEL 9.
