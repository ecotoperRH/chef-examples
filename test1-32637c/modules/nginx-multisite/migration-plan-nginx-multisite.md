---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened Nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures Nginx with self-signed TLS certificates, deploys per-site static HTML landing pages, hardens the OS with UFW firewall rules, kernel sysctl security parameters, and Fail2Ban intrusion prevention, and locks down SSH by disabling root login and password authentication.

---

## Service Type and Instances

**Service Type**: Web Server (Nginx multi-site / reverse proxy with SSL termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: Self-signed cert, TLSv1.2+TLSv1.3, HSTS enabled, security headers, gzip on
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: Self-signed cert, TLSv1.2+TLSv1.3, HSTS enabled, security headers, gzip on
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status page virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: Self-signed cert, TLSv1.2+TLSv1.3, HSTS enabled, security headers, gzip on
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`

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
- Entry point. Includes 4 sub-recipes in strict order: `security` → `nginx` → `ssl` → `sites`.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys Fail2Ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall with 5 execute resources (all idempotent via `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (skipped if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already listed)
  - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already listed)
  - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already listed)
  - `ufw_enable`: `ufw --force enable` (skipped if "Status: active")
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — `if node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: `service[ssh]` restart (delayed)
- **Conditional** — `if node['security']['ssh']['password_auth'] == false` (default: false, so condition IS met):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` declared with `action :nothing` — only triggered by the above notifies
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh hardening)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global Nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Config: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys Nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Config: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), client buffer limits (body=1K, header=1k, max_body=1k, large_headers=2×1k), timeouts (body=10, header=10, send=10), SSL session cache (shared:SSL:10m, timeout=10m), TLSv1.2+TLSv1.3, strong cipher suite, `ssl_prefer_server_ciphers on`
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts `nginx` service
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local** (document_root: `/opt/server/test`):
    - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: source=`test/index.html`, owner=www-data, group=www-data, mode=0644
  - **ci.cluster.local** (document_root: `/opt/server/ci`):
    - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: source=`ci/index.html`, owner=www-data, group=www-data, mode=0644
  - **status.cluster.local** (document_root: `/opt/server/status`):
    - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: source=`status/index.html`, owner=www-data, group=www-data, mode=0644
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: Generates self-signed cert (RSA 2048-bit, 365 days)
      - keyout: `/etc/ssl/private/test.cluster.local.key`
      - out: `/etc/ssl/certs/test.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skips if both `.crt` and `.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: Generates self-signed cert (RSA 2048-bit, 365 days)
      - keyout: `/etc/ssl/private/ci.cluster.local.key`
      - out: `/etc/ssl/certs/ci.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skips if both `.crt` and `.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: Generates self-signed cert (RSA 2048-bit, 365 days)
      - keyout: `/etc/ssl/private/status.cluster.local.key`
      - out: `/etc/ssl/certs/status.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640` on key, `chown root:ssl-cert` on key
      - Guard: `not_if` — skips if both `.crt` and `.key` already exist
      - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=`test.cluster.local`, document_root=`/opt/server/test`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/test.cluster.local.crt`, key_file=`/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with SSL, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=`ci.cluster.local`, document_root=`/opt/server/ci`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/ci.cluster.local.crt`, key_file=`/etc/ssl/private/ci.cluster.local.key`
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=`status.cluster.local`, document_root=`/opt/server/status`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/status.cluster.local.crt`, key_file=`/etc/ssl/private/status.cluster.local.key`
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes `/etc/nginx/sites-enabled/default` (removes the default Nginx placeholder site)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed: enabled + started; reloaded on any config/cert/site change
- `fail2ban` — managed: enabled + started; restarted on jail.local change
- `ssh` (sshd) — managed: restarted only when sshd_config is modified (action :nothing, triggered by notify)

---

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/emailAddress=admin@example.com`) — these are development/internal certificates and contain no secrets. The private keys are generated at runtime on the target host and are never stored in the cookbook.

> **Note for Solutions Architect**: If this cookbook is migrated to production, the self-signed certificate generation should be replaced with a proper PKI workflow (e.g., Let's Encrypt via `certbot`, or certificates delivered from a secrets manager). The `admin@example.com` email and `Example Org` subject fields are placeholders and must be updated.

---

## Checks for the Migration

**Files to verify**:

*Nginx configuration:*
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/ci.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/status.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/default` — must NOT exist (deleted)

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
- Port 80 (HTTP → HTTPS redirect, all 3 sites)
- Port 443 (HTTPS/SSL, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — rendered **1 time**
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — rendered **1 time**
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — rendered **1 time**
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` — rendered **1 time**

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl status ssh

ps aux | grep nginx
ps aux | grep fail2ban

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# ============================================================
# 3. NETWORK PORTS
# ============================================================
ss -tlnp | grep -E ':80|:443'
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 4. VIRTUAL HOST: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://test.cluster.local
# HTTPS response (expect: 200 OK, self-signed cert warning is normal)
curl -I -k https://test.cluster.local
# Verify index.html content
curl -sk https://test.cluster.local | grep -q "Test Environment" && echo "PASS: test.cluster.local content OK" || echo "FAIL: test.cluster.local content missing"
# Verify security headers
curl -sk -I https://test.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection'
# Verify SSL certificate CN
echo | openssl s_client -connect test.cluster.local:443 -servername test.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and file
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html | grep -E 'Uid|Gid|Access'

# ============================================================
# 5. VIRTUAL HOST: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://ci.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://ci.cluster.local
# Verify index.html content
curl -sk https://ci.cluster.local | grep -q "CI/CD Dashboard" && echo "PASS: ci.cluster.local content OK" || echo "FAIL: ci.cluster.local content missing"
# Verify security headers
curl -sk -I https://ci.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options'
# Verify SSL certificate CN
echo | openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and file
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html | grep -E 'Uid|Gid|Access'

# ============================================================
# 6. VIRTUAL HOST: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://status.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://status.cluster.local
# Verify index.html content
curl -sk https://status.cluster.local | grep -q "System Status" && echo "PASS: status.cluster.local content OK" || echo "FAIL: status.cluster.local content missing"
# Verify security headers
curl -sk -I https://status.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options'
# Verify SSL certificate CN
echo | openssl s_client -connect status.cluster.local:443 -servername status.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and file
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html | grep -E 'Uid|Gid|Access'

# ============================================================
# 7. SSL CERTIFICATES AND KEYS
# ============================================================
# test.cluster.local
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
stat /etc/ssl/private/test.cluster.local.key | grep Access  # should be 640, root:ssl-cert

# ci.cluster.local
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
stat /etc/ssl/private/ci.cluster.local.key | grep Access  # should be 640, root:ssl-cert

# status.cluster.local
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
stat /etc/ssl/private/status.cluster.local.key | grep Access  # should be 640, root:ssl-cert

# Verify ssl-cert group exists
getent group ssl-cert

# Verify private key directory permissions (should be 0710, root:ssl-cert)
stat /etc/ssl/private | grep -E 'Access|Uid|Gid'

# ============================================================
# 8. NGINX SITE CONFIGURATION FILES AND SYMLINKS
# ============================================================
# Verify sites-available configs exist
ls -lah /etc/nginx/sites-available/test.cluster.local
ls -lah /etc/nginx/sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-available/status.cluster.local

# Verify symlinks in sites-enabled
ls -lah /etc/nginx/sites-enabled/test.cluster.local   # should be symlink → sites-available/test.cluster.local
ls -lah /etc/nginx/sites-enabled/ci.cluster.local     # should be symlink → sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-enabled/status.cluster.local # should be symlink → sites-available/status.cluster.local

# Verify default site is REMOVED
ls /etc/nginx/sites-enabled/default 2>/dev/null && echo "FAIL: default site still present" || echo "PASS: default site removed"

# Verify site config content
grep -E 'ssl_certificate|ssl_certificate_key|server_name|root|return 301' /etc/nginx/sites-available/test.cluster.local
grep -E 'ssl_certificate|ssl_certificate_key|server_name|root|return 301' /etc/nginx/sites-available/ci.cluster.local
grep -E 'ssl_certificate|ssl_certificate_key|server_name|root|return 301' /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 9. NGINX GLOBAL AND SECURITY CONFIG
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip|sendfile'
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|ssl_protocols|ssl_ciphers|client_max_body_size'

# ============================================================
# 10. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Expected output should show:
#   Status: active
#   Default: deny (incoming)
#   22/tcp (ssh) ALLOW IN
#   80/tcp (http) ALLOW IN
#   443/tcp (https) ALLOW IN
ufw status | grep -E 'Status: active|22|80|443'

# ============================================================
# 11. FAIL2BAN
# ============================================================
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|enabled'

# ============================================================
# 12. SYSCTL KERNEL HARDENING
# ============================================================
sysctl net.ipv4.conf.all.rp_filter          # should be 1
sysctl net.ipv4.conf.all.accept_redirects   # should be 0
sysctl net.ipv4.conf.all.send_redirects     # should be 0
sysctl net.ipv4.conf.all.log_martians       # should be 1
sysctl net.ipv4.icmp_echo_ignore_all        # should be 1
sysctl net.ipv4.tcp_syncookies              # should be 1
sysctl net.ipv4.tcp_max_syn_backlog         # should be 2048
sysctl net.ipv6.conf.all.disable_ipv6       # should be 1
cat /etc/sysctl.d/99-security.conf

# ============================================================
# 13. SSH HARDENING
# ============================================================
grep '^PermitRootLogin' /etc/ssh/sshd_config        # should be: PermitRootLogin no
grep '^PasswordAuthentication' /etc/ssh/sshd_config  # should be: PasswordAuthentication no
sshd -T | grep -E 'permitrootlogin|passwordauthentication'

# ============================================================
# 14. NGINX LOGS
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 15. FAIL2BAN LOGS
# ============================================================
tail -20 /var/log/fail2ban.log
grep -E 'Ban|Unban|Found' /var/log/fail2ban.log | tail -20
```