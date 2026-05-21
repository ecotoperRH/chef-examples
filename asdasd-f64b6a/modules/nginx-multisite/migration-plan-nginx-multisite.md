---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and hardens nginx with security headers, deploys self-signed TLS certificates for each site, configures UFW firewall rules (deny-by-default, allow SSH/HTTP/HTTPS), installs and configures fail2ban with nginx-aware jails, applies kernel-level sysctl hardening, and locks down SSH (no root login, no password authentication). Each site gets its own document root under `/opt/server/`, a static `index.html` page, and a dedicated nginx virtual-host config with HTTP→HTTPS redirect.

## Service Type and Instances

**Service Type**: Web Server (nginx multisite with security hardening)

**Configured Instances**:

The `node['nginx']['sites']` attribute is a dict with **3 keys**. All three recipes `nginx.rb`, `ssl.rb`, and `sites.rb` iterate over this collection. Every key is listed explicitly below.

- **test.cluster.local**: Test/development environment virtual host
  - Document Root: `/opt/server/test`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — self-signed certificate
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Static file deployed: `/opt/server/test/index.html` (source: `files/default/test/index.html`)
  - nginx vhost config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Document Root: `/opt/server/ci`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — self-signed certificate
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Static file deployed: `/opt/server/ci/index.html` (source: `files/default/ci/index.html`)
  - nginx vhost config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: System status/monitoring virtual host
  - Document Root: `/opt/server/status`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — self-signed certificate
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Static file deployed: `/opt/server/status/index.html` (source: `files/default/status/index.html`)
  - nginx vhost config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`

## File Structure

```
cookbooks/nginx-multisite/recipes/default.rb
cookbooks/nginx-multisite/recipes/security.rb
cookbooks/nginx-multisite/recipes/nginx.rb
cookbooks/nginx-multisite/recipes/ssl.rb
cookbooks/nginx-multisite/recipes/sites.rb
cookbooks/nginx-multisite/resources/lineinfile.rb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/files/default/test/index.html
cookbooks/nginx-multisite/files/default/ci/index.html
cookbooks/nginx-multisite/files/default/status/index.html
cookbooks/nginx-multisite/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw` (single `package` resource with array `%w[fail2ban ufw]`)
- Enables and starts the `fail2ban` service
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]`, `[nginx-http-auth]`, `[nginx-limit-req]`, `[nginx-botsearch]`
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall with idempotency guards (`not_if` checks):
  - `execute 'ufw_default_deny'`: runs `ufw --force default deny` (skipped if already set)
  - `execute 'ufw_allow_ssh'`: runs `ufw allow ssh` (skipped if 22/tcp already present)
  - `execute 'ufw_allow_http'`: runs `ufw allow http` (skipped if 80/tcp already present)
  - `execute 'ufw_allow_https'`: runs `ufw allow https` (skipped if 443/tcp already present)
  - `execute 'ufw_enable'`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Settings applied: IP spoofing protection (rp_filter=1), ICMP redirect ignore, source routing disabled, martian logging, ICMP ping ignore, IPv6 disabled, TCP SYN cookie protection (tcp_syncookies=1, tcp_max_syn_backlog=2048)
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- Hardens SSH (both guarded by `not_if` checks):
  - `execute 'disable root login'`: `sed` replaces `PermitRootLogin` → `PermitRootLogin no` in `/etc/ssh/sshd_config` (conditional on `node['security']['ssh']['disable_root']` = true)
  - `execute 'disable password auth'`: `sed` replaces `PasswordAuthentication` → `PasswordAuthentication no` in `/etc/ssh/sshd_config` (conditional on `node['security']['ssh']['password_auth']` = false)
  - Both notify: `service[ssh]` restart (delayed, action :nothing by default)
