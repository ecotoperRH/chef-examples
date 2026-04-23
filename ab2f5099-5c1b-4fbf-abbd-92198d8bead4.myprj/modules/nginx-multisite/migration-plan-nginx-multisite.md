# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with per-site self-signed TLS certificates, deploys static HTML landing pages to each site's document root, hardens the OS with UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl security parameters, and locks down SSH by disabling root login and password authentication.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / virtual hosting)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/test.cluster.local` → symlinked to `/etc/nginx/sites-enabled/test.cluster.local`
  - Static file: `/opt/server/test/index.html` (Test Environment landing page)
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static file: `/opt/server/ci/index.html` (CI/CD Dashboard landing page)
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only

- **status.cluster.local**: System Status page virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static file: `/opt/server/status/index.html` (System Status landing page)
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only

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
- Entry point. Includes 4 sub-recipes in strict order: security → nginx → ssl → sites.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via 5 execute resources (each guarded by `not_if` idempotency checks):
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: `service[ssh]` restart (delayed)
- **Conditional** — if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - `execute[disable password auth]`: runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded by `not_if` grep check)
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` is declared with `action :nothing` — only triggered by the above notifies
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh hardening)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Config: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log, includes conf.d/*.conf and sites-enabled/*
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Config: server_tokens=off, rate-limit zones (login: 10r/m / 10MB, api: 30r/m / 10MB), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, client_body_timeout=10, client_header_timeout=10, send_timeout=10, ssl_session_cache=shared:SSL:10m, ssl_protocols=TLSv1.2 TLSv1.3, ssl_prefer_server_ciphers=on
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
  - **test.cluster.local** (`document_root: /opt/server/test`):
    - `directory[/opt/server/test]`: creates directory, owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/test/index.html]`: deploys static file from `files/default/test/index.html`, owner=www-data, group=www-data, mode=0644
  - **ci.cluster.local** (`document_root: /opt/server/ci`):
    - `directory[/opt/server/ci]`: creates directory, owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/ci/index.html]`: deploys static file from `files/default/ci/index.html`, owner=www-data, group=www-data, mode=0644
  - **status.cluster.local** (`document_root: /opt/server/status`):
    - `directory[/opt/server/status]`: creates directory, owner=www-data, group=www-data, mode=0755, recursive=true
    - `cookbook_file[/opt/server/status/index.html]`: deploys static file from `files/default/status/index.html`, owner=www-data, group=www-data, mode=0644
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local (all have `ssl_enabled: true`, so none are skipped by the `next unless config['ssl_enabled']` guard)
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: generates self-signed certificate (RSA 2048-bit, 365 days, subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`)
    - Writes cert to `/etc/ssl/certs/test.cluster.local.crt`
    - Writes key to `/etc/ssl/private/test.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if` — skips if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: generates self-signed certificate (same parameters, CN=ci.cluster.local)
    - Writes cert to `/etc/ssl/certs/ci.cluster.local.crt`
    - Writes key to `/etc/ssl/private/ci.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if` — skips if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: generates self-signed certificate (same parameters, CN=status.cluster.local)
    - Writes cert to `/etc/ssl/certs/status.cluster.local.crt`
    - Writes key to `/etc/ssl/private/status.cluster.local.key`, then `chmod 640` and `chown root:ssl-cert`
    - Guarded by `not_if` — skips if both cert and key files already exist
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
  - **test.cluster.local**:
    - `template[/etc/nginx/sites-available/test.cluster.local]`: renders `site.conf.erb` with variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key (mode 0644)
    - Template renders: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443) with SSL config, HSTS header, X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
    - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]`: symlink → `/etc/nginx/sites-available/test.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `template[/etc/nginx/sites-available/ci.cluster.local]`: renders `site.conf.erb` with variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key (mode 0644)
    - Template renders: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443) with SSL config, HSTS, security headers, gzip, access_log=/var/log/nginx/ci.cluster.local_access.log, error_log=/var/log/nginx/ci.cluster.local_error.log
    - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]`: symlink → `/etc/nginx/sites-available/ci.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `template[/etc/nginx/sites-available/status.cluster.local]`: renders `site.conf.erb` with variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key (mode 0644)
    - Template renders: HTTP server block (port 80) with 301 redirect to HTTPS; HTTPS server block (port 443) with SSL config, HSTS, security headers, gzip, access_log=/var/log/nginx/status.cluster.local_access.log, error_log=/var/log/nginx/status.cluster.local_error.log
    - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]`: symlink → `/etc/nginx/sites-available/status.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
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
- `nginx` — managed (enabled + started); reloaded on any config/cert/site change
- `fail2ban` — managed (enabled + started); restarted on jail.local change
- `ssh` (sshd) — managed (action: nothing, only restarted when sshd_config is modified by the two SSH hardening execute resources)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded, non-secret subject string (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`). No private keys are stored in the cookbook itself — they are generated on the target host.

## Checks for the Migration

**Files to verify**:

| File | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Global nginx configuration |
| `/etc/nginx/conf.d/security.conf` | nginx security snippet (rate limits, buffer sizes, SSL globals) |
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
| `/etc/sysctl.d/99-security.conf` | Kernel security parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |
| `/var/log/nginx/test.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/test.cluster.local_error.log` | Per-site error log (created at runtime) |
| `/var/log/nginx/ci.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/ci.cluster.local_error.log` | Per-site error log (created at runtime) |
| `/var/log/nginx/status.cluster.local_access.log` | Per-site access log (created at runtime) |
| `/var/log/nginx/status.cluster.local_error.log` | Per-site error log (created at runtime) |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Renders | Destination(s) |
|---|---|---|
| `nginx.conf.erb` | 1 time | `/etc/nginx/nginx.conf` |
| `security.conf.erb` | 1 time | `/etc/nginx/conf.d/security.conf` |
| `site.conf.erb` | 3 times | `/etc/nginx/sites-available/test.cluster.local`, `/etc/nginx/sites-available/ci.cluster.local`, `/etc/nginx/sites-available/status.cluster.local` |
| `fail2ban.jail.local.erb` | 1 time | `/etc/fail2ban/jail.local` |
| `sysctl-security.conf.erb` | 1 time | `/etc/sysctl.d/99-security.conf` |

## Pre-flight checks:
```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx      # Expected: enabled
systemctl is-enabled fail2ban   # Expected: enabled

ps aux | grep nginx | grep -v grep    # Expected: master + worker processes
ps aux | grep fail2ban | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful

# ============================================================
# 3. PORTS LISTENING
# ============================================================
ss -tlnp | grep nginx
# Expected: 0.0.0.0:80 and 0.0.0.0:443

netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 4. VIRTUAL HOST CONFIG FILES
# ============================================================

# test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/test.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-available/test.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/test.cluster.local

# ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/ci.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-available/ci.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/ci.cluster.local

# status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "EXISTS" || echo "MISSING"
test -L /etc/nginx/sites-enabled/status.cluster.local && echo "SYMLINK OK" || echo "SYMLINK MISSING"
readlink /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-available/status.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/status.cluster.local

# Default site must be ABSENT
test ! -f /etc/nginx/sites-enabled/default && echo "DEFAULT REMOVED OK" || echo "WARNING: default site still present"

# ============================================================
# 5. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local
ls -lah /opt/server/test/
test -f /opt/server/test/index.html && echo "index.html EXISTS" || echo "MISSING"
stat -c "%U:%G %a" /opt/server/test/index.html
# Expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/test
# Expected: www-data:www-data 755

# ci.cluster.local
ls -lah /opt/server/ci/
test -f /opt/server/ci/index.html && echo "index.html EXISTS" || echo "MISSING"
stat -c "%U:%G %a" /opt/server/ci/index.html
# Expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/ci
# Expected: www-data:www-data 755

# status.cluster.local
ls -lah /opt/server/status/
test -f /opt/server/status/index.html && echo "index.html EXISTS" || echo "MISSING"
stat -c "%U:%G %a" /opt/server/status/index.html
# Expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/status
# Expected: www-data:www-data 755

# ============================================================
# 6. SSL CERTIFICATES
# ============================================================

# test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/test.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=test.cluster.local, notAfter=~365 days from issue
stat -c "%a %U:%G" /etc/ssl/private/test.cluster.local.key
# Expected: 640 root:ssl-cert

# ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/ci.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=ci.cluster.local, notAfter=~365 days from issue
stat -c "%a %U:%G" /etc/ssl/private/ci.cluster.local.key
# Expected: 640 root:ssl-cert

# status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/status.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=status.cluster.local, notAfter=~365 days from issue
stat -c "%a %U:%G" /etc/ssl/private/status.cluster.local.key
# Expected: 640 root:ssl-cert

# SSL directory permissions
stat -c "%a %U:%G" /etc/ssl/certs
# Expected: 755 root:root
stat -c "%a %U:%G" /etc/ssl/private
# Expected: 710 root:ssl-cert

# ============================================================
# 7. HTTP/HTTPS CONNECTIVITY (per site)
# ============================================================

# test.cluster.local — HTTP must redirect to HTTPS
curl -v -H "Host: test.cluster.local" http://localhost/ 2>&1 | grep -E 'HTTP/|Location:'
# Expected: HTTP/1.1 301, Location: https://test.cluster.local/

# test.cluster.local — HTTPS must return 200
curl -k -v -H "Host: test.cluster.local" https://localhost/ 2>&1 | grep -E 'HTTP/|title'
# Expected: HTTP/2 200, <title>Test Environment - test.cluster.local</title>

# ci.cluster.local — HTTP must redirect to HTTPS
curl -v -H "Host: ci.cluster.local" http://localhost/ 2>&1 | grep -E 'HTTP/|Location:'
# Expected: HTTP/1.1 301, Location: https://ci.cluster.local/

# ci.cluster.local — HTTPS must return 200
curl -k -v -H "Host: ci.cluster.local" https://localhost/ 2>&1 | grep -E 'HTTP/|title'
# Expected: HTTP/2 200, <title>CI/CD Dashboard - ci.cluster.local</title>

# status.cluster.local — HTTP must redirect to HTTPS
curl -v -H "Host: status.cluster.local" http://localhost/ 2>&1 | grep -E 'HTTP/|Location:'
# Expected: HTTP/1.1 301, Location: https://status.cluster.local/

# status.cluster.local — HTTPS must return 200
curl -k -v -H "Host: status.cluster.local" https://localhost/ 2>&1 | grep -E 'HTTP/|title'
# Expected: HTTP/2 200, <title>System Status - status.cluster.local</title>

# ============================================================
# 8. SECURITY HEADERS (per site)
# ============================================================

# test.cluster.local
curl -k -s -I -H "Host: test.cluster.local" https://localhost/ | \
  grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# ci.cluster.local
curl -k -s -I -H "Host: ci.cluster.local" https://localhost/ | \
  grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Referrer-Policy|Content-Security-Policy'
# Expected: all 6 headers present

# status.cluster.local
curl -k -s -I -H "Host: status.cluster.local" https://localhost/ | \
  grep -E 