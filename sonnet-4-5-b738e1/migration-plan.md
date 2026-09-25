# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a single Vagrant-based virtual machine (Fedora 42, libvirt) running a multi-service web stack. The policy (`nginx-multisite-policy`) executes three local cookbooks in sequence: a hardened Nginx multi-site reverse proxy, a dual caching layer (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL.

The migration scope is **moderate**: three local cookbooks, four external Supermarket dependencies, and a well-defined run-list. No Chef Server, encrypted data bags, or Chef Vault are in use — the entire stack runs via `chef-solo`, which maps cleanly to Ansible's agentless push model. The primary complexity lies in replacing Chef community cookbooks (`nginx`, `memcached`, `redisio`, `ssl_certificate`, `selinux`) with native Ansible modules and roles, and in carefully handling the hardcoded credentials and self-signed certificate generation logic.

**Estimated migration timeline: 2–3 weeks** for a single engineer familiar with Ansible, or 1–1.5 weeks with a two-person team.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by **5 external Chef Supermarket cookbooks** that will be replaced by Ansible built-ins or Galaxy roles.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads. No paths have been inferred or invented.

---

- **nginx-multisite**
  - **Description**: Nginx reverse proxy with SSL termination, multi-site virtual host management, host-based firewall hardening, SSH hardening, and kernel-level network security tuning. Manages three SSL-enabled subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with self-signed TLS certificates (RSA 2048, 365-day), HTTP→HTTPS redirect, HSTS, and a full suite of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy). Firewall is enforced via UFW (default-deny, allow SSH/80/443). Intrusion prevention is handled by Fail2ban with jails for sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch. Kernel hardening is applied via sysctl (IP spoofing protection, ICMP redirect suppression, SYN flood protection, IPv6 disable).
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**: ERB templates for `nginx.conf`, per-site `site.conf`, `security.conf`, `fail2ban.jail.local`, and `sysctl-security.conf`; `lineinfile` custom resource; static `index.html` files per site; `ssl-cert` group management; `www-data` ownership of document roots; sites-available/sites-enabled symlink pattern; TLSv1.2/1.3 only with strong cipher suite.

---

- **cache**
  - **Description**: Dual in-memory caching layer installing and configuring both Memcached and Redis on the same host. Redis is configured on port 6379 with password authentication (`requirepass redis_secure_password_123` — hardcoded plaintext). Includes a `ruby_block` workaround that post-processes the generated Redis config file to strip deprecated `replica-*` directives incompatible with the installed Redis version, indicating a known compatibility issue with the `redisio` 7.2.4 cookbook. A dedicated `/var/log/redis` directory is created with correct ownership.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**: Delegates to community cookbooks `memcached` (~> 6.0) and `redisio` (7.2.4); Redis password set via node attribute; post-install config file mutation hack to fix deprecated directives; `redisio::enable` for service management.

---

- **fastapi-tutorial**
  - **Description**: Full-stack Python web application deployment for a FastAPI tutorial project. Installs Python 3, pip, venv, git, PostgreSQL (with `postgresql-contrib` and `libpq-dev`), clones the application from a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, `main` branch), creates a Python virtual environment, installs pip dependencies from `requirements.txt`, configures and starts PostgreSQL, provisions a database user (`fastapi`) and database (`fastapi_db`) with hardcoded credentials, writes a `.env` file with the `DATABASE_URL`, and installs a systemd unit file to run the app via `uvicorn` on port 8000 as root.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**: `git` resource for application deployment; Python venv creation and pip install via `execute`; PostgreSQL provisioning via inline `psql` shell commands with `|| true` guards; plaintext credentials in `.env` file (`fastapi_password`); systemd service running as `root`; `systemctl daemon-reload` via notifies chain.

---

### Infrastructure Files

