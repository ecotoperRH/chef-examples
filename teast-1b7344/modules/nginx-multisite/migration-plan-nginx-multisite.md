---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site static HTML content, and applies a layered security posture via UFW firewall rules, fail2ban intrusion prevention, kernel-level sysctl hardening, and SSH hardening. All three sites redirect HTTP→HTTPS and share a common nginx security configuration.

## Service Type and Instances

**Service Type**: Web Server (nginx multisite / reverse proxy with SSL termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, CN=test.cluster.local
  - Static content: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, CN=ci.cluster.local
  - Static content: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, CN=status.cluster.local
  - Static content: `files/default/status/index.html` → `/opt/server/status/index.html`

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
- Entry point. Includes 4 sub-recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall (idempotent, each guarded by `not_if`):
  - `ufw --force default deny` (sets default deny policy)
  - `ufw allow ssh` (opens port 22/tcp)
  - `ufw allow http` (opens port 80/tcp)
  - `ufw allow https` (opens port 443/tcp)
  - `ufw --force enable` (activates firewall)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Settings applied: IP spoofing protection (rp_filter=1), ICMP redirect ignore (accept_redirects=0), send_redirects=0, source routing disabled, log_martians=1, ICMP echo ignore (icmp_echo_ignore_all=1, icmp_echo_ignore_broadcasts=1), IPv6 disabled (disable_ipv6=1 for all/default/lo), TCP SYN flood protection (tcp_syncookies=1, tcp_max_syn_backlog=2048, tcp_synack_retries=2, tcp_syn_retries=5)
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` == true (default: true):
  - Runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
  - Guarded by `not_if "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"`
  - Notifies: `service[ssh]` restart (delayed)
- Conditional: if `node['security']['ssh']['password_auth']` == false (default: false):
  - Runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
  - Guarded by `not_if "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"`
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` declared with `action :nothing` (only triggered by notifications above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 reload_sysctl)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log, includes conf.d/*.conf and sites-enabled/*
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limiting zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, client_body_timeout=10, client_header_timeout=10, send_timeout=10, ssl_session_cache=shared:SSL:10m, ssl_session_timeout=10m, ssl_protocols=TLSv1.2 TLSv1.3, ssl_ciphers=ECDHE-RSA-AES256-GCM-SHA512:..., ssl_prefer_server_ciphers=on
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
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

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local** (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if { File.exist?(cert_file) && File.exist?(key_file) }`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2/1.3, HSTS header (max-age=31536000; includeSubDomains), X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy, gzip enabled, try_files, deny .ht/.git/.svn, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2/1.3, HSTS header (max-age=31536000; includeSubDomains), X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy, gzip enabled, try_files, deny .ht/.git/.svn, access_log=/var/log/nginx/ci.cluster.local_access.log, error_log=/var/log/nginx/ci.cluster.local_error.log
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2/1.3, HSTS header (max-age=31536000; includeSubDomains), X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy, gzip enabled, try_files, deny .ht/.git/.svn, access_log=/var/log/nginx/status.cluster.local_access.log, error_log=/var/log/nginx/status.cluster.local_error.log
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx vhost: `/etc/nginx/sites-enabled/default` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata.rb)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `nginx` — enabled, started; reloaded on config/cert/vhost changes
- `fail2ban` — enabled, started; restarted on jail.local changes
- `ssh` (sshd) — action :nothing; restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/emailAddress=admin@example.com`) — these are development/internal certificates and do not represent stored secrets. No data bags, Chef Vault, CyberArk, environment variables, or hardcoded passwords are present.

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

*Document roots and static content:*
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

*Log files:*
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`
- `/var/log/nginx/test.cluster.local_access.log`
- `/var/log/nginx/test.cluster.local_error.log`
- `/var/log/nginx/ci.cluster.local_access.log`
- `/var/log/nginx/ci.cluster.local_error.log`
- `/var/log/nginx/status.cluster.local_access.log`
- `/var/log/nginx/status.cluster.local_error.log`

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all three sites — redirect only), 443 (HTTPS, all three sites)
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — renders **1 time** (global config, no loop)
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — renders **1 time** (global security snippet, no loop)
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — renders **1 time** (static content, no variables)
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — renders **1 time** (static content, no variables)
- `site.conf.erb` → `/etc/nginx/sites-available/<site_name>` — renders **3 times**: once for `test.cluster.local`, once for `ci.cluster.local`, once for `status.cluster.local`

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
# 3. PORTS LISTENING
# ============================================================
ss -tlnp | grep -E ':80|:443'
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 4. SITE CONNECTIVITY - test.cluster.local
# ============================================================
# HTTP must redirect to HTTPS (301)
curl -I -H "Host: test.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently

# HTTPS must return 200 (skip cert validation for self-signed)
curl -k -I -H "Host: test.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify static content is served
curl -k -s -H "Host: test.cluster.local" https://localhost/ | grep -q "Test Environment"
echo "test.cluster.local content check: $?"  # Expected: 0

# Verify security headers
curl -k -I -H "Host: test.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 5. SITE CONNECTIVITY - ci.cluster.local
# ============================================================
# HTTP must redirect to HTTPS (301)
curl -I -H "Host: ci.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently

# HTTPS must return 200
curl -k -I -H "Host: ci.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify static content is served
curl -k -s -H "Host: ci.cluster.local" https://localhost/ | grep -q "CI/CD Dashboard"
echo "ci.cluster.local content check: $?"  # Expected: 0

# Verify security headers
curl -k -I -H "Host: ci.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 6. SITE CONNECTIVITY - status.cluster.local
# ============================================================
# HTTP must redirect to HTTPS (301)
curl -I -H "Host: status.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently

# HTTPS must return 200
curl -k -I -H "Host: status.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify static content is served
curl -k -s -H "Host: status.cluster.local" https://localhost/ | grep -q "System Status"
echo "status.cluster.local content check: $?"  # Expected: 0

# Verify security headers
curl -k -I -H "Host: status.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 7. VHOST CONFIGURATION FILES
# ============================================================
# Verify sites-available configs exist
ls -lah /etc/nginx/sites-available/test.cluster.local
ls -lah /etc/nginx/sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-available/status.cluster.local

# Verify symlinks in sites-enabled exist and point correctly
ls -lah /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-enabled/test.cluster.local -> /etc/nginx/sites-available/test.cluster.local
ls -lah /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-enabled/ci.cluster.local -> /etc/nginx/sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-enabled/status.cluster.local -> /etc/nginx/sites-available/status.cluster.local

# Verify default vhost is DELETED
ls /etc/nginx/sites-enabled/default 2>/dev/null && echo "FAIL: default vhost still exists" || echo "OK: default vhost removed"

# ============================================================
# 8. SSL CERTIFICATES
# ============================================================
# test.cluster.local certificate
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
# Expected: subject=.../CN=test.cluster.local, notAfter=~365 days from issue
openssl verify -CAfile /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/test.cluster.local.crt
stat -c "%a %U %G" /etc/ssl/private/test.cluster.local.key
# Expected: 640 root ssl-cert

# ci.cluster.local certificate
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
# Expected: subject=.../CN=ci.cluster.local
stat -c "%a %U %G" /etc/ssl/private/ci.cluster.local.key
# Expected: 640 root ssl-cert

# status.cluster.local certificate
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
# Expected: subject=.../CN=status.cluster.local
stat -c "%a %U %G" /etc/ssl/private/status.cluster.local.key
# Expected: 640 root ssl-cert

# Verify private key directory permissions
stat -c "%a %U %G" /etc/ssl/private
# Expected: 710 root ssl-cert

# ============================================================
# 9. DOCUMENT ROOTS AND STATIC FILES
# ============================================================
stat -c "%a %U %G" /opt/server/test
# Expected: 755 www-data www-data
stat -c "%a %U %G" /opt/server/ci
# Expected: 755 www-data www-data
stat -c "%a %U %G" /opt/server/status
# Expected: 755 www-data www-data

stat -c "%a %U %G" /opt/server/test/index.html
# Expected: 644 www-data www-data
stat -c "%a %U %G" /opt/server/ci/index.html
# Expected: 644 www-data www-data
stat -c "%a %U %G" /opt/server/status/index.html
# Expected: 644 www-data www-data

# ============================================================
# 10. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Expected: Status: active, Default: deny (incoming), allow (outgoing)
ufw status | grep -E "22/tcp|80/tcp|443/tcp"
# Expected: 22/tcp ALLOW IN Anywhere, 80/tcp ALLOW IN Anywhere, 443/tcp ALLOW IN Anywhere

# ============================================================
# 11. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: Number of jail: 5 (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch + DEFAULT)
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

cat /etc/fail2ban/jail.local | grep -E 'bantime|findtime|maxretry|enabled'

# ============================================================
# 12. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter          # Expected: 1
sysctl net.ipv4.conf.all.accept_redirects   # Expected: 0
sysctl net.ipv4.conf.all.send_redirects     # Expected: 0
sysctl net.ipv4.conf.all.log_martians       # Expected: 1
sysctl net.ipv4.icmp_echo_ignore_all        # Expected: 1
sysctl net.ipv4.tcp_syncookies              # Expected: 1
sysctl net.ipv4.tcp_max_syn_backlog         # Expected: 2048
sysctl net.ipv6.