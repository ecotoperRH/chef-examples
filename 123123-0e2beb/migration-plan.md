# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository contains a Chef-based infrastructure stack provisioned via Chef Solo and managed with Berkshelf/Policyfile dependency management. It deploys a multi-site Nginx web server with SSL termination, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL — all running on a single Fedora 42 VM managed by Vagrant with libvirt.

The stack is composed of **3 local cookbooks** and **5 external Supermarket cookbook dependencies**, with a well-defined run list: `nginx-multisite → cache → fastapi-tutorial`. The cookbooks follow standard Chef patterns (attributes, recipes, templates, custom resources) and map cleanly to Ansible equivalents, making this a **medium-complexity migration** with an estimated effort of **3–4 weeks** for a complete, tested Ansible implementation.

The primary migration challenges are: replacing Chef's attribute-driven multi-site loop logic with Ansible variable structures and `with_items`/`loop` constructs; safely migrating hardcoded credentials to Ansible Vault; handling a Redis config post-processing hack currently implemented as a `ruby_block`; and reconciling the document root path discrepancy between cookbook defaults and the `solo.json` node override. No Chef Server, encrypted data bags, or Chef Vault usage was detected — secrets are currently stored in plaintext within recipe files and JSON node attributes.

---

## Module Migration Plan

This repository contains 3 Chef cookbooks that each require individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
    - Description: Nginx reverse proxy and multi-site web server with SSL termination, per-site self-signed certificate generation, security hardening via fail2ban and UFW firewall, kernel-level sysctl network hardening, and SSH daemon hardening. Serves three virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) each with HTTP-to-HTTPS redirect, TLS 1.2/1.3 enforcement, HSTS, and a full suite of security response headers (X-Frame-Options, CSP, X-Content-Type-Options, etc.).
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Attribute-driven virtual host loop, ERB-templated `nginx.conf` and per-site `site.conf`, `security.conf` with rate limiting zones, fail2ban with nginx-specific jails (http-auth, limit-req, botsearch), UFW rules (deny default, allow SSH/HTTP/HTTPS), sysctl hardening template (IP spoofing, ICMP, SYN flood, IPv6 disable), SSH root login and password auth disabled via `sed`, custom `lineinfile` LWRP, static `index.html` files deployed per site from `files/default/{ci,status,test}/`.

- **cache**:
    - Description: Caching layer configuration deploying both Memcached (via the `memcached` Supermarket cookbook) and Redis (via the `redisio` Supermarket cookbook) with password authentication. Includes a post-processing `ruby_block` hack to strip deprecated Redis configuration directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) that the `redisio` cookbook writes but the installed Redis version does not accept.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Redis on port 6379 with `requirepass` authentication, Redis log directory creation (`/var/log/redis`), Memcached default configuration, `redisio::enable` for systemd service management, inline config-file mutation via `ruby_block`.

- **fastapi-tutorial**:
    - Description: Full-stack Python web application deployment: installs system packages (Python 3, pip, venv, git, PostgreSQL with libpq-dev), clones the FastAPI tutorial application from GitHub, creates a Python virtual environment, installs pip dependencies, configures and starts PostgreSQL, provisions a database user and database, writes a `.env` file with database connection string, and registers a systemd unit for the uvicorn application server.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: Git-based deployment from `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`), Python venv at `/opt/fastapi-tutorial/venv`, PostgreSQL user `fastapi` with password `fastapi_password`, database `fastapi_db`, `.env` file with `DATABASE_URL`, systemd service `fastapi-tutorial` running uvicorn on `0.0.0.0:8000` as root, `systemctl daemon-reload` via notifies chain.

