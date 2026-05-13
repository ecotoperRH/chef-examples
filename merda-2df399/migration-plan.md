# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site web server environment composed of three cookbooks: an Nginx reverse proxy with multi-site SSL virtual hosting and security hardening (`nginx-multisite`), a dual caching layer using Memcached and Redis (`cache`), and a Python FastAPI application backed by PostgreSQL (`fastapi-tutorial`). The full run list is executed in sequence via `chef-solo` inside a Vagrant-managed Libvirt VM running **Fedora 42**.

The migration to Ansible is assessed as **medium complexity**. All three cookbooks use standard Chef resource patterns (package, template, service, execute, directory, file, git) that map cleanly to well-supported Ansible modules. The primary risks are: hardcoded credentials in recipe source code, a workaround `ruby_block` that patches a Redis config file post-generation, self-signed certificate generation via raw `openssl` shell commands, and UFW firewall management that must be reconciled with Fedora's default `firewalld`. No Chef encrypted data bags or Chef Vault usage was detected; credentials are stored in plain text.

**Estimated migration timeline: 3–4 weeks** for a single engineer, including testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a global security hardening layer (fail2ban, UFW firewall, kernel sysctl tuning), SSH hardening, and per-site self-signed TLS certificate generation via `openssl req`. Each virtual host enforces HTTP→HTTPS redirect, TLS 1.2/1.3-only ciphers, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, Referrer-Policy).
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Data-driven multi-site loop from node attributes, ERB-templated `nginx.conf` and per-site `site.conf`, `security.conf` with rate-limiting zones, fail2ban jail configuration for SSH and Nginx, sysctl hardening (IP spoofing protection, ICMP suppression, SYN-cookie flood protection, IPv6 disable), custom `lineinfile` LWRP resource, static HTML content files per virtual host (ci, status, test), UFW rule management via `execute` resources.

- **cache**:
    - Description: Dual in-memory caching services: Memcached (delegated entirely to the upstream `memcached` community cookbook v6.1.0) and Redis (via `redisio` v7.2.4) with password authentication enabled on port 6379. Includes a post-install `ruby_block` workaround that strips deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` to ensure compatibility with the installed Redis version.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Redis password authentication (`requirepass`), Redis log directory creation at `/var/log/redis`, post-install config-file patching via `ruby_block`, Memcached via community cookbook delegation, `redisio::enable` for service management.

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application sourced from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`). Provisions system packages (Python 3, pip, venv, git, PostgreSQL with `libpq-dev`), creates a Python virtual environment, installs pip dependencies from `requirements.txt`, configures and starts PostgreSQL, creates a dedicated database user (`fastapi`) and database (`fastapi_db`), writes a `.env` file with the database connection string, and registers a `systemd` unit file (`fastapi-tutorial.service`) that starts the application via `uvicorn` on port 8000.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git-based application deployment with `:sync` action, Python venv isolation, PostgreSQL user/database provisioning via `psql` shell commands, `.env` file with embedded credentials, systemd service unit with `daemon-reload` notification, application runs as `root` user (security concern), uvicorn ASGI server on `0.0.0.0:8000`.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external Supermarket dependencies: `nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, and `ssl_certificate ~> 2.1` (the `ssl_certificate` entry is commented out in Berksfile but active in `Policyfile.rb`). Must be replaced by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy` and the ordered run list: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`. The run list order encodes an implicit dependency: security and web server are configured before the application tier. This ordering must be preserved in Ansible playbook task ordering.
- `Policyfile.lock.json`: Locked dependency graph with resolved versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4` (transitive dependency of `redisio`). Confirms all three local cookbooks at version `1.0.0`. No remote Git sources; all external cookbooks resolved from Chef Supermarket.
- `solo.json`: Chef Solo node JSON providing runtime attributes. Overrides document roots to `/var/www/<site>` (differing from the cookbook attribute defaults of `/opt/server/<site>`), confirms SSL enabled for all three sites, sets SSL certificate/key paths, and enables all security features (fail2ban, UFW, SSH root login disabled, password auth disabled). This file is the authoritative source for site configuration and must be translated into Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks`, with cache at `/var/chef-solo`. Relevant only for understanding the Chef Solo execution context; no direct Ansible equivalent needed.
- `Vagrantfile`: Vagrant configuration using the `generic/fedora42` box with Libvirt provider (2 vCPUs, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync sync of the repo to `/chef-repo`. Provisions via `vagrant-provision.sh`. Defines the target OS as **Fedora 42** and the VM platform as **Libvirt/KVM**. Should be adapted to use the `ansible` Vagrant provisioner post-migration.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo -c solo.rb -j solo.json`. This entire script is replaced by Ansible's agentless push model; no equivalent bootstrap is needed.

