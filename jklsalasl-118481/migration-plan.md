# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a **Chef Solo**-based infrastructure stack that provisions a multi-site Nginx web server with SSL termination, host-based security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The stack is currently developed and tested locally via **Vagrant + libvirt** on a Fedora 42 guest VM, using **Berkshelf** for cookbook dependency resolution and a **Policyfile** for run-list locking.

The migration involves **3 local cookbooks** and **5 external Chef Supermarket dependencies** (nginx 12.3.1, memcached 6.1.0, redisio 7.2.4, ssl_certificate 2.1.0, selinux 6.2.4). All three local cookbooks follow standard Chef patterns (attributes, templates, resources, recipes) with direct Ansible equivalents available for every construct used.

**Overall complexity: Medium.** No Chef Server, no encrypted data bags, no complex LWRP chains, and no multi-environment attribute layering. The main challenges are a hardcoded Redis password in a recipe, a `ruby_block` config-patching hack in the cache cookbook, and the need to replicate a custom `lineinfile` resource that already exists natively in Ansible.

**Estimated migration timeline: 3–4 weeks** for a fully tested, idiomatic Ansible role-based implementation covering all three cookbooks, including variable extraction, Vault integration for secrets, and Molecule-based smoke testing.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require an individual Ansible role:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx web server provisioning with multiple SSL-enabled virtual hosts (test, ci, status subdomains of `cluster.local`), self-signed TLS certificate generation via OpenSSL, HTTP→HTTPS redirect, security header injection (HSTS, X-Frame-Options, CSP, X-Content-Type-Options), rate-limiting zones, and host-level security hardening (fail2ban with nginx jails, UFW firewall rules, SSH root/password-auth lockdown, and kernel sysctl hardening)
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef 16+
    - Key Features:
        - Dynamic multi-site loop driven by `node['nginx']['sites']` attribute hash — three sites (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) each with independent document roots and SSL toggle
        - Self-signed RSA-2048 certificate generation per site using `openssl req -x509` (365-day validity), stored under `/etc/ssl/certs` and `/etc/ssl/private` with `ssl-cert` group ownership
        - Nginx global config (`nginx.conf.erb`) and per-site virtual host template (`site.conf.erb`) with TLSv1.2/1.3-only cipher suites
        - Dedicated `security.conf.erb` snippet: `server_tokens off`, rate-limit zones (`login` 10r/m, `api` 30r/m), buffer overflow mitigations, SSL session cache
        - fail2ban with four jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch` (ban 1 h, max 2–10 retries)
        - UFW rules: default deny, allow SSH/HTTP/HTTPS via idempotent `execute` guards
        - sysctl hardening: rp_filter, ICMP redirect suppression, source-route blocking, martian logging, SYN-cookie flood protection, IPv6 disable
        - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`) that replicates Ansible's built-in `lineinfile` module
        - Static `index.html` files for each of the three virtual hosts (served as `cookbook_file`)

- **cache**:
    - Description: Dual caching layer configuring Memcached (via the upstream `memcached` Supermarket cookbook) and Redis (via `redisio` Supermarket cookbook) with password authentication, a dedicated log directory, and a post-install `ruby_block` that surgically removes deprecated Redis config directives from the generated `/etc/redis/6379.conf`
    - Path: `cookbooks/cache`
    - Technology: Chef 16+
    - Key Features:
        - Delegates Memcached installation and service management entirely to the `memcached` community cookbook (version 6.1.0)
        - Redis configured on port 6379 with `requirepass` set to a hardcoded plaintext password (`redis_secure_password_123`) via `node.default['redisio']['servers']`
        - `ruby_block "fix_redis_config"` post-processes `/etc/redis/6379.conf` to strip five deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the `redisio` cookbook writes but the installed Redis version rejects
        - Redis log directory `/var/log/redis` created with `redis:redis` ownership
        - Depends on `selinux` cookbook (pulled transitively through `redisio`) — relevant for CentOS/Fedora targets