---

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest. Declares all 3 local cookbooks by path and 4 external Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`, `ssl_certificate ~> 2.1`). Note: `ssl_certificate` is commented out in the Berksfile but present and locked in `Policyfile.rb` and `Policyfile.lock.json` — this inconsistency must be resolved before migration.
- `Policyfile.rb`: Chef Policyfile defining the policy name (`nginx-multisite-policy`), the authoritative run list, and all cookbook version constraints. This is the source of truth for the dependency graph and maps directly to an Ansible playbook run order.
- `Policyfile.lock.json`: Locked dependency graph with resolved versions: `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`, `selinux 6.2.4` (transitive dep of redisio). Confirms `selinux` cookbook is a transitive dependency — relevant for RHEL/Fedora targets.
- `solo.json` (root): Chef Solo node JSON providing runtime attribute overrides. Overrides document roots to `/var/www/{site}` (conflicting with cookbook defaults of `/opt/server/{site}`), sets `ssl_enabled: true` for all three sites, sets SSL paths, and enables all security features (`fail2ban`, `ufw`, `ssh.disable_root`, `ssh.password_auth: false`). This file is the **authoritative runtime configuration** and its values must be carried into Ansible group/host vars.
- `solo.rb`: Chef Solo configuration pointing cookbook path to `/chef-repo/cookbooks` and cache to `/var/chef-solo`. Relevant only for understanding the provisioning bootstrap; no direct Ansible equivalent needed.
- `Vagrantfile`: Vagrant VM definition using `generic/fedora42` box, hostname `chef-nginx`, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, libvirt provider with 2 vCPUs and 2 GB RAM. Rsync-based folder sync of the repo to `/chef-repo`. Defines the target development environment for Ansible inventory.
- `vagrant-provision.sh`: Bootstrap shell script that installs Chef via the Omnitruck installer, installs Berkshelf as a Chef embedded gem, runs `berks install && berks vendor`, and executes `chef-solo`. In the Ansible world this is replaced entirely by `ansible-playbook`. The script also reveals that `apt-get` is used inside the VM despite the box being Fedora — indicating a potential OS mismatch or that the Vagrant box includes a Debian-compatible layer; this must be investigated.
- `f5e5b841-afe0-4bf1-9431-2418e9f4c239.myprj/`: Project metadata directory generated by the X2Ansible tooling. Contains a duplicate `solo.json`, a `generated-project-metadata.json` with the module inventory, a `Policyfile.lock.json` copy, and a prior draft `migration-plan.md`. These files are tooling artifacts and do not need to be migrated.
- `project-plan.md`: X2Ansible tool specification document. Not part of the infrastructure to be migrated.

---

### Target Details

- **Operating System**: The `Vagrantfile` specifies `generic/fedora42` (Fedora 42), and the `vagrant-provision.sh` script calls `apt-get` — a contradiction indicating either the box ships with apt compatibility shims or the provisioning script was written for Ubuntu and not updated. Cookbook `metadata.rb` files declare support for `ubuntu >= 18.04` and `centos >= 7.0`. The `selinux` transitive dependency (pulled in by `redisio`) and the `ufw` firewall usage (Debian/Ubuntu tool) further highlight a mixed-OS assumption. **The Ansible playbooks must explicitly handle both Debian/Ubuntu (`apt`, `ufw`) and RHEL/Fedora (`dnf`, `firewalld`) package managers and firewall tools, or the target OS must be standardized before migration begins.**
- **Virtual Machine Technology**: libvirt / KVM (explicitly set in `Vagrantfile` via `config.vm.provider "libvirt"`).
- **Cloud Platform**: Not specified. The infrastructure is designed for local/on-premises VM deployment. No cloud-provider-specific tooling, metadata endpoints, or SDK references were detected.

---

## Migration Approach

### Key Dependencies to Address

- **nginx (12.3.1, Supermarket)**: The community `nginx` cookbook handles installation, service management, and basic configuration. Replace with the `ansible.builtin.package` module for installation, `ansible.builtin.template` for `nginx.conf` and per-site configs, `ansible.builtin.service` for lifecycle management, and `ansible.builtin.file` for document root directories. The existing ERB templates (`nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`) can be converted to Jinja2 with minimal changes.
- **memcached (6.1.0, Supermarket)**: Thin wrapper around package install and service enable. Replace with `ansible.builtin.package` + `ansible.builtin.service`. No complex configuration is applied beyond defaults.
- **redisio (7.2.4, Supermarket)**: Manages Redis installation, per-instance configuration file generation, and service management. Replace with `ansible.builtin.package`, a templated `/etc/redis/6379.conf`, and `ansible.builtin.service`. The post-processing `ruby_block` hack (stripping deprecated directives) becomes unnecessary if the Ansible-managed template is written correctly from the start — simply omit the deprecated directives.
- **ssl_certificate (2.1.0, Supermarket)**: Referenced in `Policyfile.rb` and locked, but commented out in `Berksfile` and not directly `include_recipe`'d in any local cookbook. The `nginx-multisite::ssl` recipe implements its own `openssl req` command directly. Replace with `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, and `community.crypto.x509_certificate` modules from the `community.crypto` Ansible collection.
- **selinux (6.2.4, Supermarket)**: Transitive dependency of `redisio`. Not explicitly invoked in local recipes. On Fedora/RHEL targets, SELinux context management for Redis and Nginx paths will need to be handled via `community.general.sefcontext` and `ansible.builtin.command: restorecon` or the `ansible.posix.selinux` module.

