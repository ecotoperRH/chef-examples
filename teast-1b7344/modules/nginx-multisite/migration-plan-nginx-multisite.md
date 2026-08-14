---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations, and applies a full security hardening stack including UFW firewall rules, fail2ban intrusion prevention (with 5 jails), and kernel-level sysctl hardening. SSH is also hardened by disabling root login and password authentication.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: Self-signed RSA 2048-bit cert, TLSv1.2/1.3 only, HSTS enabled, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip enabled
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: Self-signed RSA 2048-bit cert, TLSv1.2/1.3 only, HSTS enabled, security headers, gzip enabled
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: Self-signed RSA 2048-bit cert, TLSv1.2/1.3 only, HSTS enabled, security headers, gzip enabled
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
- Entry point. Includes 4 recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (port=http,https, maxretry=10), `[nginx-botsearch]` (port=http,https, logpath=/var/log/nginx/*access.log, maxretry=2)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via 5 idempotent execute resources:
  - `ufw --force default deny` (skipped if already set)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if already active)
- Deploys kernel sysctl hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- Conditional: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- Declares `service[ssh]` with `action :nothing` (only triggered by notifies above)
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 sysctl reload), execute (2: ssh hardening, conditional)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, `access_log /var/log/nginx/access.log`, `error_log /var/log/nginx/error.log`, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (`client_body_timeout 10`, `client_header_timeout 10`, `send_timeout 10`), SSL global settings (`TLSv1.2 TLSv1.3`, cipher suite, `ssl_prefer_server_ciphers on`, `ssl_session_cache shared:SSL:10m`, `ssl_session_timeout 10m`)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations: Runs 3 times for sites (all have `ssl_enabled: true`): **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local** (ssl_enabled: true — condition passes):
    - Generates self-signed certificate (idempotent: skipped if both files already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local** (ssl_enabled: true — condition passes):
    - Generates self-signed certificate (idempotent: skipped if both files already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local** (ssl_enabled: true — condition passes):
    - Generates self-signed certificate (idempotent: skipped if both files already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2/1.3, HSTS `max-age=31536000; includeSubDomains`, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip, `try_files $uri $uri/ =404`, deny `.ht*` and `.git/.svn` locations, `access_log /var/log/nginx/test.cluster.local_access.log`, `error_log /var/log/nginx/test.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2/1.3, HSTS `max-age=31536000; includeSubDomains`, security headers, gzip, `try_files $uri $uri/ =404`, deny `.ht*` and `.git/.svn` locations, `access_log /var/log/nginx/ci.cluster.local_access.log`, `error_log /var/log/nginx/ci.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Config: HTTP port 80 → 301 redirect to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2/1.3, HSTS `max-age=31536000; includeSubDomains`, security headers, gzip, `try_files $uri $uri/ =404`, deny `.ht*` and `.git/.svn` locations, `access_log /var/log/nginx/status.cluster.local_access.log`, `error_log /var/log/nginx/status.cluster.local_error.log`
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx site: `/etc/nginx/sites-enabled/default` (action: delete)
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

**Service dependencies**:
- `nginx` — managed (enabled + started; reloaded on config changes)
- `fail2ban` — managed (enabled + started; restarted on jail.local changes)
- `ssh` / `sshd` — managed (action: nothing; restarted only when sshd_config is modified)

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — these are development/internal certificates and contain no secrets. The private keys are generated locally on the target host and are not stored in the cookbook.

> **Note for the Solutions Architect**: Because self-signed certificates are generated on the fly, there is no certificate rotation mechanism. For production use, consider integrating a proper PKI (e.g., Let's Encrypt via certbot, or an internal CA) and storing the resulting private keys in a secrets manager (HashiCorp Vault, CyberArk, or AWS Secrets Manager). The Ansible equivalent should parameterize the OpenSSL subject fields (`C`, `ST`, `L`, `O`, `OU`, `emailAddress`) as Ansible variables sourced from AAP credentials or a vault lookup.

## Checks for the Migration

**Files to verify**:

| File | Purpose |
|---|---|
| `/etc/nginx/nginx.conf` | Global nginx configuration |
| `/etc/nginx/conf.d/security.conf` | Nginx security snippet (rate limits, buffers, SSL globals) |
| `/etc/nginx/sites-available/test.cluster.local` | Virtual host config for test site |
| `/etc/nginx/sites-available/ci.cluster.local` | Virtual host config for CI site |
| `/etc/nginx/sites-available/status.cluster.local` | Virtual host config for status site |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static landing page for test site |
| `/opt/server/ci/index.html` | Static landing page for CI site |
| `/opt/server/status/index.html` | Static landing page for status site |
| `/etc/ssl/certs/test.cluster.local.crt` | Self-signed cert for test site |
| `/etc/ssl/private/test.cluster.local.key` | Private key for test site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/ci.cluster.local.crt` | Self-signed cert for CI site |
| `/etc/ssl/private/ci.cluster.local.key` | Private key for CI site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/status.cluster.local.crt` | Self-signed cert for status site |
| `/etc/ssl/private/status.cluster.local.key` | Private key for status site (mode 640, owner root:ssl-cert) |
| `/etc/fail2ban/jail.local` | Fail2ban jail configuration |
| `/etc/sysctl.d/99-security.conf` | Kernel security parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |

**Service endpoints to check**:
- Port **80** (HTTP) — nginx, all 3 sites (redirect to HTTPS)
- Port **443** (HTTPS) — nginx, all 3 sites (TLS)
- Port **22** (SSH) — sshd (UFW allows)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Times Rendered |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 |

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
ss -tlnp | grep -E ':80|:443|:22'
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 4. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://test.cluster.local
# HTTPS response (expect: 200 OK, self-signed cert warning is expected)
curl -I -k https://test.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect test.cluster.local:443 -servername test.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and index file
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html  # owner should be www-data:www-data, mode 0644
# Verify nginx config
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/test.cluster.local
# Verify symlink
ls -la /etc/nginx/sites-enabled/test.cluster.local  # should point to sites-available/test.cluster.local
# Verify per-site logs exist
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/test.cluster.local_error.log
# Verify security headers
curl -sk https://test.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 5. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://ci.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://ci.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and index file
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html  # owner should be www-data:www-data, mode 0644
# Verify nginx config
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/ci.cluster.local
# Verify symlink
ls -la /etc/nginx/sites-enabled/ci.cluster.local  # should point to sites-available/ci.cluster.local
# Verify per-site logs
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
# Verify security headers
curl -sk https://ci.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 6. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://status.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://status.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect status.cluster.local:443 -servername status.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and index file
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html  # owner should be www-data:www-data, mode 0644
# Verify nginx config
grep -E 'server_name|root|ssl_certificate|listen' /etc/nginx/sites-available/status.cluster.local
# Verify symlink
ls -la /etc/nginx/sites-enabled/status.cluster.local  # should point to sites-available/status.cluster.local
# Verify per-site logs
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_error.log
# Verify security headers
curl -sk https://status.cluster.local -I | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'

# ============================================================
# 7. SSL CERTIFICATES AND KEYS
# ============================================================
# test.cluster.local
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key  # expect: -rw-r----- root ssl-cert (640)
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Access|Uid|Gid'
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -text | grep -E 'CN|Not Before|Not After|RSA'

# ci.cluster.local
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key  # expect: -rw-r----- root ssl-cert (640)
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Access|Uid|Gid'
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -text | grep -E 'CN|Not Before|Not After|RSA'

# status.cluster.local
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key  # expect: -rw-r----- root ssl-cert (640)
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Access|Uid|Gid'
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -text | grep -E 'CN|Not Before|Not After|RSA'

# Verify ssl-cert group exists
getent group ssl-cert

# Verify private key directory permissions (expect: drwx--x--- root ssl-cert 710)
stat /etc/ssl/private | grep -E 'Access|Uid|Gid'

# ============================================================
# 8. DEFAULT SITE REMOVED
# ============================================================
# Must NOT exist (expect: No such file or directory)
ls /etc/nginx/sites-enabled/default && echo "ERROR: default site still enabled!" || echo "OK: default site removed"

# ============================================================
# 9. NGINX GLOBAL CONFIG
# ============================================================
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip|access_log|error_log' /etc/nginx/