- **fastapi-tutorial**:
    - Description: End-to-end deployment of a Python FastAPI application cloned from a public GitHub repository, including Python 3 runtime setup, virtual environment creation, pip dependency installation, PostgreSQL database and user provisioning, `.env` file generation with database credentials, and systemd unit file creation for persistent service management
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef 16+
    - Key Features:
        - System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
        - Git clone/sync of `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial`
        - Python venv at `/opt/fastapi-tutorial/venv` with `pip install -r requirements.txt`
        - PostgreSQL service enabled and started; database user `fastapi` with hardcoded password `fastapi_password`, database `fastapi_db` created via `sudo -u postgres psql` shell commands with `|| true` guards
        - `.env` file written to `/opt/fastapi-tutorial/.env` containing `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` — plaintext credentials, world-readable (`0644`)
        - systemd unit `fastapi-tutorial.service`: `Type=simple`, `User=root`, uvicorn on `0.0.0.0:8000`, `Restart=always`, `After=postgresql.service`
        - Service runs as `root` — a security concern to address during migration

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest declaring all three local cookbooks by path and four external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`). Note: `ssl_certificate ~> 2.1` is commented out here but present and locked in the Policyfile — indicates an inconsistency between the two dependency files.
- `Policyfile.rb`: Chef Policyfile defining the policy name `nginx-multisite-policy`, the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`), and all cookbook version constraints including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Fully resolved and pinned dependency graph. Locked versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4`. This is the authoritative source of truth for dependency versions during migration.
- `solo.json`: Chef Solo node JSON providing the run list and attribute overrides. Overrides document roots to `/var/www/<site>` (conflicting with the cookbook attribute default of `/opt/server/<site>`), confirms SSL enabled for all three sites, and sets security flags (`fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, `ssh.password_auth: false`). This file is the Ansible equivalent of `group_vars` or `host_vars`.
- `solo.rb`: Chef Solo configuration pointing cookbook paths to `/chef-repo/cookbooks` and `/chef-repo/cookbooks-*/cookbooks` (the Berkshelf vendor output path), with file cache at `/var/chef-solo`.
- `Vagrantfile`: Vagrant + libvirt configuration for the `generic/fedora42` box. Assigns static IP `192.168.121.10`, forwards ports 80→8080 and 443→8443, allocates 2 vCPUs / 2 GB RAM, rsyncs the repo to `/chef-repo`, and invokes `vagrant-provision.sh` as the shell provisioner. Contains commented-out `/etc/hosts` entries for the three virtual host names — these must be added manually or via Ansible for local testing.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef-embedded gem, runs `berks install && berks vendor cookbooks`, and then executes `chef-solo -c solo.rb -j solo.json`. This entire script is replaced by the Ansible playbook invocation in the migrated workflow.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `Policyfile.lock.json` copy, `generated-project-metadata.json` (cookbook inventory), and a preliminary `migration-plan.md`. These files are tooling artifacts and do not need to be migrated.

---

### Target Details

