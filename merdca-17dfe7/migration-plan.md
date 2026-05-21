# Migration Plan: Chef → Ansible

## Executive Summary

This repository contains a Chef-based infrastructure stack (`nginx-multisite-policy`) that provisions a multi-site Nginx web server with SSL, OS-level security hardening, caching services (Memcached and Redis), and a Python FastAPI application backed by PostgreSQL. The run list is defined in `Policyfile.rb` and executed via `chef-solo` inside a Fedora 42 Vagrant VM (libvirt provider, 2 vCPU / 2 GB RAM, private IP `192.168.121.10`).

The repository contains **3 local cookbooks** and **5 external Supermarket cookbook dependencies** (locked in `Policyfile.lock.json`). All three local cookbooks are version `1.0.0` and target Ubuntu ≥ 18.04 and CentOS ≥ 7.0. Migration complexity is **medium**, estimated at **3–4 weeks** including testing.

---

## Module Inventory

| # | Cookbook | Path | Version | Description | Complexity |
|---|----------|------|---------|-------------|------------|
| 1 | `nginx-multisite` | `cookbooks/nginx-multisite` | 1.0.0 | Nginx installation, multi-site virtual host configuration, self-signed SSL certificate generation, and OS security hardening (fail2ban, ufw, sysctl, SSH) | High |
| 2 | `cache` | `cookbooks/cache` | 1.0.0 | Memcached and Redis installation and configuration; Redis uses password authentication; includes a post-install config-file patch hack | Medium |
| 3 | `fastapi-tutorial` | `cookbooks/fastapi-tutorial` | 1.0.0 | Python FastAPI application deployment from GitHub, Python venv setup, PostgreSQL database/user provisioning, `.env` file creation, and systemd service unit | Medium |

### External Cookbook Dependencies (locked versions)

| Cookbook | Locked Version | Role | Ansible Replacement |
|----------|---------------|------|---------------------|
| `nginx` | 12.3.1 | Nginx package/service wrapper used by `nginx-multisite` | `ansible.builtin.package` + `ansible.builtin.service` |
| `memcached` | 6.1.0 | Memcached package/service wrapper used by `cache` | `ansible.builtin.package` + `ansible.builtin.service` |
| `redisio` | 7.2.4 | Redis install, config templating, and service management used by `cache` | `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service` |
| `ssl_certificate` | 2.1.0 | SSL cert helper (referenced in `Policyfile.rb`; actual cert generation is done inline via `openssl` CLI in `ssl.rb`) | `community.crypto.openssl_privatekey` + `community.crypto.x509_certificate` |
| `selinux` | 6.2.4 | Transitive dependency of `redisio`; manages SELinux state | `ansible.posix.selinux` |

---

## Infrastructure Files

| File | Purpose | Ansible Equivalent |
|------|---------|--------------------|
| `Policyfile.rb` | Defines policy name `nginx-multisite-policy`, run list, and cookbook source constraints | `site.yml` playbook with `roles:` list |
| `Policyfile.lock.json` | Pins exact cookbook versions (revision IDs included) | `requirements.yml` with pinned collection/role versions |
| `Berksfile` | Berkshelf dependency resolver; points to local paths and Chef Supermarket | `requirements.yml` (Ansible Galaxy) |
| `solo.json` | Node-level JSON attributes: site map, SSL paths, security flags | `group_vars/all.yml` or `host_vars/<host>.yml` |
| `solo.rb` | Chef Solo runtime config: cache path, cookbook path, log level | `ansible.cfg` |
| `Vagrantfile` | Vagrant VM definition: `generic/fedora42`, libvirt, 2 vCPU/2 GB, IP `192.168.121.10`, ports 80→8080 and 443→8443 | `inventory/hosts.yml` + `vagrant` inventory plugin or static inventory |
| `vagrant-provision.sh` | Bootstrap script: installs Chef, Berkshelf, vendors cookbooks, runs `chef-solo` | Replaced by `ansible-playbook` invocation; Vagrant `ansible` provisioner |
| `cookbooks/nginx-multisite/attributes/default.rb` | Default attribute values for sites, SSL paths, and security flags | `roles/nginx-multisite/defaults/main.yml` |
| `cookbooks/nginx-multisite/resources/lineinfile.rb` | Custom LWRP that replicates `lineinfile` behaviour with backup support | `ansible.builtin.lineinfile` (native module) |
| `cookbooks/nginx-multisite/templates/default/*.erb` | ERB templates: `nginx.conf`, `security.conf`, `site.conf`, `fail2ban.jail.local`, `sysctl-security.conf` | Jinja2 templates in `roles/nginx-multisite/templates/` |
| `cookbooks/nginx-multisite/files/default/{ci,status,test}/index.html` | Static site content for three virtual hosts | `roles/nginx-multisite/files/{ci,status,test}/index.html` |

