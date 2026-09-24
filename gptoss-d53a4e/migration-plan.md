# MIGRATION FROM CHEF TO ANSIBLE

**Executive Summary**
The repository is a pure Chef codebase consisting of three primary cookbooks that provision a multi‑site Nginx reverse‑proxy, a caching layer (Memcached + Redis), and a FastAPI tutorial application with PostgreSQL.  All infrastructure is defined for Ubuntu 18.04+/CentOS 7+ and is driven by a Policyfile/Berksfile that pulls a handful of external community cookbooks.  The migration to Ansible will involve translating each cookbook into Ansible roles, mapping Chef resources to Ansible modules, and re‑creating the policy‑driven run‑list as an Ansible playbook.  Because the codebase is modest (≈ 3 cookbooks, ~ 1 k lines of Ruby), the effort is estimated at **3 weeks** for a small team (1‑2 engineers) – including design, implementation, testing, and knowledge transfer.

---

## Module Migration Plan

This repository contains **Chef** cookbooks that need individual migration planning:

### MODULE INVENTORY

| Module | Description | Path | Technology | Key Features |
|--------|-------------|------|------------|--------------|
| **cache** | Configures caching services – installs Memcached, configures Redis with authentication, creates log directories, and applies a custom Ruby block to clean up Redis defaults. | `cookbooks/cache` | Chef | Memcached installation, Redis server with password, log dir creation, custom config cleanup |
| **fastapi-tutorial** | Deploys a FastAPI tutorial application: installs system packages, clones source, builds a Python virtual‑env, installs dependencies, creates a PostgreSQL database/user, writes an `.env` file, and registers a systemd service. | `cookbooks/fastapi-tutorial` | Chef | Python/venv, PostgreSQL DB & user, hard‑coded DB credentials, systemd service, environment file |
| **nginx-multisite** | Sets up Nginx with multiple SSL‑enabled virtual hosts, security hardening (fail2ban, ufw, sysctl), and self‑signed certificate generation for each site. | `cookbooks/nginx-multisite` | Chef | Nginx package & templated config, per‑site document roots, fail2ban, ufw firewall rules, SSH hardening, self‑signed SSL certs |

**CRITICAL PATH VERIFICATION:**
All modules listed above were discovered in the provided repository tree and verified by reading their `metadata.rb` and primary recipe files.

---

### Infrastructure Files

