## Chef Cookbook Discovery and Parsing

Analyze all three cookbooks in execution order as defined by `Policyfile.rb`: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`. This ordering encodes implicit dependencies (security and web server before application tier) and must be preserved. Parse each cookbook's `recipes/`, `attributes/`, `resources/`, `templates/`, and `files/` directories exhaustively. Identify all Chef resource types used: `package`, `template`, `service`, `execute`, `directory`, `file`, `git`, `ruby_block`, and any custom LWRPs.

---

## Attribute and Variable Resolution

Treat `solo.json` as the authoritative source for runtime attribute values, overriding any defaults in `attributes/default.rb`. Specifically, document roots are `/var/www/<site>` (from `solo.json`), not `/opt/server/<site>` (from cookbook defaults). Extract all node attribute overrides from `solo.json` and flag them for translation into Ansible `group_vars` or `host_vars`. When documenting the `nginx-multisite` cookbook, capture the full structure of `node['nginx']['sites']` as it will need to be converted to an Ansible list-of-dicts.

---

## Credential and Secret Detection

Flag all hardcoded credentials found in recipe source code for mandatory Ansible Vault migration. Identified secrets are:
- **Redis password** (`redis_secure_password_123`) in `cookbooks/cache/recipes/default.rb` line 7.
- **PostgreSQL password** (`fastapi_password`) in `cookbooks/fastapi-tutorial/recipes/default.rb` lines 32–34 and again in the `.env` file content on line 44.
Document each credential's location, the number of references, and the proposed Vault variable name (e.g., `vault_redis_password`, `vault_fastapi_db_password`). Note that the `.env` file is written with mode `0644` (world-readable) — flag this as a security finding requiring remediation.

---

## Ruby Block and Workaround Identification

Identify and document all `ruby_block` resources as they represent imperative workarounds that require special handling. In the `cache` cookbook, a `ruby_block` strips deprecated Redis directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` post-install. Document this as a config-patching workaround that can be eliminated entirely in Ansible by managing the Redis config file via a fully-owned Ansible template that simply omits the deprecated directives.

---

## Template and ERB Analysis

Parse all ERB templates in each cookbook's `templates/` directory. For each template, document: the target file path, the node attributes or variables interpolated, any loops or conditionals, and the rendering context. Key templates to analyze:
- `nginx-multisite`: `nginx.conf.erb`, per-site `site.conf.erb`, `security.conf.erb` (rate-limiting zones), `sysctl-security.conf.erb` (fully static), fail2ban `jail.local.erb`.
- `cache`: Redis configuration template (identify all directives, especially deprecated ones).
- `fastapi-tutorial`: `.env` file template with `DATABASE_URL` embedding credentials.
Note which templates are fully static (no variable interpolation) vs. data-driven.

---

## Multi-Site Loop and Data-Driven Pattern Detection

In the `nginx-multisite` cookbook, identify the iteration over `node['nginx']['sites']` that generates virtual host configs, document root directories, and SSL certificates. Document the full attribute hash structure (keys: site name, document root, SSL cert/key paths, enabled flags). This loop must be mapped to an Ansible `loop` over a `nginx_sites` list variable. Capture all per-site values from `solo.json`: sites are `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`, all with SSL enabled and document roots at `/var/www/<site>`.

---

## Custom LWRP and Dead Code Identification

Identify all custom resources (LWRPs) defined in each cookbook's `resources/` directory. For the `nginx-multisite` cookbook, a custom `lineinfile` resource is defined in `resources/lineinfile.rb`. Verify whether this resource is called anywhere in the cookbook's recipes. If no calls are found, document it as dead code requiring no migration action. Do not generate migration specifications for unused resources.

---

## External Cookbook Dependency Mapping

Map all external Chef Supermarket cookbook dependencies to their Ansible equivalents as follows:
- `nginx ~> 12.0` (resolved 12.3.1): Replace with `ansible.builtin.package` + `ansible.builtin.template` for custom configs.
- `memcached ~> 6.0` (resolved 6.1.0): Replace with `ansible.builtin.package` + `ansible.builtin.service`.
- `redisio ~> 7.2.4` (resolved 7.2.4): Replace with `ansible.builtin.package` + `ansible.builtin.template` + `ansible.builtin.service`.
- `ssl_certificate ~> 2.1` (resolved 2.1.0): Commented out in `Berksfile`, not referenced in any recipe — treat as unused, no migration required.
- `selinux 6.2.4` (transitive via `redisio`): Not explicitly configured in recipes; handle via `ansible.posix.selinux` and `community.general.sefcontext` as needed.
Document the `Berksfile` → `requirements.yml` mapping in the migration specification.

---

## Security Hardening Recipe Analysis

The `nginx-multisite` cookbook contains a `security.rb` recipe that must be fully analyzed for:
- **UFW firewall rules**: Managed via `execute` resources wrapping `ufw` CLI commands. Flag as incompatible with Fedora 42's default `firewalld`. Document all ports/rules being opened.
- **SSH hardening**: Uses `sed` commands in `execute` resources to modify `/etc/ssh/sshd_config`. Document every directive being changed.
- **Sysctl hardening**: `sysctl-security.conf.erb` sets IP spoofing protection, ICMP suppression, SYN-cookie flood protection, and IPv6 disable. Document each parameter and value.
- **fail2ban**: `jail.local` template for SSH and Nginx jails. Determine if any node attributes are interpolated or if it is fully static.
- **Self-signed TLS**: `ssl.rb` recipe uses raw `openssl req` shell commands. Document the subject string and all `execute` resources used.

---

## PostgreSQL and Application Deployment Analysis

In the `fastapi-tutorial` cookbook, document:
- All system packages installed (Python 3, pip, venv, git, PostgreSQL, `libpq-dev`).
- The `git` resource with `:sync` action targeting `https://github.com/dibanez/fastapi_tutorial.git` branch `main`.
- Python venv creation path and pip install from `requirements.txt`.
- PostgreSQL provisioning: note that `psql` shell commands with `|| true` are used for idempotency — flag for replacement with `community.postgresql` modules.
- The systemd unit file for `fastapi-tutorial.service` running `uvicorn` on `0.0.0.0:8000` as `User=root` — flag the root user as a critical security finding.
- The `daemon-reload` notification pattern via `execute[systemd_reload]`.
- PostgreSQL initialization gap: the recipe assumes Ubuntu-style auto-init; on Fedora 42, `postgresql-setup --initdb` is required before service start — flag as a platform-specific gap.

---

## Cross-Platform Package Name Discrepancies

Document all package name differences between Fedora/RHEL and Debian/Ubuntu that are relevant to this cookbook set:
- Redis: `redis` (Fedora/RHEL) vs. `redis-server` (Debian/Ubuntu).
- PostgreSQL: `postgresql-server` (Fedora/RHEL) vs. `postgresql` (Debian/Ubuntu).
- Python pip: `python3-pip` (both, but package availability may differ).
- PostgreSQL dev library: `libpq-devel` (Fedora/RHEL) vs. `libpq-dev` (Debian/Ubuntu).
The primary target is Fedora 42; Ubuntu compatibility is a secondary goal. Flag all package tasks for conditional variable file handling (`vars/RedHat.yml`, `vars/Debian.yml`).