- Resources: package (1), service (2: fail2ban + ssh), template (2), execute (7)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile/tcp_nopush/tcp_nodelay on, keepalive_timeout=65, gzip on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens off, rate limiting zones (login: 10r/m, api: 30r/m), buffer overflow protections (client_body_buffer_size=1K, client_max_body_size=1K), timeout settings (body/header/send=10s), global SSL settings (TLSv1.2+TLSv1.3, strong cipher suite)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
  - **test.cluster.local**:
    - `directory '/opt/server/test'`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file '/opt/server/test/index.html'`: source=`test/index.html`, owner=www-data, group=www-data, mode=0644 (static HTML for test environment page)
  - **ci.cluster.local**:
    - `directory '/opt/server/ci'`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file '/opt/server/ci/index.html'`: source=`ci/index.html`, owner=www-data, group=www-data, mode=0644 (static HTML for CI/CD dashboard page)
  - **status.cluster.local**:
    - `directory '/opt/server/status'`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file '/opt/server/status/index.html'`: source=`status/index.html`, owner=www-data, group=www-data, mode=0644 (static HTML for system status page)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

> **Note on `lineinfile` custom resource** (`cookbooks/nginx-multisite/resources/lineinfile.rb`): This custom resource is defined in the cookbook but is **not called** by any recipe in the execution tree. It provides a `lineinfile` resource (similar to Ansible's `lineinfile` module) that can match a regex pattern and replace or append a line in a file, with optional backup. It is not used in the current execution flow and does not need to be migrated as an active task — however, its Ansible equivalent (`ansible.builtin.lineinfile`) is already natively available.

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates` (single `package` resource with array `%w[openssl ca-certificates]`)
- Creates group `ssl-cert`
- Creates SSL certificate directory:
  - `directory '/etc/ssl/certs'`: owner=root, group=root, mode=0755
- Creates SSL private key directory:
  - `directory '/etc/ssl/private'`: owner=root, group=ssl-cert, mode=0710
