---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened Nginx web server hosting 3 virtual sites (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`), each with SSL/TLS enabled via self-signed certificates. It also applies OS-level security hardening including UFW firewall rules, fail2ban intrusion prevention with 5 jails (sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch, and DEFAULT), and kernel sysctl security parameters. All 3 sites redirect HTTP→HTTPS, serve static content from `/opt/server/{test,ci,status}`, and share a common Nginx security configuration with rate limiting and security headers.

## Service Type and Instances

**Service Type**: Web Server (Nginx multi-site with OS security hardening)

**Configured Instances**:

- **test.cluster.local**:
  - Document Root: `/opt/server/test`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/test.cluster.local.crt`, key: `/etc/ssl/private/test.cluster.local.key`
  - Static file deployed: `files/default/test/index.html` → `/opt/server/test/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**:
  - Document Root: `/opt/server/ci`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/ci.cluster.local.crt`, key: `/etc/ssl/private/ci.cluster.local.key`
  - Static file deployed: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**:
  - Document Root: `/opt/server/status`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/SSL)
  - SSL: Enabled — certificate: `/etc/ssl/certs/status.cluster.local.crt`, key: `/etc/ssl/private/status.cluster.local.key`
  - Static file deployed: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: TLSv1.2/TLSv1.3, HSTS, security headers (X-Frame-Options DENY, X-Content-Type-Options, X-XSS-Protection, CSP), gzip enabled
  - Logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`

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
- Entry point that chains all four sub-recipes in order
- Resources: include_recipe (4): security, nginx, ssl, sites

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: DEFAULT (bantime=3600, findtime=600, maxretry=3), **sshd** (port=ssh, logpath=/var/log/auth.log, maxretry=3), **nginx-http-auth** (port=http,https, logpath=/var/log/nginx/*error.log, maxretry=3), **nginx-limit-req** (port=http,https, logpath=/var/log/nginx/*error.log, maxretry=10), **nginx-botsearch** (port=http,https, logpath=/var/log/nginx/*access.log, maxretry=2)
  - Notifies: restart `service[fail2ban]` (delayed)
- Configures UFW firewall via 5 idempotent execute resources:
  - `ufw --force default deny` (skipped if already set)
  - `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw --force enable` (skipped if already active)
- Deploys kernel hardening parameters:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Parameters set: IP spoofing protection (rp_filter=1), ICMP redirect ignore (accept_redirects=0), send redirects disabled (send_redirects=0), source routing disabled (accept_source_route=0), martian logging (log_martians=1), ICMP ping ignore (icmp_echo_ignore_all=1), broadcast ping ignore (icmp_echo_ignore_broadcasts=1), IPv6 disabled (disable_ipv6=1), TCP SYN flood protection (tcp_syncookies=1, tcp_max_syn_backlog=2048, tcp_synack_retries=2, tcp_syn_retries=5)
  - Notifies: run `execute[reload_sysctl]` (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional: `node['security']['ssh']['disable_root']` is `true` →
  - Executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: restart `service[ssh]` (delayed)
- Conditional: `node['security']['ssh']['password_auth']` is `false` →
  - Executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: restart `service[ssh]` (delayed)
- `service[ssh]` declared with action `:nothing` (only triggered by notifications above)
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + disable_root + disable_password_auth)

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global Nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, tcp_nopush=on, tcp_nodelay=on, keepalive_timeout=65, gzip=on, access_log=/var/log/nginx/access.log, error_log=/var/log/nginx/error.log
  - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: reload `service[nginx]` (delayed)
- Deploys Nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: server_tokens=off, rate limit zones (login: 10r/m, api: 30r/m), client_body_buffer_size=1K, client_header_buffer_size=1k, client_max_body_size=1k, large_client_header_buffers=2 1k, client_body_timeout=10, client_header_timeout=10, send_timeout=10, ssl_session_cache=shared:SSL:10m, ssl_session_timeout=10m, ssl_protocols=TLSv1.2 TLSv1.3, ssl_prefer_server_ciphers=on
  - Notifies: reload `service[nginx]` (delayed)
- Enables and starts `service[nginx]`
- Iterations: Runs 3 times for sites:
  - **test.cluster.local**:
    - Creates directory `/opt/server/test` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner=www-data, group=www-data, mode=0644)
  - **ci.cluster.local**:
    - Creates directory `/opt/server/ci` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner=www-data, group=www-data, mode=0644)
  - **status.cluster.local**:
    - Creates directory `/opt/server/status` (owner=www-data, group=www-data, mode=0755, recursive=true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner=www-data, group=www-data, mode=0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates group `ssl-cert`
- Creates SSL certificate directory `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites (all have `ssl_enabled: true`):
  - **test.cluster.local** (ssl_enabled=true, condition passes):
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Key output: `/etc/ssl/private/test.cluster.local.key`
    - Cert output: `/etc/ssl/certs/test.cluster.local.crt`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local** (ssl_enabled=true, condition passes):
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Key output: `/etc/ssl/private/ci.cluster.local.key`
    - Cert output: `/etc/ssl/certs/ci.cluster.local.crt`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local** (ssl_enabled=true, condition passes):
    - Generates self-signed certificate via `openssl req -x509 -nodes -days 365 -newkey rsa:2048`
    - Key output: `/etc/ssl/private/status.cluster.local.key`
    - Cert output: `/etc/ssl/certs/status.cluster.local.crt`
    - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
    - Post-generation: `chmod 640` on key, `chown root:ssl-cert` on key
    - Idempotent: skipped if both cert and key files already exist
    - Notifies: reload `service[nginx]` (delayed)
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites:
  - **test.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Rendered config: HTTP server block on port 80 with `return 301 https://...` redirect; HTTPS server block on port 443 with ssl http2, TLSv1.2/TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, try_files, deny .ht/.git/.svn locations
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **ci.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
  - **status.cluster.local**:
    - Deploys vhost config via template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Notifies: reload `service[nginx]` (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: reload `service[nginx]` (delayed)
- Deletes `/etc/nginx/sites-enabled/default` (removes the default Nginx placeholder site)
  - Notifies: reload `service[nginx]` (delayed)
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in metadata.rb)

