# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-site web server environment composed of three local cookbooks and four external Supermarket dependencies. The full run list is: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`.

The stack delivers:
- An **Nginx reverse proxy** with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), security hardening, and self-signed certificate generation.
- **Caching services** (Memcached 6.1.0 + Redis 6379 with password authentication) managed via the `redisio` and `memcached` Supermarket cookbooks.
- A **Python FastAPI application** backed by PostgreSQL, deployed from a public GitHub repository, running as a systemd service.

The migration is of **medium complexity**. All three cookbooks follow standard Chef patterns (package/template/service/execute resources) with direct Ansible equivalents. The main challenges are: a hardcoded Redis password requiring Ansible Vault remediation, a Ruby-block config-patching hack in the cache cookbook, a cross-platform support requirement (Ubuntu 18.04+ and CentOS 7+ per metadata, Fedora 42 in Vagrant), and a custom `lineinfile` LWRP that maps cleanly to Ansible's built-in `lineinfile` module.

**Estimated migration effort: 3–4 weeks** for a single engineer, including testing in the Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a global `nginx.conf`, a hardened `security.conf` (rate limiting, buffer overflow protection, TLS 1.2/1.3 cipher suite), per-site self-signed certificate generation via `openssl req`, HTTP→HTTPS redirect, full security-header set (HSTS, X-Frame-Options, CSP, X-XSS-Protection), fail2ban with four jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch), UFW firewall (default deny + SSH/HTTP/HTTPS allow), SSH hardening (root login disabled, password auth disabled), and kernel-level sysctl network hardening.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef (version 1.0.0, chef_version >= 16.0)
    - Key Features: Multi-site virtual host templating via `site.conf.erb`, self-signed RSA-2048 certificate generation per site, fail2ban jail configuration, UFW rule management via `execute` resources, sysctl hardening via `/etc/sysctl.d/99-security.conf`, static site content deployment (`ci/`, `status/`, `test/` index pages), custom `lineinfile` LWRP, `www-data` ownership of document roots.

- **cache**:
    - Description: Caching services layer configuring Memcached (via the `memcached` Supermarket cookbook v6.1.0) and Redis (via the `redisio` Supermarket cookbook v7.2.4) on port 6379 with password authentication. Includes a `ruby_block` post-processing hack to strip deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf`.
    - Path: `cookbooks/cache`
    - Technology: Chef (version 1.0.0, chef_version >= 16.0)
    - Key Features: Memcached installation and service management, Redis with `requirepass` authentication, `/var/log/redis` directory creation with `redis:redis` ownership, post-install config-file patching via `ruby_block`, `redisio::enable` recipe inclusion.

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application from the public GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`), backed by a local PostgreSQL database. Provisions system packages, creates a Python virtual environment, installs pip dependencies, creates a PostgreSQL user (`fastapi`) and database (`fastapi_db`), writes a `.env` file with the `DATABASE_URL`, deploys a systemd unit file, and manages the `fastapi-tutorial` service.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef (version 1.0.0, chef_version >= 16.0)
    - Key Features: System package installation (`python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`), `git` resource for repository sync, Python venv creation and pip install, PostgreSQL service management, `sudo -u postgres psql` idempotent DB/user provisioning, `.env` file with inline credentials, systemd service unit deployment with `systemctl daemon-reload` notification, service running as `root`.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note: `ssl_certificate` is commented out in Berksfile but present in Policyfile.rb and locked in `Policyfile.lock.json`). Must be replaced by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), run list, and cookbook version constraints. Equivalent to an Ansible playbook with `roles:` or `tasks:` ordering. The run list order (`nginx-multisite` → `cache` → `fastapi-tutorial`) must be preserved as Ansible play/role execution order.
- `Policyfile.lock.json`: Pinned dependency graph including transitive dependencies (`selinux 6.2.4` pulled in by `redisio`). Documents exact versions: `memcached 6.1.0`, `nginx 12.3.1`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. Reference for pinning Ansible Galaxy role versions.
- `solo.json`: Chef Solo node JSON — the runtime attribute override file. Defines the three virtual host sites with document roots and `ssl_enabled: true`, SSL certificate/key paths (`/etc/ssl/certs`, `/etc/ssl/private`), and security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth`). Maps directly to Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No migration artifact needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant development environment using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. Defines the target development OS as **Fedora 42**. Should be updated to use the `ansible_local` or `ansible` Vagrant provisioner after migration.
- `vagrant-provision.sh`: Bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo -c solo.rb -j solo.json`. Replaced entirely by `vagrant-provision.sh` invoking `ansible-playbook` after migration.
- `project-plan.md`: X2Ansible tool specification document. Not a migration artifact; documents the tooling used to generate this plan.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project working directory generated by the X2Ansible tool, containing a prior `migration-plan.md`, `solo.json` copy, `Policyfile.lock.json` copy, and `generated-project-metadata.json`. Not part of the infrastructure source; can be excluded from the Ansible repository.