---

### Target Details

- **Operating System**: Fedora 42 (explicitly declared in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0, indicating cross-platform intent. Ansible playbooks should target the `dnf` package manager for Fedora/RHEL and include conditional `apt` support for Debian/Ubuntu where needed.
- **Virtual Machine Technology**: Libvirt/KVM (declared in `Vagrantfile` under `config.vm.provider "libvirt"`). VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references detected. The infrastructure appears designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install `nginx` from the OS package manager, plus `ansible.builtin.template` for `nginx.conf`, `security.conf`, and per-site virtual host configs. Consider the `nginxinc.nginx` Ansible Galaxy role for more complex scenarios, but given the fully custom templates already present, direct module usage is preferred.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` to install `memcached` and `ansible.builtin.service` to enable/start it. The upstream Chef cookbook performs only basic install-and-start; no complex configuration is needed.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (`redis` on Fedora/RHEL, `redis-server` on Debian/Ubuntu), `ansible.builtin.template` for `/etc/redis/6379.conf`, and `ansible.builtin.service`. The `requirepass` directive and the post-install config-patching workaround must be handled natively in the Ansible-managed template, eliminating the need for the `ruby_block` hack entirely.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection. This provides idempotent, declarative certificate management without shelling out to `openssl`.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with `ansible.posix.selinux` module. On Fedora 42, SELinux is enforcing by default; any Redis or Nginx file path changes may require SELinux context adjustments via `community.general.sefcontext`.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line 7): This credential is stored in plain text in the recipe source. **Must be migrated to Ansible Vault** as an encrypted variable (e.g., `vault_redis_password`). Count: **1 hardcoded service credential**.
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb`, lines 32–34, and again in the `.env` file content on line 44): The database password appears twice in the same recipe. **Must be migrated to Ansible Vault**. Count: **1 hardcoded database credential (referenced in 2 locations)**.
- **`.env` file with plaintext `DATABASE_URL`**: The recipe writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` using mode `0644` (world-readable). In Ansible, this file must be templated from a Vault-encrypted variable and the file mode tightened to at minimum `0640` or `0600`.
- **Self-signed TLS certificates**: The `ssl.rb` recipe generates self-signed certificates via a raw `openssl req` shell command with a hardcoded subject string (`/C=US/ST=Example/...`). These are development-only certificates. In Ansible, use `community.crypto` modules for idempotent generation. For production, integrate with Let's Encrypt via `community.crypto.acme_certificate` or an external PKI.
- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed` commands wrapped in `execute` resources. In Ansible, replace with `ansible.builtin.lineinfile` or `ansible.builtin.template` for the full `sshd_config` to ensure idempotency and auditability.
- **Application running as root**: The `fastapi-tutorial.service` systemd unit sets `User=root`. This is a significant security risk. The Ansible migration should create a dedicated unprivileged system user (e.g., `fastapi`) and run the service under that account.
- **UFW vs. firewalld**: The `security.rb` recipe uses `ufw` (Debian/Ubuntu firewall frontend). Fedora 42 uses `firewalld` by default. The Ansible migration must use `ansible.posix.firewalld` for Fedora targets and conditionally use `community.general.ufw` for Ubuntu targets, or standardize on one firewall manager.
- **fail2ban configuration**: The `jail.local` template is static (no node attribute interpolation). It can be directly copied as an Ansible `files/` static file or kept as a template. No secrets involved.
- **Sysctl hardening**: The `sysctl-security.conf.erb` template is fully static. Use `ansible.posix.sysctl` module for individual parameter management, or deploy the file via `ansible.builtin.copy` and notify a handler to reload sysctl.
- **No Chef Vault or encrypted data bags detected**: Credential protection is entirely absent in the source. Ansible Vault adoption during migration represents a net security improvement.
- **Total credentials requiring Ansible Vault protection**: **2 distinct secrets** (Redis password, PostgreSQL password).

