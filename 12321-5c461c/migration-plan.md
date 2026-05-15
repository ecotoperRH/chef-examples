# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack (policy name: `nginx-multisite-policy`) that provisions a multi-service Linux server. The stack is composed of **3 local cookbooks** and **5 external Supermarket dependencies**, orchestrated via a `Policyfile.rb` and exercised locally through a Vagrant/libvirt development environment running **Fedora 42**.

The three cookbooks cover: (1) a hardened Nginx reverse proxy with three SSL-enabled virtual hosts, (2) a dual-caching layer using Memcached and Redis, and (3) a Python FastAPI application backed by PostgreSQL. The run-list order is `nginx-multisite → cache → fastapi-tutorial`.

**Complexity assessment: Medium.** All three cookbooks use standard Chef resources (package, template, service, execute, directory, git) that map cleanly to Ansible built-in modules. The main friction points are a custom `lineinfile` LWRP, a `ruby_block` hack for Redis config post-processing, hardcoded credentials in recipe code, and self-signed certificate generation via shell commands. No encrypted data bags or Chef Vault usage was detected; credentials are stored in plain text inside recipe files and a `solo.json` node attribute file.

**Estimated migration timeline: 3–4 weeks** for a single engineer, including testing against the existing Vagrant environment.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server with three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), a global security hardening layer (fail2ban, UFW firewall, kernel sysctl tuning), SSH hardening, and self-signed TLS certificate generation via OpenSSL CLI
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - Nginx installation from OS package manager with a fully templated `nginx.conf` (gzip, keepalive, logging)
        - Per-site `sites-available/sites-enabled` virtual host management with HTTP→HTTPS redirect, TLS 1.2/1.3 enforcement, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy)
        - Global `security.conf` snippet: rate-limiting zones (`login`, `api`), buffer overflow mitigations, SSL session cache
        - Self-signed RSA-2048 certificate generation per site (365-day validity, skipped if cert+key already exist)
        - `ssl-cert` group creation; private keys owned `root:ssl-cert` with mode `0710`
        - fail2ban with jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`; ban time 3600 s, max retry 3
        - UFW rules: default deny, allow SSH/HTTP/HTTPS; force-enabled
        - sysctl hardening: IP spoofing protection, ICMP redirect rejection, source routing disabled, martian logging, ICMP echo ignore, TCP SYN-cookie flood protection, IPv6 disabled
        - SSH daemon hardening: `PermitRootLogin no`, `PasswordAuthentication no` (driven by node attributes)
        - Custom `lineinfile` LWRP (re-implements Ansible's `lineinfile` in Ruby) for in-place file editing with timestamped backups
        - Static HTML content files for each virtual host (`ci/index.html`, `status/index.html`, `test/index.html`) deployed via `cookbook_file`

- **cache**:
    - Description: Dual in-memory caching layer that installs and configures Memcached (via the community `memcached` cookbook) and Redis (via the community `redisio` cookbook) with password authentication and a post-install config-file sanitisation workaround
    - Path: `cookbooks/cache`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - Memcached installation and service management delegated entirely to the `memcached` community cookbook (v6.1.0)
        - Redis on port 6379 with `requirepass redis_secure_password_123` (hardcoded in recipe)
        - `/var/log/redis` directory created with `redis:redis` ownership, mode `0755`
        - `ruby_block "fix_redis_config"` post-processes `/etc/redis/6379.conf` after `redisio` writes it, stripping five deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that cause Redis startup failures on newer versions
        - `redisio::enable` recipe called to create and enable the systemd/init service unit

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from GitHub, running under a Python virtual environment managed by uvicorn, backed by a locally provisioned PostgreSQL database, and managed as a systemd service
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef (v1.0.0, Chef >= 16.0)
    - Key Features:
        - System package installation: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial`
        - Python venv creation at `/opt/fastapi-tutorial/venv` (idempotent via `creates` guard)
        - `pip install -r requirements.txt` inside the venv
        - PostgreSQL service enabled and started
        - Idempotent DB bootstrap via `psql` shell commands: user `fastapi` with password `fastapi_password` (hardcoded), database `fastapi_db`, full privileges granted
        - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` (world-readable, mode `0644`, owned root)
        - systemd unit file `/etc/systemd/system/fastapi-tutorial.service`: `Type=simple`, `User=root`, uvicorn bound to `0.0.0.0:8000`, `Restart=always`; `systemctl daemon-reload` triggered on change
        - Service enabled and started

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest; declares all 3 local cookbooks by path and 3 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but active in `Policyfile.rb`. Superseded by the Policyfile workflow but kept for Berkshelf-based workflows.
- `Policyfile.rb`: Authoritative policy definition; sets run-list `nginx-multisite::default → cache::default → fastapi-tutorial::default` and pins all 4 external dependencies including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Fully resolved dependency lock; pins `cache 1.0.0`, `fastapi-tutorial 1.0.0`, `memcached 6.1.0`, `nginx 12.3.1`, `nginx-multisite 1.0.0`, `redisio 7.2.4`, `selinux 6.2.4` (transitive dep of redisio), `ssl_certificate 2.1.0`. This file is the ground truth for reproducible builds.
- `solo.json`: Chef Solo node JSON; defines the run-list and overrides node attributes for all three sites (document roots under `/var/www/`, SSL enabled), SSL certificate/key paths, and all security flags. This is the primary source of runtime configuration and must be translated into Ansible `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo client configuration; sets `file_cache_path`, `cookbook_path` (includes both `cookbooks/` and any vendored `cookbooks-*/cookbooks/`), log level, and log destination.
- `Vagrantfile`: Vagrant development environment; targets `generic/fedora42` box, hostname `chef-nginx`, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, libvirt provider with 2 vCPUs / 2 GB RAM, rsync-syncs the repo to `/chef-repo` inside the VM, and calls `vagrant-provision.sh` as the shell provisioner.
- `vagrant-provision.sh`: Bootstrap shell script; runs `apt-get update` (note: Fedora uses `dnf`, not `apt` — this is a latent bug), installs `build-essential`, downloads and installs Chef via the Omnitruck script, installs Berkshelf gem into the embedded Chef Ruby, runs `berks install && berks vendor cookbooks`, then executes `chef-solo -c solo.rb -j solo.json`.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `generated-project-metadata.json` summarising the three cookbooks, a `Policyfile.lock.json` copy, and a prior `migration-plan.md` draft. Not part of the Chef run; can be ignored during migration.
- `x2a-rules/5da7334a-f7cb-4f35-b5e8-bbf41f6938d3.md`: X2Ansible tool specification document. Not infrastructure code; no migration action required.
- `project-plan.md`: X2Ansible tool specification (same content as the rules file). Not infrastructure code.

