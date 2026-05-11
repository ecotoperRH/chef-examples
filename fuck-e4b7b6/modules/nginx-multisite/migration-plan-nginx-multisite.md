---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with global security headers, deploys self-signed TLS certificates for each site, sets up UFW firewall rules (deny-by-default, allow SSH/HTTP/HTTPS), configures fail2ban with nginx-aware jails, hardens the kernel via sysctl, and locks down SSH (no root login, no password auth). Each site gets its own document root under `/opt/server/`, a static `index.html`, and a per-site nginx vhost config with HTTP→HTTPS redirect, TLS 1.2/1.3, HSTS, and security headers.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), TLSv1.2/TLSv1.3, HSTS enabled, security headers, gzip on

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), TLSv1.2/TLSv1.3, HSTS enabled, security headers, gzip on

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), TLSv1.2/TLSv1.3, HSTS enabled, security headers, gzip on

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
- Entry point. Includes four sub-recipes in strict order: `security` → `nginx` → `ssl` → `sites`.
- Resources: `include_recipe` (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, logpath=/var/log/nginx/*access.log)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via idempotent execute resources:
  - `ufw --force default deny` (skipped if already default deny)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if already active)
- Deploys kernel hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: `net.ipv4.conf.*.rp_filter=1`, `accept_redirects=0`, `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6 disable_ipv6=1`, `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — `node['security']['ssh']['disable_root'] == true` (default: true):
  - Runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
  - Skipped if `PermitRootLogin no` already present
  - Notifies: `service[ssh]` restart (delayed)
- **Conditional** — `node['security']['ssh']['password_auth'] == false` (default: false):
  - Runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
  - Skipped if `PasswordAuthentication no` already present
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` is declared with `action :nothing` — only restarts when notified by the above conditionals
- Resources: package (1, installs 2 packages), service (2: fail2ban, ssh), template (2), execute (6: 5 ufw + 1 reload_sysctl)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (`client_body_timeout 10`, `client_header_timeout 10`, `send_timeout 10`), global SSL settings (TLSv1.2/TLSv1.3, strong cipher suite, `ssl_prefer_server_ciphers on`, `ssl_session_cache shared:SSL:10m`, `ssl_session_timeout 10m`)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local** (document_root: `/opt/server/test`):
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "Test Environment" HTML page for `test.cluster.local`
  - **ci.cluster.local** (document_root: `/opt/server/ci`):
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "CI/CD Dashboard" HTML page for `ci.cluster.local`
  - **status.cluster.local** (document_root: `/opt/server/status`):
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
    - Content: "System Status" HTML page for `status.cluster.local`
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group `ssl-cert`
- Creates SSL certificate directory `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, none are skipped):
  - **test.cluster.local**:
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
    - Private key: `/etc/ssl/private/test.cluster.local.key`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
    - Private key: `/etc/ssl/private/ci.cluster.local.key`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
    - Private key: `/etc/ssl/private/status.cluster.local.key`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, installs 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with `http2`, TLSv1.2/TLSv1.3, HSTS (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with `http2`, TLSv1.2/TLSv1.3, HSTS (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with `http2`, TLSv1.2/TLSv1.3, HSTS (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx vhost: `/etc/nginx/sites-enabled/default` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

---

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / log-based banning
- `ufw` — Uncomplicated Firewall (iptables frontend)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `nginx` — managed: enabled + started; reloaded on config/cert/vhost changes
- `fail2ban` — managed: enabled + started; restarted on jail.local changes
- `ssh` (sshd) — managed: action :nothing; restarted only when sshd_config is modified by security conditionals

---

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl` with a hardcoded non-sensitive subject string (`/C=US/ST=Example/O=Example Org/...`). No database connection strings, API tokens, or authentication secrets are used anywhere in the cookbook.

---

## Checks for the Migration

**Files to verify**:

| File | Type | Notes |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Global nginx config |
| `/etc/nginx/conf.d/security.conf` | Config | Rate-limiting, buffer, SSL global settings |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Vhost for test site |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Vhost for CI site |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Vhost for status site |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | Test site landing page |
| `/opt/server/ci/index.html` | Static file | CI dashboard landing page |
| `/opt/server/status/index.html` | Static file | Status page landing page |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | 5 jails configured |
| `/etc/sysctl.d/99-security.conf` | Config | Kernel hardening parameters |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |

**Service endpoints to check**:
- Port 80 (HTTP): all three sites — redirects to HTTPS (301)
- Port 443 (HTTPS): all three sites — `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
- Unix sockets: None
- Network interfaces: All interfaces (nginx default bind)

**Templates rendered**:

| Template | Destination | Render Count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× (site loop iteration 1) |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× (site loop iteration 2) |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× (site loop iteration 3) |

Total template renders: 7 (4 unique templates; `site.conf.erb` renders 3 times)

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
# 3. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect 301)
curl -I -k http://test.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://test.cluster.local/

# HTTPS response (expect 200 with HTML)
curl -I -k https://test.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify TLS certificate details
echo | openssl s_client -connect test.cluster.local:443 -servername test.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=test.cluster.local, notAfter=~365 days from issue

# Verify vhost config exists and is symlinked
ls -la /etc/nginx/sites-available/test.cluster.local
ls -la /etc/nginx/sites-enabled/test.cluster.local
# sites-enabled entry must be a symlink pointing to sites-available

# Verify document root and index file
ls -lah /opt/server/test/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/test/index.html
stat -c "%U %G %a" /opt/server/test
# Should show: www-data www-data 755

# Verify per-site log files are created
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# Verify security headers on HTTPS response
curl -sk https://test.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Should show all 5 headers present

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect 301)
curl -I -k http://ci.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://ci.cluster.local/

# HTTPS response (expect 200 with HTML)
curl -I -k https://ci.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify TLS certificate details
echo | openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=ci.cluster.local, notAfter=~365 days from issue

# Verify vhost config exists and is symlinked
ls -la /etc/nginx/sites-available/ci.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
# sites-enabled entry must be a symlink pointing to sites-available

# Verify document root and index file
ls -lah /opt/server/ci/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/ci/index.html
stat -c "%U %G %a" /opt/server/ci
# Should show: www-data www-data 755

# Verify per-site log files are created
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# Verify security headers on HTTPS response
curl -sk https://ci.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Should show all 5 headers present

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect 301)
curl -I -k http://status.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://status.cluster.local/

# HTTPS response (expect 200 with HTML)
curl -I -k https://status.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify TLS certificate details
echo | openssl s_client -connect status.cluster.local:443 -servername status.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=status.cluster.local, notAfter=~365 days from issue

# Verify vhost config exists and is symlinked
ls -la /etc/nginx/sites-available/status.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local
# sites-enabled entry must be a symlink pointing to sites-available

# Verify document root and index file
ls -lah /opt/server/status/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/status/index.html
stat -c "%U %G %a" /opt/server/status
# Should show: www-data www-data 755

# Verify per-site log files are created
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# Verify security headers on HTTPS response
curl -sk https://status.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Should show all 5 headers present

# ============================================================
# 6. SSL CERTIFICATES AND KEYS
# ============================================================
# Verify all 3 certificate files exist
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/certs/status.cluster.local.crt

# Verify all 3 private key files exist with correct permissions (must be 640, root:ssl-cert)
ls -lah /etc/ssl/private/test.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/test.cluster.local.key
# Should show: root ssl-cert 640

ls -lah /etc/ssl/private/ci.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/ci.cluster.local.key
# Should show: root ssl-cert 640

ls -lah /etc/ssl/private/status.cluster.local.key
stat -c "%U %G %a" /etc/ssl/private/status.cluster.local.key
# Should show: root ssl-cert 640

# Verify ssl-cert group exists
getent group ssl-cert
# Should return: ssl-cert:x:<gid>:

# Verify private key directory permissions (must be 710, root:ssl-cert)
stat -c "%U %G %a" /etc/ssl/private
# Should show: root ssl-cert 710

# ============================================================
# 7. DEFAULT VHOST REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>&1
# Should return: No such file or directory

# ============================================================
# 8. NGINX GLOBAL CONFIG VALIDATION
# ============================================================
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip' /etc/nginx/nginx.conf
# Should show: worker_processes auto, worker_connections 768, keepalive_timeout 65, gzip on

grep -E 'server_tokens|limit_req_zone|ssl_protocols|ssl_ciphers' /etc/nginx/conf.d/security.conf
# Should show: server_tokens off, limit_req_zone definitions, TLSv1.2 TLSv1.3, cipher suite

# ============================================================
# 9. FAIL2BAN CONFIGURATION AND STATUS
# ============================================================
cat /etc/fail2ban/jail.local | grep -E 'enabled|bantime|maxretry|logpath'
# Should show all 5 jails with their settings

fail2ban-client status
# Should show: Number of jail: 5 (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch, DEFAULT)

fail