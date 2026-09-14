---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened Nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures Nginx with self-signed TLS certificates, deploys per-site static HTML landing pages, hardens the OS with UFW firewall rules, kernel sysctl parameters, and Fail2Ban intrusion prevention, and locks down SSH by disabling root login and password authentication. All 3 sites redirect HTTP to HTTPS and share a common security header policy.

## Service Type and Instances

**Service Type**: Web Server (Nginx multi-site / reverse proxy with SSL termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA-2048 cert, 365-day validity, CN=test.cluster.local
  - Static file deployed: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA-2048 cert, 365-day validity, CN=ci.cluster.local
  - Static file deployed: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA-2048 cert, 365-day validity, CN=status.cluster.local
  - Static file deployed: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`

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
- Entry point. Includes 4 sub-recipes in strict order: `security`, `nginx`, `ssl`, `sites`.
- Resources: include_recipe (4)

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys Fail2Ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall with 5 execute resources (all idempotent via `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (skipped if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already listed)
  - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already listed)
  - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already listed)
  - `ufw_enable`: `ufw --force enable` (skipped if already "Status: active")
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional SSH hardening (both conditions are true by default):
  - `node['security']['ssh']['disable_root'] = true` → executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - `node['security']['ssh']['password_auth'] == false` → executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Both notify: `service[ssh]` restart (delayed)
