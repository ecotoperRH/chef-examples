# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-site web server environment composed of three local cookbooks and four external Supermarket dependencies. The stack deploys an Nginx reverse proxy with SSL-enabled virtual hosts, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL — all running on a single Fedora 42 VM managed via Vagrant and libvirt.

The migration is of **medium complexity**. All three cookbooks follow standard Chef patterns (package/template/service/execute resources) that map cleanly to Ansible equivalents. The most notable challenges are: a hardcoded Redis password in a recipe, hardcoded PostgreSQL credentials written to a `.env` file, a Ruby-block-based config-file patch that must be re-expressed as an Ansible task, and the need to replace four external Chef Supermarket cookbooks with native Ansible modules or community roles.

**Estimated migration effort: 3–4 weeks** for a single engineer, including testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a custom global `nginx.conf`, per-site `server {}` blocks with HTTP→HTTPS redirect, TLS 1.2/1.3 hardening, HSTS, and a full suite of security HTTP response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy). Also manages OS-level security hardening via fail2ban, UFW firewall rules, SSH daemon hardening, and kernel sysctl parameters.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features:
        - Five sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
        - Self-signed RSA-2048 certificate generation per virtual host via `openssl req -x509`
        - Dedicated `ssl-cert` group with `0710` permissions on the private key directory
        - Per-site static `index.html` files deployed from `files/default/{ci,status,test}/`
        - `security.conf` snippet: rate-limiting zones (`login`, `api`), buffer-overflow mitigations, global SSL session cache
        - `fail2ban.jail.local` with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`
        - `sysctl-security.conf` with 16 kernel hardening parameters (rp_filter, SYN cookies, ICMP redirect suppression, IPv6 disable)
        - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) that replicates Ansible's `lineinfile` module behaviour
        - Node attributes in `attributes/default.rb` define three sites with document roots under `/opt/server/`; `solo.json` overrides roots to `/var/www/`

- **cache**:
    - Description: Caching tier configuration that installs and enables both Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication, a dedicated log directory, and a post-install Ruby-block patch to strip deprecated Redis 7 configuration directives from the generated config file.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features:
        - Redis listening on port `6379` with `requirepass redis_secure_password_123` (hardcoded in recipe)
        - `ruby_block "fix_redis_config"` strips five deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` after `redisio` writes it — a workaround for `redisio 7.2.4` generating config keys incompatible with Redis 7.x
        - `/var/log/redis` directory created with `redis:redis` ownership
        - Depends on external cookbooks `memcached ~> 6.0` and `redisio >= 0.0.0` (locked at `7.2.4`); `redisio` in turn depends on `selinux 6.2.4`

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, including Python 3 runtime setup, virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, a `.env` configuration file with hardcoded database credentials, and a systemd unit file for process supervision.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features:
        - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch into `/opt/fastapi-tutorial`
        - Python venv at `/opt/fastapi-tutorial/venv`; pip install from `requirements.txt`
        - PostgreSQL user `fastapi` with password `fastapi_password` (hardcoded); database `fastapi_db`; full privileges granted
        - `.env` file at `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (world-readable `0644`)
        - systemd unit `fastapi-tutorial.service`: `uvicorn app.main:app --host 0.0.0.0 --port 8000`, `User=root`, `Restart=always`
        - Service runs as `root` — a security concern to address during migration

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest listing all three local cookbooks by path plus four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1`). Note: `ssl_certificate` is commented out in `Berksfile` but present and locked in `Policyfile.rb` / `Policyfile.lock.json`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Fully resolved dependency lock file. Locks: `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. The `selinux` cookbook is a transitive dependency pulled in by `redisio`.
- `solo.json`: Chef Solo node JSON providing the run list and attribute overrides. Overrides document roots to `/var/www/<site>/` (differing from the cookbook attribute defaults of `/opt/server/<site>/`) and explicitly sets `security.fail2ban.enabled`, `security.ufw.enabled`, `security.ssh.disable_root`, and `security.ssh.password_auth`. This file is the authoritative source of truth for runtime configuration and must be translated into Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks`, with cache at `/var/chef-solo`.
- `Vagrantfile`: Vagrant configuration using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync sync of the repo to `/chef-repo`. Provisions via `vagrant-provision.sh`.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, then executes `chef-solo -c solo.rb -j solo.json`. This script will be replaced by an Ansible playbook invocation in the migrated environment.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata summarising the three cookbooks; used by the X2Ansible tooling.
- `project-plan.md`: X2Ansible tool specification document describing the `--init`, `--analyze`, `--migrate`, and `--validate` CLI workflow. Not part of the infrastructure itself.

