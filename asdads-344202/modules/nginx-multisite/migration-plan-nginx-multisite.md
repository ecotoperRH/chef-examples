---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with global security headers and rate-limiting, generates self-signed TLS certificates for each site, deploys per-site static `index.html` files, and hardens the OS with UFW firewall rules, fail2ban intrusion prevention, kernel-level sysctl security parameters, and SSH hardening (root login disabled, password authentication disabled).

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / virtual hosting)

**Configured Instances**:

- **test.cluster.local**: Test and development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static file: `/opt/server/test/index.html` (Test Environment landing page)
  - Key Config: SSL enabled, HTTP→HTTPS redirect, HSTS, security headers, TLSv1.2+TLSv1.3 only

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static file: `/opt/server/ci/index.html` (CI/CD Dashboard landing page)
  - Key Config: SSL enabled, HTTP→HTTPS redirect, HSTS, security headers, TLSv1.2+TLSv1.3 only

- **status.cluster.local**: System Status page virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static file: `/opt/server/status/index.html` (System Status landing page)
  - Key Config: SSL enabled, HTTP→HTTPS redirect, HSTS, security headers, TLSv1.2+TLSv1.3 only

## File Structure

```
cookbooks/nginx-multisite/
├── attributes/
│   └── default.rb
├── files/
│   └── default/
│       ├── ci/
│       │   └── index.html
│       ├── status/
│       │   └── index.html
│       └── test/
│           └── index.html
├── recipes/
│   ├── default.rb
│   ├── nginx.rb
│   ├── security.rb
│   ├── sites.rb
│   └── ssl.rb
└── templates/
    └── default/
        ├── fail2ban.jail.local.erb
        ├── nginx.conf.erb
        ├── security.conf.erb
        ├── site.conf.erb
        └── sysctl-security.conf.erb
```

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes four sub-recipes in strict order: `security` → `nginx` → `ssl` → `sites`.
- Resources: `include_recipe` (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall via 5 idempotent `execute` resources (each guarded by `not_if`):
  - `ufw_default_deny`: `ufw --force default deny` (skipped if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already present)
  - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already present)
  - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already present)
  - `ufw_enable`: `ufw --force enable` (skipped if already "Status: active")
- Deploys kernel security parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: IP spoofing protection (`rp_filter=1`), ICMP redirect ignore, source routing disable, martian logging, ICMP ping ignore (`icmp_echo_ignore_all=1`), IPv6 disable, TCP SYN flood protection (`tcp_syncookies=1`, `tcp_max_syn_backlog=2048`)
  - Notifies: delayed run of `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — `node['security']['ssh']['disable_root']` is `true`:
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded by `not_if grep -q '^PermitRootLogin no'`)
  - Notifies: delayed restart of `service[ssh]`
- **Conditional** — `node['security']['ssh']['password_auth']` is `false`:
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded by `not_if grep -q '^PasswordAuthentication no'`)
  - Notifies: delayed restart of `service[ssh]`
- Declares `service[ssh]` with `action :nothing` (only triggered by notifiers above)
- Resources: `package` (1, 2 packages), `service` (2: fail2ban + ssh), `template` (2), `execute` (8: 5 ufw + reload_sysctl + disable root login + disable password auth)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `keepalive_timeout 65`, `gzip on`, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys global nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer overflow protections (`client_body_buffer_size 1K`, `client_max_body_size 1k`), timeout settings (body/header/send = 10s), global SSL settings (TLSv1.2+TLSv1.3, strong cipher suite, `ssl_session_cache shared:SSL:10m`)
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644) — "Test Environment" landing page
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644) — "CI/CD Dashboard" landing page
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644) — "System Status" landing page
- Resources: `package` (1), `template` (2), `service` (1), `directory` (3), `cookbook_file` (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: Generates self-signed certificate (RSA 2048-bit, 365 days, subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`)
    - Writes cert to `/etc/ssl/certs/test.cluster.local.crt`
    - Writes key to `/etc/ssl/private/test.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if { File.exist?(cert_file) && File.exist?(key_file) }` — idempotent
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: Same openssl command with `CN=ci.cluster.local`
    - Writes cert to `/etc/ssl/certs/ci.cluster.local.crt`
    - Writes key to `/etc/ssl/private/ci.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if { File.exist?(cert_file) && File.exist?(key_file) }` — idempotent
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: Same openssl command with `CN=status.cluster.local`
    - Writes cert to `/etc/ssl/certs/status.cluster.local.crt`
    - Writes key to `/etc/ssl/private/status.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if { File.exist?(cert_file) && File.exist?(key_file) }` — idempotent
    - Notifies: delayed reload of `service[nginx]`