- **Operating System**: The Vagrant box is `generic/fedora42` (Fedora 42, RPM-based). The cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The provisioning script uses `apt-get` (Debian/Ubuntu package manager), creating a **platform mismatch** with the Fedora Vagrant box — this is a pre-existing inconsistency that must be resolved during migration by choosing a single target OS family or implementing proper Ansible `when` conditionals for multi-platform support.
- **Virtual Machine Technology**: libvirt (explicitly set via `config.vm.provider "libvirt"` in the Vagrantfile).
- **Cloud Platform**: Not specified. No cloud-provider-specific tooling, metadata endpoints, or SDK references are present. The stack is designed for on-premises or generic VM deployment.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Chef Supermarket)**: Replace with the `ansible.builtin.package` module to install the distro-provided nginx package, plus `ansible.builtin.template` for `nginx.conf` and per-site virtual host configs. Consider the `nginxinc.nginx` or `geerlingguy.nginx` Ansible Galaxy role as a drop-in accelerator, but evaluate whether the added abstraction is worth the dependency given the relatively simple configuration here.
- **memcached (6.1.0, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `memcached`) and `ansible.builtin.service` (enable/start). The upstream cookbook does nothing beyond package + service + a basic config file — a direct Ansible task list is sufficient with no Galaxy role required.
- **redisio (7.2.4, Chef Supermarket)**: Replace with `ansible.builtin.package` (install `redis`) and `ansible.builtin.template` or `ansible.builtin.lineinfile` for `/etc/redis/6379.conf`. The `ruby_block` config-patching hack (removing deprecated directives) must be replicated using `ansible.builtin.lineinfile` with `state: absent` or `regexp`-based replacement — this is actually cleaner in Ansible than in Chef.
- **ssl_certificate (2.1.0, Chef Supermarket)**: Replace with `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` (or `openssl_certificate`) Ansible modules from the `community.crypto` collection. These provide idempotent, declarative self-signed certificate generation without shelling out to `openssl req`.
- **selinux (6.2.4, Chef Supermarket)**: Replace with the `ansible.posix.selinux` module for SELinux state management on RHEL/Fedora targets. On Ubuntu targets this dependency is irrelevant and should be gated with `when: ansible_selinux.status == "enabled"`.

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123` in `cookbooks/cache/recipes/default.rb`, line `'requirepass' => 'redis_secure_password_123'`): This plaintext credential must be extracted into an **Ansible Vault**-encrypted variable (`vault_redis_requirepass`) before migration. The `.env` file and any Redis client configurations referencing this password must be updated consistently. **1 credential detected.**
- **Hardcoded PostgreSQL credentials** (`fastapi_password` for user `fastapi` in `cookbooks/fastapi-tutorial/recipes/default.rb` and written verbatim into `/opt/fastapi-tutorial/.env`): Both the `psql` provisioning commands and the `.env` file template must be refactored to use Vault-encrypted variables (`vault_fastapi_db_password`). The `.env` file permissions should also be tightened from `0644` to `0600` during migration. **2 credential instances detected (DB provisioning + .env file).**
- **`.env` file world-readable**: `/opt/fastapi-tutorial/.env` is created with mode `0644` and `owner: root`, exposing `DATABASE_URL` (including password) to all local users. Ansible migration must set `mode: '0600'` and consider a dedicated non-root service account.
- **FastAPI service running as root**: The systemd unit sets `User=root`. During migration, create a dedicated `fastapi` system user and update `WorkingDirectory`, `ExecStart`, and file ownership accordingly.
- **Self-signed TLS certificates**: The `ssl.rb` recipe generates self-signed certificates using `openssl req -x509` with a hardcoded subject (`/C=US/ST=Example/...`). These are appropriate for development but must be replaced with CA-signed or Let's Encrypt certificates for any production deployment. The Ansible migration should parameterize the certificate subject and provide a clear hook for production certificate injection (e.g., via `community.crypto.acme_certificate` or copying pre-provisioned certs from Vault).
- **SSL private key directory permissions**: `/etc/ssl/private` is created with mode `0710` and `group: ssl-cert`. This must be replicated precisely in Ansible using `ansible.builtin.file` with `mode: '0710'` and `group: ssl-cert` — verify the `ssl-cert` group exists on the target OS (it is a Debian/Ubuntu convention; on Fedora/RHEL a manual group creation task is required).
- **SSH hardening via `sed`**: The `security.rb` recipe uses raw `sed -i` commands to modify `/etc/ssh/sshd_config`. Replace with `ansible.builtin.lineinfile` tasks targeting `PermitRootLogin no` and `PasswordAuthentication no` — more readable, idempotent, and auditable.
- **UFW firewall management**: UFW is Debian/Ubuntu-native. On Fedora 42 (the actual Vagrant target), `firewalld` is the default firewall manager. The migration must decide on a single firewall backend or implement platform-conditional tasks using `ansible.posix.firewalld` for RHEL/Fedora and `community.general.ufw` for Debian/Ubuntu.
- **fail2ban jail configuration**: The `fail2ban.jail.local.erb` template is static (no Chef variables interpolated). It can be migrated as a verbatim `ansible.builtin.copy` or a minimal `ansible.builtin.template`. Ensure the `nginx-botsearch` filter file exists on the target distribution before enabling that jail.
- **Vault/secrets summary**: 3 credential instances requiring Ansible Vault protection — Redis `requirepass`, PostgreSQL user password (provisioning), PostgreSQL password in `.env` file.

---

### Technical Challenges

- **Platform mismatch (apt vs dnf)**: `vagrant-provision.sh` calls `apt-get update` and `apt-get install -y build-essential`, but the Vagrant box is `generic/fedora42` (uses `dnf`). The cookbook `metadata.rb` files list Ubuntu and CentOS support but not Fedora. The Ansible migration must make an explicit platform decision: either standardize on a single OS family or implement `ansible_os_family`-conditional task blocks (`when: ansible_os_family == "Debian"` / `when: ansible_os_family == "RedHat"`). This is the highest-priority ambiguity to resolve before writing any Ansible tasks.
- **`ruby_block "fix_redis_config"` config patching**: The cache cookbook uses a `ruby_block` to post-process the Redis config file generated by `redisio`, removing five deprecated directives. In Ansible, this translates to five `ansible.builtin.lineinfile` tasks with `state: absent` and appropriate `regexp` patterns, or a single `ansible.builtin.replace` task per directive. This is straightforward but must be tested against the exact Redis version installed on the target to confirm which directives are actually written.
- **Document root path inconsistency**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{test,ci,status}`, but `solo.json` (both the root and the `.myprj` copy) overrides them to `/var/www/{test,ci,status}.cluster.local`. The Ansible role variables must use the `solo.json` values as the authoritative source, and the discrepancy should be documented and resolved in the variable defaults.
- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom Chef resource that duplicates Ansible's built-in `ansible.builtin.lineinfile` module. This resource does not appear to be called anywhere in the current recipes (no `lineinfile` resource calls found in any recipe file), suggesting it may be dead code. Verify before migration; if unused, simply omit it.
- **Dynamic site loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create directories, deploy static files, generate virtual host configs, and create symlinks. In Ansible this maps to `loop` or `with_dict` over a `nginx_sites` variable dict. The loop logic is straightforward but requires careful variable structure design to maintain the same flexibility.
- **Git-based application deployment**: `fastapi-tutorial` uses Chef's `git` resource to clone/sync from GitHub. The Ansible `ansible.builtin.git` module is a direct equivalent, but network access to `https://github.com/dibanez/fastapi_tutorial.git` must be available from the target host at provisioning time. Consider whether a local mirror or artifact-based deployment is more appropriate for production.
- **`systemctl daemon-reload` ordering**: The Chef recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, use `ansible.builtin.systemd` with `daemon_reload: true` in the same task that manages the service, or use a handler — ensure the reload happens before the `enabled/started` state is applied.
- **`|| true` idempotency guards in PostgreSQL provisioning**: The `create_db_user` execute block uses shell-level `|| true` to suppress errors if the user/database already exists. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and provide proper changed/failed state reporting.
- **Berkshelf vendor path**: `solo.rb` adds `/chef-repo/cookbooks-*/cookbooks` to the cookbook path to pick up Berkshelf-vendored dependencies. In Ansible there is no equivalent concept — all role dependencies are declared in `requirements.yml` and installed via `ansible-galaxy install`. Ensure the Galaxy role installation step is part of the CI/CD and developer onboarding documentation.