---

### Security Considerations

- **Hardcoded Redis password**: The Redis `requirepass` value `redis_secure_password_123` is hardcoded directly in `cookbooks/cache/recipes/default.rb` as a node attribute assignment. **This credential must be moved to Ansible Vault** before the playbook is committed to any version control system. Detected: 1 hardcoded service credential.
- **Hardcoded PostgreSQL credentials**: The `fastapi-tutorial` recipe hardcodes the PostgreSQL username (`fastapi`), password (`fastapi_password`), and database name (`fastapi_db`) in three places: the `psql` shell commands, the `.env` file content, and the `DATABASE_URL` environment variable. **All three must be parameterized and stored in Ansible Vault.** Detected: 1 hardcoded database password, 1 plaintext `.env` file with connection string.
- **`.env` file permissions**: The FastAPI `.env` file at `/opt/fastapi-tutorial/.env` is created with mode `0644` (world-readable), exposing the `DATABASE_URL` including the database password to all local users. In Ansible, this file should be deployed with mode `0600` and owned by the service account (not root).
- **FastAPI service running as root**: The systemd unit sets `User=root`, which is a significant security risk. The Ansible migration should introduce a dedicated `fastapi` system user and update the service definition accordingly.
- **Self-signed SSL certificates**: The `nginx-multisite::ssl` recipe generates self-signed certificates using `openssl req` with a hardcoded subject string (`/C=US/ST=Example/...`). These are appropriate for development but must not be used in production. The Ansible role should support a variable to switch between self-signed (dev) and externally-provided or Let's Encrypt certificates (production). Certificate subject fields should be parameterized as Ansible variables.
- **SSL private key permissions**: The recipe correctly sets the private key to mode `0640` owned by `root:ssl-cert`. This must be preserved exactly in the Ansible equivalent.
- **SSH hardening**: Root login and password authentication are disabled via `sed` commands on `/etc/ssh/sshd_config`. In Ansible, use the `ansible.builtin.lineinfile` module (a direct equivalent of the custom `lineinfile` LWRP defined in this cookbook) or the `devsec.hardening.ssh_hardening` role for a more comprehensive approach.
- **UFW firewall**: The `security` recipe configures UFW (an Ubuntu/Debian tool). On Fedora 42, UFW is not the default — `firewalld` is. The Ansible playbook must branch on `ansible_os_family` to use `community.general.ufw` on Debian-family systems and `ansible.posix.firewalld` on RedHat-family systems.
- **Sysctl hardening**: The `sysctl-security.conf.erb` template disables IPv6 globally (`net.ipv6.conf.all.disable_ipv6 = 1`) and ignores all ICMP pings. These are aggressive settings that may break IPv6-dependent services or monitoring. They should be reviewed and made configurable via Ansible boolean variables before applying to production.
- **Fail2ban**: Four jails are configured (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch). The `logpath` for `sshd` points to `/var/log/auth.log` (Debian convention); on Fedora/RHEL the correct path is `/var/log/secure`. This must be handled conditionally in the Ansible template.
- **No secrets management system detected**: There are no Chef encrypted data bags, Chef Vault references, or external secrets manager integrations. All secrets are in plaintext. Ansible Vault should be introduced as part of this migration to establish a secrets baseline.

