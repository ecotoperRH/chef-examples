# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a **Chef Solo** infrastructure-as-code project that provisions a single Vagrant-based virtual machine (Fedora 42, libvirt) running a multi-service web stack. The policy (`nginx-multisite-policy`) executes three local cookbooks in sequence: a hardened Nginx multi-site reverse proxy, a dual caching layer (Memcached + Redis), and a FastAPI Python application backed by PostgreSQL.

The migration scope is **moderate**: three local cookbooks, four external Supermarket dependencies, and a well-defined run-list. No Chef Server, encrypted data bags, or Chef Vault are in use — the entire stack runs via `chef-solo`, which simplifies the transition. The primary complexity lies in replacing Chef community cookbooks (`nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `ssl_certificate 2.1.0`) with native Ansible modules and roles, and in safely handling the several hardcoded credentials present in the source.

**Estimated migration timeline: 2–3 weeks** for a single engineer familiar with Ansible, or 1–1.5 weeks with a two-person team.

---

## Module Migration Plan

This repository contains **3 local Chef cookbooks** that need individual migration planning, backed by **4 external Chef Supermarket cookbooks** that will be replaced by Ansible built-ins or Galaxy roles.

---

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
All paths below were confirmed from the provided repository tree and file content reads. No paths have been inferred or invented.

---

- **nginx-multisite**
  - **Description**: Nginx reverse proxy with SSL termination, multi-site virtual host management, host-based firewall hardening, SSH hardening, and kernel-level network security tuning. Manages three SSL-enabled subdomains (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with its own self-signed certificate, document root, and per-site access/error logs. Enforces TLS 1.2/1.3-only cipher suites, HSTS, and a full set of security response headers (X-Frame-Options, CSP, X-Content-Type-Options). Deploys fail2ban with jails for SSH, nginx-http-auth, nginx-limit-req, and nginx-botsearch. Configures UFW with default-deny and explicit allow rules for ports 22, 80, and 443. Applies a comprehensive sysctl hardening profile (IP spoofing protection, ICMP redirect suppression, SYN-cookie flood protection, IPv6 disable).
  - **Path**: `cookbooks/nginx-multisite`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**:
    - ERB templates: `nginx.conf.erb`, `site.conf.erb`, `security.conf.erb`, `fail2ban.jail.local.erb`, `sysctl-security.conf.erb`
    - Static site content files for three virtual hosts (`ci/`, `status/`, `test/`)
    - Custom `lineinfile` LWRP resource (`resources/lineinfile.rb`)
    - Attribute-driven site map (document roots, SSL toggle) via `attributes/default.rb`
    - Depends on external `nginx ~> 12.0` Supermarket cookbook (locked at 12.3.1)
    - Depends on external `ssl_certificate ~> 2.1` Supermarket cookbook (locked at 2.1.0)

---

- **cache**
  - **Description**: Dual in-memory caching layer that installs and configures both Memcached and Redis on the same host. Redis is configured on port 6379 with password authentication. Includes a `ruby_block` workaround that post-processes the generated Redis config file to strip deprecated `replica-*` directives that are incompatible with the locked `redisio 7.2.4` cookbook, indicating a known compatibility issue with the community cookbook version.
  - **Path**: `cookbooks/cache`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**:
    - Delegates Memcached installation to external `memcached ~> 6.0` Supermarket cookbook (locked at 6.1.0)
    - Delegates Redis installation to external `redisio ~> 7.2.4` Supermarket cookbook (locked at 7.2.4); `redisio` itself depends on `selinux 6.2.4`
    - **Hardcoded Redis password**: `redis_secure_password_123` set directly in `recipes/default.rb`
    - Post-install config file mutation via `ruby_block` (a known workaround for `redisio` compatibility)
    - Creates `/var/log/redis` directory with `redis:redis` ownership

---

- **fastapi-tutorial**
  - **Description**: Full-stack Python web application provisioner. Clones the `fastapi_tutorial` repository from GitHub, creates a Python 3 virtual environment, installs pip dependencies, provisions a PostgreSQL database and dedicated user, writes a `.env` configuration file with the database connection string, and registers the application as a systemd service (`fastapi-tutorial.service`) running `uvicorn` on port 8000.
  - **Path**: `cookbooks/fastapi-tutorial`
  - **Technology**: Chef (≥ 16.0)
  - **Key Features**:
    - Clones `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) to `/opt/fastapi-tutorial`
    - Installs system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`
    - **Hardcoded PostgreSQL credentials**: user `fastapi`, password `fastapi_password`, database `fastapi_db` — written both into the `psql` provisioning commands and into `/opt/fastapi-tutorial/.env`
    - `.env` file written with mode `0644` (world-readable), exposing the `DATABASE_URL` with embedded password
    - systemd unit runs the application as `root` (no dedicated service account)
    - No external cookbook dependencies; all logic is self-contained

---

### Infrastructure Files

- **`Policyfile.rb`**: Chef Policyfile defining the `nginx-multisite-policy` run-list and pinning all external cookbook sources. This is the authoritative dependency declaration — maps directly to Ansible's `requirements.yml` for Galaxy roles.
- **`Policyfile.lock.json`**: Fully resolved dependency lock file with exact versions and SHA identifiers for all 8 cookbooks (3 local + 5 external). Use this as the reference for exact version parity when selecting Ansible Galaxy role versions.
- **`Berksfile`**: Berkshelf dependency file used for local development and Vagrant provisioning. Mirrors `Policyfile.rb`; note that `ssl_certificate` is commented out here but active in the Policyfile — this discrepancy should be resolved during migration.
- **`solo.json`**: Chef Solo node JSON providing runtime attributes: site definitions (document roots, SSL flags), SSL certificate/key paths, and security flags (fail2ban, UFW, SSH hardening). This file is the direct source of truth for Ansible inventory variables / `group_vars`.
- **`solo.rb`**: Chef Solo configuration pointing to `/var/chef-solo` as the cache path and `/chef-repo/cookbooks` as the cookbook path. No migration artifact needed; replaced by `ansible.cfg` and inventory.
- **`Vagrantfile`**: Vagrant VM definition using `generic/fedora42` box with libvirt provider (2 vCPU, 2 GB RAM), private network `192.168.121.10`, and port forwards 80→8080 and 443→8443. Defines the target environment for the Ansible inventory. The commented-out `chef_solo` provisioner block can be replaced with an `ansible_local` or `ansible` provisioner.
- **`vagrant-provision.sh`**: Bootstrap shell script that installs Chef, Berkshelf, vendors cookbooks, and runs `chef-solo`. In the Ansible migration this is replaced by the Vagrant `ansible` provisioner or a simple `ansible-playbook` call.
- **`project-plan.md`**: Existing project documentation — review for any additional context or constraints before migration.
- **`x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md`**: Migration rules or constraints file — review contents before finalising the Ansible role structure.

---

### Target Details

- **Operating System**: Ubuntu (≥ 18.04) and CentOS (≥ 7.0) are declared as supported in all three `metadata.rb` files. The Vagrant development environment uses **Fedora 42** (`generic/fedora42`). The `www-data` user in `nginx.rb` and `apt-get` calls in `vagrant-provision.sh` indicate the primary runtime target is **Debian/Ubuntu**. Default to **Ubuntu 22.04 LTS** for the Ansible migration unless the production target is confirmed otherwise.
- **Virtual Machine Technology**: **libvirt / KVM** — explicitly configured in the `Vagrantfile` (`config.vm.provider "libvirt"`). The VM is used as a local development/testing environment; production deployment mechanism is not defined in this repository.
- **Cloud Platform**: Not specified. No cloud-provider-specific configurations, metadata endpoints, or SDK references are present.

---

## Migration Approach

### Key Dependencies to Address

- **`nginx` (12.3.1)** — Chef Supermarket community cookbook managing Nginx installation and base configuration. Replace with the `ansible.builtin.package` module for installation and Ansible `template` tasks for `nginx.conf`. Consider the `nginxinc.nginx` Galaxy role for more complex scenarios, or manage fully with native tasks given the relatively simple configuration present.

- **`memcached` (6.1.0)** — Chef Supermarket cookbook for Memcached installation and service management. Replace with `ansible.builtin.package` + `ansible.builtin.service` tasks. No complex configuration is applied beyond defaults, making this a straightforward substitution.

- **`redisio` (7.2.4)** — Chef Supermarket cookbook for Redis installation and configuration. Note the active workaround in `cache::default` that strips deprecated `replica-*` directives from the generated config — this signals that `redisio 7.2.4` generates a config incompatible with the Redis version on the target OS. In Ansible, manage Redis directly via `ansible.builtin.package`, a `template` task for `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`), and `ansible.builtin.service`. This eliminates the workaround entirely.

- **`ssl_certificate` (2.1.0)** — Chef Supermarket cookbook for SSL certificate management. Currently used only for self-signed certificate generation via `openssl req`. Replace with the `community.crypto.x509_certificate` and `community.crypto.openssl_privatekey` Ansible modules (from `community.crypto` collection). For production, integrate with Let's Encrypt via `community.crypto.acme_certificate`.

- **`selinux` (6.2.4)** — Transitive dependency of `redisio`; manages SELinux policy. In Ansible, use `ansible.posix.selinux` module if the production target requires SELinux management (relevant for CentOS/RHEL targets).

---

### Security Considerations

- **Hardcoded Redis password** (`redis_secure_password_123`): Embedded directly in `cookbooks/cache/recipes/default.rb`. In Ansible, move to `ansible-vault`-encrypted variables (`vars/secrets.yml`). Never commit plaintext credentials to the playbook repository.

- **Hardcoded PostgreSQL credentials** (`fastapi` / `fastapi_password`): Appear in three places in `cookbooks/fastapi-tutorial/recipes/default.rb` — in the `psql` provisioning commands, in the `.env` file content, and implicitly in the `DATABASE_URL`. Migrate to `ansible-vault` encrypted variables. The `.env` file template should use a vault variable reference.

- **World-readable `.env` file**: `/opt/fastapi-tutorial/.env` is written with mode `0644`, exposing `DATABASE_URL` (including the database password) to all local users. Change to mode `0600` in the Ansible `template` task, and set `owner` to the dedicated service account (see below).

- **FastAPI service running as `root`**: The systemd unit sets `User=root`. Create a dedicated `fastapi` system account in Ansible and run the service under that account. Update directory ownership accordingly.

- **Self-signed SSL certificates**: All three virtual hosts use self-signed certificates generated at provision time with a 365-day validity. These are appropriate for development but must be replaced with CA-signed or Let's Encrypt certificates for any production deployment. Document this as a hard requirement in the Ansible role's README.

- **SSH hardening via `sed`**: `security.rb` mutates `/etc/ssh/sshd_config` using `sed` commands. Replace with the `ansible.builtin.lineinfile` module (or `ansible.builtin.template` for the full sshd_config) for idempotent, auditable SSH configuration management.

- **UFW management via shell commands**: UFW is configured through `execute` resources running raw `ufw` commands with `not_if` guards. Replace with the `community.general.ufw` Ansible module for fully idempotent firewall management.

- **Fail2ban configuration**: Managed via an ERB template (`fail2ban.jail.local.erb`). Migrate to an Ansible `template` task with a Jinja2 equivalent. The jail configuration (ban times, retry counts, monitored log paths) should be parameterised as role variables.

- **Sysctl hardening**: Applied via `sysctl-security.conf.erb` template and a `sysctl -p` execute resource. Replace with the `ansible.posix.sysctl` module for each kernel parameter, or deploy the config file via `template` and notify a handler to reload sysctl.

- **No secrets management system in use**: The source repository uses no Chef Vault, encrypted data bags, or external secrets store. All credentials are plaintext in recipe files. Ansible Vault must be introduced as part of this migration — this is a net security improvement.

---

### Technical Challenges

- **`redisio` config compatibility workaround**: The `ruby_block "fix_redis_config"` in `cache::default` is a post-hoc file mutation that strips deprecated Redis directives. This indicates a version mismatch between `redisio 7.2.4` and the Redis package available on the target OS. When migrating, write the Redis configuration directly via an Ansible template, bypassing this issue entirely. Verify the correct Redis config directive names for the target OS's Redis package version before writing the template.

- **Custom `lineinfile` LWRP**: `cookbooks/nginx-multisite/resources/lineinfile.rb` defines a custom Chef resource. Review its implementation before migration to confirm whether it is actually called anywhere in the cookbook (it does not appear in the recipes reviewed). If unused, discard it; if used, replace with `ansible.builtin.lineinfile`.

- **Attribute-driven site loop**: Both `nginx.rb` and `sites.rb` iterate over `node['nginx']['sites']` to create document roots, deploy static files, generate SSL certificates, and write virtual host configs. In Ansible, this maps to a `loop` or `with_items` construct over a `nginx_sites` list variable. The variable structure should mirror `solo.json`'s `nginx.sites` object and be placed in `group_vars` or the role's `defaults/main.yml`.

- **`ssl_certificate` cookbook commented out in Berksfile**: The `ssl_certificate ~> 2.1` dependency is commented out in `Berksfile` but active in `Policyfile.rb` and present in `Policyfile.lock.json`. This discrepancy suggests the cookbook may not actually be used at runtime (the SSL recipe uses raw `openssl` commands rather than the cookbook's resources). Confirm before migration whether `ssl_certificate` resources are invoked anywhere; if not, the `community.crypto` collection is sufficient.

- **PostgreSQL provisioning idempotency**: The `fastapi-tutorial` recipe uses `|| true` to suppress errors on duplicate `CREATE USER` / `CREATE DATABASE` statements. In Ansible, use the `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent.

