# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service web server environment. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and executed through Vagrant on a Fedora 42 / libvirt VM.

The run list executes three cookbooks in order: `nginx-multisite → cache → fastapi-tutorial`, deploying a hardened Nginx reverse proxy with three SSL-enabled virtual hosts, a dual caching layer (Memcached + Redis), and a Python FastAPI application backed by PostgreSQL.

**Overall Migration Complexity: Medium**
The codebase is well-structured and self-contained. The primary challenges are replacing Chef community cookbook abstractions (`nginx ~> 12.3.1`, `memcached ~> 6.1.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1.0`) with native Ansible modules, handling a hardcoded Redis password and plaintext PostgreSQL credentials, and faithfully reproducing the custom `lineinfile` resource and the Redis config post-processing hack.

**Estimated Migration Timeline: 5–8 working days**
- nginx-multisite: 2–3 days (most complex; 5 recipes, 5 templates, custom resource)
- cache: 1–2 days (Redis + Memcached, credential handling)
- fastapi-tutorial: 1–2 days (Python venv, PostgreSQL, systemd service)
- Integration, testing, and validation: 1 day

---

## Module Migration Plan

This repository contains **3 Chef cookbooks** that need individual migration planning.

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation, security hardening via HTTP headers, rate limiting, UFW firewall rules, Fail2Ban intrusion prevention, and kernel-level sysctl network hardening.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features:
    - Installs and configures Nginx from the OS package manager (not the Chef `nginx` community cookbook at runtime — the community cookbook is declared as a dependency in `Policyfile.rb` but the recipe installs `nginx` directly via the `package` resource).
    - Renders `nginx.conf` and a global `security.conf` (rate-limit zones, buffer overflow protections, SSL session settings, `server_tokens off`) from ERB templates.
    - Iterates over a `node['nginx']['sites']` attribute hash to create per-site document roots, deploy static `index.html` files from cookbook files, generate per-site self-signed RSA-2048 / 365-day TLS certificates via `openssl req`, and render per-site Nginx vhost configs with HTTP→HTTPS redirect, TLSv1.2/1.3-only cipher suites, HSTS, and a full set of security response headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Content-Security-Policy).
    - Configures UFW with default-deny, then allows SSH/HTTP/HTTPS.
    - Deploys Fail2Ban with a custom `jail.local` covering `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails (3600 s ban, 3 retries).
    - Applies a sysctl hardening profile (`/etc/sysctl.d/99-security.conf`) covering IP spoofing protection, ICMP redirect suppression, source routing disablement, martian logging, ICMP echo ignore, TCP SYN-cookie flood protection, and IPv6 disable.
    - Hardens SSH daemon: disables root login and password authentication via `sed` on `/etc/ssh/sshd_config`.
    - Includes a custom `lineinfile` LWRP (Light-Weight Resource Provider) that replicates Ansible's `lineinfile` module behaviour (match-and-replace or append, with timestamped backup).
    - Default attribute values are defined in `attributes/default.rb`; runtime overrides are supplied via `solo.json` (document roots differ between defaults and `solo.json`).

- **cache**:
  - Description: Dual in-memory caching layer deploying Memcached (via the `memcached ~> 6.1.0` community cookbook) and Redis (via the `redisio ~> 7.2.4` community cookbook) with password authentication, a dedicated log directory, and a post-install config sanitisation workaround.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features:
    - Delegates Memcached installation and service management entirely to the `memcached` community cookbook (no local customisation).
    - Configures a single Redis instance on port 6379 with `requirepass redis_secure_password_123` via `node.default['redisio']['servers']`.
    - Creates `/var/log/redis` owned by the `redis` user.
    - Delegates Redis installation and service management to `redisio` and `redisio::enable`.
    - Contains a `ruby_block` hack (`fix_redis_config`) that post-processes `/etc/redis/6379.conf` to strip out deprecated `replica-*` directives that the `redisio 7.2.4` cookbook writes but the installed Redis version rejects (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`).
    - Depends on the `selinux ~> 6.2.4` cookbook transitively (pulled in by `redisio`).

