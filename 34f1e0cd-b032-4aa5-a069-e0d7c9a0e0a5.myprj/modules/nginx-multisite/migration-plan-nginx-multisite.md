# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with per-site self-signed TLS certificates, deploys static HTML landing pages for each site, hardens the OS with UFW firewall rules, fail2ban intrusion prevention, and kernel-level sysctl security parameters, and locks down SSH by disabling root login and password authentication.

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
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only, self-signed cert (365 days, RSA 2048)

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/ci.cluster.local` → symlinked to `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static content: `files/default/ci/index.html` → `/opt/server/ci/index.html`
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only, self-signed cert (365 days, RSA 2048)

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP → 301 redirect to HTTPS), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - nginx config: `/etc/nginx/sites-available/status.cluster.local` → symlinked to `/etc/nginx/sites-enabled/status.cluster.local`
  - Static content: `files/default/status/index.html` → `/opt/server/status/index.html`
  - Key Config: ssl_enabled=true, HTTP→HTTPS redirect, HSTS, TLSv1.2+TLSv1.3 only, self-signed cert (365 days, RSA 2048)

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

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Entry point. Includes 4 sub-recipes in strict order: security → nginx → ssl → sites.
   - Resources: include_recipe (4)

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs packages: `fail2ban`, `ufw`
   - Enables and starts the `fail2ban` service
   - Deploys fail2ban jail configuration:
     - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
     - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2)
     - Notifies: delayed restart of `service[fail2ban]`
   - Configures UFW firewall via 5 idempotent execute resources:
     - `ufw_default_deny`: `ufw --force default deny` (skipped if already set)
     - `ufw_allow_ssh`: `ufw allow ssh` (skipped if 22/tcp already allowed)
     - `ufw_allow_http`: `ufw allow http` (skipped if 80/tcp already allowed)
     - `ufw_allow_https`: `ufw allow https` (skipped if 443/tcp already allowed)
     - `ufw_enable`: `ufw --force enable` (skipped if already active)
   - Deploys kernel sysctl hardening:
     - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
     - Parameters set: `net.ipv4.conf.*.rp_filter=1` (IP spoofing protection), `accept_redirects=0` (ICMP redirect ignore), `send_redirects=0`, `accept_source_route=0`, `log_martians=1`, `icmp_echo_ignore_all=1`, `icmp_echo_ignore_broadcasts=1`, `ipv6.disable_ipv6=1` (all interfaces), `tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`
     - Notifies: delayed run of `execute[reload_sysctl]` (`sysctl -p /etc/sysctl.d/99-security.conf`)
   - Conditional: if `node['security']['ssh']['disable_root']` is true (default: **true**):
     - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
     - Notifies: delayed restart of `service[ssh]`
   - Conditional: if `node['security']['ssh']['password_auth']` is false (default: **false**):
     - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
     - Notifies: delayed restart of `service[ssh]`
   - `service[ssh]` declared with `action :nothing` (only triggered by notifies above)
   - Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + disable root login + disable password auth)

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs package: `nginx`
   - Deploys global nginx configuration:
     - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
     - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `keepalive_timeout 65`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`
     - Includes: `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
     - Notifies: delayed reload of `service[nginx]`
   - Deploys nginx security snippet:
     - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
     - Settings: `server_tokens off`, rate limiting zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), `client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`, timeouts (body/header/send = 10s), SSL: `TLSv1.2 TLSv1.3`, strong cipher suite, `ssl_prefer_server_ciphers on`
     - Notifies: delayed reload of `service[nginx]`
   - Enables and starts `service[nginx]`
   - Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
     - **test.cluster.local**:
       - `directory[/opt/server/test]`: owner=www-data, group=www-data, mode=0755, recursive=true
       - `cookbook_file[/opt/server/test/index.html]`: source=`test/index.html`, owner=www-data, group=www-data, mode=0644
     - **ci.cluster.local**:
       - `directory[/opt/server/ci]`: owner=www-data, group=www-data, mode=0755, recursive=true
       - `cookbook_file[/opt/server/ci/index.html]`: source=`ci/index.html`, owner=www-data, group=www-data, mode=0644
     - **status.cluster.local**:
       - `directory[/opt/server/status]`: owner=www-data, group=www-data, mode=0755, recursive=true
       - `cookbook_file[/opt/server/status/index.html]`: source=`status/index.html`, owner=www-data, group=www-data, mode=0644
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs packages: `openssl`, `ca-certificates`
   - Creates system group: `ssl-cert`
   - Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
   - Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
   - Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local (all have `ssl_enabled: true`, so none are skipped)
     - **test.cluster.local**:
       - `execute[generate-ssl-cert-test.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` do not already exist
       - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/test.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
       - Notifies: delayed reload of `service[nginx]`
     - **ci.cluster.local**:
       - `execute[generate-ssl-cert-ci.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` do not already exist
       - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/ci.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
       - Notifies: delayed reload of `service[nginx]`
     - **status.cluster.local**:
       - `execute[generate-ssl-cert-status.cluster.local]`: Generates self-signed cert if `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` do not already exist
       - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/status.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
       - Notifies: delayed reload of `service[nginx]`
   - Resources: package (1, multi-package), group (1), directory (2), execute (3)

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations: Runs 3 times for sites: test.cluster.local, ci.cluster.local, status.cluster.local
     - **test.cluster.local**:
       - `template[/etc/nginx/sites-available/test.cluster.local]`: source=`site.conf.erb`, mode=0644
         - Variables passed: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
         - Rendered config: HTTP server block (port 80) with `return 301 https://...`; HTTPS server block (port 443 ssl http2) with ssl_certificate, ssl_certificate_key, TLSv1.2+TLSv1.3, HSTS header, X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP, gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
         - Notifies: delayed reload of `service[nginx]`
       - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
         - Notifies: delayed reload of `service[nginx]`
     - **ci.cluster.local**:
       - `template[/etc/nginx/sites-available/ci.cluster.local]`: source=`site.conf.erb`, mode=0644
         - Variables passed: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
         - Notifies: delayed reload of `service[nginx]`
       - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
         - Notifies: delayed reload of `service[nginx]`
     - **status.cluster.local**:
       - `template[/etc/nginx/sites-available/status.cluster.local]`: source=`site.conf.erb`, mode=0644
         - Variables passed: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
         - Notifies: delayed reload of `service[nginx]`
       - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
         - Notifies: delayed reload of `service[nginx]`
   - Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
     - Notifies: delayed reload of `service[nginx]`
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
- `nginx` — managed: enabled + started; reloaded on any config/cert/site change
- `fail2ban` — managed: enabled + started; restarted on jail.local change
- `ssh` (sshd) — managed: restarted only when sshd_config is modified (disable_root or password_auth changes)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — these are development/internal certificates and contain no secret material. The private key files are protected by filesystem permissions (mode 0640, owner root:ssl-cert) rather than encryption.