---

## Target Details

| Property | Value |
|----------|-------|
| **Operating System (dev/Vagrant)** | Fedora 42 (`generic/fedora42`) |
| **Declared OS support (metadata.rb)** | Ubuntu ≥ 18.04, CentOS ≥ 7.0 |
| **Hypervisor** | libvirt (KVM) |
| **VM Resources** | 2 vCPU, 2 GB RAM |
| **Private Network IP** | `192.168.121.10` |
| **Forwarded Ports** | 80 → 8080 (HTTP), 443 → 8443 (HTTPS) |
| **Virtual Hosts** | `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` |
| **Document Roots** | `/opt/server/test`, `/opt/server/ci`, `/opt/server/status` (attributes); `solo.json` overrides to `/var/www/<site>` |
| **SSL Certificate Path** | `/etc/ssl/certs/<site>.crt` |
| **SSL Private Key Path** | `/etc/ssl/private/<site>.key` |
| **FastAPI App Path** | `/opt/fastapi-tutorial` |
| **FastAPI Source Repo** | `https://github.com/dibanez/fastapi_tutorial.git` (branch: `main`) |
| **FastAPI Service Port** | `8000` (uvicorn, `0.0.0.0`) |
| **PostgreSQL DB** | `fastapi_db`, owner `fastapi`, password `fastapi_password` |
| **Redis Port / Password** | `6379` / `redis_secure_password_123` |
| **Chef Version Required** | ≥ 16.0 |
| **Ansible Minimum Version** | 2.14+ recommended (for `community.crypto` and `ansible.posix` collections) |

---

## Key Dependencies

### Inter-Cookbook Dependencies (run-list order matters)

```
nginx-multisite::default
  └── nginx-multisite::security   (fail2ban, ufw, sysctl, SSH hardening)
  └── nginx-multisite::nginx      (package, nginx.conf, security.conf, document roots, static files)
  └── nginx-multisite::ssl        (openssl CLI → self-signed certs per site)
  └── nginx-multisite::sites      (sites-available configs, symlinks to sites-enabled, remove default)

cache::default
  └── memcached (external cookbook 6.1.0)
  └── redisio   (external cookbook 7.2.4)
        └── selinux (external cookbook 6.2.4, transitive)

fastapi-tutorial::default
  └── postgresql (system package, no external cookbook)
  └── git clone  (https://github.com/dibanez/fastapi_tutorial.git)
  └── python3-venv + pip install -r requirements.txt
  └── systemd unit (After=postgresql.service)
```

### Service Start-Order Dependencies

1. `postgresql` must be running before `fastapi-tutorial` service starts (enforced via `After=postgresql.service` in the systemd unit).
2. `nginx` must be started after SSL certificates exist (Chef `notifies :reload` chain; in Ansible, use `handlers` and task ordering).
3. `fail2ban` must be configured before it is started (jail.local template → restart handler).
4. `sysctl` settings must be applied before network-facing services start.

### External Network Dependencies

- Chef Supermarket (`supermarket.chef.io`) — replaced by Ansible Galaxy in migration.
- GitHub (`github.com/dibanez/fastapi_tutorial.git`) — required at provision time for `git` module.
- `omnitruck.chef.io` — only needed during Chef bootstrap; not needed post-migration.

