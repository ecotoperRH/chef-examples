---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with global security headers, generates self-signed TLS certificates for each site, deploys per-site static `index.html` content, and hardens the host with UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl security parameters. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / reverse proxy with SSL termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/test.cluster.local.crt`, key: `/etc/ssl/private/test.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static content: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/ci.cluster.local.crt`, key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static content: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/status.cluster.local.crt`, key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static content: `files/default/status/index.html` → `/opt/server/status/index.html`
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
- Entry point. Includes four sub-recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall (idempotent `not_if` guards on each rule):
  - `ufw --force default deny` — sets default deny policy
  - `ufw allow ssh` — opens port 22/tcp
  - `ufw allow http` — opens port 80/tcp
  - `ufw allow https` — opens port 443/tcp
  - `ufw --force enable` — activates the firewall
- Deploys kernel security hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (ICMP redirect ignore), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` (`sysctl -p /etc/sysctl.d/99-security.conf`)
- Conditional: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
  - Guard: `not_if "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"`
  - Notifies: delayed restart of `service[ssh]`
- Conditional: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
  - Guard: `not_if "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"`
  - Notifies: delayed restart of `service[ssh]`
- `service[ssh]` declared with `action :nothing` — only triggered by the above notifiers
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 reload_sysctl), execute (2 conditional: disable_root + disable_password_auth)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), `client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`, timeouts (body/header/send = 10s), SSL: TLSv1.2+TLSv1.3, strong cipher suite, `ssl_prefer_server_ciphers on`
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `service[nginx]`
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local** (document_root: `/opt/server/test`):
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local** (document_root: `/opt/server/ci`):
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local** (document_root: `/opt/server/status`):
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group `ssl-cert`
- Creates SSL certificate directory `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped):
  - **test.cluster.local**:
    - Guard: `not_if { File.exist?('/etc/ssl/certs/test.cluster.local.crt') && File.exist?('/etc/ssl/private/test.cluster.local.key') }`
    - Generates self-signed certificate (RSA 2048-bit, 365 days):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Guard: `not_if { File.exist?('/etc/ssl/certs/ci.cluster.local.crt') && File.exist?('/etc/ssl/private/ci.cluster.local.key') }`
    - Generates self-signed certificate (RSA 2048-bit, 365 days):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Guard: `not_if { File.exist?('/etc/ssl/certs/status.cluster.local.crt') && File.exist?('/etc/ssl/private/status.cluster.local.key') }`
    - Generates self-signed certificate (RSA 2048-bit, 365 days):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Config behaviour (ssl_enabled=true): HTTP server block on port 80 issues `return 301 https://$server_name$request_uri`; HTTPS server block on port 443 with `ssl http2`, TLSv1.2+TLSv1.3, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn` locations
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
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
- `nginx` — managed: enabled + started; reloaded on any config/cert/site change
- `fail2ban` — managed: enabled + started; restarted on jail.local change
- `ssh` (sshd) — managed: action :nothing; restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl` with a hardcoded placeholder subject (`/C=US/ST=Example/O=Example Org/emailAddress=admin@example.com`) — these are development/internal certificates and do not represent stored secrets. The certificate and key files are written to standard system paths (`/etc/ssl/certs/` and `/etc/ssl/private/`) and are not sourced from any secret store.