## Checks for the Migration

**Files to verify**:

*nginx configuration:*
- `/etc/nginx/nginx.conf` — global nginx config
- `/etc/nginx/conf.d/security.conf` — security snippet (rate limiting, buffer sizes, SSL globals)
- `/etc/nginx/sites-available/test.cluster.local` — virtual host config for test site
- `/etc/nginx/sites-available/ci.cluster.local` — virtual host config for CI site
- `/etc/nginx/sites-available/status.cluster.local` — virtual host config for status site
- `/etc/nginx/sites-enabled/test.cluster.local` — symlink → sites-available
- `/etc/nginx/sites-enabled/ci.cluster.local` — symlink → sites-available
- `/etc/nginx/sites-enabled/status.cluster.local` — symlink → sites-available
- `/etc/nginx/sites-enabled/default` — must NOT exist (deleted)

*SSL certificates and keys:*
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`

*Document roots and static content:*
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`

*Security configuration:*
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config` — must contain `PermitRootLogin no` and `PasswordAuthentication no`

*Log files:*
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`
- `/var/log/nginx/test.cluster.local_access.log`
- `/var/log/nginx/test.cluster.local_error.log`
- `/var/log/nginx/ci.cluster.local_access.log`
- `/var/log/nginx/ci.cluster.local_error.log`
- `/var/log/nginx/status.cluster.local_access.log`
- `/var/log/nginx/status.cluster.local_error.log`

**Service endpoints to check**:
- Port 80 (HTTP, all 3 sites — redirect only)
- Port 443 (HTTPS, all 3 sites)
- Unix sockets: none
- Network interfaces: all interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` — rendered **1 time**
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` — rendered **1 time**
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` — rendered **1 time**
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` — rendered **1 time**
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` — rendered **1 time**

(`site.conf.erb` is rendered **3 times total**, once per site, with different variables each time)

## Pre-flight checks:
```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban
ps aux | grep nginx | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# ============================================================
# 3. SITE: test.cluster.local
# ============================================================
# HTTP → HTTPS redirect check (expect: 301 redirect)
curl -I -k http://test.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://test.cluster.local/

# HTTPS response check (expect: 200 OK with HTML content)
curl -I -k https://test.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify SSL certificate CN
openssl s_client -connect test.cluster.local:443 -servername test.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=test.cluster.local, notAfter=~365 days from issue

# Verify security headers
curl -sk -I https://test.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection'
# Should show all 4 headers present

# Verify document root and static file
ls -lah /opt/server/test/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/test/index.html
curl -sk https://test.cluster.local/ | grep -i "Test Environment"
# Should return HTML containing "Test Environment"

