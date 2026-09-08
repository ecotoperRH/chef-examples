# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a multi-service web stack on a single Vagrant-managed VM (Fedora 42 / libvirt). The policy (`nginx-multisite-policy`) runs three local cookbooks in sequence — `nginx-multisite`, `cache`, and `fastapi-tutorial` — backed by five external Chef Supermarket dependencies. The overall migration scope is **moderate**: three cookbooks of low-to-medium complexity, a well-understood dependency graph, and a clear Vagrant-based development workflow that maps naturally to Ansible's agentless model.

**Estimated migration effort:** 3–5 engineer-days for a competent Ansible practitioner, including role authoring, secret remediation, and Molecule test coverage.

**Key risks:** hardcoded credentials in two cookbooks, self-signed SSL certificate generation logic, a workaround `ruby_block` patching a Redis config file, and a `sed`-based sshd_config mutation that should be replaced with Ansible's `lineinfile` or a managed template.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, plus **5 external Supermarket cookbook dependencies** that must be replaced with native Ansible modules or community roles.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file reads.

---

- **nginx-multisite**
  - **Description:** Nginx multi-site web server with SSL termination, security hardening, and firewall configuration. Orchestrates four sub-recipes: `security` (fail2ban, UFW, SSH hardening, sysctl tuning), `nginx` (package install, nginx.conf template, per-site document roots and static files), `ssl` (self-signed certificate generation via `openssl req`), and `sites` (per-vhost `sites-available` config + symlink to `sites-enabled`). Serves three internal subdomains: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, all SSL-enabled.
  - **Path:** `cookbooks/nginx-multisite`
  - **Technology:** Chef
  - **Key Features:** ERB-templated `nginx.conf` and per-site `site.conf`, fail2ban `jail.local` template, UFW rule management via shell `execute` resources, sysctl security tuning (`/etc/sysctl.d/99-security.conf`), SSH root-login and password-auth hardening via `sed`, self-signed RSA-2048 certificates (365-day), `www-data` document root ownership, sites-enabled symlink management, default site removal.

---

- **cache**
  - **Description:** Caching layer that installs and configures both Memcached and Redis on the same host. Redis is configured with password authentication and a `requirepass` directive; a `ruby_block` post-processes the generated Redis config file to strip deprecated replica-related directives that the `redisio` cookbook emits for older Redis versions.
  - **Path:** `cookbooks/cache`
  - **Technology:** Chef
  - **Key Features:** Delegates Memcached setup to the `memcached` (~> 6.0) Supermarket cookbook; delegates Redis setup to `redisio` (7.2.4) with `redisio::enable`; creates `/var/log/redis` directory; hardcoded Redis password (`redis_secure_password_123`); `ruby_block` hack to remove deprecated config keys from `/etc/redis/6379.conf`.

---

- **fastapi-tutorial**
  - **Description:** Full-stack Python application deployment that installs a FastAPI application from a public GitHub repository, sets up a Python virtual environment, configures PostgreSQL as the backing database, writes a `.env` file with database credentials, and registers a systemd service (`fastapi-tutorial.service`) to run the app via `uvicorn` on port 8000.
  - **Path:** `cookbooks/fastapi-tutorial`
  - **Technology:** Chef
  - **Key Features:** Installs `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`; clones `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`); creates venv at `/opt/fastapi-tutorial/venv`; installs Python deps from `requirements.txt`; creates PostgreSQL user `fastapi` with hardcoded password `fastapi_password` and database `fastapi_db`; writes `/opt/fastapi-tutorial/.env` with `DATABASE_URL` containing the plaintext password; systemd unit runs as `root`; `systemctl daemon-reload` triggered on service file change.

---

### Infrastructure Files

