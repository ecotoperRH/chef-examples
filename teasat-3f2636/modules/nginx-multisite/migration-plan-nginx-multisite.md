---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened Nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures Nginx with security headers, deploys self-signed TLS certificates for each site, hardens the OS via UFW firewall rules, kernel sysctl parameters, and Fail2Ban intrusion prevention, and optionally locks down SSH (disabling root login and password authentication). Each site gets its own document root under `/opt/server/`, a static `index.html` landing page, and a dedicated Nginx virtual host config with HTTP→HTTPS redirect.

## Service Type and Instances

**Service Type**: Web Server (Nginx multi-site / reverse proxy with OS hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP→HTTPS redirect, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), TLSv1.2+TLSv1.3 only

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP→HTTPS redirect, HSTS, security headers, TLSv1.2+TLSv1.3 only

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP redirect) → 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP→HTTPS redirect, HSTS, security headers, TLSv1.2+TLSv1.3 only

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
- Deploys Fail2Ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Jail config includes: `[DEFAULT]` bantime=3600, findtime=600, maxretry=3; `[sshd]` enabled, logpath=/var/log/auth.log; `[nginx-http-auth]` enabled, port=http,https; `[nginx-limit-req]` enabled, maxretry=10; `[nginx-botsearch]` enabled, maxretry=2
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall with 5 execute resources (all idempotent via `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (guard: `ufw status | grep -q "Default: deny"`)
  - `ufw_allow_ssh`: `ufw allow ssh` (guard: `ufw status | grep -q "22/tcp"`)
  - `ufw_allow_http`: `ufw allow http` (guard: `ufw status | grep -q "80/tcp"`)
  - `ufw_allow_https`: `ufw allow https` (guard: `ufw status | grep -q "443/tcp"`)
  - `ufw_enable`: `ufw --force enable` (guard: `ufw status | grep -q "Status: active"`)
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` (`sysctl -p /etc/sysctl.d/99-security.conf`)
- **Conditional**: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guard: `grep -q '^PermitRootLogin no' /etc/ssh/sshd_config`)
  - Notifies: delayed restart of `service[ssh]`
- **Conditional**: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guard: `grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config`)
  - Notifies: delayed restart of `service[ssh]`