# Verify nginx vhost config
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/test.cluster.local
# Should be a symlink → /etc/nginx/sites-available/test.cluster.local

# Verify per-site logs exist
ls -lah /var/log/nginx/test.cluster.local_access.log
ls -lah /var/log/nginx/test.cluster.local_error.log

# ============================================================
# 4. SITE: ci.cluster.local
# ============================================================
# HTTP → HTTPS redirect check (expect: 301 redirect)
curl -I -k http://ci.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://ci.cluster.local/

# HTTPS response check (expect: 200 OK)
curl -I -k https://ci.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify SSL certificate CN
openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=ci.cluster.local

# Verify security headers
curl -sk -I https://ci.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection'

# Verify document root and static file
ls -lah /opt/server/ci/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/ci/index.html
curl -sk https://ci.cluster.local/ | grep -i "CI/CD"
# Should return HTML containing "CI/CD"

# Verify nginx vhost config
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/ci.cluster.local
# Should be a symlink → /etc/nginx/sites-available/ci.cluster.local

# Verify per-site logs exist
ls -lah /var/log/nginx/ci.cluster.local_access.log
ls -lah /var/log/nginx/ci.cluster.local_error.log

# ============================================================
# 5. SITE: status.cluster.local
# ============================================================
# HTTP → HTTPS redirect check (expect: 301 redirect)
curl -I -k http://status.cluster.local
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://status.cluster.local/

# HTTPS response check (expect: 200 OK)
curl -I -k https://status.cluster.local
# Should return: HTTP/1.1 200 OK

# Verify SSL certificate CN
openssl s_client -connect status.cluster.local:443 -servername status.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Should show: subject=.../CN=status.cluster.local

# Verify security headers
curl -sk -I https://status.cluster.local | grep -E 'Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|X-XSS-Protection'

# Verify document root and static file
ls -lah /opt/server/status/index.html
# Should show: -rw-r--r-- 1 www-data www-data ... /opt/server/status/index.html
curl -sk https://status.cluster.local/ | grep -i "System Status"
# Should return HTML containing "System Status"

# Verify nginx vhost config
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|ssl_certificate|root|listen'
ls -la /etc/nginx/sites-enabled/status.cluster.local
# Should be a symlink → /etc/nginx/sites-available/status.cluster.local

# Verify per-site logs exist
ls -lah /var/log/nginx/status.cluster.local_access.log
ls -lah /var/log/nginx/status.cluster.local_error.log

# ============================================================
# 6. DEFAULT SITE REMOVED
# ============================================================
ls /etc/nginx/sites-enabled/default 2>&1
# Should return: No such file or directory

# ============================================================
# 7. SSL CERTIFICATES AND KEYS
# ============================================================
# test.cluster.local
ls -lah /etc/ssl/certs/test.cluster.local.crt
ls -lah /etc/ssl/private/test.cluster.local.key
stat -c "%a %U %G" /etc/ssl/private/test.cluster.local.key
# Should show: 640 root ssl-cert

# ci.cluster.local
ls -lah /etc/ssl/certs/ci.cluster.local.crt
ls -lah /etc/ssl/private/ci.cluster.local.key
stat -c "%a %U %G" /etc/ssl/private/ci.cluster.local.key
# Should show: 640 root ssl-cert

# status.cluster.local
ls -lah /etc/ssl/certs/status.cluster.local.crt
ls -lah /etc/ssl/private/status.cluster.local.key
stat -c "%a %U %G" /etc/ssl/private/status.cluster.local.key
# Should show: 640 root ssl-cert

# Verify ssl-cert group exists
getent group ssl-cert
# Should return: ssl-cert:x:<gid>:

# ============================================================
# 8. FIREWALL (UFW)
# ============================================================
ufw status verbose
# Should show: Status: active
# Should show rules for: 22/tcp (SSH), 80/tcp (HTTP), 443/tcp (HTTPS)
# Should show: Default: deny (incoming)

ufw status | grep -E "22|80|443|Status|Default"

# ============================================================
# 9. FAIL2BAN
# ============================================================
systemctl status fail2ban
fail2ban-client status
# Should list jails: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch

fail2ban-client status sshd
# Should show: Currently banned: 0 (or more), Filter: enabled

fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|enabled'
# Should show: bantime = 3600, maxretry = 3 (default), enabled = true for all jails

# ============================================================
# 10. SYSCTL KERNEL HARDENING
# ============================================================
cat /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
# Should return: net.ipv4.conf.all.rp_filter = 1

sysctl net.ipv4.conf.all.accept_redirects
# Should return: net.ipv4.conf.all.accept_redirects = 0

sysctl net.ipv4.tcp_syncookies
# Should return: net.ipv4.tcp_syncookies = 1

sysctl net.ipv6.conf.all.disable_ipv6
# Should return: net.ipv6.conf.all.disable_ipv