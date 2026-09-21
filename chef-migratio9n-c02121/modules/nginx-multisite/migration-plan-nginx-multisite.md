---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 virtual sites (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with SSL enabled (self-signed certificates), dedicated document roots, and static HTML landing pages. It also applies a full security baseline: UFW firewall rules, fail2ban intrusion prevention with 5 jails, kernel-level sysctl hardening, and SSH hardening (root login disabled, password authentication disabled).

---

## Service Type and Instances

**Service Type**: Web Server (nginx multisite with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` deployed from `files/default/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` deployed from `files/default/ci/index.html`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` deployed from `files/default/status/index.html`

---

## File Structure

```
cookbooks/nginx-multisite/
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── templates/
│   └── default/
│       ├── fail2ban.jail.local.erb
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       └── sysctl-security.conf.erb
├── attributes/
│   └── default.rb
└── files/
    └── default/
        ├── test/
        │   └── index.html
        ├── ci/
        │   └── index.html
        └── status/
            └── index.html
```

---

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point that includes all four sub-recipes in order
- Resources: include_recipe (4): security, nginx, ssl, sites

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs security packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (port=http,https, maxretry=10), `[nginx-botsearch]` (port=http,https, logpath=/var/log/nginx/*access.log, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via 5 execute resources (each idempotent with `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (skips if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skips if 22/tcp already listed)
  - `ufw_allow_http`: `ufw allow http` (skips if 80/tcp already listed)
  - `ufw_allow_https`: `ufw allow https` (skips if 443/tcp already listed)
  - `ufw_enable`: `ufw --force enable` (skips if already "Status: active")
- Deploys kernel sysctl security hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Settings: IP spoofing protection (rp_filter=1), ICMP redirect ignore, source routing disabled, martian logging, ICMP ping ignore, IPv6 disabled, TCP SYN flood protection (syncookies=1, max_syn_backlog=2048)
  - Notifies: `execute[reload_sysctl]` run (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — `node['security']['ssh']['disable_root']` is `true`:
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skips if already set)
  - Notifies: `service[ssh]` restart (delayed)
- **Conditional** — `node['security']['ssh']['password_auth']` is `false`:
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skips if already set)
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` declared with `action :nothing` (only triggered by above notifies)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh conditional)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile/tcp_nopush/tcp_nodelay on, keepalive_timeout=65, gzip on, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens off, rate limiting zones (login: 10r/m, api: 30r/m), buffer overflow protections (client_body_buffer_size=1K, client_max_body_size=1K), timeout settings (body/header/send=10s), global SSL settings (TLSv1.2+TLSv1.3, strong cipher suite)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts `nginx` service (supports restart, reload, status)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: source=`test/index.html` (static HTML for test environment), owner=www-data, group=www-data, mode=0644
  - **ci.cluster.local**:
    - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: source=`ci/index.html` (static HTML for CI/CD dashboard), owner=www-data, group=www-data, mode=0644
  - **status.cluster.local**:
    - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: source=`status/index.html` (static HTML for system status page), owner=www-data, group=www-data, mode=0644
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped):
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: Generates self-signed cert with `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
      - Key: `/etc/ssl/private/test.cluster.local.key` (chmod 640, chown root:ssl-cert)
      - Cert: `/etc/ssl/certs/test.cluster.local.crt`
      - Idempotent: skips if both cert and key files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: Generates self-signed cert with `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
      - Key: `/etc/ssl/private/ci.cluster.local.key` (chmod 640, chown root:ssl-cert)
      - Cert: `/etc/ssl/certs/ci.cluster.local.crt`
      - Idempotent: skips if both cert and key files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: Generates self-signed cert with `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
      - Key: `/etc/ssl/private/status.cluster.local.key` (chmod 640, chown root:ssl-cert)
      - Cert: `/etc/ssl/certs/status.cluster.local.crt`
      - Idempotent: skips if both cert and key files already exist
      - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Config: HTTP port 80 redirects to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS (max-age=31536000; includeSubDomains), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip, deny .ht/.git/.svn locations
      - Access log: `/var/log/nginx/test.cluster.local_access.log`
      - Error log: `/var/log/nginx/test.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Access log: `/var/log/nginx/ci.cluster.local_access.log`
      - Error log: `/var/log/nginx/ci.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Access log: `/var/log/nginx/status.cluster.local_access.log`
      - Error log: `/var/log/nginx/status.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Removes default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata.rb)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — SSL certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed (enable + start; reloaded on config/cert/site changes)
- `fail2ban` — managed (enable + start; restarted on jail.local changes)
- `ssh` / `sshd` — managed (action :nothing; restarted only when sshd_config is modified)

---

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with a placeholder subject (`O=Example Org`, `emailAddress=admin@example.com`) and are intended for development/internal use only. No data bags, Chef Vault, CyberArk, environment variables carrying secrets, or hardcoded passwords were found.

> **Note for Solutions Architect**: If this cookbook is being migrated to a production environment, the self-signed SSL certificates should be replaced with certificates from a trusted CA (e.g., Let's Encrypt, internal PKI). The certificate generation subject fields (`/C=US/ST=Example/L=Example/O=Example Org`) are hardcoded placeholders and should be parameterized in the Ansible equivalent.

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

*Log files (created at runtime):*
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
- Unix sockets: none
- Network interfaces: all interfaces (0.0.0.0)

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: renders 1 time (static, no variables)
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: renders 1 time (static, no variables)
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: renders 1 time (static, no variables)
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: renders 1 time (static, no variables)
- `site.conf.erb` → `/etc/nginx/sites-available/<site_name>`: renders **3 times** (once per site: test.cluster.local, ci.cluster.local, status.cluster.local)

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
# 2. NGINX CONFIGURATION VALIDATION
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# Global config
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip'

# Security snippet
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|ssl_protocols|ssl_ciphers'

# Default site must NOT exist
ls -la /etc/nginx/sites-enabled/default && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 3. SITE: test.cluster.local
# ============================================================
# Config file
ls -lah /etc/nginx/sites-available/test.cluster.local
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'

# Symlink
ls -la /etc/nginx/sites-enabled/test.cluster.local  # should point to /etc/nginx/sites-available/test.cluster.local

# Document root and static file
ls -lah /opt/server/test/
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data, 0644

# SSL certificate
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert, 0640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"

# HTTP → HTTPS redirect (port 80)
curl -I -k http://test.cluster.local 2>/dev/null | grep -E 'HTTP|Location'  # expect 301 redirect to https://

# HTTPS response (port 443)
curl -I -k https://test.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options'
curl -sk https://test.cluster.local | grep "Test Environment"  # verify index.html content

# Logs
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# Config file
ls -lah /etc/nginx/sites-available/ci.cluster.local
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'

# Symlink
ls -la /etc/nginx/sites-enabled/ci.cluster.local  # should point to /etc/nginx/sites-available/ci.cluster.local

# Document root and static file
ls -lah /opt/server/ci/
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data, 0644

# SSL certificate
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert, 0640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"

# HTTP → HTTPS redirect (port 80)
curl -I -k http://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Location'  # expect 301 redirect to https://

# HTTPS response (port 443)
curl -I -k https://ci.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options'
curl -sk https://ci.cluster.local | grep "CI/CD Dashboard"  # verify index.html content

# Logs
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# Config file
ls -lah /etc/nginx/sites-available/status.cluster.local
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'

# Symlink
ls -la /etc/nginx/sites-enabled/status.cluster.local  # should point to /etc/nginx/sites-available/status.cluster.local

# Document root and static file
ls -lah /opt/server/status/
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data, 0644

# SSL certificate
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert, 0640
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"

# HTTP → HTTPS redirect (port 80)
curl -I -k http://status.cluster.local 2>/dev/null | grep -E 'HTTP|Location'  # expect 301 redirect to https://

# HTTPS response (port 443)
curl -I -k https://status.cluster.local 2>/dev/null | grep -E 'HTTP|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options'
curl -sk https://status.cluster.local | grep "System Status"  # verify index.html content

# Logs
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. NETWORK LISTENING
# ============================================================
ss -tlnp | grep nginx
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 7. FAIL2BAN CONFIGURATION AND STATUS
# ============================================================
cat /etc/fail2ban/jail.local | grep -E 'bantime|findtime|maxretry|enabled'

# Verify all 5 jails are active
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# ============================================================
# 8. UFW FIREWALL STATUS
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
# 9. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf | grep -E 'rp_filter|accept_redirects|syncookies|disable_ipv6'

# Verify applied values
sysctl net.ipv4.conf.all.rp_filter          # should be 1
sysctl net.ipv4.conf.all.accept_redirects   # should be 0
sysctl net.ipv4.tcp_syncookies              # should be 1
sysctl net.ipv4.icmp_echo_ignore_all        # should be 1
sysctl net.ipv6.conf.all.disable_ipv6       # should be 1

# ============================================================
# 10. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config        # should be: PermitRootLogin no
grep -E '^PasswordAuthentication' /etc/ssh/sshd_config  # should be: PasswordAuthentication no

# Verify sshd config is valid
sshd -t && echo "sshd config OK" || echo "ERROR: sshd config invalid"

# ============================================================
# 11. SSL DIRECTORY PERMISSIONS
# ============================================================
stat /etc/ssl/certs | grep -E 'Uid|Gid|Access'    # should be root:root, 0755
stat /etc/ssl/private | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert, 0710
getent group ssl-cert                               # ssl-cert group must exist

# ============================================================
# 12. GLOBAL NGINX LOGS
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
journalctl -u nginx --since "1 hour ago" | tail -30
```