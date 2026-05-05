# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure stack that provisions a multi-site Nginx web server with SSL/TLS termination, security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is currently exercised locally via Vagrant with a Fedora 42 libvirt VM and Chef Solo as the provisioner.

The migration consists of **3 local cookbooks** and **5 external Supermarket cookbook dependencies** that together implement a complete web application platform. All three cookbooks have clear, well-scoped responsibilities and low cross-cookbook coupling, making this an excellent candidate for an incremental, role-by-role Ansible migration.

**Overall complexity: Medium.** The Chef resources used throughout the cookbooks (`package`, `template`, `service`, `directory`, `execute`, `git`, `file`) map directly to well-supported Ansible modules. The most notable friction points are: a `ruby_block` hack used to post-process the Redis configuration file, a custom `lineinfile` LWRP that duplicates native Ansible functionality, and hardcoded credentials scattered across recipe files and `solo.json` that must be moved into Ansible Vault before the first playbook run.

**Estimated timeline: 3–4 weeks** for a complete migration including testing and documentation, assuming one engineer with Ansible experience.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multi-site virtual host management, per-site SSL/TLS using self-signed certificates, HTTP-to-HTTPS redirect, security header injection (HSTS, X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection), gzip compression, and a full security hardening layer covering UFW firewall rules, fail2ban intrusion prevention with four active jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch), SSH daemon hardening, and kernel-level sysctl network security tuning.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Three pre-configured virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), TLSv1.2/1.3-only cipher suites, rate-limiting zones (`login` 10 r/m, `api` 30 r/m), UFW default-deny with SSH/HTTP/HTTPS allow rules, fail2ban with 1-hour bans and 3-retry thresholds, sysctl hardening (rp_filter, SYN cookies, ICMP suppression, IPv6 disable), SSH root login disabled, password authentication disabled, static per-site `index.html` content files deployed from cookbook `files/`.

- **cache**:
    - Description: Caching services layer that installs and configures both Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication enabled. Includes a post-install `ruby_block` workaround that strips deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` to ensure compatibility with newer Redis versions.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Redis on port 6379 with `requirepass` authentication, Memcached with default community cookbook settings, Redis log directory ownership (`redis:redis`, mode `0755`), `redisio::enable` for systemd service management, hardcoded Redis password (`redis_secure_password_123`) in recipe source.

- **fastapi-tutorial**:
    - Description: Full-stack Python web application deployment that installs system packages, clones a FastAPI application from GitHub, creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file with database credentials, deploys a systemd unit file, and starts the application service on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`), Python 3 venv at `/opt/fastapi-tutorial/venv`, PostgreSQL user `fastapi` with password `fastapi_password`, database `fastapi_db`, `DATABASE_URL` written in plaintext to `/opt/fastapi-tutorial/.env` (mode `0644`), uvicorn ASGI server bound to `0.0.0.0:8000`, systemd service running as `root`, `After=postgresql.service` dependency declared.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external Supermarket dependencies: `nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, and `ssl_certificate ~> 2.1` (the `ssl_certificate` line is commented out in Berksfile but active in Policyfile.rb). This file drives `berks install` / `berks vendor` during Vagrant provisioning. Has no direct Ansible equivalent — dependencies become Ansible Galaxy role references in `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and version constraints for all cookbooks. Equivalent to an Ansible site playbook that imports three roles in order.