---

### Migration Order

The following order minimizes risk by starting with the most self-contained cookbook and ending with the one that has the most external dependencies and security-sensitive content:

1. **`cache` cookbook → Ansible `cache` role** *(Low complexity, fully independent, no template variables)*
    - Install and configure Memcached via package + service tasks
    - Install Redis, write `/etc/redis/6379.conf` with `requirepass` from Ansible Vault
    - Replace `ruby_block` config patch with `lineinfile` tasks removing deprecated directives
    - Create `/var/log/redis` directory with correct ownership
    - Validate: `redis-cli -a <password> ping` returns `PONG`; `memcached-tool localhost:11211 stats` succeeds

2. **`nginx-multisite` cookbook → Ansible `nginx_multisite` role** *(Medium complexity, security-critical, many templates)*
    - Install nginx, deploy `nginx.conf` and `security.conf` templates
    - Create `ssl-cert` group; generate per-site self-signed certificates using `community.crypto` modules
    - Deploy per-site virtual host configs via loop over `nginx_sites` variable dict
    - Deploy static `index.html` files for each virtual host
    - Remove default site symlink
    - Configure fail2ban with `jail.local` template
    - Configure UFW/firewalld rules (platform-conditional)
    - Apply SSH hardening via `lineinfile`
    - Apply sysctl hardening via `ansible.posix.sysctl` module
    - Validate: `curl -k https://test.cluster.local` returns HTTP 200; `fail2ban-client status` shows active jails; `ufw status` shows active rules

