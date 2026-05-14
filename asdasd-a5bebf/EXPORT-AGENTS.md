## Ansible Collection Requirements

Use the following FQCN modules and collections for this migration:
- `ansible.builtin.package`, `ansible.builtin.template`, `ansible.builtin.service`, `ansible.builtin.file`, `ansible.builtin.copy`, `ansible.builtin.git`, `ansible.builtin.lineinfile`, `ansible.builtin.replace` — for core tasks
- `community.crypto.openssl_privatekey`, `community.crypto.openssl_csr`, `community.crypto.x509_certificate` — for self-signed TLS certificate generation
- `ansible.posix.sysctl` — for kernel sysctl hardening (one task per parameter)
- `ansible.posix.firewalld` — for firewall rules on Fedora/RHEL targets
- `community.general.ufw` — for firewall rules on Ubuntu/Debian targets (secondary path)
- `ansible.posix.selinux` — for SELinux management on Fedora/RHEL
- `community.postgresql.postgresql_user`, `community.postgresql.postgresql_db` — for idempotent PostgreSQL provisioning
- All module references must use FQCN format. Declare all non-builtin collections in `requirements.yml`.

---

## Ansible Vault for Credential Management

All hardcoded secrets identified during analysis must be migrated to Ansible Vault encrypted variables. Do not store any plaintext secrets in role defaults, vars, or templates:
- Redis password (`redis_secure_password_123`) → Vault variable `vault_redis_password`
- PostgreSQL password (`fastapi_password`) → Vault variable `vault_fastapi_db_password`; inject into all three locations: PostgreSQL user creation task, `.env` file template (`DATABASE_URL`), and systemd unit environment

Vault-encrypted variables must be referenced via a wrapper variable pattern (e.g., `redis_password: "{{ vault_redis_password }}"`). Document the Vault variable names in the role's `README.md`.

---

## Security Remediation During Export

The following security issues identified during analysis must be remediated in the generated Ansible role — do not replicate the insecure Chef behavior:
- `.env` file at `/opt/fastapi-tutorial/.env`: deploy with mode `0600`, owned by the dedicated application service user (not `root`)
- FastAPI systemd unit: introduce a dedicated `fastapi` system user; set `User=fastapi` in the unit file instead of `User=root`
- SSH hardening: use `ansible.builtin.lineinfile` module (or `devsec.hardening.ssh_hardening` role) instead of `sed` for idempotent, auditable SSH configuration
- Self-signed TLS certificates: use `community.crypto` modules; note these are acceptable for development but production deployments require CA-signed or Let's Encrypt certificates

---

## ERB to Jinja2 Template Conversion

Convert all ERB templates to Jinja2 with the following rules:
- ERB `<%= variable %>` → Jinja2 `{{ variable }}`
- ERB `<% if condition %>` → Jinja2 `{% if condition %}`
- ERB `<% end %>` → Jinja2 `{% endif %}`
- ERB `<% array.each do |item| %>` → Jinja2 `{% for item in array %}`
- `nginx.conf.erb`: parameterise the hardcoded `user www-data;` — use a variable (e.g., `nginx_worker_user`) defaulting to `nginx` for RHEL/Fedora and `www-data` for Debian/Ubuntu
- `site.conf.erb`: replicate the conditional SSL block faithfully in Jinja2; preserve HTTP→HTTPS redirect, TLS 1.2/1.3 enforcement, HSTS, and full security-header suite
- `sysctl-security.conf.erb` and `jail.local`: these are fully static — deploy as plain templates or files

---

## Multi-Site Nginx Vhost Loop

Reproduce the `node['nginx']['sites']` iteration as an Ansible `loop` over a `nginx_sites` list variable (sourced from `group_vars`). The loop must cover:
- `ansible.builtin.file`: create document root directories
- `ansible.builtin.copy`: deploy static HTML content files for each vhost (`ci/`, `status/`, `test/`)
- `ansible.builtin.template`: generate per-site `site.conf` from the Jinja2-converted template
- `ansible.builtin.file`: create `sites-enabled` symlinks pointing to `sites-available/<site>.conf`

Use `/var/www/<site>/` as the canonical document root path (from `solo.json`, not `attributes/default.rb`).

---

## Redis Config Directive Removal

Replace the `ruby_block` config-patching hack from `cache/recipes/default.rb` with one of the following approaches (preferred first):
1. **Preferred**: Template the Redis configuration file directly, bypassing the community role's template entirely, and omit the five deprecated directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from the template
2. **Alternative**: Use a loop of `ansible.builtin.replace` or `ansible.builtin.lineinfile` tasks with `regexp` patterns to remove each directive from `/etc/redis/6379.conf` post-install

Document which approach is used and why. Ensure the directive-removal logic is preserved — the target Redis version triggers this incompatibility.