---

### Target Details

- **Operating System**: **Fedora 42** (primary, as specified in `Vagrantfile` with `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu >= 18.04 and CentOS >= 7.0, indicating a cross-platform intent. Ansible playbooks must handle both Debian/Ubuntu (`apt`, `ufw`, `www-data` user) and RHEL/Fedora/CentOS (`dnf`/`yum`, `firewalld`, `nginx` user) package managers and service names. The `ufw` firewall tool used in `security.rb` is Debian/Ubuntu-specific and is not available on Fedora/RHEL — this is a critical cross-platform gap.
- **Virtual Machine Technology**: **KVM/libvirt** (specified via `config.vm.provider "libvirt"` in `Vagrantfile`).
- **Cloud Platform**: Not specified. The infrastructure is designed for on-premises or generic VM deployment. No cloud-provider-specific tooling, metadata endpoints, or SDKs are present.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0, locked 12.3.1)**: The `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role provides equivalent functionality. Alternatively, use the `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` modules directly for full control. The Chef `nginx` cookbook's attribute-driven site management must be re-implemented as Ansible variable-driven template loops.
- **memcached (~> 6.0, locked 6.1.0)**: Replace with `geerlingguy.memcached` Galaxy role or direct `package`/`service` tasks. Memcached configuration is minimal (default settings); a simple role suffices.
- **redisio (~> 7.2.4, locked 7.2.4)**: Replace with `geerlingguy.redis` Galaxy role or direct package/template tasks. The `requirepass` directive must be templated from an Ansible Vault variable. The `ruby_block` config-patching hack (stripping deprecated directives) must be replaced with a clean Ansible-managed `redis.conf` template that never emits those deprecated keys in the first place.
- **ssl_certificate (~> 2.1, locked 2.1.0)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection. This provides idempotent, declarative self-signed certificate generation without shell `openssl req` invocations.
- **selinux (6.2.4, transitive via redisio)**: On RHEL/Fedora targets, use the `ansible.posix.selinux` module and `community.general.seboolean` / `ansible.posix.sefcontext` as needed. On Ubuntu targets, SELinux is not applicable (AppArmor is used instead).

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): This is a **critical security finding** — a plaintext credential committed to source control. Must be migrated to an **Ansible Vault**-encrypted variable (e.g., `vault_redis_password`) and referenced via `vars_files` or `group_vars/all/vault.yml`. The password itself must be rotated before or during migration.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb`, both in the `psql` provisioning commands and in the `.env` file content): Another **critical security finding** — plaintext database password in source. Must be migrated to Ansible Vault (`vault_fastapi_db_password`). The `.env` file template must reference the vaulted variable. The password must be rotated.
- **`.env` file permissions** (`mode '0644'`, `owner 'root'`, `group 'root'` in `fastapi-tutorial` recipe): The `.env` file containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` is world-readable. In Ansible, this file should be deployed with `mode: '0600'` and owned by the service account user (not root).
- **FastAPI service running as root** (`User=root` in the systemd unit): The application runs as the `root` user, which is a security risk. During migration, a dedicated `fastapi` system user should be created and the service unit updated accordingly.
- **Self-signed SSL certificates**: Generated via `openssl req` with a hardcoded subject (`/C=US/ST=Example/...`). Acceptable for development; production deployments must use CA-signed certificates (Let's Encrypt via `community.crypto.acme_certificate` or an internal PKI). The certificate subject details should be parameterized as Ansible variables.
- **SSH hardening** (root login disabled, password auth disabled): Managed via `sed` on `/etc/ssh/sshd_config` in `security.rb`. Replace with the `ansible.builtin.lineinfile` module or a full `sshd_config` template. Ensure the Ansible control node has key-based SSH access configured before applying these hardening tasks, or the playbook will lock itself out.
- **UFW firewall rules**: Managed via `execute` resources with `not_if` guards in `security.rb`. Replace with the `community.general.ufw` Ansible module for idempotent rule management. **Note**: UFW is Debian/Ubuntu-specific. On Fedora/RHEL targets, use `ansible.posix.firewalld` instead. The playbook must branch on `ansible_os_family`.
- **fail2ban configuration**: The `jail.local` template bans on 3 retries for SSH and nginx-http-auth, 10 retries for nginx-limit-req, and 2 retries for nginx-botsearch, with a 1-hour ban time. Migrate using `ansible.builtin.template` for `jail.local` and `ansible.builtin.service` for fail2ban. The `community.general` collection provides a `fail2ban_*` set of modules as an alternative.
- **sysctl kernel hardening**: 20+ kernel parameters set in `/etc/sysctl.d/99-security.conf` (IP spoofing protection, ICMP redirect blocking, source routing disabled, martian logging, ICMP echo ignore, IPv6 disabled, TCP SYN cookie protection). Replace with the `ansible.posix.sysctl` module applied in a loop over a variable-defined parameter dictionary.
- **Credential summary by module**:
  - `cache`: 1 hardcoded secret (Redis `requirepass` password).
  - `fastapi-tutorial`: 2 hardcoded secrets (PostgreSQL user password in `psql` command + `.env` file `DATABASE_URL`).
  - `nginx-multisite`: 0 hardcoded secrets (SSL cert subject is parameterizable but not a secret).
  - **Total: 3 credential instances requiring Ansible Vault migration.**

### Technical Challenges

- **Cross-platform firewall divergence**: The `security.rb` recipe uses `ufw`, which is only available on Debian/Ubuntu. The Vagrantfile targets Fedora 42, which uses `firewalld`. The current Chef code will fail on Fedora without modification. The Ansible migration must implement an `ansible_os_family`-conditional block: `community.general.ufw` for Debian/Ubuntu and `ansible.posix.firewalld` for RedHat/Fedora. This is the highest-risk technical gap in the current codebase.
- **Redis config-patching `ruby_block` hack**: The `cache` cookbook uses a `ruby_block` to post-process `/etc/redis/6379.conf` and strip deprecated directives emitted by the `redisio` cookbook. In Ansible, this is resolved by using a fully Ansible-managed `redis.conf` template (via `geerlingguy.redis` role variables or a custom template) that never generates those deprecated keys, eliminating the need for post-processing entirely.
- **Dynamic multi-site loop templating**: The `nginx-multisite` cookbook iterates over `node['nginx']['sites']` to create document root directories, deploy static content, generate SSL certificates, and create virtual host configs. In Ansible, this maps to a `loop:` over a `nginx_sites` list variable, with `ansible.builtin.file`, `ansible.builtin.copy`, `community.crypto.*`, and `ansible.builtin.template` tasks. The ERB template `site.conf.erb` must be converted to a Jinja2 template (`site.conf.j2`).
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` resource (`cookbooks/nginx-multisite/resources/lineinfile.rb`) that replicates Ansible's built-in `ansible.builtin.lineinfile` module behavior (match-and-replace or append, with backup). This maps directly and trivially to `ansible.builtin.lineinfile` — no custom logic needed.
- **PostgreSQL idempotent provisioning**: The `fastapi-tutorial` recipe uses `sudo -u postgres psql -c "..." || true` shell commands for database and user creation. These are not truly idempotent (the `|| true` masks errors). In Ansible, replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **Git-based application deployment**: The `git` Chef resource syncs `https://github.com/dibanez/fastapi_tutorial.git` at branch `main`. In Ansible, use `ansible.builtin.git` with `version: main` and `update: yes`. The `creates:` guard on the venv creation and the pip install must be made idempotent using `ansible.builtin.stat` checks or the `creates:` parameter of `ansible.builtin.command`.
- **`systemctl daemon-reload` notification**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` after writing the systemd unit file. In Ansible, use the `ansible.builtin.systemd` module with `daemon_reload: yes` in a handler triggered by the unit file template task.
- **`www-data` vs. `nginx` user**: The `nginx.rb` recipe sets document root ownership to `www-data:www-data`, which is the Debian/Ubuntu nginx user. On Fedora/RHEL, the nginx user is `nginx`. The Ansible role must set the web user via a variable defaulting per `ansible_os_family`.
- **Attribute precedence and `solo.json` overrides**: The `solo.json` file overrides the cookbook's `attributes/default.rb` values (e.g., document roots change from `/opt/server/*` to `/var/www/*`). In Ansible, this maps to `group_vars` or `host_vars` overriding role defaults. Both sets of paths must be reconciled and a single canonical variable source established.

### Migration Order

1. **`nginx-multisite` cookbook** — Migrate first as it is the most complex cookbook and establishes the foundational web server, security hardening, and SSL infrastructure that the other services depend on for exposure. Decompose into sub-roles: `nginx_base` (install + nginx.conf), `nginx_ssl` (certificate generation), `nginx_sites` (virtual host templating), `nginx_security` (fail2ban + ufw/firewalld + sysctl + SSH hardening). Validate with the Vagrant environment before proceeding.

2. **`cache` cookbook** — Migrate second as it is independent of `nginx-multisite` and `fastapi-tutorial`. Use `geerlingguy.redis` and `geerlingguy.memcached` Galaxy roles as a base, overriding variables for the Redis password (from Ansible Vault) and port. Eliminate the `ruby_block` config-patching hack by using a clean role-managed `redis.conf`. Validate Redis authentication and Memcached availability before proceeding.

3. **`fastapi-tutorial` cookbook** — Migrate last as it has the most hardcoded secrets, depends on PostgreSQL (which must be running), and involves the most complex idempotency challenges (git sync, venv, pip, DB provisioning). Create a dedicated `fastapi` system user, migrate credentials to Ansible Vault, use `community.postgresql` collection modules for DB provisioning, and deploy the systemd unit via `ansible.builtin.template` + `ansible.builtin.systemd` handler.

### Assumptions

1. **Target OS for production**: The Vagrantfile specifies Fedora 42, but cookbook metadata declares Ubuntu 18.04+ and CentOS 7+ support. It is assumed that the **primary production target is a RHEL-family OS (Fedora/CentOS/RHEL)**. If Ubuntu is also a target, the Ansible roles must implement `ansible_os_family`-based conditionals for package names, firewall tools (`ufw` vs. `firewalld`), and web server user (`www-data` vs. `nginx`).
2. **UFW on Fedora is non-functional**: The current `security.rb` recipe installs and configures `ufw` on what is effectively a Fedora host (per Vagrantfile). It is assumed this is a known gap in the Chef code and that the Ansible migration will correctly use `firewalld` on Fedora/RHEL targets.
3. **Self-signed certificates are acceptable for all current environments**: No CA-signed certificate workflow (e.g., Let's Encrypt, internal PKI) is present. It is assumed self-signed certificates remain acceptable for the migrated Ansible environment, with production certificate management deferred to a future phase.
4. **The FastAPI GitHub repository remains publicly accessible**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git`. It is assumed this repository will remain available and that the `main` branch is the correct deployment target. If the repository becomes private, an SSH deploy key or token must be added to Ansible Vault.
5. **Redis and Memcached are single-node, no clustering**: The `cache` cookbook configures a single Redis instance on port 6379 and a single Memcached instance. No replication, Sentinel, or Cluster configuration is present. It is assumed this single-node topology is intentional and will be preserved in Ansible.
6. **The `ssl_certificate` Supermarket cookbook is not actively used**: It is present in `Policyfile.rb` and `Policyfile.lock.json` but commented out in `Berksfile` and not referenced in any recipe. It is assumed this dependency is vestigial and will not be migrated.
7. **Document root path discrepancy is intentional per environment**: `attributes/default.rb` sets document roots to `/opt/server/{site}` while `solo.json` overrides them to `/var/www/{site}`. It is assumed `/var/www/{site}` is the correct path for the Vagrant/development environment and that the Ansible `group_vars` will canonicalize this per environment (dev vs. production).
8. **The `fastapi-tutorial` service running as `root` is a known issue**: The systemd unit sets `User=root`. It is assumed the migration is an opportunity to correct this to a dedicated `fastapi` service account, and that no application-level assumption depends on running as root.
9. **Ansible Vault will be used for all secrets**: It is assumed the team will adopt Ansible Vault for the three identified credentials (Redis password, PostgreSQL user password, PostgreSQL DATABASE_URL). The existing plaintext passwords must be rotated as part of the migration process.
10. **Chef Solo (no Chef Server)**: The infrastructure uses `chef-solo` with a local `solo.json` node file — there is no Chef Server, Ohai data, or encrypted data bags in use. This simplifies migration as there are no server-side constructs (roles, environments, data bags) to translate beyond what is in the local files.
11. **The `selinux` cookbook (transitive dependency of `redisio`) is not explicitly configured**: No SELinux policy customizations are present in the local cookbooks. It is assumed SELinux is either permissive or that the `redisio` cookbook's transitive `selinux` dependency handles any required boolean/context changes. The Ansible migration should verify SELinux status on RHEL/Fedora targets and apply `ansible.posix.seboolean` for Redis as needed.
