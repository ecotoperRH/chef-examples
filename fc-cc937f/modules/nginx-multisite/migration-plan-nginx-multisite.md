# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting **3 SSL-enabled virtual hosts** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations with HTTP→HTTPS redirects, and applies a full security hardening layer including UFW firewall rules, fail2ban intrusion prevention (with 5 jails), and kernel-level sysctl hardening. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / reverse proxy with TLS termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/test.cluster.local.crt`, key: `/etc/ssl/private/test.cluster.local.key`
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/ci.cluster.local.crt`, key: `/etc/ssl/private/ci.cluster.local.key`
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/status.cluster.local.crt`, key: `/etc/ssl/private/status.cluster.local.key`
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`

## File Structure

```
cookbooks/nginx-multisite/recipes/default.rb
cookbooks/nginx-multisite/recipes/security.rb
cookbooks/nginx-multisite/recipes/nginx.rb
cookbooks/nginx-multisite/recipes/ssl.rb
cookbooks/nginx-multisite/recipes/sites.rb
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/files/default/test/index.html
cookbooks/nginx-multisite/files/default/ci/index.html
cookbooks/nginx-multisite/files/default/status/index.html
cookbooks/nginx-multisite/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 sub-recipes in strict order: `security` → `nginx` → `ssl` → `sites`
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service immediately
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall (idempotent — each execute has a `not_if` guard):
  - `ufw --force default deny` (guard: skip if default deny already set)
  - `ufw allow ssh` (guard: skip if 22/tcp already allowed)
  - `ufw allow http` (guard: skip if 80/tcp already allowed)
  - `ufw allow https` (guard: skip if 443/tcp already allowed)
  - `ufw --force enable` (guard: skip if UFW already active)
- Deploys kernel hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Kernel parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6, all+default), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all/default/lo), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` (`sysctl -p /etc/sysctl.d/99-security.conf`)
- **Conditional**: If `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
  - Guard: skip if `PermitRootLogin no` already present
  - Notifies: delayed restart of `service[ssh]`
- **Conditional**: If `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
  - Guard: skip if `PasswordAuthentication no` already present
  - Notifies: delayed restart of `service[ssh]`
- `service[ssh]` is declared with `action :nothing` — only restarts when notified by the above conditionals
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 sysctl reload)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login`: 10r/m, `api`: 30r/m), buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (body/header/send = 10s), global SSL settings (TLSv1.2/TLSv1.3, cipher suite, `ssl_prefer_server_ciphers on`, session cache 10m)
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `service[nginx]`
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