---

### Technical Challenges

- **Redis config post-install patching (`ruby_block`)**: The `cache` cookbook uses a `ruby_block` to strip deprecated Redis directives from `/etc/redis/6379.conf` after `redisio` generates it. This is a workaround for an incompatibility between the `redisio` cookbook's template and the installed Redis version. In Ansible, the Redis configuration file will be fully managed by an Ansible template, so the deprecated directives simply will not be present — eliminating the need for this workaround entirely. Care must be taken to audit which Redis directives are valid for the Redis version available on Fedora 42.
- **Data-driven multi-site Nginx loop**: The `nginx-multisite` cookbook iterates over `node['nginx']['sites']` to generate virtual host configs, document root directories, and SSL certificates. In Ansible, this maps naturally to a `loop` over a `nginx_sites` list variable, but the variable structure must be carefully translated from the Chef attribute hash (keyed by site name) to an Ansible-friendly list of dicts. The `solo.json` overrides the document roots relative to the cookbook defaults — this discrepancy must be resolved in the Ansible variable definition.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` resource (`resources/lineinfile.rb`) that replicates functionality already native to Ansible (`ansible.builtin.lineinfile`). This resource does not appear to be called anywhere in the cookbook recipes (no `lineinfile` calls found in recipe files), but its presence should be noted. No migration action required beyond confirming it is unused.
- **Cross-platform package name differences**: Package names differ between Fedora (`redis`, `python3-pip`, `postgresql-server`) and Ubuntu (`redis-server`, `python3-pip`, `postgresql`). Ansible tasks must use `ansible.builtin.package` with platform-conditional variable files (`vars/RedHat.yml`, `vars/Debian.yml`) or `when` conditionals to handle naming differences.
- **PostgreSQL initialization on Fedora**: On Fedora/RHEL, PostgreSQL requires explicit `postgresql-setup --initdb` before the service can start, unlike Ubuntu where the package post-install script handles this. The `fastapi-tutorial` recipe assumes Ubuntu-style behavior. The Ansible role must include a task to initialize the PostgreSQL data directory on RHEL-family systems.
- **`psql` idempotency**: The recipe uses `|| true` to suppress errors from duplicate `CREATE USER`/`CREATE DATABASE` statements. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require error suppression hacks.
- **Git deployment with `:sync` action**: The recipe uses Chef's `git` resource with `:sync` to keep the application directory up to date. In Ansible, `ansible.builtin.git` with `update: yes` provides equivalent behavior, but care must be taken with the `force` option if local modifications exist.
- **systemd `daemon-reload` notification**: The recipe notifies `execute[systemd_reload]` immediately when the service file changes. In Ansible, use a handler with `ansible.builtin.systemd` and `daemon_reload: yes` to achieve the same effect idiomatically.
- **Document root path discrepancy**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/<site>`, but `solo.json` overrides them to `/var/www/<site>`. The Ansible variable definition must use the `solo.json` values (`/var/www/<site>`) as the authoritative source, as these represent the actual deployed configuration.

---

### Migration Order