---

### Target Details

- **Operating System**: Fedora 42 (primary runtime as declared in `Vagrantfile` with `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The Ansible migration should target **Red Hat Enterprise Linux 9 / Fedora** as the primary platform, with optional Ubuntu compatibility via `ansible_os_family` conditionals. Package names (`ufw`, `fail2ban`, `libpq-dev`) differ between Debian and RPM families and will require platform-specific variable files.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly declared in the `Vagrantfile` (`config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. The infrastructure is designed for on-premises or generic VM deployment. No cloud-provider-specific tooling, metadata endpoints, or SDK packages are referenced.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0, locked 12.3.1)**: The `nginx` Supermarket cookbook is used only as a dependency carrier; the `nginx-multisite` cookbook installs nginx directly via the `package` resource and manages all configuration through its own templates. Replace with Ansible's `ansible.builtin.package` + `ansible.builtin.template` tasks. No community role is required.
- **memcached (~> 6.0, locked 6.1.0)**: Used via `include_recipe 'memcached'` in `cache::default`. Replace with `ansible.builtin.package` (install `memcached`) + `ansible.builtin.service` (enable/start). Configuration is default; no custom template is present in the source.
- **redisio (~> 7.2.4, locked 7.2.4)**: Provides Redis installation and per-instance config file generation. Replace with `ansible.builtin.package` (install `redis`), `ansible.builtin.template` for `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`), and `ansible.builtin.service`. The Ruby-block config-patch hack must be replaced with explicit `ansible.builtin.lineinfile` or `ansible.builtin.blockinfile` tasks that remove the deprecated directives cleanly.
- **ssl_certificate (~> 2.1, locked 2.1.0)**: Referenced in `Policyfile.rb` but not directly called in any recipe (the `ssl.rb` recipe uses raw `openssl` shell commands instead). Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection for idempotent self-signed certificate generation.
- **selinux (6.2.4)**: Transitive dependency of `redisio`. On Fedora/RHEL targets, SELinux management should be handled with `ansible.posix.selinux` and `community.general.seboolean` modules as needed for Redis and Nginx.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`): This credential is stored in plain text in the recipe. During migration, move to **Ansible Vault** — define `redis_requirepass` in an encrypted `group_vars/all/vault.yml`. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`fastapi` / `fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env` with mode `0644`): Two credentials (DB user password and the `DATABASE_URL` connection string). Move both to Ansible Vault. The `.env` file must be deployed with mode `0600` and owned by the service account, not `root`. **2 credentials detected.**
- **FastAPI service running as root**: The systemd unit sets `User=root`. During migration, create a dedicated `fastapi` system user and update the unit file accordingly.
- **Self-signed SSL certificates**: The `ssl.rb` recipe generates self-signed certificates via a shell `openssl` command with a hardcoded subject (`/C=US/ST=Example/...`). These are appropriate for development but must be replaced with CA-signed or Let's Encrypt certificates for production. The Ansible migration should use `community.crypto` modules and parameterise the subject fields via variables.
- **SSL private key permissions**: The recipe correctly sets `0640` on private keys with `root:ssl-cert` ownership. This must be preserved in the Ansible equivalent tasks.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` commands in `security.rb`. Replace with `ansible.builtin.lineinfile` tasks targeting `/etc/ssh/sshd_config`, with a handler to restart `sshd`. Ensure the Ansible control node has key-based access before applying these settings.
- **UFW firewall**: UFW is Debian/Ubuntu-native. On Fedora/RHEL targets, replace with `ansible.posix.firewalld`. Use `ansible_os_family` to conditionally apply the correct firewall module. The `solo.json` confirms UFW is enabled, so this platform mismatch must be resolved.
- **fail2ban**: Directly portable. Use `ansible.builtin.package`, `ansible.builtin.template` (for `jail.local`), and `ansible.builtin.service`. The `jail.local` ERB template maps 1:1 to a Jinja2 template.
- **sysctl hardening**: Use `ansible.posix.sysctl` module for each of the 16 kernel parameters defined in `sysctl-security.conf.erb`. This is fully idempotent and avoids the template+shell approach.
- **No Chef encrypted data bags or Chef Vault usage detected**: Secrets are stored as plain-text recipe attributes and node JSON — a pre-existing security gap that the Ansible migration must remediate via Ansible Vault.

