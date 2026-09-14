# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a Fedora/Ubuntu/CentOS server running Nginx with multiple SSL-enabled virtual hosts, caching services (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL. The stack is currently exercised via Vagrant with a `libvirt` provider and a shell-based provisioner that invokes `chef-solo` with Berkshelf for dependency resolution.

The migration scope covers **3 local cookbooks** and **5 external Chef Supermarket dependencies**, all of which map cleanly to well-supported Ansible collections and modules. No Chef Server, encrypted data bags, or Chef Vault infrastructure is in use — the entire stack runs as Chef Solo — which significantly reduces migration complexity.

**Overall complexity: Medium.**
The primary challenges are the self-signed SSL certificate generation workflow, the Redis configuration post-processing hack, and the multi-site Nginx vhost loop that must be reproduced with Ansible's `loop` / `with_items` constructs. No exotic Chef resources or custom LWRPs are used beyond a single `lineinfile` resource stub.

**Estimated timeline: 2–3 weeks** for a single engineer, or 1–1.5 weeks with two engineers working in parallel on independent cookbooks.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by 5 locked external Supermarket cookbooks that will be replaced by native Ansible modules and collections.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads. No paths have been inferred or invented.

---

- **nginx-multisite**
  - **Description**: Core Nginx web server cookbook that installs Nginx, deploys a hardened `nginx.conf`, configures three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), generates self-signed TLS certificates via `openssl`, deploys per-site static `index.html` files, configures `fail2ban` with a custom `jail.local`, enforces UFW firewall rules (deny-all default, allow SSH/HTTP/HTTPS), applies kernel-level sysctl security hardening, and hardens SSH (disables root login and password authentication).
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef
  - **Key Features**:
    - Attribute-driven multi-site vhost loop (`node['nginx']['sites']`) rendered via `site.conf.erb`
    - Self-signed RSA-2048 certificate generation per vhost using `openssl req -x509`
    - SSL private key directory restricted to `root:ssl-cert` group with mode `0710`
    - `fail2ban` integration with templated `jail.local`
    - UFW firewall managed via idempotent `execute` guards
    - sysctl security hardening via `/etc/sysctl.d/99-security.conf`
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
    - Recipes: `default` → `security` → `nginx` → `ssl` → `sites`

- **cache**
  - **Description**: Caching layer cookbook that installs and configures both Memcached (via the `memcached` Supermarket cookbook) and Redis (via `redisio`) with password authentication. Includes a notable `ruby_block` post-processing hack that strips deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the generated `/etc/redis/6379.conf` after `redisio` writes it, working around an incompatibility between the `redisio 7.2.4` cookbook and the installed Redis version.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef
  - **Key Features**:
    - Memcached installed via `memcached ~> 6.0` Supermarket cookbook
    - Redis on port 6379 with `requirepass` authentication
    - Post-write config file mutation via `ruby_block` (compatibility shim)
    - `/var/log/redis` directory ownership enforced
    - External dependencies: `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4` (transitive)