---

### Technical Challenges

- **Document root path inconsistency**: The cookbook `attributes/default.rb` sets document roots to `/opt/server/{site}` while `solo.json` overrides them to `/var/www/{site}`. The static `index.html` files are deployed to whichever path the attribute resolves to at runtime. In Ansible, this must be resolved into a single canonical variable definition in `group_vars` or `host_vars`, and the correct path must be confirmed with the operations team before migration.
- **Redis `ruby_block` config post-processing**: The `cache` cookbook uses a `ruby_block` to open and regex-edit the Redis config file after `redisio` writes it, stripping directives that cause the installed Redis version to fail. In Ansible, this entire hack is eliminated by owning the Redis config template directly — write a Jinja2 template for `/etc/redis/6379.conf` that never includes the deprecated directives. However, the exact Redis version on the target system must be confirmed to ensure the template is compatible.
- **Custom `lineinfile` LWRP**: The `nginx-multisite` cookbook defines a custom `lineinfile` resource (`resources/lineinfile.rb`) that replicates functionality already available natively in Ansible as `ansible.builtin.lineinfile`. This resource is not called anywhere in the current recipes (it appears to be unused infrastructure), but its existence should be noted. No migration effort is required for the resource itself.
- **Attribute-driven site loop**: The `nginx.rb` and `sites.rb` recipes iterate over `node['nginx']['sites']` to create directories, deploy files, and generate per-site Nginx configs. In Ansible, this maps to a `loop` over a `nginx_sites` list variable, with `ansible.builtin.template`, `ansible.builtin.file`, and `ansible.builtin.copy` tasks. The Jinja2 conversion of `site.conf.erb` is straightforward but requires careful handling of the conditional SSL block.
- **`apt-get` in `vagrant-provision.sh` on Fedora**: The provisioning script calls `apt-get update` and `apt-get install -y build-essential` on what is declared as a Fedora 42 VM. This will fail on a real Fedora system. The Ansible playbook must use `ansible.builtin.package` (distro-agnostic) or explicitly use `ansible.builtin.dnf` for Fedora targets. This OS ambiguity must be resolved before writing the Ansible inventory.
- **Git-based application deployment**: The `fastapi-tutorial` recipe uses Chef's `git` resource to clone and sync the application. Ansible's `ansible.builtin.git` module is a direct equivalent, but the `action :sync` behavior (which resets to the specified revision) must be replicated carefully to avoid overwriting local changes in non-idempotent deployments.
- **systemd daemon-reload ordering**: The recipe uses `notifies :run, 'execute[systemd_reload]', :immediately` to reload systemd after writing the unit file. In Ansible, this is handled via a handler (`systemctl daemon-reload`) triggered by a `notify` on the template task — a direct conceptual equivalent, but the handler must be defined in the role's `handlers/main.yml`.
- **PostgreSQL initialization idempotency**: The `create_db_user` execute block uses `|| true` to suppress errors on duplicate user/database creation. In Ansible, use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require error suppression hacks.
- **Platform-specific service names**: The SSH service is named `ssh` on Debian/Ubuntu and `sshd` on RHEL/Fedora. The `security.rb` recipe hardcodes `service 'ssh'`. The Ansible playbook must use a variable (e.g., `ssh_service_name`) set per OS family in `group_vars`.

---

### Migration Order

