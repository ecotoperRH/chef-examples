---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 virtual sites (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with SSL/TLS enabled via self-signed certificates. It also applies a full security baseline: UFW firewall rules, fail2ban intrusion prevention with nginx-specific jails, kernel-level sysctl hardening, and SSH hardening (root login disabled, password authentication disabled). All 3 sites serve static HTML content from `/opt/server/{test,ci,status}` and are configured with HTTP→HTTPS redirects, security headers, and per-site access/error logs.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multisite with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, HTTP→HTTPS redirect (301), HSTS enabled, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, HTTP→HTTPS redirect (301), HSTS enabled, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, HTTP→HTTPS redirect (301), HSTS enabled, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`

---

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

---

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point that chains all four sub-recipes in order
- Resources: include_recipe (4)
- Execution order: security → nginx → ssl → sites

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via 5 idempotent execute resources:
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` is true (default: true):
  - `execute[disable root login]`: runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- Conditional: if `node['security']['ssh']['password_auth']` is false (default: false):
  - `execute[disable password auth]`: runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` declared with `action :nothing` — only triggered by the above notifiers
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh conditionals)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limiting zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, client_body_timeout=10, client_header_timeout=10, send_timeout=10, ssl_session_cache=shared:SSL:10m, ssl_protocols=TLSv1.2 TLSv1.3, ssl_ciphers=ECDHE-RSA-AES256-GCM-SHA512:..., ssl_prefer_server_ciphers=on
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations — runs 3 times for sites:
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
- Creates SSL certificate directory: `directory[/etc/ssl/certs]` — owner=root, group=root, mode=0755
- Creates SSL private key directory: `directory[/etc/ssl/private]` — owner=root, group=ssl-cert, mode=0710
- Iterations — runs 3 times for sites (all have ssl_enabled=true):
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`:
      - Generates self-signed cert: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - Sets key permissions: `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - Sets key ownership: `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
      - Idempotent: skipped if both `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`:
      - Generates self-signed cert: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - Sets key permissions: `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - Sets key ownership: `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
      - Idempotent: skipped if both `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`:
      - Generates self-signed cert: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - Sets key permissions: `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - Sets key ownership: `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
      - Idempotent: skipped if both `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations — runs 3 times for sites:
  - **test.cluster.local**:
    - `template[/etc/nginx/sites-available/test.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Rendered config: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443 ssl http2) with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, try_files, deny .ht/.git/.svn
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]`: symlink → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `template[/etc/nginx/sites-available/ci.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Rendered config: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443 ssl http2) with ci-specific paths and server_name
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]`: symlink → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `template[/etc/nginx/sites-available/status.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables passed: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Rendered config: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443 ssl http2) with status-specific paths and server_name
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]`: symlink → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- `file[/etc/nginx/sites-enabled/default]`: action=delete (removes the default nginx site)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata.rb)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — SSL certificate generation tooling
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed: enabled + started; reloaded on config/cert/site changes
- `fail2ban` — managed: enabled + started; restarted on jail.local changes
- `ssh` (sshd) — managed: restarted only when sshd_config is modified (action :nothing, triggered by notifiers)

---

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/emailAddress=admin@example.com`) — this subject string is not a secret but should be reviewed and customized for production use. No passwords, tokens, private keys, or data bag references exist anywhere in the cookbook.

---

## Checks for the Migration

**Files to verify**:

*nginx configuration:*
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/ci.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/status.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/default` (must NOT exist — deleted)

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
- Port 80 (HTTP redirect only) — all 3 sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
- Port 443 (HTTPS) — all 3 sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
- Unix sockets: none
- Network interfaces: all interfaces (0.0.0.0)

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — rendered 1 time
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — rendered 1 time
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — rendered 1 time
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — rendered 1 time
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`, `/etc/nginx/sites-available/ci.cluster.local`, `/etc/nginx/sites-available/status.cluster.local` — rendered **3 times**

---

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
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# Verify default site is removed
ls -la /etc/nginx/sites-enabled/default && echo "ERROR: default site still exists" || echo "OK: default site removed"

# Verify global config
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip' /etc/nginx/nginx.conf
grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols' /etc/nginx/conf.d/security.conf

# ============================================================
# 3. SITE: test.cluster.local
# ============================================================
# Config file exists and is symlinked
ls -la /etc/nginx/sites-available/test.cluster.local
ls -la /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-available/test.cluster.local

# Document root and static file
ls -lah /opt/server/test/
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html | grep -E 'Uid|Gid|Access'
# Expected: www-data:www-data, mode 0644

# HTTP redirect check (expect 301)
curl -I -k http://test.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://test.cluster.local/

# HTTPS check (expect 200, -k for self-signed cert)
curl -I -k https://test.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport|X-Frame|X-Content'
# Expected: HTTP/1.1 200 OK
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains
# Expected: X-Frame-Options: DENY
# Expected: X-Content-Type-Options: nosniff

# SSL certificate details
openssl s_client -connect test.cluster.local:443 -servername test.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=test.cluster.local/...
# Expected: notAfter= (365 days from issuance)