- **fastapi-tutorial**
  - **Description**: Application deployment cookbook that clones a FastAPI Python application from GitHub (`https://github.com/dibanez/fastapi_tutorial.git`, `main` branch), creates a Python virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` configuration file containing the database connection string, and registers a `systemd` service (`fastapi-tutorial.service`) to run the application via `uvicorn` on port 8000.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef
  - **Key Features**:
    - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - Git clone + sync from public GitHub repository
    - Python venv at `/opt/fastapi-tutorial/venv`
    - PostgreSQL user `fastapi` and database `fastapi_db` created via `psql` shell commands
    - `.env` file written to `/opt/fastapi-tutorial/.env` with `DATABASE_URL` containing plaintext credentials
    - `systemd` unit file deployed to `/etc/systemd/system/fastapi-tutorial.service`
    - Service runs as `root` (security concern — see Security Considerations)

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all 3 local cookbook paths and 4 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1`). The `ssl_certificate` entry is commented out in the Berksfile but active in `Policyfile.rb`. **Migration consideration**: Replace entirely with Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile declaring the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and pinning all cookbook versions. **Migration consideration**: The run list order defines the provisioning sequence and must be preserved in the Ansible playbook task order.
- `Policyfile.lock.json`: Locked dependency graph with exact versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. **Migration consideration**: Reference for exact upstream versions being replaced; `selinux` is a transitive dependency of `redisio` and has no direct Ansible equivalent needed (Ansible's `ansible.posix.selinux` module covers this natively).
- `solo.json`: Chef Solo node JSON providing the run list and all node attribute overrides (site definitions, SSL paths, security flags). **Migration consideration**: This is the primary source of truth for variable values; all keys map directly to Ansible `vars` or `group_vars`.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks`. **Migration consideration**: No Ansible equivalent needed; superseded by `ansible.cfg` and inventory.
- `Vagrantfile`: Vagrant configuration using `generic/fedora42` box with `libvirt` provider, 2 vCPUs, 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. **Migration consideration**: Reusable as-is for Ansible testing; replace the `shell` provisioner block with an `ansible_local` or `ansible` provisioner pointing to the new playbook.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. **Migration consideration**: Replace with a minimal bootstrap that installs Ansible (e.g., `pip install ansible` or `dnf install ansible`) and runs `ansible-playbook`.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom LWRP stub named `lineinfile` — a Chef analogue to Ansible's `lineinfile` module. **Migration consideration**: Drop entirely; Ansible's built-in `ansible.builtin.lineinfile` module is a direct replacement.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` as the development VM. `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `vagrant-provision.sh` script uses `apt-get`, indicating the primary tested target is a Debian/Ubuntu family OS. The `nginx-multisite` cookbook uses `www-data` as the Nginx user (Debian convention). **Recommendation**: Target **Ubuntu 22.04 LTS** for Ansible migration to match the `apt-get`/`www-data` conventions already in the cookbooks, or **Fedora 42** to match the Vagrant box — confirm with the owning team.
- **Virtual Machine Technology**: **libvirt/KVM** — explicitly configured in the `Vagrantfile` via `config.vm.provider "libvirt"`. Vagrant is used for local development/testing only; no production VM platform is specified in the repository.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present in any reviewed file.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket: Replace with `ansible.builtin.package` to install the OS-native Nginx package, plus `ansible.builtin.template` for `nginx.conf` and vhost configs. The `nginxinc.nginx` Galaxy role is an optional drop-in if richer management is needed.
- **memcached (6.1.0)** — Chef Supermarket: Replace with `ansible.builtin.package` (`memcached`) and `ansible.builtin.service`. No complex configuration is applied beyond defaults; direct module usage is sufficient.
- **redisio (7.2.4)** — Chef Supermarket: Replace with `ansible.builtin.package` (`redis`) and a templated `redis.conf` with `requirepass` set. The `ruby_block` post-processing hack (stripping deprecated directives) becomes unnecessary when managing the config file directly via Ansible template — this is a net simplification.
- **ssl_certificate (2.1.0)** — Chef Supermarket (locked but commented out in Berksfile): Replace with `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` from the `community.crypto` Ansible collection, which provides idempotent self-signed certificate generation without shelling out to `openssl`.
- **selinux (6.2.4)** — Chef Supermarket (transitive via redisio): Replace with `ansible.posix.selinux` module if SELinux management is required on the target. On Ubuntu/Debian targets this dependency is irrelevant.

### Security Considerations

- **Hardcoded Redis password**: `cookbooks/cache/recipes/default.rb` sets `requirepass` to the literal string `redis_secure_password_123` directly in the recipe. **Migration approach**: Move to `ansible-vault`-encrypted `group_vars` or an external secrets manager (HashiCorp Vault, AWS Secrets Manager). Do not carry this credential forward as a plaintext variable.
- **Hardcoded PostgreSQL credentials**: `cookbooks/fastapi-tutorial/recipes/default.rb` creates the `fastapi` PostgreSQL user with password `fastapi_password` via an inline `psql` shell command, and writes the same password into `/opt/fastapi-tutorial/.env` as `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`. **Migration approach**: Encrypt with `ansible-vault`; use `ansible.builtin.template` for the `.env` file with a vaulted variable substitution.
- **FastAPI service running as root**: The `systemd` unit in `fastapi-tutorial` sets `User=root`. **Migration approach**: Create a dedicated `fastapi` system user during migration and update the service unit accordingly. Flag this as a mandatory remediation item, not optional.
- **Self-signed TLS certificates**: All three vhosts use self-signed certificates generated at provision time. **Migration approach**: Use `community.crypto` collection for idempotent generation in dev/test. For production, integrate `community.crypto.acme_certificate` (Let's Encrypt) or a PKI-backed certificate workflow.
- **SSH hardening state**: The `security` recipe disables root login and password authentication via `sed` on `sshd_config`. **Migration approach**: Use `ansible.builtin.lineinfile` or `ansible.builtin.template` for `sshd_config`; ensure the Ansible control node has key-based access established *before* this task runs, or the playbook will lock itself out.
- **UFW firewall management**: Managed via raw `execute` shell commands with `not_if` guards. **Migration approach**: Replace with `community.general.ufw` module for fully idempotent firewall state management.
- **`.env` file permissions**: The FastAPI `.env` file is written with mode `0644` and owned by `root`, meaning the database password is world-readable. **Migration approach**: Set mode to `0600` and restrict ownership to the dedicated service user.

### Technical Challenges

- **Redis config post-processing hack**: The `cache` cookbook's `ruby_block` that strips deprecated Redis directives from the `redisio`-generated config is a workaround for an upstream cookbook incompatibility. In Ansible, the Redis config is written directly from a template, so this problem does not exist — but the team must verify which Redis directives are valid on the target Redis version and write a clean template from scratch rather than porting the hack.
- **Multi-site vhost loop**: The `nginx-multisite` cookbook iterates over `node['nginx']['sites']` in three separate recipes (`nginx.rb`, `ssl.rb`, `sites.rb`) to create document roots, generate certificates, and deploy vhost configs. In Ansible this maps to a single `loop` over a `nginx_sites` list variable, but the three-recipe split must be collapsed into a coherent task ordering within one role to avoid partial state.
- **Attribute precedence and `solo.json` overrides**: `solo.json` overrides the document root paths defined in `attributes/default.rb` (e.g., `/var/www/test.cluster.local` vs. `/opt/server/test`). The Ansible migration must canonicalize these into a single `defaults/main.yml` with the `solo.json` values taking precedence, and document which values are environment-specific.
- **`ssl_certificate` cookbook discrepancy**: The cookbook is commented out in `Berksfile` but present and locked in `Policyfile.lock.json`. It is not explicitly called in any recipe, suggesting it may be an unused transitive dependency or a partially removed feature. Confirm with the team whether `ssl_certificate` functionality is needed before migration.
- **Berkshelf vendoring in CI**: The `vagrant-provision.sh` script vendors cookbooks at runtime via `berks vendor`. Any existing CI pipeline that relies on this pattern must be updated to use `ansible-galaxy install -r requirements.yml` instead.
- **Fedora 42 vs. Ubuntu package names**: The Vagrantfile targets Fedora 42 but the cookbook code uses `apt-get` and `www-data` (Debian conventions). The Ansible role must handle both families via `ansible_os_family` conditionals, or the target OS must be standardized before migration begins.
- **PostgreSQL idempotency**: The `fastapi-tutorial` recipe uses `|| true` to suppress errors on duplicate user/database creation. Ansible's `community.postgresql` collection (`postgresql_user`, `postgresql_db` modules) handles idempotency natively and should replace the raw `psql` shell commands entirely.

### Migration Order

1. **cache** — Lowest risk. Memcached and Redis have direct, well-tested Ansible module equivalents. Migrating this first eliminates the `redisio` + `ruby_block` hack and validates the Ansible inventory and connection setup. No inter-cookbook dependencies.
2. **nginx-multisite** — Medium complexity. The vhost loop, SSL certificate generation, fail2ban, UFW, and sysctl hardening all have native Ansible equivalents. Migrate after `cache` so the full stack can be tested together. The existing partial Ansible role at `modules/nginx/ansible/roles/nginx/` should be reviewed as a starting reference — it already contains templates (`nginx.conf.j2`, `site.j2`, `default.conf.j2`) and a task structure that partially overlaps with this cookbook.
3. **fastapi-tutorial** — Highest complexity due to the PostgreSQL provisioning, Git-based deployment, Python venv management, systemd unit, and the mandatory security remediation (service user, credential vaulting, `.env` permissions). Migrate last, after the platform baseline (Nginx + caching) is validated.

### Assumptions

1. **Target OS is Ubuntu 22.04 LTS** (or compatible Debian family) based on `apt-get` usage and `www-data` Nginx user in the cookbooks, despite the Vagrantfile specifying `generic/fedora42`. This must be confirmed with the owning team before role variable defaults are finalized.
2. **Chef Server is not in use.** The entire stack runs as `chef-solo` with no Chef Server, Hosted Chef, or Chef Automate integration. No node object, search, or data bag APIs are used.
3. **No encrypted data bags or Chef Vault.** All secrets are currently stored as plaintext in recipe code and `solo.json`. The migration is an opportunity to introduce proper secrets management; no decryption tooling needs to be ported.
4. **The `ssl_certificate` Supermarket cookbook is not actively used.** It appears in `Policyfile.lock.json` and `Policyfile.rb` but is commented out in `Berksfile` and not called in any recipe. It is assumed to be a vestigial dependency and will not be migrated unless confirmed otherwise.
5. **The partial Ansible role at `modules/nginx/ansible/roles/nginx/`** is a prior migration attempt or reference implementation. It will be reviewed for reusable templates and task patterns but is not assumed to be production-ready or complete.
6. **The `lineinfile` custom resource** (`cookbooks/nginx-multisite/resources/lineinfile.rb`) is a stub and not called by any recipe in the reviewed code. It is assumed safe to drop without replacement.
7. **The FastAPI application source** (`https://github.com/dibanez/fastapi_tutorial.git`) is a public repository. If it becomes private before or during migration, SSH key management for the Ansible `git` module will need to be addressed.
8. **Vagrant is used for local development only.** There is no evidence of a production deployment pipeline (no CI/CD configuration files, no cloud provider configs). The Ansible playbook will initially target the same Vagrant environment and be extended to production targets separately.
9. **The `selinux` Supermarket cookbook** is a transitive dependency of `redisio` and is not directly configured. On Ubuntu targets it is irrelevant. If the target is confirmed as RHEL/Fedora, SELinux policy for Redis and Nginx will need to be addressed explicitly in the Ansible roles.
10. **Port 8000 (uvicorn/FastAPI) is not exposed** in the Vagrantfile port forwards (only 80→8080 and 443→8443 are forwarded). It is assumed the FastAPI service is accessed via Nginx reverse proxy, though no Nginx upstream proxy configuration exists in the current cookbooks. This gap should be clarified before migration.
