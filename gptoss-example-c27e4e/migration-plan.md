# MIGRATION FROM CHEF TO ANSIBLE

**Executive Summary**

The repository is a small Chef ecosystem consisting of three primary cookbooks (`cache`, `fastapi-tutorial`, `nginx-multisite`) plus supporting infrastructure files (Berksfile, Policyfile, Vagrantfile, solo.json, solo.rb, provisioning script).  All configuration is expressed as Chef resources and attributes, targeting Ubuntu 18.04+/CentOS 7+ Linux VMs provisioned via Vagrant/libvirt.  The migration to Ansible will involve translating each cookbook into one or more Ansible roles, preserving the same functional boundaries (caching services, FastAPI application stack, multi‑site Nginx with security hardening).  Because the code base is modest (≈ 3 k lines of Ruby DSL) the overall effort is estimated at **2–3 weeks** for a small team (1–2 engineers) including testing, CI integration, and knowledge transfer.

---

## Module Migration Plan

This repository contains **Chef** cookbooks that need individual migration planning:

### MODULE INVENTORY

| Module | Description | Path | Technology | Key Features |
|--------|-------------|------|------------|--------------|
| **cache** | Configures caching services – installs `memcached` and `redisio`, sets a Redis password, creates log directory, and applies a custom Ruby block to clean up unwanted Redis config lines. | `cookbooks/cache` | Chef | Memcached installation, Redis with authentication, log directory creation, custom config sanitisation. |
| **fastapi-tutorial** | Deploys a FastAPI tutorial application: installs system packages, clones source repo, creates a Python virtual environment, installs Python deps, provisions PostgreSQL, creates DB/user with password, writes `.env`, creates systemd service for the app. | `cookbooks/fastapi-tutorial` | Chef | Python/virtualenv, PostgreSQL DB & user, systemd service, environment file with credentials. |
| **nginx-multisite** | Sets up Nginx with multiple SSL‑enabled sub‑domains, hardens the host (fail2ban, ufw, sysctl, SSH hardening), generates self‑signed certificates per site, and deploys site‑specific `index.html` files. | `cookbooks/nginx-multisite` | Chef | Nginx package & templated config, per‑site document roots, fail2ban, UFW firewall rules, SSH root/PasswordAuth disable, self‑signed SSL cert generation, sysctl security tweaks. |

**CRITICAL PATH VERIFICATION:**
All modules listed above were discovered in the provided repository tree and verified by reading their `metadata.rb` and primary recipe files.

---

### Infrastructure Files

| File | Purpose | Migration Considerations |
|------|---------|--------------------------|
| `Berksfile` | Declares local and external cookbook sources and version constraints. | Translate to Ansible Galaxy `requirements.yml` (external roles) and ensure equivalent versions of community roles (e.g., `geerlingguy.nginx`, `geerlingguy.redis`, `geerlingguy.memcached`). |
| `Policyfile.rb` | Defines run‑list and cookbook pins for policy‑based Chef runs. | Run‑list maps directly to Ansible playbook order. Pinning becomes version constraints in `requirements.yml`. |
| `Vagrantfile` | Spins up a Fedora 42 VM with libvirt, forwards ports, and runs a shell provisioner that invokes Chef. | Convert to an Ansible‑driven Vagrant provisioner (`config.vm.provision "ansible"`) or keep Vagrant for VM creation and hand over configuration to Ansible. |
| `vagrant-provision.sh` | Shell script that installs Chef client, uploads cookbooks, and runs `chef-client`. | Replace with Ansible playbook execution (`ansible-playbook site.yml`). |
| `solo.json` / `solo.rb` | Chef Solo configuration (node attributes, cookbook paths). | Node attributes become Ansible variables (group_vars/host_vars). Solo config is no longer needed. |
| `project-plan.md` | High‑level project documentation. | Keep as reference; update with Ansible‑specific milestones. |
| `x2a-rules/...` | Miscellaneous markdown notes (not part of provisioning). | No migration needed. |

---

## Target Details

- **Operating System**: The cookbooks declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7. The Vagrant box used is `generic/fedora42`.  For the migration we will target **Ubuntu 22.04 LTS** as the primary OS (most community Ansible roles assume Debian‑based platforms) while preserving CentOS compatibility where needed.
- **Virtual Machine Technology**: Vagrant with the `libvirt` provider (KVM).  No change required; Ansible can be invoked from Vagrant.
- **Cloud Platform**: Not specified.  All provisioning is local VM‑centric.  If later moved to AWS/Azure/GCP, the same Ansible roles can be reused with cloud‑specific modules.

---

## Migration Approach

### Key Dependencies to Address

| Dependency | Current Version / Constraint | Ansible Replacement |
|------------|------------------------------|---------------------|
| `nginx` (Chef cookbook) | `~> 12.0` | `geerlingguy.nginx` role (latest) |
| `memcached` (Chef cookbook) | `~> 6.0` | `geerlingguy.memcached` role |
| `redisio` (Chef cookbook) | `~> 7.2.4` | `geerlingguy.redis` role |
| `ssl_certificate` (Chef cookbook – commented) | `~> 2.1` | Handled by custom Ansible tasks (OpenSSL module) |
| System packages (python3, postgresql, etc.) | Installed via Chef `package` resource | Ansible `apt`/`yum` modules |