3. **`fastapi-tutorial` cookbook → Ansible `fastapi_tutorial` role** *(High complexity, secrets, service account, external git dependency)*
    - Create dedicated `fastapi` system user and group (replace `User=root`)
    - Install system packages (`python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`)
    - Clone application from GitHub using `ansible.builtin.git`
    - Create Python venv and install pip dependencies
    - Enable and start PostgreSQL service
    - Provision database user and database using `community.postgresql` modules (replace raw `psql` shell commands)
    - Deploy `.env` file from template with Vault-sourced credentials, mode `0600`, owned by `fastapi` user
    - Deploy systemd unit file with `User=fastapi`; reload daemon; enable and start service
    - Validate: `systemctl is-active fastapi-tutorial` returns `active`; `curl http://localhost:8000/docs` returns HTTP 200

---

### Assumptions

1. **Target OS decision is pending**: The Vagrant box is Fedora 42 but the cookbook metadata and provisioning script reference Ubuntu/Debian tooling. It is assumed the team will select **one primary target OS** before Ansible role development begins. The plan defaults to Fedora/RHEL family (matching the Vagrant box) with optional Debian/Ubuntu conditionals if multi-platform support is required.
2. **Self-signed certificates are intentional for the current scope**: It is assumed that production deployments will substitute proper CA-signed or Let's Encrypt certificates. The Ansible role will generate self-signed certs by default but expose a variable (`nginx_ssl_cert_source: self_signed | provided`) to switch to pre-provisioned certificate files.
3. **The GitHub repository `https://github.com/dibanez/fastapi_tutorial.git` remains publicly accessible**: If the repository becomes private or is moved, the `ansible.builtin.git` task will require SSH key injection or a token-based HTTPS URL.
4. **Redis and Memcached are single-node, no clustering**: The current configuration deploys standalone instances. No Redis Sentinel, Cluster, or Memcached consistent-hashing pool configuration is present or assumed to be needed.
5. **PostgreSQL is co-located with the FastAPI application**: The `DATABASE_URL` points to `localhost`. It is assumed this single-host topology is intentional for the tutorial/development context and will not be split into a separate database host during this migration.
6. **The `ssl_certificate` Supermarket cookbook is a locked dependency but its recipes are never explicitly called**: No `include_recipe 'ssl_certificate'` appears in any local recipe. It is assumed this dependency is vestigial (possibly from an earlier iteration) and can be dropped in the Ansible migration.
7. **The custom `lineinfile` LWRP in `nginx-multisite/resources/lineinfile.rb` is dead code**: No call sites were found in any recipe. It is assumed this resource was created experimentally and is not part of the active configuration. It will not be migrated unless a call site is discovered during deeper review.
8. **The `solo.json` document root paths (`/var/www/<site>`) take precedence over the cookbook attribute defaults (`/opt/server/<site>`)**: The `solo.json` values represent the operator's intent at runtime. Ansible `group_vars` will use the `/var/www/` paths as defaults.
9. **Ansible Vault will be used for all secrets**: Redis `requirepass`, PostgreSQL user password, and any future credentials will be stored in an encrypted Vault file. The team is assumed to have a Vault password management process (e.g., `ansible-vault` with a password file stored in a secrets manager).
10. **The FastAPI service account will be migrated from `root` to a dedicated `fastapi` system user**: This is treated as a required security improvement, not an optional change. Any file ownership or permission dependencies in the application code must be verified against the new user context.
11. **The commented-out `/etc/hosts` entries in the Vagrantfile are required for local testing**: These entries (`192.168.121.10 test.cluster.local`, etc.) must be added to the developer's host machine manually or via a local Ansible task targeting `localhost` — they are not part of the server provisioning playbook.
12. **`fail2ban` package availability on Fedora**: `fail2ban` is available in the Fedora repositories but may require the `epel-release` repository on CentOS/RHEL. The Ansible role must conditionally enable EPEL on RHEL-family targets before installing fail2ban.
13. **UFW is not available on Fedora/RHEL**: `ufw` is a Debian/Ubuntu tool. On Fedora 42, `firewalld` is the native firewall manager. The migration will implement firewall rules using `ansible.posix.firewalld` for RHEL/Fedora and `community.general.ufw` for Debian/Ubuntu, gated by `ansible_os_family`.
