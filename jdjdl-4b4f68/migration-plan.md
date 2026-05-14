# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure stack (`nginx-multisite-policy`) composed of **3 local cookbooks** and **5 external Supermarket dependencies**, all managed via Chef Policyfile and Berkshelf. The stack provisions a single node running: a hardened Nginx reverse proxy serving three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a dual caching layer (Memcached + Redis with password authentication), and a Python FastAPI application backed by PostgreSQL, deployed from a public Git repository.

The development environment is a Fedora 42 Vagrant VM running on libvirt, provisioned via `chef-solo`. The Chef run list is strictly sequential: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`.

**Migration complexity: Medium.** All three cookbooks use standard Chef resources (`package`, `template`, `service`, `execute`, `directory`, `file`, `git`) that map cleanly to Ansible built-in modules. The most notable complications are: a hardcoded Redis password in a Chef attribute, hardcoded PostgreSQL credentials written to a `.env` file, a `ruby_block` workaround patching the Redis config post-install, a custom `lineinfile` Chef resource that duplicates native Ansible functionality, and a discrepancy between document root paths defined in `attributes/default.rb` vs. `solo.json`. No Chef Server, encrypted data bags, or Chef Vault are in use — secrets are stored in plaintext.

**Estimated migration timeline: 3–4 weeks** for a single engineer, including testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed certificate generation via OpenSSL, security hardening via fail2ban and UFW firewall, SSH daemon hardening, and kernel-level network security via sysctl tuning
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Multi-site virtual host configuration driven by a node attribute hash (`node['nginx']['sites']`), making the number of sites fully data-driven
        - Per-site self-signed TLS certificates generated with `openssl req -x509 -nodes -days 365 -newkey rsa:2048`; certificates stored under `/etc/ssl/certs/` and private keys under `/etc/ssl/private/` with `0710` permissions and `ssl-cert` group ownership
        - Nginx security hardening via a dedicated `conf.d/security.conf`: `server_tokens off`, rate-limiting zones (`limit_req_zone`), buffer overflow protections, TLS 1.2/1.3 only with strong cipher suites
        - Per-site virtual host templates enforcing HTTP→HTTPS redirect, HSTS (`max-age=31536000; includeSubDomains`), and security response headers (`X-Frame-Options DENY`, `X-Content-Type-Options nosniff`, `X-XSS-Protection`, `Content-Security-Policy`, `Referrer-Policy`)
        - fail2ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`; ban time 3600s, max retry 3
        - UFW firewall: default deny, allow SSH/HTTP/HTTPS
        - SSH daemon hardening: `PermitRootLogin no`, `PasswordAuthentication no` applied via `sed` with idempotency guards
        - sysctl hardening: IP spoofing protection, ICMP redirect rejection, source routing disabled, martian logging, SYN flood protection (`tcp_syncookies`), IPv6 disabled
        - Custom `lineinfile` Chef resource (`resources/lineinfile.rb`) that reimplements Ansible's native `lineinfile` module
        - Static HTML content files for each site (`files/default/{test,ci,status}/index.html`) deployed to document roots

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, including a post-install config-patching workaround for deprecated Redis directives
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Memcached installed and configured via the upstream `memcached` community cookbook (v6.1.0); no local attribute overrides applied
        - Redis configured via `redisio` (v7.2.4) on port 6379 with `requirepass redis_secure_password_123` set as a node attribute in plaintext
        - Redis log directory `/var/log/redis` created with `redis:redis` ownership
        - `ruby_block "fix_redis_config"` post-processes `/etc/redis/6379.conf` to strip deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the `redisio` cookbook writes but the installed Redis version rejects — this workaround must be replicated in Ansible
        - `redisio::enable` recipe called to create and enable the Redis systemd service
        - Transitive dependency on `selinux` cookbook (v6.2.4) pulled in by `redisio`

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, with PostgreSQL database provisioning, Python virtual environment setup, dependency installation, and systemd service management
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - System packages installed: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Application source cloned from `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial` using Chef `git` resource with `action :sync`
        - Python virtual environment created at `/opt/fastapi-tutorial/venv`; dependencies installed from `requirements.txt` via `pip`
        - PostgreSQL service enabled and started; database user `fastapi` created with password `fastapi_password` (plaintext); database `fastapi_db` created and all privileges granted — all via `sudo -u postgres psql` shell commands with `|| true` guards
        - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` in plaintext with `0644` permissions owned by root
        - systemd unit file written to `/etc/systemd/system/fastapi-tutorial.service`; service runs as `root`, starts `uvicorn app.main:app --host 0.0.0.0 --port 8000`, restarts always
        - `systemctl daemon-reload` triggered immediately on unit file change; service enabled and started

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest; declares all 3 local cookbooks by path and 3 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). The `ssl_certificate ~> 2.1` entry is commented out in the Berksfile but **active** in `Policyfile.rb` and resolved in `Policyfile.lock.json` — this inconsistency should be resolved before migration.
- `Policyfile.rb`: Defines the `nginx-multisite-policy` policy, the canonical run list, and all cookbook version constraints including `ssl_certificate ~> 2.1`. This is the authoritative dependency source.
- `Policyfile.lock.json`: Fully resolved and pinned dependency graph. Locked versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. Serves as the reference for exact versions to replicate in Ansible.
- `solo.json`: Chef Solo node JSON; overrides site document roots to `/var/www/<site>` (conflicting with `attributes/default.rb` which sets `/opt/server/<site>`), and sets security flags. This file is the **runtime source of truth** for attribute values and must be used as the basis for Ansible `group_vars`.
- `solo.rb`: Chef Solo runtime configuration; sets `file_cache_path`, `cookbook_path`, log level. No migration value — replaced by Ansible's own execution model.
- `Vagrantfile`: Provisions a `generic/fedora42` VM via libvirt with 2 vCPUs, 2 GB RAM, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443. Rsync-based folder sync to `/chef-repo`. The commented-out `/etc/hosts` block and the commented-out `chef_solo` provisioner block indicate in-progress development. The Vagrant environment should be adapted to use `ansible_local` or a remote Ansible provisioner for post-migration testing.
- `vagrant-provision.sh`: Bootstrap script that installs Chef via the Omnitruck script, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, then executes `chef-solo`. This entire script is replaced by Ansible's agentless execution model.
- `x2a-rules/ccfbfee9-dc46-4256-a7b8-5ecd5eaaa779.md`: **Organisation policy rules that apply to this migration.** Two mandatory constraints: (1) Only collections from the `edb.*` namespace are approved for production use — community collections require SRE review; (2) All migrated projects must fetch SSH authorized keys from `https://github.com/eloycoto.keys` and place them in `/opt/allowed_keys/` on every deployment (keys must not be baked into images).