- Iterations: Runs 3 times for sites with ssl_enabled=true: test.cluster.local, ci.cluster.local, status.cluster.local (all 3 sites have `ssl_enabled: true`)
  - **test.cluster.local**:
    - `execute 'generate-ssl-cert-test.cluster.local'`: Generates self-signed certificate using `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
      - Output cert: `/etc/ssl/certs/test.cluster.local.crt`
      - Output key: `/etc/ssl/private/test.cluster.local.key`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
      - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
      - Idempotency guard: `not_if { File.exist?(cert) && File.exist?(key) }` — skipped if both files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute 'generate-ssl-cert-ci.cluster.local'`: Same openssl command
      - Output cert: `/etc/ssl/certs/ci.cluster.local.crt`
      - Output key: `/etc/ssl/private/ci.cluster.local.key`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
      - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
      - Idempotency guard: skipped if both files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute 'generate-ssl-cert-status.cluster.local'`: Same openssl command
      - Output cert: `/etc/ssl/certs/status.cluster.local.crt`
      - Output key: `/etc/ssl/private/status.cluster.local.key`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
      - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
      - Idempotency guard: skipped if both files already exist
      - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=`test.cluster.local`, document_root=`/opt/server/test`, ssl_enabled=true, cert_file=`/etc/ssl/certs/test.cluster.local.crt`, key_file=`/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP header, gzip, location / try_files, deny .ht/.git/.svn, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
      - Notifies: `service[nginx]` reload (delayed)
    - `link '/etc/nginx/sites-enabled/test.cluster.local'` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=`ci.cluster.local`, document_root=`/opt/server/ci`, ssl_enabled=true, cert_file=`/etc/ssl/certs/ci.cluster.local.crt`, key_file=`/etc/ssl/private/ci.cluster.local.key`
      - Rendered config: identical structure to test.cluster.local with ci-specific paths and log files (`/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`)
      - Notifies: `service[nginx]` reload (delayed)
    - `link '/etc/nginx/sites-enabled/ci.cluster.local'` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=`status.cluster.local`, document_root=`/opt/server/status`, ssl_enabled=true, cert_file=`/etc/ssl/certs/status.cluster.local.crt`, key_file=`/etc/ssl/private/status.cluster.local.key`
      - Rendered config: identical structure with status-specific paths and log files (`/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`)
      - Notifies: `service[nginx]` reload (delayed)
    - `link '/etc/nginx/sites-enabled/status.cluster.local'` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- After the loop: `file '/etc/nginx/sites-enabled/default'` → action :delete (removes the default nginx placeholder site)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb` (no `depends` lines)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / log-based banning
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `nginx` — enabled, started; reloaded on config/cert/vhost changes
- `fail2ban` — enabled, started; restarted on jail.local changes
- `ssh` (sshd) — restarted when sshd_config is modified (root login or password auth changes)

## Credentials

**Detection Summary**: 0 credentials detected across 6 recipe/attribute files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed and created at runtime using `openssl req` with a hardcoded non-sensitive subject string (`/C=US/ST=Example/O=Example Org/...`). No data bags, Chef Vault items, encrypted attributes, API keys, database passwords, or external secret manager references are present.

> **Note for Solutions Architect**: The self-signed certificate subject (`emailAddress=admin@example.com`, `O=Example Org`) is hardcoded in `ssl.rb`. If real certificates (e.g., from an internal CA or Let's Encrypt) are required in the Ansible migration, the certificate provisioning task will need to be redesigned and the certificate/key material sourced from a secrets manager (e.g., HashiCorp Vault PKI, CyberArk, or AAP credential store).

## Checks for the Migration

**Files to verify**:

| File | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Global nginx configuration |
| `/etc/nginx/conf.d/security.conf` | nginx security snippet (rate limits, buffers, SSL globals) |
| `/etc/nginx/sites-available/test.cluster.local` | Virtual host config for test site |
| `/etc/nginx/sites-available/ci.cluster.local` | Virtual host config for CI site |
| `/etc/nginx/sites-available/status.cluster.local` | Virtual host config for status site |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | Must NOT exist (deleted by recipe) |
| `/opt/server/test/index.html` | Static page for test.cluster.local |
| `/opt/server/ci/index.html` | Static page for ci.cluster.local |
| `/opt/server/status/index.html` | Static page for status.cluster.local |
| `/etc/ssl/certs/test.cluster.local.crt` | Self-signed cert for test site |
| `/etc/ssl/private/test.cluster.local.key` | Private key for test site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/ci.cluster.local.crt` | Self-signed cert for CI site |
| `/etc/ssl/private/ci.cluster.local.key` | Private key for CI site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/status.cluster.local.crt` | Self-signed cert for status site |
| `/etc/ssl/private/status.cluster.local.key` | Private key for status site (mode 640, owner root:ssl-cert) |
| `/etc/fail2ban/jail.local` | fail2ban jail configuration |
| `/etc/sysctl.d/99-security.conf` | Kernel hardening parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |
| `/var/log/nginx/test.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/test.cluster.local_error.log` | Per-site error log (created at runtime) |
| `/var/log/nginx/ci.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/ci.cluster.local_error.log` | Per-site error log (created at runtime) |
| `/var/log/nginx/status.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/status.cluster.local_error.log` | Per-site error log (created at runtime) |

**Service endpoints to check**:
- Ports listening: **80** (HTTP, all 3 sites — redirects to HTTPS), **443** (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× (loop iteration 1) |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× (loop iteration 2) |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× (loop iteration 3) |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================

systemctl status nginx
systemctl status fail2ban
systemctl status ssh

ps aux | grep nginx | grep -v grep
ps aux | grep fail2ban | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION VALIDATION
# ============================================================

# Syntax check
nginx -t

# Verify global config key settings
grep -E 'worker_processes|worker_connections|keepalive_timeout|server_tokens' /etc/nginx/nginx.conf
grep -E 'gzip|sendfile|tcp_nopush' /etc/nginx/nginx.conf

# Verify security snippet
cat /etc/nginx/conf.d/security.conf
grep -E 'server_tokens|limit_req_zone|ssl_protocols|ssl_ciphers' /etc/nginx/conf.d/security.conf

# Verify default site is removed
ls -la /etc/nginx/sites-enabled/default 2>/dev/null && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 3. VIRTUAL HOST CONFIGS AND SYMLINKS
# ============================================================

# Site: test.cluster.local
ls -la /etc/nginx/sites-available/test.cluster.local
ls -la /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local  # should be /etc/nginx/sites-available/test.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/test.cluster.local

# Site: ci.cluster.local
ls -la /etc/nginx/sites-available/ci.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local  # should be /etc/nginx/sites-available/ci.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/ci.cluster.local

# Site: status.cluster.local
ls -la /etc/nginx/sites-available/status.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local  # should be /etc/nginx/sites-available/status.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 4. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# Site: test.cluster.local
ls -lah /opt/server/test/
stat /opt/server/test/index.html  # should be owner www-data:www-data, mode 0644
cat /opt/server/test/index.html | grep -i "Test Environment"

# Site: ci.cluster.local
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html  # should be owner www-data:www-data, mode 0644
cat /opt/server/ci/index.html | grep -i "CI/CD"

# Site: status.cluster.local
ls -lah /opt/server/status/
stat /opt/server/status/index.html  # should be owner www-data:www-data, mode 0644
cat /opt/server/status/index.html | grep -i "System Status"

# ============================================================
# 5. SSL CERTIFICATES
# ============================================================

# Site: test.cluster.local
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be 640, root:ssl-cert
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"
openssl verify -CAfile /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/test.cluster.local.crt  # self-signed: should say OK

# Site: ci.cluster.local
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be 640, root:ssl-cert
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"
openssl verify -CAfile /etc/ssl/certs/ci.cluster.local.crt /etc/ssl/certs/ci.cluster.local.crt  # self-signed: should say OK

# Site: status.cluster.local
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be 640, root:ssl-cert
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"
openssl verify -CAfile /etc/ssl/certs/status.cluster.local.crt /etc/ssl/certs/status.cluster.local.crt  # self-signed: should say OK

# SSL directory permissions
stat /etc/ssl/certs | grep -E 'Uid|Gid|Access'   # should be 0755, root:root
stat /etc/ssl/private | grep -E 'Uid|Gid|Access' # should be 0710, root:ssl-cert

# ============================================================
# 6. HTTP/HTTPS CONNECTIVITY - EACH SITE INDIVIDUALLY
# ============================================================

# Site: test.cluster.local
# HTTP should redirect to HTTPS (301)
curl -I -H "Host: test.cluster.local" http://localhost/ 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://test.cluster.local/

# HTTPS should return 200 (using --insecure for self-signed cert)
curl -k -I -H "Host: test.cluster.local" https://localhost/ 2>/dev/null | grep -E 'HTTP|Strict-Transport'
# Expected: HTTP/2 200, Strict-Transport-Security header present

# Verify security headers on test site
curl -k -sI -H "Host: test.cluster.local" https://localhost/ | grep -E 'X-Frame-Options|X-Content-Type|X-XSS|Referrer-Policy|Content-Security-Policy'
# Expected: X-Frame-Options: DENY, X-Content-Type-Options: nosniff, etc.

# Site: ci.cluster.local
# HTTP should redirect to HTTPS (301)
curl -I -H "Host: ci.cluster.local" http://localhost/ 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://ci.cluster.local/

# HTTPS should return 200
curl -k -I -H "Host: ci.cluster.local" https://localhost/ 2>/dev/null | grep -E 'HTTP|Strict-Transport'
# Expected: HTTP/2 200, Strict-Transport-Security header present

# Verify security headers on ci site
curl -k -sI -H "Host: ci.cluster.local" https://localhost/ | grep -E 'X-Frame-Options|X-Content-Type|X-XSS|Referrer-Policy|Content-Security-Policy'
# Expected: X-Frame-Options: DENY, X-Content-Type-Options: nosniff, etc.

# Site: status