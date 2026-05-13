# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The entire stack is driven by three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) and four external Chef Supermarket dependencies (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`), all pinned in `Policyfile.lock.json`.

The migration is of **medium complexity**. The cookbooks follow conventional Chef patterns (package/template/service resources, attribute-driven configuration, ERB templates) that map cleanly to Ansible equivalents. The most notable challenges are: a hardcoded Redis password in a cookbook recipe, self-signed TLS certificate generation via raw `openssl` shell commands, a custom `lineinfile` LWRP that duplicates native Ansible functionality, and a post-install Redis config-patching `ruby_block` hack that will need a clean Ansible replacement.

**Estimated migration timeline: 3–4 weeks** for a single engineer, including testing against the existing Vagrant/libvirt environment.

---

## Module Migration Plan

This repository contains three Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), self-signed TLS certificate generation per vhost, HTTP→HTTPS redirect, security-hardened Nginx configuration (server tokens off, rate limiting zones, strict SSL cipher suite, TLSv1.2/1.3 only), and a full suite of HTTP security response headers (HSTS, X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy).
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef (version 1.0.0, requires Chef >= 16.0)
    - Key Features:
        - Five sub-recipes orchestrated by `default.rb`: `security`, `nginx`, `ssl`, `sites`
        - Attribute-driven vhost loop — site names, document roots, and SSL toggle are all driven by `node['nginx']['sites']` hash (defined in `attributes/default.rb` and overridden in `solo.json`)
        - Per-vhost self-signed certificate generation via `openssl req -x509` shell command (idempotent via `not_if` file existence check); certificates stored in `/etc/ssl/certs`, private keys in `/etc/ssl/private` with `0710` permissions and `ssl-cert` group ownership
        - Static site content (three `index.html` files for `test`, `ci`, `status` sub-sites) deployed via `cookbook_file` resource
        - UFW firewall configured with default-deny policy, SSH/HTTP/HTTPS allow rules
        - fail2ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`
        - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` commands
        - Kernel hardening via `/etc/sysctl.d/99-security.conf`: IP spoofing protection, ICMP redirect rejection, SYN flood protection, IPv6 disable
        - Custom LWRP `lineinfile` resource (reimplements Ansible's `lineinfile` module in Ruby)

- **cache**:
    - Description: Caching layer provisioning Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, a custom log directory, and a post-install config-patching workaround for deprecated Redis directive names.
    - Path: `cookbooks/cache`
    - Technology: Chef (version 1.0.0, requires Chef >= 16.0)
    - Key Features:
        - Delegates Memcached installation entirely to the `memcached` community cookbook (no local attribute overrides)
        - Redis configured on port `6379` with `requirepass` set to a hardcoded plaintext password (`redis_secure_password_123`) via `node.default['redisio']['servers']`
        - Creates `/var/log/redis` directory with `redis:redis` ownership
        - Includes `redisio` and `redisio::enable` recipes
        - `ruby_block "fix_redis_config"` post-processes `/etc/redis/6379.conf` to strip five deprecated directive lines (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that cause `redisio 7.2.4` to fail on newer Redis versions — this is an acknowledged hack in the source code

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application from a public GitHub repository, including system package installation, Python virtual environment creation, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and a systemd unit file for process supervision.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef (version 1.0.0, requires Chef >= 16.0)
    - Key Features:
        - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial` using the Chef `git` resource with `:sync` action
        - Creates Python venv at `/opt/fastapi-tutorial/venv` and installs `requirements.txt` via pip
        - Enables and starts the `postgresql` system service
        - Provisions PostgreSQL role `fastapi` with hardcoded password `fastapi_password`, database `fastapi_db`, and full privileges — executed via `sudo -u postgres psql` shell commands with `|| true` error suppression
        - Writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` in plaintext, owned by `root:root` with mode `0644`
        - Writes `/etc/systemd/system/fastapi-tutorial.service` running uvicorn as `User=root` on `0.0.0.0:8000`, with `After=postgresql.service`
        - Runs `systemctl daemon-reload` and enables/starts the `fastapi-tutorial` service

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest listing all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but present and locked in `Policyfile.rb` / `Policyfile.lock.json`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Fully resolved and pinned dependency graph. Locks: `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4` (transitive dep of redisio), `ssl_certificate 2.1.0`. This file is the authoritative source of truth for dependency versions.
- `solo.json`: Chef Solo node JSON providing run list and attribute overrides. Overrides document roots to `/var/www/<site>` (conflicting with the cookbook attribute default of `/opt/server/<site>`), sets `ssl.certificate_path` and `ssl.private_key_path`, and enables all security features (`fail2ban`, `ufw`, `ssh.disable_root`, `ssh.password_auth: false`).
- `solo.rb`: Chef Solo configuration pointing cache path to `/var/chef-solo` and cookbook path to `/chef-repo/cookbooks`.
- `Vagrantfile`: Vagrant configuration using `generic/fedora42` box, libvirt provider (2 vCPUs, 2 GB RAM), private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, rsync-based folder sync of the repo to `/chef-repo`, and shell provisioner calling `vagrant-provision.sh`.
- `vagrant-provision.sh`: Bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor cookbooks`, and then executes `chef-solo -c solo.rb -j solo.json`. This is the sole entry point for converging the node.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory containing a prior draft `migration-plan.md`, a `generated-project-metadata.json` module inventory, and a duplicate `solo.json`. These are artefacts of a previous analysis run and are not part of the active Chef configuration.

---

### Target Details

- **Operating System**: **Fedora 42** is the active development target (specified in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu >= 18.04 and CentOS >= 7.0, but the provisioning scripts use `apt-get` (Debian/Ubuntu package manager), indicating the Vagrant environment may diverge from the declared metadata. The Ansible migration should target **Red Hat Enterprise Linux 9 / Fedora** as primary, with Ubuntu 22.04 LTS as a secondary supported platform.
- **Virtual Machine Technology**: **KVM/libvirt** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`.
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK packages are referenced anywhere in the repository. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Community Chef cookbook wrapping Nginx package installation and base configuration. Replace with the `ansible.builtin.package` module for installation and Jinja2 templates for `nginx.conf` and `conf.d/security.conf`. The `nginx_core` Ansible collection (`nginxinc.nginx_core`) is an optional drop-in if a community role is preferred.
- **memcached (6.1.0)** — Community Chef cookbook. Replace with `ansible.builtin.package` + `ansible.builtin.service` + a template for `/etc/memcached.conf`. No complex configuration is applied locally; the cookbook is included with all defaults.
- **redisio (7.2.4)** — Community Chef cookbook for Redis installation and service management. Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/6379.conf` (or the distro-default path). The post-install config-patching hack in `cache::default` must be replaced with a clean Ansible template that simply omits the deprecated directives from the outset.
- **ssl_certificate (2.1.0)** — Community Chef cookbook for TLS certificate management. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` Ansible modules from the `community.crypto` collection for self-signed certificate generation.
- **selinux (6.2.4)** — Transitive dependency of `redisio`; manages SELinux policy. Replace with `ansible.posix.selinux` module and `ansible.posix.seboolean` as needed.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123`) in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`): This plaintext credential must be extracted and stored in **Ansible Vault** before migration. Create a vault-encrypted variable `vault_redis_password` and reference it in the Redis configuration template.
- **Hardcoded PostgreSQL credentials** in `cookbooks/fastapi-tutorial/recipes/default.rb`: The PostgreSQL role password (`fastapi_password`) appears in three places — the `psql` provisioning command, the `.env` file content, and implicitly in the `DATABASE_URL`. All three must be replaced with a single Ansible Vault variable (e.g., `vault_fastapi_db_password`).
- **Plaintext `.env` file** at `/opt/fastapi-tutorial/.env` with `DATABASE_URL` containing credentials, written with mode `0644` (world-readable). In the Ansible role, this file should be deployed with mode `0600`, owned by the application service user (not `root`), and its content sourced from Ansible Vault variables.
- **FastAPI service running as root** (`User=root` in the systemd unit): This is a significant security risk. The Ansible migration should create a dedicated unprivileged system user (e.g., `fastapi`) and run the service under that account.
- **Self-signed TLS certificates**: Generated via raw `openssl` shell commands with `not_if` idempotency guards. The `community.crypto` Ansible collection provides idiomatic, fully idempotent equivalents. Certificate subject fields currently embed `admin@example.com` and placeholder organisation values — these should be parameterised as Ansible variables.
- **SSH hardening via `sed`**: The current approach uses `sed -i` to modify `/etc/ssh/sshd_config` with `not_if` guards. Replace with `ansible.builtin.lineinfile` or a full `sshd_config` template managed by Ansible for deterministic, auditable configuration.
- **UFW firewall rules**: Managed via raw `ufw` shell commands with `not_if` guards checking `ufw status` output. Replace with the `community.general.ufw` Ansible module for idiomatic, idempotent firewall management. Note: on RHEL/Fedora targets, `firewalld` is the default firewall manager — the migration must decide between UFW (Ubuntu-centric) and firewalld (RHEL-centric) based on the final target OS.
- **fail2ban configuration**: The `jail.local` template is well-structured and can be migrated directly as an Ansible Jinja2 template. The `maxretry`, `bantime`, and `findtime` values should be exposed as Ansible variables.
- **Kernel sysctl hardening**: The `sysctl-security.conf.erb` template is a static file with no ERB interpolation. It can be migrated as a verbatim Ansible `files/` asset deployed via `ansible.builtin.copy`, or as a set of `ansible.posix.sysctl` module calls for individual parameter management.
- **Credential count summary**:
    - `cache` cookbook: 1 hardcoded credential (Redis `requirepass`)
    - `fastapi-tutorial` cookbook: 2 hardcoded credentials (PostgreSQL role password, `DATABASE_URL` in `.env`)
    - `nginx-multisite` cookbook: 0 runtime credentials (certificate subject fields are placeholder values only)
    - **Total: 3 credentials requiring Ansible Vault protection**

---

### Technical Challenges

- **`solo.json` vs. `attributes/default.rb` conflict**: The `solo.json` node JSON overrides document roots to `/var/www/<site>` while `attributes/default.rb` defaults to `/opt/server/<site>`. The `vagrant-provision.sh` script runs Chef Solo with `solo.json`, so `/var/www/<site>` is the effective runtime value. However, the static `index.html` files reference `/opt/server/<site>` in their content. The Ansible migration must canonicalise on one path and update both the vhost configuration and the static file content accordingly.
- **Redis config-patching `ruby_block` hack**: The `cache` cookbook post-processes the Redis config file generated by `redisio` to strip deprecated directives. In Ansible, this entire pattern is eliminated by owning the Redis configuration template directly — the Ansible role should render `/etc/redis/redis.conf` (or the distro-specific path) from a Jinja2 template that never includes the deprecated directives, making the hack unnecessary.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` reimplements Ansible's native `ansible.builtin.lineinfile` module in Ruby. This resource is defined but not called anywhere in the current recipes — it can be dropped entirely during migration with no functional impact.
- **Multi-platform package name divergence**: The `vagrant-provision.sh` script uses `apt-get` (Debian/Ubuntu), but the Vagrantfile targets Fedora 42 (which uses `dnf`). This inconsistency suggests the provisioning script may not work as-is on the declared target OS. The Ansible migration must use `ansible.builtin.package` with platform-conditional variable files (`vars/Debian.yml`, `vars/RedHat.yml`) to handle package name differences (e.g., `libpq-dev` on Debian vs. `postgresql-devel` on RHEL, `python3-venv` vs. `python3-virtualenv`).
- **Git-based application deployment**: The `fastapi-tutorial` cookbook clones a public GitHub repository at converge time. In Ansible, `ansible.builtin.git` provides equivalent functionality, but the migration should consider whether a `requirements.txt`-pinned deployment or an artifact-based deployment (wheel/tarball) is more appropriate for production use.
- **Nginx `sites-available` / `sites-enabled` symlink pattern**: This is a Debian/Ubuntu Nginx convention. On RHEL/Fedora, Nginx uses `conf.d/` drop-in files. The Ansible role must handle this divergence, either by standardising on `conf.d/` or by conditionally creating the `sites-available`/`sites-enabled` directories on RHEL targets.
- **Attribute path override pattern**: Chef's attribute precedence system (default → normal → override) is used to allow `solo.json` to override cookbook defaults. In Ansible, this maps to variable precedence (role defaults → group_vars → host_vars → extra_vars). The migration must map each Chef attribute to the appropriate Ansible variable scope.
- **Service name divergence**: The SSH service is named `ssh` on Debian/Ubuntu and `sshd` on RHEL/Fedora. The `security.rb` recipe notifies `service[ssh]` — the Ansible role must use a platform-conditional service name variable.

---

### Migration Order

The following order minimises risk by migrating independent components first and deferring the most complex cookbook (with the most security issues and external dependencies) to last:

1. **`cache` role** — Lowest structural complexity; two independent services (Memcached, Redis) with no intra-stack dependencies. Migrating this first also forces the resolution of the hardcoded Redis password into Ansible Vault, establishing the secrets management pattern for the rest of the migration. The Redis config-patching hack is eliminated cleanly by owning the template.

2. **`nginx-multisite` role** — Medium complexity; self-contained web server configuration with well-understood Ansible equivalents for every Chef resource used. The security sub-recipe (fail2ban, UFW, SSH hardening, sysctl) should be extracted into a dedicated `security` role to promote reuse. Migrating this second validates the Jinja2 templating approach and the `community.crypto` certificate generation before the more complex application cookbook.

3. **`fastapi-tutorial` role** — Highest complexity; involves the most hardcoded credentials, a running-as-root service, a git-based deployment, PostgreSQL provisioning, and the most platform-sensitive package names. Should be migrated last, after the Ansible Vault pattern and platform variable files are established by the earlier roles.

---

### Assumptions

1. **Target OS ambiguity**: The `Vagrantfile` specifies `generic/fedora42`, but `vagrant-provision.sh` uses `apt-get` (a Debian/Ubuntu tool). It is assumed that the intended production target is a **RHEL-family OS** (Fedora/RHEL/CentOS Stream) and that the `apt-get` call in the provisioning script is a latent bug. The Ansible migration will target RHEL 9 / Fedora as primary, with Ubuntu 22.04 as a secondary supported platform, using platform-conditional variable files.

2. **Self-signed certificates are development-only**: The `openssl req -x509` certificate generation is assumed to be acceptable only for the Vagrant development environment. It is assumed that production deployments will require externally issued certificates (e.g., Let's Encrypt via `community.crypto.acme_certificate` or organisation PKI). The migration plan documents both paths but implements self-signed generation to match current behaviour.

3. **Document root canonical path**: Given the conflict between `solo.json` (`/var/www/<site>`) and `attributes/default.rb` (`/opt/server/<site>`), it is assumed that `/var/www/<site>` is the intended runtime path (as `solo.json` is the active node configuration). The Ansible role will default to `/var/www/<site>` and the static `index.html` content will be updated to reflect this.

4. **Redis standalone mode**: No Redis Sentinel, Cluster, or replication configuration is present. It is assumed Redis will continue to run as a single standalone instance. The `replicaservestaledata: nil` value in the `redisio` server hash (which triggers the config-patching hack) confirms replication is intentionally disabled.

5. **Memcached default configuration**: The `cache` cookbook includes `memcached` with no attribute overrides, meaning all Memcached settings (port 11211, 64 MB memory, localhost binding) are community cookbook defaults. It is assumed these defaults are acceptable and will be carried forward as Ansible role defaults.

6. **FastAPI application repository availability**: The cookbook clones `https://github.com/dibanez/fastapi_tutorial.git` at provision time. It is assumed this public repository will remain available and that the `main` branch is stable. If the repository becomes private or is relocated, the Ansible role's `git` task will need updated credentials or a new URL.

7. **PostgreSQL version**: No explicit PostgreSQL version is specified in the cookbook — it installs whatever version is available in the OS package repository. It is assumed the default repository version is acceptable. If a specific version is required, the Ansible role should add the official PostgreSQL APT/YUM repository.

8. **No Chef Server or Chef Automate**: The stack uses Chef Solo exclusively (no Chef Server, no Policyfile push, no Automate pipeline). The migration does not need to account for Chef Server API calls, data bags, or Chef Vault — the only secrets present are hardcoded in recipe files.

9. **No encrypted data bags or Chef Vault**: Confirmed by inspection — no `chef-vault` gem usage, no `data_bag_item` calls, and no `encrypted_data_bag_secret` references exist anywhere in the repository. All credentials are currently plaintext in recipe files and the `.env` file.

10. **The `lineinfile` custom resource is unused**: The LWRP defined in `cookbooks/nginx-multisite/resources/lineinfile.rb` is not called by any recipe in this repository. It is assumed it was created speculatively and can be dropped without any functional impact during migration.

11. **Vagrant/libvirt environment is preserved for testing**: It is assumed the existing `Vagrantfile` and libvirt setup will be retained as the integration test environment during migration, with the Chef provisioner replaced by an Ansible provisioner (`config.vm.provision "ansible"`) pointing at the new playbooks.
