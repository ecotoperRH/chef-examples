# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-site web server environment composed of three cookbooks: an Nginx reverse proxy with multi-site SSL hosting and security hardening, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL. The run list is `nginx-multisite::default → cache::default → fastapi-tutorial::default`, executed via `chef-solo` inside a Vagrant-managed Fedora 42 VM running on libvirt/KVM.

The migration is of **medium complexity**. All three cookbooks follow conventional Chef patterns (package/template/service/execute resources) that map cleanly to Ansible equivalents. The most notable friction points are: a hardcoded Redis password in a recipe, hardcoded PostgreSQL credentials written to a `.env` file, a `ruby_block` workaround that patches the Redis config post-install, a custom `lineinfile` LWRP that duplicates a native Ansible module, and the use of four upstream Supermarket cookbooks (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`) that must each be replaced with Ansible roles or built-in modules.

**Estimated migration effort: 3–4 weeks** for a single engineer, including testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation per vhost, a global security hardening layer (fail2ban with four jails, UFW firewall, kernel sysctl hardening), and per-site static HTML content deployment
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Multi-vhost Nginx config via ERB templates, HTTP→HTTPS redirect, TLS 1.2/1.3 with strong cipher suite, HSTS + security response headers (X-Frame-Options, CSP, X-Content-Type-Options), per-site access/error logs, fail2ban jails for sshd / nginx-http-auth / nginx-limit-req / nginx-botsearch, UFW default-deny with SSH/80/443 allow rules, sysctl IP-spoofing and SYN-flood protections, SSH root login and password authentication disabled, custom `lineinfile` LWRP

- **cache**:
  - Description: Dual in-memory caching services — Memcached (delegated entirely to the upstream `memcached 6.1.0` Supermarket cookbook) and Redis 6379 with password authentication, a dedicated `/var/log/redis` directory, and a post-install `ruby_block` hack that strips deprecated `replica-*` directives from the generated `/etc/redis/6379.conf`
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached via upstream cookbook, Redis via `redisio 7.2.4` cookbook with `requirepass` set to a hardcoded password (`redis_secure_password_123`), `redisio::enable` for systemd service activation, config-file post-processing workaround for deprecated Redis directives, transitive dependency on `selinux 6.2.4` cookbook (pulled in by redisio)

- **fastapi-tutorial**:
  - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, running inside a Python virtual environment under systemd, backed by a locally-provisioned PostgreSQL database with a dedicated user and database, and configured via a `.env` file containing hardcoded database credentials
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: System package installation (python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev), `git` resource syncing `https://github.com/dibanez/fastapi_tutorial.git` at `main`, Python venv creation + `pip install -r requirements.txt`, PostgreSQL service enable/start, `psql` shell commands to create role `fastapi` (password: `fastapi_password`) and database `fastapi_db`, `.env` file with `DATABASE_URL` containing plaintext credentials, systemd unit file for `uvicorn` on port 8000, `systemctl daemon-reload` handler

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest; declares all three local cookbooks plus four upstream Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note `ssl_certificate` is commented out here but active in the Policyfile). Not needed in Ansible; replaced by `requirements.yml` for Galaxy roles.
- `Policyfile.rb`: Chef Policyfile defining the policy name, run list, and version constraints. The Ansible equivalent is a `site.yml` playbook with an ordered role list.
- `Policyfile.lock.json`: Pinned dependency graph including transitive dependencies (`selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the authoritative version reference when selecting equivalent Ansible Galaxy roles.
- `solo.json` (root): Chef Solo node JSON; overrides default attributes for site document roots (`/var/www/<site>`), SSL paths, and security flags. These values become Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo runtime config pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks`. No Ansible equivalent needed.
- `Vagrantfile`: Provisions a `generic/fedora42` VM via libvirt with 2 vCPUs / 2 GB RAM, private IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync-mounts the repo to `/chef-repo`, and calls `vagrant-provision.sh`. The VM definition is reusable as-is for Ansible testing; only the provisioner block changes.
- `vagrant-provision.sh`: Bash bootstrap that installs Chef via the Omnitruck script, installs Berkshelf as a Chef embedded gem, runs `berks vendor`, and invokes `chef-solo`. In the Ansible world this is replaced by Vagrant's built-in `ansible_local` or `ansible` provisioner pointing at a `site.yml` playbook.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `Policyfile.lock.json` copy, `generated-project-metadata.json` (structured module inventory), and a prior draft `migration-plan.md`. These are tooling artefacts and do not need to be migrated.
- `project-plan.md`: X2Ansible tool specification document. Not part of the infrastructure; no migration action required.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` (Fedora Linux 42) as the primary development target. The cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`, indicating the intended production targets are Debian/Ubuntu or RHEL/CentOS family hosts. Ansible roles should be written to support both families using `ansible_os_family` conditionals. Default to **Red Hat Enterprise Linux 9 / Fedora** for primary testing given the Vagrant box choice.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"` with title `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Supermarket)**: Replace with the `nginxinc.nginx` Ansible Galaxy role or the community `geerlingguy.nginx` role. Alternatively, implement directly using `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service` — which is straightforward given the cookbook only uses a standard `nginx.conf` and per-site `sites-available/` configs. The ERB templates translate directly to Jinja2.
- **memcached (6.1.0, Supermarket)**: Replace with `geerlingguy.memcached` Galaxy role or a simple `package` + `service` task pair. The upstream cookbook is used without any attribute overrides, so the Ansible equivalent is minimal.
- **redisio (7.2.4, Supermarket)**: Replace with `geerlingguy.redis` Galaxy role. The only custom attribute is `requirepass`; map this to the role's `redis_requirepass` variable, stored in Ansible Vault. The `ruby_block` config-patching hack (stripping deprecated `replica-*` directives) must be replicated using `ansible.builtin.lineinfile` with `state: absent` or a clean Jinja2 template that never emits those directives — the latter is strongly preferred.
- **ssl_certificate (2.1.0, Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` collection. The current usage generates self-signed certificates per vhost with a fixed 365-day validity and `rsa:2048` key.
- **selinux (6.2.4, Supermarket)**: Transitive dependency of redisio. Replace with `ansible.posix.selinux` module if the target is RHEL/Fedora. On Ubuntu targets this is a no-op.

### Security Considerations

- **Hardcoded Redis password**: `cookbooks/cache/recipes/default.rb` sets `requirepass` to the literal string `redis_secure_password_123` directly in the recipe. This credential must be extracted and stored in **Ansible Vault** as `vault_redis_requirepass`. The plaintext value must be rotated before or during migration. **1 hardcoded credential detected in this module.**
- **Hardcoded PostgreSQL credentials**: `cookbooks/fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` in both the `psql` shell commands and the `.env` file content. The `.env` file is written with mode `0644` (world-readable), which is a security defect. In Ansible, the password must be stored in Vault as `vault_fastapi_db_password`, the `.env` file template must use mode `0600`, and ownership should be changed from `root:root` to the application service user. **2 hardcoded credential instances detected in this module.**
- **Self-signed TLS certificates**: All three vhosts use `openssl req -x509` to generate self-signed certificates stored in `/etc/ssl/certs` and `/etc/ssl/private`. The private key directory is `0710 root:ssl-cert`. This is appropriate for development but must be flagged for production: replace with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA. The `ssl-cert` group creation and key file permissions (`640 root:ssl-cert`) must be preserved in the Ansible role.
- **SSH hardening**: `security.rb` disables root login and password authentication via `sed` on `/etc/ssh/sshd_config`. In Ansible, use `ansible.builtin.lineinfile` or the `devsec.hardening.ssh_hardening` Galaxy role. Ensure the Ansible control node has a valid SSH key deployed before applying these changes, or the playbook will lock itself out.
- **UFW firewall**: Managed via `execute` resources running `ufw` CLI commands. Replace with `community.general.ufw` module. Note: UFW is Debian/Ubuntu-specific; for RHEL/Fedora targets use `ansible.posix.firewalld` instead. A conditional block per `ansible_os_family` is required.
- **fail2ban**: Configured via a template (`fail2ban.jail.local.erb`) with four jails. Migrate the template to Jinja2 (`fail2ban.jail.local.j2`) and deploy with `ansible.builtin.template`. The `fail2ban` package name is consistent across Debian and RHEL families.
- **sysctl kernel hardening**: `sysctl-security.conf.erb` sets 15 kernel parameters covering IP spoofing, ICMP redirect, source routing, martian logging, ICMP echo suppression, and SYN-flood protection. Replace with `ansible.posix.sysctl` module tasks (one per parameter) or deploy the file via `ansible.builtin.template` to `/etc/sysctl.d/99-security.conf` and notify a `sysctl -p` handler.
- **FastAPI service running as root**: The systemd unit file sets `User=root`. This is a significant security risk and should be corrected during migration by creating a dedicated `fastapi` system user and updating `WorkingDirectory`, `ExecStart`, and file ownership accordingly.
- **No secrets management currently in use**: The repository contains no Chef Vault, encrypted data bags, or environment variable injection for secrets. All credentials are plaintext in recipe files and node JSON. Ansible Vault must be introduced as part of this migration for all credentials identified above.

### Technical Challenges

- **`ruby_block` Redis config patching**: The `fix_redis_config` block in `cache::default` reads `/etc/redis/6379.conf` after `redisio` writes it and strips five deprecated directive patterns using regex substitution. This is a workaround for an outdated `redisio` cookbook generating config keys that the installed Redis version no longer accepts. In Ansible, the cleanest solution is to use a `geerlingguy.redis` role version that supports the target Redis version natively, or to supply a fully-managed Jinja2 template for `redis.conf` that never emits the deprecated directives. Using `ansible.builtin.lineinfile` with `regexp` + `state: absent` is a viable but fragile fallback.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom resource that replicates `ansible.builtin.lineinfile` behaviour (match-and-replace or append, with timestamped backup). This resource is not called anywhere in the current recipes (it appears to be a utility resource for future use), but it maps directly to the native Ansible module and requires no special migration effort beyond removal.
- **Attribute precedence and `solo.json` overrides**: The `solo.json` at the repo root overrides `document_root` values from `attributes/default.rb` (e.g., `/var/www/test.cluster.local` vs. `/opt/server/test`). There is also a second `solo.json` inside the `.myprj` directory with the same overrides. The canonical values must be determined before writing Ansible `group_vars`. The discrepancy between the two `solo.json` files (both use `/var/www/<site>`) and `attributes/default.rb` (uses `/opt/server/<site>`) must be resolved — the `solo.json` runtime values take precedence in Chef, so `/var/www/<site>` is the effective path.
- **Multi-platform support**: The cookbooks declare support for both Ubuntu ≥ 18.04 and CentOS ≥ 7, but the Vagrant environment uses Fedora 42. UFW is not available on Fedora (use `firewalld`); the `www-data` user/group does not exist on Fedora (use `nginx`); `apt-get` references in `vagrant-provision.sh` will fail on Fedora. Ansible roles must use `ansible_os_family` / `ansible_distribution` conditionals throughout.
- **Git-based application deployment**: `fastapi-tutorial` clones from `https://github.com/dibanez/fastapi_tutorial.git` at the `main` branch with `action :sync`. The `ansible.builtin.git` module is a direct equivalent, but the `version: main` + `force: yes` combination should be used carefully in production to avoid overwriting local changes. A pinned commit SHA or tag is recommended.
- **`pip install` idempotency**: The `execute 'install_dependencies'` resource runs unconditionally on every Chef run (`action :run`). In Ansible, `ansible.builtin.pip` with `requirements: /opt/fastapi-tutorial/requirements.txt` and `virtualenv:` is idempotent by default and is the correct replacement.
- **PostgreSQL initialisation**: The `create_db_user` execute block uses `|| true` to suppress errors on re-runs, which is a fragile idempotency pattern. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **`systemctl daemon-reload` handler ordering**: The Chef recipe notifies `execute[systemd_reload]` with `:immediately`, meaning the reload happens inline before the service resource. Ansible's `ansible.builtin.systemd` module with `daemon_reload: yes` in a handler achieves the same effect; ensure the handler is flushed before the service start task using `meta: flush_handlers` if needed.
- **Vagrant provisioner replacement**: `vagrant-provision.sh` installs Chef via Omnitruck and runs Berkshelf — both are unnecessary in the Ansible world. The `Vagrantfile` should be updated to use `config.vm.provision "ansible_local"` (or `"ansible"`) pointing to `site.yml`, removing the shell provisioner entirely.

### Migration Order

1. **`nginx-multisite` → Ansible role `nginx_multisite`** *(Week 1–2)*
   This cookbook is the most self-contained and delivers the highest visible value. It has no dependencies on the other two cookbooks. Begin here to establish the Ansible project skeleton (`ansible/`, `roles/`, `group_vars/`, `inventory/`), validate the Vagrant+Ansible workflow, and confirm template rendering for all five ERB→Jinja2 conversions. Implement the `community.crypto` SSL tasks and the `community.general.ufw` / `ansible.posix.firewalld` conditional firewall block. Migrate the fail2ban and sysctl hardening tasks. Validate all three vhosts are reachable over HTTPS with the expected security headers.

2. **`cache` → Ansible role `cache`** *(Week 2–3)*
   Memcached is trivial (package + service). Redis requires Vault integration for the password and a clean resolution of the deprecated-directive problem. Introduce `ansible-vault` at this stage and encrypt `vault_redis_requirepass`. Validate Redis authentication with `redis-cli -a`.

3. **`fastapi-tutorial` → Ansible role `fastapi_tutorial`** *(Week 3–4)*
   Highest complexity due to PostgreSQL provisioning, Python venv management, git deployment, systemd unit, and the most sensitive credentials. Introduce `vault_fastapi_db_password`, fix the `.env` file permissions, create a dedicated `fastapi` system user, and validate the full application stack end-to-end (PostgreSQL → FastAPI → HTTP 200 on port 8000).

### Assumptions

1. **Fedora 42 is the primary target OS** for the Vagrant development environment. Production targets are assumed to be RHEL 9 or Ubuntu 22.04 LTS based on cookbook metadata declarations; this must be confirmed with the infrastructure team before writing OS-family conditionals.
2. **Self-signed certificates are acceptable for all current environments.** If any of the three vhosts (`test`, `ci`, `status`) are exposed beyond the local Vagrant network, proper CA-signed or Let's Encrypt certificates will be required and the SSL role must be extended accordingly.
3. **The FastAPI GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) remains publicly accessible** and its `requirements.txt` is compatible with the Python version available on the target OS. If the repo becomes private, an SSH deploy key must be provisioned.
4. **No Redis clustering or Sentinel is required.** The current configuration is a single-node Redis instance on the default port 6379. If HA is needed, the role design will need to change significantly.
5. **No Memcached clustering is required.** Memcached is deployed as a single local instance with default settings; no custom `memcached.conf` attributes are overridden.
6. **The `ssl-cert` group and `/etc/ssl/private` directory with mode `0710`** are the intended permission model for private keys. This will be preserved in the Ansible role.
7. **The document root discrepancy between `attributes/default.rb` (`/opt/server/<site>`) and `solo.json` (`/var/www/<site>`) is intentional** — `solo.json` represents the runtime-overridden values and `/var/www/<site>` is the effective path. The Ansible `group_vars` will use `/var/www/<site>` as the default, with the `/opt/server/<site>` path available as a commented alternative.
8. **The `www-data` user/group** referenced in `nginx.rb` for document root ownership is Debian/Ubuntu-specific. On Fedora/RHEL the correct user is `nginx`. An `ansible_os_family`-based variable is required.
9. **Ansible Vault will be used for all secrets.** No external secrets manager (HashiCorp Vault, AWS Secrets Manager, etc.) is assumed. If the team uses an external secrets backend, the Vault variable references in the roles will need to be adapted to use the appropriate Ansible lookup plugin.
10. **The custom `lineinfile` LWRP** in `cookbooks/nginx-multisite/resources/lineinfile.rb` is not called by any recipe in this repository. It is assumed to be dead code and will not be migrated; the native `ansible.builtin.lineinfile` module covers its functionality.
11. **`vagrant-provision.sh` uses `apt-get`**, which is incompatible with the declared `generic/fedora42` Vagrant box. It is assumed this script was written for a Debian-based box and the Fedora box was adopted later without updating the script. The Ansible migration will resolve this inconsistency by replacing the shell provisioner entirely.
12. **The FastAPI application runs on port 8000** and is not currently fronted by Nginx as a reverse proxy (no upstream proxy block exists in the Nginx templates). If proxying FastAPI through Nginx is desired, an additional `location /` proxy block must be added to `site.conf.j2` — this is out of scope for the current migration unless explicitly requested.
13. **The `selinux` cookbook** is a transitive dependency of `redisio` and is not explicitly configured. It is assumed SELinux is either permissive or disabled on the target hosts, consistent with a development-focused environment. If enforcing mode is required on RHEL/Fedora targets, `ansible.posix.selinux` and appropriate SELinux boolean/context tasks must be added to the Redis role.
