# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a single Vagrant-based virtual machine (Fedora 42, libvirt) running a multi-service web stack. The policy (`nginx-multisite-policy`) executes three local cookbooks in sequence: a hardened Nginx multi-site reverse proxy, a dual caching layer (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL.

The migration scope is **moderate**: three local cookbooks, four external Supermarket cookbook dependencies, and a set of supporting infrastructure files. All logic is self-contained within this repository — there is no Chef Server, no encrypted data bags, and no external node management. The primary complexity lies in replacing Chef community cookbooks (`nginx`, `memcached`, `redisio`, `ssl_certificate`, `selinux`) with native Ansible modules and roles, and in safely handling the hardcoded credentials present in the source.

**Estimated migration timeline: 2–3 weeks** for a single engineer, or 1 week with a two-person team.

---

## Module Migration Plan

This repository contains three Chef cookbooks that need individual migration planning:

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads.

---

- **nginx-multisite**
  - **Description**: Nginx reverse proxy with SSL termination, multi-site virtual host management, host-based firewall hardening, and SSH hardening. Configures three SSL-enabled subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with self-signed TLS certificates (RSA 2048, 365-day), HTTP→HTTPS redirect, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection). Installs and configures `fail2ban` with jails for SSH, nginx-http-auth, nginx-limit-req, and nginx-botsearch. Enforces UFW firewall rules (default deny, allow SSH/HTTP/HTTPS) and applies kernel-level network hardening via `sysctl` (IP spoofing protection, ICMP redirect suppression, SYN flood protection, IPv6 disable).
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef (>= 16.0)
  - **Key Features**:
    - ERB templates for `nginx.conf`, per-site `site.conf`, `security.conf`, `fail2ban/jail.local`, and `sysctl-security.conf`
    - TLSv1.2/1.3 only; strong cipher suite; per-site access/error logs
    - SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
    - Static site content (`index.html`) deployed per virtual host from cookbook `files/`
    - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`)
    - Site configuration driven by node attributes (overridable via `solo.json`)

---

- **cache**
  - **Description**: Dual in-memory caching layer installing and configuring both Memcached and Redis on the same host. Redis is configured on port 6379 with password authentication. Includes a `ruby_block` workaround that post-processes the generated Redis config file to strip deprecated `replica-*` directives that are incompatible with the locked `redisio 7.2.4` cookbook on the target Redis version.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef (>= 16.0)
  - **Key Features**:
    - Delegates Memcached installation to the `memcached` community cookbook (v6.1.0)
    - Delegates Redis installation to the `redisio` community cookbook (v7.2.4) with `redisio::enable`
    - Hardcoded Redis password: `redis_secure_password_123`
    - Post-install config file mutation hack to remove incompatible Redis directives
    - Creates `/var/log/redis` directory with correct ownership

---

- **fastapi-tutorial**
  - **Description**: Full-stack Python web application deployment. Installs Python 3 toolchain (`python3`, `python3-pip`, `python3-venv`), clones the `fastapi_tutorial` application from GitHub (`https://github.com/dibanez/fastapi_tutorial.git`, `main` branch), creates a Python virtual environment, installs pip dependencies from `requirements.txt`, provisions a PostgreSQL database and user, writes a `.env` configuration file, and registers a `systemd` service (`fastapi-tutorial.service`) running `uvicorn` on port 8000.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef (>= 16.0)
  - **Key Features**:
    - Git-based application deployment (live `main` branch sync)
    - PostgreSQL provisioning via raw `psql` shell commands (no community cookbook)
    - Hardcoded credentials: PostgreSQL user `fastapi` / password `fastapi_password`; `DATABASE_URL` written in plaintext to `/opt/fastapi-tutorial/.env`
    - systemd unit file written inline; service runs as `root`
    - No idempotency guard on `pip install` (runs on every Chef run)

---

### Infrastructure Files