### Security Considerations

1. **Hard‑coded credentials**
   - Redis password (`redis_secure_password_123`) in `cache/recipes/default.rb`.
   - PostgreSQL user/password (`fastapi` / `fastapi_password`) in `fastapi-tutorial/recipes/default.rb`.
   - These should be moved to Ansible Vault or an external secret manager (e.g., HashiCorp Vault, AWS Secrets Manager).  The migration plan includes creating encrypted variables (`vault_redis_password`, `vault_fastapi_db_password`).
2. **SSH hardening**
   - Disables root login and password authentication via inline `execute` resources.  In Ansible, use the `openssh_keypair` and `lineinfile` modules, or the `ansible.posix.authorized_key` and `ansible.builtin.service` for SSH service reload.
3. **Firewall (UFW) rules**
   - Managed via `execute` resources.  Replace with the `community.general.ufw` Ansible module for idempotent rule management.
4. **Fail2Ban configuration**
   - Template `fail2ban.jail.local.erb`.  Convert to an Ansible template (`fail2ban/jail.local.j2`) and use the `service` module for restarts.
5. **Self‑signed SSL certificates**
   - Generated with a shell `execute`.  Use the `community.crypto.openssl_certificate` module for deterministic certificate creation.

### Technical Challenges

| Challenge | Description | Mitigation |
|-----------|-------------|------------|
| **Ruby‑specific logic (ruby_block)** | The `cache` cookbook uses a `ruby_block` to edit the Redis config file in‑place. | Replace with Ansible `lineinfile` or `replace` modules; ensure idempotence. |
| **Dynamic site generation** | Nginx sites are defined in a Ruby attribute hash and iterated over. | Translate the attribute hash to an Ansible dictionary variable (`nginx_sites`) and loop with `with_items`/`loop`. |
| **Systemd service templating** | FastAPI service file is written via a `file` resource with embedded heredoc. | Use Ansible `template` module with a Jinja2 systemd unit file. |
| **Mixed OS support** | Vagrant box is Fedora, but cookbooks target Ubuntu/CentOS. | Standardise on Ubuntu 22.04 for the migration; test role compatibility on CentOS if required. |
| **External community cookbooks** | Chef community cookbooks may have richer functionality than the Ansible equivalents. | Evaluate required features; if missing, implement custom Ansible tasks (e.g., Redis auth). |

### Migration Order

1. **Foundation Layer** – Set up base OS, package manager, and common utilities (Python, Git, OpenSSL).  Create an Ansible playbook that installs required system packages and configures the VM (mirrors Vagrant provisioning).  This establishes a stable platform for subsequent roles.
2. **Cache Role** – Migrate `cache` cookbook to an Ansible role (`role_cache`).  Validate memcached and Redis installation, secret handling, and config sanitisation.
3. **Nginx‑Multisite Role** – Migrate `nginx-multisite` to `role_nginx_multisite`.  Include sub‑roles or tasks for security hardening (UFW, Fail2Ban, SSH), SSL generation, and site provisioning.
4. **FastAPI Tutorial Role** – Migrate `fastapi-tutorial` to `role_fastapi`.  Ensure PostgreSQL setup, DB/user creation, virtualenv handling, and systemd service deployment.
5. **Integration Playbook** – Assemble a top‑level playbook (`site.yml`) that runs the roles in the order: `common`, `cache`, `nginx_multisite`, `fastapi`.  Align with the original Chef run‑list.
6. **Testing & CI** – Add Molecule tests for each role, integrate with GitHub Actions or similar CI pipeline.

### Assumptions

- The target environment will be a Linux VM (Ubuntu 22.04) managed by Vagrant/libvirt; no Windows or PowerShell components are present.
- All external Chef community cookbooks have functional equivalents in Ansible Galaxy or can be re‑implemented with a modest amount of custom tasks.
- Secrets are acceptable to be stored in Ansible Vault for the purpose of this migration; no external secret‑store integration is required at this stage.
- The `ssl_certificate` cookbook is not used (commented out) – SSL handling will be fully covered by the custom tasks in the `nginx-multisite` role.
- No Puppet, Salt, or PowerShell modules exist in this repository; the only IaC technology present is Chef.
- The Vagrant provisioning script (`vagrant-provision.sh`) only installs Chef and runs `chef-client`; it does not contain additional logic that needs migration.

---

## Next Steps

1. **Create Ansible role skeletons** (`ansible-galaxy init role_cache`, etc.).
2. **Export external dependencies** to `requirements.yml`.
3. **Map Chef attributes to Ansible variables** (e.g., `node['nginx']['sites']` → `nginx_sites`).
4. **Implement secret handling** with Ansible Vault.
5. **Develop and run Molecule tests** for each role.
6. **Update Vagrantfile** to use Ansible provisioner and verify end‑to‑end deployment.
7. **Document hand‑off** and conduct knowledge‑transfer sessions with the operations team.

---

*Prepared by the Migration Planning Agent on 2026‑09‑24.*