- **fastapi-tutorial**:
  - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running under a Python virtual environment managed by `uvicorn`, backed by a locally-provisioned PostgreSQL database, and managed as a systemd service.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features:
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using the `git` resource with `:sync` action.
    - Creates a Python venv at `/opt/fastapi-tutorial/venv` and installs dependencies from `requirements.txt`.
    - Enables and starts the `postgresql` service.
    - Creates PostgreSQL role `fastapi` with password `fastapi_password`, database `fastapi_db`, and grants all privileges — executed via `sudo -u postgres psql` shell commands with `|| true` guards for idempotency.
    - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (mode `0644`, owned by root).
    - Deploys a systemd unit file `/etc/systemd/system/fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as root, with `After=postgresql.service`.
    - Reloads systemd daemon and enables/starts the `fastapi-tutorial` service.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency file declaring all local cookbook paths and external Supermarket sources with version constraints. Maps directly to an Ansible `requirements.yml` for Galaxy roles. Note: `ssl_certificate` is commented out in `Berksfile` but present and locked in `Policyfile.rb` / `Policyfile.lock.json`.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), run list order, and pinned version constraints for all cookbooks. Equivalent to an Ansible playbook with an ordered `roles:` or `tasks:` list.
- `Policyfile.lock.json`: Fully resolved and locked dependency graph (8 cookbooks with SHA identifiers). Serves as the authoritative source of truth for exact versions during migration: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`.
- `solo.json`: Chef Solo node JSON supplying runtime attribute overrides (site document roots under `/var/www/`, SSL paths, security flags). Translates to Ansible `group_vars/all.yml` or host-level `host_vars`.
- `solo.rb`: Chef Solo configuration file (cache path, cookbook path, log level). No direct Ansible equivalent; superseded by `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU / 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Translates to an Ansible inventory file with connection variables, or a Molecule test scenario.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. Replaced entirely by the Ansible control node workflow (`ansible-playbook`).
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/generated-project-metadata.json`: Auto-generated project metadata listing the three cookbooks with descriptions. Useful as a reference during Ansible role scaffolding.

---

### Target Details