- Resources: `package` (1, 2 packages), `group` (1), `directory` (2), `execute` (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Renders: HTTP server block (port 80) with `return 301 https://...` redirect + HTTPS server block (port 443 ssl http2) with SSL config, HSTS header, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, location blocks
      - Per-site logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - Symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Renders: HTTP server block (port 80) with `return 301 https://...` redirect + HTTPS server block (port 443 ssl http2) with SSL config, HSTS header, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, location blocks
      - Per-site logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - Symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Renders: HTTP server block (port 80) with `return 301 https://...` redirect + HTTPS server block (port 443 ssl http2) with SSL config, HSTS header, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, location blocks
      - Per-site logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`
      - Notifies: delayed reload of `service[nginx]`
    - Symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: delayed reload of `service[nginx]`
- Resources: `template` (3), `link` (3), `file` (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `nginx` — enabled + started; reloaded on any config/cert/site change
- `fail2ban` — enabled + started; restarted on jail.local change
- `ssh` (sshd) — restarted when sshd_config is modified (root login or password auth changes)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req -x509` with a hardcoded placeholder subject (`O=Example Org`, `emailAddress=admin@example.com`) and are not sourced from any secret store. The certificate and key files are written to standard system paths (`/etc/ssl/certs/` and `/etc/ssl/private/`) and are not pre-provisioned secrets.

> **Note for the Solutions Architect**: In a production migration, the self-signed certificates should be replaced with certificates from a trusted CA (e.g., Let's Encrypt, an internal PKI, or certificates stored in AAP's credential store / HashiCorp Vault). The `admin@example.com` email and `Example Org` subject fields in the openssl command are placeholders and must be updated.

## Checks for the Migration

**Files to verify**:

| File | Type | Notes |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Global nginx config |
| `/etc/nginx/conf.d/security.conf` | Config | Rate-limiting, buffer, SSL global settings |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | Test site content |
| `/opt/server/ci/index.html` | Static file | CI site content |
| `/opt/server/status/index.html` | Static file | Status site content |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | 5 jails configured |
| `/etc/sysctl.d/99-security.conf` | Config | Kernel security parameters |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |
| `/var/log/nginx/test.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/test.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_error.log` | Log | Created on first request |

**Service endpoints to check**:
- Port **80** (HTTP, all 3 sites — redirects to HTTPS)
- Port **443** (HTTPS/TLS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (`0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× (site loop iteration 1) |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× (site loop iteration 2) |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× (site loop iteration 3) |

`site.conf.erb` renders **3 times total** (once per site), each with different `server_name`, `document_root`, `cert_file`, and `key_file` variables.

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
# HTTP must redirect to HTTPS (301)
curl -I http://test.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://test.cluster.local/

# HTTPS must return 200 with self-signed cert (skip cert verify with -k)
curl -k -I https://test.cluster.local
# Expected: HTTP/1.1 200 OK

# Verify page content
curl -k -s https://test.cluster.local | grep -q "Test Environment"
echo "test.cluster.local content check: $?"  # Expected: 0

# Verify SSL certificate details
echo | openssl s_client -connect test.cluster.local:443 -servername test.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=test.cluster.local, notAfter=~365 days from issue

# Verify certificate file exists and has correct permissions
ls -lh /etc/ssl/certs/test.cluster.local.crt
ls -lh /etc/ssl/private/test.cluster.local.key

stat -c "%a %U %G" /etc/ssl/private/test.cluster.local.key
# Expected: 640 root ssl-cert

# Verify document root and index file
ls -lah /opt/server/test/
cat /opt/server/test/index.html | grep -q "Test Environment"
echo "test index.html check: $?"  # Expected: 0

stat -c "%a %U %G" /opt/server/test/index.html
# Expected: 644 www-data www-data

# Verify nginx site config and symlink
ls -lah /etc/nginx/sites-available/test.cluster.local
ls -lah /etc/nginx/sites-enabled/test.cluster.local
# Expected: sites-enabled/test.cluster.local -> /etc/nginx/sites-available/test.cluster.local

grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/test.cluster.local

# Verify HSTS header
curl -k -s -I https://test.cluster.local | grep -i "Strict-Transport-Security"
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains

# Verify security headers
curl -k -s -I https://test.cluster.local | grep -iE "X-Frame-Options|X-Content-Type-Options|X-XSS-Protection"

# ============================================================
# 5. VIRTUAL HOST: ci.cluster.local
# ============================================================
# HTTP must redirect to HTTPS (301)
curl -I http://ci.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://ci.cluster.local/

# HTTPS must return 200
curl -k -I https://ci.cluster.local
# Expected: HTTP/1.1 200 OK

# Verify page content
curl -k -s https://ci.cluster.local | grep -q "CI/CD Dashboard"
echo "ci.cluster.local content check: $?"  # Expected: 0

# Verify SSL certificate details
echo | openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=ci.cluster.local

# Verify certificate file exists and has correct permissions
ls -lh /etc/ssl/certs/ci.cluster.local.crt
ls -lh /etc/ssl/private/ci.cluster.local.key

stat -c "%a %U %G" /etc/ssl/private/ci.cluster.local.key
# Expected: 640 root ssl-cert

# Verify document root and index file
ls -lah /opt/server/ci/
cat /opt/server/ci/index.html | grep -q "CI/CD Dashboard"
echo "ci index.html check: $?"  # Expected: 0

stat -c "%a %U %G" /opt/server/ci/index.html
# Expected: 644 www-data www-data

# Verify nginx site config and symlink
ls -lah /etc/nginx/sites-available/ci.cluster.local
ls -lah /etc/nginx/sites-enabled/ci.cluster.local
# Expected: sites-enabled/ci.cluster.local -> /etc/nginx/sites-available/ci.cluster.local

grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/ci.cluster.local

# Verify HSTS header
curl -k -s -I https://ci.cluster.local | grep -i "Strict-Transport-Security"
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains

# Verify security headers
curl -k -s -I https://ci.cluster.local | grep -iE "X-Frame-Options|X-Content-Type-Options|X-XSS-Protection"

# ============================================================
# 6. VIRTUAL HOST: status.cluster.local
# ============================================================
# HTTP must redirect to HTTPS (301)
curl -I http://status.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://status.cluster.local/

# HTTPS must return 200
curl -k -I https://status.cluster.local
# Expected: HTTP/1.1 200 OK

# Verify page content
curl -k -s https://status.cluster.local | grep -q "System Status"
echo "status.cluster.local content check: $?"  # Expected: 0

# Verify SSL certificate details
echo | openssl s_client -connect status.cluster.local:443 -servername status.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Expected: subject=.../CN=status.cluster.local

# Verify certificate file exists and has correct permissions
ls -lh /etc/ssl/certs/status.cluster.local.crt
ls -lh /etc/ssl/private/status.cluster.local.key

stat -c "%a %U %G" /etc/ssl/private/status.cluster.local.key
# Expected: 640 root ssl-cert

# Verify document root and index file
ls -lah /opt/server/status/
cat /opt/server/status/index.html | grep -q "System Status"
echo "status index.html check: $?"  # Expected: 0

stat -c "%a %U %G" /opt/server/status/index.html
# Expected: 644 www-data www-data

# Verify nginx site config and symlink
ls -lah /etc/nginx/sites-available/status.cluster.local
ls -lah /etc/nginx/sites-enabled/status.cluster.local
# Expected: sites-enabled/status.cluster.local -> /etc/nginx/sites-available/status.cluster.local

grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/status.cluster.local

# Verify HSTS header
curl -k -s -I https://status.cluster.local | grep -i "Strict-Transport-Security"
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains

# Verify security headers
curl -k -s -I https://status.cluster.local | grep -iE "X-Frame-Options|X-Content-Type-Options|X-XSS-Protection"

# ============================================================
# 7. DEFAULT SITE REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>/dev/