- **`Policyfile.rb`**: Chef Policyfile defining the `nginx-multisite-policy` run list and pinning all cookbook sources. Maps directly to an Ansible playbook with ordered roles. Must be replaced — no Ansible equivalent exists.
- **`Policyfile.lock.json`**: Resolved dependency lock file. Documents exact versions of all transitive dependencies (including `selinux 6.2.4`, `ssl_certificate 2.1.0`). Use as the authoritative version reference when selecting Ansible Galaxy roles.
- **`Berksfile`**: Berkshelf dependency file (superseded by Policyfile in practice). Lists the same cookbooks; the `ssl_certificate` entry is commented out in Berksfile but active in Policyfile — this inconsistency should be resolved during migration.
- **`solo.json`**: Chef Solo node JSON — the primary runtime configuration input. Defines the three virtual host names, document roots, SSL paths, and all security flags. This file's structure maps directly to Ansible `group_vars` or `host_vars`.
- **`solo.rb`**: Chef Solo configuration file specifying `file_cache_path` and `cookbook_path`. Has no Ansible equivalent; replaced by `ansible.cfg` and inventory.
- **`Vagrantfile`**: Vagrant VM definition targeting `generic/fedora42` with libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, and port forwards 80→8080, 443→8443. The commented-out `/etc/hosts` provisioner block and the commented-out `chef_solo` provisioner block indicate the setup is still in active development. Migrate to an Ansible-compatible `Vagrantfile` using the `ansible` provisioner, or replace with a static inventory file.
- **`vagrant-provision.sh`**: Bootstrap shell script that installs Chef, runs Berkshelf to vendor dependencies, and executes `chef-solo`. Replaced entirely by `ansible-playbook` invocation. The script also reveals the VM uses `apt-get`, confirming a Debian/Ubuntu-family guest OS despite the `generic/fedora42` box label — this discrepancy must be investigated before migration.
- **`project-plan.md`**: Existing project documentation. Review for additional context before migration begins.
- **`x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`**: Repository-specific migration rule file. Read before finalising the Ansible role structure.

---

### Target Details

- **Operating System**: The `Vagrantfile` specifies `generic/fedora42` (Fedora 42), but `vagrant-provision.sh` uses `apt-get` — a Debian/Ubuntu package manager. The cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The nginx template uses `www-data` as the web server user (Debian/Ubuntu convention). **The effective target OS is Ubuntu (likely 20.04 or 22.04 LTS)**; the Fedora box reference is likely a misconfiguration. This must be confirmed before migration.
- **Virtual Machine Technology**: Vagrant with **libvirt** provider (explicitly configured in `Vagrantfile` with `config.vm.provider "libvirt"`). KVM/QEMU hypervisor on the host.
- **Cloud Platform**: Not specified. No cloud-specific tooling, metadata endpoints, or provider configurations are present. This is a local development/test environment.

---

## Migration Approach

### Key Dependencies to Address