- **Operating System**: Ubuntu 18.04+ or CentOS 7+ per `metadata.rb` `supports` declarations. The Vagrant box is `generic/fedora42` (Fedora 42), which is RPM-based. The recipes use Debian-specific artefacts (`www-data` user/group, `ufw`, `/var/log/auth.log`, `apt-get` in the provisioner script), indicating the **primary target is a Debian/Ubuntu system** despite the Fedora Vagrant box. Default to **Ubuntu 22.04 LTS** for the Ansible migration unless the team confirms Fedora/RHEL as the production target (see Assumptions).
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. The VM is used as a local development and testing environment.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook: Replace with the `ansible.builtin.package` module to install `nginx` from the OS package manager, `ansible.builtin.template` for `nginx.conf` and `security.conf`, and `ansible.builtin.service` for lifecycle management. The ERB templates translate directly to Jinja2. Consider the `nginxinc.nginx` Ansible Galaxy role as an optional drop-in, but given the level of custom configuration, direct task-based implementation is recommended.
- **memcached (6.1.0)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (`memcached`), `ansible.builtin.service`, and optionally the `geerlingguy.memcached` Galaxy role. No local customisation is applied on top of this cookbook, making it a straightforward substitution.
- **redisio (7.2.4)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (`redis` / `redis-server`), `ansible.builtin.template` for `redis.conf` (setting `requirepass`), and `ansible.builtin.service`. The `fix_redis_config` ruby_block hack (stripping deprecated `replica-*` directives) must be reproduced — use `ansible.builtin.lineinfile` with `regexp` + `state: absent` for each deprecated directive, or template the entire `redis.conf` directly to avoid the issue altogether (preferred approach).
- **ssl_certificate (2.1.0)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.command` invoking `openssl req` (matching the existing self-signed cert generation logic), or preferably the `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey` modules from the `community.crypto` Ansible collection for idempotent certificate management.
- **selinux (6.2.4)** — Chef Supermarket community cookbook (transitive via redisio): Replace with `ansible.posix.selinux` module if the target is RHEL/Fedora, or omit entirely for Ubuntu targets where SELinux is not active.

---

### Security Considerations

- **Hardcoded Redis password**: The string `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb` (`node.default['redisio']['servers'][0]['requirepass']`). **Migrate to Ansible Vault**: store as `vault_redis_password` in an encrypted `group_vars/all/vault.yml` and reference it in the Redis template variable.
- **Hardcoded PostgreSQL credentials**: The username `fastapi`, password `fastapi_password`, and database `fastapi_db` are hardcoded in three places in `cookbooks/fastapi-tutorial/recipes/default.rb`: the `psql` shell commands, the `.env` file content, and the `DATABASE_URL`. **Migrate to Ansible Vault**: store as `vault_db_password` and `vault_db_user`. The `.env` file should be templated with `mode: '0600'` and owned by the application service user (not root).
- **`.env` file permissions**: The current recipe writes `/opt/fastapi-tutorial/.env` with mode `0644` (world-readable), exposing the database password. The Ansible equivalent must set `mode: '0600'` and assign ownership to a dedicated non-root service account.
- **FastAPI service running as root**: The systemd unit runs `uvicorn` as `User=root`. The Ansible migration should create a dedicated `fastapi` system user and update the service unit accordingly.
- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated by `openssl req` with a 365-day validity and a hardcoded subject (`/C=US/ST=Example/...`). These are appropriate for development but must be replaced with CA-signed or Let's Encrypt certificates for production. The Ansible migration should parameterise the subject fields and certificate validity, and provide a hook for production certificate injection.
- **SSH hardening via `sed`**: Root login and password authentication are disabled by directly patching `/etc/ssh/sshd_config` with `sed`. Replace with `ansible.builtin.lineinfile` tasks (matching the `PermitRootLogin` and `PasswordAuthentication` directives) or the `devsec.hardening.ssh_hardening` Galaxy role for a more comprehensive approach.
- **UFW management via shell `execute` resources**: UFW rules are applied through raw shell commands with `not_if` guards. Replace with the `community.general.ufw` Ansible module for fully idempotent firewall management.
- **Credential count summary**:
  - `cache` cookbook: 1 hardcoded secret (Redis `requirepass`)
  - `fastapi-tutorial` cookbook: 2 hardcoded secrets (PostgreSQL password appears in `psql` commands and `.env` file), 1 hardcoded database URL
  - `nginx-multisite` cookbook: 0 runtime secrets; TLS private keys are generated on-host and never stored in the repository

---

### Technical Challenges

- **Attribute precedence and `solo.json` overrides**: The `nginx-multisite` cookbook defines default document roots in `attributes/default.rb` (`/opt/server/{test,ci,status}`) but `solo.json` overrides them to `/var/www/{site-name}`. Both sets of paths appear in the static HTML files. The Ansible migration must consolidate these into a single authoritative variable source (`group_vars` or `host_vars`) and ensure the static HTML files reference the correct paths.
- **Custom `lineinfile` LWRP**: The cookbook ships its own `lineinfile` resource (`resources/lineinfile.rb`) that mimics Ansible's `lineinfile` module. This resource is not called anywhere in the current recipes (it appears to be a utility resource available for future use or external consumers). It translates directly to `ansible.builtin.lineinfile` and requires no special handling, but its existence should be noted during role design.
- **`redisio` compatibility hack**: The `fix_redis_config` ruby_block strips deprecated Redis configuration directives written by `redisio 7.2.4`. This indicates a version mismatch between the cookbook and the installed Redis binary. In Ansible, this is best resolved by templating the entire `redis.conf` from scratch rather than patching a generated file, giving full control over the configuration and eliminating the need for the workaround.
- **Debian vs. RPM target ambiguity**: The `metadata.rb` files declare support for both Ubuntu ≥ 18.04 and CentOS ≥ 7.0, but the recipes use Debian-specific conventions (`www-data` user, `ufw`, `apt-get` in the provisioner). The Vagrant box is Fedora 42 (RPM). The Ansible roles must either target a single OS family or implement conditional task blocks (`when: ansible_os_family == 'Debian'`) for package names, service names, and user/group names.
- **Git-based application deployment**: The `fastapi-tutorial` recipe uses the Chef `git` resource with `:sync` action to clone and update the application. The Ansible equivalent (`ansible.builtin.git`) is straightforward, but the team must decide on a deployment strategy: direct git clone (current approach), artifact-based deployment, or a dedicated deployment tool. The `requirements.txt` install step is not idempotent in the current recipe (runs on every converge); the Ansible task should use `pip` module with `state: present` or add a `creates` guard.
- **PostgreSQL initialisation idempotency**: The `create_db_user` execute resource uses `|| true` shell guards to suppress errors on re-runs. Replace with the `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, use a handler with `ansible.builtin.systemd` (`daemon_reload: true`) triggered by a `notify` on the unit file template task.
- **Nginx `sites-available` / `sites-enabled` symlink pattern**: The recipe creates symlinks from `sites-enabled` to `sites-available`. Ansible does not have a built-in "nginx site enable" module; use `ansible.builtin.file` with `state: link` to replicate this, and `ansible.builtin.file` with `state: absent` to remove the default site.

