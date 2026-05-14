## Chef Run List and Policy Parsing

Parse `Policyfile.rb` and `Policyfile.lock.json` to extract the full run list (`nginx-multisite::default`, `cache::default`, `fastapi-tutorial::default`) and all locked cookbook versions. Treat `Policyfile.lock.json` as the authoritative dependency manifest. Also parse `solo.json` as the authoritative source of runtime attribute overrides — its values supersede `attributes/default.rb` defaults and must be translated into Ansible `group_vars` or `host_vars`.

---

## Attribute and Variable Precedence

Identify all attribute files (`attributes/default.rb`) and compare their values against `solo.json` overrides. Document every override explicitly. For example, document root paths defined in `attributes/default.rb` as `/opt/server/{test,ci,status}` are overridden in `solo.json` to `/var/www/{test.cluster.local,ci.cluster.local,status.cluster.local}` — the `solo.json` values are canonical and must be used in the migration specification.

---

## Recipe Execution Order and Sub-Recipe Orchestration

For each cookbook, parse `default.rb` to extract the full ordered list of `include_recipe` calls and resource declarations. For `nginx-multisite`, document the five sub-recipes in order: `security` → `nginx` → `ssl` → `sites`. For `cache`, document the Memcached and Redis provisioning sequence including the post-install `ruby_block`. For `fastapi-tutorial`, document the full deployment sequence: packages → PostgreSQL → git clone → venv/pip → `.env` → systemd unit → service.

---

## External Cookbook Dependency Mapping

Map all four external Supermarket dependencies to their Ansible replacements:
- `nginx (~> 12.0, locked 12.3.1)`: dependency carrier only — replace with `ansible.builtin.package` + `ansible.builtin.template`; no community role required.
- `memcached (~> 6.0, locked 6.1.0)`: replace with `ansible.builtin.package` + `ansible.builtin.service`.
- `redisio (~> 7.2.4, locked 7.2.4)`: replace with `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service`.
- `ssl_certificate (~> 2.1, locked 2.1.0)`: present in `Policyfile.rb` but not called in any recipe — drop entirely.
- `selinux (6.2.4)`: transitive dependency of `redisio` — handle with `ansible.posix.selinux` and `community.general.seboolean` as needed.

---

## Credential and Secret Detection

Identify all hardcoded credentials in recipes and node JSON:
- `cookbooks/cache/recipes/default.rb`: Redis password `redis_secure_password_123` (hardcoded string in `requirepass` directive). Flag as **Credential 1**.
- `cookbooks/fastapi-tutorial/recipes/default.rb`: PostgreSQL user password `fastapi_password` and `DATABASE_URL=postgresql://fastapi:fastapi_password@localhost/fastapi_db` written to `.env`. Flag as **Credentials 2 and 3**.
Document that no Chef encrypted data bags or Chef Vault usage is present — secrets are stored as plain-text recipe attributes, a pre-existing security gap. All three credentials must be migrated to Ansible Vault.

---

## Ruby Block and Custom Resource Analysis

Identify and document all `ruby_block` resources and custom LWRPs:
- `ruby_block 'fix_redis_config'` in `cache::default.rb`: post-processes `/etc/redis/6379.conf` to strip five deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`). This is a workaround for `redisio 7.2.4` generating config keys incompatible with Redis 7.x. Document the exact directives to be removed.
- `resources/lineinfile.rb` in `nginx-multisite`: a custom LWRP replicating Ansible's `lineinfile` module. Verify it is not called by any recipe in the repository — if confirmed unused, flag for removal.

---

## Template Inventory and ERB Parsing

Enumerate all ERB templates in each cookbook's `templates/` directory. For each template, document: the target file path, the Chef resource that deploys it, all Ruby variables/node attributes referenced, and any conditional logic. Pay special attention to:
- `security.conf.erb`: rate-limiting zones and SSL session cache directives.
- `fail2ban.jail.local.erb`: jail definitions for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`.
- `sysctl-security.conf.erb`: 16 kernel hardening parameters.
- Nginx virtual host server block templates: per-site SSL, HTTP→HTTPS redirect, HSTS, and security headers.
- Redis config template (if present): document all directives including the five deprecated ones to be stripped.

