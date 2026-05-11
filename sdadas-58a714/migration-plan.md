# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is developed and tested locally via Vagrant (libvirt/Fedora 42) and driven by a `Policyfile.rb` run-list of three local cookbooks.

**Migration scope:** 3 local Chef cookbooks, 5 external Supermarket cookbook dependencies, 8 locked dependency versions, 5 ERB templates, 1 custom Chef resource, and 3 static site assets.

**Complexity assessment:** Medium. The cookbooks follow conventional Chef patterns (package/template/service resources, node attributes, `include_recipe` composition) that map cleanly to Ansible tasks, roles, and Jinja2 templates. The main friction points are the Redis config post-processing hack, the custom `lineinfile` resource, cross-platform package-name differences, and hardcoded credentials that must be vaulted.

**Timeline estimate:** 3–4 weeks for a full migration including testing:
- Week 1 – Security hardening role + Nginx multisite role (foundation)
- Week 2 – Cache role (Memcached + Redis)
- Week 3 – FastAPI application role (Python, PostgreSQL, systemd)
- Week 4 – Integration testing, Vagrant/CI validation, documentation

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with multiple SSL-enabled virtual hosts (test.cluster.local, ci.cluster.local, status.cluster.local), self-signed TLS certificate generation, per-site document roots with static HTML content, and a comprehensive security hardening layer (UFW firewall, Fail2Ban intrusion prevention, SSH hardening, and kernel sysctl tuning)
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Multi-vhost Nginx configuration via ERB templates; HTTP→HTTPS redirect; TLS 1.2/1.3 with strong cipher suites; HSTS, X-Frame-Options, CSP, and other security headers; UFW default-deny with SSH/HTTP/HTTPS allow rules; Fail2Ban jails for sshd, nginx-http-auth, nginx-limit-req, and nginx-botsearch; SSH root login and password authentication disabled; kernel-level IP spoofing protection, ICMP hardening, and TCP SYN-cookie flood protection via sysctl; custom `lineinfile` Chef resource for idempotent file-line management; per-site static `index.html` files served from `files/default/{test,ci,status}/`