- **GitHub dependency at provision time**: The `fastapi-tutorial` cookbook clones a public GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`) during provisioning. This creates a runtime dependency on external network access and repository availability. Consider vendoring the application code or using a private mirror for production deployments. In Ansible, use the `ansible.builtin.git` module with an explicit `version` (commit SHA) rather than tracking `main`.

- **Vagrant/libvirt-specific configuration**: The current setup is tightly coupled to a local Vagrant/libvirt development environment. The Ansible migration should abstract environment-specific values (IP addresses, port forwards, box type) into inventory variables so the same playbook can target both Vagrant VMs and production hosts.

- **`www-data` user assumption**: `nginx.rb` hardcodes `owner 'www-data'` for document roots, which is Debian/Ubuntu-specific. On CentOS/RHEL the nginx user is `nginx`. If multi-OS support is retained, parameterise the web server user as a role variable with OS-family-based defaults.

---

### Migration Order

1. **`nginx-multisite` — security sub-role** (`security.rb`): Migrate the OS hardening tasks first (UFW, fail2ban, sysctl, SSH config). This is self-contained, has no external cookbook dependencies, and delivers immediate security value. Maps cleanly to a reusable `security` Ansible role.

2. **`nginx-multisite` — nginx sub-role** (`nginx.rb`, `ssl.rb`, `sites.rb`, templates): Migrate Nginx installation, SSL certificate generation, virtual host configuration, and static file deployment. Depends on the security role being in place. Replace ERB templates with Jinja2 equivalents. Validate all three virtual hosts are reachable before proceeding.

3. **`cache`** (Memcached + Redis): Migrate caching services. Straightforward package + service + config tasks. Use this migration to eliminate the `redisio` workaround and introduce Ansible Vault for the Redis password. Validate both services are running and accepting connections.

4. **`fastapi-tutorial`** (Python app + PostgreSQL): Migrate last due to the highest number of security issues (hardcoded credentials, root service account, world-readable `.env`). Introduce a dedicated `fastapi` system user, vault-encrypted database credentials, and a corrected `.env` file mode. Validate the FastAPI service starts and the PostgreSQL database is accessible.

---

### Assumptions

1. **Target OS for production is Ubuntu 22.04 LTS**: Inferred from `www-data` user references and `apt-get` usage in `vagrant-provision.sh`. If CentOS/RHEL is the production target, package names, service names, and the web server user will differ and must be handled with Ansible `ansible_os_family` conditionals.

2. **Chef Solo only — no Chef Server**: The repository uses `chef-solo` with a local `solo.json` node file. There is no Chef Server, Ohai data, or node search in use. This simplifies migration as there is no server-side state to replicate.

3. **Development/lab environment only**: The presence of self-signed certificates, hardcoded passwords, a service running as root, and a Vagrant-only deployment mechanism strongly suggests this is a development or tutorial environment, not a production system. The migration plan assumes production hardening (real certificates, secrets management, non-root service accounts) will be applied as part of the Ansible migration.

4. **`ssl_certificate` Supermarket cookbook is not functionally used**: The SSL recipe generates certificates using raw `openssl` shell commands rather than the `ssl_certificate` cookbook's custom resources. The cookbook appears in the Policyfile lock but may be a vestigial dependency. This should be confirmed by inspecting the full cookbook dependency graph before finalising the Ansible `requirements.yml`.

5. **`lineinfile` custom LWRP is unused**: The custom resource at `cookbooks/nginx-multisite/resources/lineinfile.rb` does not appear to be called in any of the reviewed recipes. Assumed to be dead code; confirm before discarding.

6. **Single-node deployment**: All three cookbooks are applied to the same host in a single run-list. The Ansible migration will produce a single playbook with three roles applied to one host group. No multi-node orchestration (e.g., separate DB server, load balancer) is implied by the current configuration.

7. **No CI/CD pipeline for infrastructure**: No `.github/`, `.gitlab-ci.yml`, `Jenkinsfile`, or equivalent pipeline configuration is present. The migration plan does not include pipeline setup, but adding Molecule tests and a CI pipeline for the Ansible roles is strongly recommended.

8. **`x2a-rules/` directory contains migration-specific guidance**: The file `x2a-rules/d5872732-f37d-4221-8ddd-af1d68455083.md` has not been read but may contain additional constraints or rules for this migration. Its contents should be reviewed and incorporated before finalising the Ansible role structure.

9. **Memcached requires no authentication configuration**: The `cache` cookbook delegates entirely to the `memcached` community cookbook with no custom attributes. Memcached is assumed to be running on localhost only (no network-exposed unauthenticated instance). Confirm the bind address before migrating.

10. **FastAPI application source is externally maintained**: The `fastapi_tutorial` GitHub repository is not part of this infrastructure repo. Any changes to its `requirements.txt` or application structure will affect the provisioning outcome. The Ansible role should pin to a specific commit SHA rather than tracking `main`.