- **`Policyfile.rb`** — Chef Policyfile defining the `nginx-multisite-policy` run list and pinning all cookbook versions. Maps directly to an Ansible playbook with ordered roles. Must be retired once migration is complete.
- **`Policyfile.lock.json`** — Locked dependency graph (8 cookbooks, fully resolved). Serves as the authoritative version reference when selecting equivalent Ansible Galaxy roles or writing native tasks.
- **`Berksfile`** — Berkshelf dependency file used by `vagrant-provision.sh` to vendor external cookbooks. Superseded by `Policyfile.lock.json` for version authority; both can be retired post-migration.
- **`solo.json`** — Chef Solo node attributes (run list + nginx site map + security flags). Translates to Ansible `group_vars` or `host_vars` YAML files.
- **`solo.rb`** — Chef Solo configuration (cache path, cookbook path). No Ansible equivalent needed; retire after migration.
- **`Vagrantfile`** — Vagrant VM definition: `generic/fedora42`, libvirt provider, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443. Retain and update to use `ansible_local` or `ansible` provisioner in place of the shell provisioner.
- **`vagrant-provision.sh`** — Bootstrap script that installs Chef, runs Berkshelf to vendor cookbooks, then executes `chef-solo`. Replace with a direct `ansible-playbook` invocation or Vagrant's built-in Ansible provisioner.
- **`project-plan.md`** — Existing project planning document. Review for any additional context before archiving.
- **`modules/nginx/`** — A partially completed Ansible role for Nginx already exists in this repository (under `modules/nginx/ansible/roles/nginx/`). It includes defaults, handlers, tasks, templates, vars, meta, and Molecule tests. This work-in-progress should be reviewed and extended rather than started from scratch.

---

### Target Details

