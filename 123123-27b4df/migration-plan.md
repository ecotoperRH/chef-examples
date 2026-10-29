# MIGRATION FROM CHEF TO ANSIBLE

This document provides a high-level (10,000-foot view) architectural migration plan to transition the infrastructure automation in this repository from Chef (Chef Solo / Berkshelf) to Ansible.

The repository currently provisions an end-to-end multi-tier web application stack consisting of Nginx with multi-domain virtual hosts and SSL termination, system security hardening (UFW, Fail2ban, SSH, sysctl), caching backends (Memcached and Redis), and a Python FastAPI backend supported by a local PostgreSQL database. The migration scope encompasses 3 custom local cookbooks, their external dependencies, supporting orchestration scripts, and configuration state files.

- **Migration Complexity**: Low to Moderate (3 local cookbooks, 3 external cookbook dependencies, straightforward web and database services).
- **Estimated Timeline**: 1 to 2 weeks for role conversion, testing, validation, and Vagrant/CI integration.

---

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning into Ansible roles or collections:

### MODULE INVENTORY

- **cache**:
    - Description: Configures caching services including Memcached daemon installation and Redis server setup with authentication and custom configuration fixes.
    - Path: `cookbooks/cache`
    - Technology: Chef
    - Key Features: Memcached service provisioning via community cookbook, Redis 6379 instance configuration with password protection (`requirepass`), custom log directory creation, and Ruby regex-based Redis configuration sanitization.

- **fastapi-tutorial**:
    - Description: Provisions the full application runtime environment for a Python FastAPI tutorial service backed by a PostgreSQL database instance.
    - Path: `cookbooks/fastapi-tutorial`
    - Technology: Chef
    - Key Features: System package installations (Python 3, pip, venv, libpq, Git), PostgreSQL service initialization, database and user creation with grant privileges, application source checkout from Git, Python virtual environment setup with pip requirements installation, `.env` file templating, and systemd service unit registration with auto-start.

- **nginx-multisite**:
    - Description: High-level edge web server and security management cookbook that configures multi-tenant Nginx virtual host sites with TLS certificates and system security controls.
    - Path: `cookbooks/nginx-multisite`
    - Technology: Chef
    - Key Features: Nginx multi-domain configuration with HTTP-to-HTTPS redirect rules, automated self-signed SSL/TLS certificate generation via OpenSSL, site document root staging with default index pages, custom `lineinfile` resource provider, system firewall configuration (UFW), brute-force defense (Fail2ban), SSH daemon hardening (disabling root login and password authentication), and kernel network security parameters via sysctl (`99-security.conf`).

### Infrastructure Files

- `Berksfile`: Berkshelf dependency manifest resolving Supermarket cookbooks (`nginx ~> 12.0`, `memcached ~> 6.0`, `redisio ~> 7.2.4`) and local paths. Needs replacement with Ansible Galaxy dependencies (`requirements.yml`).
- `Vagrantfile`: Vagrant VM orchestration file configuring guest networking (IP `192.168.121.10`, ports 80->8080, 443->8443) using Libvirt provider. Must be updated to provision using the Ansible provisioner (`ansible` or `ansible_local`) instead of `vagrant-provision.sh`.
- `vagrant-provision.sh`: Shell bootstrap script that installs Chef Solo, build-essential, Berkshelf, vendors cookbooks, and executes `chef-solo`. Will be retired and replaced by an Ansible playbook runner or native Vagrant Ansible provisioning.
- `solo.rb`: Chef Solo runtime configuration declaring file cache paths and cookbook directories. Will be deprecated upon migration.
- `solo.json`: Chef Solo node attributes containing the site host definitions (`ci.cluster.local`, `status.cluster.local`, `test.cluster.local`), run-list declaration, SSL directory paths, and security flags. Will be refactored into Ansible `group_vars/all.yml` or `host_vars`.

### Target Details

- **Operating System**: Ubuntu / Debian-family Linux (explicitly supported in `metadata.rb` as Ubuntu `>= 18.04` and CentOS `>= 7.0`; underlying recipes specifically invoke `apt-get`, `ufw`, and reference Debian user `www-data`). Target OS recommended for Ansible target is **Ubuntu 22.04 LTS** (or Debian 12). *Note: Vagrantfile currently references `generic/fedora42`, which conflicts with the Debian/Ubuntu shell commands in `vagrant-provision.sh`.*
- **Virtual Machine Technology**: Vagrant with Libvirt provider (`config.vm.provider "libvirt"` with 2 vCPUs and 2048 MB RAM).
- **Cloud Platform**: Not specified / Local virtualized environment (Libvirt/KVM).

---

## Migration Approach

### Key Dependencies to Address