- `Policyfile.lock.json`: Locked dependency graph with resolved versions and SHA identifiers for all 8 cookbooks (`cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`). Serves as the source of truth for exact versions to target when selecting Ansible Galaxy roles.
- `solo.json`: Chef Solo node JSON providing run list and attribute overrides. Defines the three virtual host names and document roots, SSL certificate/key paths (`/etc/ssl/certs`, `/etc/ssl/private`), and security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth`). Migrates to Ansible `group_vars/` or `host_vars/` variable files.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` as the cache path and `/chef-repo/cookbooks` as the cookbook path. No migration artifact needed — replaced by `ansible.cfg` and inventory configuration.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. Migrates to an Ansible inventory file with a `vagrant` host group and connection variables (`ansible_host`, `ansible_user`, `ansible_port`). The libvirt provider details inform target VM sizing.
- `vagrant-provision.sh`: Bash bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks vendor`, and executes `chef-solo`. Migrates to a simple `ansible-playbook` invocation; the Berkshelf vendoring step has no equivalent and is eliminated entirely.

---

### Target Details

- **Operating System**: Fedora 42 is the active development target (declared in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The `security.rb` recipe uses `ufw` (Debian/Ubuntu firewall tool) and references `/var/log/auth.log` (Debian path), indicating the cookbooks were originally written for Ubuntu and adapted. The Ansible migration should target **Red Hat Enterprise Linux 9 / Fedora** as the primary platform and use `ansible_os_family` conditionals to handle `ufw` vs `firewalld` and log path differences for Ubuntu compatibility.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly declared in the `Vagrantfile` via `config.vm.provider "libvirt"`. VM title is `chef-nginx-multisite`, 2 vCPU, 2 GB RAM.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are referenced anywhere in the repository. The infrastructure is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community Chef nginx cookbook handles package install, service management, and basic configuration. Replace with the `nginxinc.nginx` Ansible Galaxy role or the `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` modules directly. The existing `nginx.conf.erb` and `site.conf.erb` templates can be converted to Jinja2 with minimal changes (replace `<%= @var %>` with `{{ var }}` and `<% if %>` with `{% if %}`).
- **memcached (6.1.0, Chef Supermarket)**: Wraps a simple package install and service enable. Replace with `ansible.builtin.package` (package name: `memcached`) and `ansible.builtin.service`. No complex configuration is applied beyond defaults.
- **redisio (7.2.4, Chef Supermarket)**: Manages Redis installation, per-instance configuration file generation, and service management. Replace with `ansible.builtin.package` (package name: `redis`), `ansible.builtin.template` for `/etc/redis/redis.conf`, and `ansible.builtin.service`. The `requirepass` directive maps directly to a template variable sourced from Ansible Vault. The `ruby_block` config-stripping hack becomes unnecessary if the Ansible template is written cleanly for the target Redis version.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Provides SSL certificate resource abstraction. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible Galaxy collection for self-signed certificate generation. For production, integrate with `community.crypto.acme_certificate` or a PKI role.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Manages SELinux policy. Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` for boolean management. Verify whether SELinux is enforcing on the target Fedora/RHEL hosts and add appropriate `sefcontext` tasks for Redis data directories if needed.

---

### Security Considerations

