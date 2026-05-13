## Ansible Collection Usage Policy

Use fully-qualified collection names (FQCN) for all modules. Required collections for this migration:
- `ansible.builtin`: `package`, `template`, `service`, `file`, `copy`, `lineinfile`, `git`, `systemd`, `user`, `command`, `shell`.
- `ansible.posix`: `sysctl`, `firewalld`, `selinux`.
- `community.crypto`: `openssl_privatekey`, `openssl_csr`, `x509_certificate`, `acme_certificate` (for future production PKI).
- `community.general`: `ufw` (Ubuntu conditional only), `sefcontext`.
- `community.postgresql`: `postgresql_user`, `postgresql_db`.
Declare all non-builtin collections in `requirements.yml` for Ansible Galaxy installation. Do not use short module names.

---

## Ansible Vault for Credential Protection

All hardcoded credentials from the Chef source must be migrated to Ansible Vault encrypted variables. Do not store any secret in plaintext in any role file, `group_vars`, `host_vars`, or template:
- Redis password (`redis_secure_password_123`) → Vault variable `vault_redis_password`.
- PostgreSQL password (`fastapi_password`) → Vault variable `vault_fastapi_db_password`.
Reference Vault variables in templates and tasks via their Vault variable names. The `.env` file for the FastAPI application must be rendered from a Jinja2 template using `vault_fastapi_db_password` and deployed with file mode `0600` (not `0644`).

---

## Role and Playbook Structure

Create a new `ansible/` directory from scratch with the following structure: `roles/`, `playbooks/`, `inventory/`, `group_vars/`, `host_vars/`. Generate one Ansible role per Chef cookbook: `nginx_multisite`, `cache`, `fastapi_tutorial`. The main playbook must apply roles in the order that preserves the Chef run list sequence: `cache` → `nginx_multisite` → `fastapi_tutorial`. Translate all `solo.json` attribute overrides into `group_vars/all.yml` or appropriate `host_vars` files. Use the `solo.json` values as authoritative (e.g., document roots `/var/www/<site>`).

---

## ERB to Jinja2 Template Conversion

Convert all ERB templates to Jinja2 with the following mapping rules:
- `<%= node['key'] %>` → `{{ variable_name }}`
- `<% if condition %>` → `{% if condition %}`
- `<% node['sites'].each do |name, site| %>` → `{% for site in nginx_sites %}`
- Ruby string interpolation `#{var}` → `{{ var }}`
Place all converted templates in the role's `templates/` directory with a `.j2` extension. Fully static templates (no variable interpolation, e.g., `sysctl-security.conf.erb`, `jail.local`) may be placed in `files/` and deployed with `ansible.builtin.copy` instead of `ansible.builtin.template`. Verify each converted template for correct Jinja2 syntax before finalizing.

---

## Multi-Site Nginx Loop Implementation

Implement the data-driven multi-site pattern using an Ansible `loop` over a `nginx_sites` list variable defined in `group_vars`. Convert the Chef attribute hash (keyed by site name) to a list of dicts with explicit keys (e.g., `name`, `document_root`, `ssl_cert`, `ssl_key`, `ssl_enabled`). The three sites are `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, all with `ssl_enabled: true` and document roots at `/var/www/<site>`. Use `loop` with `ansible.builtin.template` for virtual host config generation, `ansible.builtin.file` for document root creation, and `community.crypto` modules for per-site certificate generation.

---

## Redis Configuration Template — Deprecated Directive Elimination

The Ansible-managed Redis configuration template must not include the following deprecated directives that were patched out by the Chef `ruby_block` workaround: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`. Audit the Redis version available on Fedora 42 and include only directives valid for that version. The `requirepass` directive must be set using the `vault_redis_password` Vault variable. By owning the full template, the post-install patching workaround is eliminated entirely.

---

## Firewall Management — Fedora vs. Ubuntu Conditional Handling

The Chef `security.rb` recipe uses `ufw` (Debian/Ubuntu frontend), which is incompatible with Fedora 42's default `firewalld`. In the Ansible `nginx_multisite` role:
- Use `ansible.posix.firewalld` for Fedora/RHEL targets (primary target).
- Use `community.general.ufw` conditionally for Ubuntu targets (secondary goal).
Implement platform detection via `ansible_os_family` conditionals or separate variable files (`vars/RedHat.yml`, `vars/Debian.yml`). Document all ports that must be opened (80, 443, 22 at minimum) based on the UFW rules found in the Chef recipe.

---

## SSL Certificate Generation with community.crypto

Replace the raw `openssl req` shell commands in `ssl.rb` with idempotent `community.crypto` module tasks:
1. `community.crypto.openssl_privatekey` — generate the private key.
2. `community.crypto.openssl_csr` — generate the certificate signing request.
3. `community.crypto.x509_certificate` — self-sign the certificate.
Run these tasks in a loop over `nginx_sites` to generate per-site certificates. Use the SSL cert/key paths from `solo.json` as the target paths. These are development-only self-signed certificates; note in role documentation that `community.crypto.acme_certificate` should be used for production environments.

---

## SSH Hardening — Replace sed with lineinfile or Template

The Chef `security.rb` recipe modifies `/etc/ssh/sshd_config` using `sed` commands in `execute` resources. Replace these with `ansible.builtin.lineinfile` tasks (one per directive) or a full `ansible.builtin.template` for `sshd_config` to ensure idempotency and auditability. At minimum, the following directives must be managed: `PermitRootLogin no`, `PasswordAuthentication no` (as declared in `solo.json`). Notify a handler to restart `sshd` on any change.

---

## PostgreSQL Initialization and Idempotent Provisioning

In the `fastapi_tutorial` role, include a task to initialize the PostgreSQL data directory on RHEL-family systems before starting the service:
```yaml
- name: Initialize PostgreSQL database
  ansible.builtin.command: postgresql-setup --initdb
  args:
    creates: /var/lib/pgsql/data/PG_VERSION
  when: ansible_os_family == 'RedHat'
```
Replace the `psql` shell commands (with `|| true` error suppression) with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules, which are natively idempotent. Use `vault_fastapi_db_password` for the database user password.

---

## FastAPI Application Security Remediation

The Chef recipe runs the FastAPI service as `User=root` in the systemd unit — this must be remediated during migration:
1. Create a dedicated unprivileged system user (e.g., `fastapi`) using `ansible.builtin.user` with `system: yes`.
2. Set `User=fastapi` and `Group=fastapi` in the systemd unit template.
3. Ensure the application directory and venv are owned by the `fastapi` user.
4. Deploy the `.env` file with mode `0600` (not `0644`) owned by the `fastapi` user.
The `.env` file must be rendered from a Jinja2 template using `vault_fastapi_db_password` for the `DATABASE_URL` value.

---

## systemd Handler Pattern

Replace the Chef `execute[systemd_reload]` immediate notification pattern with an Ansible handler:
```yaml
# handlers/main.yml
- name: Reload systemd daemon
  ansible.builtin.systemd:
    daemon_reload: yes
```
Notify this handler from any task that deploys or modifies a systemd unit file. Additionally, define service restart handlers (e.g., `Restart nginx`, `Restart redis`, `Restart fastapi-tutorial`) that are notified by their respective config template tasks. Handlers must be defined in each role's `handlers/main.yml`.

---

## Cross-Platform Package Variable Files

Create platform-specific variable files within each role to handle package name differences between Fedora/RHEL and Debian/Ubuntu:
- `vars/RedHat.yml`: `redis_package: redis`, `postgresql_package: postgresql-server`, `postgresql_dev_package: libpq-devel`.
- `vars/Debian.yml`: `redis_package: redis-server`, `postgresql_package: postgresql`, `postgresql_dev_package: libpq-dev`.
Load the appropriate file at the top of each role's `tasks/main.yml` using `ansible.builtin.include_vars` with `ansible_os_family` as the selector. Use `ansible.builtin.package` (not `dnf` or `apt` directly) for all package installation tasks to maintain cross-platform compatibility.

---

## Git Deployment Task

Replace the Chef `git` resource with `:sync` action with `ansible.builtin.git`:
```yaml
- name: Deploy FastAPI application
  ansible.builtin.git:
    repo: https://github.com/dibanez/fastapi_tutorial.git
    dest: /opt/fastapi-tutorial
    version: main
    update: yes
```
Ensure the destination directory is owned by the `fastapi` system user. If the repository is ever made private, document that `accept_hostkey` and SSH key credential configuration will be required.

---

## Molecule Testing Requirements

Generate Molecule tests for each Ansible role. Each Molecule scenario must:
- Target the `generic/fedora42` platform (matching the Vagrant environment).
- Verify that all services are running and enabled after role application: `nginx`, `redis`, `memcached`, `postgresql`, `fastapi-tutorial`.
- Verify that SSL certificate files exist at the paths defined in `group_vars`.
- Verify that the `.env` file exists with mode `0600`.
- Verify that the `fastapi-tutorial` service is not running as root.
- Verify that firewall rules are active via `firewalld`.
- Test idempotency: re-running the role must produce zero changes.
The Vagrant environment (`Vagrantfile` updated to use the `ansible` provisioner) serves as the integration test target.

---

## Vagrant Integration — Ansible Provisioner

Update the `Vagrantfile` to replace the `vagrant-provision.sh` shell provisioner with the Ansible provisioner pointing to the new playbook entry point:
```ruby
config.vm.provision "ansible" do |ansible|
  ansible.playbook = "ansible/playbooks/site.yml"
  ansible.inventory_path = "ansible/inventory/"
end
```
The VM configuration (2 vCPUs, 2 GB RAM, private network IP `192.168.121.10`, port forwards 80→8080 and 443→8443, Libvirt provider) must be preserved. The `vagrant-provision.sh` script (Chef bootstrap) is fully replaced and should be removed or archived.

---

## Sysctl Hardening Implementation

The `sysctl-security.conf.erb` template is fully static. Implement sysctl hardening using `ansible.posix.sysctl` module tasks for individual parameter management (preferred for auditability), or deploy the file via `ansible.builtin.copy` to `/etc/sysctl.d/99-security.conf` and notify a handler to run `sysctl --system`. Parameters to manage include: IP spoofing protection, ICMP suppression, SYN-cookie flood protection, and IPv6 disable. Document each parameter's purpose in task `name` fields.

---

## SELinux Context Management

Fedora 42 runs SELinux in enforcing mode by default. Any file paths changed from Chef defaults (e.g., Redis log directory at `/var/log/redis`, Nginx document roots at `/var/www/<site>`, FastAPI application at `/opt/fastapi-tutorial`) may require SELinux context adjustments. Use `community.general.sefcontext` to set file contexts and `ansible.builtin.command` with `restorecon` (or the `sefcontext` module's `reload` option) to apply them. Do not disable SELinux; manage contexts explicitly.