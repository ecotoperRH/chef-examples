# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo** infrastructure-as-code project that provisions a full application stack on a single Linux host (Fedora 42 / generic Vagrant VM). The policy (`nginx-multisite-policy`) runs three local cookbooks in sequence — `nginx-multisite`, `cache`, and `fastapi-tutorial` — backed by five external Chef Supermarket cookbooks (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, `ssl_certificate 2.1.0`).

**Migration status**: All three local cookbooks have already been converted to Ansible roles and are present in the repository under their respective module directories. The migration work is substantially complete at the role level; the remaining effort focuses on integration, secrets management hardening, and production-readiness validation.

- **Source technology**: Chef Solo (Chef >= 16.0), Berkshelf/Policyfile dependency management, Vagrant + libvirt for local testing
- **Target technology**: Ansible (min version 2.9–2.10 per role metadata), Ansible Automation Platform (AAP) for credential management
- **Scope**: 3 local cookbooks → 3 Ansible roles + 1 pre-existing upstream nginx role
- **Complexity**: Low-to-moderate — the stack is single-host, the cookbooks are well-structured, and the Ansible equivalents already exist. The primary remaining risks are secrets remediation (3 hardcoded credentials), the Redis source-compile workaround, and the self-signed SSL certificate lifecycle.
- **Estimated timeline**: 2–3 sprints (4–6 weeks) to reach production-ready state, assuming secrets management infrastructure is already available.

---

## Module Migration Plan

This repository contains 3 local Chef cookbooks that require individual migration planning, plus 1 pre-existing Ansible nginx role that was migrated separately:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths were confirmed in the provided repository tree or via direct file reads are listed below.

---