- `service[ssh]` declared with `action :nothing` (only triggered by notifications above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh conditionals)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global Nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Config: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys Nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Config: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), client buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (body/header/send = 10s), SSL session cache/timeout, TLSv1.2+TLSv1.3, cipher suite
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `service[nginx]`
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: source=`files/default/test/index.html`, owner=www-data, group=www-data, mode=0644 — static HTML page titled "Test Environment"
  - **ci.cluster.local**:
    - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: source=`files/default/ci/index.html`, owner=www-data, group=www-data, mode=0644 — static HTML page titled "CI/CD Dashboard"
  - **status.cluster.local**:
    - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: source=`files/default/status/index.html`, owner=www-data, group=www-data, mode=0644 — static HTML page titled "System Status"
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped by the `next unless config['ssl_enabled']` guard):
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: generates self-signed cert via `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`, then `chmod 640` key and `chown root:ssl-cert` key
    - Guard: `not_if { File.exist?('/etc/ssl/certs/test.cluster.local.crt') && File.exist?('/etc/ssl/private/test.cluster.local.key') }`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: same openssl command with CN=ci.cluster.local, key at `/etc/ssl/private/ci.cluster.local.key`, cert at `/etc/ssl/certs/ci.cluster.local.crt`
    - Guard: `not_if { File.exist?('/etc/ssl/certs/ci.cluster.local.crt') && File.exist?('/etc/ssl/private/ci.cluster.local.key') }`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: same openssl command with CN=status.cluster.local, key at `/etc/ssl/private/status.cluster.local.key`, cert at `/etc/ssl/certs/status.cluster.local.crt`
    - Guard: `not_if { File.exist?('/etc/ssl/certs/status.cluster.local.crt') && File.exist?('/etc/ssl/private/status.cluster.local.key') }`
    - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - `template[/etc/nginx/sites-available/test.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`; HTTPS server block on port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs at `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - `template[/etc/nginx/sites-available/ci.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Per-site logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - `template[/etc/nginx/sites-available/status.cluster.local]`: source=`site.conf.erb`, mode=0644
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Per-site logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- Deletes the default Nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: delayed reload of `service[nginx]`
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx.service` — managed (enable + start; reloaded on config/cert/site changes)
- `fail2ban.service` — managed (enable + start; restarted on jail.local changes)
- `ssh.service` (or `sshd.service`) — restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime by `openssl` using only placeholder subject fields (`O=Example Org`, `emailAddress=admin@example.com`) — no pre-existing private keys or passphrases are required.

## Checks for the Migration

**Files to verify**:

*Nginx configuration files:*
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

*Security configuration files:*
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config` (PermitRootLogin no, PasswordAuthentication no)

**Service endpoints to check**:
- Port 80 (HTTP, all 3 sites — redirect only), bound to all interfaces (0.0.0.0)
- Port 443 (HTTPS, all 3 sites), bound to all interfaces (0.0.0.0)
- Unix sockets: None

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — rendered **1 time**
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — rendered **1 time**
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — rendered **1 time**
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` — rendered **1 time**

## Pre-flight checks:
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
curl -I -H "Host: test.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://test.cluster.local/

# HTTPS check (self-signed cert, use -k to skip verification)
curl -k -I -H "Host: test.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify document root and index file
ls -lah /opt/server/test/
cat /opt/server/test/index.html | grep -i "Test Environment"
stat -c "%U %G %a" /opt/server/test/index.html
# Expected: www-data www-data 644

# Verify nginx vhost config
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/test.cluster.local
# Expected: symlink → /etc/nginx/sites-available/test.cluster.local

# Verify SSL certificate
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
# Expected: CN=test.cluster.local, notAfter ~365 days from issue
ls -lah /etc/ssl/private/test.cluster.local.key
stat -c "%a" /etc/ssl/private/test.cluster.local.key
# Expected: 640

# Per-site logs
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log
tail -5 /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 5. SITE: ci.cluster.local
# ============================================================
# HTTP redirect check (should return 301)
curl -I -H "Host: ci.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://ci.cluster.local/

# HTTPS check
curl -k -I -H "Host: ci.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify document root and index file
ls -lah /opt/server/ci/
cat /opt/server/ci/index.html | grep -i "CI/CD"
stat -c "%U %G %a" /opt/server/ci/index.html
# Expected: www-data www-data 644

# Verify nginx vhost config
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/ci.cluster.local
# Expected: symlink → /etc/nginx/sites-available/ci.cluster.local

# Verify SSL certificate
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
# Expected: CN=ci.cluster.local, notAfter ~365 days from issue
ls -lah /etc/ssl/private/ci.cluster.local.key
stat -c "%a" /etc/ssl/private/ci.cluster.local.key
# Expected: 640

# Per-site logs
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log
tail -5 /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 6. SITE: status.cluster.local
# ============================================================
# HTTP redirect check (should return 301)
curl -I -H "Host: status.cluster.local" http://localhost/
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://status.cluster.local/

# HTTPS check
curl -k -I -H "Host: status.cluster.local" https://localhost/
# Expected: HTTP/1.1 200 OK

# Verify document root and index file
ls -lah /opt/server/status/
cat /opt/server/status/index.html | grep -i "System Status"
stat -c "%U %G %a" /opt/server/status/index.html
# Expected: www-data www-data 644

# Verify nginx vhost config
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/status.cluster.local
# Expected: symlink → /etc/nginx/sites-available/status.cluster.local

# Verify SSL certificate
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
# Expected: CN=status.cluster.local, notAfter ~365 days from issue
ls -lah /etc/ssl/private/status.cluster.local.key
stat -c "%a" /etc/ssl/private/status.cluster.local.key
# Expected: 640

# Per-site logs
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log
tail -5 /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 7. DEFAULT SITE REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>&1
# Expected: "No such file or directory"

# ============================================================
# 8. SECURITY HEADERS (verify on each site)
# ============================================================
curl -k -s -I -H "Host: test.cluster.local" https://localhost/ | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 6 headers present

curl -k -s -I -H "Host: ci.cluster.local" https://localhost/ | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 6 headers present

curl -k -s -I -H "Host: status.cluster.local" https://localhost/ | grep -E 'Strict-Transport|X-Frame|X-Content-Type|X-XSS|Referrer-Policy|Content-Security'
# Expected: all 6 headers present

# ============================================================
# 9. SSL CERTIFICATE DIRECTORY PERMISSIONS
# ============================================================
stat -c "%U %G %a" /etc/ssl/certs
# Expected: root root 755
stat -c "%U %G %a" /etc/ssl/private
# Expected: root ssl-cert 710
getent group ssl-cert
# Expected: ssl-cert group exists

# ============================================================
# 10. NGINX GLOBAL CONFIG
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip|server_tokens'
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols'
# Expected: server_tokens off; ssl_protocols TLSv1.2 TLSv1.3;

# ============================================================
# 11. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Expected: Status: active, Default: deny (incoming), Rules: 22/tcp ALLOW, 80/tcp ALLOW, 443/tcp ALLOW

ufw status | grep -E "22|80|443|Status|Default"

# ============================================================
# 12. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: Number of jail: 5 (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch + DEFAULT)

fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|enabled'
# Expected: bantime=3600, maxretry=3 (sshd/http-auth), maxretry=10 (limit-req), maxretry=2 (botsearch)

# ============================================================
# 13. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
# Expected: net.ipv4.conf.all.rp_filter = 1
sysctl net.ipv4.conf.all.accept_redirects
# Expected: net.ipv4.conf.all.accept_redirects = 0
sysctl net.ipv4.tcp_syncookies
# Expected: net.ipv4.tcp_syncookies = 1
sysctl net.ipv6.conf.all.disable_ipv6
# Expected: net.ipv6.conf.all.disable_ipv6 = 1
sysctl net.ipv4.icmp_echo_ignore_all
# Expected: net.ipv4.icmp_echo_ignore_all = 1

# ============================================================
# 14. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin|^PasswordAuthentication' /etc/ssh/sshd_config
# Expected:
#   PermitRootLogin no
#   PasswordAuthentication no

sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# Expected: permitrootlogin no, passwordauthentication no

# ============================================================
# 15. NGINX LOGS (global)
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
journalctl -u nginx --since "1 hour ago" | tail -30

# ============================================================
# 16. FAIL2BAN LOGS
# ============================================================
tail -20 /var/log/fail2ban.log
journalctl -u fail2ban --since "1 hour ago" | tail -20
```