1. **`cache` cookbook** — Migrate first as it is the most self-contained cookbook with no inbound dependencies from the other two cookbooks. Memcached and Redis are independent services. Migrating this first also forces resolution of the Ansible Vault strategy for the Redis password before it is needed elsewhere. Estimated effort: **3–4 days**.

2. **`nginx-multisite` cookbook** — Migrate second. It has no runtime dependency on `cache` or `fastapi-tutorial`, but it is the most complex cookbook (5 recipes, 5 templates, 1 custom resource, 3 static file sets, security hardening). Resolving the UFW vs. firewalld challenge and the SSL certificate generation approach here establishes patterns reused in the final cookbook. Estimated effort: **6–8 days**.

3. **`fastapi-tutorial` cookbook** — Migrate last. It depends on PostgreSQL (which it installs itself) and implicitly on the Nginx virtual host infrastructure being in place to proxy traffic. It also carries the highest security debt (root service user, plaintext `.env`, hardcoded DB credentials) that must be addressed during migration. Estimated effort: **4–5 days**.

---

### Assumptions

1. **Target OS is Fedora 42** as declared in the `Vagrantfile`. The cookbook `metadata.rb` files claim Ubuntu ≥ 18.04 and CentOS ≥ 7.0 support, but no Ubuntu- or CentOS-specific testing infrastructure exists in this repository. The Ansible migration will primarily target Fedora 42 / RHEL 9-family, with Ubuntu compatibility treated as a secondary goal requiring separate validation.
2. **Self-signed certificates are acceptable for the target environment**. The `ssl.rb` recipe explicitly generates self-signed certificates described as "for development." If this infrastructure is intended for production use, a proper PKI or ACME/Let's Encrypt integration must be scoped as additional work not covered by a direct migration.
3. **The FastAPI application repository (`https://github.com/dibanez/fastapi_tutorial.git`) remains publicly accessible** and the `main` branch is stable. If the repository is private or the branch changes, the `ansible.builtin.git` task will require credential configuration.
4. **Redis and Memcached are single-node, non-clustered deployments**. No replication, Sentinel, or Cluster configuration is present in the source. The Ansible migration will maintain this topology.
5. **The `ssl_certificate` community cookbook** is declared in `Policyfile.rb` and locked in `Policyfile.lock.json` but is **commented out in `Berksfile`** and not referenced in any recipe. It is assumed to be unused and will not be migrated.
6. **The custom `lineinfile` LWRP** defined in `cookbooks/nginx-multisite/resources/lineinfile.rb` is not called by any recipe in this repository. It is assumed to be dead code and will not be migrated to Ansible.
7. **The `solo.json` attribute values are authoritative** over the cookbook `attributes/default.rb` defaults where they conflict (specifically, document roots `/var/www/<site>` vs. `/opt/server/<site>`). The Ansible `group_vars` will use the `solo.json` values.
8. **No existing Ansible inventory or playbook structure exists** in this repository. The migration will establish a new `ansible/` directory with roles, playbooks, inventory, and `group_vars` from scratch following Ansible best practices.
9. **The `selinux` cookbook** (v6.2.4, a transitive dependency of `redisio`) is resolved in the lock file but not explicitly configured in any recipe. It is assumed that SELinux management will be handled via the `ansible.posix.selinux` module and `community.general.sefcontext` as needed for file context adjustments, rather than disabling SELinux.
10. **Vagrant will continue to be used** as the local development and testing environment post-migration. The `Vagrantfile` will be updated to use the `ansible` provisioner in place of the shell provisioner, pointing to the new Ansible playbook entry point.
11. **The `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/` directory** is a project metadata artifact from the X2Ansible tooling and is not part of the infrastructure source. It will not be migrated.
12. **No high-availability or load-balancing requirements** are implied by the current configuration. All three services (Nginx, cache, FastAPI) are co-located on a single VM. The Ansible roles will be written to support single-host deployment, with multi-host inventory expansion as a future concern.