- **`Policyfile.rb`**: Chef Policyfile defining the `nginx-multisite-policy` run-list and pinning all cookbook sources. This is the authoritative dependency manifest. Migration consideration: the run-list order (`nginx-multisite → cache → fastapi-tutorial`) defines the provisioning sequence and must be preserved in Ansible playbook task ordering.
- **`Policyfile.lock.json`**: Fully resolved dependency lock file. Records exact versions: `nginx` 12.3.1, `memcached` 6.1.0, `redisio` 7.2.4, `ssl_certificate` 2.1.0, `selinux` 6.2.4. Use these pinned versions as the reference when selecting equivalent Ansible Galaxy roles.
- **`Berksfile`**: Berkshelf dependency file mirroring the Policyfile. Notes that `ssl_certificate` is commented out in Berksfile but present in Policyfile.lock.json — the lock file is the ground truth.
- **`solo.json`**: Chef Solo JSON attributes file. Defines the run-list and all runtime node attributes (site definitions, SSL paths, security flags). This file is the direct source for Ansible variable definitions (`host_vars`, `group_vars`, or role defaults).
- **`solo.rb`**: Chef Solo configuration. Sets `file_cache_path` and `cookbook_path`. No migration action needed; informational only.
- **`Vagrantfile`**: Vagrant VM definition using `generic/fedora42` box with libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Provisions via `vagrant-provision.sh`. Migration consideration: the Ansible inventory should reflect this host definition; the Vagrantfile can be updated to use the `ansible` provisioner instead of the shell provisioner.
- **`vagrant-provision.sh`**: Shell bootstrap script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks vendor`, and executes `chef-solo`. This entire script is replaced by Ansible's native Vagrant provisioner (`ansible_local` or `ansible`).
- **`project-plan.md`**: Existing project documentation. Review for any additional context before migration.
- **`x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`**: Migration rules or constraints file. Review contents before finalizing the Ansible role structure.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` (Fedora 42). However, `metadata.rb` for all three cookbooks declares support for `ubuntu >= 18.04` and `centos >= 7.0`. The nginx recipes use `www-data` as the web server user (Debian/Ubuntu convention) and `apt-get` is used in the provisioning script — indicating the **actual tested target is Ubuntu**. The Fedora box in the Vagrantfile may be aspirational or a recent change. Clarification is required before finalizing the Ansible target OS. Default assumption: **Ubuntu 22.04 LTS** based on `www-data` user, `apt-get`, and `ufw`/`fail2ban` package names.
- **Virtual Machine Technology**: **libvirt / KVM** via Vagrant (`config.vm.provider "libvirt"`). VM title is `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-specific configurations, metadata endpoints, or cloud SDK references are present. This is a local development/lab environment.

---

## Migration Approach

### Key Dependencies to Address

- **`nginx` (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module for installation and `ansible.builtin.template` for `nginx.conf` and per-site configs. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) translate directly to Jinja2. Alternatively, use the `nginxinc.nginx` Galaxy role.
- **`memcached` (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.service`. No complex configuration is applied — a simple role or task file is sufficient.
- **`redisio` (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/6379.conf`. The post-install config-mutation hack in the `cache` cookbook must be replaced with a properly rendered Jinja2 template that omits the deprecated directives entirely. Consider the `geerlingguy.redis` Galaxy role as a well-maintained alternative.
- **`ssl_certificate` (2.1.0, Chef Supermarket)**: Present in `Policyfile.lock.json` but not explicitly called in any local recipe (SSL cert generation is done inline via `openssl` shell commands in `ssl.rb`). Replace with `ansible.builtin.command` or the `community.crypto.x509_certificate` module for self-signed cert generation.
- **`selinux` (6.2.4, Chef Supermarket)**: Pulled in transitively by `redisio`. On Ubuntu targets this is a no-op. If the target is RHEL/CentOS/Fedora, use the `ansible.posix.selinux` module or `geerlingguy.selinux` role.

---

### Security Considerations

- **Hardcoded Redis password**: `cookbooks/cache/recipes/default.rb` sets `requirepass redis_secure_password_123` directly in the recipe as a plain string. In Ansible, this must be migrated to an **Ansible Vault**-encrypted variable (`vault_redis_password`) referenced in the role's `vars/main.yml` or `group_vars`.
- **Hardcoded PostgreSQL credentials**: `cookbooks/fastapi-tutorial/recipes/default.rb` contains `CREATE USER fastapi WITH PASSWORD 'fastapi_password'` inline in a shell heredoc, and the same password appears in the `.env` file written to disk as `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db`. Both must be replaced with Ansible Vault-encrypted variables.
- **`.env` file permissions**: The `.env` file containing the database URL is written with mode `0644` (world-readable). In Ansible, this should be corrected to `0600` or `0640` with appropriate ownership (not `root:root` if the service runs as a dedicated user).
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk and should be corrected during migration — create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed TLS certificates**: All three virtual hosts use self-signed certificates generated via `openssl req -x509`. The certificates are valid for 365 days with a hardcoded subject (`/C=US/ST=Example/...`). In Ansible, use `community.crypto.x509_certificate` with `selfsigned` provider, or plan for Let's Encrypt integration via `community.crypto.acme_certificate` for non-development environments.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` on `sshd_config`. In Ansible, use `ansible.builtin.lineinfile` or the `devsec.hardening.ssh_hardening` Galaxy role for idempotent SSH configuration management.
- **UFW firewall**: Default-deny with explicit allow for SSH, HTTP, HTTPS. Migrate to `community.general.ufw` module tasks.
- **Fail2ban**: Jail configuration is managed via an ERB template. Translate to a Jinja2 template and deploy with `ansible.builtin.template`. The jail definitions (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch) are well-defined and map directly.
- **Kernel sysctl hardening**: `sysctl-security.conf.erb` disables IPv6, enables SYN cookies, suppresses ICMP redirects, and enables martian logging. Migrate using `ansible.posix.sysctl` module tasks or deploy the file via `ansible.builtin.template` to `/etc/sysctl.d/99-security.conf` with a handler calling `sysctl -p`.
- **No secrets management in use**: The repository uses no Chef encrypted data bags, Chef Vault, or external secrets backends. All credentials are plaintext in recipe files. Ansible Vault must be introduced as part of this migration.

---

### Technical Challenges

- **OS mismatch between Vagrantfile and cookbook metadata**: The Vagrantfile targets `generic/fedora42` but the cookbooks use Ubuntu conventions (`www-data`, `apt-get`, `ufw`). The Ansible roles must target a single, confirmed OS. Resolve this ambiguity before writing any tasks — the package names, service names, and user accounts differ between Fedora and Ubuntu.
- **`redisio` config-mutation hack**: The `ruby_block` in `cache/recipes/default.rb` that strips deprecated Redis directives by post-processing the config file is a code smell indicating the `redisio` cookbook generates an incompatible config for the installed Redis version. In Ansible, this is cleanly solved by rendering the Redis config from a Jinja2 template that only includes supported directives — but the correct set of directives for the target Redis version must be verified first.
- **`lineinfile` custom resource**: `cookbooks/nginx-multisite/resources/lineinfile.rb` defines a custom Chef resource. Its purpose must be reviewed before migration to determine whether it is actually used and what Ansible equivalent is needed (likely `ansible.builtin.lineinfile`).
- **Dynamic site loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create document roots, deploy static files, and generate per-site vhost configs. In Ansible, this maps to a `loop` over a `sites` variable (dict or list), using `ansible.builtin.file`, `ansible.builtin.copy`, and `ansible.builtin.template` tasks. The variable structure from `solo.json` can be directly adapted to Ansible `group_vars`.
- **PostgreSQL provisioning via raw shell**: Database and user creation in `fastapi-tutorial` uses `sudo -u postgres psql -c "..."` shell commands with `|| true` guards for idempotency. In Ansible, replace with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which provide proper idempotency without shell hacks.
- **Git-based application deployment**: The `git` resource clones from a public GitHub repo at `main` branch with `:sync` action (equivalent to `update`). In Ansible, use `ansible.builtin.git` with `update: yes`. Pin to a specific commit SHA or tag for production stability rather than tracking `main`.
- **Berkshelf vendor step**: The provisioning script runs `berks vendor cookbooks` to download external cookbooks into the local path before `chef-solo` runs. In Ansible, there is no equivalent step — Galaxy roles are installed via `ansible-galaxy install -r requirements.yml` and are referenced directly. The `requirements.yml` file must be created as part of the migration.
- **Chef Solo vs. Ansible push model**: Chef Solo is pull-less but still requires a Chef installation on the target. Ansible is fully agentless. The `vagrant-provision.sh` bootstrap script becomes unnecessary; the Vagrantfile should be updated to use `config.vm.provision "ansible_local"` or `"ansible"`.

---

### Migration Order

1. **`nginx-multisite` — Security sub-tasks first** (Low risk, foundational): Begin with the security recipe (`security.rb`) as it has no external cookbook dependencies. Implement UFW, Fail2ban, SSH hardening, and sysctl as standalone Ansible tasks or a `security` role. This establishes the Ansible Vault pattern for any future secrets and validates the target OS.
2. **`nginx-multisite` — Nginx core and sites** (Moderate complexity): Translate `nginx.rb`, `ssl.rb`, and `sites.rb` into Ansible tasks using `ansible.builtin.package`, `ansible.builtin.template` (Jinja2 conversions of ERB templates), `ansible.builtin.file`, and `ansible.builtin.copy`. Implement the site loop using `loop` over a `nginx_sites` variable derived from `solo.json`. Validate all three virtual hosts with self-signed certs.
3. **`cache`** (Moderate complexity — external dependency replacement): Replace `memcached` community cookbook with direct package/service tasks. Replace `redisio` with a clean Jinja2-templated Redis config (eliminating the hack). Migrate the Redis password to Ansible Vault. Consider `geerlingguy.redis` as a Galaxy role baseline.
4. **`fastapi-tutorial`** (Highest complexity — multiple concerns): Migrate last due to the most moving parts: Python venv, git deploy, PostgreSQL provisioning, systemd service, and `.env` secrets. Use `community.postgresql.*` modules for database work. Introduce a dedicated `fastapi` system user. Encrypt all credentials with Ansible Vault. Pin the Git revision.

---

### Assumptions

1. **Target OS is Ubuntu (likely 22.04 LTS)**, not Fedora 42 as declared in the Vagrantfile, based on `www-data` user references, `apt-get` in the provisioning script, and `ufw`/`fail2ban` package availability. This must be confirmed with the repository owner before migration begins.
2. **Chef Solo / single-node deployment**: There is no Chef Server, no roles, no environments, and no data bags. The entire stack runs on one VM. The Ansible equivalent is a single playbook targeting one host.
3. **Development/lab environment**: Self-signed certificates, hardcoded passwords, and a service running as `root` indicate this is not a production deployment. The migration plan assumes these will be corrected during migration, but the scope of those corrections should be agreed upon with the team.
4. **The `ssl_certificate` community cookbook** (present in `Policyfile.lock.json`) is not directly invoked by any local recipe — SSL cert generation is handled inline in `ssl.rb` via `openssl` shell commands. It may be a transitive dependency or a leftover. No Ansible equivalent is needed unless further investigation reveals it is used.
5. **The `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md` file** may contain migration-specific rules or constraints that could affect role structure, naming conventions, or variable organization. Its contents must be reviewed before finalizing the Ansible role layout.
6. **The `project-plan.md` file** may contain architectural decisions or constraints relevant to the migration. It should be reviewed for context.
7. **The `lineinfile` custom resource** in `cookbooks/nginx-multisite/resources/lineinfile.rb` has not been confirmed as actively used in any recipe. If it is used, it maps to `ansible.builtin.lineinfile`. If unused, it can be dropped.
8. **No CI/CD pipeline** is present in this repository. The migration plan does not include pipeline integration, but adding an Ansible-based CI pipeline (e.g., GitHub Actions with `ansible-lint` and Molecule testing) is strongly recommended post-migration.
9. **Redis is single-instance with no replication**. The `replicaservestaledata: nil` attribute in the `cache` recipe and the hack removing `replica-*` directives confirm no replication is configured. The Ansible Redis config should be a standalone single-instance setup.
10. **The FastAPI application source** (`https://github.com/dibanez/fastapi_tutorial.git`) is a public repository. If this changes to a private repository before or during migration, SSH key management or token-based authentication will need to be added to the Ansible role.