- **nginx (~> 12.0 Supermarket cookbook)**: Replace with standard package installation via `ansible.builtin.apt` and modular Jinja2 configuration templates, or adopt `geerlingguy.nginx` from Ansible Galaxy.
- **memcached (~> 6.0 Supermarket cookbook)**: Replace with native `ansible.builtin.apt` (`memcached` package) and `ansible.builtin.systemd` service management, or `geerlingguy.memcached`.
- **redisio (~> 7.2.4 Supermarket cookbook)**: Replace with native `redis-server` package installation and template configuration (`/etc/redis/redis.conf`), or adopt `geerlingguy.redis`. This eliminates the fragile Chef `ruby_block` regex patch used to strip legacy replica directives.
- **lineinfile custom Chef resource (`cookbooks/nginx-multisite/resources/lineinfile.rb`)**: Replace directly with the built-in Ansible module `ansible.builtin.lineinfile`, which provides full idempotency, backup capabilities, and regex substitution out of the box.

### Security Considerations

- **Vault / Secrets Management**:
  - `cookbooks/cache`: Redis authentication token (`requirepass 'redis_secure_password_123'`) is currently hardcoded in plaintext within the recipe.
  - `cookbooks/fastapi-tutorial`: Database credentials (`fastapi_password` and database connection string `postgresql://fastapi:fastapi_password@localhost/fastapi_db`) are hardcoded in plaintext in both the recipe and generated `.env` file.
  - **Remediation**: Migrate all passwords and sensitive connection URIs into an encrypted Ansible Vault (`vault.yml`) accessed via Ansible vault password or dynamic secrets provider.
- **SSL/TLS Certificates**:
  - `cookbooks/nginx-multisite`: Self-signed certificates are generated ad-hoc via raw OpenSSL commands in `recipes/ssl.rb`.
  - **Remediation**: Replace raw shell execution with Ansible's native `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` modules for development, with parameters allowing drop-in commercial or Let's Encrypt certificates in production.
- **Firewall & Security Hardening**:
  - UFW rules (default deny, allow 22/tcp, 80/tcp, 443/tcp) should be implemented using `community.general.ufw`.
  - SSH daemon hardening (`PermitRootLogin no`, `PasswordAuthentication no`) currently uses `sed` commands in Chef; migrate to `ansible.builtin.lineinfile` or dedicated SSH hardening roles (e.g., `dev-sec.ssh-hardening`).
  - Fail2ban jail configurations and kernel `sysctl` hardening parameters should be rendered using `ansible.builtin.template` and `ansible.posix.sysctl`.

### Technical Challenges

- **OS and Package Manager Discrepancy**: `Vagrantfile` specifies Fedora 42 (`generic/fedora42`), but `vagrant-provision.sh` uses `apt-get`, and `nginx-multisite` configures `ufw` and `www-data` ownership. The Ansible roles must either be strictly targeted to Ubuntu/Debian or implemented with OS-family conditionality (`ansible_os_family == "Debian"` vs `"RedHat"`).
- **PostgreSQL User & Database Provisioning**: In Chef, PostgreSQL setup uses raw `psql` shell executions with piped `CREATE USER` and `CREATE DATABASE` queries suppressed with `|| true`. This should be replaced with idempotent Ansible modules `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db`.
- **Application Deployment Idempotency**: The FastAPI tutorial uses `git clone`, Python venv creation, and pip install in separate execute blocks. In Ansible, use `ansible.builtin.git` and `ansible.builtin.pip` with `virtualenv` to manage virtualenv creation, package installations, and change tracking idempotently.
- **Redis Configuration Patching**: The Chef cookbook contains an inline Ruby block monkey-patching `/etc/redis/6379.conf` via regular expression removals. In Ansible, managing Redis via a clean Jinja2 template (`redis.conf.j2`) avoids configuration file mutations after installation.

### Migration Order

1. **Phase 1: Base Platform & Security Hardening (`security` role)**:
   - Migrate UFW firewall rules, Fail2ban configuration, sysctl network optimizations, and SSH daemon hardening.
   - Low risk, baseline requirement for server stabilization.
2. **Phase 2: Data & Caching Services (`cache` role & `postgresql` task)**:
   - Migrate Memcached and Redis configurations with templated configs and encrypted Redis authentication.
   - Provision PostgreSQL server, role, and database using `community.postgresql`.
3. **Phase 3: Application Runtime (`fastapi-tutorial` role)**:
   - Migrate Python 3 dependencies, Git repository clone, Python virtualenv provisioning, `.env` file templating, and systemd service management.
4. **Phase 4: Web Proxy & Multi-Site Routing (`nginx-multisite` role)**:
   - Migrate Nginx core installation, TLS certificate generation with `community.crypto`, dynamic virtual host templating based on site dictionaries, and index document deployments.
5. **Phase 5: Playbook Assembly & Vagrant Integration**:
   - Create top-level `site.yml` and `requirements.yml`.
   - Update `Vagrantfile` to use `generic/ubuntu2204` and the Ansible provisioner.

### Assumptions

- The target deployment environment is an Ubuntu/Debian-based distribution (recommended Ubuntu 22.04 LTS), resolving the conflict with the Fedora 42 Vagrant box image.
- Self-signed certificates generated for `ci.cluster.local`, `status.cluster.local`, and `test.cluster.local` are intended solely for local testing and will be replaced by CA-signed or automated ACME certificates in non-local environments.
- The external GitHub repository (`https://github.com/dibanez/fastapi_tutorial.git`) remains publicly accessible during host provisioning.
- Redis will run as a single standard instance rather than a multi-node cluster or replica topology, matching current solo configuration.
