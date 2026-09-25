# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo** infrastructure-as-code project that provisions a single server running Nginx (multi-site with SSL), caching services (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL. The project is currently developed and tested via **Vagrant + libvirt** on a Fedora 42 VM, using **Berkshelf** for dependency management and a **Policyfile** for run-list locking.

The migration scope covers **3 local cookbooks** and **5 external Chef Supermarket dependencies**, translating into approximately **4–5 Ansible roles** plus a top-level playbook. The overall complexity is **low-to-moderate**: the logic is straightforward, but several security-sensitive items (hardcoded credentials, self-signed SSL generation, SSH hardening) require careful handling during migration.

**Estimated timeline**: 2–3 weeks for a single engineer, including testing.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths were confirmed in the provided repository tree or via `file_search` are listed below.

---

- **nginx-multisite**:
  - Description: Nginx web server with multi-site virtual host support, SSL termination, HTTP→HTTPS redirection, and security hardening. Manages three named virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with self-signed TLS certificates, HSTS, CSP, and X-Frame-Options headers. Also configures fail2ban, UFW firewall rules (deny-all default, allow SSH/HTTP/HTTPS), and kernel-level sysctl security parameters. SSH root login and password authentication are disabled via `sshd_config` manipulation.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: ERB-templated `nginx.conf` and per-site `site.conf`, TLSv1.2/1.3-only cipher suite, HSTS with `includeSubDomains`, fail2ban `jail.local` template, UFW idempotent shell commands, sysctl hardening via `/etc/sysctl.d/99-security.conf`, Hiera-equivalent node attributes for site definitions, `lineinfile` custom resource, static `index.html` files per site served from cookbook files.

- **cache**:
  - Description: Caching layer that installs and configures both Memcached and Redis on the same host. Redis is configured with password authentication (`requirepass`) on port 6379. Includes a `ruby_block` workaround that post-processes the Redis config file to strip deprecated `replica-*` directives that the `redisio` cookbook writes but the installed Redis version rejects.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Delegates Memcached setup to the `memcached` community cookbook (v6.1.0), delegates Redis setup to `redisio` (v7.2.4) with `redisio::enable`, creates `/var/log/redis` directory, hardcoded Redis password in recipe attributes, post-install config-file patching hack.

- **fastapi-tutorial**:
  - Description: Deploys a FastAPI Python application from a public GitHub repository (`dibanez/fastapi_tutorial`, `main` branch) into `/opt/fastapi-tutorial`. Sets up a Python 3 virtual environment, installs pip dependencies, provisions a PostgreSQL database and user, writes a `.env` file with database credentials, and registers a systemd service (`fastapi-tutorial.service`) running `uvicorn` on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: `git` resource for source checkout, Python venv creation, PostgreSQL user/database provisioning via `psql` shell commands, plaintext `.env` file with `DATABASE_URL` containing credentials, systemd unit file written inline, service runs as `root`, `systemctl daemon-reload` triggered on unit file change.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all three local cookbooks by path and four external cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — the last one commented out in Berksfile but active in Policyfile). Must be replaced by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the run-list (`nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`) and pinned cookbook sources. Defines the authoritative execution order for migration.
- `Policyfile.lock.json`: Locked dependency graph with exact versions and SHA identifiers for all 8 resolved cookbooks (including transitive deps `selinux 6.2.4` pulled in by `redisio`). Reference for exact versions when selecting Ansible Galaxy roles.
- `solo.rb`: Chef Solo configuration pointing to `/var/chef-solo` cache and `/chef-repo/cookbooks` path. No direct Ansible equivalent needed; replaced by inventory and `ansible.cfg`.
- `solo.json`: Node JSON supplying the run-list and all node attribute overrides (site definitions, SSL paths, security flags). This is the primary source of truth for variable values to be ported into Ansible `group_vars` or role `defaults`.
- `Vagrantfile`: Vagrant + libvirt VM definition (Fedora 42, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443). Provisions via `vagrant-provision.sh`. Ansible equivalent: replace `chef_solo` provisioner block with `ansible_local` or `ansible` provisioner.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef, runs Berkshelf vendor, and executes `chef-solo`. In Ansible migration, this is replaced by the Vagrant `ansible` provisioner or a simple `ansible-playbook` call.
- `x2a-rules/cbbb21c1-fa2c-417e-a1d6-42b822782fbd.md`: Project note requesting GitHub Actions CI pipelines for each Ansible project. Should be implemented as part of the migration deliverables.
- `project-plan.md`: Existing project planning document; review for additional context before finalising migration scope.

---

### Target Details

