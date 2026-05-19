---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting **3 SSL-enabled virtual hosts** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations, and applies a full security hardening layer including UFW firewall rules, fail2ban intrusion prevention (with 5 jails), and kernel-level sysctl hardening. All three sites redirect HTTP→HTTPS and serve static HTML landing pages from `/opt/server/{test,ci,status}`.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static file: `/opt/server/test/index.html` (Test Environment landing page)
  - Key Config: ssl_enabled=true, TLSv1.2+TLSv1.3, HSTS, security headers, gzip

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static file: `/opt/server/ci/index.html` (CI/CD Dashboard landing page)
  - Key Config: ssl_enabled=true, TLSv1.2+TLSv1.3, HSTS, security headers, gzip

- **status.cluster.local**: System Status page virtual host
  - Location/Path: `/opt/server/status` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static file: `/opt/server/status/index.html` (System Status landing page)
  - Key Config: ssl_enabled=true, TLSv1.2+TLSv1.3, HSTS, security headers, gzip

---

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

---

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 sub-recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service immediately
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall (idempotent, each guarded by `not_if`):
  - `ufw --force default deny` (skipped if default deny already set)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if UFW already active)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: IP spoofing protection (rp_filter=1), ICMP redirect ignore (accept_redirects=0), send redirects disabled (send_redirects=0), source routing disabled (accept_source_route=0), martian logging (log_martians=1), ICMP ping ignore (icmp_echo_ignore_all=1), broadcast ping ignore (icmp_echo_ignore_broadcasts=1), IPv6 disabled (disable_ipv6=1), TCP SYN flood protection (tcp_syncookies=1, tcp_max_syn_backlog=2048, tcp_synack_retries=2, tcp_syn_retries=5)
  - Notifies: delayed run of `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Executes: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
  - Guarded by `not_if "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"`
  - Notifies: delayed restart of `service[ssh]`
- **Conditional** — if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Executes: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
  - Guarded by `not_if "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"`
  - Notifies: delayed restart of `service[ssh]`
- Declares `service[ssh]` with `action :nothing` (only triggered by notifications above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 reload_sysctl), execute (2 conditional: disable_root + disable_password_auth)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: delayed reload of `service[nginx]`
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limiting zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, client_body_timeout=10, client_header_timeout=10, send_timeout=10, ssl_session_cache=shared:SSL:10m, ssl_protocols=TLSv1.2 TLSv1.3, ssl_prefer_server_ciphers=on
  - Notifies: delayed reload of `service[nginx]`
- Enables and starts `nginx` service
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local**
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "Test Environment" HTML landing page
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "CI/CD Dashboard" HTML landing page
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "System Status" HTML landing page
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local** (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if` checking both cert and key file existence):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if`):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- **Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local**
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS (max-age=31536000; includeSubDomains), X-Frame-Options: DENY, X-Content-Type-Options: nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS, security headers, gzip, access_log=/var/log/nginx/ci.cluster.local_access.log, error_log=/var/log/nginx/ci.cluster.local_error.log
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS, security headers, gzip, access_log=/var/log/nginx/status.cluster.local_access.log, error_log=/var/log/nginx/status.cluster.local_error.log
      - Notifies: delayed reload of `service[nginx]`
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: delayed reload of `service[nginx]`
- Deletes the default nginx site: `/etc/nginx/sites-enabled/default` (action: delete)
  - Notifies: delayed reload of `service[nginx]`
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
- `nginx` — managed (enabled + started; reloaded on config changes)
- `fail2ban` — managed (enabled + started; restarted on jail.local changes)
- `ssh` / `sshd` — managed (action: nothing; restarted only when sshd_config is modified by conditional blocks)

---

## Credentials

**Detection Summary**: 0 credentials detected across all files.

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed, development-grade certificates with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`). No data bags, Chef Vault items, encrypted attributes, API keys, database passwords, or external secret manager references are present.

> **Note for Solutions Architect**: The `admin@example.com` email address embedded in the SSL certificate subject is a placeholder. If real certificates (e.g., Let's Encrypt or internal CA-signed) are required in the Ansible migration, a secrets/vault integration will need to be added at that stage.

---

## Checks for the Migration

**Files to verify**:

| File | Type | Notes |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Global nginx config |
| `/etc/nginx/conf.d/security.conf` | Config | Rate limiting, buffer, SSL global settings |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Virtual host config |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | Absent | Must NOT exist |
| `/opt/server/test/index.html` | Static file | Test landing page |
| `/opt/server/ci/index.html` | Static file | CI/CD landing page |
| `/opt/server/status/index.html` | Static file | Status landing page |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 0640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | 5 jails configured |
| `/etc/sysctl.d/99-security.conf` | Config | Kernel hardening parameters |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |
| `/var/log/nginx/test.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/test.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_error.log` | Log | Created on first request |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (no variables, static content) |
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (no variables, static content) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (no variables, static content) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× (server_name, document_root, ssl_enabled, cert_file, key_file) |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× (server_name, document_root, ssl_enabled, cert_file, key_file) |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× (server_name, document_root, ssl_enabled, cert_file, key_file) |

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

ps aux | grep nginx | grep -v grep
ps aux | grep fail2ban | grep -v grep

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
# 4. VIRTUAL HOST CONFIGS - verify each site individually
# ============================================================

# Site: test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/test.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/test.cluster.local

# Site: ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/ci.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/ci.cluster.local

# Site: status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/status.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/status.cluster.local

# Default site must be ABSENT
test ! -f /etc/nginx/sites-enabled/default && echo "DEFAULT REMOVED OK" || echo "WARNING: default site still present"

# ============================================================
# 5. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local document root
ls -lah /opt/server/test/
stat /opt/server/test/index.html
cat /opt/server/test/index.html | grep -i "Test Environment"  # should match

# ci.cluster.local document root
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html
cat /opt/server/ci/index.html | grep -i "CI/CD"  # should match

# status.cluster.local document root
ls -lah /opt/server/status/
stat /opt/server/status/index.html
cat /opt/server/status/index.html | grep -i "System Status"  # should match

# Ownership check (all should be www-data:www-data)
stat -c "%U:%G %a %n" /opt/server/test/index.html    # expected: www-data:www-data 644
stat -c "%U:%G %a %n" /opt/server/ci/index.html      # expected: www-data:www-data 644
stat -c "%U:%G %a %n" /opt/server/status/index.html  # expected: www-data:www-data 644

# ============================================================
# 6. SSL CERTIFICATES - verify each site individually
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

# ============================================================
# 7. HTTP CONNECTIVITY - test each site individually
# ============================================================

# test.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://test.cluster.local/   # expected: 301
curl -k -v -o /dev/null -s -w "%{http_code}" https://test.cluster.local/  # expected: 200
curl -k -s https://test.cluster.local/ | grep -i "Test Environment"  # should match

# ci.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://ci.cluster.local/   # expected: 301
curl -k -v -o /dev/null -s -w "%{http_code}" https://ci.cluster.local/  # expected: 200
curl -k -s https://ci.cluster.local/ | grep -i "CI/CD"  # should match

# status.cluster.local - HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://status.cluster.local/   # expected: 301
curl -k -v -o /dev/null -s -w "%{http_code}" https://status.cluster.local/  # expected: 200
curl -k -s https://status.cluster.local/ | grep -i "System Status"  # should match

# ============================================================
# 8.