---

## Security Considerations

### Secrets Requiring Ansible Vault Protection

| Secret | Current Location | Risk | Ansible Vault Action |
|--------|-----------------|------|----------------------|
| Redis password `redis_secure_password_123` | Plaintext in `cookbooks/cache/recipes/default.rb` | **HIGH** — committed to source control | Move to `vault.yml`; reference as `{{ vault_redis_password }}` |
| PostgreSQL user password `fastapi_password` | Plaintext in `cookbooks/fastapi-tutorial/recipes/default.rb` and written to `/opt/fastapi-tutorial/.env` | **HIGH** — committed to source control | Move to `vault.yml`; reference as `{{ vault_postgres_password }}` |
| PostgreSQL `DATABASE_URL` in `.env` | Plaintext in recipe, written to disk as mode `0644` | **HIGH** — world-readable on disk | Vault-encrypt value; deploy `.env` with mode `0600` |
| SSL private keys | Generated on-host at `/etc/ssl/private/<site>.key`, mode `640`, group `ssl-cert` | Medium — self-signed, dev only | For production: store CA-signed keys in Vault; for dev: keep generated |

### Hardening Settings to Preserve

| Setting | Source File | Ansible Module |
|---------|-------------|----------------|
| `PermitRootLogin no` | `security.rb` (sed on sshd_config) | `ansible.builtin.lineinfile` |
| `PasswordAuthentication no` | `security.rb` (sed on sshd_config) | `ansible.builtin.lineinfile` |
| UFW default deny + allow SSH/HTTP/HTTPS | `security.rb` | `community.general.ufw` |
| fail2ban jails: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch | `fail2ban.jail.local.erb` | `ansible.builtin.template` → `/etc/fail2ban/jail.local` |
| sysctl: rp_filter, no ICMP redirects, no source routing, SYN cookies, IPv6 disabled | `sysctl-security.conf.erb` | `ansible.posix.sysctl` (one task per key) or `ansible.builtin.template` → `/etc/sysctl.d/99-security.conf` |
| Nginx: `server_tokens off`, rate limiting zones, TLS 1.2/1.3 only, strong cipher suite, HSTS, security headers | `security.conf.erb`, `site.conf.erb` | `ansible.builtin.template` (direct port of ERB → Jinja2) |
| SSL: TLSv1.2 + TLSv1.3, ECDHE cipher preference, session cache | `site.conf.erb` | Preserved in Jinja2 template |

### `.env` File Permissions

The Chef recipe creates `/opt/fastapi-tutorial/.env` with mode `0644` (world-readable). The Ansible equivalent **must** use mode `0600` and owner `root` (or a dedicated service account) to prevent credential exposure.

---

## Technical Challenges

### 1. Custom `lineinfile` LWRP → Native Ansible Module
- **Chef**: `cookbooks/nginx-multisite/resources/lineinfile.rb` implements a custom resource that reads a file, applies a regex substitution or appends a line, and optionally writes a timestamped backup.
- **Ansible**: `ansible.builtin.lineinfile` provides identical functionality natively (`regexp:`, `line:`, `backup:` parameters). The custom resource can be dropped entirely.

### 2. Redis Config Post-Install Patch Hack
- **Chef**: `cache/recipes/default.rb` contains an explicit `ruby_block "fix_redis_config"` that strips deprecated `replica-*` and `client-output-buffer-limit` directives from `/etc/redis/6379.conf` after `redisio` writes it. This is a workaround for a version mismatch between `redisio 7.2.4` and the installed Redis binary.
- **Ansible**: Since `redisio` is not used, the Ansible role will write a clean Redis configuration template directly (no post-patch needed). The template must omit the deprecated directives from the start.

