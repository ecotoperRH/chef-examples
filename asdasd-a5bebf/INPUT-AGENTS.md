## Chef Cookbook Discovery and Inventory

Analyze all three local cookbooks (`nginx-multisite`, `cache`, `fastapi-tutorial`) located under `cookbooks/`. Use `Policyfile.lock.json` as the authoritative version reference for all 8 resolved cookbooks. Cross-reference `solo.json` as the primary source of truth for node attribute overrides — these values take precedence over `attributes/default.rb` defaults and must be used as the canonical values in the migration specification (e.g., document roots `/var/www/<site>/` from `solo.json` override `/opt/server/<site>/` from attributes).

---

## Recipe Execution Order and Run List Parsing

Parse `Policyfile.rb` to extract the run list order: `nginx-multisite::default` → `cache::default` → `fastapi-tutorial::default`. Document intra-cookbook recipe includes (e.g., `include_recipe 'memcached'` in `cache`). Map the run list to the recommended Ansible migration order: security hardening (extracted from nginx-multisite) → cache → nginx-multisite → fastapi-tutorial.

---

## Attribute and Variable Extraction

Extract all node attributes from `solo.json` (site definitions, document roots, SSL flags, certificate/key paths, fail2ban/UFW/SSH security flags) and `attributes/default.rb` files. Flag any attribute whose `solo.json` value differs from the cookbook default — the `solo.json` value is canonical. These attributes become Ansible `group_vars` / `host_vars` variable definitions.

---

## Hardcoded Credential Detection

Identify and flag all hardcoded secrets found in recipe files:
- Redis password: `redis_secure_password_123` in `cookbooks/cache/recipes/default.rb` (`node['redisio']['servers'][0]['requirepass']`)
- PostgreSQL password: `fastapi_password` in `cookbooks/fastapi-tutorial/recipes/default.rb` — appears in the `psql` CREATE USER command, the `.env` file `DATABASE_URL`, and implicitly in the systemd environment (3 locations)

All hardcoded secrets must be flagged for Ansible Vault migration. Document each occurrence location precisely in the migration specification.

---

## Security Risk Identification

During analysis, flag the following security risks for remediation during export:
- `.env` file at `/opt/fastapi-tutorial/.env` created with mode `0644` (world-readable, exposes `DATABASE_URL`)
- FastAPI systemd unit running as `User=root` (privilege escalation risk)
- SSH hardening performed via direct `sed` manipulation of `/etc/ssh/sshd_config` (not idempotent)
- `ufw` firewall usage on a Fedora 42 target (platform mismatch — `firewalld` is the default on RHEL/Fedora)

---

## Template and ERB Parsing

Identify all ERB templates in each cookbook and document their variables, conditionals, and loops:
- `nginx-multisite`: `nginx.conf.erb` (note hardcoded `user www-data;` — must be parameterised for Fedora/RHEL where the nginx worker user is `nginx`), `security.conf.erb`, per-site `site.conf.erb` (HTTP→HTTPS redirect, TLS 1.2/1.3, HSTS, security headers, conditional SSL block), `sysctl-security.conf.erb` (fully static), `jail.local` (fully static)
- Document all ERB variable references and conditionals for Jinja2 conversion.

---

## Iteration and Loop Detection

Identify all resource loops in recipes:
- `nginx-multisite` (`sites.rb`, `nginx.rb`): iterates over `node['nginx']['sites']` to create document root directories, deploy static HTML files, generate per-site `site.conf` files, and create `sites-enabled` symlinks. Document the full loop body and all per-site attributes (document root, SSL flag, vhost name).
- Document the loop structure so it can be reproduced as an Ansible `loop` over a `nginx_sites` list variable.

---

## Ruby Block and Non-Standard Resource Detection