1. **`nginx-multisite` cookbook** — Migrate first as it is the most complex cookbook and establishes the foundational security posture (firewall, SSH hardening, sysctl) that all other services depend on. Decompose into sub-roles: `nginx_install`, `nginx_sites`, `nginx_ssl`, `security_hardening`. Validate each sub-role independently before combining.

2. **`cache` cookbook** — Migrate second as it is fully independent of `nginx-multisite` and `fastapi-tutorial`. Low complexity. Implement Memcached and Redis as separate tasks files within a single `cache` role. Write a clean Redis config template to eliminate the `ruby_block` hack entirely.

3. **`fastapi-tutorial` cookbook** — Migrate last due to its dependency on PostgreSQL (which must be running before the application starts), its use of Git-based deployment (requires network access during provisioning), and the security remediation work needed (dedicated service user, `.env` file permissions, credential vaulting). This cookbook has the highest number of security issues to address.

---

### Assumptions

1. **Target OS ambiguity**: It is assumed that the `apt-get` calls in `vagrant-provision.sh` are a scripting error and that the actual target OS is Fedora 42 as declared in the `Vagrantfile`. This must be confirmed with the team. If Ubuntu is the actual target, the firewall module choice (`ufw` vs `firewalld`), package manager, and SELinux handling will differ significantly.

2. **Document root canonical path**: It is assumed that the `solo.json` override (`/var/www/{site}`) takes precedence over the cookbook attribute defaults (`/opt/server/{site}`) and represents the intended production path. The Ansible `group_vars` will use `/var/www/{site}` unless the team confirms otherwise.

3. **Self-signed certificates are development-only**: It is assumed that production deployments will use CA-signed or Let's Encrypt certificates. The Ansible SSL role will be designed with a `ssl_cert_type` variable (`self_signed` | `letsencrypt` | `provided`) to support all three modes.

4. **`ssl_certificate` Supermarket cookbook is unused**: The cookbook is locked in `Policyfile.lock.json` and referenced in `Policyfile.rb` but commented out in `Berksfile` and never `include_recipe`'d. It is assumed this is dead dependency and will not be migrated.

5. **Redis is single-instance, no clustering**: The `redisio` configuration defines a single server on port 6379. It is assumed no Redis Sentinel or Cluster configuration is required. The Ansible role will configure a single standalone Redis instance.

6. **Memcached uses default configuration**: No custom Memcached attributes are set in any recipe or `solo.json`. It is assumed the default Memcached configuration (port 11211, 64 MB memory, localhost binding) is intentional and acceptable.

7. **FastAPI application repository remains available**: The deployment depends on `https://github.com/dibanez/fastapi_tutorial.git` being publicly accessible. It is assumed this repository will remain available and that the `main` branch is stable. If the repository becomes private or is moved, the Ansible `git` task will require credential configuration.

8. **No Chef Server or remote state**: The infrastructure uses Chef Solo exclusively. There are no Chef Server API calls, search queries, or data bag lookups to replicate in Ansible. All configuration is self-contained in the local files.

9. **IPv6 can be disabled**: The `sysctl-security.conf.erb` template disables IPv6 system-wide. It is assumed this is intentional and that no services in the stack require IPv6 connectivity.

10. **`www-data` user exists on target**: The `nginx.rb` recipe sets document root ownership to `www-data:www-data`. On Fedora, Nginx typically runs as `nginx:nginx`. It is assumed the team will accept using `nginx:nginx` on Fedora targets, or that `www-data` will be created explicitly. This must be confirmed.

11. **Ansible Vault will be adopted for secrets**: It is assumed the team accepts introducing Ansible Vault as the secrets management solution for Redis password, PostgreSQL credentials, and any future secrets. No external secrets manager (HashiCorp Vault, AWS Secrets Manager, etc.) integration is in scope for this migration.

12. **The custom `lineinfile` LWRP is not called by any recipe**: A review of all recipe files confirms the `lineinfile` resource defined in `resources/lineinfile.rb` is never invoked within this cookbook. It is assumed this is unused scaffolding and will not be ported to Ansible.