### 3. Multi-Site Nginx Virtual Host Loop
- **Chef**: `sites.rb` and `nginx.rb` iterate over `node['nginx']['sites']` hash to create document roots, deploy static files, render per-site `site.conf.erb` templates, and create `sites-enabled` symlinks.
- **Ansible**: Use `ansible.builtin.template` and `ansible.builtin.file` inside a `loop:` over a `nginx_sites` list variable. The Jinja2 template is a direct port of `site.conf.erb` (replace `<%= @var %>` with `{{ var }}` and `<% if @ssl_enabled %>` with `{% if ssl_enabled %}`).

### 4. SSL Certificate Generation Idempotency
- **Chef**: `ssl.rb` uses `not_if { ::File.exist?(cert_file) && ::File.exist?(key_file) }` to skip regeneration.
- **Ansible**: Use `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` with `force: false` (default). These modules are idempotent by design and produce equivalent output to the `openssl req -x509` command used in the recipe.

### 5. UFW on Fedora (Target OS Mismatch)
- **Chef**: `security.rb` installs `ufw` (a Debian/Ubuntu tool). The Vagrant box is `generic/fedora42`, which uses `firewalld` by default. The Chef recipe installs `ufw` on Fedora anyway.
- **Ansible**: Decide at migration time whether to use `community.general.ufw` (requires `ufw` package on Fedora) or switch to `ansible.posix.firewalld` (native to Fedora/RHEL). If Ubuntu/CentOS support is required, use a conditional: `when: ansible_os_family == 'Debian'` for ufw and `when: ansible_os_family == 'RedHat'` for firewalld.

### 6. SSH Service Name Difference
- **Chef**: `security.rb` notifies `service[ssh]`. On Fedora/RHEL the service is named `sshd`, not `ssh`.
- **Ansible**: Use `ansible_facts['services']` detection or set `ssh_service_name: "{{ 'sshd' if ansible_os_family == 'RedHat' else 'ssh' }}"` as a variable.

### 7. PostgreSQL Idempotent User/DB Creation
- **Chef**: `fastapi-tutorial/recipes/default.rb` uses `|| true` shell guards to suppress errors on duplicate creation.
- **Ansible**: Use `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent and do not require shell hacks.

### 8. FastAPI Running as Root
- **Chef**: The systemd unit sets `User=root`. This is a security risk.
- **Ansible**: Create a dedicated `fastapi` system user and run the service under that account. Update `WorkingDirectory`, `Environment`, and file ownership accordingly.

### 9. `vagrant-provision.sh` Uses `apt-get` on Fedora
- The provisioning script calls `apt-get update` and `apt-get install -y build-essential`, which will fail on Fedora 42 (which uses `dnf`). This is a latent bug in the current repo. The Ansible playbook must use `ansible.builtin.package` (OS-agnostic) or explicit `ansible.builtin.dnf`/`ansible.builtin.apt` tasks with `when:` guards.

---

## Migration Order

Migration should proceed in the following sequence to respect service dependencies and allow incremental validation at each stage.

### Phase 1 — Security Hardening (from `nginx-multisite::security`)
**Ansible Role**: `roles/security`

Tasks to implement:
1. Install `fail2ban` and `ufw` (or `firewalld` on Fedora/RHEL)
2. Deploy `/etc/fail2ban/jail.local` from Jinja2 template (port of `fail2ban.jail.local.erb`)
3. Enable and start `fail2ban` service
4. Configure UFW/firewalld: default deny, allow SSH (22), HTTP (80), HTTPS (443)
5. Deploy `/etc/sysctl.d/99-security.conf` from Jinja2 template (port of `sysctl-security.conf.erb`)
6. Apply sysctl settings (`ansible.posix.sysctl` or `command: sysctl -p`)
7. Harden SSH: `PermitRootLogin no`, `PasswordAuthentication no` via `lineinfile`; notify `sshd`/`ssh` handler

**Validation**: `ufw status`, `fail2ban-client status`, `sysctl net.ipv4.conf.all.rp_filter`, `grep PermitRootLogin /etc/ssh/sshd_config`

---

### Phase 2 — Nginx + SSL + Virtual Hosts (from `nginx-multisite::nginx`, `::ssl`, `::sites`)
**Ansible Role**: `roles/nginx-multisite`

Tasks to implement:
1. Install `nginx`, `openssl`, `ca-certificates` packages
2. Create `ssl-cert` group
3. Create `/etc/ssl/certs` (mode `0755`) and `/etc/ssl/private` (mode `0710`, group `ssl-cert`)
4. Generate per-site self-signed certificates using `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` (loop over `nginx_sites`)
5. Deploy `/etc/nginx/nginx.conf` from Jinja2 template (port of `nginx.conf.erb`)
6. Deploy `/etc/nginx/conf.d/security.conf` from Jinja2 template (port of `security.conf.erb`)
7. Create document root directories (`/opt/server/<site>` or `/var/www/<site>`) with owner `www-data`
8. Deploy `index.html` static files for each site from `files/{ci,status,test}/index.html`
9. Deploy per-site vhost configs to `/etc/nginx/sites-available/<site>` from Jinja2 template (port of `site.conf.erb`)
10. Create symlinks `/etc/nginx/sites-enabled/<site>` → `sites-available/<site>`
11. Remove `/etc/nginx/sites-enabled/default`
12. Enable and start `nginx` service; define `reload nginx` handler

**Variables** (from `attributes/default.rb` and `solo.json`):
```yaml
nginx_sites:
  - name: test.cluster.local
    document_root: /opt/server/test
    ssl_enabled: true
  - name: ci.cluster.local
    document_root: /opt/server/ci
    ssl_enabled: true
  - name: status.cluster.local
    document_root: /opt/server/status
    ssl_enabled: true