---

### Technical Challenges

- **UFW on Fedora/RHEL**: The `security.rb` recipe installs and configures `ufw`, which is not available on Fedora/RHEL by default. The Vagrantfile targets Fedora 42, creating a platform mismatch. During migration, decide whether to use `firewalld` (native to Fedora/RHEL) or install `ufw` explicitly. The migration plan should implement a conditional: `when: ansible_os_family == 'Debian'` for UFW tasks and `when: ansible_os_family == 'RedHat'` for firewalld tasks.
- **Redis config-file patch (ruby_block)**: The `fix_redis_config` Ruby block in `cache::default.rb` post-processes `/etc/redis/6379.conf` to strip five deprecated directives written by `redisio`. In Ansible, this must be replaced with explicit `ansible.builtin.lineinfile` tasks (with `state: absent` and `regexp:` patterns) or by owning the entire Redis config template. The latter approach is cleaner and fully idempotent.
- **Document root path inconsistency**: `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}` while `solo.json` overrides them to `/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}`. The Ansible migration must canonicalise these paths in a single variable file. The `solo.json` values should be treated as the authoritative runtime values.
- **Custom `lineinfile` LWRP**: `resources/lineinfile.rb` implements a custom Chef resource that mimics Ansible's `lineinfile` module. This resource is defined but not called in any recipe in this repository. It can be dropped entirely during migration since Ansible provides this natively.
- **Git-based application deployment**: `fastapi-tutorial::default` uses Chef's `git` resource to clone/sync from GitHub. Replace with `ansible.builtin.git`. Ensure the target host has outbound HTTPS access to `github.com`. The `revision: main` means the playbook will always pull the latest commit on `main` — consider pinning to a specific tag or SHA for production stability.
- **Idempotency of PostgreSQL provisioning**: The recipe uses `execute` with `|| true` to suppress errors on duplicate user/database creation. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **systemd daemon-reload ordering**: The recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` after writing the unit file. In Ansible, use a handler with `ansible.builtin.systemd: daemon_reload: yes` triggered by the unit file task.
- **Multi-platform package name differences**: `libpq-dev` (Debian) vs `postgresql-devel` (RHEL/Fedora); `python3-pip` availability varies. Define platform-specific variable files (`vars/Debian.yml`, `vars/RedHat.yml`) and load them with `include_vars`.
- **Nginx `www-data` user**: The `nginx.rb` recipe sets document root ownership to `www-data:www-data`. On Fedora/RHEL, the Nginx user is `nginx`. Parameterise the web server user/group via variables.

---

### Migration Order

1. **nginx-multisite** — *Migrate first.* This is the most complex cookbook but is self-contained and has no runtime dependencies on the other two cookbooks. Establishing the Nginx role first validates the Ansible structure, the SSL certificate workflow, the templating approach, and the security hardening tasks. It also unblocks the virtual host configuration needed by the FastAPI application.
   - Sub-tasks in order: security hardening (fail2ban, UFW/firewalld, SSH, sysctl) → Nginx install + global config → SSL certificate generation → virtual host site configs + static content deployment.

2. **cache** — *Migrate second.* Independent of `nginx-multisite` and `fastapi-tutorial` at runtime. Low complexity once the Redis config-patch problem is resolved by owning the config template. Validates Ansible Vault integration for the Redis password before tackling the more sensitive FastAPI credentials.
   - Sub-tasks: Memcached install/service → Redis install + full config template (replacing the ruby_block hack) + service → Vault-encrypted password variable.

3. **fastapi-tutorial** — *Migrate last.* Depends on PostgreSQL being available (which it installs itself) and benefits from the Nginx virtual host already being in place for proxying. Contains the most security debt (root service user, world-readable `.env`, hardcoded credentials) that must be remediated as part of the migration.
   - Sub-tasks: System package install → PostgreSQL service + idempotent DB/user provisioning (community.postgresql) → Git clone → venv + pip install → `.env` deployment via Vault → systemd unit (non-root user) → service enable/start.

---

### Assumptions

1. **Target OS for Ansible**: The Vagrantfile specifies Fedora 42, but cookbook metadata declares Ubuntu ≥ 18.04 and CentOS ≥ 7 support. It is assumed that **Fedora 42 / RHEL 9** is the primary migration target. Ubuntu compatibility is a secondary goal and will require platform-conditional tasks for package names, firewall tooling, and service user names.
2. **UFW vs firewalld decision**: It is assumed that the team will decide to use `firewalld` (native to Fedora) rather than installing `ufw` on the target. If `ufw` must be retained (e.g., for Ubuntu parity), this assumption must be revisited.
3. **Self-signed certificates are acceptable for the migrated environment**: The current setup generates self-signed certificates for development. It is assumed this remains acceptable post-migration. If production deployment is intended, a Let's Encrypt or internal CA workflow must be added.
4. **Ansible Vault will be used for all secrets**: It is assumed the team will adopt Ansible Vault to store the Redis password, PostgreSQL password, and any future credentials. The current plain-text storage in recipes is a known gap to be closed.
5. **The FastAPI GitHub repository remains publicly accessible**: `https://github.com/dibanez/fastapi_tutorial.git` at branch `main` is assumed to remain available and stable. If the repository is private or the branch is renamed, the `ansible.builtin.git` task will need SSH key configuration or a different revision reference.
6. **PostgreSQL is installed on the same host as FastAPI**: The `DATABASE_URL` uses `localhost`. It is assumed single-host deployment continues. A multi-host topology would require changes to PostgreSQL `pg_hba.conf` and the connection string.
7. **The `fastapi-tutorial` service user will be changed to a non-root account**: The current `User=root` in the systemd unit is a security risk. It is assumed the migration will introduce a dedicated `fastapi` system user. The application must be verified to function correctly under a non-root user before this change is finalised.
8. **The custom `lineinfile` LWRP is unused and will be dropped**: No recipe in this repository calls the custom `lineinfile` resource. It is assumed it was created for future use or as a proof-of-concept and can be safely omitted from the Ansible migration.
9. **Document root canonical path**: The `solo.json` override (`/var/www/<fqdn>/`) is assumed to be the intended runtime path, superseding the cookbook attribute defaults (`/opt/server/<subdomain>/`). The Ansible `group_vars` will use the `solo.json` values.
10. **Vagrant/libvirt environment is retained for development testing**: It is assumed the Vagrantfile will be updated to provision via `ansible_local` or `ansible` provisioner instead of the shell script, allowing the migrated playbooks to be tested in the same VM environment.
11. **The `ssl_certificate` Supermarket cookbook is not functionally used**: Despite being present in `Policyfile.rb` and locked in `Policyfile.lock.json`, no recipe calls any resource from `ssl_certificate`. It is assumed this dependency can be dropped entirely in the Ansible migration.
12. **SELinux is permissive or managed externally on the target**: The `selinux` cookbook is a transitive dependency of `redisio` but no SELinux policy customisations are present in the local cookbooks. It is assumed SELinux is either in permissive mode or that default policies are sufficient for Nginx and Redis on the target host.