- **cache**:
    - Description: Caching services layer that installs and configures both Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication, a dedicated log directory, and a post-processing Ruby block that strips deprecated Redis replica configuration directives from the generated config file
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached installation delegated to `memcached` community cookbook; Redis on port 6379 with `requirepass` authentication; `/var/log/redis` directory with correct ownership; post-processing `ruby_block` to remove deprecated `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` directives from `/etc/redis/6379.conf`; `redisio::enable` recipe to manage the Redis systemd service

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, running inside a Python virtual environment, backed by a locally provisioned PostgreSQL database, and managed as a systemd service
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: System package installation (python3, python3-pip, python3-venv, git, postgresql, postgresql-contrib, libpq-dev); Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch into `/opt/fastapi-tutorial`; Python venv creation and `pip install -r requirements.txt`; PostgreSQL service enable/start; PostgreSQL user `fastapi` and database `fastapi_db` creation with full privileges; `.env` file generation at `/opt/fastapi-tutorial/.env` containing `DATABASE_URL` with embedded plaintext credentials; systemd unit file for `fastapi-tutorial.service` running `uvicorn app.main:app --host 0.0.0.0 --port 8000` as root; `systemctl daemon-reload` and service enable/start

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring the three local cookbooks and four external Supermarket dependencies (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1` — note `ssl_certificate` is commented out in Berksfile but present in Policyfile). Must be replaced by Ansible Galaxy `requirements.yml`.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy` and the ordered run-list `nginx-multisite::default → cache::default → fastapi-tutorial::default`. The run-list order encodes a dependency: security/nginx must be ready before cache, and cache before the application. This ordering must be preserved in Ansible playbook task ordering or role dependencies.
- `Policyfile.lock.json`: Pinned dependency graph locking 8 cookbooks (cache 1.0.0, fastapi-tutorial 1.0.0, memcached 6.1.0, nginx 12.3.1, nginx-multisite 1.0.0, redisio 7.2.4, selinux 6.2.4, ssl_certificate 2.1.0). Provides the authoritative version reference for selecting equivalent Ansible Galaxy roles.
- `solo.json`: Chef Solo node JSON supplying run-list and node attribute overrides. Defines three virtual-host entries (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) each with `document_root` and `ssl_enabled: true`, SSL certificate/key paths, and security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth: false`). These values become Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing `file_cache_path` to `/var/chef-solo` and `cookbook_path` to `/chef-repo/cookbooks`. No migration artifact needed; replaced by Ansible inventory and `ansible.cfg`.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, forwarded ports 80→8080 and 443→8443, rsync of the repo to `/chef-repo`. The network and resource settings inform the Ansible inventory `host_vars` and the target VM specification.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and then invokes `chef-solo -c solo.rb -j solo.json`. In the Ansible world this is replaced by `ansible-playbook` invocation; the script's `apt-get update` and `build-essential` install steps should be captured in a pre-tasks block.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `Policyfile.lock.json` copy, `generated-project-metadata.json` (structured cookbook inventory), and a prior `migration-plan.md` draft. These are tooling artifacts and do not need to be migrated.

---

### Target Details

- **Operating System**: Fedora 42 is the active development target (specified in `Vagrantfile` as `generic/fedora42`). Cookbook `metadata.rb` files declare support for Ubuntu ≥ 18.04 and CentOS ≥ 7.0. The provisioning script uses `apt-get`, indicating the Vagrant box may actually be Debian-family despite the Fedora box name, or the script is partially incorrect. Ansible playbooks should use the `ansible_os_family` fact to branch package names (e.g., `nginx` vs `nginx`, `ufw` vs `firewalld`, `ssh` vs `sshd` service name). Default to **Red Hat Enterprise Linux 9 / Fedora** for production targets.
- **Virtual Machine Technology**: libvirt / KVM (explicitly set in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role, or implement directly using `ansible.builtin.package`, `ansible.builtin.template`, and `ansible.builtin.service` modules. The ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) convert directly to Jinja2 with minimal syntax changes (`<%= @var %>` → `{{ var }}`).
- **memcached (6.1.0, Chef Supermarket)**: Replace with `geerlingguy.memcached` Galaxy role or native `package`/`service` tasks. The community cookbook performs a straightforward install-and-enable; no complex configuration is present in the local cookbook.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `geerlingguy.redis` Galaxy role or native tasks. The local cookbook overrides `node['redisio']['servers']` to set port and `requirepass`; these map to role variables. The post-processing `ruby_block` that strips deprecated directives must be replaced with an Ansible `ansible.builtin.lineinfile` (with `state: absent` and `regexp`) or a fully managed `template` task that never emits those directives in the first place.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection. The current Chef recipe already implements self-signed cert generation via raw `openssl req` shell commands, so a direct `ansible.builtin.command` wrapper is also viable as an interim step.
- **selinux (6.2.4, Chef Supermarket — transitive via redisio)**: Replace with `ansible.posix.selinux` module or the `geerlingguy.selinux` role. Evaluate whether SELinux permissive/enforcing mode needs to be set for Redis on the target OS.

---

### Security Considerations

- **Hardcoded Redis password** (`cookbooks/cache/recipes/default.rb`, line: `'requirepass' => 'redis_secure_password_123'`): This plaintext credential must be extracted and stored in **Ansible Vault**. Create a vaulted variable `redis_requirepass` in `group_vars/all/vault.yml`. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`cookbooks/fastapi-tutorial/recipes/default.rb`): The PostgreSQL user password `'fastapi_password'` appears in both the `psql` command and the `.env` file content inline in the recipe. Both occurrences must be replaced with a vaulted variable `fastapi_db_password`. **2 credential occurrences detected (DB creation command + .env file template).**
- **`.env` file permissions**: The `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644` and owned by `root:root`, meaning the database URL (including password) is world-readable. In Ansible, set mode to `0600` and consider running the application as a dedicated non-root user.
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk. The Ansible role should create a dedicated `fastapi` system user and run the service under that account.
- **Self-signed TLS certificates**: The `ssl.rb` recipe generates self-signed certificates via `openssl req` with a hardcoded subject (`/C=US/ST=Example/...`). These are development-only. The Ansible migration should parameterise the subject fields and provide a clear path to swap in CA-signed or Let's Encrypt certificates for production. Certificate files land in `/etc/ssl/certs` (mode 0755) and `/etc/ssl/private` (mode 0710, group `ssl-cert`). Replicate these permissions exactly in Ansible.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are enforced via `sed` commands in `security.rb`. Replace with `ansible.builtin.lineinfile` tasks targeting `/etc/ssh/sshd_config`, or use the `devsec.hardening.ssh_hardening` role for a more comprehensive baseline.
- **UFW firewall**: Default-deny with SSH/HTTP/HTTPS allow rules. Use the `community.general.ufw` module. On RHEL/Fedora targets, UFW is not available; use `ansible.posix.firewalld` instead and gate on `ansible_os_family`.
- **Fail2Ban**: Five jails configured (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch, plus DEFAULT). The `fail2ban.jail.local.erb` template converts directly to a Jinja2 template. Use `ansible.builtin.template` + `ansible.builtin.service` handler.
- **Kernel sysctl hardening**: 18 sysctl parameters covering IP spoofing, ICMP redirect, source routing, martian logging, ICMP echo suppression, IPv6 disable, and TCP SYN-cookie protection. Use `ansible.posix.sysctl` module with `sysctl_file: /etc/sysctl.d/99-security.conf` and `reload: yes`.
- **No Chef encrypted data bags or Chef Vault usage detected.** All secrets are currently stored as plaintext node attributes or inline recipe strings.

---

### Technical Challenges

- **Redis config post-processing hack**: `cache/recipes/default.rb` uses a `ruby_block` to read, regex-strip, and rewrite `/etc/redis/6379.conf` after `redisio` generates it. This pattern has no direct Ansible equivalent when delegating to a Galaxy role. **Mitigation**: Either (a) use a fully managed Jinja2 template for `redis.conf` that never emits the deprecated directives, bypassing the Galaxy role's template entirely, or (b) use `ansible.builtin.lineinfile` with `state: absent` and `regexp` for each of the five deprecated directive patterns as post-tasks.
- **Custom `lineinfile` Chef resource** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): This custom resource replicates functionality of Ansible's built-in `ansible.builtin.lineinfile` module almost exactly (match-and-replace or append, with backup). It can be dropped entirely in Ansible; all call sites should be replaced with `ansible.builtin.lineinfile` tasks.
- **Cross-platform package and service name divergence**: The `vagrant-provision.sh` uses `apt-get` (Debian/Ubuntu), but the Vagrantfile targets `generic/fedora42` (RPM-based). Cookbook metadata supports both Ubuntu ≥ 18.04 and CentOS ≥ 7. Ansible playbooks must use `ansible_pkg_mgr` or `ansible_os_family` conditionals, or rely on the `package` module's OS-agnostic behaviour. Key differences: `ufw` (Debian) vs `firewalld` (RHEL); `ssh` service (Debian) vs `sshd` (RHEL); `www-data` user (Debian) vs `nginx` user (RHEL).
- **Document root path inconsistency**: `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, but `solo.json` (both root and `.myprj/`) overrides them to `/var/www/{test,ci,status}.cluster.local`. The static HTML files reference `/opt/server/` paths in their content. This inconsistency must be resolved before migration; a single canonical path should be chosen and the HTML content updated accordingly.
- **Git-based application deployment**: `fastapi-tutorial` uses the Chef `git` resource to clone/sync from GitHub. In Ansible, `ansible.builtin.git` is the direct equivalent, but idempotency requires careful handling of `update: yes` vs `force` when local changes exist. The `main` branch reference should be pinned to a specific commit SHA or tag for reproducible deployments.
- **PostgreSQL provisioning via raw psql commands**: The recipe uses `sudo -u postgres psql -c "..."` shell commands with `|| true` to suppress errors on re-runs. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules from the `community.postgresql` collection for idempotent, declarative database provisioning.
- **Nginx `sites-available`/`sites-enabled` symlink pattern**: This is a Debian/Ubuntu convention. On RHEL/Fedora, Nginx uses `/etc/nginx/conf.d/`. The `sites.rb` recipe creates symlinks; Ansible must either replicate the symlink pattern (using `ansible.builtin.file` with `state: link`) or adapt to `conf.d` drop-ins depending on the target OS.
- **Service notification ordering**: Chef's `:delayed` notification batches service reloads to the end of the Chef run. Ansible handlers provide equivalent behaviour but must be explicitly flushed with `meta: flush_handlers` at appropriate points in the play to maintain the same ordering guarantees.
- **Vagrant provisioning script uses `apt-get update` unconditionally**: This is a side-effect of the bootstrap script. In Ansible, use `ansible.builtin.apt` with `update_cache: yes` and `cache_valid_time` to avoid unnecessary updates on every run.

---

### Migration Order

1. **Security hardening** (extracted from `nginx-multisite::security`) — Low risk, self-contained, no external dependencies. Establishes the security baseline that all other roles depend on. Delivers immediate value. Maps to an Ansible `security` role with tasks for UFW/firewalld, Fail2Ban, SSH config, and sysctl.

2. **nginx-multisite** (core web server + virtual hosts + SSL) — Moderate complexity. Depends on the security role being applied first (firewall ports must be open). The ERB→Jinja2 template conversion is mechanical. Self-signed cert generation via `community.crypto` modules is well-supported. Delivers the three virtual hosts.

3. **cache** (Memcached + Redis) — Low-to-moderate complexity. Independent of the application layer. The Redis config post-processing hack is the primary challenge. Resolving it cleanly (managed template vs. lineinfile cleanup) should be done before the application role that may depend on Redis being correctly configured.

4. **fastapi-tutorial** (Python app + PostgreSQL) — Highest complexity. Depends on PostgreSQL being available (installed as part of this cookbook but could be split). Requires credential vaulting, service user creation, Git deployment, venv management, and systemd unit templating. Should be migrated last after the infrastructure foundation is stable.

---

### Assumptions

1. **Target OS for production is RHEL 9 / Fedora** based on the Vagrantfile (`generic/fedora42`) and the presence of the `selinux` transitive dependency, despite the provisioning script using `apt-get`. Ansible roles must handle both OS families via conditionals, but RHEL/Fedora is the primary target.
2. **Self-signed certificates are acceptable for the migrated development environment.** A separate production certificate strategy (Let's Encrypt, internal CA, or pre-provisioned certs) is out of scope for this migration but should be documented as a follow-up task.
3. **The FastAPI GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`) will remain publicly accessible** during and after migration. If the repository becomes private, Ansible will need SSH key or token-based Git authentication.
4. **Redis does not require clustering, Sentinel, or persistence** beyond what the current single-instance `redisio` configuration provides. The migration targets a standalone Redis instance.
5. **Memcached requires no authentication** (the community cookbook installs and starts it with defaults). If the application requires SASL authentication, this is an undocumented requirement that must be clarified before migration.
6. **The three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) serve only static HTML** in the current configuration. No dynamic proxying, upstream backends, or application routing is configured in Nginx for these sites. The FastAPI application runs on port 8000 and is not yet proxied through Nginx.
7. **The document root path discrepancy** between `attributes/default.rb` (`/opt/server/{test,ci,status}`) and `solo.json` (`/var/www/{site}.cluster.local`) will be resolved in favour of the `solo.json` override values (`/var/www/`) as these represent the runtime-applied configuration. The static HTML file content referencing `/opt/server/` paths is cosmetic and will be updated.
8. **Ansible Vault will be used for all secrets.** The two identified plaintext credentials (Redis password, PostgreSQL password) will be moved to a vaulted `group_vars/all/vault.yml` file before any playbook is committed to version control.
9. **The `www-data` user/group** referenced in `nginx.rb` for document root ownership is Debian-specific. On RHEL/Fedora, the Nginx worker runs as the `nginx` user. The Ansible role will use a variable `nginx_user` defaulting to `nginx` on RHEL and `www-data` on Debian.
10. **No Chef Server, Chef Automate, or Policyfile push workflow is in use.** The stack runs exclusively via `chef-solo`, making the migration straightforward — there is no Chef Server API, data bags, environments, or roles infrastructure to replicate.
11. **The `ssl_certificate` community cookbook** is commented out in `Berksfile` but present and locked in `Policyfile.lock.json`. It is not directly `include_recipe`'d in any local cookbook recipe. It is assumed to be an unused/vestigial dependency and will not be migrated.
12. **The custom `lineinfile` Chef resource** in `nginx-multisite/resources/lineinfile.rb` is not called from any recipe in this repository (no `lineinfile` resource calls were found in the recipes). It appears to be a utility resource included for potential use. It will be dropped in the Ansible migration with a note that `ansible.builtin.lineinfile` provides equivalent functionality natively.
13. **IPv6 is intentionally disabled** via sysctl (`net.ipv6.conf.all.disable_ipv6 = 1`). This will be preserved in the Ansible `sysctl` tasks unless the target environment requires IPv6.
14. **The FastAPI application is run as `root`** in the current Chef configuration. The Ansible migration will introduce a dedicated `fastapi` system user as a security improvement. This is a deliberate deviation from the source configuration and must be validated against the application's file permission requirements.