---

### Migration Order

1. **nginx-multisite** — Migrate first as it is the most self-contained cookbook with no runtime dependency on the other two. Establishing the Nginx role, security hardening tasks, and SSL certificate generation early provides the foundation for the full playbook. Validates the Jinja2 template conversion from ERB and the `community.crypto` collection usage.
2. **cache** — Migrate second. Depends on resolving the `redisio` compatibility issue (Redis config templating strategy) and the Ansible Vault setup for the Redis password. Memcached is trivial; Redis requires the most attention. No dependency on `nginx-multisite` or `fastapi-tutorial`.
3. **fastapi-tutorial** — Migrate last due to the highest number of security remediation items (hardcoded credentials, root service user, world-readable `.env`), the external git dependency, and the PostgreSQL provisioning complexity. Should be migrated only after Ansible Vault is fully configured and the target OS family is confirmed.

---

### Assumptions

1. **Target OS family is Ubuntu/Debian**: The recipes use `www-data`, `ufw`, and `apt-get`, which are Debian-specific. The Vagrant box (`generic/fedora42`) appears to be a local developer convenience rather than a reflection of the production target. The migration plan assumes **Ubuntu 22.04 LTS** as the primary target. If the production target is RHEL/CentOS/Fedora, package names (`nginx`, `redis`, `memcached`, `postgresql`), service names (`sshd` vs `ssh`), the web server user (`nginx` vs `www-data`), and firewall tooling (`firewalld` vs `ufw`) must all be adjusted.
2. **Chef `nginx` community cookbook is not used at runtime**: The `nginx` cookbook is declared in `Policyfile.rb` and `Berksfile` but the `nginx-multisite::nginx` recipe installs Nginx directly via `package 'nginx'` without calling `include_recipe 'nginx'`. The community cookbook's resources and attributes are therefore not exercised. The Ansible migration does not need to replicate the community cookbook's behaviour.
3. **`ssl_certificate` community cookbook is not used at runtime**: Similarly, `ssl_certificate ~> 2.1.0` is locked in `Policyfile.lock.json` but no recipe calls `include_recipe 'ssl_certificate'` or uses its resources. SSL certificates are generated directly via `openssl req` in `nginx-multisite::ssl`. The Ansible migration should use `community.crypto` modules directly.
4. **Self-signed certificates are acceptable for the initial Ansible migration**: The migration will replicate the self-signed certificate generation behaviour. Production certificate management (Let's Encrypt / internal CA) is considered out of scope for the initial migration and should be addressed as a follow-up task.
5. **The `solo.json` document root paths (`/var/www/...`) take precedence over `attributes/default.rb` paths (`/opt/server/...`)**: The `solo.json` overrides are the runtime-effective values. The Ansible `group_vars` will use the `/var/www/` paths. The static HTML files currently reference `/opt/server/` paths in their content — these will need to be updated to match.
6. **The FastAPI application source repository (`https://github.com/dibanez/fastapi_tutorial.git`) is accessible**: The Ansible `git` task will require network access to GitHub from the managed node. If the environment is air-gapped, an internal mirror or artifact repository must be provisioned.
7. **PostgreSQL is installed and managed locally on the same host**: The `fastapi-tutorial` recipe installs PostgreSQL on the same node as the application. The Ansible migration assumes this single-node topology. A multi-node topology (separate DB host) would require inventory changes and firewall rule additions.
8. **No existing Ansible infrastructure**: The migration assumes a greenfield Ansible setup. No existing inventory, `ansible.cfg`, or Galaxy roles are present in the repository.
9. **Vagrant/libvirt is used only for local development testing**: The Ansible migration will target the same VM for initial validation but is expected to be adapted for a production inventory. The `Vagrantfile` will be updated to use the Ansible provisioner instead of the shell provisioner.
10. **The `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/` directory is tooling scaffolding**: This directory appears to be generated by the X2Ansible migration tool (as described in `project-plan.md`) and contains a duplicate `solo.json` and a prior `migration-plan.md`. It is not part of the Chef cookbook source and should be excluded from the Ansible repository.
11. **Redis is configured as a standalone instance**: Only a single Redis server on port 6379 is defined. No replication, Sentinel, or Cluster configuration is present. The Ansible migration will replicate this single-instance topology.
12. **Memcached configuration is entirely default**: The `cache` cookbook calls `include_recipe 'memcached'` with no attribute overrides. The Ansible migration will install Memcached with OS-default configuration unless the team specifies otherwise.
