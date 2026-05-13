# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The entire stack is driven by three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) and four external Chef Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`), all pinned in `Policyfile.lock.json`.

The development environment is a **Fedora 42** VM managed by Vagrant with libvirt, provisioned via a shell bootstrap script that installs Chef and Berkshelf at runtime. The run-list is `nginx-multisite::default → cache::default → fastapi-tutorial::default`, executed by `chef-solo` with node attributes supplied through `solo.json`.

**Migration complexity: Medium.** The cookbooks are well-structured, follow standard Chef patterns, and map cleanly to Ansible roles and built-in modules. The primary challenges are the Redis configuration post-processing hack, the dynamic multi-site loop logic, self-signed certificate generation, and two sets of hardcoded credentials that must be vaulted. A complete migration including testing is estimated at **3–4 weeks** for a single engineer, or **1.5–2 weeks** with two engineers working in parallel on independent roles.

---

## Module Migration Plan

This repository contains three Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx reverse proxy and static-file web server that provisions three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) with self-signed certificate generation, HTTP-to-HTTPS redirect, security response headers (HSTS, X-Frame-Options, CSP, X-XSS-Protection), gzip compression, and a custom `lineinfile` resource for idempotent file-line management.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Four sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
        - Per-site document roots with static `index.html` files deployed from `files/default/{test,ci,status}/`
        - Self-signed RSA-2048 certificates generated via `openssl req` (365-day validity) stored under `/etc/ssl/certs` and `/etc/ssl/private`
        - `ssl-cert` group with `0710` permissions on the private key directory
        - `nginx.conf.erb` template: worker auto-scaling, gzip, `sites-enabled` include pattern
        - `security.conf.erb` template: `server_tokens off`, rate-limit zones (`login` 10r/m, `api` 30r/m), strict buffer limits, TLSv1.2/1.3 cipher suite
        - `site.conf.erb` template: per-vhost SSL block, HSTS header, security headers, hidden `.ht`/`.git`/`.svn` locations, per-site access/error logs
        - Custom `lineinfile` LWRP (in `resources/lineinfile.rb`) that replicates Ansible's `lineinfile` module behaviour with optional backup
        - Attribute-driven site map in `attributes/default.rb` (overridable via `solo.json`)

- **cache**:
    - Description: Dual caching layer that installs and configures Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, a dedicated log directory, and a post-install Ruby block that strips incompatible `replica-*` directives from the generated Redis config file.
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached` community cookbook
        - Configures a single Redis instance on port 6379 with `requirepass redis_secure_password_123` (hardcoded in recipe)
        - Creates `/var/log/redis` owned by the `redis` user
        - Post-install `ruby_block "fix_redis_config"` that removes five `replica-*` / `client-output-buffer-limit` directives from `/etc/redis/6379.conf` to work around a `redisio` 7.x compatibility issue with newer Redis versions
        - Calls `redisio::enable` to activate the Redis systemd service

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running inside a Python virtual environment under `/opt/fastapi-tutorial`, backed by a locally-installed PostgreSQL database with a dedicated user and database, exposed as a systemd service via `uvicorn` on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` with `action :sync`
        - Creates a Python venv and installs `requirements.txt` via pip
        - Enables and starts the `postgresql` service
        - Creates PostgreSQL role `fastapi` with password `fastapi_password` and database `fastapi_db` via inline `psql` shell commands (idempotent with `|| true`)
        - Writes `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (plaintext)
        - Writes `/etc/systemd/system/fastapi-tutorial.service` (Type=simple, User=root, `uvicorn app.main:app --host 0.0.0.0 --port 8000`, Restart=always)
        - Runs `systemctl daemon-reload` and enables/starts the service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four Supermarket dependencies with version constraints. Used by `vagrant-provision.sh` to vendor cookbooks before the Chef Solo run. In Ansible there is no equivalent; all role dependencies will be declared in `requirements.yml` for Ansible Galaxy.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), the run-list, and cookbook sources. Superseded in Ansible by a playbook with an explicit `roles:` list.
- `Policyfile.lock.json`: Pinned dependency graph including transitive dependency `selinux 6.2.4` (pulled in by `redisio`). Provides the authoritative version reference for all eight cookbook locks. Must be consulted when selecting equivalent Ansible collection/role versions.
- `solo.json`: Node attribute JSON consumed by `chef-solo -j`. Overrides default site document roots to `/var/www/<site>` and sets security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth`). In Ansible this becomes `group_vars/all.yml` or host-specific `host_vars`.
- `solo.rb`: Chef Solo configuration: sets `file_cache_path`, `cookbook_path`, log level. Replaced by `ansible.cfg` in the Ansible world.
- `Vagrantfile`: Defines a `generic/fedora42` VM with 2 vCPUs / 2 GB RAM, private network `192.168.121.10`, forwarded ports 80→8080 and 443→8443, libvirt provider, rsync folder sync, and shell provisioner. The commented-out `chef_solo` provisioner block confirms the intended Chef Solo workflow. In Ansible this becomes a `vagrant` inventory with an Ansible provisioner block.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef-embedded gem, vendors cookbooks, and runs `chef-solo`. This entire script is replaced by Ansible's agentless SSH execution model — no bootstrap script is needed.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `Policyfile.lock.json` copy, `generated-project-metadata.json` (cookbook inventory), and a prior draft `migration-plan.md`. These files are tooling artefacts and do not need to be migrated.