Identify all `ruby_block` resources and custom LWRPs:
- `cache/recipes/default.rb`: `ruby_block` that strips five deprecated Redis config directives (`replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority`) from `/etc/redis/6379.conf` post-install. Document each directive pattern precisely.
- `nginx-multisite/resources/lineinfile.rb`: custom `lineinfile` LWRP — maps directly to `ansible.builtin.lineinfile`; no custom logic needed.
- Flag `ruby_block` resources as requiring special conversion attention (not a direct 1:1 Ansible mapping).

---

## External Cookbook Dependency Mapping

Map each external Supermarket dependency to its Ansible equivalent:
- `nginx 12.3.1` → `nginxinc.nginx` Galaxy role or direct `package` + `template` tasks
- `memcached 6.1.0` → `geerlingguy.memcached` Galaxy role or direct `package`/`service` tasks
- `redisio 7.2.4` → `geerlingguy.redis` Galaxy role or direct `package`/`template`/`service` tasks
- `ssl_certificate 2.1.0` → `community.crypto` collection modules (`openssl_privatekey`, `openssl_csr`, `x509_certificate`); verify whether this cookbook is actually called in any recipe — if unused, omit from `requirements.yml`
- `selinux 6.2.4` (transitive via redisio) → `ansible.posix.selinux` module or `geerlingguy.selinux` role

Document the mapping for each dependency in the migration specification.

---

## PostgreSQL Idempotency Analysis

In `fastapi-tutorial/recipes/default.rb`, identify all `psql` shell commands used to create the database user (`fastapi`), database (`fastapi_db`), and grant privileges. Note that `|| true` guards suppress errors but do not provide true idempotency. Flag these for replacement with `community.postgresql.postgresql_user` and `community.postgresql.postgresql_db` modules in the migration specification.

---

## Git-Based Application Deployment Detection

In `fastapi-tutorial`, identify the Chef `git` resource with `action :sync` targeting `/opt/fastapi-tutorial` from `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`). Document the pip install step from `requirements.txt` and note that it should only re-run when `requirements.txt` changes. Flag the need for a handler-based approach in Ansible.

---

## Platform Divergence Detection

Flag all Ubuntu/Debian-specific conventions used in cookbooks that conflict with the Fedora 42 target:
- `ufw` firewall package and rules (Debian/Ubuntu) vs. `firewalld` (Fedora/RHEL)
- `www-data` nginx worker user (Debian/Ubuntu) vs. `nginx` user (Fedora/RHEL)
- Document all platform-specific resource usages so the export phase can apply appropriate `when: ansible_os_family` conditionals.

---

## SELinux Consideration on Fedora Target

Note that `selinux 6.2.4` is a transitive dependency pulled in by `redisio`. On Fedora 42, SELinux is enforcing by default. Document the need for SELinux boolean/policy adjustments in the migration specification, specifically: allowing Redis to bind to its port and write to `/var/log/redis`, and `httpd_can_network_connect` for Nginx. Assume basic SELinux boolean adjustments are sufficient — no custom policy module compilation is required.

---

## Static Content and File Resource Inventory

Inventory all static file resources deployed by each cookbook:
- `nginx-multisite`: static HTML content files for each vhost (`ci/`, `status/`, `test/`) — copy over unchanged
- `fastapi-tutorial`: `.env` file at `/opt/fastapi-tutorial/.env`, systemd unit `fastapi-tutorial.service`
- Document file paths, ownership, and modes. Flag the `.env` file mode `0644` as a security risk requiring remediation to `0600`.

---

## SSL Certificate Generation Workflow

In `nginx-multisite`, identify the self-signed certificate generation workflow using `openssl req -x509` with 365-day validity and a hardcoded subject string (`/C=US/ST=Example/...`). Document all certificate/key paths (sourced from `solo.json`). Note this is intentional for the development/test environment. Map to `community.crypto` collection modules for the export phase.

---

## Vestigial Dependency Verification

Verify whether `ssl_certificate ~> 2.1` (present in `Policyfile.rb` and `Policyfile.lock.json` but commented out in `Berksfile`) is called in any recipe. Based on code inspection, it is assumed unused. Document the finding explicitly — if confirmed unused, it must be omitted from the Ansible `requirements.yml`.