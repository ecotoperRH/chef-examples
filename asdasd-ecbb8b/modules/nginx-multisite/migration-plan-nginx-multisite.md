# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with global security headers and rate-limiting, generates self-signed TLS certificates for each site, deploys per-site document roots with static `index.html` landing pages, and hardens the host OS via UFW firewall rules, fail2ban intrusion prevention (with five jails), and kernel-level sysctl security parameters. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / virtual hosting)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL: Enabled — self-signed certificate
    - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
    - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Static content: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), per-site access/error logs at `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL: Enabled — self-signed certificate
    - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
    - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Static content: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers, per-site access/error logs at `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL: Enabled — self-signed certificate
    - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
    - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Static content: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers, per-site access/error logs at `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`

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

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: delayed restart of `service[fail2ban]`
- Configures UFW firewall via idempotent execute resources:
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel security parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (IPv4+IPv6), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
  - Notifies: delayed run of `execute[reload_sysctl]` (`sysctl -p /etc/sysctl.d/99-security.conf`)
- Conditional: if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: delayed restart of `service[ssh]`
- Conditional: if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: delayed restart of `service[ssh]`
- `service[ssh]` declared with action `:nothing` (only triggered by notifications above)
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + disable root login + disable password auth)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
    - Sets: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, includes `conf.d/*.conf` and `sites-enabled/*`
    - Notifies: delayed reload of `service[nginx]`
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
    - Sets: `server_tokens off`, rate-limit zones (`login` 10r/m, `api` 30r/m), buffer overflow protections (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeout settings (body/header/send = 10s), global SSL settings (TLSv1.2/TLSv1.3, cipher suite, `ssl_prefer_server_ciphers on`, session cache 10m)
    - Notifies: delayed reload of `service[nginx]`
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
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
- Creates system group: `ssl-cert`
- Creates SSL directory structure:
  - `directory[/etc/ssl/certs]`: owner=root, group=root, mode=0755
  - `directory[/etc/ssl/private]`: owner=root, group=ssl-cert, mode=0710
- Iterations: Runs 3 times for sites (all have `ssl_enabled: true`) — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
  - **test.cluster.local** (ssl_enabled=true → condition passes):
    - `execute[generate-ssl-cert-test.cluster.local]`: generates self-signed cert with `openssl req -x509 -nodes -days 365 -newkey rsa:2048`, CN=test.cluster.local, org="Example Org", emailAddress=admin@example.com
    - Writes key to `/etc/ssl/private/test.cluster.local.key`, cert to `/etc/ssl/certs/test.cluster.local.crt`
    - Post-generation: `chmod 640 /etc/ssl/private/test.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local** (ssl_enabled=true → condition passes):
    - `execute[generate-ssl-cert-ci.cluster.local]`: same openssl command, CN=ci.cluster.local
    - Writes key to `/etc/ssl/private/ci.cluster.local.key`, cert to `/etc/ssl/certs/ci.cluster.local.crt`
    - Post-generation: `chmod 640 /etc/ssl/private/ci.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local** (ssl_enabled=true → condition passes):
    - `execute[generate-ssl-cert-status.cluster.local]`: same openssl command, CN=status.cluster.local
    - Writes key to `/etc/ssl/private/status.cluster.local.key`, cert to `/etc/ssl/certs/status.cluster.local.crt`
    - Post-generation: `chmod 640 /etc/ssl/private/status.cluster.local.key`, `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: delayed reload of `service[nginx]`
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites — **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Renders: HTTP server block (port 80, 301 redirect to HTTPS) + HTTPS server block (port 443 ssl http2, TLSv1.2/TLSv1.3, HSTS, security headers, gzip, try_files, deny .ht/.git/.svn, per-site logs)
    - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
    - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
    - Notifies: delayed reload of `service[nginx]`
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
    - Notifies: delayed reload of `service[nginx]`
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: delayed reload of `service[nginx]`
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `fail2ban` — intrusion prevention
- `ufw` — host-based firewall
- `nginx` — web server
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `fail2ban` — enabled + started; restarted on jail.local changes
- `nginx` — enabled + started; reloaded on any config/template/cert/site change
- `ssh` (sshd) — action `:nothing`; restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT`) and a non-sensitive contact email (`admin@example.com`). These are development/internal certificates and do not represent stored secrets.

> **Note for the Solutions Architect**: When migrating to Ansible/AAP, if real (CA-signed) certificates are required in production, the certificate content and private key material will need to be sourced from a secrets manager (e.g., HashiCorp Vault, CyberArk, or AAP Credential Store) and injected as Ansible variables. This is not currently handled by the Chef cookbook.

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
| `/opt/server/test/index.html` | Static file | Test site landing page |
| `/opt/server/ci/index.html` | Static file | CI site landing page |
| `/opt/server/status/index.html` | Static file | Status site landing page |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Self-signed, 365 days |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 0640, root:ssl-cert |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 0640, root:ssl-cert |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 0640, root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | 5 jails configured |
| `/etc/sysctl.d/99-security.conf` | Config | Kernel hardening params |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |
| `/var/log/nginx/test.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/test.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/ci.cluster.local_error.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_access.log` | Log | Created on first request |
| `/var/log/nginx/status.cluster.local_error.log` | Log | Created on first request |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all three sites — redirect only), 443 (HTTPS, all three sites)
- Unix sockets: none
- Network interfaces: all interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× |

`site.conf.erb` renders **3 times total** (once per site), each with different `server_name`, `document_root`, `cert_file`, and `key_file` variables.

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx    # should output: enabled
systemctl is-enabled fail2ban # should output: enabled