---

### Target Details

- **Operating System**: The Vagrantfile specifies `generic/fedora42` (Fedora Linux 42) as the development target. The cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `vagrant-provision.sh` script incorrectly calls `apt-get` (a Debian/Ubuntu tool) on a Fedora host, indicating the primary tested platform is likely **Ubuntu 20.04/22.04** despite the Vagrantfile box. The Ansible roles should target **Ubuntu 22.04 LTS** as the primary platform, with conditional task blocks for RHEL/Fedora compatibility where needed (e.g., `ufw` vs `firewalld`, `apt` vs `dnf`).
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the Vagrantfile (`config.vm.provider "libvirt"`). The VM is named `chef-nginx-multisite`.
- **Cloud Platform**: Not specified. No cloud-provider SDK, metadata endpoint, or cloud-init configuration is present. The stack is designed for on-premises or bare-metal/VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: The community cookbook wraps OS package installation and service management. Replace with the Ansible `ansible.builtin.package` module (`nginx`) plus `ansible.builtin.service`. The `nginx.conf.erb` and `security.conf.erb` templates migrate directly to Ansible Jinja2 templates with minimal variable substitution changes (`<%= @var %>` → `{{ var }}`).
- **memcached (6.1.0, Chef Supermarket)**: Fully delegated to the community cookbook. Replace with `ansible.builtin.package` (`memcached`) and `ansible.builtin.service`. No custom configuration is applied beyond what the cookbook defaults provide; verify default port (11211) and memory settings are acceptable.
- **redisio (7.2.4, Chef Supermarket)**: Manages Redis installation, per-instance config file generation, and service unit creation. Replace with `ansible.builtin.package` (`redis` / `redis-server`), a templated `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`), and `ansible.builtin.service`. The `ruby_block` post-processing hack (stripping 5 deprecated directives) must be replicated using `ansible.builtin.lineinfile` with `state: absent` or a clean Jinja2 template that never emits those directives.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Referenced in `Policyfile.rb` but not explicitly called in any local recipe (SSL is handled inline in `nginx-multisite::ssl`). Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection for self-signed cert generation.
- **selinux (6.2.4, Chef Supermarket)**: Pulled in as a transitive dependency of `redisio`. No direct SELinux configuration is applied in local recipes. On RHEL/Fedora targets, use the `ansible.posix.selinux` module or `ansible.builtin.command` with `semanage`/`setsebool` as needed. On Ubuntu targets, this dependency is a no-op and can be skipped.