---

## Platform Conditional Handling

Apply explicit platform conditionals for all OS-divergent tasks:
- Firewall management: `when: ansible_os_family == 'RedHat'` for `ansible.posix.firewalld` tasks; `when: ansible_os_family == 'Debian'` for `community.general.ufw` tasks
- Nginx worker user: set `nginx_worker_user` variable to `nginx` for RedHat family, `www-data` for Debian family
- The primary tested path is Fedora 42 / RHEL-family. Ubuntu support is secondary.
- Do not silently skip platform-specific tasks — use explicit `when` conditions so failures are visible.

---

## PostgreSQL Idempotency

Replace all `psql` shell commands (with `|| true` guards) from `fastapi-tutorial` with natively idempotent Ansible modules:
- `community.postgresql.postgresql_user`: create user `fastapi` with the Vault-sourced password
- `community.postgresql.postgresql_db`: create database `fastapi_db`
- Grant privileges using the `priv` parameter of `community.postgresql.postgresql_user`

Do not use `ansible.builtin.shell` or `ansible.builtin.command` for PostgreSQL provisioning.

---

## Git-Based Application Deployment and pip Install Handler

Use `ansible.builtin.git` with `update: yes` to clone/sync `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`) into `/opt/fastapi-tutorial`. Register the task result and trigger a handler to re-run `pip install -r requirements.txt` only when the git task reports a change. This ensures pip install does not re-run on every playbook execution.

---

## Systemd Service Management

For the FastAPI systemd unit (`fastapi-tutorial.service`):
- Deploy the unit file via `ansible.builtin.template`
- Trigger `systemctl daemon-reload` via a handler notified on unit file change (do not run daemon-reload unconditionally)
- Set `User=fastapi` (dedicated system user, not `root`) in the unit file
- Use `ansible.builtin.systemd` module to enable and start the service

For Redis: use `redisio::enable` equivalent — ensure the Redis service is enabled and started after configuration.

---

## SELinux Configuration on Fedora/RHEL

On Fedora 42 / RHEL targets where SELinux is enforcing by default, include SELinux tasks:
- Set required SELinux booleans (e.g., `httpd_can_network_connect` for Nginx reverse proxy)
- Apply correct SELinux port labels for Redis (port 6379)
- Ensure Redis can write to `/var/log/redis` with correct SELinux file context
- Use `ansible.posix.seboolean` and `ansible.posix.sefcontext` modules
- Assume basic boolean adjustments are sufficient — no custom policy module compilation is required

---

## Variable Files and group_vars Structure

Source all variable values from `solo.json` as the canonical reference for `group_vars` / `host_vars`:
- Site definitions (vhost names, document roots, SSL flags) → `group_vars/all/nginx.yml`
- SSL certificate/key paths → `group_vars/all/ssl.yml`
- Security flags (fail2ban, SSH hardening, sysctl) → `group_vars/all/security.yml`
- Vault-encrypted secrets → `group_vars/all/vault.yml` (encrypted)
- Wrapper variables referencing Vault variables → `group_vars/all/vars.yml`

Do not duplicate attribute defaults from `attributes/default.rb` where `solo.json` provides an override.

---

## requirements.yml and Galaxy Role Dependencies

Generate a `requirements.yml` declaring all external Ansible Galaxy roles and collections needed:
- Collections: `community.crypto`, `ansible.posix`, `community.general`, `community.postgresql`
- Roles (as applicable): `nginxinc.nginx` or `geerlingguy.memcached`, `geerlingguy.redis`, `geerlingguy.selinux`
- Do NOT include an entry for `ssl_certificate` — it is a vestigial Chef dependency confirmed unused in any recipe
- Pin versions in `requirements.yml` to match the stability level of the locked Chef cookbook versions

---

## Vagrant Compatibility for Local Testing

Structure Ansible playbooks for general-purpose deployment (not Vagrant-specific). Provide a Vagrant-compatible inventory as a convenience for local testing. The `Vagrantfile` can be updated to replace the `shell` provisioner with an `ansible_local` or `ansible` provisioner. Preserve the existing VM configuration: `generic/fedora42` box, libvirt provider, 2 vCPU / 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443.

---

## Idempotency and Task Ordering

Ensure all generated tasks are idempotent:
- Use `ansible.builtin.package` (not shell commands) for package installation
- Use `ansible.builtin.file` with `state: directory` for directory creation
- Use `ansible.builtin.systemd` for service management
- Avoid `ansible.builtin.shell` or `ansible.builtin.command` except where no module equivalent exists; when used, add `changed_when` and `failed_when` conditions
- Respect the migration order in task file structure: security hardening → cache → nginx-multisite → fastapi-tutorial, reflecting the run list dependency chain