| File | Purpose & Migration Considerations |
|------|------------------------------------|
| `Berksfile` | Declares external cookbook dependencies (nginx, memcached, redisio, ssl_certificate).  In Ansible these become Galaxy roles or direct module usage; version constraints must be captured. |
| `Policyfile.rb` | Defines the run‑list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`).  Will be translated into an Ansible playbook that includes the three roles in the same order. |
| `Vagrantfile` | Provides a local VM for development/testing.  Ansible can be used as the provisioner inside Vagrant; the file will be updated to point to the generated playbook. |
| `vagrant-provision.sh` | Shell script used by Vagrant to invoke Chef Solo.  Will be replaced by `ansible-playbook` command. |
| `solo.json` / `solo.rb` | Chef Solo configuration – not needed after migration; can be archived. |
| `project-plan.md` | Existing project documentation – useful reference for migration scope. |
| `x2a-rules/*.md` | Miscellaneous documentation – no direct impact on migration. |

---

## Target Details

- **Operating System**: The cookbooks declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.  No OS‑specific logic beyond package names; the target Ansible environment will target the same families (Ubuntu 22.04 LTS / RHEL 9 as default if unspecified). 
- **Virtual Machine Technology**: Vagrant is used for local development; the underlying provider is not explicit (likely VirtualBox).  Migration will keep Vagrant as the test harness, switching the provisioner to Ansible.
- **Cloud Platform**: No cloud‑specific resources (AWS, Azure, GCP) are present.  The target is on‑premise or generic cloud VMs.

---

## Migration Approach

### Key Dependencies to Address

| Dependency | Current Version / Constraint | Ansible Replacement |
|------------|------------------------------|---------------------|
| `nginx` (Chef cookbook) | `~> 12.0` | Use Ansible `nginx` role from Ansible Galaxy or the built‑in `ansible.builtin.apt/yum` + `ansible.builtin.template` for config files. |
| `memcached` | `~> 6.0` | Ansible `community.general.memcached` module or simple package install + config template. |
| `redisio` | latest (no constraint) | Ansible `community.redis.redis` role or manual package install + configuration template. |
| `ssl_certificate` | `~> 2.1` | Replace with Ansible `community.crypto.openssl_certificate` module for self‑signed certs or use `acme_certificate` for real certs. |
| `fail2ban` (via Chef) | N/A | Ansible `community.general.fail2ban` role or package + template. |
| `ufw` | N/A | Ansible `community.general.ufw` module. |
| `sysctl` | N/A | Ansible `ansible.posix.sysctl` module. |

### Security Considerations

- **Hard‑coded credentials**: Redis password (`redis_secure_password_123`) and PostgreSQL user/password (`fastapi_password`) are stored in plain text within recipes and generated `.env` files.  Migration should move these to Ansible Vault or an external secret manager (e.g., HashiCorp Vault) and reference them via `{{ vault_redis_password }}` etc.
- **SSH hardening**: Chef recipes modify `/etc/ssh/sshd_config`.  In Ansible, use the `ansible.posix.authorized_key` and `ansible.builtin.lineinfile` modules to enforce `PermitRootLogin no` and `PasswordAuthentication no`.
- **Firewall rules**: UFW commands will be replaced by the `community.general.ufw` module, ensuring idempotent rule management.
- **Fail2ban configuration**: The `jail.local` template contains regexes; ensure the template is migrated unchanged and stored securely.
- **Self‑signed certificates**: Generated via `openssl` command in Chef.  Ansible can use `community.crypto.openssl_certificate` to produce identical certs, but consider moving to a proper PKI for production.

### Technical Challenges

1. **Ruby‑specific logic (ruby_block)** – The `cache` cookbook contains a `ruby_block` that manually edits the Redis config file.  Ansible can replace this with the `ansible.builtin.replace` or `ansible.builtin.lineinfile` modules, but careful testing is required to ensure the same idempotent behaviour.
2. **Dynamic site discovery**: Nginx‑multisite iterates over `node['nginx']['sites']` (a data structure likely supplied via attributes or Hiera).  In Ansible, this will become a variable (e.g., `nginx_sites`) defined in group_vars/host_vars or passed via inventory.  Mapping the attribute hierarchy to Ansible variables is a key step.
3. **Template syntax conversion**: Chef uses ERB (`*.erb`).  Ansible uses Jinja2 (`*.j2`).  All templates (`nginx.conf.erb`, `security.conf.erb`, `site.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`) must be converted to Jinja2 syntax, preserving variable references.
4. **Service notifications**: Chef’s `notifies` triggers delayed reloads.  In Ansible, handlers will be defined for `nginx reload`, `fail2ban restart`, `ssh restart`, etc., and tasks will `notify` them appropriately.
5. **Policyfile run‑list ordering**: The Chef run‑list defines a specific order; Ansible playbooks must respect this order to avoid race conditions (e.g., Nginx must be configured after SSL certs are generated).

### Migration Order

1. **Foundation Role – `cache`** (low complexity, no external services).  Convert package installs, directory creation, and Redis config cleanup.
2. **Web Server Role – `nginx-multisite`** (moderate complexity).  Migrate Nginx installation, templating, firewall, fail2ban, SSH hardening, and SSL generation.
3. **Application Role – `fastapi-tutorial`** (higher complexity).  Migrate system packages, git clone, Python venv, PostgreSQL DB/user creation, environment file, and systemd service.
4. **Playbook Assembly** – Create a top‑level playbook that includes the three roles in the order above, mirroring the Policyfile run‑list.
5. **Testing & Validation** – Use the existing Vagrant environment to spin up a VM, run the Ansible playbook, and verify functional parity.

### Assumptions

- The repository contains **only** the three cookbooks listed; no hidden Puppet, PowerShell, or Salt modules exist.
- All attribute data (e.g., `node['nginx']['sites']`) is defined within the cookbooks or supplied via Chef attributes files; we will translate these into Ansible variables.
- External community cookbooks are stable and have comparable functionality in Ansible Galaxy or via built‑in modules.
- The target environment will continue to use Ubuntu/CentOS; no OS migration is planned.
- Secrets management will be introduced during migration (Ansible Vault) – existing plain‑text passwords will be replaced.
- No cloud‑specific resources are required; the migration stays within the same VM/VMware/VirtualBox context.

---

## Next Steps
1. **Kick‑off meeting** with the DevOps team to agree on variable naming conventions and secret handling strategy.
2. **Create Ansible role skeletons** (`cache`, `nginx_multisite`, `fastapi_tutorial`).
3. **Port templates** from ERB to Jinja2.
4. **Implement handlers** for service reloads/restarts.
5. **Iterative testing** in the Vagrant VM, fixing idempotency issues.
6. **Documentation hand‑off** – update `project-plan.md` with the new Ansible architecture.

---

*Prepared by the Migration Planning Agent*