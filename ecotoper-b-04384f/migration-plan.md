# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a single Vagrant-based virtual machine (Fedora 42 / libvirt) running three cooperating services: a multi-site Nginx reverse proxy with SSL, a caching layer (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL. The full run-list is `nginx-multisite → cache → fastapi-tutorial`.

The migration scope is **3 local cookbooks** and **5 external Supermarket cookbook dependencies**, all targeting Ubuntu ≥ 18.04 / CentOS ≥ 7.0 (with the Vagrant box currently pinned to Fedora 42). Complexity is **moderate**: the logic is well-structured, but several security concerns (hardcoded credentials, self-signed certificates, root-run application service) and a Chef-specific config-patching hack in the `cache` cookbook require deliberate handling in Ansible.

**Estimated migration timeline: 2–3 weeks** for a single engineer, or 1 week with a two-person team.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that need individual migration planning.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths were confirmed in the provided repository tree are listed below.

---

- **nginx-multisite**
  - **Description**: Nginx web server with multi-site virtual host management, SSL termination using self-signed certificates, firewall hardening (UFW + fail2ban), and kernel-level security tuning via sysctl. Serves three subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with its own document root and SSL certificate pair.
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef
  - **Key Features**:
    - Nginx installation and `nginx.conf` templating (`nginx.conf.erb`)
    - Per-site `sites-available`/`sites-enabled` symlink management (`site.conf.erb`)
    - Self-signed RSA-2048 certificate generation via `openssl req -x509` (365-day validity)
    - SSL directory layout with `ssl-cert` group and `0710` permissions on private key path
    - Security hardening: UFW default-deny with SSH/HTTP/HTTPS allow rules, fail2ban with `jail.local` template, sysctl security parameters (`sysctl-security.conf.erb`)
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no` via `sed` in-place edits
    - Static site content deployed from `files/default/{ci,status,test}/index.html`
    - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`)
    - Node attributes drive all site definitions, SSL paths, and security toggles

---

- **cache**
  - **Description**: Dual caching layer that installs and configures Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication. Includes a post-install Ruby block that patches the Redis config file to strip deprecated `replica-*` directives incompatible with the installed Redis version.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef
  - **Key Features**:
    - Memcached installation delegated to `memcached` community cookbook (v6.1.0)
    - Redis on port 6379 with `requirepass` authentication
    - `/var/log/redis` directory creation with correct ownership
    - `redisio` (v7.2.4) + `redisio::enable` for service management
    - Post-install `ruby_block` hack to remove deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf`
    - Transitive dependency on `selinux` cookbook (v6.2.4) pulled in by `redisio`

---

- **fastapi-tutorial**
  - **Description**: Full-stack Python application deployment that clones a FastAPI tutorial project from GitHub, sets up a Python 3 virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file, and registers the application as a systemd service running under `root`.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef
  - **Key Features**:
    - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Git clone of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) to `/opt/fastapi-tutorial`
    - Python venv creation and `pip install -r requirements.txt`
    - PostgreSQL service enable/start; `psql` commands to create user `fastapi`, database `fastapi_db`, and grant privileges
    - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL` with embedded plaintext credentials
    - systemd unit file for `fastapi-tutorial.service` running `uvicorn` on `0.0.0.0:8000`; service runs as `root`
    - `systemctl daemon-reload` triggered on unit file change

---

### Infrastructure Files