ps aux | grep nginx | grep -v grep    # should show master + worker processes
ps aux | grep fail2ban | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
# Expected output: nginx: configuration file /etc/nginx/nginx.conf test is successful

# ============================================================
# 3. PORTS LISTENING
# ============================================================
ss -tlnp | grep nginx
# Expected: 0.0.0.0:80 and 0.0.0.0:443

netstat -tulpn | grep -E ':80|:443'
lsof -i :80
lsof -i :443

# ============================================================
# 4. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect
curl -I http://test.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://test.cluster.local/

# HTTPS response (self-signed cert, skip verify)
curl -k -I https://test.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers present
curl -k -s -D - https://test.cluster.local -o /dev/null | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy'
# Expected: all 5 headers present

# Document root and index file
ls -lah /opt/server/test/index.html
stat -c "%U:%G %a" /opt/server/test/index.html
# Expected: www-data:www-data 644

# Virtual host config
ls -lah /etc/nginx/sites-available/test.cluster.local
readlink /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-available/test.cluster.local

# TLS certificate
ls -lah /etc/ssl/certs/test.cluster.local.crt
stat -c "%U:%G %a" /etc/ssl/private/test.cluster.local.key
# Expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=test.cluster.local, notAfter=365 days from issuance

# Per-site logs
grep -c "" /var/log/nginx/test.cluster.local_access.log 2>/dev/null || echo "log not yet created (no requests)"
tail -5 /var/log/nginx/test.cluster.local_error.log 2>/dev/null || echo "no errors"

# ============================================================
# 5. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect
curl -I http://ci.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://ci.cluster.local/

# HTTPS response
curl -k -I https://ci.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers present
curl -k -s -D - https://ci.cluster.local -o /dev/null | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy'
# Expected: all 5 headers present

# Document root and index file
ls -lah /opt/server/ci/index.html
stat -c "%U:%G %a" /opt/server/ci/index.html
# Expected: www-data:www-data 644

# Virtual host config
ls -lah /etc/nginx/sites-available/ci.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-available/ci.cluster.local

# TLS certificate
ls -lah /etc/ssl/certs/ci.cluster.local.crt
stat -c "%U:%G %a" /etc/ssl/private/ci.cluster.local.key
# Expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=ci.cluster.local

# Per-site logs
grep -c "" /var/log/nginx/ci.cluster.local_access.log 2>/dev/null || echo "log not yet created (no requests)"
tail -5 /var/log/nginx/ci.cluster.local_error.log 2>/dev/null || echo "no errors"

# ============================================================
# 6. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect
curl -I http://status.cluster.local
# Expected: HTTP/1.1 301 Moved Permanently
# Expected: Location: https://status.cluster.local/

# HTTPS response
curl -k -I https://status.cluster.local
# Expected: HTTP/1.1 200 OK

# Security headers present
curl -k -s -D - https://status.cluster.local -o /dev/null | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy'
# Expected: all 5 headers present

# Document root and index file
ls -lah /opt/server/status/index.html
stat -c "%U:%G %a" /opt/server/status/index.html
# Expected: www-data:www-data 644

# Virtual host config
ls -lah /etc/nginx/sites-available/status.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-available/status.cluster.local

# TLS certificate
ls -lah /etc/ssl/certs/status.cluster.local.crt
stat -c "%U:%G %a" /etc/ssl/private/status.cluster.local.key
# Expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
# Expected: subject=.../CN=status.cluster.local

# Per-site logs
grep -c "" /var/log/nginx/status.cluster.local_access.log 2>/dev/null || echo "log not yet created (no requests)"
tail -5 /var/log/nginx/status.cluster.local_error.log 2>/dev/null || echo "no errors"

# ============================================================
# 7. DEFAULT SITE REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>/dev/null && echo "ERROR: default site still exists" || echo "OK: default site removed"

# ============================================================
# 8. NGINX GLOBAL CONFIG VALIDATION
# ============================================================
grep -E 'worker_processes|worker_connections|keepalive_timeout|gzip' /etc/nginx/nginx.conf
# Expected: worker_processes auto; worker_connections 768; keepalive_timeout 65; gzip on;

grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols' /etc/nginx/conf.d/security.conf
# Expected: server_tokens off; limit_req_zone ... zone=login:10m rate=10r/m; client_max_body_size 1k; ssl_protocols TLSv1.2 TLSv1.3;

# ============================================================
# 9. FAIL2BAN
# ============================================================
fail2ban-client status
# Expected: Number of jail: 5 (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch + DEFAULT)

fail2ban-client status sshd
# Expected: Status for the jail: sshd / Currently banned: 0 (or more)

fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

grep -E 'bantime|findtime|maxretry' /etc/fail2ban/jail.local
# Expected: bantime = 3600, findtime = 600, maxretry = 3

# ============================================================
# 10. UFW FIREWALL
# ============================================================
ufw status verbose
# Expected: Status: active
# Expected rules: 22/tcp (ssh) ALLOW IN, 80/tcp (http) ALLOW IN, 443/tcp (https) ALLOW IN
# Expected default: deny (incoming)

ufw status | grep -E "22|80|443"
# Expected: 22/tcp ALLOW IN, 80/tcp ALLOW IN, 443/tcp ALLOW IN

# ============================================================
# 11. SYSCTL KERNEL HARDENING
# ============================================================
sysctl net.ipv4.conf.all.rp_filter
# Expected: net.ipv4.conf.all.rp_filter = 1

sysctl net.ipv4.conf.all.accept_redirects
# Expected: net.ipv4.conf.all.accept_redirects = 0

sysctl net.ip