- **Operating System:** Ubuntu 18.04+ / CentOS 7+ per `metadata.rb` `supports` declarations; the Vagrant box is `generic/fedora42` (Fedora 42). The `www-data` user and `ufw`/`fail2ban` package names are Debian/Ubuntu-specific — the migration must account for the divergence between the declared OS support and the actual Fedora test environment (e.g., `firewalld` instead of `ufw`, `nginx` user instead of `www-data` on RHEL-family).
- **Virtual Machine Technology:** VirtualBox-compatible Vagrant box provisioned via **libvirt** (KVM). The `Vagrantfile` explicitly uses the `libvirt` provider.
- **Cloud Platform:** Not specified. No cloud-provider tooling, metadata endpoints, or cloud-init configurations are present.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1)** — Supermarket cookbook that installs and manages Nginx. Replace with the `ansible.builtin.package` module (`nginx`) plus the in-repo partial role at `modules/nginx/ansible/roles/nginx/`. Alternatively, adopt `geerlingguy.nginx` from Ansible Galaxy.
- **memcached (6.1.0)** — Supermarket cookbook for Memcached installation and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service` tasks, or `geerlingguy.memcached` Galaxy role.
- **redisio (7.2.4)** — Supermarket cookbook for Redis installation with per-instance config file generation. Replace with `ansible.builtin.package` + `ansible.builtin.template` for `/etc/redis/6379.conf`, or `geerlingguy.redis` Galaxy role. The `ruby_block` config-patching hack must be replaced with a clean Ansible template that never emits the deprecated directives in the first place.
- **ssl_certificate (2.1.0)** — Supermarket cookbook for SSL certificate management (locked in `Policyfile.lock.json`, commented out in `Berksfile`). Replace with `community.crypto.x509_certificate` + `community.crypto.openssl_privatekey` Ansible modules for self-signed certs, or integrate Let's Encrypt via `community.crypto.acme_certificate`.
- **selinux (6.2.4)** — Pulled in transitively by `redisio`. Replace with `ansible.posix.selinux` module if SELinux management is required on target hosts.

---

### Security Considerations

- **Hardcoded Redis password:** The string `redis_secure_password_123` is embedded in plaintext in `cookbooks/cache/recipes/default.rb`. Must be extracted to an Ansible Vault-encrypted variable before migration.
- **Hardcoded PostgreSQL/FastAPI credentials:** The password `fastapi_password` appears in three places in `cookbooks/fastapi-tutorial/recipes/default.rb`: the `psql` CREATE USER command, the `DATABASE_URL` in the `.env` file, and the systemd environment. All three must be replaced with a single Vault-encrypted variable rendered via `ansible.builtin.template`.
- **Plaintext `.env` file:** `/opt/fastapi-tutorial/.env` is written with mode `0644` and owned by `root:root`, exposing `DATABASE_URL` (including the password) to all local users. The Ansible equivalent should use mode `0600` and a dedicated application user rather than `root`.
- **FastAPI service runs as root:** The systemd unit sets `User=root`. This is a privilege escalation risk and should be corrected during migration by creating a dedicated `fastapi` system user.
- **Self-signed SSL certificates:** `ssl.rb` generates self-signed certificates using `openssl req` with a hardcoded subject string. The Ansible migration should use `community.crypto` modules for idempotent certificate management and consider a path to CA-signed or Let's Encrypt certificates for non-development environments.
- **SSH hardening via `sed`:** `security.rb` mutates `/etc/ssh/sshd_config` with `sed` commands. Replace with `ansible.builtin.lineinfile` or a fully managed `sshd_config` template to ensure idempotency and auditability.
- **UFW firewall rules via shell `execute`:** Firewall state is managed through raw `ufw` shell commands with `not_if` guards. Replace with `community.general.ufw` module tasks for declarative, idempotent firewall management.
- **SSL private key permissions:** `ssl.rb` sets the private key to mode `640`, owned `root:ssl-cert`. Replicate this exactly in the Ansible `community.crypto.openssl_privatekey` task to avoid inadvertent key exposure.
- **Vault/secrets inventory by module:**
  - `cache`: 1 credential — Redis `requirepass` password.
  - `fastapi-tutorial`: 2 credentials — PostgreSQL user password (used in `psql` DDL, `.env` file, and `DATABASE_URL`); GitHub repository URL (public, no credential, but the `revision: main` floating ref is a supply-chain risk).
  - `nginx-multisite`: No hardcoded credentials; SSL subject fields use placeholder values (`Example Org`, `admin@example.com`) that should be parameterised.

---

### Technical Challenges

- **OS family divergence:** The cookbooks declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7, but the Vagrant box is Fedora 42. Package names (`ufw` vs `firewalld`), service names (`ssh` vs `sshd`), and the `www-data` user do not exist on Fedora/RHEL. The Ansible roles must use `ansible_os_family` / `ansible_distribution` conditionals or separate variable files to handle both families correctly.
- **`ruby_block` config-patching hack in `cache`:** The Redis cookbook generates a config file with deprecated directives, which are then stripped by a `ruby_block`. In Ansible, this must be solved at the template level — either by owning the full `/etc/redis/6379.conf` template or by using `ansible.builtin.lineinfile` with `regexp`/`state: absent` to remove the offending lines. The root cause (outdated `redisio` cookbook) should be addressed by pinning to a compatible Redis version.
- **Floating Git revision in `fastapi-tutorial`:** The cookbook clones `revision: main`, meaning each Chef run may pull a different application version. The Ansible equivalent (`ansible.builtin.git`) should pin to a specific commit SHA or tag for reproducibility.
- **Idempotency of PostgreSQL DDL:** The `create_db_user` execute resource uses `|| true` to suppress errors on re-runs. Ansible's `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules handle idempotency natively and should replace the raw `psql` shell commands.
- **Partial Ansible role already exists:** `modules/nginx/ansible/roles/nginx/` contains an in-progress Ansible role with Molecule tests. Before authoring new roles, this existing work must be audited for completeness and compatibility with the full `nginx-multisite` cookbook feature set (security hardening, SSL, multi-site config).
- **Vagrant provisioner replacement:** `vagrant-provision.sh` installs Chef and Berkshelf at runtime. Replacing it with Vagrant's native `ansible_local` provisioner (which auto-installs Ansible in the VM) or the `ansible` provisioner (which runs Ansible from the host) is straightforward but requires updating the `Vagrantfile`.
- **Memcached configuration scope:** The `cache` cookbook delegates entirely to the `memcached` Supermarket cookbook without setting any custom attributes. The Ansible migration must determine whether default Memcached settings are intentional or whether attributes were simply never tuned.