nginx_ssl_certificate_path: /etc/ssl/certs
nginx_ssl_private_key_path: /etc/ssl/private
```

**Validation**: `nginx -t`, `curl -k https://test.cluster.local`, check HTTP→HTTPS redirect, verify security headers

---

### Phase 3 — Caching Services (from `cache::default`)
**Ansible Role**: `roles/cache`

Tasks to implement:
1. Install and start `memcached` service (package name: `memcached`)
2. Install `redis` package
3. Create `/var/log/redis` directory (owner `redis`, mode `0755`)
4. Deploy clean `/etc/redis/redis.conf` (or `/etc/redis/6379.conf`) Jinja2 template — **omit all deprecated `replica-*` directives** (eliminates the `fix_redis_config` hack)
5. Set `requirepass {{ vault_redis_password }}` in template
6. Enable and start `redis` service; define `restart redis` handler

**Vault variables**:
```yaml
# ansible-vault encrypted
vault_redis_password: redis_secure_password_123
```

**Validation**: `redis-cli -a <password> ping` → `PONG`, `memcached-tool 127.0.0.1:11211 stats`

---

### Phase 4 — FastAPI Application (from `fastapi-tutorial::default`)
**Ansible Role**: `roles/fastapi-tutorial`

Tasks to implement:
1. Install system packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev` (Debian) / `python3-devel`, `postgresql-server`, `postgresql-contrib` (RHEL/Fedora)
2. Create dedicated `fastapi` system user (replaces running as `root`)
3. Create `/opt/fastapi-tutorial` directory (owner `fastapi`)
4. Clone `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) using `ansible.builtin.git`
5. Create Python venv: `python3 -m venv /opt/fastapi-tutorial/venv`
6. Install pip dependencies: `pip install -r /opt/fastapi-tutorial/requirements.txt`
7. Enable and start `postgresql` service
8. Initialize PostgreSQL data directory if needed (Fedora: `postgresql-setup --initdb`)
9. Create PostgreSQL user `fastapi` with `{{ vault_postgres_password }}` using `community.postgresql.postgresql_user`
10. Create PostgreSQL database `fastapi_db` owned by `fastapi` using `community.postgresql.postgresql_db`
11. Deploy `/opt/fastapi-tutorial/.env` from template with mode `0600`, owner `fastapi` (contains `DATABASE_URL` with vault password)
12. Deploy `/etc/systemd/system/fastapi-tutorial.service` (update `User=fastapi`; preserve `After=postgresql.service`)
13. Run `systemctl daemon-reload`
14. Enable and start `fastapi-tutorial` service