**System package dependencies**:
- `fail2ban` — intrusion prevention
- `ufw` — firewall management
- `nginx` — web server
- `openssl` — SSL certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies**:
- `fail2ban` — managed by systemd (enabled + started)
- `nginx` — managed by systemd (enabled + started; reloaded on config changes)
- `ssh` / `sshd` — managed by systemd (restarted only when sshd_config is modified)

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with placeholder subject fields (`O=Example Org`, `emailAddress=admin@example.com`) hardcoded in the `ssl.rb` recipe — these are not secrets but are worth noting as deployment-time configuration values that may need to be parameterized in Ansible (e.g., the certificate subject fields and the 365-day validity period).

## Checks for the Migration

**Files to verify**:

| File | Description |
|---|---|
| `/etc/nginx/nginx.conf` | Global Nginx configuration |
| `/etc/nginx/conf.d/security.conf` | Nginx security snippet (rate limits, buffer sizes, SSL globals) |
| `/etc/nginx/sites-available/test.cluster.local` | Virtual host config for test site |
| `/etc/nginx/sites-available/ci.cluster.local` | Virtual host config for ci site |
| `/etc/nginx/sites-available/status.cluster.local` | Virtual host config for status site |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | Must NOT exist (deleted by recipe) |
| `/opt/server/test/index.html` | Static content for test site |
| `/opt/server/ci/index.html` | Static content for ci site |
| `/opt/server/status/index.html` | Static content for status site |
| `/etc/ssl/certs/test.cluster.local.crt` | Self-signed cert for test site |
| `/etc/ssl/private/test.cluster.local.key` | Private key for test site |
| `/etc/ssl/certs/ci.cluster.local.crt` | Self-signed cert for ci site |
| `/etc/ssl/private/ci.cluster.local.key` | Private key for ci site |
| `/etc/ssl/certs/status.cluster.local.crt` | Self-signed cert for status site |
| `/etc/ssl/private/status.cluster.local.key` | Private key for status site |
| `/etc/fail2ban/jail.local` | Fail2ban jail configuration |
| `/etc/sysctl.d/99-security.conf` | Kernel security parameters |
| `/etc/ssh/sshd_config` | SSH daemon config (PermitRootLogin no, PasswordAuthentication no) |
| `/var/log/nginx/access.log` | Global Nginx access log |
| `/var/log/nginx/error.log` | Global Nginx error log |
| `/var/log/nginx/test.cluster.local_access.log` | Per-site access log for test |
| `/var/log/nginx/ci.cluster.local_access.log` | Per-site access log for ci |
| `/var/log/nginx/status.cluster.local_access.log` | Per-site access log for status |