- **Operating System**: Ubuntu 18.04+ or CentOS 7+ per cookbook `metadata.rb` `supports` declarations. The Vagrant box is `generic/fedora42`, indicating active development targets Fedora 42 (RPM-based). Migration should target **Ubuntu 22.04 LTS** or **Red Hat Enterprise Linux 9** depending on production environment; Fedora 42 is used for local development only.
- **Virtual Machine Technology**: **libvirt / KVM** — confirmed by `config.vm.provider "libvirt"` in `Vagrantfile`. Vagrant is used exclusively for local development and testing.
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present in the repository.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Chef Supermarket community cookbook: Replace with the `ansible.builtin.package` module to install `nginx` from the OS package manager, plus `ansible.builtin.template` for `nginx.conf` and per-site configs. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) translate directly to Jinja2 with minimal syntax changes.
- **memcached (6.1.0)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service` (enable/start). Configuration is minimal; no complex template needed.
- **redisio (7.2.4)** — Chef Supermarket community cookbook: Replace with `ansible.builtin.package` (install `redis`/`redis-server`) and `ansible.builtin.template` for `/etc/redis/redis.conf`. The `ruby_block` config-patching hack is eliminated entirely — Ansible's template will write a clean config from the start.
- **ssl_certificate (2.1.0)** — Chef Supermarket community cookbook (locked in Policyfile, commented out in Berksfile): Currently unused in active recipes; self-signed cert generation is handled inline via `openssl` shell commands. In Ansible, use `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey` modules for idempotent certificate management.
- **selinux (6.2.4)** — Transitive dependency of `redisio`: Pulled in automatically; no direct recipe usage visible. In Ansible, use `ansible.posix.selinux` module if the target is RHEL/Fedora; no action needed for Ubuntu.

### Security Considerations

- **Hardcoded Redis password**: The string `redis_secure_password_123` is written directly in `cookbooks/cache/recipes/default.rb` as a node attribute. **Must be migrated to Ansible Vault** (`ansible-vault encrypt_string`) and referenced as a variable — never stored in plaintext in the playbook or role defaults.
- **Hardcoded PostgreSQL credentials**: `fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` in both the `psql` provisioning commands and the `.env` file written to disk. Both the provisioning variable and the `.env` file content must be Vault-encrypted. The `.env` file permissions should also be tightened from `0644` to `0600`.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk and should be corrected during migration — create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed SSL certificates**: Generated via inline `openssl req` shell commands in `ssl.rb`. In Ansible, replace with `community.crypto` modules for idempotent, auditable certificate lifecycle management. For production, integrate with Let's Encrypt (`community.crypto.acme_certificate`) or an internal CA.
- **SSH hardening**: `security.rb` disables root login and password authentication via `sed` on `sshd_config`. In Ansible, use `ansible.builtin.lineinfile` or `ansible.builtin.template` for `sshd_config` to achieve the same result idempotently. Ensure the Ansible control node has key-based access configured before applying this change.
- **UFW firewall**: Managed via raw `execute` shell commands with `not_if` guards. Replace with `community.general.ufw` module for fully idempotent firewall management.
- **fail2ban configuration**: Managed via an ERB template (`fail2ban.jail.local.erb`). Translate to a Jinja2 template; review the template content for any site-specific ban thresholds or email alert addresses that may need to become variables.
- **Sysctl hardening**: Written to `/etc/sysctl.d/99-security.conf` via ERB template. Use `ansible.posix.sysctl` module instead of a raw template for individual parameter management, or keep as a template for bulk application.
- **No Chef Vault or encrypted data bags** are present in this repository — all secrets are currently in plaintext in recipe files or node JSON.

### Technical Challenges

- **`ruby_block` config-patching hack in `cache`**: The Redis recipe post-processes the generated config file to strip deprecated directives. This workaround exists because `redisio` 7.2.4 writes Redis 3.x-era config keys that newer Redis versions reject. In Ansible, this is eliminated by writing the Redis config directly from a Jinja2 template — but the correct set of valid config keys for the target Redis version must be verified before writing the template.
- **Attribute-driven multi-site loop**: `nginx-multisite` iterates over `node['nginx']['sites']` to generate virtual host configs, SSL certificates, document roots, and static files. In Ansible, this maps to a `loop` over a `sites` list variable, but the per-site `cookbook_file` resource (which selects a static HTML file by site name prefix) requires careful mapping to `ansible.builtin.copy` with a computed `src` path.
- **Chef `lineinfile` custom resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` defines a custom Chef resource. Its purpose must be reviewed before migration to determine whether it is actually called anywhere and what Ansible built-in it maps to (`ansible.builtin.lineinfile`).
- **Vagrant box is Fedora 42 but metadata supports Ubuntu/CentOS**: Package names, service names, and paths differ between distributions (e.g., `redis` vs `redis-server`, `ssh` vs `sshd`). The Ansible roles must either target a single OS or use `ansible_os_family` conditionals. Clarify the production target OS before writing roles.
- **`ssl_certificate` cookbook is locked but commented out**: The Policyfile.lock.json includes `ssl_certificate 2.1.0` as a resolved dependency, but it is commented out in `Berksfile` and not called in any recipe. Confirm whether it was intentionally removed or is planned for future use before deciding whether to include `community.crypto` in the Ansible role.
- **Git-based application deployment**: `fastapi-tutorial` clones from a public GitHub URL at `main` branch with no pinned commit. This is non-deterministic. During migration, pin to a specific tag or commit SHA in the Ansible `ansible.builtin.git` task, and consider whether the repository should be mirrored internally.
- **Vagrant provisioner replacement**: The `vagrant-provision.sh` script installs Chef at runtime via `curl | bash` (a security anti-pattern). The Vagrant `ansible` provisioner should replace this entirely, pointing at the new playbook. The `ansible_local` provisioner can be used if Ansible is not available on the host machine.
- **GitHub Actions CI requirement**: The `x2a-rules` note requests GitHub Actions pipelines per Ansible project. This is an additional deliverable: a workflow running `ansible-lint`, `molecule` tests, and optionally `vagrant up --provision` in a CI environment must be created alongside the playbook.