> **Note on site_folder derivation**: The cookbook_file source is derived by taking the first label of the site FQDN: `test.cluster.local` → `test`, `ci.cluster.local` → `ci`, `status.cluster.local` → `status`. The Ansible equivalent must replicate this mapping explicitly.

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so the `next unless ssl_enabled` guard never skips any site)
  - **test.cluster.local**:
    - Generates self-signed certificate (guard: skip if both `/etc/ssl/certs/test.cluster.local.crt` AND `/etc/ssl/private/test.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Generates self-signed certificate (guard: skip if both `/etc/ssl/certs/ci.cluster.local.crt` AND `/etc/ssl/private/ci.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Generates self-signed certificate (guard: skip if both `/etc/ssl/certs/status.cluster.local.crt` AND `/etc/ssl/private/status.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - HTTP block: `listen 80`, returns 301 redirect to HTTPS
      - HTTPS block: `listen 443 ssl http2`, `root /opt/server/test`, `index index.html index.htm index.php`, ssl_certificate/ssl_certificate_key, TLSv1.2/TLSv1.3, HSTS header, security headers, gzip, `location /` with try_files, deny `.ht*` and `.git/.svn` locations
    - Creates symlink `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - HTTP block: `listen 80`, returns 301 redirect to HTTPS
      - HTTPS block: `listen 443 ssl http2`, `root /opt/server/ci`, `index index.html index.htm index.php`, ssl_certificate/ssl_certificate_key, TLSv1.2/TLSv1.3, HSTS header, security headers, gzip, `location /` with try_files, deny `.ht*` and `.git/.svn` locations
    - Creates symlink `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - HTTP block: `listen 80`, returns 301 redirect to HTTPS
      - HTTPS block: `listen 443 ssl http2`, `root /opt/server/status`, `index index.html index.htm index.php`, ssl_certificate/ssl_certificate_key, TLSv1.2/TLSv1.3, HSTS header, security headers, gzip, `location /` with try_files, deny `.ht*` and `.git/.svn` locations
    - Creates symlink `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
- Deletes `/etc/nginx/sites-enabled/default` (removes the default nginx placeholder site)
  - Notifies: delayed reload of `service[nginx]`
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed: enabled + started; reloaded on config/cert/site changes
- `fail2ban` — managed: enabled + started; restarted on jail.local changes
- `ssh` (sshd) — managed: restarted only when sshd_config is modified (action :nothing, notified by conditionals)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — these are development/internal certificates and do not involve any stored secrets. The certificate files themselves (`.crt`, `.key`) are generated on the target host and are not sourced from a secrets manager.

> **Note for Solutions Architect**: If this cookbook is being migrated for a production environment, the self-signed certificate generation should be replaced with certificates sourced from a proper PKI (e.g., Let's Encrypt via `certbot`, an internal CA, or certificates stored in HashiCorp Vault / AWS ACM). The `admin@example.com` email and `Example Org` subject fields are placeholders and must be updated.

## Checks for the Migration

**Files to verify**:

| File/Directory | Type | Expected |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Rendered from nginx.conf.erb |
| `/etc/nginx/conf.d/security.conf` | Config | Rendered from security.conf.erb |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Rendered from site.conf.erb |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Rendered from site.conf.erb |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Rendered from site.conf.erb |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → /etc/nginx/sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → /etc/nginx/sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → /etc/nginx/sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | Deployed from files/default/test/index.html |
| `/opt/server/ci/index.html` | Static file | Deployed from files/default/ci/index.html |
| `/opt/server/status/index.html` | Static file | Deployed from files/default/status/index.html |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Generated by openssl, 365-day self-signed |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Generated by openssl, 365-day self-signed |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Generated by openssl, 365-day self-signed |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | Rendered from fail2ban.jail.local.erb |
| `/etc/sysctl.d/99-security.conf` | Config | Rendered from sysctl-security.conf.erb |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Renders |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 time (global) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 time (global) |
| `site.conf.erb` | `/etc/nginx/sites-available/<site_name>` | 3 times: test.cluster.local, ci.cluster.local, status.cluster.local |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 time |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 time |

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx    # should output: enabled
systemctl is-enabled fail2ban # should output: enabled

# ============================================================
# 2. NGINX CONFIGURATION VALIDATION
# ============================================================
nginx -t
# Expected output: nginx: configuration file /etc/nginx/nginx.conf test is successful

# Verify global config key settings
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip' /etc/nginx/nginx.conf
grep 'server_tokens' /etc/nginx/conf.d/security.conf  # should output: server_tokens off;
grep 'ssl_protocols' /etc/nginx/conf.d/security.conf  # should output: ssl_protocols TLSv1.2 TLSv1.3;

# Verify default site is removed
ls -la /etc/nginx/sites-enabled/default 2>&1  # should output: No such file or directory

# ============================================================
# 3. VIRTUAL HOST: test.cluster.local
# ============================================================
# Config file exists and is valid
cat /etc/nginx/sites-available/test.cluster.local
grep 'server_name test.cluster.local' /etc/nginx/sites-available/test.cluster.local
grep 'ssl_certificate /etc/ssl/certs/test.cluster.local.crt' /etc/nginx/sites-available/test.cluster.local
grep 'return 301' /etc/nginx/sites-available/test.cluster.local  # HTTP→HTTPS redirect present

# Symlink is correct
ls -la /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-enabled/test.cluster.local -> /etc/nginx/sites-available/test.cluster.local

# Document root and index file
ls -lah /opt/server/test/index.html  # should exist, owner www-data:www-data, mode 0644
stat -c "%U:%G %a" /opt/server/test/index.html  # should output: www-data:www-data 644

# HTTP redirect check (requires DNS or /etc/hosts entry)
curl -I http://test.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://test.cluster.local/

# HTTPS response (skip cert verification for self-signed)
curl -k -I https://test.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport'
# Expected: HTTP/1.1 200 OK + Strict-Transport-Security header

# Per-site log files exist
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. VIRTUAL HOST: ci.cluster.local
# ============================================================
cat /etc/nginx/sites-available/ci.cluster.local
grep 'server_name ci.cluster.local' /etc/nginx/sites-available/ci.cluster.local
grep 'ssl_certificate /etc/ssl/certs/ci.cluster.local.crt' /etc/nginx/sites-available/ci.cluster.local
grep 'return 301' /etc/nginx/sites-available/ci.cluster.local  # HTTP→HTTPS redirect present

# Symlink is correct
ls -la /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-enabled/ci.cluster.local -> /etc/nginx/sites-available/ci.cluster.local

# Document root and index file
ls -lah /opt/server/ci/index.html  # should exist, owner www-data:www-data, mode 0644
stat -c "%U:%G %a" /opt/server/ci/index.html  # should output: www-data:www-data 644

# HTTP redirect check (requires DNS or /etc/hosts entry)
curl -I http://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://ci.cluster.local/

# HTTPS response (skip cert verification for self-signed)
curl -k -I https://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport'
# Expected: HTTP/1.1 200 OK + Strict-Transport-Security header

# Per-site log files exist
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. VIRTUAL HOST: status.cluster.local
# ============================================================
cat /etc/nginx/sites-available/status.cluster.local
grep 'server_name status.cluster.local' /etc/nginx/sites-available/status.cluster.local
grep 'ssl_certificate /etc/ssl/certs/status.cluster.local.crt' /etc/nginx/sites-available/status.cluster.local
grep 'return 301' /etc/nginx/sites-available/status.cluster.local  # HTTP→HTTPS redirect present

# Symlink is correct
ls -la /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-enabled/status.cluster.local -> /etc/nginx/sites-available/status.cluster.local

# Document root and index file
ls -lah /opt/server/status/index.html  # should exist, owner www-data:www-data, mode 0644
stat -c "%U:%G %a" /opt/server/status/index.html  # should output: www-data:www-data 644

# HTTP redirect check (requires DNS or /etc/hosts entry)
curl -I http://status.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://status.cluster.local/

# HTTPS response (skip cert verification for self-signed)
curl -k -I https://status.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport'
# Expected: HTTP/1.1 200 OK + Strict-Transport-Security header

# Per-site log files exist
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. SSL CERTIFICATES
# ============================================================
# test.cluster.local certificate
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat -c "%U:%G %a" /etc/ssl/private/test.cluster.local.key  # should output: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
# Expected: subject=CN=test.cluster.local, notAfter=<365 days from generation>

# ci.cluster.local certificate
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat -c "%U:%G %a" /etc/ssl/private/ci.cluster.local.key  # should output: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
# Expected: subject=CN=ci.cluster.local

# status.cluster.local certificate
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl