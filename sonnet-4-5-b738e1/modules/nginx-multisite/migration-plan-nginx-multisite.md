---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx vhost configurations, and applies a layered security posture via UFW firewall rules, fail2ban intrusion prevention (5 jails), and kernel-level sysctl hardening. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multisite with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test` (document root)
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: SSL enabled, TLSv1.2+TLSv1.3, HSTS, security headers, gzip, per-site access/error logs at `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci` (document root)
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: SSL enabled, TLSv1.2+TLSv1.3, HSTS, security headers, gzip, per-site access/error logs at `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status page virtual host
  - Location/Path: `/opt/server/status` (document root)
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: SSL enabled, TLSv1.2+TLSv1.3, HSTS, security headers, gzip, per-site access/error logs at `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`

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
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb

cookbooks/nginx-multisite/attributes/default.rb

cookbooks/nginx-multisite/files/default/test/index.html
cookbooks/nginx-multisite/files/default/ci/index.html
cookbooks/nginx-multisite/files/default/status/index.html
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 sub-recipes in strict order: `security`, `nginx`, `ssl`, `sites`.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall via 5 execute resources (each guarded by `not_if`):
  - `ufw --force default deny` (skipped if default deny already set)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if UFW already active)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: IP spoofing protection (rp_filter=1), ICMP redirect ignore, source routing disabled, martian logging, ICMP ping ignore (icmp_echo_ignore_all=1), broadcast ping ignore, IPv6 disabled (disable_ipv6=1), TCP SYN flood protection (tcp_syncookies=1, tcp_max_syn_backlog=2048, tcp_synack_retries=2, tcp_syn_retries=5)
  - Notifies: delayed run of `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional**: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: delayed restart of `service[ssh]`
- **Conditional**: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: delayed restart of `service[ssh]`
- Declares `service[ssh]` with `action :nothing` (only triggered by notifies above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 UFW + reload_sysctl + 2 SSH sed)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Sets: user=www-data, worker_processes=auto, worker_connections=768, sendfile/tcp_nopush/tcp_nodelay on, keepalive_timeout=65, gzip on, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Sets: server_tokens off, rate limiting zones (login: 10r/m, api: 30r/m), client buffer limits (body=1K, header=1K, max_body=1K), timeouts (body/header/send=10s), global SSL settings (TLSv1.2+TLSv1.3, session cache 10m)
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `service[nginx]`
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner=www-data, group=www-data, mode=0644)
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner=www-data, group=www-data, mode=0644)
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner=www-data, group=www-data, mode=0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites where ssl_enabled=true: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local** (all 3 qualify)
  - **test.cluster.local**:
    - Executes `generate-ssl-cert-test.cluster.local` (guarded by `not_if` checking existence of both cert and key files):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Executes `generate-ssl-cert-ci.cluster.local` (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Executes `generate-ssl-cert-status.cluster.local` (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables passed: server_name=`test.cluster.local`, document_root=`/opt/server/test`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/test.cluster.local.crt`, key_file=`/etc/ssl/private/test.cluster.local.key`
      - Template renders: HTTP server block (port 80) with `return 301 https://...` redirect; HTTPS server block (port 443 ssl http2) with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3 ciphers, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy, gzip, `try_files`, deny `.ht*` and `.git/.svn` locations
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Deploys vhost config: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=`ci.cluster.local`, document_root=`/opt/server/ci`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/ci.cluster.local.crt`, key_file=`/etc/ssl/private/ci.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Deploys vhost config: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=`status.cluster.local`, document_root=`/opt/server/status`, ssl_enabled=`true`, cert_file=`/etc/ssl/certs/status.cluster.local.crt`, key_file=`/etc/ssl/private/status.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- Deletes `/etc/nginx/sites-enabled/default` (removes the default nginx placeholder site)
  - Notifies: delayed reload of `service[nginx]`
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `fail2ban` — intrusion prevention
- `ufw` — firewall management
- `nginx` — web server
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `fail2ban` — enabled + started; restarted on jail config change
- `nginx` — enabled + started; reloaded on any config/cert/vhost change
- `ssh` (sshd) — action :nothing; restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across all files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — these are development/internal certificates and do not embed any secret material in the cookbook itself.

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
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: none
- Network interfaces: all interfaces (nginx listens on `*:80` and `*:443`)

**Templates rendered**:
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: renders **1 time** (no loop)
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: renders **1 time** (no loop)
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: renders **1 time** (no loop)
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: renders **1 time** (no loop)
- `site.conf.erb` → `/etc/nginx/sites-available/<site_name>`: renders **3 times** (once per site: test.cluster.local, ci.cluster.local, status.cluster.local)

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
# 4. SITE: test.cluster.local
# ============================================================
# HTTP redirect check (should return 301)
curl -I -k http://test.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://test.cluster.local/

# HTTPS check (self-signed cert, use -k)
curl -I -k https://test.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers check
curl -sk https://test.cluster.local -I | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 5 headers present

# Document root and static file
ls -lah /opt/server/test/
cat /opt/server/test/index.html | grep -i "test environment"
# Expected: "Test Environment" title present

# SSL certificate details
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=test.cluster.local, notAfter ~365 days from issue

# SSL key permissions
ls -lah /etc/ssl/private/test.cluster.local.key
# Expected: -rw-r----- root ssl-cert (640)

# Per-site logs
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log
tail -5 /var/log/nginx/test.cluster.local_access.log

# ============================================================
# 5. SITE: ci.cluster.local
# ============================================================
# HTTP redirect check (should return 301)
curl -I -k http://ci.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://ci.cluster.local/

# HTTPS check
curl -I -k https://ci.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers check
curl -sk https://ci.cluster.local -I | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 5 headers present

# Document root and static file
ls -lah /opt/server/ci/
cat /opt/server/ci/index.html | grep -i "CI/CD"
# Expected: "CI/CD Dashboard" title present

# SSL certificate details
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=ci.cluster.local, notAfter ~365 days from issue

# SSL key permissions
ls -lah /etc/ssl/private/ci.cluster.local.key
# Expected: -rw-r----- root ssl-cert (640)

# Per-site logs
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log
tail -5 /var/log/nginx/ci.cluster.local_access.log

# ============================================================
# 6. SITE: status.cluster.local
# ============================================================
# HTTP redirect check (should return 301)
curl -I -k http://status.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://status.cluster.local/

# HTTPS check
curl -I -k https://status.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers check
curl -sk https://status.cluster.local -I | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 5 headers present

# Document root and static file
ls -lah /opt/server/status/
cat /opt/server/status/index.html | grep -i "System Status"
# Expected: "System Status" title present

# SSL certificate details
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=status.cluster.local, notAfter ~365 days from issue

# SSL key permissions
ls -lah /etc/ssl/private/status.cluster.local.key
# Expected: -rw-r----- root ssl-cert (640)

# Per-site logs
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log
tail -5 /var/log/nginx/status.cluster.local_access.log

# ============================================================
# 7. NGINX VHOST CONFIGURATION FILES
# ============================================================
# Verify sites-available configs exist
ls -lah /etc/nginx/sites-available/
# Expected: test.cluster.local, ci.cluster.local, status.cluster.local

# Verify symlinks in sites-enabled
ls -lah /etc/nginx/sites-enabled/
# Expected: test.cluster.local -> ../sites-available/test.cluster.local
#           ci.cluster.local    -> ../sites-available/ci.cluster.local
#           status.cluster.local -> ../sites-available/status.cluster.local
#           NO 'default' file

# Confirm default site is removed
test ! -f /etc/nginx/sites-enabled/default && echo "OK: default site removed" || echo "FAIL: default site still present"

# Verify SSL is configured in each vhost
grep -E 'ssl_certificate|ssl_certificate_key|listen 443' /etc/nginx/sites-available/test.cluster.local
grep -E 'ssl_certificate|ssl_certificate_key|listen 443' /etc/nginx/sites-available/ci.cluster.local
grep -E 'ssl_certificate|ssl_certificate_key|listen 443' /etc/nginx/sites-available/status.cluster.local

# Verify HTTP→HTTPS redirect in each vhost
grep 'return 301' /etc/nginx/sites-available/test.cluster.local
grep 'return 301' /etc/nginx/sites-available/ci.cluster.local
grep 'return 301' /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 8. NGINX GLOBAL CONFIG
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip'
# Expected: worker_processes auto, worker_connections 768, keepalive_timeout 65, gzip on

cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|ssl_protocols'
# Expected: server_tokens off, limit_req_zone for login and api, ssl_protocols TLSv1.2 TLSv1.3

# ============================================================
# 9. SSL DIRECTORY PERMISSIONS
# ============================================================
ls -lah /etc/ssl/certs/ | grep cluster
# Expected: 3 .crt files (test, ci, status)

ls -lah /etc/ssl/private/ | grep cluster
# Expected: 3 .key files with mode 640, owner root:ssl-cert

stat -c "%a %U:%G" /etc/ssl/private
# Expected: 710 root:ssl-cert

# ============================================================
# 10. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: Number of jail: 5 (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch + DEFAULT)

fail2ban-client status sshd
# Expected: Status for the jail: sshd, Currently banned: 0 (or more)

fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|findtime'
# Expected: bantime=3600, findtime=600, maxretry=3 (DEFAULT)

tail -20 /var/log/fail2ban.log

# ============================================================
# 11. UFW FIREWALL
# ============================================================
ufw status verbose
# Expected: Status: active
#           Default: deny (incoming), allow (outgoing)
#           22/tcp (ssh) ALLOW IN
#           80/tcp (http) ALLOW IN
#           443/tcp (https) ALLOW IN

ufw status | grep -E '22|80|443'
# Expected: all 3 ports listed as ALLOW

# ============================================================
# 12. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf | grep -E 'rp_filter|syncookies|disable_ipv6|icmp_echo_ignore_all'
# Expected: rp_filter=1, tcp_syncookies=1, disable_ipv6=1, icmp_echo_ignore_all=1

sysctl net.ipv4.conf.all.rp_filter
# Expected: net.ipv4.conf.all.rp_filter = 1

sysctl net.ipv4.tcp_syncookies
# Expected: net.ipv4.tcp_syncookies = 1

sysctl net.ipv6.conf.all.disable_ipv6
# Expected: net.ipv6.conf.all.disable_ipv6 = 1

sysctl net.ipv4.icmp_echo_ignore_all
# Expected: net.ipv4.icmp_echo_ignore_all = 1

# ============================================================
# 13. SSH HARDENING
# ============================================================
grep '^PermitRootLogin' /etc/ssh/sshd_config
# Expected: PermitRootLogin no

grep '^PasswordAuthentication' /etc/ssh/sshd_config
# Expected: PasswordAuthentication no

sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# Expected: permitrootlogin no, passwordauthentication no

# ============================================================
# 14. NGINX LOGS (GLOBAL)
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
# Expected: no critical errors; 301 redirects for HTTP, 200 for HTTPS

journalctl -u nginx --since "1 hour ago" | grep -i error
# Expected: no errors

# ============================================================
# 15. OWNER/PERMISSION CHECKS ON DOCUMENT ROOTS
# ============================================================
stat -c "%a %U:%G" /opt/server/test
# Expected: 755 www-data:www-data

stat -c "%a %U:%G" /opt/server/ci
# Expected: 755 www-data:www-data

stat -c "%a %U:%G" /opt/server/status
# Expected: 755 www-data:www-data

stat -c "%a %U:%G" /opt/server/test/index.html
# Expected: 644 www-data:www-data

stat -c "%a %U:%G" /opt/server/ci/index.html
# Expected: 644 www-data:www-data

stat -c "%a %U:%G" /opt/server/status/index.html
# Expected: 644 www-data:www-data
```