> **Note for Solutions Architect**: If this cookbook is being migrated for a production environment, the self-signed certificate generation should be replaced with a proper certificate management solution (e.g., Let's Encrypt via `certbot`, or certificates provisioned from an internal PKI/Vault PKI secrets engine). The `admin@example.com` email and `Example Org` subject fields in the `openssl req` command are placeholders and must be updated.

## Checks for the Migration

**Files to verify**:

| File/Directory | Type | Expected |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Rendered from `nginx.conf.erb` |
| `/etc/nginx/conf.d/security.conf` | Config | Rendered from `security.conf.erb` |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → `/etc/nginx/sites-available/test.cluster.local` |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → `/etc/nginx/sites-available/ci.cluster.local` |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → `/etc/nginx/sites-available/status.cluster.local` |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | Deployed from cookbook files |
| `/opt/server/ci/index.html` | Static file | Deployed from cookbook files |
| `/opt/server/status/index.html` | Static file | Deployed from cookbook files |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | Generated by openssl, mode 0640, owner root:ssl-cert |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | Generated by openssl, mode 0640, owner root:ssl-cert |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | Generated by openssl, mode 0640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | Rendered from `fail2ban.jail.local.erb` |
| `/etc/sysctl.d/99-security.conf` | Config | Rendered from `sysctl-security.conf.erb` |
| `/etc/ssh/sshd_config` | Config | `PermitRootLogin no`, `PasswordAuthentication no` |

**Service endpoints to check**:
- Ports listening: `80/tcp` (HTTP, all sites — redirect only), `443/tcp` (HTTPS, all sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× (ssl_enabled=true branch) |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× (ssl_enabled=true branch) |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× (ssl_enabled=true branch) |

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# ============================================================
# 3. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -H "Host: test.cluster.local" http://localhost/
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://test.cluster.local/

# HTTPS response (expect: 200 OK with self-signed cert)
curl -k -I -H "Host: test.cluster.local" https://localhost/
# Should return: HTTP/1.1 200 OK

# Verify static content
curl -k -s -H "Host: test.cluster.local" https://localhost/ | grep -q "Test Environment"
echo "test.cluster.local content check: $?"  # should be 0

# Verify document root and index file
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html | grep -E 'Uid|Gid|Access'
# Expected: owner www-data, group www-data, mode 0644

# Verify nginx site config
ls -lah /etc/nginx/sites-available/test.cluster.local
ls -lah /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-available/test.cluster.local

# Verify SSL certificate
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: mode 0640, owner root, group ssl-cert
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
# Expected: CN=test.cluster.local, notAfter ~365 days from issue

# Verify per-site logs exist
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -H "Host: ci.cluster.local" http://localhost/
# Should return: HTTP/1.1 301 Moved Permanently

# HTTPS response (expect: 200 OK)
curl -k -I -H "Host: ci.cluster.local" https://localhost/
# Should return: HTTP/1.1 200 OK

# Verify static content
curl -k -s -H "Host: ci.cluster.local" https://localhost/ | grep -q "CI/CD Dashboard"
echo "ci.cluster.local content check: $?"  # should be 0

# Verify document root and index file
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html | grep -E 'Uid|Gid|Access'
# Expected: owner www-data, group www-data, mode 0644

# Verify nginx site config
ls -lah /etc/nginx/sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-available/ci.cluster.local

# Verify SSL certificate
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: mode 0640, owner root, group ssl-cert
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
# Expected: CN=ci.cluster.local

# Verify per-site logs exist
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -H "Host: status.cluster.local" http://localhost/
# Should return: HTTP/1.1 301 Moved Permanently

# HTTPS response (expect: 200 OK)
curl -k -I -H "Host: status.cluster.local" https://localhost/
# Should return: HTTP/1.1 200 OK

# Verify static content
curl -k -s -H "Host: status.cluster.local" https://localhost/ | grep -q "System Status"
echo "status.cluster.local content check: $?"  # should be 0

# Verify document root and index file
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html | grep -E 'Uid|Gid|Access'
# Expected: owner www-data, group www-data, mode 0644

# Verify nginx site config
ls -lah /etc/nginx/sites-available/status.cluster.local
ls -lah /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-available/status.cluster.local

# Verify SSL certificate
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'
# Expected: mode 0640, owner root, group ssl-cert
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
# Expected: CN=status.cluster.local

# Verify per-site logs exist
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. DEFAULT SITE REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>/dev/null && echo "FAIL: default site still exists" || echo "OK: default site removed"

# ============================================================
# 7. SECURITY HEADERS VALIDATION
# ============================================================
# Check all three sites return required security headers
curl -k -s -I -H "Host: test.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

curl -k -s -I -H "Host: ci.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

curl -k -s -I -H "Host: status.cluster.local" https://localhost/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# ============================================================
# 8. FIREWALL AND SECURITY HARDENING
# ============================================================
# UFW status
ufw status verbose
# Expected: Status active, default deny incoming, allow 22/tcp, 80/tcp, 443/tcp

# fail2ban jail status
fail2ban-client status
fail2ban-client status sshd