**Service endpoints to check**:
- Ports listening: 80 (HTTP, all 3 sites — redirect only), 443 (HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0)

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
# 4. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://test.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://test.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect test.cluster.local:443 -servername test.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and static file
ls -lah /opt/server/test/index.html
stat /opt/server/test/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data 0644
# Verify vhost config
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
# Verify symlink
ls -la /etc/nginx/sites-enabled/test.cluster.local
# Verify SSL cert and key
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert 0640
# Verify per-site logs exist
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 5. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://ci.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://ci.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and static file
ls -lah /opt/server/ci/index.html
stat /opt/server/ci/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data 0644
# Verify vhost config
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
# Verify symlink
ls -la /etc/nginx/sites-enabled/ci.cluster.local
# Verify SSL cert and key
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert 0640
# Verify per-site logs exist
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 6. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect (expect: 301 Moved Permanently)
curl -I -k http://status.cluster.local
# HTTPS response (expect: 200 OK)
curl -I -k https://status.cluster.local
# Verify SSL certificate CN
echo | openssl s_client -connect status.cluster.local:443 -servername status.cluster.local 2>/dev/null | openssl x509 -noout -subject -dates
# Verify document root and static file
ls -lah /opt/server/status/index.html
stat /opt/server/status/index.html | grep -E 'Uid|Gid|Access'  # should be www-data:www-data 0644
# Verify vhost config
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|listen|ssl_certificate|root|return 301'
# Verify symlink
ls -la /etc/nginx/sites-enabled/status.cluster.local
# Verify SSL cert and key
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Uid|Gid|Access'  # should be root:ssl-cert 0640
# Verify per-site logs exist
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 7. DEFAULT SITE REMOVED
# ============================================================
# Must NOT exist (expect: No such file or directory)
ls /etc/nginx/sites-enabled/default && echo "FAIL: default site still enabled" || echo "OK: default site removed"

# ============================================================
# 8. NGINX GLOBAL CONFIG
# ============================================================
cat /etc/nginx/nginx.conf | grep -E 'user|worker_processes|worker_connections|keepalive_timeout|gzip'
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols'

# ============================================================
# 9. SECURITY HEADERS (check on each site)
# ============================================================
curl -sI -k https://test.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy|Referrer-Policy'
curl -sI -k https://ci.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy|Referrer-Policy'
curl -sI -k https://status.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Content-Security-Policy|Referrer-Policy'

# ============================================================
# 10. FAIL2BAN
# ============================================================
systemctl status fail2ban
fail2ban-client status
# Verify all 5 jails are active
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
# Verify jail config
cat /etc/fail2ban/jail.local | grep -E 'bantime|findtime|maxretry|enabled'

# ============================================================
# 11. UFW FIREWALL
# ============================================================
ufw status verbose
# Expected output should show:
#   Status: active
#   Default: deny (incoming)
#   22/tcp (ssh) ALLOW IN
#   80/tcp (http) ALLOW IN
#   443/tcp (https) ALLOW IN
ufw status | grep -E 'Status: active|22|80|443'

# ============================================================
# 12. SYSCTL KERNEL PARAMETERS
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter          # expect: 1
sysctl net.ipv4.conf.all.accept_redirects   # expect: 0
sysctl net.ipv4.conf.all.send_redirects     # expect: 0
sysctl net.ipv4.tcp_syncookies              # expect: 1
sysctl net.ipv4.tcp_max_syn_backlog         # expect: 2048
sysctl net.ipv6.conf.all.disable_ipv6      # expect: 1
sysctl net.ipv4.icmp_echo_ignore_all       # expect: 1

# ============================================================
# 13. SSH HARDENING
# ============================================================
grep -E '^PermitRootLogin' /etc/ssh/sshd_config        # expect: PermitRootLogin no
grep -E '^PasswordAuthentication' /etc/ssh/sshd_config  # expect: PasswordAuthentication no
sshd -T | grep -E 'permitrootlogin|passwordauthentication'

# ============================================================
# 14. SSL DIRECTORY PERMISSIONS
# ============================================================
stat /etc/ssl/certs | grep -E 'Uid|Gid|Access'    # expect: root:root 0755
stat /etc/ssl/private | grep -E 'Uid|Gid|Access'  # expect: root:ssl-cert 0710
getent group ssl-cert                               # expect: ssl-cert group exists

# ============================================================
# 15. NGINX LOGS
# ============================================================
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
# Check for errors on startup
journalctl -u nginx --since "1 hour ago" | grep -E 'error|warn|crit'
```