---

### Security Considerations

- **Hardcoded Redis password**: `redis_secure_password_123` is written verbatim in `cookbooks/cache/recipes/default.rb` (line: `'requirepass' => 'redis_secure_password_123'`). **1 credential detected.** Migrate to `ansible-vault encrypt_string` and store in `group_vars/all/vault.yml`. Reference as `{{ vault_redis_password }}` in the Redis config template.
- **Hardcoded PostgreSQL credentials**: `fastapi_password` appears twice in `cookbooks/fastapi-tutorial/recipes/default.rb` — once in the `psql` bootstrap command and once in the `.env` file content. **2 credential instances detected (1 logical secret).** Migrate to Ansible Vault as `vault_fastapi_db_password`. The `.env` file template must use `{{ vault_fastapi_db_password }}` and the file permissions should be tightened from `0644` to `0600` with ownership changed from `root:root` to the application service user.
- **`.env` file world-readable**: `/opt/fastapi-tutorial/.env` is currently created with mode `0644`, exposing `DATABASE_URL` (including the password) to all local users. This must be corrected in the Ansible task (`mode: '0600'`).
- **FastAPI service running as root**: The systemd unit sets `User=root`. This is a significant security risk and should be corrected during migration by creating a dedicated `fastapi` system user and updating `WorkingDirectory`, `ExecStart`, and file ownership accordingly.
- **Self-signed TLS certificates**: Generated via `openssl req -x509` shell commands in `nginx-multisite::ssl`. Certificates are 365-day RSA-2048 with a hardcoded subject (`/C=US/ST=Example/...`). Replace with `community.crypto` modules. For production, integrate with Let's Encrypt via the `community.crypto.acme_certificate` module or the `geerlingguy.certbot` role.
- **SSH hardening**: `PermitRootLogin no` and `PasswordAuthentication no` are applied via `sed` commands. Migrate to `ansible.builtin.lineinfile` tasks or the `devsec.hardening.ssh_hardening` community role. Ensure the Ansible control node has key-based SSH access configured before applying `PasswordAuthentication no` to avoid lockout.
- **UFW firewall**: Rules are applied via `execute` resources wrapping `ufw` CLI commands. Migrate to the `community.general.ufw` module. On RHEL/Fedora targets, use `ansible.posix.firewalld` instead.
- **fail2ban**: Configuration is fully template-driven (`fail2ban.jail.local.erb`). The template contains no secrets. Migrate using `ansible.builtin.template` and `ansible.builtin.service`. Consider the `oefenweb.fail2ban` community role as an alternative.
- **sysctl hardening**: Applied via a template to `/etc/sysctl.d/99-security.conf`. Migrate using the `ansible.posix.sysctl` module (one task per parameter) or `ansible.builtin.template` + `ansible.builtin.command: sysctl -p`. Note: `net.ipv4.icmp_echo_ignore_all = 1` will break ICMP-based health checks; verify this is intentional.
- **SSL private key permissions**: Keys are created with mode `0640`, owned `root:ssl-cert`. Replicate exactly in Ansible using `ansible.builtin.file` after certificate generation.
- **No secrets management system in use**: There are no Chef encrypted data bags, Chef Vault calls, or environment variable injection patterns. All secrets are plaintext in recipe code. Ansible Vault must be introduced as part of this migration.