### Migration Order

1. **`nginx-multisite` → Ansible role `nginx_multisite`** *(Priority 1 — highest value, self-contained)*
   Install and configure Nginx, deploy virtual host configs from Jinja2 templates, generate self-signed certificates via `community.crypto`, deploy static site files, configure security headers. This is the most feature-rich cookbook but has no external cookbook dependencies beyond the `nginx` package itself.

2. **`cache` → Ansible role `cache`** *(Priority 2 — moderate complexity)*
   Install Memcached and Redis via package manager, write Redis config from a clean Jinja2 template (eliminating the `ruby_block` hack), enable services. Migrate the Redis password to Ansible Vault before writing any task files.

3. **Security hardening sub-tasks within `nginx_multisite` role** *(Priority 3 — security-sensitive)*
   Migrate fail2ban, UFW, sysctl, and SSH hardening tasks. These touch system-wide security settings and must be tested carefully — especially SSH hardening, which can lock out the Ansible control node if applied incorrectly.

4. **`fastapi-tutorial` → Ansible role `fastapi_tutorial`** *(Priority 4 — most complex, credential-heavy)*
   Clone application from Git (pin revision), create virtualenv, install pip dependencies, provision PostgreSQL user and database, write Vault-encrypted `.env` file with `0600` permissions, deploy and enable systemd service under a non-root user. This role has the most security remediation work and depends on PostgreSQL being available (either provisioned by this role or a separate `postgresql` role).

### Assumptions

1. **Target OS for production is not explicitly defined.** The `metadata.rb` files list both Ubuntu ≥ 18.04 and CentOS ≥ 7.0 as supported, but the Vagrant box is Fedora 42. It is assumed that the primary migration target is **Ubuntu 22.04 LTS** unless confirmed otherwise; OS-specific conditionals will be needed for RHEL/Fedora support.
2. **All three cookbooks run on a single host.** The `solo.json` run-list and Vagrant single-VM setup imply a monolithic deployment. It is assumed this remains a single-host deployment in Ansible (one play, one inventory host), not a distributed multi-host topology.
3. **Self-signed certificates are acceptable for the target environment.** The SSL recipe explicitly generates self-signed certs "for development." If this is also used in staging or production, a proper CA or ACME integration must be added — this is flagged as an assumption requiring stakeholder confirmation.
4. **The `ssl_certificate` community cookbook is intentionally unused.** It is locked in `Policyfile.lock.json` but commented out in `Berksfile` and not called in any recipe. It is assumed it can be safely excluded from the Ansible migration.
5. **The Redis `ruby_block` hack is a workaround for a version mismatch**, not intentional behaviour. It is assumed the Ansible migration will write a clean Redis config template, making the hack unnecessary.
6. **No Chef Server, Chef Vault, or encrypted data bags are in use.** All configuration is Chef Solo with plaintext attributes. There are no encrypted secrets to decrypt or migrate from a Chef secrets store.
7. **The GitHub repository `dibanez/fastapi_tutorial` is accessible** from the target environment at provisioning time. If the environment is air-gapped, an internal mirror or artifact repository must be set up before migration.
8. **The `project-plan.md` file does not contain additional module definitions** beyond what is captured here. It has not been read in full; if it contains additional infrastructure requirements, the module inventory may need to be extended.
9. **The `x2a-rules` GitHub Actions requirement applies to the migrated Ansible project**, not the current Chef repository. It is assumed a single GitHub Actions workflow per Ansible role (or one workflow for the entire playbook) is acceptable.
10. **Vagrant + libvirt remains the local development environment** after migration. Only the provisioner changes from `shell`/Chef Solo to Ansible; the VM definition, network, and resource allocation remain the same.