- **`Berksfile`**: Berkshelf dependency resolver. Declares all three local cookbooks by path and pins external cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). The `ssl_certificate` dependency is commented out in Berksfile but active in Policyfile — this inconsistency should be resolved before migration.
- **`Policyfile.rb`**: Chef Policyfile defining the `nginx-multisite-policy` run-list. Supersedes Berksfile for policy-based workflows. Locks all cookbook versions.
- **`Policyfile.lock.json`**: Fully resolved dependency lock file. Pins: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`. This is the authoritative version reference for Ansible role equivalents.
- **`solo.rb`**: Chef Solo configuration. Sets cache path to `/var/chef-solo` and cookbook path to `/chef-repo/cookbooks`. Relevant only during transition; no Ansible equivalent needed.
- **`solo.json`**: Chef Solo node JSON (run-list + node attributes). Contains the full site map, SSL paths, and security flags. This file is the primary source of truth for Ansible `group_vars` / `host_vars` variable definitions.
- **`Vagrantfile`**: Vagrant VM definition using `generic/fedora42` box with libvirt provider (2 vCPU, 2 GB RAM). Exposes ports 80→8080 and 443→8443. Provisions via `vagrant-provision.sh`. The Ansible inventory should reflect the same network configuration (`192.168.121.10`).
- **`vagrant-provision.sh`**: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. In Ansible, this entire script is replaced by `ansible-playbook` invocation. The script also reveals that the target OS at provision time is Debian/Ubuntu-family (`apt-get`), despite the Vagrant box being Fedora — this is a discrepancy to investigate.

---

### Target Details

- **Operating System**: The `metadata.rb` files declare support for **Ubuntu ≥ 18.04** and **CentOS ≥ 7.0**. The `vagrant-provision.sh` bootstrap uses `apt-get`, indicating Ubuntu/Debian is the primary tested target. The Vagrantfile uses `generic/fedora42`, which is a discrepancy. Ansible roles should be written for **Ubuntu 22.04 LTS** as the primary target, with conditional task blocks for RHEL/CentOS compatibility where needed.
- **Virtual Machine Technology**: **libvirt / KVM** (declared in `Vagrantfile` via `config.vm.provider "libvirt"`). Vagrant is used purely for local development/testing; the Ansible inventory should support both Vagrant-managed VMs and bare-metal/cloud targets.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider SDKs are present. The infrastructure appears to be on-premises or local virtualization only.

---

## Migration Approach

### Key Dependencies to Address

- **`nginx` (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install `nginx` from the OS package manager, plus `ansible.builtin.template` for `nginx.conf` and per-site configs. The community `nginxinc.nginx` Ansible Galaxy role is an optional drop-in if a richer abstraction is needed.
- **`memcached` (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service`. No complex configuration is applied beyond defaults; a simple role suffices.
- **`redisio` (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `redis-server`), `ansible.builtin.template` for `redis.conf`, and `ansible.builtin.service`. The post-install config-patching hack (see Technical Challenges) must be replaced with a proper Jinja2 template that never emits the deprecated directives in the first place.
- **`selinux` (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. On RHEL/CentOS targets, use the `ansible.posix.selinux` module and `community.general.seboolean` as needed. On Ubuntu targets, this dependency is a no-op and can be skipped entirely.
- **`ssl_certificate` (2.1.0, Chef Supermarket)**: Currently locked in `Policyfile.lock.json` but commented out in `Berksfile` and not explicitly called in any recipe. Verify whether it is actually used at runtime. If not, omit from Ansible. If yes, replace with `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey`.

---

### Security Considerations

- **Hardcoded Redis password**: `cookbooks/cache/recipes/default.rb` sets `requirepass` to the literal string `redis_secure_password_123`. In Ansible, this must be moved to **Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable (e.g., `{{ redis_password }}`).
- **Hardcoded PostgreSQL credentials**: `cookbooks/fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` directly in `psql` commands and writes it in plaintext to `/opt/fastapi-tutorial/.env`. Both the `postgresql_user` task and the `.env` template must consume a vaulted variable (e.g., `{{ fastapi_db_password }}`).
- **Self-signed SSL certificates**: The `ssl.rb` recipe generates self-signed certificates via `openssl req -x509` with a 365-day TTL. In Ansible, use `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` for development, or integrate **Let's Encrypt** via `community.crypto.acme_certificate` for production. Certificate renewal automation (cron/systemd timer) should be added.
- **FastAPI service running as root**: The systemd unit in `fastapi-tutorial` sets `User=root`. This is a significant security risk. The Ansible role must create a dedicated unprivileged system user (e.g., `fastapi`) and run the service under that account.
- **`.env` file permissions**: `/opt/fastapi-tutorial/.env` is written with mode `0644` (world-readable), exposing the database password. The Ansible `template` or `copy` task must set mode `0600` and restrict ownership to the application user.
- **SSH hardening via `sed`**: The `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed` in-place substitution. In Ansible, use `ansible.builtin.lineinfile` or `ansible.builtin.template` for `sshd_config` to ensure idempotent, auditable changes.
- **UFW firewall management**: UFW rules are applied via raw `execute` blocks with `not_if` guards. In Ansible, use the `community.general.ufw` module for fully idempotent firewall management.
- **Vault / secrets management summary**:
  - `cache` cookbook: 1 hardcoded service password (Redis `requirepass`)
  - `fastapi-tutorial` cookbook: 1 hardcoded DB password (PostgreSQL user + `.env` file)
  - `nginx-multisite` cookbook: No application secrets, but SSL private keys require secure file handling

---

### Technical Challenges

- **Redis config-patching hack**: The `cache` cookbook uses a `ruby_block` to post-process `/etc/redis/6379.conf` and strip deprecated `replica-*` directives. This is a workaround for a version mismatch between the `redisio` cookbook's generated config and the installed Redis binary. In Ansible, this must be replaced with a Jinja2 `redis.conf` template that only emits directives valid for the target Redis version. Identify the exact Redis version on the target OS before writing the template.
- **Chef `lineinfile` custom resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom LWRP. Review its logic and replace with Ansible's native `ansible.builtin.lineinfile` module, which provides equivalent functionality.
- **Dynamic site loop (node attributes → Jinja2)**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, deploy files, and render templates. In Ansible, this maps to a `loop` over a `sites` dictionary defined in `group_vars`. The Jinja2 `site.conf.j2` template must replicate the ERB `site.conf.erb` logic.
- **`ssl_certificate` cookbook ambiguity**: The cookbook is locked in `Policyfile.lock.json` but commented out in `Berksfile` and not explicitly `include_recipe`'d in any local cookbook. It may be pulled in as a transitive dependency or may be dead code. This must be clarified before migration to avoid missing SSL functionality.
- **OS mismatch (Fedora box vs. apt-get bootstrap)**: `vagrant-provision.sh` calls `apt-get` but the Vagrantfile uses `generic/fedora42`. This suggests the provisioner script was written for Ubuntu and the Vagrantfile was updated without updating the script. The Ansible playbook must use the correct package manager for the actual target OS; use `ansible_pkg_mgr` or `ansible_os_family` conditionals if multi-distro support is required.
- **PostgreSQL idempotency**: The `fastapi-tutorial` recipe uses `|| true` to suppress errors on duplicate DB/user creation. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require error suppression.
- **Git-based application deployment**: The recipe clones from a public GitHub URL at provision time. In Ansible, use `ansible.builtin.git` with a pinned `version` (commit SHA or tag) rather than `main` to ensure reproducible deployments. Consider whether the application source should be vendored or fetched from an artifact repository in production.
- **`systemctl daemon-reload` trigger**: The Chef recipe uses `notifies :run` to reload systemd only when the unit file changes. In Ansible, use `ansible.builtin.systemd` with `daemon_reload: true` in a handler triggered by the unit file template task.

---

### Migration Order

Migrate in the following order to respect service dependencies and minimize risk:

1. **`nginx-multisite`** — Highest standalone value; no application-layer dependencies. Migrate security hardening (UFW, fail2ban, sysctl, SSH) and Nginx multi-site configuration first. Validate SSL certificate generation and site reachability before proceeding.
2. **`cache`** — Moderate complexity due to the Redis config-patching hack. Migrate Memcached first (trivial), then Redis with a clean Jinja2 template. Validate Redis authentication and log directory before proceeding.
3. **`fastapi-tutorial`** — Highest complexity and most security debt (hardcoded credentials, root service user, world-readable `.env`). Depends on PostgreSQL being available (installed by this same cookbook) and on the network being reachable for the GitHub clone. Migrate last, after all secrets are vaulted and a dedicated service user is created.

---

### Assumptions

1. **Target OS for Ansible**: Assumed to be **Ubuntu 22.04 LTS** based on `apt-get` usage in `vagrant-provision.sh` and `metadata.rb` Ubuntu support declaration. If the actual production target is CentOS/RHEL or Fedora, package names, service names, and firewall tooling will differ and the roles will need conditional branches.
2. **Vagrant is development-only**: The Vagrantfile and `vagrant-provision.sh` are assumed to be local developer tooling, not production infrastructure. The Ansible inventory will target real hosts; Vagrant integration (if retained) will use the `ansible` Vagrant provisioner.
3. **`ssl_certificate` cookbook is unused at runtime**: Based on the fact that it is commented out in `Berksfile` and not explicitly called in any recipe, it is assumed to be dead code. If it is actually invoked as a transitive dependency, the SSL role must be extended accordingly.
4. **Redis version compatibility**: The config-patching hack implies the installed Redis version does not support `replica-*` directives (i.e., it uses the older `slave-*` naming, or the directives are simply unsupported). The exact Redis version on the target OS must be confirmed before writing the Ansible template.
5. **PostgreSQL version**: No version is pinned in the `fastapi-tutorial` cookbook; the OS default will be installed. The Ansible role should explicitly pin a PostgreSQL version (e.g., 15 or 16) for reproducibility.
6. **GitHub repository availability**: The `fastapi-tutorial` cookbook clones from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`). It is assumed this repository remains publicly accessible. If it becomes private or is moved, the Ansible role will need updated credentials or a mirrored source.
7. **No Chef Server**: The use of `chef-solo` and `Policyfile` without a Chef Server means there is no node data bag, encrypted data bag, or Chef Vault usage to migrate. All "secrets" are currently hardcoded in recipe files.
8. **No existing Ansible infrastructure**: It is assumed there is no existing Ansible control node, inventory, or Galaxy roles in place. The migration will establish these from scratch.
9. **Single-node topology**: The run-list and Vagrantfile describe a single VM running all services (Nginx, Memcached, Redis, PostgreSQL, FastAPI). The Ansible playbook is assumed to target a single host group initially. Decomposition into separate host groups is out of scope unless explicitly requested.
10. **`lineinfile` custom resource scope**: The custom `lineinfile` LWRP in `nginx-multisite` is assumed to be a thin wrapper around file line manipulation. Its full implementation has not been read; if it contains non-trivial logic beyond what `ansible.builtin.lineinfile` provides, additional analysis will be needed.