---

### Target Details

- **Operating System**: **Fedora 42** is the active development target (declared in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, indicating the intent to support both Debian and RHEL family systems. The Ansible roles must therefore use the `ansible_os_family` fact to branch package names (e.g., `nginx` vs `nginx`, `ufw` vs `firewalld`, `ssh` vs `sshd` service names) and handle both `apt` and `dnf`/`yum` package managers. Default to **Red Hat Enterprise Linux 9 / Fedora** as the primary target given the active Vagrantfile.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly declared in the `Vagrantfile` (`config.vm.provider "libvirt"`). The VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider SDK packages, metadata endpoint calls, or cloud-init configurations are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community cookbook wraps package installation and service management. Replace with the `ansible.builtin.package` module (`nginx`) and `ansible.builtin.service`. The `nginx.conf` and `security.conf` templates already exist in the cookbook and can be ported directly to Ansible Jinja2 templates with minimal variable substitution changes (ERB `<%= @var %>` → Jinja2 `{{ var }}`).
- **memcached (6.1.0, Chef Supermarket)**: Fully delegated to the community cookbook. Replace with `ansible.builtin.package` (`memcached`) and `ansible.builtin.service`. No custom configuration is applied beyond what the community cookbook provides, so a simple install-and-enable task is sufficient.
- **redisio (7.2.4, Chef Supermarket)**: Manages Redis installation, config file generation, and service enablement. Replace with `ansible.builtin.package` (`redis` / `redis-server`), a templated `/etc/redis/6379.conf` (or `/etc/redis.conf` on RHEL), and `ansible.builtin.service`. The post-install config-stripping hack (see Technical Challenges) must be replicated with `ansible.builtin.lineinfile` or `ansible.builtin.replace` tasks.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Referenced in `Policyfile.rb` but not directly called in any local recipe — SSL is handled inline in `ssl.rb` via raw `openssl req` shell commands. Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection, which provide idempotent self-signed certificate generation without shelling out.
- **selinux (6.2.4, Chef Supermarket)**: Transitive dependency pulled in by `redisio`. Replace with `ansible.posix.selinux` module if SELinux management is required on RHEL/Fedora targets. On Fedora 42 this may be needed to allow Redis and Nginx to bind to their ports.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): This credential is committed in plaintext to the repository. **Must be migrated to Ansible Vault** as `vault_redis_password`. The Ansible Redis config template must reference `{{ vault_redis_password }}`.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb` in both the `psql` command and the `.env` file content): Two occurrences of the same plaintext password. **Must be migrated to Ansible Vault** as `vault_fastapi_db_password`. The `.env` file template and the `postgresql_user` task must both reference `{{ vault_fastapi_db_password }}`.
- **Plaintext `.env` file** (`/opt/fastapi-tutorial/.env`): Written with mode `0644` and owned by `root`. In Ansible, deploy this file with mode `0600` and consider using `ansible.builtin.template` sourced from a Vault-encrypted variable file. The `DATABASE_URL` contains the database password in the connection string.
- **Self-signed SSL certificates**: Generated via `openssl req` with a 365-day validity and a hardcoded subject (`/C=US/ST=Example/...`). The private key is set to mode `0640`, group `ssl-cert`. In Ansible, use `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` to replicate this idempotently. For production, replace with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA.
- **SSH hardening** (`PermitRootLogin no`, `PasswordAuthentication no`): Implemented via `sed` in `security.rb`. Replace with `ansible.builtin.lineinfile` tasks targeting `/etc/ssh/sshd_config`, with a handler to restart the `sshd` service. Ensure the Ansible control user has a valid SSH key before disabling password auth to avoid lockout.
- **UFW firewall rules**: Configured via raw `ufw` shell commands with `not_if` guards. Replace with the `community.general.ufw` module. Note: UFW is Debian/Ubuntu-native; on Fedora/RHEL targets use `ansible.posix.firewalld` instead. The Ansible role must branch on `ansible_os_family`.
- **fail2ban configuration**: Deployed via `fail2ban.jail.local.erb` template with four jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch). Replace with `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service`. The template content is static and ports directly to Jinja2 with no variable substitution needed.
- **sysctl kernel hardening**: 18 kernel parameters covering IP spoofing protection, ICMP redirect suppression, SYN flood protection, and IPv6 disablement. Replace with `ansible.posix.sysctl` module tasks (one task per parameter, or a loop over a variable dictionary). This is a direct 1:1 mapping.
- **FastAPI service running as root** (`User=root` in the systemd unit): A security risk. The Ansible migration is an opportunity to create a dedicated `fastapi` system user and run the service under that account.
- **Credential count summary**:
    - `cache` cookbook: 1 hardcoded password (Redis `requirepass`)
    - `fastapi-tutorial` cookbook: 2 hardcoded password occurrences (PostgreSQL user creation + `.env` file)
    - `nginx-multisite` cookbook: 0 hardcoded credentials (SSL subject uses placeholder org data only)
    - **Total: 3 plaintext credential instances across 2 cookbooks — all must be vaulted before first Ansible run**

---

### Technical Challenges

- **Redis config post-processing hack**: `cache/recipes/default.rb` uses a `ruby_block` to strip five directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` after `redisio` writes it. This exists because `redisio 7.x` generates config keys that are invalid in newer Redis versions. In Ansible, since the config file will be managed directly via a Jinja2 template (not generated by a community role), these directives simply will not be included — eliminating the need for the hack entirely. However, the correct Redis config key names for the target Redis version must be verified.
- **Dynamic multi-site loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create document roots, deploy static files, generate per-site vhost configs, and create `sites-enabled` symlinks. In Ansible this maps to a `loop` over a `nginx_sites` list variable, using `ansible.builtin.file`, `ansible.builtin.copy`, `ansible.builtin.template`, and `ansible.builtin.file` (state: link) tasks. The variable structure must be defined in `group_vars` to match the current attribute schema.
- **Custom `lineinfile` LWRP**: The cookbook ships its own `lineinfile` resource (`resources/lineinfile.rb`) that replicates Ansible's built-in `lineinfile` module. This resource is not called anywhere in the current recipes (it appears to be a utility resource for future use or external consumers). No migration action is required — Ansible's native `ansible.builtin.lineinfile` module covers this functionality completely.
- **ERB → Jinja2 template conversion**: Five ERB templates must be converted. The syntax differences are minor (`<%= @var %>` → `{{ var }}`, `<% if @ssl_enabled %>` → `{% if ssl_enabled %}`, `<% end %>` → `{% endif %}`), but the `site.conf.erb` template has an unclosed `<% if @ssl_enabled %>` block (the `}` closing the HTTP server block is inside the `if` branch) that must be carefully restructured in Jinja2 to avoid rendering errors.
- **Platform divergence (UFW vs firewalld)**: The `security.rb` recipe uses `ufw`, which is only available on Debian/Ubuntu. The Vagrantfile targets Fedora 42, which uses `firewalld`. The current Chef code will fail on Fedora without modification. The Ansible role must use `ansible_os_family` conditionals to select `community.general.ufw` (Debian) or `ansible.posix.firewalld` (RedHat) — and this divergence should be resolved and tested explicitly.
- **`apt-get update` in vagrant-provision.sh**: The bootstrap script calls `apt-get update` and `apt-get install build-essential`, which are Debian-specific commands, yet the VM is Fedora 42. This is a latent bug in the current provisioning script. The Ansible migration should use `ansible.builtin.package` with `update_cache: true` (for apt) or rely on `dnf` auto-refresh, and must not assume a specific package manager.
- **Git-based application deployment**: `fastapi-tutorial` uses `git ... action :sync` which always pulls the latest `main` branch. In Ansible, `ansible.builtin.git` with `version: main` replicates this, but a `force: true` flag may be needed if local modifications exist. Consider pinning to a specific commit SHA or tag for reproducibility in production.
- **PostgreSQL idempotency**: The current recipe uses `psql -c "CREATE USER ... || true"` shell hacks for idempotency. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` Ansible collection, which handle idempotency natively.
- **systemd daemon-reload ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd before enabling the service. In Ansible, use a handler with `ansible.builtin.systemd` (`daemon_reload: true`) triggered by the service file template task, ensuring correct ordering.

---

### Migration Order

The following order minimises risk by migrating independent, lower-complexity components first and leaving the most credential-sensitive and dependency-heavy component for last:

1. **`cache` role** — Lowest external surface area; Memcached has zero configuration and Redis configuration is self-contained. Migrating this first validates the Ansible Vault setup for the Redis password and establishes the pattern for service roles. No dependencies on other local cookbooks.

2. **`nginx-multisite` role** — Core infrastructure component. Depends on no other local cookbook. Migrating second allows the multi-site loop pattern, template conversion, SSL certificate generation, and security hardening (fail2ban, UFW/firewalld, sysctl, SSH) to be validated in isolation. The static HTML files and all five templates are already present and need only syntax conversion.

3. **`fastapi-tutorial` role** — Highest complexity: involves Git deployment, Python venv management, PostgreSQL provisioning, systemd service management, and two vaulted credentials. Should be migrated last, after the PostgreSQL community collection is confirmed available and the Vault pattern is established from step 1.

---

### Assumptions

1. **Target OS for Ansible**: The primary target is Fedora 42 (matching the Vagrantfile). Ubuntu/CentOS compatibility declared in `metadata.rb` is aspirational; the Ansible roles should implement OS-family branching but Fedora 42 is the only actively tested platform.
2. **Self-signed certificates are acceptable for the target environment**: The `ssl.rb` recipe generates development-grade self-signed certificates. If this is a production migration, the SSL role must be redesigned to use Let's Encrypt or an internal CA — this is out of scope for the initial migration but should be flagged as a follow-up task.
3. **The FastAPI GitHub repository remains publicly accessible**: `fastapi-tutorial` clones `https://github.com/dibanez/fastapi_tutorial.git`. If this repository becomes private or is deleted, the deployment will fail. Consider mirroring or vendoring the application source.
4. **Redis does not require clustering or persistence**: The current configuration is a single-instance Redis with password auth and no AOF/RDB persistence settings. The Ansible role will replicate this single-instance model.
5. **Memcached requires no custom configuration**: The `cache` cookbook delegates entirely to the `memcached` community cookbook with no attribute overrides. The Ansible role will install and start Memcached with default settings.
6. **The `ssl_certificate` community cookbook is not actively used**: It appears in `Policyfile.rb` and `Policyfile.lock.json` but is never `include_recipe`'d in any local recipe. SSL is handled directly in `ssl.rb` via shell commands. No migration action is required for this dependency.
7. **The `lineinfile` custom resource is not called by any recipe**: It exists in `resources/lineinfile.rb` as a utility LWRP but has no callers in the current codebase. It will not be migrated; Ansible's built-in `lineinfile` module is the direct replacement if it is needed in future.
8. **Document root paths**: `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, while `solo.json` overrides them to `/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}`. The Ansible `group_vars` should use the `solo.json` values (`/var/www/`) as the canonical defaults, since that is what the active provisioning run uses.
9. **`www-data` user exists on the target**: `nginx.rb` sets document root ownership to `www-data:www-data`. On Fedora/RHEL, Nginx runs as `nginx:nginx`. The Ansible role must use `{{ nginx_user }}` variable defaulting to `nginx` on RedHat and `www-data` on Debian.
10. **Ansible Vault will be used for all secrets**: The two plaintext passwords (`redis_secure_password_123`, `fastapi_password`) must be rotated and stored in an Ansible Vault-encrypted file before the first Ansible run. The current plaintext values in the Chef recipes should be treated as compromised and changed as part of the migration.
11. **No Chef Server is in use**: The entire stack runs via `chef-solo`, confirming there is no Chef Server, data bags, Chef Vault, or encrypted data bags to migrate. All configuration is in attributes and recipe logic.
12. **The `selinux` cookbook is a transitive dependency only**: It is pulled in by `redisio` but no SELinux policy customisations are made in any local recipe. On Fedora 42 with SELinux enforcing, the Ansible roles may need `ansible.posix.seboolean` or `community.general.sefcontext` tasks to allow Nginx and Redis to operate correctly — this must be verified during testing.
