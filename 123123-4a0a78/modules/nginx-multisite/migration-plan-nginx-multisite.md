---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations, and applies a security baseline including UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl hardening. Each site has its own document root under `/opt/server/` and a static `index.html` landing page.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / reverse proxy with TLS termination)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, security headers applied
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, security headers applied
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status page virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA 2048-bit cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, security headers applied
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`

---

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

---

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 sub-recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs security packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: restart `service[fail2ban]` (delayed)
- Configures UFW firewall with 5 execute resources (all idempotent via `not_if` guards):
  - `ufw_default_deny`: `ufw --force default deny` (skipped if already "Default: deny")
  - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already listed)
  - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already listed)
  - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already listed)
  - `ufw_enable`: `ufw --force enable` (skipped if "Status: active")
- Deploys kernel hardening configuration:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Kernel parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `net.ipv4.conf.all.accept_redirects=0` + `net.ipv6.conf.all.accept_redirects=0` (ICMP redirect ignore), `net.ipv4.conf.all.send_redirects=0` (no send redirects), `net.ipv4.conf.all.accept_source_route=0` + IPv6 equivalent (disable source routing), `net.ipv4.conf.all.log_martians=1` (log martians), `net.ipv4.icmp_echo_ignore_all=1` (ignore ICMP ping), `net.ipv4.icmp_echo_ignore_broadcasts=1`, `net.ipv6.conf.all.disable_ipv6=1` (IPv6 disabled), `net.ipv4.tcp_syncookies=1` + `tcp_max_syn_backlog=2048` + `tcp_synack_retries=2` + `tcp_syn_retries=5` (SYN flood protection)
  - Notifies: run `execute[reload_sysctl]` (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` is true (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: restart `service[ssh]` (delayed)
- Conditional: if `node['security']['ssh']['password_auth']` is false (default: false):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Notifies: restart `service[ssh]` (delayed)
- `service[ssh]` declared with `action :nothing` (only triggered by notifications above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh hardening)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: reload `service[nginx]` (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limit zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, timeouts=10s, SSL session cache shared:SSL:10m, TLSv1.2+TLSv1.3, strong cipher suite
  - Notifies: reload `service[nginx]` (delayed)
- Enables and starts `service[nginx]`
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: source=`files/default/test/index.html`, owner=www-data, group=www-data, mode=0644
  - **ci.cluster.local**:
    - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: source=`files/default/ci/index.html`, owner=www-data, group=www-data, mode=0644
  - **status.cluster.local**:
    - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: source=`files/default/status/index.html`, owner=www-data, group=www-data, mode=0644
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local** (all have `ssl_enabled: true`, so none are skipped by the `next unless config['ssl_enabled']` guard)
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/test.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/ci.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/status.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
      - Notifies: reload `service[nginx]` (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, access_log=/var/log/nginx/ci.cluster.local_access.log, error_log=/var/log/nginx/ci.cluster.local_error.log
      - Notifies: reload `service[nginx]` (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, access_log=/var/log/nginx/status.cluster.local_access.log, error_log=/var/log/nginx/status.cluster.local_error.log
      - Notifies: reload `service[nginx]` (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: reload `service[nginx]` (delayed)
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
- `nginx` — managed: enabled + started; reloaded on any config/cert/site change
- `fail2ban` — managed: enabled + started; restarted on jail.local change
- `ssh` (sshd) — managed: action :nothing (restarted only when sshd_config is modified by hardening steps)

---

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/emailAddress=admin@example.com`) — these are development/internal certificates and do not represent production secrets. The `admin@example.com` email address is a static placeholder embedded directly in the `ssl.rb` recipe's `openssl req` command.

---

## Checks for the Migration

**Files to verify**:

| File | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Global nginx configuration |
| `/etc/nginx/conf.d/security.conf` | Nginx security snippet (rate limits, buffer sizes, SSL globals) |
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
| `/etc/ssl/certs/test.cluster.local.crt` | Self-signed TLS certificate for test site |
| `/etc/ssl/private/test.cluster.local.key` | TLS private key for test site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/ci.cluster.local.crt` | Self-signed TLS certificate for CI site |
| `/etc/ssl/private/ci.cluster.local.key` | TLS private key for CI site (mode 640, owner root:ssl-cert) |
| `/etc/ssl/certs/status.cluster.local.crt` | Self-signed TLS certificate for status site |
| `/etc/ssl/private/status.cluster.local.key` | TLS private key for status site (mode 640, owner root:ssl-cert) |
| `/etc/fail2ban/jail.local` | Fail2ban jail configuration |
| `/etc/sysctl.d/99-security.conf` | Kernel security parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |

**Service endpoints to check**:
- Port 22 (SSH — allowed through UFW)
- Port 80 (HTTP — allowed through UFW; all sites redirect to HTTPS)
- Port 443 (HTTPS — allowed through UFW; all 3 virtual hosts)
- Unix sockets: None
- Network interfaces: nginx binds to all interfaces (no explicit `listen` IP in config)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 (static, no variables) |
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 (static, no variables) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 (static, no variables) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 (static, no variables) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 of 3 |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 2 of 3 |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 3 of 3 |

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
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols'

# Default site must NOT exist
ls -la /etc/nginx/sites-enabled/default && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 3. VIRTUAL HOST CONFIGS - test.cluster.local
# ============================================================
test -f /etc/nginx/sites-available/test.cluster.local && echo "OK: config exists" || echo "ERROR: config missing"
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
ls -la /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local  # should be /etc/nginx/sites-available/test.cluster.local

# ============================================================
# 4. VIRTUAL HOST CONFIGS - ci.cluster.local
# ============================================================
test -f /etc/nginx/sites-available/ci.cluster.local && echo "OK: config exists" || echo "ERROR: config missing"
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
ls -la /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local  # should be /etc/nginx/sites-available/ci.cluster.local

# ============================================================
# 5. VIRTUAL HOST CONFIGS - status.cluster.local
# ============================================================
test -f /etc/nginx/sites-available/status.cluster.local && echo "OK: config exists" || echo "ERROR: config missing"
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
ls -la /etc/nginx/sites-enabled/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local  # should be /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 6. DOCUMENT ROOTS AND STATIC FILES
# ============================================================
# test.cluster.local
ls -lah /opt/server/test/
stat /opt/server/test/index.html
stat -c "%U:%G %a" /opt/server/test/index.html  # should show: www-data:www-data 644

# ci.cluster.local
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html
stat -c "%U:%G %a" /opt/server/ci/index.html  # should show: www-data:www-data 644

# status.cluster.local
ls -lah /opt/server/status/
stat /opt/server/status/index.html
stat -c "%U:%G %a" /opt/server/status/index.html  # should show: www-data:www-data 644

# ============================================================
# 7. SSL CERTIFICATES
# ============================================================
# test.cluster.local certificate
test -f /etc/ssl/certs/test.cluster.local.crt && echo "OK: cert exists" || echo "ERROR: cert missing"
test -f /etc/ssl/private/test.cluster.local.key && echo "OK: key exists" || echo "ERROR: key missing"
stat -c "%a %U:%G" /etc/ssl/private/test.cluster.local.key  # should show: 640 root:ssl-cert
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates | grep -E 'CN=test.cluster.local|notAfter'
openssl verify -CAfile /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/test.cluster.local.crt

# ci.cluster.local certificate
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "OK: cert exists" || echo "ERROR: cert missing"
test -f /etc/ssl/private/ci.cluster.local.key && echo "OK: key exists" || echo "ERROR: key missing"
stat -c "%a %U:%G" /etc/ssl/private/ci.cluster.local.key  # should show: 640 root:ssl-cert
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates | grep -E 'CN=ci.cluster.local|notAfter'

# status.cluster.local certificate
test -f /etc/ssl/certs/status.cluster.local.crt && echo "OK: cert exists" || echo "ERROR: cert missing"
test -f /etc/ssl/private/status.cluster.local.key && echo "OK: key exists" || echo "ERROR: key missing"
stat -c "%a %U:%G" /etc/ssl/private/status.cluster.local.key  # should show: 640 root:ssl-cert
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates | grep -E 'CN=status.cluster.local|notAfter'

# SSL directory permissions
stat -c "%a %U:%G" /etc/ssl/certs    # should show: 755 root:root
stat -c "%a %U:%G" /etc/ssl/private  # should show: 710 root:ssl-cert
getent group ssl-cert                # ssl-cert group must exist

# ============================================================
# 8. HTTP CONNECTIVITY - test.cluster.local
# ============================================================
# HTTP should redirect to HTTPS (301)
curl -I -H "Host: test.cluster.local" http://localhost/ 2>/dev/null | grep -E 'HTTP/|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://test.cluster.local/

# HTTPS should return 200 (skip cert verification for self-signed)
curl -k -I -H "Host: test.cluster.local" https://localhost/ 2>/dev/null | grep -E 'HTTP/|Strict-Transport|X-Frame'
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# ============================================================
# 9. HTTP CONNECTIVITY - ci.cluster.local
# ============================================================
curl -I -H "Host: ci.cluster.local" http://localhost/ 2>/dev/null | grep -E 'HTTP/|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://ci.cluster.local/

curl -k -I -H "Host: ci.cluster.local" https://localhost/ 2>/dev/null | grep -E 'HTTP/|Strict-Transport|X-Frame'
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# ============================================================
# 10. HTTP CONNECTIVITY - status.cluster.local
# ============================================================
curl -I -H "Host: status.cluster.local" http://localhost/ 2>/dev/null | grep -E 'HTTP/|Location'
# Expected: HTTP/1.1 301 Moved Permanently + Location: https://status.cluster.local/

curl -k -I -H "Host: status.cluster.local" https://localhost/ 2>/dev/null | grep -E 'HTTP/|Strict-Transport|X-Frame'
# Expected: HTTP/1.1 200 OK, Strict-Transport-Security header present, X-Frame-Options: DENY

# ============================================================
# 11. NETWORK PORTS
# ============================================================
ss -tlnp | grep -E ':80|:443'
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443
# Both ports 80 and 443 must show nginx listening

# ============================================================
# 12. UFW FIREWALL
# ============================================================
ufw status verbose
# Expected output must include:
#   Status: active
#   Default: deny (incoming)
#   22/tcp (SSH) ALLOW IN
#   80/tcp (HTTP) ALLOW IN
#   443/tcp (HTTPS) ALLOW IN

ufw status | grep -q "Status: active" && echo "OK: UFW active" || echo "ERROR: UFW not active"
ufw status | grep -q "22/tcp" && echo "OK: SSH allowed" || echo "ERROR: SSH not allowed"
ufw status | grep -q "80/tcp" && echo "OK: HTTP allowed" || echo "ERROR: HTTP not allowed"
ufw status | grep -q "443/tcp" && echo "OK: HTTPS allowed" || echo "ERROR: HTTPS not allowed"

# ============================================================
# 13. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: 5 jails listed: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch

fail2ban-client status sshd | grep -E 'Currently banned|Total banned'
fail2ban-client status nginx-http-auth | grep -E 'Currently banned|Total banned'
fail2ban-client status nginx-limit-req | grep -E 'Currently banned|Total banned'
fail2ban-client status nginx-botsearch | grep -E 'Currently banned|Total banned'

cat /etc/fail2ban/jail.local | grep -E 'bantime|findtime|maxretry|enabled'
# Expected: bantime=3600, findtime=600, maxretry=3 (DEFAULT), nginx-botsearch maxretry=2, nginx-limit-req maxretry=10

# ============================================================
# 14. SYSCTL KERNEL HARDENING
# ============================================================
test -f /etc/sysctl.d/99-security.conf && echo "OK: sysctl config exists" || echo "ERROR: sysctl config missing"

sysctl net.ipv4.conf.all.rp_filter           # should be 1
sysctl net.ipv4.conf.all.accept_redirects    # should be 0
sysctl net.ipv4.conf.all.send_redirects      # should be 0
sysctl net.ipv4.conf.all.accept_source_route # should be 0
sysctl net.ipv4.conf.all.log_martians        # should be 1
sysctl net.ipv4.icmp_echo_ignore_all         # should be 1
sysctl net.ipv4.icmp_echo_ignore_broadcasts  # should be 1
sysctl net.ipv6.conf.all.disable_ipv6        # should be 1
sysctl net.ipv4.tcp_syncookies               # should be 1
sysctl net.ipv4.tcp_max_syn_backlog          # should be 2048

# ============================================================
# 15. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config
# Expected: PermitRootLogin no

grep -E '^PasswordAuthentication' /etc/ssh/sshd_config
# Expected: PasswordAuthentication no

sshd -t && echo "OK: sshd_config syntax valid" || echo "ERROR: sshd_config syntax error"

# ============================================================
# 16. NGINX ACCESS AND ERROR LOGS
# ============================================================
# Global logs
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log

# Per-site logs - test.cluster.local
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log

# Per-site logs - ci.cluster.local
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log

# Per-site logs - status.cluster.local
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# Fail2ban log
tail -20 /var/log/fail2ban.log

# Auth log (monitored by fail2ban sshd jail)
tail -20 /var/log/auth.log
```