- `service[ssh]` defined with `action :nothing` (only triggered by notifications above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh sed)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global Nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, `access_log /var/log/nginx/access.log`, `error_log /var/log/nginx/error.log`
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys Nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), `client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`, timeouts (body/header/send = 10s), SSL global settings (TLSv1.2+TLSv1.3, strong cipher suite, `ssl_prefer_server_ciphers on`)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts `nginx` service
- Iterations: Runs 3 times for sites — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Note on `site_folder` derivation: the cookbook_file source is derived by splitting the site name on `.` and taking the first element: `test.cluster.local` → `test`, `ci.cluster.local` → `ci`, `status.cluster.local` → `status`, mapping directly to `files/default/{test,ci,status}/index.html`.
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations: Runs 3 times for sites — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local** (all have `ssl_enabled: true`, none are skipped):
  - **test.cluster.local**:
    - Generates self-signed certificate (idempotent: skipped if both `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate (idempotent: skipped if both `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate (idempotent: skipped if both `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables passed: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with `ssl http2`, TLSv1.2+TLSv1.3, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip enabled, `try_files $uri $uri/ =404`, deny `.ht*` and `.git/.svn` paths, per-site logs at `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables passed: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Config: identical SSL/security header policy as above; per-site logs at `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables passed: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Config: identical SSL/security header policy as above; per-site logs at `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes the default Nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `fail2ban` — intrusion prevention
- `ufw` — firewall management
- `nginx` — web server
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `fail2ban` — enabled and started; restarted on jail config change
- `nginx` — enabled and started; reloaded on any config/cert/site change
- `ssh` (sshd) — restarted when sshd_config is modified (root login or password auth changes)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — these are development/internal certificates and contain no secret material. Private key files are protected by filesystem permissions (mode 0640, owner root:ssl-cert) rather than encryption.

## Checks for the Migration

**Files to verify**:

*Nginx global configuration:*
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`

*Per-site virtual host configs (sites-available):*
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`

*Per-site symlinks (sites-enabled):*
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`

*Document roots and static files:*
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`

*SSL certificates:*
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`

*SSL private keys:*
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`

*Security configuration:*
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`

*Deleted file (must NOT exist):*
- `/etc/nginx/sites-enabled/default`

**Service endpoints to check**:
- Port 80 (HTTP, all 3 sites — redirect only)
- Port 443 (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0) — Nginx listens on `listen 80` and `listen 443 ssl http2` without explicit IP binding

**Templates rendered**:
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: renders **1 time** (no variables, static content)
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: renders **1 time** (no variables, static content)
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: renders **1 time** (no variables, static content)
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: renders **1 time** (no variables, static content)
- `site.conf.erb` → `/etc/nginx/sites-available/{site_name}`: renders **3 times** — once for `test.cluster.local`, once for `ci.cluster.local`, once for `status.cluster.local`

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

# Global config checks
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip' /etc/nginx/nginx.conf
grep -E 'server_tokens|client_max_body_size|ssl_protocols|limit_req_zone' /etc/nginx/conf.d/security.conf

# Default site must NOT exist
ls -la /etc/nginx/sites-enabled/default && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 3. VIRTUAL HOST CONFIGS AND SYMLINKS
# ============================================================

# Site: test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "OK: config exists" || echo "MISSING: test.cluster.local config"
ls -la /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local  # should be /etc/nginx/sites-available/test.cluster.local
grep -E 'server_name|root|ssl_certificate|ssl_certificate_key' /etc/nginx/sites-available/test.cluster.local

# Site: ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "OK: config exists" || echo "MISSING: ci.cluster.local config"
ls -la /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local  # should be /etc/nginx/sites-available/ci.cluster.local
grep -E 'server_name|root|ssl_certificate|ssl_certificate_key' /etc/nginx/sites-available/ci.cluster.local

# Site: status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "OK: config exists" || echo "MISSING: status.cluster.local config"
ls -la /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local  # should be /etc/nginx/sites-available/status.cluster.local
grep -E 'server_name|root|ssl_certificate|ssl_certificate_key' /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 4. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local document root
ls -lah /opt/server/test/
stat /opt/server/test/index.html  # owner: www-data, group: www-data, mode: 0644
grep -i "Test Environment" /opt/server/test/index.html && echo "OK: correct index.html" || echo "WRONG: unexpected content"

# ci.cluster.local document root
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html  # owner: www-data, group: www-data, mode: 0644
grep -i "CI/CD" /opt/server/ci/index.html && echo "OK: correct index.html" || echo "WRONG: unexpected content"

# status.cluster.local document root
ls -lah /opt/server/status/
stat /opt/server/status/index.html  # owner: www-data, group: www-data, mode: 0644
grep -i "System Status" /opt/server/status/index.html && echo "OK: correct index.html" || echo "WRONG: unexpected content"

# ============================================================
# 5. SSL CERTIFICATES
# ============================================================

# test.cluster.local certificate
test -f /etc/ssl/certs/test.cluster.local.crt && echo "OK: cert exists" || echo "MISSING: test cert"
test -f /etc/ssl/private/test.cluster.local.key && echo "OK: key exists" || echo "MISSING: test key"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Access|Uid|Gid'  # should be 0640, root:ssl-cert

# ci.cluster.local certificate
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "OK: cert exists" || echo "MISSING: ci cert"
test -f /etc/ssl/private/ci.cluster.local.key && echo "OK: key exists" || echo "MISSING: ci key"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Access|Uid|Gid'  # should be 0640, root:ssl-cert

# status.cluster.local certificate
test -f /etc/ssl/certs/status.cluster.local.crt && echo "OK: cert exists" || echo "MISSING: status cert"
test -f /etc/ssl/private/status.cluster.local.key && echo "OK: key exists" || echo "MISSING: status key"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Access|Uid|Gid'  # should be 0640, root:ssl-cert

# ssl-cert group must exist
getent group ssl-cert

# ============================================================
# 6. HTTP/HTTPS CONNECTIVITY TESTS
# ============================================================

# test.cluster.local — HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://test.cluster.local/  # expected: 301
curl -k -o /dev/null -s -w "%{http_code}" https://test.cluster.local/  # expected: 200
curl -k -s https://test.cluster.local/ | grep -i "Test Environment" && echo "OK: correct page served"

# ci.cluster.local — HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://ci.cluster.local/  # expected: 301
curl -k -o /dev/null -s -w "%{http_code}" https://ci.cluster.local/  # expected: 200
curl -k -s https://ci.cluster.local/ | grep -i "CI/CD" && echo "OK: correct page served"

# status.cluster.local — HTTP should redirect to HTTPS (301)
curl -v -o /dev/null -s -w "%{http_code}" http://status.cluster.local/  # expected: 301
curl -k -o /dev/null -s -w "%{http_code}" https://status.cluster.local/  # expected: 200
curl -k -s https://status.cluster.local/ | grep -i "System Status" && echo "OK: correct page served"

# Security headers check (test.cluster.local as representative)
curl -k -I https://test.cluster.local/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 5 headers present

# TLS protocol check — TLSv1.2 and TLSv1.3 only
openssl s_client -connect test.cluster.local:443 -tls1_2 </dev/null 2>&1 | grep -E 'Protocol|Cipher'
openssl s_client -connect test.cluster.local:443 -tls1_3 </dev/null 2>&1 | grep -E 'Protocol|Cipher'
openssl s_client -connect test.cluster.local:443 -tls1_1 </dev/null 2>&1 | grep "handshake failure"  # should FAIL

# ============================================================
# 7. NETWORK PORTS
# ============================================================
netstat -tulpn | grep nginx
ss -tlnp | grep -E ':80|:443'
lsof -i :80
lsof -i :443

# ============================================================
# 8. FIREWALL (UFW)
# ============================================================
ufw status verbose
ufw status verbose | grep -E 'Status: active'  # must be active
ufw status verbose | grep -E '22/tcp|OpenSSH'  # SSH allowed
ufw status verbose | grep -E '80/tcp|Nginx HTTP'  # HTTP allowed
ufw status verbose | grep -E '443/tcp|Nginx HTTPS'  # HTTPS allowed
ufw status verbose | grep "Default: deny"  # default deny must be set

# ============================================================
# 9. FAIL2BAN
# ============================================================
fail2ban-client status
fail2ban-client status sshd  # should show enabled jail
fail2ban-client status nginx-http-auth  # should show enabled jail
fail2ban-client status nginx-limit-req  # should show enabled jail
fail2ban-client status nginx-botsearch  # should show enabled jail
cat /etc/fail2ban/jail.local | grep -E 'bantime|findtime|maxretry|enabled'

# ============================================================
# 10. SYSCTL KERNEL PARAMETERS
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter  # expected: 1
sysctl net.ipv4.conf.all.accept_redirects  # expected: 0
sysctl net.ipv6.conf.all.accept_redirects  # expected: 0
sysctl net.ipv4.conf.all.send_redirects  # expected: 0
sysctl net.ipv4.icmp_echo_ignore_all  # expected: 1
sysctl net.ipv6.conf.all.disable_ipv6  # expected: 1
sysctl net.ipv4.tcp_syncookies  # expected: 1
sysctl net.ipv4.tcp_max_syn_backlog  # expected: 2048

# ============================================================
# 11. SSH HARDENING
# ============================================================
grep '^PermitRootLogin' /etc/ssh/sshd_config  # expected: PermitRootLogin no
grep '^PasswordAuthentication' /etc/ssh/sshd_config  # expected: PasswordAuthentication no
sshd -T | grep -E 'permitrootlogin|passwordauthentication'  # live effective config

# ============================================================
# 12. LOGS
# ============================================================
# Nginx global logs
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log

# Per-site access logs
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log

tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log

tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# Fail2ban log
tail -20 /var/log/fail2ban.log

# Auth log (for SSH ban activity)
tail -20 /var/log/auth.log

# Systemd journal
journalctl -u nginx --no-pager -n 30
journalctl -u fail2ban --no-pager -n 30
journalctl -u ssh --no-pager -n 30
```