---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting **3 SSL-enabled virtual hosts** (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs nginx, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations, and applies a full security hardening layer including UFW firewall rules, fail2ban intrusion prevention (with 5 jails), and kernel-level sysctl hardening. All three sites redirect HTTP→HTTPS and serve static HTML landing pages from `/opt/server/{test,ci,status}`.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site with security hardening)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA-2048 cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` served from document root

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA-2048 cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` served from document root

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP→HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: ssl_enabled=true, self-signed RSA-2048 cert, 365-day validity, TLSv1.2+TLSv1.3, HSTS enabled, static `index.html` served from document root

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
- Deploys fail2ban configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall via 5 idempotent execute resources:
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel hardening configuration:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: IP spoofing protection (rp_filter=1), ICMP redirect ignore, source routing disabled, martian logging, ICMP ping ignore (icmp_echo_ignore_all=1), TCP SYN flood protection (syncookies=1, max_syn_backlog=2048), IPv6 disabled
  - Notifies: `execute[reload_sysctl]` run (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional SSH hardening (both conditions are true by default):
  - `node['security']['ssh']['disable_root'] = true` → runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - `node['security']['ssh']['password_auth'] = false` → runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Both notify: `service[ssh]` restart (delayed)
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (8: 5 ufw + reload_sysctl + disable_root + disable_password_auth)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Sets: user=www-data, worker_processes=auto, worker_connections=768, sendfile/tcp_nopush/tcp_nodelay on, keepalive_timeout=65, gzip on, includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Sets: server_tokens off, rate limiting zones (login: 10r/m, api: 30r/m), buffer overflow protections (client_body_buffer_size=1K, client_max_body_size=1K), timeout settings (body/header/send=10s), global SSL settings (TLSv1.2+TLSv1.3, strong cipher suite)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
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

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local** (all have `ssl_enabled=true`, so none are skipped)
  - **test.cluster.local**:
    - Generates self-signed certificate via `execute[generate-ssl-cert-test.cluster.local]`:
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
      - Idempotent: skipped if both `.crt` and `.key` files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate via `execute[generate-ssl-cert-ci.cluster.local]`:
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
      - Idempotent: skipped if both `.crt` and `.key` files already exist
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate via `execute[generate-ssl-cert-status.cluster.local]`:
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
      - Idempotent: skipped if both `.crt` and `.key` files already exist
      - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs **3 times** for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**
  - **test.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
      - Config: HTTP port 80 redirects to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS (max-age=31536000; includeSubDomains), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip enabled, access_log=/var/log/nginx/test.cluster.local_access.log, error_log=/var/log/nginx/test.cluster.local_error.log
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
      - Config: HTTP port 80 redirects to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS (max-age=31536000; includeSubDomains), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip enabled, access_log=/var/log/nginx/ci.cluster.local_access.log, error_log=/var/log/nginx/ci.cluster.local_error.log
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys virtual host config via template `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
      - Config: HTTP port 80 redirects to HTTPS; HTTPS port 443 with ssl http2, TLSv1.2+TLSv1.3, HSTS (max-age=31536000; includeSubDomains), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, CSP), gzip enabled, access_log=/var/log/nginx/status.cluster.local_access.log, error_log=/var/log/nginx/status.cluster.local_error.log
      - Notifies: `service[nginx]` reload (delayed)
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx site: `/etc/nginx/sites-enabled/default` (action: delete)
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
- `nginx` — managed: enabled + started; reloaded on config/cert/site changes
- `fail2ban` — managed: enabled + started; restarted on jail.local changes
- `ssh` (sshd) — managed: restarted on sshd_config changes (root login / password auth)

## Credentials

**Detection Summary**: 0 credentials detected across 0 files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed and created locally using `openssl` with a hardcoded placeholder subject (`/C=US/ST=Example/O=Example Org/emailAddress=admin@example.com`) — these are development/internal certificates and do not involve any external secret store. The `admin@example.com` email address embedded in the certificate subject is a placeholder and not a functional credential.

## Checks for the Migration

**Files to verify**:

| File/Directory | Type | Expected |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | mode 0644, owned root:root |
| `/etc/nginx/conf.d/security.conf` | Config | mode 0644, owned root:root |
| `/etc/nginx/sites-available/test.cluster.local` | Config | mode 0644 |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | mode 0644 |
| `/etc/nginx/sites-available/status.cluster.local` | Config | mode 0644 |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → sites-available/test.cluster.local |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → sites-available/ci.cluster.local |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → sites-available/status.cluster.local |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | mode 0644, owned www-data:www-data |
| `/opt/server/ci/index.html` | Static file | mode 0644, owned www-data:www-data |
| `/opt/server/status/index.html` | Static file | mode 0644, owned www-data:www-data |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | exists, valid |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 0640, owned root:ssl-cert |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | exists, valid |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 0640, owned root:ssl-cert |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | exists, valid |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 0640, owned root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | mode 0644 |
| `/etc/sysctl.d/99-security.conf` | Config | mode 0644 |
| `/etc/ssh/sshd_config` | Config | PermitRootLogin no, PasswordAuthentication no |
| `/var/log/nginx/test.cluster.local_access.log` | Log | created on first request |
| `/var/log/nginx/test.cluster.local_error.log` | Log | created on first request |
| `/var/log/nginx/ci.cluster.local_access.log` | Log | created on first request |
| `/var/log/nginx/ci.cluster.local_error.log` | Log | created on first request |
| `/var/log/nginx/status.cluster.local_access.log` | Log | created on first request |
| `/var/log/nginx/status.cluster.local_error.log` | Log | created on first request |

**Service endpoints to check**:
- Ports listening: **80** (nginx HTTP, all sites), **443** (nginx HTTPS, all sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

**Templates rendered**:

| Template | Destination | Renders |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 time |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 time |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 time |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 time |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 time |

## Pre-flight checks:
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
# 3. PORT VERIFICATION
# ============================================================
ss -tlnp | grep -E ':80|:443'
netstat -tulpn | grep nginx
lsof -i :80
lsof -i :443

# ============================================================
# 4. VIRTUAL HOST CONFIG FILES
# ============================================================
# Verify all 3 sites-available configs exist
ls -lah /etc/nginx/sites-available/
test -f /etc/nginx/sites-available/test.cluster.local    && echo "OK: test.cluster.local config exists"   || echo "MISSING: test.cluster.local"
test -f /etc/nginx/sites-available/ci.cluster.local      && echo "OK: ci.cluster.local config exists"     || echo "MISSING: ci.cluster.local"
test -f /etc/nginx/sites-available/status.cluster.local  && echo "OK: status.cluster.local config exists" || echo "MISSING: status.cluster.local"

# Verify all 3 symlinks in sites-enabled
ls -lah /etc/nginx/sites-enabled/
test -L /etc/nginx/sites-enabled/test.cluster.local   && echo "OK: test symlink exists"   || echo "MISSING: test symlink"
test -L /etc/nginx/sites-enabled/ci.cluster.local     && echo "OK: ci symlink exists"     || echo "MISSING: ci symlink"
test -L /etc/nginx/sites-enabled/status.cluster.local && echo "OK: status symlink exists" || echo "MISSING: status symlink"

# Verify default site is REMOVED
test ! -f /etc/nginx/sites-enabled/default && echo "OK: default site removed" || echo "FAIL: default site still present"

# ============================================================
# 5. DOCUMENT ROOTS AND STATIC FILES
# ============================================================
# Site: test.cluster.local
ls -lah /opt/server/test/
test -f /opt/server/test/index.html && echo "OK: test/index.html exists" || echo "MISSING: test/index.html"
stat -c "%U:%G %a" /opt/server/test/index.html  # expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/test/            # expected: www-data:www-data 755

# Site: ci.cluster.local
ls -lah /opt/server/ci/
test -f /opt/server/ci/index.html && echo "OK: ci/index.html exists" || echo "MISSING: ci/index.html"
stat -c "%U:%G %a" /opt/server/ci/index.html    # expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/ci/              # expected: www-data:www-data 755

# Site: status.cluster.local
ls -lah /opt/server/status/
test -f /opt/server/status/index.html && echo "OK: status/index.html exists" || echo "MISSING: status/index.html"
stat -c "%U:%G %a" /opt/server/status/index.html  # expected: www-data:www-data 644
stat -c "%U:%G %a" /opt/server/status/            # expected: www-data:www-data 755

# ============================================================
# 6. SSL CERTIFICATES
# ============================================================
# Certificate: test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt   && echo "OK: test cert exists" || echo "MISSING: test cert"
test -f /etc/ssl/private/test.cluster.local.key && echo "OK: test key exists"  || echo "MISSING: test key"
stat -c "%U:%G %a" /etc/ssl/private/test.cluster.local.key  # expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -text | grep -E 'CN=|Not After'

# Certificate: ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt   && echo "OK: ci cert exists" || echo "MISSING: ci cert"
test -f /etc/ssl/private/ci.cluster.local.key && echo "OK: ci key exists"  || echo "MISSING: ci key"
stat -c "%U:%G %a" /etc/ssl/private/ci.cluster.local.key    # expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -text | grep -E 'CN=|Not After'

# Certificate: status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt   && echo "OK: status cert exists" || echo "MISSING: status cert"
test -f /etc/ssl/private/status.cluster.local.key && echo "OK: status key exists"  || echo "MISSING: status key"
stat -c "%U:%G %a" /etc/ssl/private/status.cluster.local.key  # expected: root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -text | grep -E 'CN=|Not After'

# Verify cert/key pair match for all 3 sites
diff <(openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -pubkey -noout) \
     <(openssl pkey -in /etc/ssl/private/test.cluster.local.key -pubout) \
     && echo "OK: test cert/key match" || echo "FAIL: test cert/key mismatch"

diff <(openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -pubkey -noout) \
     <(openssl pkey -in /etc/ssl/private/ci.cluster.local.key -pubout) \
     && echo "OK: ci cert/key match" || echo "FAIL: ci cert/key mismatch"

diff <(openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -pubkey -noout) \
     <(openssl pkey -in /etc/ssl/private/status.cluster.local.key -pubout) \
     && echo "OK: status cert/key match" || echo "FAIL: status cert/key mismatch"

# ============================================================
# 7. HTTP/HTTPS CONNECTIVITY (requires /etc/hosts or DNS)
# ============================================================
# Site: test.cluster.local — HTTP must redirect to HTTPS (301)
curl -I -k http://test.cluster.local   # expected: 301 Moved Permanently → https://
curl -I -k https://test.cluster.local  # expected: 200 OK
curl -sk https://test.cluster.local | grep -q "Test Environment" && echo "OK: test page content correct" || echo "FAIL: test page content wrong"

# Site: ci.cluster.local — HTTP must redirect to HTTPS (301)
curl -I -k http://ci.cluster.local     # expected: 301 Moved Permanently → https://
curl -I -k https://ci.cluster.local    # expected: 200 OK
curl -sk https://ci.cluster.local | grep -q "CI/CD Dashboard" && echo "OK: ci page content correct" || echo "FAIL: ci page content wrong"

# Site: status.cluster.local — HTTP must redirect to HTTPS (301)
curl -I -k http://status.cluster.local   # expected: 301 Moved Permanently → https://
curl -I -k https://status.cluster.local  # expected: 200 OK
curl -sk https://status.cluster.local | grep -q "System Status" && echo "OK: status page content correct" || echo "FAIL: status page content wrong"

# Verify HSTS header is present on all 3 sites
curl -skI https://test.cluster.local   | grep -i "Strict-Transport-Security"  # expected: max-age=31536000; includeSubDomains
curl -skI https://ci.cluster.local     | grep -i "Strict-Transport-Security"
curl -skI https://status.cluster.local | grep -i "Strict-Transport-Security"

# Verify security headers on all 3 sites
curl -skI https://test.cluster.local   | grep -E "X-