---

## File and Static Content Discovery

Identify all files deployed via Chef `cookbook_file` or `remote_file` resources from `files/default/`. For `nginx-multisite`, document the three static `index.html` files under `files/default/{ci,status,test}/` and their target document root paths. Record file modes and ownership for all deployed files, especially:
- SSL private key directory: `0710` permissions, `ssl-cert` group.
- SSL private keys: `0640` mode, `root:ssl-cert` ownership.
- `.env` file: currently `0644` (world-readable) — flag as security issue requiring remediation to `0600`.

---

## Service and Notification Dependency Mapping

For each cookbook, map all `notifies` and `subscribes` relationships between resources. Document:
- `fastapi-tutorial`: `execute[systemd_reload]` notified immediately after writing the systemd unit file.
- `nginx-multisite`: service restart notifications triggered by config template changes.
- `security.rb`: SSH daemon restart triggered by `sshd_config` modifications via `sed` commands.
These notification chains must be translated into Ansible handler definitions.

---

## Platform and OS-Family Conditional Detection

Identify all platform-conditional logic in recipes and attributes. Document the mismatch between the declared target OS (Fedora 42 / RHEL 9) and cookbook metadata (Ubuntu ≥ 18.04, CentOS ≥ 7). Flag the following platform-specific divergences requiring `ansible_os_family` conditionals in the migration:
- `ufw` (Debian/Ubuntu) vs `firewalld` (Fedora/RHEL).
- `libpq-dev` (Debian) vs `postgresql-devel` (RHEL/Fedora).
- Nginx service user `www-data` (Debian) vs `nginx` (RHEL/Fedora).
- `python3-pip` and `python3-venv` package name variations across families.

---

## Security Hardening Resource Inventory

Fully enumerate all security hardening actions performed by `security.rb` in `nginx-multisite`:
- fail2ban installation, `jail.local` template deployment, and service enablement.
- UFW firewall rule configuration (flag platform mismatch with Fedora target).
- SSH daemon hardening via `sed` commands setting `PermitRootLogin no` and `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
- Kernel sysctl parameters: document all 16 parameters from `sysctl-security.conf.erb` (rp_filter, SYN cookies, ICMP redirect suppression, IPv6 disable, etc.).
Document the `solo.json` flags: `security.fail2ban.enabled`, `security.ufw.enabled`, `security.ssh.disable_root`, `security.ssh.password_auth`.

---

## SSL Certificate Generation Analysis

Document the self-signed certificate generation approach in `ssl.rb`: raw `openssl req -x509` shell commands generating RSA-2048 certificates per virtual host with a hardcoded subject (`/C=US/ST=Example/...`). Record:
- All three virtual host FQDNs: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`.
- Certificate and key file paths.
- The `ssl-cert` group and `0710` permissions on the private key directory.
- The hardcoded subject fields (to be parameterised as variables in the migration).
Note that `ssl_certificate` Supermarket cookbook is present in `Policyfile.rb` but not called — confirm and flag for removal.

---

## FastAPI Application Deployment Analysis

Document the full FastAPI deployment sequence in `fastapi-tutorial::default`:
- System packages: `python3`, `python3-pip`, `python3-venv`, `git`, `postgresql`, `postgresql-contrib`, `libpq-dev`.
- Git clone of `https://github.com/dibanez/fastapi_tutorial.git` at `main` branch into `/opt/fastapi-tutorial`.
- Python venv at `/opt/fastapi-tutorial/venv` and pip install from `requirements.txt`.
- PostgreSQL provisioning: user `fastapi`, database `fastapi_db`, full privileges — using `execute` with `|| true` for idempotency (flag as non-idiomatic).
- `.env` file with `DATABASE_URL` (hardcoded credentials, mode `0644` — flag both).
- systemd unit `fastapi-tutorial.service` with `User=root` (flag as security risk).
- `uvicorn app.main:app --host 0.0.0.0 --port 8000` as the service command.