- **nginx-multisite**:
  - Description: Hardened Nginx web server hosting three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`). Applies a full security baseline including UFW firewall rules (deny-all default, allow SSH/HTTP/HTTPS), fail2ban intrusion prevention with nginx-specific jails, kernel sysctl hardening, and SSH hardening (root login disabled, password authentication disabled). Each site serves static HTML from `/opt/server/{test,ci,status}` with HTTP→HTTPS redirects, HSTS, and per-site access/error logs. Self-signed RSA 2048-bit TLS certificates are generated via `openssl req -x509` for each vhost.
  - Path: `cookbooks/nginx-multisite`
  - Ansible Role Path: `weqe-d92f93/modules/nginx-multisite/ansible/roles/nginx_multisite`
  - Technology: Chef
  - Key Features: nginx multisite vhost templating, self-signed TLS cert generation, UFW firewall management, fail2ban with jail.local template, sysctl security hardening, SSH hardening via `sed` on `sshd_config`, sites-available/sites-enabled symlink management

---

- **cache**:
  - Description: Dual caching layer deploying Memcached (port 11211, 64 MB RAM, 1024 max connections, no authentication) and Redis (port 6379, password-authenticated, compiled from source at version 3.2.11 by default, managed via systemd `redis@6379.service`). Includes a post-configuration `ruby_block` hack that strips five deprecated Redis directives from `/etc/redis/6379.conf` to work around version compatibility issues between the `redisio` cookbook's config template and the installed Redis version. Redis password is hardcoded as `redis_secure_password_123` in the recipe.
  - Path: `cookbooks/cache`
  - Ansible Role Path: `weqe-d92f93/modules/cache/ansible/roles/cache`
  - Technology: Chef
  - Key Features: Memcached system user/group provisioning, Redis source compilation from `download.redis.io`, systemd unit templating (`redis@6379.service`), PAM ulimit configuration, OS-default Redis service disable, post-config directive stripping (compatibility fix), AAP credential type definition for Redis password

---

- **fastapi-tutorial**:
  - Description: Deploys a FastAPI Python ASGI application from GitHub (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) onto the host. Installs system packages (Python 3, pip, venv, git, PostgreSQL, libpq-dev), creates a Python virtual environment at `/opt/fastapi-tutorial/venv`, installs pip dependencies, provisions a PostgreSQL database (`fastapi_db`) and user (`fastapi`) with a hardcoded password, writes a `.env` configuration file with the database URL, deploys a systemd unit file, and starts the `fastapi-tutorial` service on port 8000 via uvicorn.
  - Path: `cookbooks/fastapi-tutorial`
  - Ansible Role Path: `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial`
  - Technology: Chef
  - Key Features: Git repository clone and sync, Python venv creation, pip requirements install, PostgreSQL user/database provisioning via `sudo -u postgres psql`, `.env` file templating, systemd service unit deployment, uvicorn ASGI server management

---

- **nginx** (upstream/pre-existing Ansible role):
  - Description: General-purpose Nginx installation and configuration role supporting both RedHat (via DNF + EPEL) and Debian/Ubuntu (via APT) families. Manages the main `nginx.conf`, a default site, and an arbitrary list of named virtual host configurations. Includes SELinux Python module installation on RedHat. This role was migrated independently and is not derived from a local Chef cookbook in this repository.
  - Path: `123-fc2c2f/modules/nginx/ansible/roles/nginx`
  - Technology: Ansible (pre-migrated)
  - Key Features: Dual OS-family support (RedHat/Debian), EPEL repo file deployment, sites-available/sites-enabled directory structure, Jinja2 site templates, SELinux compatibility, nginx service handler (restart/reload)

---

### Infrastructure Files

- `Policyfile.rb`: Chef Policyfile defining the `nginx-multisite-policy` run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all cookbook version constraints. This is the primary dependency manifest — replace with an Ansible playbook that calls the three roles in order.
- `Policyfile.lock.json`: Locked dependency graph pinning all 8 cookbooks (3 local + 5 external) to exact versions and content hashes. Use as the authoritative reference for external dependency versions when selecting equivalent Ansible collections or OS packages.
- `Berksfile`: Berkshelf dependency file mirroring the Policyfile constraints. Redundant with `Policyfile.lock.json` for migration purposes.
- `solo.json`: Chef Solo node attributes JSON — defines the three nginx vhosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), SSL paths, and security settings (fail2ban, UFW, SSH hardening). Translate directly into Ansible role `defaults/main.yml` or inventory `host_vars`.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` cookbook path. No migration action required.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider, 2 GB RAM, 2 vCPUs, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Indicates the target OS is **Fedora 42** (RHEL family). Replace with an Ansible inventory file and molecule test configuration.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef, runs Berkshelf, and executes `chef-solo`. Replace with an Ansible playbook invocation or molecule converge step.
- `project-plan.md`: Existing project planning document — review for any additional context not captured in code.

---

### Target Details

- **Operating System**: Fedora 42 (confirmed via `Vagrantfile`: `config.vm.box = "generic/fedora42"`). RedHat family. The Chef cookbooks also declare support for Ubuntu >= 18.04 and CentOS >= 7.0, and the migrated Ansible roles support both RedHat (EL 7/8/9/10) and Debian/Ubuntu families. Primary target for migration validation is Fedora 42 / RHEL-compatible.
- **Virtual Machine Technology**: libvirt/KVM (confirmed via `Vagrantfile`: `config.vm.provider "libvirt"`). Vagrant is used for local development and testing only.
- **Cloud Platform**: Not specified. No cloud-specific configurations, metadata endpoints, or cloud SDK references are present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx 12.3.1** (Chef Supermarket): The `nginx-multisite` cookbook installs nginx directly via the OS package manager (`package 'nginx'`) without using the upstream `nginx` cookbook's resources. The migrated `nginx_multisite` Ansible role follows the same pattern. The separate `nginx` Ansible role (in `123-fc2c2f/`) provides a more general-purpose alternative. Ensure the correct role is used for each use case and that nginx package versions are pinned appropriately for the target OS.

- **memcached 6.1.0** (Chef Supermarket): Provides the `memcached_instance` custom resource. The Ansible `cache` role reimplements this logic natively using `ansible.builtin.package`, `ansible.builtin.user`, `ansible.builtin.group`, and `ansible.builtin.file` tasks. No external Ansible collection dependency is required.