- **`nginx` (12.3.1, Chef Supermarket)**: Provides Nginx installation and base configuration. Replace with the `ansible.builtin.package` module for installation and Ansible `template` tasks for `nginx.conf`. Consider the `nginxinc.nginx` Galaxy role for production-grade management, or implement natively — the nginx configuration in this repo is straightforward enough for direct translation.
- **`memcached` (6.1.0, Chef Supermarket)**: Installs and configures Memcached. Replace with `ansible.builtin.package` + `ansible.builtin.service` + a `template` task for `memcached.conf`. The `community.general` collection has no dedicated Memcached role; native tasks are sufficient.
- **`redisio` (7.2.4, Chef Supermarket)**: Installs Redis with per-instance configuration. Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/redis.conf` + `ansible.builtin.service`. The `geerlingguy.redis` Ansible Galaxy role is a well-maintained drop-in equivalent. The config-file mutation hack in `cache::default` must be replaced with a properly templated Redis config that omits the deprecated directives from the start.
- **`ssl_certificate` (2.1.0, Chef Supermarket)**: Present in `Policyfile.lock.json` as a transitive dependency but not directly invoked in any local cookbook recipe (SSL cert generation is handled inline via `openssl` shell commands in `nginx-multisite::ssl`). No direct Ansible replacement needed; use `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey` modules instead of shell commands.
- **`selinux` (6.2.4, Chef Supermarket)**: Pulled in as a transitive dependency of `redisio`. Not directly used by local cookbooks. On the target Ubuntu system, SELinux is not active (AppArmor is used instead). Verify whether any SELinux policy management is actually required; if not, this dependency can be dropped entirely.

---

### Security Considerations

- **Hardcoded Redis password**: The string `redis_secure_password_123` is hardcoded in `cookbooks/cache/recipes/default.rb`. In Ansible, this must be moved to an **Ansible Vault**-encrypted variable (e.g., `vault_redis_password`) and referenced via `vars_files` or `group_vars/all/vault.yml`.
- **Hardcoded PostgreSQL credentials**: The username `fastapi` and password `fastapi_password` are hardcoded in `cookbooks/fastapi-tutorial/recipes/default.rb` and written in plaintext to `/opt/fastapi-tutorial/.env`. Both the provisioning credential and the application `.env` file must be managed via Ansible Vault. The `.env` file should be deployed using the `ansible.builtin.template` module with a vaulted variable.
- **Plaintext `.env` file permissions**: The `.env` file is currently created with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded password to all local users. The Ansible task must set mode `0600` and assign a non-root owner matching the service account.
- **Service running as root**: The `fastapi-tutorial` systemd unit runs `uvicorn` as `User=root`. The Ansible migration should create a dedicated `fastapi` system user and update the service unit accordingly.
- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated via inline `openssl` shell commands. The Ansible migration should use `community.crypto.x509_certificate` (with `selfsigned` provider for dev/test) or integrate with an ACME/Let's Encrypt workflow (`community.crypto.acme_certificate`) for production. Certificate paths (`/etc/ssl/certs`, `/etc/ssl/private`) and the `ssl-cert` group are preserved.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` commands on `sshd_config`. In Ansible, use `ansible.builtin.lineinfile` (or the `devsec.hardening.ssh_hardening` Galaxy role) to manage these settings idempotently. **Caution**: disabling password auth before SSH key distribution is confirmed will lock out the Vagrant user — sequence these tasks carefully.
- **UFW firewall**: Managed via raw `ufw` shell commands with `not_if` guards. Replace with the `community.general.ufw` module for idempotent rule management.
- **Kernel sysctl hardening**: Applied via a template to `/etc/sysctl.d/99-security.conf`. Replace with `ansible.posix.sysctl` module tasks, one per parameter, for full idempotency and auditability.
- **fail2ban configuration**: Managed via an ERB template. Replace with `ansible.builtin.template` deploying the same jail configuration. The `community.general` collection does not include a fail2ban module; template-based management is appropriate.
- **No secrets management system in use**: There are no Chef encrypted data bags, Chef Vault references, or external secrets backends. All secrets are currently in plaintext in recipe files. Ansible Vault is the minimum viable replacement; consider HashiCorp Vault integration for production environments.

---

### Technical Challenges

