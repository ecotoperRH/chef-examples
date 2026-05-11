# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through a Vagrant-managed Fedora 42 VM using `chef-solo`.

The overall migration complexity is **moderate**. The cookbooks are well-scoped, self-contained, and follow standard Chef patterns. The primary challenges are: replacing Chef community cookbooks (`nginx`, `memcached`, `redisio`) with native Ansible modules, migrating a custom `lineinfile` LWRP to the built-in `ansible.builtin.lineinfile` module, handling hardcoded credentials, and converting ERB templates to Jinja2.

**Estimated migration timeline: 5–8 working days** for a single experienced Ansible engineer, broken down as:
- `nginx-multisite` role: 2–3 days (most complex — 5 recipes, 5 templates, custom resource, security hardening)
- `cache` role: 1–2 days (Redis + Memcached, credential handling, config patching workaround)
- `fastapi-tutorial` role: 1–2 days (Python venv, PostgreSQL, systemd service, hardcoded secrets)
- Integration, testing, and inventory setup: 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that require individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server configured with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation via OpenSSL, HTTP-to-HTTPS redirect, security hardening via UFW firewall rules, Fail2Ban intrusion prevention (with jails for sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch), kernel-level network hardening via sysctl, and SSH hardening (root login disabled, password authentication disabled).
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Multi-recipe structure (default → security → nginx → ssl → sites), ERB-templated `nginx.conf` and per-site `site.conf`, rate-limiting zones (`login`, `api`), HSTS + full security header suite (X-Frame-Options, CSP, X-Content-Type-Options), custom `lineinfile` LWRP, per-site static `index.html` content files, `www-data` document root ownership, `ssl-cert` group for private key access control.