---

### Technical Challenges

- **`ruby_block "fix_redis_config"` post-processing hack**: The cache cookbook strips 5 deprecated Redis config directives after `redisio` writes the config file. This workaround exists because `redisio 7.2.4` emits directives that newer Redis versions reject. In Ansible, this is best solved by owning the Redis config template entirely (rather than patching after the fact), using a Jinja2 template that never emits the offending lines. Alternatively, use `ansible.builtin.lineinfile` with `state: absent` and `regexp:` for each directive. The template approach is strongly preferred for maintainability.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` re-implements in-place line editing with timestamped backups. This maps directly to Ansible's built-in `ansible.builtin.lineinfile` module. No custom module is needed; all call sites must be identified and replaced.
- **`vagrant-provision.sh` uses `apt-get` on Fedora**: The provisioning script calls `apt-get update` and `apt-get install -y build-essential` on a Fedora 42 VM. This will fail at runtime. The Ansible inventory/playbook must use the correct package manager (`dnf` on Fedora, `apt` on Ubuntu). Use `ansible.builtin.package` (the generic module) combined with `when: ansible_os_family == 'Debian'` / `when: ansible_os_family == 'RedHat'` conditionals for platform-specific tasks.
- **Multi-site Nginx loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, deploy static files, generate virtual host configs, and create symlinks. In Ansible, this maps to `loop:` over a `nginx_sites` variable (list of dicts). The Jinja2 template for `site.conf.erb` requires careful porting of the conditional SSL block (`<% if @ssl_enabled %>`).
- **`solo.json` document root discrepancy**: `solo.json` defines document roots as `/var/www/<site>/` but `attributes/default.rb` defines them as `/opt/server/<site>/`. The `solo.json` values take precedence at runtime (Chef attribute override). The Ansible `group_vars` must use the `/var/www/` paths to match the actual runtime behaviour.
- **`cookbook_file` source path resolution**: Static HTML files are deployed from `files/default/{ci,status,test}/index.html` using a `site_folder` variable derived by splitting the site name on `.` and taking the first segment. This logic must be replicated in Ansible, either by naming files consistently or using a `with_fileglob` / `loop` pattern.
- **Service dependency ordering**: The FastAPI systemd unit declares `After=postgresql.service`. Ansible does not automatically enforce cross-role service ordering; the playbook must sequence the `fastapi-tutorial` role after the PostgreSQL tasks complete, and the `cache` role after Nginx is up (if needed).
- **Platform package name differences**: `redis-server` (Ubuntu/Debian) vs `redis` (RHEL/Fedora/CentOS); `ufw` (Ubuntu) vs `firewalld` (RHEL/Fedora). All package tasks must include platform conditionals or use a variable map.
- **`ssl_certificate` cookbook referenced but unused locally**: The cookbook is locked in `Policyfile.lock.json` (v2.1.0) but no local recipe calls `ssl_certificate` resources. It may have been intended for future use or was replaced by the inline `openssl` shell commands. No migration action is required beyond removing the dependency.

---

### Migration Order

The following order minimises risk by establishing foundational services before dependent ones:

1. **security (extracted from nginx-multisite)** — Migrate the `nginx-multisite::security` recipe first as a standalone `security` Ansible role. It has zero dependencies on other cookbooks and establishes the firewall, fail2ban, sysctl, and SSH hardening baseline that all subsequent roles rely on. Low risk, high value.

2. **nginx-multisite** — Migrate Nginx installation, global config, SSL certificate generation, and virtual host management. Depends on the `security` role being applied first (UFW must allow ports 80/443 before Nginx is tested). Medium complexity due to the multi-site loop and SSL template logic.

3. **cache** — Migrate Memcached and Redis. Independent of `nginx-multisite` and `fastapi-tutorial` at the service level. The Redis config template must be written from scratch to avoid the `ruby_block` hack. Medium complexity due to the config post-processing workaround.

4. **fastapi-tutorial** — Migrate last due to its dependency on PostgreSQL being running and the database/user existing before the application starts. Highest complexity: involves git deployment, venv management, DB bootstrapping, `.env` secret injection, and systemd unit management. Security remediation (non-root service user, file permission tightening) should be applied here.

---

### Assumptions

1. **Primary target OS is Ubuntu 22.04 LTS**, inferred from the `apt-get` calls in `vagrant-provision.sh` and the cookbook `supports 'ubuntu', '>= 18.04'` declarations, despite the Vagrantfile specifying `generic/fedora42`. The Ansible roles should be written for Ubuntu first, with RHEL/Fedora compatibility added as a secondary concern using `when:` conditionals.
2. **Self-signed certificates are acceptable for the target environment.** If this is a production migration, the SSL recipe must be replaced with a proper CA-signed or Let's Encrypt certificate workflow before go-live.
3. **The FastAPI GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`, branch `main`) will remain publicly accessible** during and after migration. If the repo becomes private, an SSH deploy key or token must be added to the Ansible Vault and passed to the `ansible.builtin.git` task.
4. **Redis and Memcached are single-instance, non-clustered deployments.** No replication, Sentinel, or Cluster configuration is present. The Ansible roles should not introduce clustering unless explicitly requested.
5. **The `ssl_certificate` community cookbook (locked at v2.1.0) is not actively used** by any local recipe. It is safe to drop this dependency entirely in the Ansible migration.
6. **The `selinux` cookbook (v6.2.4) is a transitive dependency of `redisio`** and applies no configuration on Ubuntu targets. On RHEL/Fedora targets, SELinux policy adjustments for Redis (e.g., allowing port 6379) may be required and should be validated post-migration.
7. **The `lineinfile` custom LWRP is only defined, never called** within the local cookbooks (no `lineinfile` resource calls were found in any recipe). It was likely scaffolded for future use. No migration of call sites is required, but the LWRP definition itself does not need to be ported.
8. **Node attribute precedence**: `solo.json` overrides `attributes/default.rb` for document roots (`/var/www/` vs `/opt/server/`). The Ansible `group_vars` will use the `solo.json` values (`/var/www/<site>/`) as the authoritative configuration.
9. **The Vagrant/libvirt environment is a development-only concern.** The Ansible migration should target a standard inventory (static or dynamic) rather than Vagrant. A `Vagrantfile` using the `ansible` provisioner can be provided as a developer convenience wrapper if needed.
10. **No CI/CD pipeline integration exists** in the current Chef setup (provisioning is entirely manual via `vagrant up`). The migration plan does not include CI/CD pipeline creation, but the resulting Ansible roles should be structured to support it (role-based layout, variable separation, vault-encrypted secrets).
11. **The `x2a-rules/` directory and `f5e5b841-.../` project directory are tooling artefacts**, not infrastructure code. They will not be migrated and can be excluded from the Ansible repository.
12. **Credentials will be rotated** before or during migration. The current plaintext passwords (`redis_secure_password_123`, `fastapi_password`) should be treated as compromised and replaced with new secrets stored in Ansible Vault.