# Per-site log files
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# Config file exists and is symlinked
ls -la /etc/nginx/sites-available/ci.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-available/ci.cluster.local

# Document root and static file
ls -lah /opt/server/ci/
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html | grep -E 'Uid|Gid|Access'
# Expected: www-data:www-data, mode 0644

# HTTP redirect check (expect 301)
curl -I -k http://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://ci.cluster.local/

# HTTPS check (expect 200)
curl -I -k https://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport|X-Frame|X-Content'
# Expected: HTTP/1.1 200 OK
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains
# Expected: X-Frame-Options: DENY
# Expected: X-Content-Type-Options: nosniff

# SSL certificate details
openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=ci.cluster.local/...
# Expected: notAfter= (365 days from issuance)

# Per-site log files
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# Config file exists and is symlinked
ls -la /etc/nginx/sites-available/status.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-available/status.cluster.local

# Document root and static file
ls -lah /opt/server/status/
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html | grep -E 'Uid|Gid|Access'
# Expected: www-data:www-data, mode 0644

# HTTP redirect check (expect 301)
curl -I -k http://status.cluster.local 2>/dev/null | grep -E 'HTTP|Location'
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://status.cluster.local/

# HTTPS check (expect 200)
curl -I -k https://status.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport|X-Frame|X-Content'
# Expected: HTTP/1.1 200 OK
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains
# Expected: X-Frame-Options: DENY
# Expected: X-Content-Type-Options: nosniff

# SSL certificate details
openssl s_client -connect status.cluster.local:443 -servername status.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=status.cluster.local/...
# Expected: notAfter= (365 days from issuance)

# Per-site log files
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. SSL CERTIFICATE FILE PERMISSIONS
# ============================================================
# Certificates (should be readable by nginx)
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/certs/status.cluster.local.crt

# Private keys (should be 0640, owned root:ssl-cert)
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: Access: (0640/-rw-r-----) Uid: (0/root) Gid: (.../ssl-cert)

stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: Access: (0640/-rw-r-----) Uid: (0/root) Gid: (.../ssl-cert)

stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: Access: (0640/-rw-r-----) Uid: (0/root) Gid: (.../ssl-cert)

# ssl-cert group membership (nginx user should be in ssl-cert group)
getent group ssl-cert
id www-data

# ============================================================
# 7. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Expected: Status: active
# Expected: Default: deny (incoming), allow (outgoing)
# Expected: 22/tcp (ssh) ALLOW IN
# Expected: 80/tcp (http) ALLOW IN
# Expected: 443/tcp (https) ALLOW IN

ufw status numbered | grep -E '22|80|443'

# ============================================================
# 8. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: Number of jail: 4 active jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch)

fail2ban-client status sshd
# Expected: Currently banned: 0 (or more), Filter: enabled

fail2ban-client status nginx-http-auth
# Expected: Currently banned: 0 (or more), Filter: enabled

fail2ban-client status nginx-limit-req
# Expected: Currently banned: 0 (or more), Filter: enabled

fail2ban-client status nginx-botsearch
# Expected: Currently banned: 0 (or more), Filter: enabled

grep -E 'bantime|findtime|maxretry|enabled' /etc/fail2ban/jail.local

# ============================================================
# 9. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf

sysctl net.ipv4.conf.all.rp_filter           # Expected: 1
sysctl net.ipv4.conf.all.accept_redirects    # Expected: 0
sysctl net.ipv6.conf.all.accept_redirects    # Expected: 0
sysctl net.ipv4.conf.all.send_redirects      # Expected: 0
sysctl net.ipv4.conf.all.accept_source_route # Expected: 0
sysctl net.ipv4.conf.all.log_martians        # Expected: 1
sysctl net.ipv4.icmp_echo_ignore_all         # Expected: 1
sysctl net.ipv4.icmp_echo_ignore_broadcasts  # Expected: 1
sysctl net.ipv6.conf.all.disable_ipv6        # Expected: 1
sysctl net.ipv4.tcp_syncookies               # Expected: 1
sysctl net.ipv4.tcp_max_syn_backlog          # Expected: 2048

# ============================================================
# 10. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config
# Expected: PermitRootLogin no

grep -E '^PasswordAuthentication' /etc/ssh/sshd_config
# Expected: PasswordAuthentication no

sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# Expected: permitrootlogin no
# Expected: passwordauthentication no

# ============================================================
# 11. NETWORK PORTS
# ============================================================
ss -tlnp | grep -E ':80|:443'
# Expected: nginx listening on 0.0.0.0:80 and 0.0.0.0:443

netstat -tulpn | grep nginx
lsof -i :80 -i :443 | grep nginx

# ============================================================
# 12. LOGS
# ============================================================
# Global nginx logs
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log

# Per-site access logs
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_access.log

# Per-site error logs
tail -20 /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# Fail2ban log
tail -20 /var/log/fail2ban.log

# Auth log (for SSH ban activity)
tail -20 /var/log/auth.log

# Systemd journal
journalctl -u nginx --no-pager -n 30
journalctl -u fail2ban --no-pager -n 30
```