- **cache**:
  - Description: Caching layer configuration that installs and enables both Memcached (via the `memcached` community cookbook) and Redis (via the `redisio` community cookbook) with password authentication. Includes a `ruby_block` workaround to strip deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` after `redisio` writes it.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Redis on port 6379 with `requirepass` authentication, Memcached default configuration, post-write config patching via `ruby_block`, `/var/log/redis` directory ownership, `redisio::enable` for systemd service activation.

- **fastapi-tutorial**:
  - Description: Full-stack Python web application deployment that clones the `fastapi_tutorial` repository from GitHub, creates a Python 3 virtual environment, installs pip dependencies, configures a PostgreSQL database with a dedicated user and database, writes a `.env` file with database credentials, and registers a systemd service (`fastapi-tutorial.service`) running `uvicorn` on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Git clone from `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`), Python venv at `/opt/fastapi-tutorial/venv`, PostgreSQL user `fastapi` with hardcoded password, database `fastapi_db`, `.env` file with `DATABASE_URL`, systemd unit with `After=postgresql.service`, `uvicorn app.main:app --host 0.0.0.0 --port 8000`, service runs as `root` (security concern).

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local and external cookbook sources. References Chef Supermarket for `nginx (~> 12.0)`, `memcached (~> 6.0)`, and `redisio (~> 7.2.4)`. The `ssl_certificate` cookbook is commented out in this file but is active in `Policyfile.rb` and resolved in the lock file. Must be replaced by Ansible Galaxy `requirements.yml` or native module usage.
- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook versions. The Ansible equivalent is a `site.yml` playbook with role includes and a `requirements.yml` for Galaxy dependencies.
- `Policyfile.lock.json`: Resolved dependency lock file pinning exact versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. Serves as the authoritative reference for which community cookbook versions were in use and what transitive dependencies exist.
- `solo.json`: Chef Solo node JSON providing runtime attribute overrides — site definitions (document roots, SSL flags), SSL certificate/key paths, and security flags (fail2ban, ufw, SSH hardening). This maps directly to Ansible `group_vars/all.yml` or a host-specific `host_vars` file.
- `solo.rb`: Chef Solo configuration file setting `file_cache_path`, `cookbook_path`, log level, and log destination. No direct Ansible equivalent needed; replaced by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, `libvirt` provider (2 vCPU, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. The Ansible equivalent is an inventory file with `ansible_host=192.168.121.10` and a `vagrant` connection plugin or standard SSH inventory.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a gem, runs `berks vendor`, and executes `chef-solo`. In Ansible, this is replaced by running `ansible-playbook` directly against the Vagrant VM after configuring SSH access.
- `project-plan.md`: Internal tooling specification for the X2Ansible migration tool. Not part of the infrastructure being migrated; reference only.

---

### Target Details

- **Operating System**: Ubuntu (primary target, inferred from `www-data` user/group for Nginx document roots, `ufw` firewall tooling, `/var/log/auth.log` path in Fail2Ban jail config, `apt-get` usage in `vagrant-provision.sh`, and `supports 'ubuntu', '>= 18.04'` in all three `metadata.rb` files). CentOS ≥ 7.0 is also declared as supported in metadata. The Vagrant box is `generic/fedora42`, indicating the development environment diverges from the declared production target OS — this is a notable inconsistency to resolve. **Recommended Ansible target: Ubuntu 22.04 LTS** for production alignment; Fedora 42 for local Vagrant testing.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. VM title is `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references are present in any file.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook wrapping Nginx installation and service management. Replace with `ansible.builtin.package` (install `nginx`), `ansible.builtin.template` for `nginx.conf` and `security.conf`, `ansible.builtin.service` for enable/start, and `community.general` or native modules for site management. No Galaxy role required; all logic is straightforward.
- **memcached (6.1.0)** — Community cookbook for Memcached installation and service. Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service`. Default configuration is sufficient; no complex attributes are set in the `cache` cookbook.
- **redisio (7.2.4)** — Community cookbook for Redis installation, configuration file generation, and service management. Replace with `ansible.builtin.package` (install `redis-server`), `ansible.builtin.template` or `ansible.builtin.lineinfile` for `/etc/redis/6379.conf` (set `requirepass`, remove deprecated directives), and `ansible.builtin.service`. The `ruby_block` config-patching hack becomes unnecessary since Ansible gives direct control over the config file content.
- **ssl_certificate (2.1.0)** — Locked in `Policyfile.lock.json` but commented out in `Berksfile`; not directly called in any recipe. The `ssl.rb` recipe handles certificate generation inline via `openssl` CLI. No replacement needed beyond the `ansible.builtin.command` or `community.crypto.x509_certificate` module for self-signed cert generation.
- **selinux (6.2.4)** — Transitive dependency of `redisio`. Not directly invoked. In Ansible, SELinux management is handled natively via `ansible.posix.selinux` if the target is RHEL/Fedora. On Ubuntu (primary target), this dependency is irrelevant.

---

### Security Considerations

- **Hardcoded Redis password**: The `cache` cookbook hardcodes `requirepass redis_secure_password_123` directly in `recipes/default.rb` as a node attribute string. **Migration approach**: Extract to an Ansible Vault-encrypted variable (`vault_redis_password`) stored in `group_vars/all/vault.yml`. Reference as `{{ vault_redis_password }}` in the Redis config template.
  - *Credential count*: 1 hardcoded secret in `cache` cookbook.

- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial/recipes/default.rb` hardcodes the PostgreSQL user password (`fastapi_password`) in three places: the `psql` CREATE USER command, the `.env` file `DATABASE_URL`, and implicitly in the service environment. **Migration approach**: Extract to Ansible Vault (`vault_fastapi_db_password`). Use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules instead of raw `psql` shell commands. Render `.env` via `ansible.builtin.template` with the vaulted variable.
  - *Credential count*: 1 hardcoded DB password used in 3 locations in `fastapi-tutorial` cookbook.

- **FastAPI service running as root**: The systemd unit in `fastapi-tutorial` sets `User=root`. **Migration approach**: Create a dedicated `fastapi` system user and group; update the systemd unit template accordingly. Ensure `/opt/fastapi-tutorial` is owned by that user.

- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated at provision time via `openssl req -x509`. Certificates are stored at `/etc/ssl/certs/<site>.crt` and `/etc/ssl/private/<site>.key`. **Migration approach**: Use `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` Ansible modules for idempotent certificate generation. For production, replace with Let's Encrypt via `community.crypto.acme_certificate` or `certbot` role. The `ssl-cert` group and `0640` key permissions must be replicated in Ansible tasks.
  - *Credential count*: 3 self-signed certificate/key pairs (one per virtual host).

- **SSH hardening via `sed`**: `security.rb` uses raw `sed` commands to modify `/etc/ssh/sshd_config`. **Migration approach**: Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no`, with a handler to restart `sshd`. This is more idempotent and readable.

- **UFW firewall via shell commands**: `security.rb` uses `execute` resources with `ufw` CLI commands and `not_if` guards. **Migration approach**: Use `community.general.ufw` module for all firewall rules — default deny, allow SSH/HTTP/HTTPS — which is fully idempotent without shell guards.

- **Fail2Ban configuration**: Managed via an ERB template (`fail2ban.jail.local.erb`) with static content (no dynamic variables). **Migration approach**: Copy the template as a static Jinja2 template (no variable substitution needed) or use `ansible.builtin.copy` with the file content. Ensure the `fail2ban` service handler triggers a restart on config change.

- **Kernel sysctl hardening**: `sysctl-security.conf.erb` is a static file setting 15+ kernel parameters (IP spoofing protection, ICMP redirect blocking, IPv6 disable, SYN flood protection). **Migration approach**: Use `ansible.posix.sysctl` module for each parameter, or deploy the file via `ansible.builtin.template` and notify a `sysctl -p` handler. Note: disabling IPv6 globally (`net.ipv6.conf.all.disable_ipv6 = 1`) may conflict with some Ubuntu 22.04 system services — verify before applying.

- **No Chef Vault or encrypted data bags detected**: Secrets are stored as plaintext node attributes and inline strings. All must be migrated to Ansible Vault before production use.

---

### Technical Challenges

- **`ruby_block` config-patching workaround in `cache`**: The `redisio` cookbook generates a Redis config with deprecated directives that cause Redis to fail on newer versions. The `ruby_block "fix_redis_config"` strips these lines post-write. In Ansible, this is eliminated entirely by writing the Redis config directly via a template that only includes valid directives. However, the exact set of required Redis configuration options must be validated against the target Redis version on Ubuntu 22.04 (Redis 6.x or 7.x) before templating.

- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom Chef resource that mimics `ansible.builtin.lineinfile` behaviour (match-and-replace or append, with timestamped backup). This maps directly to `ansible.builtin.lineinfile` with `regexp` and `line` parameters. The backup behaviour (timestamped `.backup.<epoch>` files) is non-standard and should be evaluated — Ansible's `backup: yes` creates a single backup copy, not timestamped ones.

- **ERB → Jinja2 template conversion**: Five ERB templates must be converted to Jinja2:
  - `nginx.conf.erb` — static content, no variables; direct copy.
  - `security.conf.erb` — static content, no variables; direct copy.
  - `site.conf.erb` — uses `@server_name`, `@document_root`, `@ssl_enabled`, `@cert_file`, `@key_file`; straightforward Jinja2 variable substitution with `{% if ssl_enabled %}` block.
  - `fail2ban.jail.local.erb` — static content, no variables; direct copy.
  - `sysctl-security.conf.erb` — static content, no variables; direct copy.

- **Attribute precedence and `solo.json` overrides**: `solo.json` overrides the default document root paths defined in `attributes/default.rb` (e.g., default is `/opt/server/test` but `solo.json` sets `/var/www/test.cluster.local`). The Ansible equivalent must consolidate these into a single `group_vars` or `host_vars` file, clearly documenting which values are environment-specific overrides vs. defaults.

- **Vagrant box OS mismatch**: The Vagrant environment uses `generic/fedora42` but all cookbooks declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. `apt-get` is used in `vagrant-provision.sh`, which would fail on Fedora. The `www-data` user referenced in `nginx.rb` does not exist on Fedora by default (Nginx uses `nginx` user). The Ansible playbook must either target Ubuntu consistently or implement OS-family conditionals (`ansible_os_family == 'Debian'` vs `'RedHat'`) for package names, service names, and user/group names.

- **Git clone idempotency**: `fastapi-tutorial` uses `git` resource with `action :sync`, which always pulls the latest `main` branch. In Ansible, `ansible.builtin.git` with `update: yes` replicates this, but care must be taken to handle cases where local modifications exist. Consider pinning to a specific commit SHA for production deployments.

- **PostgreSQL provisioning via raw shell**: The `create_db_user` execute resource runs three `psql` commands with `|| true` to suppress errors on re-run. **Migration approach**: Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are fully idempotent and do not require error suppression hacks.

- **`systemctl daemon-reload` notification pattern**: The `fastapi-tutorial` recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` after writing the unit file. In Ansible, this is handled by a handler using `ansible.builtin.systemd` with `daemon_reload: yes`, triggered by a `notify` on the template task.

- **Nginx `sites-available` / `sites-enabled` symlink pattern**: `sites.rb` creates symlinks from `sites-enabled` to `sites-available`. This is an Ubuntu/Debian Nginx convention. On RHEL/Fedora, Nginx uses `conf.d/` only. The Ansible role must account for this if multi-OS support is required.