- **OS mismatch (`generic/fedora42` vs. `apt-get`)**: The Vagrantfile box and the provisioning script use incompatible OS assumptions. Before writing any Ansible tasks, the actual target OS must be confirmed. If the intent is Ubuntu, the Vagrantfile box should be corrected to `generic/ubuntu2204` or similar. If Fedora/RHEL is the true target, all `apt`/`www-data`/`ufw` references in the cookbooks must be replaced with `dnf`/`nginx`/`firewalld` equivalents in Ansible.
- **`redisio` config-file mutation hack**: The `ruby_block` in `cache::default.rb` post-processes the Redis config to strip deprecated directives. This is a sign that `redisio 7.2.4` generates a config incompatible with the installed Redis version. In Ansible, this is resolved by fully owning the Redis config template and never relying on a community role to generate it — the template should only include directives valid for the target Redis version.
- **No idempotency on `pip install`**: The `fastapi-tutorial` cookbook runs `pip install -r requirements.txt` unconditionally on every Chef run. The Ansible equivalent (`ansible.builtin.pip`) is idempotent by default but should be pinned to a `requirements.txt` hash or use a virtual environment state check to avoid unnecessary reinstalls.
- **Inline systemd unit file**: The `fastapi-tutorial.service` unit is written as a heredoc inside the recipe. In Ansible, this should be extracted to a proper `templates/fastapi-tutorial.service.j2` Jinja2 template for maintainability and variable substitution.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` defines a custom Chef resource. Review its implementation before migration — if it wraps standard `sed`/`grep` logic, it maps directly to `ansible.builtin.lineinfile`. If it has non-standard behaviour, it may require a custom Ansible module or a more complex task sequence.
- **Berkshelf vs. Policyfile inconsistency**: `ssl_certificate` is commented out in `Berksfile` but active in `Policyfile.rb` and resolved in `Policyfile.lock.json`. The actual runtime behaviour (Policyfile) includes it as a transitive dependency. Clarify whether any `ssl_certificate` resources are used indirectly before dropping it from scope.
- **Git-based application deployment on `main`**: The `fastapi-tutorial` cookbook syncs from the `main` branch on every run, meaning the deployed application version is not pinned. The Ansible `ansible.builtin.git` module should pin to a specific commit SHA or tag for reproducible deployments.
- **PostgreSQL provisioning via raw shell**: Database and user creation uses `sudo -u postgres psql -c "..."` with `|| true` guards. Replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules for proper idempotency and error handling.

---

### Migration Order

1. **`nginx-multisite` — security sub-tasks** *(low risk, foundational)*
   Migrate the `security.rb` recipe first: UFW rules, sysctl hardening, and fail2ban. These are self-contained, have no external cookbook dependencies, and establish the security baseline. Validate with `ansible-playbook --check` before applying.

2. **`nginx-multisite` — nginx, ssl, and sites sub-tasks** *(moderate complexity)*
   Migrate Nginx installation, the `nginx.conf` template, SSL certificate generation, and virtual host configuration. The ERB templates translate cleanly to Jinja2. Replace `openssl` shell commands with `community.crypto` modules. Validate all three virtual hosts serve HTTPS correctly before proceeding.

3. **`cache`** *(moderate complexity — external dependency replacement)*
   Migrate Memcached (simple) then Redis (complex due to the config-hack). Select `geerlingguy.redis` or write native tasks with a clean config template. Vault-encrypt the Redis password. Verify Redis connectivity from the FastAPI application before proceeding.

4. **`fastapi-tutorial`** *(highest complexity — multiple concerns)*
   Migrate last as it depends on both PostgreSQL (installed as part of this cookbook) and Redis (from `cache`). Create a dedicated `fastapi` system user, vault-encrypt all credentials, fix `.env` file permissions, pin the Git revision, replace raw `psql` commands with `community.postgresql` modules, and extract the systemd unit to a template.

---

### Assumptions

1. **Target OS is Ubuntu (likely 22.04 LTS)**, not Fedora 42 as stated in the Vagrantfile. This is inferred from `apt-get` usage in `vagrant-provision.sh`, `www-data` user references in cookbook recipes, and `ubuntu >= 18.04` support declarations in all `metadata.rb` files. **This must be confirmed with the repository owner before migration begins.**
2. **This is a development/test environment**, not a production system. The use of self-signed certificates, Vagrant, `chef-solo` (no Chef Server), and a single-node topology all indicate a local development stack. Production hardening (certificate authority integration, secrets backend, multi-node inventory) is out of scope for the initial migration but should be planned as a follow-on.
3. **The `ssl_certificate` community cookbook is not directly invoked** by any local cookbook recipe. It appears only as a transitive dependency of `redisio` via the Policyfile resolver. It is assumed safe to drop from the Ansible migration unless investigation of `redisio 7.2.4`'s internals reveals otherwise.
4. **The `selinux` community cookbook is not required on the target system.** Ubuntu uses AppArmor, not SELinux. This dependency is assumed to be an artefact of `redisio`'s broad platform support and can be dropped.
5. **The custom `lineinfile` LWRP** in `cookbooks/nginx-multisite/resources/lineinfile.rb` is assumed to wrap standard line-in-file editing logic equivalent to `ansible.builtin.lineinfile`. Its implementation was not read; this assumption should be verified.
6. **No Chef Server, Chef Automate, or external node inventory exists.** The entire infrastructure is managed via `chef-solo` with a local `solo.json`. The Ansible migration target is a single-host inventory (the Vagrant VM), with `solo.json` attributes mapping to `host_vars` or `group_vars`.
7. **The `project-plan.md` and `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md` files** may contain additional requirements or constraints not captured in the cookbook code. These should be reviewed before finalising the Ansible role structure.
8. **The FastAPI application source (`https://github.com/dibanez/fastapi_tutorial.git`)** is an external public repository. It is assumed to remain accessible and that the `main` branch is stable. The migration plan recommends pinning to a specific commit SHA for reproducibility.
9. **Memcached requires no authentication configuration** in the current setup. No password or SASL configuration is present in the `cache` cookbook. This is assumed intentional (internal-only access) and is preserved in the Ansible migration.
10. **Port 8000 (uvicorn/FastAPI) is not exposed via UFW or Nginx proxy** in the current configuration. The FastAPI service is accessible only directly on port 8000, not through the Nginx reverse proxy. Whether this is intentional or an omission should be clarified — the migration plan does not add a proxy configuration that does not exist in the source.
