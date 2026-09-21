---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on Ubuntu/CentOS. It installs nginx with a global security configuration, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations with HTTP→HTTPS redirects, and hardens the host with UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl security parameters. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site with host hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/test.cluster.local.crt`, key: `/etc/ssl/private/test.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), per-site access/error logs

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/ci.cluster.local.crt`, key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers, per-site access/error logs

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP 80 (redirects to HTTPS), HTTPS 443
  - SSL: Enabled — certificate: `/etc/ssl/certs/status.cluster.local.crt`, key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers, per-site access/error logs

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
cookbooks/nginx-multisite/attributes/default.rb
cookbooks/nginx-multisite/files/default/test/index.html
cookbooks/nginx-multisite/files/default/ci/index.html
cookbooks/nginx-multisite/files/default/status/index.html
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point that chains all four sub-recipes in order
- Resources: include_recipe (4): security, nginx, ssl, sites

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs security packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: delayed restart of `fail2ban` service
- Configures UFW firewall with 5 execute resources (all idempotent via `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (skipped if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already listed)
  - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already listed)
  - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already listed)
  - `ufw_enable`: `ufw --force enable` (skipped if already "Status: active")
- Deploys kernel hardening configuration:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: delayed restart of `service[ssh]`
- Conditional: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: delayed restart of `service[ssh]`
- `service[ssh]` declared with `action :nothing` — only triggered by the above notifiers
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh hardening)

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
  - Settings: `server_tokens off`, rate-limit zones (`login` 10r/m, `api` 30r/m), buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (body/header/send = 10s), SSL global settings (TLSv1.2/TLSv1.3, cipher suite, `ssl_prefer_server_ciphers on`, session cache 10m)
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `service[nginx]`
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: source=`files/default/test/index.html`, owner=www-data, group=www-data, mode=0644
  - **ci.cluster.local**:
    - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: source=`files/default/ci/index.html`, owner=www-data, group=www-data, mode=0644
  - **status.cluster.local**:
    - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: source=`files/default/status/index.html`, owner=www-data, group=www-data, mode=0644
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites (all have `ssl_enabled: true`, so none are skipped): **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: generates self-signed cert (RSA 2048, 365 days)
      - keyout: `/etc/ssl/private/test.cluster.local.key`
      - out: `/etc/ssl/certs/test.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skipped if both cert and key files already exist
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: generates self-signed cert (RSA 2048, 365 days)
      - keyout: `/etc/ssl/private/ci.cluster.local.key`
      - out: `/etc/ssl/certs/ci.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skipped if both cert and key files already exist
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: generates self-signed cert (RSA 2048, 365 days)
      - keyout: `/etc/ssl/private/status.cluster.local.key`
      - out: `/etc/ssl/certs/status.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skipped if both cert and key files already exist
      - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - `template[/etc/nginx/sites-available/test.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with SSL, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip, `try_files`, deny `.ht*` and `.git/.svn` locations, access_log `/var/log/nginx/test.cluster.local_access.log`, error_log `/var/log/nginx/test.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - `template[/etc/nginx/sites-available/ci.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with SSL, HSTS, security headers, per-site access_log `/var/log/nginx/ci.cluster.local_access.log`, error_log `/var/log/nginx/ci.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - `template[/etc/nginx/sites-available/status.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with SSL, HSTS, security headers, per-site access_log `/var/log/nginx/status.cluster.local_access.log`, error_log `/var/log/nginx/status.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- `file[/etc/nginx/sites-enabled/default]`: action=delete (removes the default nginx placeholder site)
  - Notifies: delayed reload of `service[nginx]`
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed: enabled + started; reloaded on config/cert/site changes
- `fail2ban` — managed: enabled + started; restarted on jail.local changes
- `ssh` (sshd) — managed: action=nothing, restarted only when sshd_config is modified by hardening steps

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`O=Example Org`, `emailAddress=admin@example.com`) and are not sourced from any secret store. The certificate subject fields are static strings embedded directly in the recipe, not retrieved from a vault or data bag.

> **Note for the Solutions Architect**: When migrating to Ansible/AAP, if real (CA-signed) certificates are required instead of self-signed ones, certificate private keys and signed certificate bodies will need to be sourced from a secrets manager (e.g., HashiCorp Vault, CyberArk, or AAP Credential Store) and injected as variables. This is not currently handled by the Chef cookbook.

## Checks for the Migration

**Files to verify**:

*nginx global configuration:*
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`

*Per-site nginx configurations (sites-available):*
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`

*Per-site nginx symlinks (sites-enabled):*
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`

*Default site removed:*
- `/etc/nginx/sites-enabled/default` — must NOT exist

*Document roots and static files:*
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`

*SSL certificates and keys:*
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`

*Security configuration:*
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config` (PermitRootLogin no, PasswordAuthentication no)

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: none
- Network interfaces: all interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — rendered **1 time**
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — rendered **1 time**
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — rendered **1 time**
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` — rendered **1 time**

Total: `site.conf.erb` renders **3 times** (once per site); all other templates render once each.

## Pre-flight checks:
```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban
ps aux | grep nginx | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# Verify default site is removed
ls -la /etc/nginx/sites-enabled/default && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 3. SITE: test.cluster.local
# ============================================================
# Config file and symlink
ls -la /etc/nginx/sites-available/test.cluster.local
ls -la /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local  # should point to /etc/nginx/sites-available/test.cluster.local

# Document root and static file
ls -lah /opt/server/test/
ls -lah /opt/server/test/index.html
stat -c "%U %G %a" /opt/server/test          # should show: www-data www-data 755
stat -c "%U %G %a" /opt/server/test/index.html  # should show: www-data www-data 644

# SSL certificate and key
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/test.cluster.local.key  # should show: root ssl-cert 640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"

# HTTP → HTTPS redirect
curl -I -k http://test.cluster.local 2>/dev/null | grep -E "HTTP|Location"
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://test.cluster.local/

# HTTPS response
curl -I -k https://test.cluster.local 2>/dev/null | grep -E "HTTP|Strict-Transport|X-Frame"
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# Per-site log files
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# Config file and symlink
ls -la /etc/nginx/sites-available/ci.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local  # should point to /etc/nginx/sites-available/ci.cluster.local

# Document root and static file
ls -lah /opt/server/ci/
ls -lah /opt/server/ci/index.html
stat -c "%U %G %a" /opt/server/ci          # should show: www-data www-data 755
stat -c "%U %G %a" /opt/server/ci/index.html  # should show: www-data www-data 644

# SSL certificate and key
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/ci.cluster.local.key  # should show: root ssl-cert 640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"

# HTTP → HTTPS redirect
curl -I -k http://ci.cluster.local 2>/dev/null | grep -E "HTTP|Location"
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://ci.cluster.local/

# HTTPS response
curl -I -k https://ci.cluster.local 2>/dev/null | grep -E "HTTP|Strict-Transport|X-Frame"
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# Per-site log files
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# Config file and symlink
ls -la /etc/nginx/sites-available/status.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local  # should point to /etc/nginx/sites-available/status.cluster.local

# Document root and static file
ls -lah /opt/server/status/
ls -lah /opt/server/status/index.html
stat -c "%U %G %a" /opt/server/status          # should show: www-data www-data 755
stat -c "%U %G %a" /opt/server/status/index.html  # should show: www-data www-data 644

# SSL certificate and key
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/status.cluster.local.key  # should show: root ssl-cert 640
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"

# HTTP → HTTPS redirect
curl -I -k http://status.cluster.local 2>/dev/null | grep -E "HTTP|Location"
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://status.cluster.local/

# HTTPS response
curl -I -k https://status.cluster.local 2>/dev/null | grep -E "HTTP|Strict-Transport|X-Frame"
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# Per-site log files
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. SSL DIRECTORY PERMISSIONS
# ============================================================
stat -c "%U %G %a" /etc/ssl/certs    # should show: root root 755
stat -c "%U %G %a" /etc/ssl/private  # should show: root ssl-cert 710
getent group ssl-cert                 # should show ssl-cert group exists

# ============================================================
# 7. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Expected output must include:
#   Status: active
#   Default: deny (incoming)
#   22/tcp (SSH) ALLOW IN
#   80/tcp (HTTP) ALLOW IN
#   443/tcp (HTTPS) ALLOW IN
ufw status | grep -E "Status: active"
ufw status | grep -E "22|ssh"
ufw status | grep -E "80|http"
ufw status | grep -E "443|https"

# ============================================================
# 8. FAIL2BAN
# ============================================================
systemctl status fail2ban
fail2ban-client status
# Expected: 5 jails listed: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch

fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Verify jail.local configuration
cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|findtime'
# Expected: bantime=3600, findtime=600, maxretry=3 (DEFAULT), maxretry=10 (nginx-limit-req), maxretry=2 (nginx-botsearch)

# ============================================================
# 9. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter          # should be 1
sysctl net.ipv4.conf.all.accept_redirects   # should be 0
sysctl net.ipv4.conf.all.send_redirects     # should be 0
sysctl net.ipv4.conf.all.accept_source_route # should be 0
sysctl net.ipv4.conf.all.log_martians       # should be 1
sysctl net.ipv4.icmp_echo_ignore_all        # should be 1
sysctl net.ipv4.tcp_syncookies              # should be 1
sysctl net.ipv4.tcp_max_syn_backlog         # should be 2048
sysctl net.ipv6.conf.all.disable_ipv6       # should be 1

# ============================================================
# 10. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config
# Expected: PermitRootLogin no

grep -E '^PasswordAuthentication' /etc/ssh/sshd_config
# Expected: PasswordAuthentication no

systemctl status ssh
# Expected: active (running)

# ============================================================
# 11. NETWORK PORTS
# ============================================================
ss -tlnp | grep -E ':80|:443'
# Expected: nginx listening on 0.0.0.0:80 and 0.0.0.0:443
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 12. NGINX GLOBAL CONFIG VALIDATION
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip'
# Expected: worker_processes auto, worker_connections 768, keepalive_timeout 65, gzip on

cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|client_max_body_size|ssl_protocols'
# Expected: server_tokens off, client_max_body_size 1k, ssl_protocols TLSv1.2 TLSv1.3

# ============================================================
# 13. LOGS
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log
journalctl -u nginx -n 50 --no-pager
journalctl -u fail2ban -n 50 --no-pager
```