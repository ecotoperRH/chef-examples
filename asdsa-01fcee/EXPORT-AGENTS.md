## Ansible Collection Requirements

The generated Ansible role must use the following collections. Include all in `requirements.yml`:
- `ansible.builtin`: package, template, service, file, copy, git, lineinfile, blockinfile, systemd, user, group, command, shell, sysctl.
- `ansible.posix`: `sysctl` (for kernel hardening parameters), `firewalld` (for Fedora/RHEL firewall), `selinux`.
- `community.crypto`: `openssl_privatekey`, `x509_certificate` (replacing raw `openssl` shell commands for self-signed certificate generation).
- `community.postgresql`: `postgresql_user`, `postgresql_db`, `postgresql_privs` (replacing `execute` with `|| true` idempotency hacks).
- `community.general`: `seboolean` (for SELinux boolean management on Fedora/RHEL).

---

## Ansible Vault for Credentials

All hardcoded credentials identified in the Chef source must be migrated to Ansible Vault. Do not emit any plaintext secret values in task files, defaults, or templates:
- Define `redis_requirepass` in an encrypted `group_vars/all/vault.yml` (source: `redis_secure_password_123` in `cache::default.rb`).
- Define `fastapi_db_password` and `fastapi_database_url` in the same vault file (source: `fastapi_password` and `DATABASE_URL` in `fastapi-tutorial::default.rb`).
- Reference vault variables in templates and tasks using standard Jinja2 variable syntax.
- The `.env` file template must reference `fastapi_database_url` from Vault and be deployed with mode `0600`, not `0644`.

---

## ERB to Jinja2 Template Conversion

Convert all Chef ERB templates to Jinja2 with the following rules:
- Replace `<%= node['attr'] %>` with `{{ attr_variable }}`.
- Replace `<% if condition %>` / `<% end %>` with `{% if condition %}` / `{% endif %}`.
- Replace `<% array.each do |item| %>` / `<% end %>` with `{% for item in list %}` / `{% endfor %}`.
- Replace Ruby string interpolation (`#{var}`) with Jinja2 `{{ var }}`.
- The `fail2ban.jail.local.erb` template maps 1:1 to Jinja2 — preserve all jail definitions for `sshd`, `nginx-http-auth`, `nginx-limit-req`, `nginx-botsearch`.
- The `sysctl-security.conf.erb` template should be replaced by individual `ansible.posix.sysctl` tasks (one per parameter) rather than a file template, for full idempotency.
- Parameterise all hardcoded SSL subject fields (`/C=US/ST=Example/...`) as role variables.

---

## Platform-Conditional Task Structure

Generate platform-specific variable files and conditional tasks to handle OS-family differences:
- Create `vars/RedHat.yml` and `vars/Debian.yml` with differing package names: `postgresql-devel` (RedHat) vs `libpq-dev` (Debian); `nginx` user (RedHat) vs `www-data` (Debian).
- Load platform vars with `ansible.builtin.include_vars` using `file: '{{ ansible_os_family }}.yml'`.
- Firewall tasks: use `ansible.posix.firewalld` with `when: ansible_os_family == 'RedHat'` and `community.general.ufw` (or `ansible.builtin.package`/`command`) with `when: ansible_os_family == 'Debian'`.
- Primary target is Fedora 42 / RHEL 9; Ubuntu compatibility is secondary.

---

## Replacing the Redis ruby_block Config Patch

The `ruby_block 'fix_redis_config'` that strips deprecated directives from `/etc/redis/6379.conf` must be replaced using one of two approaches (prefer option A for full idempotency):
- **Option A (preferred)**: Own the entire Redis config file via an `ansible.builtin.template` task. Ensure the Jinja2 template does not include any of the five deprecated directives: `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`.
- **Option B (fallback)**: Use five `ansible.builtin.lineinfile` tasks with `state: absent` and `regexp:` patterns matching each deprecated directive line.
In both cases, notify the Redis service handler to restart after config changes.

---

## SSH Hardening Task Generation

Replace the `sed`-based SSH hardening in `security.rb` with `ansible.builtin.lineinfile` tasks targeting `/etc/ssh/sshd_config`:
- Set `PermitRootLogin no` (driven by `security_ssh_disable_root` variable, sourced from `solo.json` `security.ssh.disable_root`).
- Set `PasswordAuthentication no` (driven by `security_ssh_password_auth` variable).
- Both tasks must notify a handler: `ansible.builtin.service: name=sshd state=restarted`.
- Include a pre-task warning or documentation note that key-based SSH access must be confirmed on the Ansible control node before these tasks are applied.

---

## SSL Certificate Generation with community.crypto

Replace raw `openssl req -x509` shell commands in `ssl.rb` with idempotent `community.crypto` tasks:
- Use `community.crypto.openssl_privatekey` to generate RSA-2048 private keys per virtual host.
- Use `community.crypto.x509_certificate` with `provider: selfsigned` to generate self-signed certificates.
- Generate certificates for all three virtual hosts: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`.
- Preserve file permissions: private key directory `0710` with `ssl-cert` group; private keys `0640` with `root:ssl-cert` ownership.
- Parameterise all subject fields (C, ST, O, CN) as role variables rather than hardcoding `/C=US/ST=Example/...`.

---

## FastAPI Service User Remediation

The systemd unit `fastapi-tutorial.service` currently sets `User=root`. The exported Ansible role must remediate this:
- Create a dedicated `fastapi` system user and group using `ansible.builtin.user` with `system: yes` and `shell: /sbin/nologin`.
- Update the systemd unit file template to set `User=fastapi`.
- Ensure `/opt/fastapi-tutorial` and the venv directory are owned by the `fastapi` user.
- Verify application functionality under the non-root user before finalising.
- The `.env` file must be owned by the `fastapi` user with mode `0600`.

---

## PostgreSQL Provisioning with community.postgresql

Replace the `execute` resources with `|| true` error suppression in `fastapi-tutorial::default` with natively idempotent `community.postgresql` module tasks:
- `community.postgresql.postgresql_user`: create user `fastapi` with password sourced from Ansible Vault variable `fastapi_db_password`.
- `community.postgresql.postgresql_db`: create database `fastapi_db` with owner `fastapi`.
- `community.postgresql.postgresql_privs`: grant full privileges on `fastapi_db` to user `fastapi`.
- Ensure PostgreSQL service is started and enabled before provisioning tasks run.

---

## Systemd Handler and Daemon-Reload Pattern

Replace Chef `notifies :run, 'execute[systemd_reload]', :immediately` patterns with Ansible handlers:
- Define a handler using `ansible.builtin.systemd: daemon_reload: yes` triggered by the systemd unit file task.
- Define separate service restart handlers for `nginx`, `redis`, `memcached`, `fail2ban`, `sshd`, and `fastapi-tutorial` services.
- Use `notify:` on the task that writes each unit or config file to trigger the appropriate handler.
- Ensure `daemon_reload` handler runs before service restart handlers using `listen` groups or handler ordering.

---

## Document Root Variable Canonicalisation

The `solo.json` document root values (`/var/www/test.cluster.local`, `/var/www/ci.cluster.local`, `/var/www/status.cluster.local`) must be used as the canonical paths in all generated Ansible tasks and templates — not the `attributes/default.rb` defaults (`/opt/server/{test,ci,status}`). Define these paths as role variables in `defaults/main.yml` or `group_vars/all/main.yml` and reference them consistently across virtual host config templates, directory creation tasks, and static file copy tasks.

---

## Git-Based Application Deployment

Replace Chef's `git` resource in `fastapi-tutorial::default` with `ansible.builtin.git`:
- Set `repo: https://github.com/dibanez/fastapi_tutorial.git`, `dest: /opt/fastapi-tutorial`, `version: main`.
- Add a documentation note that pinning to a specific tag or SHA is recommended for production stability instead of tracking `main`.
- Ensure the target host has outbound HTTPS access to `github.com`.
- If the repository is private, document the requirement for SSH key configuration on the managed host.

---

## Nginx Virtual Host and Global Config Generation

Generate Ansible tasks and Jinja2 templates for the full Nginx configuration:
- Deploy a global `nginx.conf` template with security headers (X-Frame-Options, CSP, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy), TLS 1.2/1.3 hardening, and HSTS.
- Deploy a `security.conf` snippet template with rate-limiting zones (`login`, `api`), buffer-overflow mitigations, and global SSL session cache.
- Generate per-site server block configs for all three virtual hosts with HTTP→HTTPS redirect.
- Deploy static `index.html` files from `files/default/{ci,status,test}/` using `ansible.builtin.copy`.
- Parameterise the Nginx service user/group (`nginx` on RHEL, `www-data` on Debian) via platform variable files.

---

## Dropping the Custom lineinfile LWRP

The custom `lineinfile` LWRP defined in `nginx-multisite/resources/lineinfile.rb` replicates Ansible's native `ansible.builtin.lineinfile` module and is not called by any recipe in the repository. Do not generate any Ansible equivalent for this resource — omit it entirely from the exported role. Use `ansible.builtin.lineinfile` natively wherever line-in-file operations are required.

---

## Vagrant Integration for Testing

The existing Vagrant/libvirt environment (Fedora 42, 2 vCPU, 2 GB RAM, private network `192.168.121.10`, port forwards 80→8080 and 443→8443) should be retained for development testing. Update the `Vagrantfile` to replace the `vagrant-provision.sh` shell provisioner with an `ansible_local` or `ansible` provisioner that invokes the migrated playbook. This allows the migrated roles to be validated against the same VM environment used for the Chef stack.