- **Hardcoded Redis password**: The string `redis_secure_password_123` is written directly in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`). This credential is committed to source control. **Action required**: Remove from source, store in `ansible/group_vars/all/vault.yml` encrypted with `ansible-vault`, and reference as `{{ vault_redis_password }}` in the Redis configuration template. **1 hardcoded credential detected in this module.**
- **Hardcoded PostgreSQL credentials**: The username `fastapi`, password `fastapi_password`, and database name `fastapi_db` are hardcoded in `cookbooks/fastapi-tutorial/recipes/default.rb` in both the `psql` shell commands and the `.env` file content block. **Action required**: Move all three values to Ansible Vault. The `.env` file template must use `{{ vault_db_password }}`. **2 hardcoded credentials detected in this module (password appears twice — in the CREATE USER statement and in DATABASE_URL).**
- **Plaintext `.env` file**: `/opt/fastapi-tutorial/.env` is written with mode `0644` (world-readable) and contains `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`. **Action required**: Change the Ansible `template` task mode to `0600` and ensure the file is owned by the application service user (not `root`).
- **FastAPI service running as root**: The systemd unit in `fastapi-tutorial/recipes/default.rb` sets `User=root`. **Action required**: Create a dedicated `fastapi` system user in the Ansible role and update the `User=` directive. Adjust directory ownership accordingly.
- **Self-signed SSL certificates**: All three virtual hosts use self-signed certificates generated via `openssl req -x509` with a 365-day validity and a hardcoded subject (`/C=US/ST=Example/...`). Certificates are stored in `/etc/ssl/certs/` and `/etc/ssl/private/`. **Action required**: The Ansible role should use `community.crypto` modules to generate certificates idempotently. For production environments, replace with CA-signed or Let's Encrypt certificates. **0 secrets stored in certificates, but subject metadata is placeholder and must be updated.**
- **SSL private key permissions**: The `ssl.rb` recipe sets key file permissions to `640` owned `root:ssl-cert`. This is correct and must be preserved exactly in the Ansible equivalent tasks.
- **SSH hardening**: Root login and password authentication are disabled via `sed` commands on `/etc/ssh/sshd_config`. **Action required**: Replace with the `ansible.builtin.lineinfile` module (or a dedicated `sshd_config` template) to manage these directives idempotently. Ensure the Ansible control node has a valid SSH key deployed before hardening runs, or the VM will become inaccessible.
- **UFW firewall**: Managed via raw `execute` resources with `not_if` guards. **Action required**: Replace with the `community.general.ufw` module on Ubuntu/Debian targets. On Fedora/RHEL targets, use `ansible.posix.firewalld` instead — UFW is not available on RPM-based systems, which is a platform inconsistency in the current Chef code.
- **fail2ban**: Configured via a template (`fail2ban.jail.local.erb`) with four jails. The template contains no secrets. **Action required**: Convert the ERB template to Jinja2 (no variable substitution is used in the current template, so conversion is trivial). Use `ansible.builtin.template` + `ansible.builtin.service` tasks.
- **Sysctl hardening**: IPv6 is globally disabled (`net.ipv6.conf.all.disable_ipv6 = 1`). ICMP echo is suppressed (`net.ipv4.icmp_echo_ignore_all = 1`). **Action required**: Use the `ansible.posix.sysctl` module for each parameter. Verify that disabling IPv6 and ICMP does not conflict with the target environment's monitoring or management tooling.
- **No Chef Vault or encrypted data bags detected**: The repository uses no Chef Vault, encrypted data bags, or `chef-vault` gem references. All secrets are currently in plaintext in recipe files and `solo.json`.

---

### Technical Challenges

- **`ruby_block` Redis config post-processing**: `cookbooks/cache/recipes/default.rb` uses a `ruby_block` to read, regex-strip, and rewrite `/etc/redis/6379.conf` after `redisio` generates it, removing deprecated directives. This pattern has no direct Ansible equivalent. **Mitigation**: Write the Redis configuration from scratch using an Ansible Jinja2 template that only includes directives valid for the target Redis version, eliminating the need for post-processing entirely. Verify the target Redis package version on Fedora 42 (`redis 7.x`) and ensure the template omits all deprecated `replica-*` directives.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom Chef resource that mimics `ansible.builtin.lineinfile` behavior (match-and-replace or append, with timestamped backup). This resource is not called anywhere in the current recipes (no `lineinfile` calls found in recipe files), suggesting it is dead code or reserved for future use. **Mitigation**: Do not migrate this resource. Use `ansible.builtin.lineinfile` natively in Ansible where line-level file edits are needed.
- **ERB-to-Jinja2 template conversion**: Five ERB templates exist in `nginx-multisite`. The `site.conf.erb` template uses conditional blocks (`<% if @ssl_enabled %>`) and variable interpolation (`<%= @server_name %>`). **Mitigation**: Convert ERB syntax to Jinja2 (`{{ server_name }}`, `{% if ssl_enabled %}`). The logic is straightforward; no complex Ruby expressions are used in any template.
- **Platform inconsistency (UFW on Fedora)**: The `security.rb` recipe installs and configures `ufw`, which is a Debian/Ubuntu tool. The Vagrantfile targets Fedora 42, where `ufw` is not in the default repositories. The current Chef code likely fails on Fedora without additional package sources. **Mitigation**: In the Ansible role, use `ansible_os_family` to branch between `community.general.ufw` (Debian) and `ansible.posix.firewalld` (RedHat). This also fixes the `/var/log/auth.log` path in the fail2ban jail (Fedora uses `/var/log/secure`).
- **Document root path inconsistency**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{site}/`, but `solo.json` overrides them to `/var/www/{site}/`. The `nginx.rb` recipe uses `node['nginx']['sites']` which resolves to the `solo.json` values at runtime. **Mitigation**: Consolidate to a single canonical path in Ansible `group_vars`. Recommend `/var/www/{site}` as the standard, matching the `solo.json` override.
- **Git-based application deployment**: The `fastapi-tutorial` recipe uses `git` resource with `action :sync` to keep `/opt/fastapi-tutorial` up to date from the `main` branch. This means every Chef run may update the application. **Mitigation**: Use `ansible.builtin.git` with `version: main` and `update: yes`. Consider adding a `force: yes` flag to handle local modifications, or pin to a specific commit SHA for production stability.
- **Idempotency of PostgreSQL provisioning**: The `create_db_user` execute block uses `|| true` to suppress errors on duplicate user/database creation. This is a fragile idempotency guard. **Mitigation**: Use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.
- **`systemctl daemon-reload` ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. **Mitigation**: Use the `ansible.builtin.systemd` module with `daemon_reload: yes` in the handler, which is the idiomatic Ansible pattern.
- **Vagrant-specific network configuration**: The Vagrantfile uses a libvirt private network (`192.168.121.10`) and port forwarding. The `vagrant-provision.sh` script references `192.168.56.10` in its output messages (inconsistent with the Vagrantfile IP). **Mitigation**: The Ansible inventory should define the correct IP. The IP inconsistency in the shell script output is a documentation bug and should be corrected.

---

### Migration Order

1. **`nginx-multisite` cookbook** — Migrate first. It is the most complex cookbook but has no runtime dependencies on the other two cookbooks. Establishing the Nginx role, SSL certificate generation, security hardening (fail2ban, UFW/firewalld, sysctl, SSH), and virtual host templating first creates the foundational Ansible role structure and variable conventions that the other roles will follow. Resolving the UFW/firewalld platform split here also sets the pattern for any future OS-family branching.