- **redisio 7.2.4** (Chef Supermarket): A complex cookbook that compiles Redis 3.2.11 from source by default. The Ansible `cache` role fully reimplements this across 11 task files. Verify that the source-compile path is still desired on the target OS, or consider switching to the OS package (`redis-server` / `redis`) by setting `cache_redis_package_install: true` — this would eliminate the build toolchain dependency and the compatibility-fix lineinfile tasks.

- **selinux 6.2.4** (Chef Supermarket): Pulled in transitively by `redisio`. The Ansible `nginx` role handles SELinux Python module installation on RedHat. Ensure `libselinux-python` / `python3-libselinux` are installed on Fedora 42 targets before running any role that manages file contexts or booleans.

- **ssl_certificate 2.1.0** (Chef Supermarket): Referenced in `Policyfile.rb` but not directly used by the local cookbooks — the `nginx-multisite` cookbook generates self-signed certificates inline via `openssl` shell commands. The Ansible `nginx_multisite` role replicates this with `ansible.builtin.command` using `openssl req -x509`. For production, replace self-signed certificates with certificates from a trusted CA (Let's Encrypt via `community.crypto.acme_certificate`, or an internal PKI).

- **build-essential** (implicit, via redisio): Redis source compilation requires `gcc`, `make`, and related build tools. The Ansible `cache` role must ensure these are installed on the target before the compile tasks run. Confirm availability on Fedora 42 (`dnf groupinstall "Development Tools"`).

- **PostgreSQL client library** (`libpq-dev`): Required for `psycopg2` compilation in the FastAPI venv. Package name differs by OS family: `libpq-dev` (Debian/Ubuntu) vs `postgresql-devel` or `libpq-devel` (RHEL/Fedora). The current Ansible role uses the Debian package name — **this must be corrected for Fedora 42 targets**.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123`): Defined in plaintext in `cookbooks/cache/recipes/default.rb`. The Ansible `cache` role externalizes this as `{{ redis_password }}`, with an AAP credential type (`Redis Authentication Password`) and controller credential definition already created in `weqe-d92f93/modules/cache/ansible/roles/cache/aap-configuration/`. **Action required**: Store the actual password in AAP Credential Store or Ansible Vault (`vault_redis_password`) before any production deployment. Do not commit the plaintext value to version control.

- **Hardcoded FastAPI database password** (`fastapi_password`): Defined in plaintext in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env` (mode 0644, readable by all). The Ansible `fastapi_tutorial` role externalizes this as `{{ db_password }}` / `{{ vault_db_password }}`, with an AAP credential type (`FastAPI PostgreSQL Database`) already defined in `weqe-d92f93/modules/fastapi-tutorial/ansible/roles/fastapi_tutorial/aap-configuration/`. **Action required**: Store `db_password`, `db_username`, `db_host`, `db_name`, and `database_url` in AAP or Ansible Vault. Also harden the `.env` file permissions from `0644` to `0600` in the Ansible template task.

- **Hardcoded database URL** (`DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`): Composite secret written inline to `/opt/fastapi-tutorial/.env`. Treated as a separate credential in the AAP credential type definition (`vault_database_url`). Ensure the full URL is vaulted, not just the password component.

- **Self-signed TLS certificates**: All three nginx vhosts use self-signed RSA 2048-bit certificates generated at provision time with a 365-day validity. These are acceptable for development/internal use but must be replaced with CA-signed certificates for any production or internet-facing deployment. The `openssl req` command in the Ansible `nginx_multisite` role uses placeholder subject fields (`Example Org`, `admin@example.com`) that must be parameterized for production.

- **SSH hardening**: The `nginx-multisite` cookbook (and its Ansible equivalent) disables root login and password authentication in `sshd_config` via `sed` commands. Verify that key-based SSH access is fully configured on target hosts **before** applying this role, or the host may become inaccessible.

- **UFW firewall**: Default-deny policy applied with explicit allow rules for SSH (22), HTTP (80), and HTTPS (443). The FastAPI application port (8000) is **not** opened in the firewall — if external access to the API is required, an additional UFW rule must be added.

- **Redis network exposure**: Redis is bound to `0.0.0.0:6379` (all interfaces) with password authentication. In a production environment, consider binding to `127.0.0.1` only, or adding a UFW rule to block external access to port 6379.

- **Memcached network exposure**: Memcached is bound to `0.0.0.0:11211` with **no authentication**. This is a significant security risk if the host is network-accessible. Add a UFW deny rule for port 11211 or bind Memcached to `127.0.0.1`.

- **FastAPI service runs as root**: The systemd unit file sets `User=root`. This is a security anti-pattern. The Ansible role preserves this behavior. For production, create a dedicated `fastapi` service account and update the unit file accordingly.

- **`.env` file permissions**: Currently set to `0644` (world-readable), exposing the database password to all local users. Change to `0600` in the Ansible template task.

---

### Technical Challenges

- **Redis source compilation vs. package install**: The `redisio` cookbook compiles Redis 3.2.11 from source by default, which is an old version (EOL). The post-config `ruby_block` hack (stripping 5 directives) exists specifically because the `redisio` config template generates directives that Redis 3.2.11 does not support. The Ansible role faithfully replicates this workaround via `ansible.builtin.lineinfile`. For production, strongly consider switching to `cache_redis_package_install: true` to use the OS-provided Redis package (which will be a much newer version), eliminating the build toolchain requirement and the compatibility hack entirely.

- **OS package name differences (Fedora 42 target)**: The Vagrantfile specifies Fedora 42, but several package names in the Chef cookbooks and Ansible roles use Debian/Ubuntu naming conventions (e.g., `libpq-dev`, `python3-venv`, `www-data` user/group). The Ansible `fastapi_tutorial` role's package list must be audited and corrected for RHEL/Fedora: `libpq-dev` → `libpq-devel`, `python3-venv` is not a separate package on Fedora (included in `python3`), and the nginx web user is `nginx` not `www-data`.

- **PostgreSQL provisioning idempotency**: The `fastapi-tutorial` cookbook uses `|| true` shell hacks to suppress errors on re-runs. The Ansible role uses `ansible.builtin.shell` with `changed_when: false` for the same commands. For a production-grade migration, replace these with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` collection, which provide true idempotency and proper diff reporting.

- **Nginx `www-data` user on Fedora**: The `nginx-multisite` cookbook and its Ansible equivalent use `www-data` as the nginx web user (Debian convention). On Fedora/RHEL, the nginx package creates a `nginx` user instead. The `nginx_multisite_web_user` and `nginx_multisite_web_group` defaults must be overridden to `nginx` for Fedora 42 targets.

- **Chef `lineinfile` custom resource**: The `nginx-multisite` cookbook includes a custom `resources/lineinfile.rb` resource. This has been replaced in the Ansible role with `ansible.builtin.lineinfile`, which is a native Ansible module — no custom implementation needed.

- **Molecule test infrastructure**: All four Ansible roles include Molecule test suites (`molecule/default/`). These need to be validated against the actual target platform (Fedora 42 / RHEL) before the roles are considered production-ready. The `create.yml` and `destroy.yml` files should be reviewed to ensure they target the correct container/VM image.

- **Run order dependency**: The Chef run list enforces `nginx-multisite → cache → fastapi-tutorial` order. The Ansible playbook must preserve this sequence, as `fastapi-tutorial` depends on PostgreSQL being available (started by its own role) and nginx being configured to potentially proxy to the FastAPI backend.

- **No Ansible playbook yet**: The repository contains individual Ansible roles but no top-level playbook that assembles them into the equivalent of the Chef `nginx-multisite-policy` run list. A `site.yml` or equivalent playbook must be created to wire the roles together with the correct inventory and variable assignments.

---

### Migration Order

1. **nginx-multisite** (Priority 1 — foundational, low credential risk, already migrated): Validate the `nginx_multisite` Ansible role against Fedora 42. Fix the `www-data` → `nginx` user/group for RHEL targets. Parameterize SSL certificate subject fields. Test with Molecule. This role has no external service dependencies and can be validated in isolation.

2. **cache** (Priority 2 — moderate complexity, one credential to vault): Validate the `cache` Ansible role. Decide on source-compile vs. package-install for Redis. Store `redis_password` in AAP/Vault using the provided credential type definition. Test Memcached and Redis connectivity post-deployment. Verify the compatibility-fix `lineinfile` tasks remove the correct directives.

3. **fastapi-tutorial** (Priority 3 — depends on PostgreSQL, two credentials to vault, package name fixes needed): Validate the `fastapi_tutorial` Ansible role on Fedora 42 (fix `libpq-dev` → `libpq-devel`). Store `db_password` and `database_url` in AAP/Vault. Harden `.env` file permissions to `0600`. Consider replacing shell-based PostgreSQL provisioning with `community.postgresql` collection modules. Validate end-to-end: nginx → FastAPI → PostgreSQL.

4. **Integration playbook** (Priority 4 — final assembly): Create a `site.yml` playbook that applies all three roles in order against the target inventory. Wire AAP credential types to role variables. Replace the `Vagrantfile` + `vagrant-provision.sh` workflow with an Ansible inventory and playbook invocation. Validate the full stack end-to-end.

---

### Assumptions

1. **Target OS is Fedora 42 (RHEL family)**: Inferred from the Vagrantfile (`generic/fedora42`). The Chef cookbooks declare support for both Ubuntu >= 18.04 and CentOS >= 7.0, but the actual test environment is Fedora. Package names, service names, and user conventions in the Ansible roles must be validated against Fedora 42 specifically.

2. **Single-host deployment**: The entire stack (nginx, Redis, Memcached, FastAPI, PostgreSQL) runs on one VM. The Ansible migration assumes the same topology. If the target architecture separates services across hosts, the roles and inventory must be restructured accordingly.

3. **AAP is available for credential management**: The migrated roles include AAP credential type and controller credential YAML files. This assumes an Ansible Automation Platform instance is available. If AAP is not in scope, Ansible Vault (`ansible-vault`) should be used instead for all three secrets.

4. **Redis source compilation is intentional**: The `redisio` cookbook compiles Redis 3.2.11 from source. This is preserved in the Ansible `cache` role. It is assumed this is intentional (e.g., for a specific version requirement), but it may be a legacy artifact. Clarification from the application team is needed before production deployment.

5. **Self-signed certificates are acceptable for the target environment**: The SSL certificates are self-signed and generated at provision time. It is assumed this is acceptable for the intended use case (internal/development). If the target is internet-facing or requires trusted certificates, a CA integration must be added.

6. **The FastAPI application repository is accessible**: The `fastapi-tutorial` role clones `https://github.com/dibanez/fastapi_tutorial.git` at provision time. It is assumed the target hosts have outbound internet access to GitHub, or a mirror/artifact repository is available.

7. **No existing Ansible playbook**: The repository contains roles but no top-level playbook. It is assumed one needs to be created as part of this migration.

8. **`www-data` vs `nginx` user**: The `nginx-multisite` cookbook and Ansible role use `www-data` as the web user (Debian convention). It is assumed this needs to be corrected to `nginx` for Fedora 42, but this has not been confirmed against the actual nginx package behavior on that platform.

9. **PostgreSQL is installed and managed by the `fastapi-tutorial` role**: No separate database role exists. PostgreSQL is installed as a side effect of the FastAPI cookbook. If PostgreSQL needs to be managed independently (e.g., shared across applications), a dedicated database role should be extracted.

10. **The `ssl_certificate` cookbook (v2.1.0) in the Policyfile lock is unused**: It appears in the locked dependency graph but is not directly called by any local cookbook recipe. It is assumed it was included speculatively or as a transitive dependency and can be safely omitted from the Ansible migration.