---

### Migration Order

1. **`nginx-multisite`** — Highest value, most complete existing Ansible work (`modules/nginx/ansible/roles/nginx/`). Start here to validate the Vagrant + Ansible workflow end-to-end. Delivers the core web server, security hardening, and SSL infrastructure that the other cookbooks depend on for a working environment. Low credential risk.

2. **`cache`** — Self-contained caching layer with two well-understood services (Memcached, Redis). Migrate after Nginx so the base OS and firewall are already in place. Requires Vault secret creation for the Redis password and resolution of the `ruby_block` config-patching issue before the role can be considered production-ready.

3. **`fastapi-tutorial`** — Most complex cookbook: multi-step application deployment, database provisioning, systemd service, and the highest concentration of security issues (hardcoded credentials, root service user, floating Git ref). Migrate last, after the platform roles are stable, and use this cookbook's migration as the forcing function for establishing the Ansible Vault workflow and a proper application user.

---

### Assumptions

1. **Target Ansible version:** Assumed to be Ansible Core 2.15+ (compatible with `ansible.builtin`, `community.general`, `community.crypto`, `community.postgresql`, and `ansible.posix` collections). The exact version has not been specified.
2. **Inventory structure:** It is assumed that a single host (the Vagrant VM) is the initial target. A production inventory with host groups has not been defined; one will need to be created.
3. **Vault workflow:** No Ansible Vault setup exists yet. It is assumed the team will adopt Vault-encrypted `group_vars` files for all secrets identified above. The choice of vault password storage (vault password file, `ansible-vault`, HashiCorp Vault lookup) is undecided.
4. **OS target for production:** The `metadata.rb` files declare Ubuntu ≥ 18.04 and CentOS ≥ 7 support, but the only tested environment is Fedora 42 via Vagrant. It is unclear whether the production target is Ubuntu, CentOS/RHEL, or Fedora. The migration plan assumes **Red Hat Enterprise Linux 9** as the production baseline unless clarified, with Ubuntu 22.04 as a secondary target.
5. **SSL certificate strategy:** The current implementation generates self-signed certificates. It is assumed this is acceptable for the development/test environment but that a CA-signed or Let's Encrypt certificate strategy will be defined for production. The migration plan does not prescribe a specific CA.
6. **Redis version compatibility:** The `ruby_block` hack exists because `redisio 7.2.4` emits deprecated directives for newer Redis versions. It is assumed the target Redis version is ≥ 6.0 (where those directives were removed/renamed). The Ansible role should pin a specific Redis package version.
7. **FastAPI application ownership:** The GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` is assumed to be under the team's control or at minimum a stable, trusted source. The floating `main` branch reference is treated as a known risk.
8. **Memcached default configuration:** No custom Memcached attributes are set in the `cache` cookbook. It is assumed default Memcached settings (11211/tcp, 64 MB memory, localhost bind) are intentional for this deployment.
9. **Single-node deployment:** All three cookbooks run on the same VM. The Ansible migration will initially target a single-host playbook. Horizontal scaling or role separation across multiple hosts is out of scope for this migration.
10. **The existing `modules/nginx/` Ansible role** is assumed to be a work-in-progress from a prior migration attempt and not yet production-ready. It will be reviewed and extended rather than replaced wholesale.
11. **`ssl_certificate` cookbook status:** This dependency is locked in `Policyfile.lock.json` but commented out in `Berksfile`, suggesting it was evaluated and deprioritised. It is assumed self-signed certificate generation (currently in `ssl.rb`) is the intended approach and that the `ssl_certificate` cookbook is not actively used.
