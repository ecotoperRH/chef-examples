---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting **3 SSL-enabled virtual hosts** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with self-signed TLS certificates, deploys per-site document roots with static `index.html` files, hardens the OS with UFW firewall rules, kernel sysctl parameters, and fail2ban intrusion prevention, and locks down SSH by disabling root login and password authentication. All three sites redirect HTTP→HTTPS and share a common nginx security configuration.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / reverse proxy with SSL termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/test.cluster.local.crt`, key: `/etc/ssl/private/test.cluster.local.key`
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/ci.cluster.local.crt`, key: `/etc/ssl/private/ci.cluster.local.key`
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/status.cluster.local.crt`, key: `/etc/ssl/private/status.cluster.local.key`
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`

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
├── resources/
│   └── lineinfile.rb
└── templates/
    └── default/
        ├── fail2ban.jail.local.erb
        ├── nginx.conf.erb
        ├── security.conf.erb
        ├── site.conf.erb
        └── sysctl-security.conf.erb
```

> **Note**: No provider files are used. The `resources/lineinfile.rb` custom resource is defined in the cookbook but is **not called** by any recipe in the execution tree — it can be safely ignored during migration.

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes four sub-recipes in strict order.
- Resources: `include_recipe` (4): `security`, `nginx`, `ssl`, `sites`

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: delayed restart of `fail2ban` service
- Configures UFW firewall via idempotent execute resources:
  - `ufw --force default deny` (skipped if already set)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if already active)
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Executes: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: delayed restart of `ssh` service
- **Conditional** — if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Executes: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: delayed restart of `ssh` service
- `service[ssh]` is declared with `action :nothing` — only restarts when notified by the above conditionals
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 sysctl reload)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `nginx` service
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limit zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, timeouts (body/header/send=10s), SSL protocols TLSv1.2+TLSv1.3, ssl_prefer_server_ciphers=on
  - Notifies: delayed reload of `nginx` service
- Enables and starts the `nginx` service
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local**
  - **test.cluster.local** (`site_folder` = `test`):
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local** (`site_folder` = `ci`):
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local** (`site_folder` = `status`):
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local** (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - Generates self-signed certificate (skipped if both files already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
      - Key: `/etc/ssl/private/test.cluster.local.key`
      - Cert: `/etc/ssl/certs/test.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640 /etc/ssl/private/test.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
      - Notifies: delayed reload of `nginx` service
  - **ci.cluster.local**:
    - Generates self-signed certificate (skipped if both files already exist):
      - Key: `/etc/ssl/private/ci.cluster.local.key`
      - Cert: `/etc/ssl/certs/ci.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640 /etc/ssl/private/ci.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
      - Notifies: delayed reload of `nginx` service
  - **status.cluster.local**:
    - Generates self-signed certificate (skipped if both files already exist):
      - Key: `/etc/ssl/private/status.cluster.local.key`
      - Cert: `/etc/ssl/certs/status.cluster.local.crt`
      - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
      - Post-commands: `chmod 640 /etc/ssl/private/status.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
      - Notifies: delayed reload of `nginx` service
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local**
  - **test.cluster.local**:
    - Deploys virtual host config via template:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables passed: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 redirects to HTTPS; HTTPS server block on port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, try_files, deny .ht/.git/.svn
      - Notifies: delayed reload of `nginx` service
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `nginx` service
  - **ci.cluster.local**:
    - Deploys virtual host config via template:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables passed: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Notifies: delayed reload of `nginx` service
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `nginx` service
  - **status.cluster.local**:
    - Deploys virtual host config via template:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables passed: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Notifies: delayed reload of `nginx` service
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `nginx` service
- Deletes the default nginx site: `/etc/nginx/sites-enabled/default` (action: delete)
  - Notifies: delayed reload of `nginx` service
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` lines in `metadata.rb`)

**System package dependencies**:
- `fail2ban` — intrusion prevention
- `ufw` — firewall management
- `nginx` — web server
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `fail2ban` — enabled and started; restarted on jail config change
- `nginx` — enabled and started; reloaded on any config/cert/site change
- `ssh` (sshd) — restarted only when sshd_config is modified (root login or password auth changes)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime by `openssl` using only public organizational placeholder values (`O=Example Org`, `emailAddress=admin@example.com`) — no private keys or passphrases are stored in the cookbook itself.

## Checks for the Migration

**Files to verify**:

| File | Type | Created by |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | `nginx.rb` (template) |
| `/etc/nginx/conf.d/security.conf` | Config | `nginx.rb` (template) |
| `/etc/nginx/sites-available/test.cluster.local` | Config | `sites.rb` (template) |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | `sites.rb` (template) |
| `/etc/nginx/sites-available/status.cluster.local` | Config | `sites.rb` (template) |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | `sites.rb` (link) |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | `sites.rb` (link) |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | `sites.rb` (link) |
| `/etc/nginx/sites-enabled/default` | Absent (deleted) | `sites.rb` (file delete) |
| `/opt/server/test/index.html` | Static HTML | `nginx.rb` (cookbook_file) |
| `/opt/server/ci/index.html` | Static HTML | `nginx.rb` (cookbook_file) |
| `/opt/server/status/index.html` | Static HTML | `nginx.rb` (cookbook_file) |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS Certificate | `ssl.rb` (execute/openssl) |
| `/etc/ssl/private/test.cluster.local.key` | TLS Private Key | `ssl.rb` (execute/openssl) |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS Certificate | `ssl.rb` (execute/openssl) |
| `/etc/ssl/private/ci.cluster.local.key` | TLS Private Key | `ssl.rb` (execute/openssl) |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS Certificate | `ssl.rb` (execute/openssl) |
| `/etc/ssl/private/status.cluster.local.key` | TLS Private Key | `ssl.rb` (execute/openssl) |
| `/etc/fail2ban/jail.local` | Config | `security.rb` (template) |
| `/etc/sysctl.d/99-security.conf` | Config | `security.rb` (template) |
| `/etc/ssh/sshd_config` | Config (modified) | `security.rb` (execute/sed) |

**Service endpoints to check**:
- Port **80** (HTTP) — nginx, all 3 virtual hosts (redirect to HTTPS)
- Port **443** (HTTPS) — nginx, all 3 virtual hosts (SSL termination)
- Port **22** (SSH) — sshd (allowed through UFW)
- Unix sockets: None
- Network interfaces: nginx binds to all interfaces (`listen 80` / `listen 443 ssl http2` without explicit IP)

**Templates rendered**:

| Template | Destination | Renders |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 time (global) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 time (global) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 time |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 time (global) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 time (global) |

`site.conf.erb` renders **3 times total** (once per site), each time with different `server_name`, `document_root`, `cert_file`, and `key_file` variables.

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
# 3. VIRTUAL HOST CONFIG FILES - verify each site individually
# ============================================================

# Site: test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/test.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -E 'server_name|listen|ssl_certificate|root' /etc/nginx/sites-available/test.cluster.local

# Site: ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/ci.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -E 'server_name|listen|ssl_certificate|root' /etc/nginx/sites-available/ci.cluster.local

# Site: status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/status.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -E 'server_name|listen|ssl_certificate|root' /etc/nginx/sites-available/status.cluster.local

# Default site must be absent
test ! -f /etc/nginx/sites-enabled/default && echo "DEFAULT REMOVED OK" || echo "WARNING: default site still present"

# ============================================================
# 4. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local document root
ls -lah /opt/server/test/
stat /opt/server/test/index.html
cat /opt/server/test/index.html | grep -i "Test Environment"

# ci.cluster.local document root
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html
cat /opt/server/ci/index.html | grep -i "CI/CD"

# status.cluster.local document root
ls -lah /opt/server/status/
stat /opt/server/status/index.html
cat /opt/server/status/index.html | grep -i "System Status"

# Ownership check (all should be www-data:www-data 644)
stat -c "%U:%G %a %n" /opt/server/test/index.html    # expected: www-data:www-data 644
stat -c "%U:%G %a %n" /opt/server/ci/index.html      # expected: www-data:www-data 644
stat -c "%U:%G %a %n" /opt/server/status/index.html  # expected: www-data:www-data 644

# ============================================================
# 5. SSL CERTIFICATES - verify each site individually
# ============================================================

# test.cluster.local certificate
test -f /etc/ssl/certs/test.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/test.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"
stat -c "%a %U:%G %n" /etc/ssl/private/test.cluster.local.key  # expected: 640 root:ssl-cert

# ci.cluster.local certificate
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/ci.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"
stat -c "%a %U:%G %n" /etc/ssl/private/ci.cluster.local.key  # expected: 640 root:ssl-cert

# status.cluster.local certificate
test -f /etc/ssl/certs/status.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/status.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"
stat -c "%a %U:%G %n" /etc/ssl/private/status.cluster.local.key  # expected: 640 root:ssl-cert

# SSL directory permissions
stat -c "%a %U:%G %n" /etc/ssl/certs    # expected: 755 root:root
stat -c "%a %U:%G %n" /etc/ssl/private  # expected: 710 root:ssl-cert

# ssl-cert group exists
getent group ssl-cert

# ============================================================
# 6. HTTP/HTTPS CONNECTIVITY - test each site individually
# ============================================================

# test.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -H "Host: test.cluster.local" http://localhost/ 2>&1 | grep -E "HTTP/|Location:"
# Expected: HTTP/1.1 301 and Location: https://test.cluster.local/

# test.cluster.local - HTTPS should return 200 with HTML content
curl -k -s -o /dev/null -w "%{http_code}" -H "Host: test.cluster.local" https://localhost/
# Expected: 200
curl -k -s -H "Host: test.cluster.local" https://localhost/ | grep -i "Test Environment"

# ci.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -H "Host: ci.cluster.local" http://localhost/ 2>&1 | grep -E "HTTP/|Location:"
# Expected: HTTP/1.1 301 and Location: https://ci.cluster.local/

# ci.cluster.local - HTTPS should return 200 with HTML content
curl -k -s -o /dev/null -w "%{http_code}" -H "Host: ci.cluster.local" https://localhost/
# Expected: 200
curl -k -s -H "Host: ci.cluster.local" https://localhost/ | grep -i "CI/CD"

# status.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -H "Host: status.cluster.local" http://localhost/ 2>&1 | grep -E "HTTP/|Location:"
# Expected: HTTP/1.1 301 and Location: https://status.cluster.local/

# status.cluster.local - HTTPS should return 200 with HTML content
curl -k -s -o /dev/null -w "%{http_code}" -H "Host: status.cluster.local" https://localhost/
# Expected: 200
curl -k -s -H "Host: status.cluster.local" https://localhost/ | grep -i "System Status"

# ============================================================
# 7. SECURITY HEADERS - verify each site
# ============================================================

# test.cluster.local security headers
curl -k -s -I -H "Host: test.cluster.local" https://localhost/ | grep -E "X-Frame-Options|X-Content-Type|Strict-Transport|X-XSS|Referrer-Policy|Content-Security"
# Expected: X-Frame-Options: DENY, X-Content-Type-Options: nosniff, Strict-Transport-Security present

# ci.cluster.local security headers
curl -k -s -I -H "Host: ci.cluster.local" https://localhost/ | grep -E "X-Frame-Options|X-Content-Type|Strict-Transport|X-XSS|Referrer-Policy|Content-Security"

# status.cluster.local security headers
curl -k -s -I -H "Host: status.cluster.local" https://localhost/ | grep -E "X-Frame-Options|X-Content-Type|Strict-Transport|X-XSS|Referrer-Policy|Content-Security"

# ============================================================
# 8. NGINX GLOBAL CONFIGURATION
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections|keepalive_timeout'

# ============================================================
# 9. FIREWALL STATUS
# ============================================================
ufw status verbose
# Expected: Status active, 22/tcp ALLOW, 80/tcp ALLOW, 443/tcp ALLOW, default deny

# ============================================================
# 10. FAIL2BAN STATUS
# ============================================================
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
cat /etc/fail2ban/jail.local

# 