**Vault variables**:
```yaml
# ansible-vault encrypted
vault_postgres_password: fastapi_password
```

**Validation**: `systemctl status fastapi-tutorial`, `curl http://localhost:8000/docs`, `psql -U fastapi -d fastapi_db -c '\l'`

---

### Suggested Ansible Project Layout

```
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml                  # Vagrant host: 192.168.121.10
│   └── group_vars/
│       ├── all.yml                # Non-secret variables
│       └── vault.yml              # ansible-vault encrypted secrets
├── site.yml                       # Master playbook (mirrors Policyfile run_list)
├── roles/
│   ├── security/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   ├── fail2ban.jail.local.j2
│   │   │   └── sysctl-security.conf.j2
│   │   └── defaults/main.yml
│   ├── nginx-multisite/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   ├── nginx.conf.j2
│   │   │   ├── security.conf.j2
│   │   │   └── site.conf.j2
│   │   ├── files/
│   │   │   ├── ci/index.html
│   │   │   ├── status/index.html
│   │   │   └── test/index.html
│   │   └── defaults/main.yml
│   ├── cache/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   └── redis.conf.j2
│   │   └── defaults/main.yml
│   └── fastapi-tutorial/
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/
│       │   ├── fastapi.env.j2
│       │   └── fastapi-tutorial.service.j2
│       └── defaults/main.yml
└── requirements.yml               # community.crypto, community.general,
                                   # community.postgresql, ansible.posix
```

---

## Assumptions

1. **Target OS remains Fedora 42** for the Vagrant development environment. The Ansible roles will include `when:` conditionals to also support Ubuntu ≥ 18.04 and CentOS/RHEL ≥ 7 as declared in `metadata.rb`.
2. **Self-signed certificates are acceptable for development**. The `community.crypto` modules will replicate the existing `openssl req -x509` behaviour. Production deployments should substitute CA-signed certificates (e.g., Let's Encrypt via `community.crypto.acme_certificate`).
3. **The `solo.json` document root override** (`/var/www/<site>`) takes precedence over the `attributes/default.rb` value (`/opt/server/<site>`). The Ansible `defaults/main.yml` will use `/opt/server/<site>` as the default, matching the attribute file, and the inventory `group_vars` can override to `/var/www/<site>` to match `solo.json` behaviour.
4. **The `fix_redis_config` ruby_block hack** is a workaround for `redisio 7.2.4` writing deprecated Redis directives. Since Ansible will not use `redisio`, a clean template will be written directly and this hack is not needed.
5. **The `vagrant-provision.sh` script uses `apt-get`** on a Fedora host — this is a latent bug. Post-migration, the Vagrant provisioner will be switched to `ansible` type, eliminating the shell script entirely.
6. **The FastAPI application repository** at `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) will remain publicly accessible during and after migration.
7. **Redis and Memcached are single-instance, non-clustered**. No sentinel, cluster, or replication configuration is required.
8. **PostgreSQL does not require remote access**. The FastAPI app connects via `localhost`; no `pg_hba.conf` changes for remote hosts are needed.
9. **The `selinux` transitive dependency** (from `redisio`) will be handled by `ansible.posix.selinux` if SELinux is enforcing on the target. On Fedora 42 with default settings, SELinux is enforcing; the role should set the appropriate boolean (`httpd_can_network_connect`) if nginx proxying to FastAPI is added in future.
10. **Ansible Vault** will be used for all secrets currently hardcoded in recipes. The vault file will be committed encrypted; the vault password will be managed out-of-band (e.g., CI secret, `--vault-password-file`).
11. **The custom `lineinfile` LWRP** (`resources/lineinfile.rb`) has no unique logic beyond what `ansible.builtin.lineinfile` provides natively. It will not be ported as a custom module.
12. **The FastAPI service will be run as a dedicated `fastapi` system user** rather than `root` as currently configured in the Chef recipe, correcting the existing security misconfiguration.