2. **`cache` cookbook** — Migrate second. It is self-contained (Memcached and Redis are independent services) and has no dependency on `nginx-multisite` or `fastapi-tutorial`. Migrating this second allows the Redis Vault secret (`vault_redis_password`) to be established and the Vault workflow to be validated before tackling the more credential-heavy `fastapi-tutorial` cookbook. The Redis template approach also eliminates the `ruby_block` hack cleanly.

3. **`fastapi-tutorial` cookbook** — Migrate last. It has the highest credential surface (PostgreSQL password, `.env` file, DATABASE_URL), requires a dedicated system user to be created, and depends on PostgreSQL being available before the application service starts. Migrating it last ensures the Vault patterns and service-ordering conventions established in steps 1 and 2 are already in place.

---

### Assumptions

1. **Target OS for Ansible**: The Vagrantfile targets Fedora 42, but cookbook metadata declares Ubuntu ≥ 18.04 and CentOS ≥ 7.0 support. It is assumed that **Fedora 42 / RHEL 9** is the primary production target for the Ansible migration, with Ubuntu support treated as a secondary concern requiring `ansible_os_family` conditionals. If Ubuntu is the actual production target, the firewall module choice (UFW vs firewalld) and log paths must be revisited.

2. **UFW availability on Fedora**: The current Chef `security.rb` recipe installs `ufw` on what is declared as a Fedora target. It is assumed this either fails silently in the current setup or that an additional package repository is configured outside this repository. The Ansible migration will use `firewalld` on RHEL/Fedora and `ufw` on Debian/Ubuntu.

3. **Self-signed certificates are acceptable for all environments**: The SSL recipe generates self-signed certificates with a 365-day validity and placeholder subject fields. It is assumed this is intentional for the development/test scope of this repository. Production deployments would require a separate certificate provisioning strategy (e.g., Let's Encrypt via `community.crypto.acme_certificate` or an internal CA).

4. **Redis single-instance, no clustering**: The `cache` cookbook configures a single Redis instance on port 6379. No Sentinel, Cluster, or replication configuration is present. It is assumed the Ansible migration targets the same single-instance topology.

5. **Memcached default configuration is sufficient**: The `cache` cookbook calls `include_recipe 'memcached'` with no attribute overrides, relying entirely on the community cookbook's defaults. It is assumed the default Memcached configuration (port 11211, 64 MB memory, localhost binding) is intentional and should be preserved in the Ansible role.

6. **FastAPI application repository remains publicly accessible**: The recipe clones `https://github.com/dibanez/fastapi_tutorial.git` from the `main` branch. It is assumed this repository will remain publicly accessible and that the `main` branch is the correct deployment target. If the repository is private or the branch changes, the Ansible `git` task variables must be updated accordingly.

7. **PostgreSQL version is distribution-default**: No specific PostgreSQL version is pinned in the recipe. It is assumed the distribution-default PostgreSQL package is acceptable. On Fedora 42 this is PostgreSQL 16; on Ubuntu 22.04 it is PostgreSQL 14. If a specific version is required, the Ansible role must add the official PostgreSQL APT/YUM repository.

8. **The `lineinfile` custom resource is dead code**: No calls to the custom `lineinfile` resource were found in any recipe file. It is assumed this resource was created for future use or is a leftover and does not need to be migrated.

9. **`solo.json` attribute overrides are the authoritative values**: Where `solo.json` overrides cookbook `attributes/default.rb` values (e.g., document roots `/var/www/{site}` vs `/opt/server/{site}`), the `solo.json` values are treated as the intended runtime configuration and will be used as the defaults in Ansible `group_vars`.

10. **No Chef Server, Chef Vault, or encrypted data bags are in use**: The repository uses Chef Solo exclusively. No Chef Server API, organization, or Vault-encrypted data bags are referenced. All secrets are currently in plaintext and must be migrated to Ansible Vault from scratch.

11. **The project UUID directory (`f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj`) is tooling metadata**: This directory contains a previously generated migration plan, a `solo.json` copy, and project metadata JSON from the X2Ansible tool. It is not part of the Chef infrastructure and does not need to be migrated. It can be added to `.gitignore` or removed.

12. **Vagrant is used for local development only**: The Vagrantfile and `vagrant-provision.sh` are development convenience tools, not production provisioning artifacts. The Ansible migration will target the same VM topology but will be invoked via `ansible-playbook` rather than `vagrant provision`. A `Vagrantfile` using the Ansible provisioner (`config.vm.provision "ansible"`) can optionally replace the current shell provisioner for local testing continuity.