---

### Migration Order

1. **`cache` role** — Lowest risk. Installs two well-understood services (Memcached, Redis) with minimal templating. Migrating this first validates the Ansible inventory, connection, and vault setup. The `ruby_block` workaround is eliminated cleanly. No external service dependencies.

2. **`nginx-multisite` role** — Medium complexity. Depends on SSL certificates being present (generated within the same role), so the sub-task order within the role matters: security hardening → Nginx install + config → SSL cert generation → site config deployment. Must be migrated before `fastapi-tutorial` since the FastAPI app may eventually be proxied through Nginx.

3. **`fastapi-tutorial` role** — Highest complexity due to hardcoded secrets, root service user, raw PostgreSQL shell commands, and external Git dependency. Should be migrated last after vault infrastructure is established and the base OS environment (Python, PostgreSQL packages) is validated on the target.

---

### Assumptions

1. **Target OS for Ansible is Ubuntu 22.04 LTS**, not Fedora 42. The Vagrant `generic/fedora42` box appears to be a local developer convenience that does not reflect the intended production OS. All cookbook `metadata.rb` files declare `supports 'ubuntu', '>= 18.04'`, and Ubuntu-specific tooling (`ufw`, `www-data`, `apt-get`, `/var/log/auth.log`) is used throughout. This must be confirmed with the team before migration begins.

2. **The `ssl_certificate` community cookbook (v2.1.0)** is locked in `Policyfile.lock.json` and present in `Policyfile.rb` but commented out in `Berksfile` and not called in any recipe. It is assumed to be an unused/vestigial dependency and will not be migrated.

3. **Self-signed certificates are acceptable for the target environment**. The `ssl.rb` recipe generates self-signed certs with a 365-day validity. If this is a production environment, Let's Encrypt or an internal CA should be used instead. The migration plan assumes self-signed certs are intentional (development/internal cluster use).

4. **The three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) are all served from the same host**. The Ansible inventory will have a single host or host group. If these are intended to be separate hosts in production, the inventory and role assignments must be restructured.

5. **Document root paths from `solo.json` (`/var/www/<site>`) take precedence** over the defaults in `attributes/default.rb` (`/opt/server/<site>`). The `solo.json` values are assumed to be the correct production paths and will be used as defaults in the Ansible `group_vars`.

6. **The FastAPI application's `requirements.txt` exists** in the cloned repository at `https://github.com/dibanez/fastapi_tutorial.git`. The migration assumes this file is present and valid. If the repository is private or the branch changes, the Ansible `git` task will need credential configuration.

7. **PostgreSQL is installed from the OS default package repository**. No specific PostgreSQL version is pinned in the `fastapi-tutorial` recipe. The migration will use the default `postgresql` package available on the target Ubuntu version (PostgreSQL 14 on Ubuntu 22.04).

8. **Memcached requires no custom configuration**. The `cache` cookbook calls `include_recipe 'memcached'` with no attribute overrides, implying default Memcached settings are sufficient. The Ansible role will install and start Memcached with default configuration.

9. **The `redisio` cookbook's `selinux` transitive dependency is irrelevant** on the Ubuntu target. SELinux is not active on Ubuntu (AppArmor is used instead). No SELinux Ansible tasks will be included unless the target OS is confirmed to be RHEL/Fedora.

10. **The custom `lineinfile` LWRP** in `nginx-multisite/resources/lineinfile.rb` is not actually called anywhere in the cookbook's recipes or templates. It appears to be a utility resource defined for potential use. It will be documented but not actively migrated unless usage is found during deeper analysis.

11. **Vagrant is used for local development only** and will not be part of the Ansible-managed infrastructure. The `Vagrantfile` and `vagrant-provision.sh` will be replaced by an Ansible inventory entry pointing to the VM's IP (`192.168.121.10`) with appropriate SSH credentials.

12. **No CI/CD pipeline integration is currently in place** for Chef (no `.kitchen.yml`, no pipeline config files detected). The Ansible migration should include a recommendation to add `ansible-lint` and `molecule` testing as part of a new CI pipeline.

13. **The `fastapi-tutorial` service running as `root`** is assumed to be a known shortcut in the current Chef implementation and not an intentional production security posture. The Ansible role will create a dedicated `fastapi` system user as part of the migration.