---

### Target Details

- **Operating System**: Fedora 42 is the active development target (specified in `Vagrantfile`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The provisioning script uses `apt-get`, indicating the Vagrant bootstrap targets a Debian-family OS — this is inconsistent with the Fedora box and must be resolved. For Ansible, the roles should be written to support both Debian/Ubuntu (using `apt`, `ufw`) and RHEL/Fedora (using `dnf`, `firewalld`) via `ansible_os_family` conditionals.
- **Virtual Machine Technology**: libvirt / KVM (explicitly set as the Vagrant provider: `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present. The infrastructure appears designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community Chef nginx cookbook handles installation, service management, and basic configuration. Replace with Ansible's built-in `ansible.builtin.package` + `ansible.builtin.service` modules and Jinja2 templates for `nginx.conf` and per-site configs. The existing `.erb` templates translate directly to Jinja2 with minimal syntax changes (`<%= @var %>` → `{{ var }}`). No external Ansible collection required.
- **memcached (6.1.0, Chef Supermarket)**: Handles package install and service enable/start. Replace with `ansible.builtin.package` and `ansible.builtin.service`. No complex configuration is applied locally — the cookbook defaults are used as-is.
- **redisio (7.2.4, Chef Supermarket)**: Handles Redis package install, config file generation, and service management. Replace with `ansible.builtin.package`, `ansible.builtin.template` for `/etc/redis/6379.conf`, and `ansible.builtin.service`. The `ruby_block` config-patching workaround must be replicated using `ansible.builtin.lineinfile` (with `state: absent` or `regexp`-based replacement) to strip the deprecated directives after the config file is written.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Referenced in `Policyfile.rb` and resolved in the lock file, but no explicit `include_recipe 'ssl_certificate'` call was found in any local recipe — the cookbook appears to be a transitive or reserved dependency. Self-signed certificate generation is handled directly in `nginx-multisite::ssl` via `openssl` shell commands. Replace with `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey` modules — note these are **not** in the `edb.*` namespace and require SRE review per `x2a-rules`. Alternatively, implement using `ansible.builtin.command` with `openssl req` to avoid the collection approval requirement.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. On Fedora/RHEL targets, SELinux policy management will be needed for Redis and Nginx. Use `ansible.posix.selinux` or `ansible.builtin.command` with `setsebool`/`semanage` as appropriate. The `ansible.posix` collection requires SRE review per org policy.

### Security Considerations

- **Hardcoded Redis password**: `requirepass redis_secure_password_123` is set as a plaintext Chef node attribute in `cookbooks/cache/recipes/default.rb`. This credential must be moved to **Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable (e.g., `vault_redis_password`). **1 credential detected.**
- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial` recipe hardcodes `fastapi_password` in three places: the `psql` provisioning command, the `.env` file content, and implicitly in the `DATABASE_URL`. All three must be replaced with a single Ansible Vault variable (e.g., `vault_fastapi_db_password`). The `.env` file template must use `mode: '0600'` (not `0644` as currently set) and should be owned by the service account, not root. **1 credential (used in 3 locations) detected.**
- **SSL private key permissions**: The `ssl.rb` recipe sets private key permissions to `0640` with `root:ssl-cert` ownership. This must be preserved exactly in the Ansible equivalent using `ansible.builtin.file` with `owner: root`, `group: ssl-cert`, `mode: '0640'`.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` commands. Replace with `ansible.builtin.lineinfile` tasks targeting `/etc/ssh/sshd_config`, with a handler to restart the `sshd` service. Ensure the Ansible control connection is not broken by these changes (use key-based auth before applying).
- **UFW firewall**: The `security.rb` recipe uses `execute` resources with shell idempotency guards. Replace with the `community.general.ufw` module (requires SRE review) or `ansible.builtin.command` with `creates`/`changed_when` guards. On Fedora/RHEL, `firewalld` is the native alternative and uses `ansible.posix.firewalld`.
- **sysctl hardening**: 15 kernel parameters are set via a template to `/etc/sysctl.d/99-security.conf`. Replace with `ansible.posix.sysctl` module (one task per parameter, or loop) — requires SRE review — or deploy the file via `ansible.builtin.template` and run `sysctl -p` via a handler.
- **Authorized keys (org policy)**: Per `x2a-rules/ccfbfee9-dc46-4256-a7b8-5ecd5eaaa779.md`, every migrated project must fetch SSH keys from `https://github.com/eloycoto.keys` and place them in `/opt/allowed_keys/` on each deployment. This is **not present in the current Chef code** and must be added as a new task in the Ansible playbook using `ansible.builtin.get_url` + `ansible.builtin.copy` or `ansible.builtin.uri`.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a security risk and should be corrected during migration — create a dedicated `fastapi` system user and run the service under that account.
- **`.env` file world-readable**: `/opt/fastapi-tutorial/.env` is created with `mode '0644'`, exposing the database password to all local users. Change to `0600` in the Ansible equivalent.
- **Ansible collection approval**: Per org policy (`x2a-rules`), only `edb.*` collections are pre-approved. Collections such as `community.general`, `community.crypto`, and `ansible.posix` — all potentially useful for this migration — require explicit SRE review before use in production.

### Technical Challenges

- **Document root path inconsistency**: `cookbooks/nginx-multisite/attributes/default.rb` defines document roots as `/opt/server/{test,ci,status}`, while `solo.json` (the runtime node JSON) overrides them to `/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}`. Chef's attribute precedence means `solo.json` wins at runtime. The Ansible `group_vars` must use the `solo.json` values (`/var/www/<site>`), and the static HTML files must be deployed to those paths. The attribute file paths are effectively dead code and should not be carried forward.
- **`ruby_block` Redis config patching**: The `fix_redis_config` block in `cache::default` post-processes the Redis config file to remove deprecated directives written by the `redisio` cookbook. In Ansible, since there is no upstream cookbook abstraction, the Redis config template can be written correctly from the start — the workaround becomes unnecessary if a custom Jinja2 template is used for `/etc/redis/6379.conf` instead of relying on a community role that generates the wrong config.
- **Custom `lineinfile` Chef resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements line-in-file editing with backup support. This maps directly to Ansible's built-in `ansible.builtin.lineinfile` module and requires no special handling — it is simply dropped.
- **`apt-get` in `vagrant-provision.sh` vs. Fedora target**: The bootstrap script calls `apt-get update` and `apt-get install -y build-essential`, which will fail on Fedora 42 (which uses `dnf`). This suggests the Vagrant box may have been changed from Ubuntu to Fedora without updating the provisioning script, or the script is only used for bootstrapping Chef and the cookbooks themselves handle OS differences. The Ansible playbook must explicitly handle package manager differences using `ansible_pkg_mgr` or `ansible_os_family` conditionals.
- **SELinux on Fedora**: Fedora 42 ships with SELinux enforcing by default. The `redisio` cookbook pulls in the `selinux` Chef cookbook as a dependency, indicating SELinux policy adjustments are expected. Nginx serving from non-standard document roots and Redis binding to its port will require SELinux boolean/context adjustments (`httpd_can_network_connect`, file contexts for `/var/www/*`). These must be explicitly handled in Ansible tasks.
- **FastAPI application availability**: The application is cloned from `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch. The Ansible `ansible.builtin.git` module with `version: main` and `update: yes` replicates `action :sync`. However, if the repository is private or the branch is renamed, the deployment will fail. A fallback or version pin should be considered.
- **Service ordering**: The FastAPI systemd unit declares `After=postgresql.service`, but Chef does not enforce cross-cookbook service ordering. In Ansible, task ordering within a play is explicit and sequential — PostgreSQL tasks must complete (including database/user creation) before the FastAPI service is started. This is naturally handled by Ansible's linear execution model.
- **Berksfile/Policyfile inconsistency**: `ssl_certificate` is commented out in `Berksfile` but active in `Policyfile.rb`. The lock file resolves it. This inconsistency should be documented and the Berksfile corrected before the Chef codebase is archived.
- **`www-data` user on Fedora**: The `nginx.rb` recipe sets Nginx document root ownership to `www-data:www-data`, which is the Debian/Ubuntu Nginx user. On Fedora/RHEL, the Nginx user is `nginx`. The Ansible role must use a variable (e.g., `nginx_user`) conditioned on `ansible_os_family`.

### Migration Order

1. **`nginx-multisite` cookbook — Security sub-component** (low risk, no external service dependencies): Migrate the `security.rb` recipe first. This covers fail2ban, UFW, SSH hardening, and sysctl. These are self-contained and establish the security baseline. Validate against the Vagrant VM before proceeding.

2. **`nginx-multisite` cookbook — Nginx + SSL + Sites sub-components** (moderate complexity, depends on security baseline): Migrate `nginx.rb`, `ssl.rb`, and `sites.rb` as a unit. Port the three `.erb` templates to Jinja2. Implement self-signed certificate generation. Deploy static HTML content files. Validate all three virtual hosts respond correctly over HTTPS with expected security headers.

3. **`cache` cookbook — Memcached** (low complexity, fully independent): Install and configure Memcached using `ansible.builtin.package` and `ansible.builtin.service`. No configuration overrides are applied, making this the simplest migration task.

4. **`cache` cookbook — Redis** (moderate complexity, credential handling required): Install Redis, write a correct Jinja2 config template (eliminating the `ruby_block` workaround), configure password authentication using an Ansible Vault variable, enable and start the service. Validate connectivity with `redis-cli -a <password> ping`.

5. **`fastapi-tutorial` cookbook** (highest complexity, depends on PostgreSQL + Python ecosystem + external Git repo): Migrate last due to the most dependencies. Create a dedicated `fastapi` system user. Install system packages, clone the repository, create the virtual environment, install Python dependencies, provision PostgreSQL (database + user with vaulted password), write the `.env` file with corrected permissions, deploy the systemd unit, and start the service. Validate the API is reachable on port 8000.

6. **Org policy additions** (mandatory, applies across all modules): Add a task (ideally in a shared `common` role run first) to fetch SSH authorized keys from `https://github.com/eloycoto.keys` and write them to `/opt/allowed_keys/` on every playbook run.

### Assumptions

1. **Runtime attribute values from `solo.json` take precedence** over `attributes/default.rb` defaults. The Ansible `group_vars` will be based on `solo.json` values (document roots at `/var/www/<site>`), treating the cookbook attribute defaults as development fallbacks that were overridden in practice.
2. **Self-signed certificates are acceptable** for the target environment. If this is a production migration, the SSL tasks should be replaced with Let's Encrypt (`certbot`) or an internal CA workflow. This is not inferable from the repository alone and must be confirmed with the team.
3. **The Vagrant/libvirt environment will be used for post-migration validation.** The `Vagrantfile` will need to be updated to use `ansible_local` or a remote Ansible provisioner in place of `vagrant-provision.sh`.
4. **The `apt-get` calls in `vagrant-provision.sh` are a bootstrap artifact** and do not reflect the actual target OS package manager. The Ansible playbook will use `dnf` for Fedora and `apt` for Ubuntu/Debian, conditioned on `ansible_os_family`.
5. **No Chef Server, encrypted data bags, or Chef Vault are in use.** All configuration is driven by `solo.json` and cookbook attributes. There are no server-side secrets to migrate — only the plaintext credentials in the recipes, which must be vaulted.
6. **The `ssl_certificate` community cookbook** (resolved in the lock file) is not explicitly invoked in any local recipe. It is assumed to be a transitive or reserved dependency and will not be directly migrated. Certificate generation will use the `openssl` CLI approach already present in `ssl.rb`.
7. **SELinux is enforcing on Fedora 42.** Ansible tasks must include appropriate SELinux context and boolean management. This is not handled in the current Chef code (beyond the transitive `selinux` cookbook dependency in `redisio`) and represents new work.
8. **The `edb.*` collection namespace restriction** (from `x2a-rules`) means that `community.general`, `community.crypto`, and `ansible.posix` collections — while functionally ideal for several tasks — require SRE approval before use. Where possible, tasks will be implemented using `ansible.builtin.*` modules and `ansible.builtin.command`/`ansible.builtin.shell` with idempotency guards as a fallback to avoid blocking on collection approvals.
9. **The FastAPI GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`) is assumed to remain publicly accessible** at the `main` branch. If the repository is private or the branch changes, the `ansible.builtin.git` task will require credential configuration or a branch variable override.
10. **The three virtual host sites (`test`, `ci`, `status`) are the complete set.** The data-driven nature of the Chef attributes (`node['nginx']['sites']` hash) means additional sites could be added at runtime. The Ansible equivalent should preserve this flexibility using a `nginx_sites` list variable in `group_vars`.
11. **The `www-data` Nginx user referenced in `nginx.rb`** is a Debian/Ubuntu convention. On Fedora, the correct user is `nginx`. The migration will parameterise this as `nginx_user` with an OS-family conditional.
12. **Running the FastAPI service as `root`** (as currently configured in the systemd unit) is considered a defect to be corrected during migration, not a requirement to preserve. A dedicated `fastapi` system user will be created.
13. **The authorised keys requirement** from `x2a-rules/ccfbfee9-dc46-4256-a7b8-5ecd5eaaa779.md` is a new addition not present in the Chef codebase. It is treated as a mandatory new task to be implemented in the Ansible migration, not an existing behaviour to replicate.
