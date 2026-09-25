---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with per-site self-signed TLS certificates, deploys static HTML landing pages for each site, hardens the OS with UFW firewall rules, kernel sysctl parameters, and fail2ban intrusion prevention, and locks down SSH by disabling root login and password authentication.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / virtual hosting)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static content: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Key Config: SSL enabled, HTTP→HTTPS redirect, TLSv1.2/1.3 only, HSTS, security headers

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static content: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: SSL enabled, HTTP→HTTPS redirect, TLSv1.2/1.3 only, HSTS, security headers

- **status.cluster.local**: System status page virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static content: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: SSL enabled, HTTP→HTTPS redirect, TLSv1.2/1.3 only, HSTS, security headers

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
- Entry point. Includes 4 sub-recipes in strict order: `security`, `nginx`, `ssl`, `sites`.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs security packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
  - Notifies: restart `fail2ban` service (delayed)
- Configures UFW firewall with 5 execute resources (each guarded by `not_if` idempotency checks):
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: run `execute[reload_sysctl]` (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - Runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: restart `service[ssh]` (delayed)
- Conditional: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - Runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: restart `service[ssh]` (delayed)
- Declares `service[ssh]` with `action :nothing` (only triggered by notifies above)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (6: 5 ufw + 1 reload_sysctl)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Config: `user www-data`, `worker_processes auto`, `worker_connections 768`, gzip on, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: reload `service[nginx]` (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Config: `server_tokens off`, rate limiting zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer overflow protections (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeout settings (body/header/send = 10s), global SSL settings (TLSv1.2/1.3, cipher suite, session cache)
  - Notifies: reload `service[nginx]` (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites:
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
- Iterations: Runs 3 times for sites (all have `ssl_enabled: true`, so none are skipped):
  - **test.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if` checking file existence):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if` checking file existence):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate (guarded by `not_if` checking file existence):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: reload `service[nginx]` (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites:
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables passed: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with ssl_certificate, ssl_certificate_key, TLSv1.2/1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, `try_files`, deny `.ht*` and `.git/.svn` locations, per-site access/error logs
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables passed: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables passed: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
- Deletes the default nginx site: removes `/etc/nginx/sites-enabled/default`
  - Notifies: reload `service[nginx]` (delayed)
- Resources: template (3), link (3), file (1)

---

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

---

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime by `openssl` using only public organizational placeholder values (`O=Example Org`, `emailAddress=admin@example.com`). No private keys are stored in the cookbook itself — they are generated on the target host and never leave it.

---

## Checks for the Migration

**Files to verify**:

| File | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Global nginx configuration |
| `/etc/nginx/conf.d/security.conf` | nginx security snippet (rate limits, buffers, SSL globals) |
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
| `/etc/ssl/private/test.cluster.local.key` | Private key for test site |
| `/etc/ssl/certs/ci.cluster.local.crt` | Self-signed cert for CI site |
| `/etc/ssl/private/ci.cluster.local.key` | Private key for CI site |
| `/etc/ssl/certs/status.cluster.local.crt` | Self-signed cert for status site |
| `/etc/ssl/private/status.cluster.local.key` | Private key for status site |
| `/etc/fail2ban/jail.local` | fail2ban jail configuration |
| `/etc/sysctl.d/99-security.conf` | Kernel hardening parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: none
- Network interfaces: all interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 time |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 time |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 time |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 time |

---

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl status ssh

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
# 4. VIRTUAL HOST CONFIG FILES
# ============================================================

# test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "EXISTS" || echo "MISSING"
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
readlink -f /etc/nginx/sites-enabled/test.cluster.local  # should resolve to sites-available/test.cluster.local

# ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "EXISTS" || echo "MISSING"
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
readlink -f /etc/nginx/sites-enabled/ci.cluster.local  # should resolve to sites-available/ci.cluster.local

# status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "EXISTS" || echo "MISSING"
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
readlink -f /etc/nginx/sites-enabled/status.cluster.local  # should resolve to sites-available/status.cluster.local

# Default site must be absent
test ! -f /etc/nginx/sites-enabled/default && echo "DEFAULT REMOVED OK" || echo "WARNING: default site still present"

# ============================================================
# 5. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local
ls -lah /opt/server/test/
stat /opt/server/test/index.html  # owner should be www-data:www-data, mode 0644
cat /opt/server/test/index.html | grep -i "Test Environment"

# ci.cluster.local
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html  # owner should be www-data:www-data, mode 0644
cat /opt/server/ci/index.html | grep -i "CI/CD"

# status.cluster.local
ls -lah /opt/server/status/
stat /opt/server/status/index.html  # owner should be www-data:www-data, mode 0644
cat /opt/server/status/index.html | grep -i "System Status"

# ============================================================
# 6. SSL CERTIFICATES
# ============================================================

# test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/test.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'  # mode should be 640, group ssl-cert

# ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/ci.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'  # mode should be 640, group ssl-cert

# status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/status.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'  # mode should be 640, group ssl-cert

# SSL directory permissions
stat /etc/ssl/certs | grep Access   # should be 0755, owner root:root
stat /etc/ssl/private | grep Access # should be 0710, owner root:ssl-cert

# ============================================================
# 7. HTTP CONNECTIVITY TESTS (add --resolve if DNS not configured)
# ============================================================

# test.cluster.local — HTTP should redirect to HTTPS (301)
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://test.cluster.local/

# test.cluster.local — HTTPS should return 200 with content
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
# Expected: HTTP/1.1 200 OK
curl -k -s --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -i "Test Environment"

# ci.cluster.local — HTTP should redirect to HTTPS (301)
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://ci.cluster.local/

# ci.cluster.local — HTTPS should return 200 with content
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
# Expected: HTTP/1.1 200 OK
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -i "CI/CD"

# status.cluster.local — HTTP should redirect to HTTPS (301)
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://status.cluster.local/

# status.cluster.local — HTTPS should return 200 with content
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
# Expected: HTTP/1.1 200 OK
curl -k -s --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -i "System Status"

# ============================================================
# 8. SECURITY HEADERS VERIFICATION
# ============================================================

# test.cluster.local
curl -k -s -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# ci.cluster.local
curl -k -s -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# status.cluster.local
curl -k -s -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# ============================================================
# 9. FAIL2BAN
# ============================================================
systemctl status fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|findtime|enabled'
# Expected: bantime=3600, findtime=600, maxretry=3 in [DEFAULT]

# ============================================================
# 10. UFW FIREWALL
# ============================================================
ufw status verbose
# Expected: Status: active, Default: deny (incoming), allow (outgoing)
# Expected rules: 22/tcp (ssh) ALLOW IN, 80/tcp (http) ALLOW IN, 443/tcp (https) ALLOW IN
ufw status | grep -E '22|80|443'

# ============================================================
# 11. SYSCTL KERNEL PARAMETERS
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter          # Expected: 1
sysctl net.ipv4.conf.all.accept_redirects   # Expected: 0
sysctl net.ipv4.conf.all.send_redirects     # Expected: 0
sysctl net.ipv4.conf.all.log_martians       # Expected: 1
sysctl net.ipv4.icmp_echo_ignore_all        # Expected: 1
sysctl net.ipv4.tcp_syncookies              # Expected: 1
sysctl net.ipv4.tcp_max_syn_backlog         # Expected: 2048
sysctl net.ipv6.conf.all.disable_ipv6      # Expected: 1

# ============================================================
# 12. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config
# Expected: PermitRootLogin no

grep -E '^PasswordAuthentication' /etc/ssh/sshd_config
# Expected: PasswordAuthentication no

sshd -T | grep -E 'permitrootlogin|passwordauthentication'
# Expected: permitrootlogin no, passwordauthentication no

# ============================================================
# 13. NGINX LOGS
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 14. NGINX GLOBAL CONFIG PARAMETERS
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'user|worker_processes|worker_connections|gzip|keepalive_timeout'
# Expected: user www-data, worker_processes auto, worker_connections 768, gzip on, keepalive_timeout 65

cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|client_body_buffer_size|ssl_protocols'
# Expected: server_tokens off, rate limit zones defined, client_body_buffer_size 1K, ssl_protocols TLSv1.2 TLSv1.3
```