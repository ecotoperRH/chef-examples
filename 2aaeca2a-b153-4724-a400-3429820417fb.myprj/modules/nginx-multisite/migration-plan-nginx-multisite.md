# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with per-site self-signed TLS certificates, deploys static HTML landing pages to each site's document root, applies kernel-level security hardening via sysctl, enforces firewall rules with UFW, and sets up fail2ban intrusion prevention. SSH is also hardened by disabling root login and password authentication. All 3 sites redirect HTTP→HTTPS and share a common nginx security configuration.

---

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / virtual hosting)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA 2048-bit cert, 365-day validity, CN=test.cluster.local
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA 2048-bit cert, 365-day validity, CN=ci.cluster.local
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System status/monitoring virtual host
  - Location/Path: `/opt/server/status` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/SSL)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed RSA 2048-bit cert, 365-day validity, CN=status.cluster.local
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
cookbooks/nginx-multisite/files/default/test/index.html
cookbooks/nginx-multisite/files/default/ci/index.html
cookbooks/nginx-multisite/files/default/status/index.html
cookbooks/nginx-multisite/attributes/default.rb
```

---

## Module Explanation

The cookbook performs operations in this order:

**1. default** (`cookbooks/nginx-multisite/recipes/default.rb`):
- Entry point. Includes 4 sub-recipes in strict order: `security` → `nginx` → `ssl` → `sites`.
- Resources: include_recipe (4)

---

**2. security** (`cookbooks/nginx-multisite/recipes/security.rb`):
- Installs packages: `fail2ban`, `ufw`
- Enables and starts the `fail2ban` service
- Deploys fail2ban jail configuration:
  - Template: `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode 0644)
  - Configures 5 jails: `[DEFAULT]` (bantime=3600, findtime=600, maxretry=3), `[sshd]` (enabled, port=ssh, logpath=/var/log/auth.log), `[nginx-http-auth]` (enabled, port=http,https, logpath=/var/log/nginx/*error.log), `[nginx-limit-req]` (enabled, maxretry=10), `[nginx-botsearch]` (enabled, maxretry=2, logpath=/var/log/nginx/*access.log)
  - Notifies: `service[fail2ban]` restart (delayed)
- Configures UFW firewall rules (idempotent via `not_if` guards):
  - `ufw --force default deny` — sets default deny policy
  - `ufw allow ssh` — opens port 22/tcp
  - `ufw allow http` — opens port 80/tcp
  - `ufw allow https` — opens port 443/tcp
  - `ufw --force enable` — activates the firewall
- Deploys kernel security hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Settings applied: IP spoofing protection (`rp_filter=1`), ICMP redirect ignore (`accept_redirects=0`), send redirect disable (`send_redirects=0`), source routing disable (`accept_source_route=0`), martian logging (`log_martians=1`), ICMP ping ignore (`icmp_echo_ignore_all=1`), broadcast ping ignore (`icmp_echo_ignore_broadcasts=1`), IPv6 disable (`disable_ipv6=1` for all, default, lo), TCP SYN flood protection (`tcp_syncookies=1`, `tcp_max_syn_backlog=2048`, `tcp_synack_retries=2`, `tcp_syn_retries=5`)
  - Notifies: `execute[reload_sysctl]` run (delayed) → runs `sysctl -p /etc/sysctl.d/99-security.conf`
- Conditional SSH hardening (both conditions are true by default):
  - `node['security']['ssh']['disable_root'] = true` → runs `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - `node['security']['ssh']['password_auth'] == false` → runs `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (guarded: skips if already set)
  - Both notify: `service[ssh]` restart (delayed)
- `service[ssh]` is declared with `action :nothing` — only restarts when notified
- Resources: package (1, multi-package), service (2: fail2ban + ssh), template (2), execute (7: 5 ufw + reload_sysctl + 2 ssh sed)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `keepalive_timeout 65`, `sendfile on`, `tcp_nopush on`, `tcp_nodelay on`, `gzip on`, access_log `/var/log/nginx/access.log`, error_log `/var/log/nginx/error.log`, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer limits (`client_body_buffer_size 1K`, `client_header_buffer_size 1k`, `client_max_body_size 1k`, `large_client_header_buffers 2 1k`), timeouts (`client_body_timeout 10`, `client_header_timeout 10`, `send_timeout 10`), global SSL settings (`TLSv1.2 TLSv1.3`, strong cipher suite, `ssl_prefer_server_ciphers on`, `ssl_session_cache shared:SSL:10m`, `ssl_session_timeout 10m`)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local** (document_root: `/opt/server/test`):
    - Creates directory `/opt/server/test` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/test/index.html` → `/opt/server/test/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **ci.cluster.local** (document_root: `/opt/server/ci`):
    - Creates directory `/opt/server/ci` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: www-data, group: www-data, mode: 0644)
  - **status.cluster.local** (document_root: `/opt/server/status`):
    - Creates directory `/opt/server/status` (owner: www-data, group: www-data, mode: 0755, recursive: true)
    - Deploys static file: `files/default/status/index.html` → `/opt/server/status/index.html` (owner: www-data, group: www-data, mode: 0644)
- Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner: root, group: root, mode: 0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner: root, group: ssl-cert, mode: 0710)
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so the `next unless` guard never skips any):
  - **test.cluster.local**:
    - Generates self-signed certificate (guarded: skips if both `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/test.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Generates self-signed certificate (guarded: skips if both `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/ci.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Generates self-signed certificate (guarded: skips if both `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` already exist):
      - `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"`
      - `chmod 640 /etc/ssl/private/status.cluster.local.key`
      - `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, multi-package), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations — runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`:
  - **test.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Config: HTTP port 80 → HTTPS 301 redirect; HTTPS port 443 with `ssl http2`; SSL protocols TLSv1.2/TLSv1.3; strong cipher suite; HSTS `max-age=31536000; includeSubDomains`; security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy); gzip enabled; `try_files $uri $uri/ =404`; deny `.ht*`, `.git`, `.svn`; access_log `/var/log/nginx/test.cluster.local_access.log`; error_log `/var/log/nginx/test.cluster.local_error.log`
    - Creates symlink: `/etc/nginx/sites-enabled/test.cluster.local` → `/etc/nginx/sites-available/test.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Config: identical structure to test.cluster.local; access_log `/var/log/nginx/ci.cluster.local_access.log`; error_log `/var/log/nginx/ci.cluster.local_error.log`
    - Creates symlink: `/etc/nginx/sites-enabled/ci.cluster.local` → `/etc/nginx/sites-available/ci.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Deploys virtual host config:
      - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Config: identical structure; access_log `/var/log/nginx/status.cluster.local_access.log`; error_log `/var/log/nginx/status.cluster.local_error.log`
    - Creates symlink: `/etc/nginx/sites-enabled/status.cluster.local` → `/etc/nginx/sites-available/status.cluster.local`
    - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx site: `/etc/nginx/sites-enabled/default` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
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

**Service dependencies** (systemd services managed):
- `fail2ban` — enabled + started; restarted on jail config change
- `nginx` — enabled + started; reloaded on any config/cert/site change
- `ssh` (sshd) — action :nothing; restarted only when sshd_config is modified

---

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The self-signed TLS certificates are generated at runtime using `openssl req` with a hardcoded placeholder subject (`O=Example Org`, `emailAddress=admin@example.com`) — these are not secrets, but the Ansible developer should note that in a production migration, real certificates (e.g., from Let's Encrypt or an internal CA) should be substituted and their private keys managed via Ansible Vault or AAP Credential objects.

---

## Checks for the Migration

**Files to verify**:

| File/Directory | Type | Expected |
|---|---|---|
| `/etc/nginx/nginx.conf` | Config | Rendered from `nginx.conf.erb` |
| `/etc/nginx/conf.d/security.conf` | Config | Rendered from `security.conf.erb` |
| `/etc/nginx/sites-available/test.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-available/ci.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-available/status.cluster.local` | Config | Rendered from `site.conf.erb` |
| `/etc/nginx/sites-enabled/test.cluster.local` | Symlink | → `/etc/nginx/sites-available/test.cluster.local` |
| `/etc/nginx/sites-enabled/ci.cluster.local` | Symlink | → `/etc/nginx/sites-available/ci.cluster.local` |
| `/etc/nginx/sites-enabled/status.cluster.local` | Symlink | → `/etc/nginx/sites-available/status.cluster.local` |
| `/etc/nginx/sites-enabled/default` | File | Must NOT exist (deleted) |
| `/opt/server/test/index.html` | Static file | Deployed from `files/default/test/index.html` |
| `/opt/server/ci/index.html` | Static file | Deployed from `files/default/ci/index.html` |
| `/opt/server/status/index.html` | Static file | Deployed from `files/default/status/index.html` |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | Generated by openssl, mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | Generated by openssl, mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Generated by openssl |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | Generated by openssl, mode 640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | Rendered from `fail2ban.jail.local.erb` |
| `/etc/sysctl.d/99-security.conf` | Config | Rendered from `sysctl-security.conf.erb` |
| `/etc/ssh/sshd_config` | Config | `PermitRootLogin no`, `PasswordAuthentication no` |
| `/var/log/nginx/` | Log dir | Per-site access and error logs created at runtime |

**Service endpoints to check**:
- Port 80/tcp — nginx HTTP (all 3 virtual hosts; immediately redirects to HTTPS)
- Port 443/tcp — nginx HTTPS (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`)
- Port 22/tcp — SSH (UFW allows; root login disabled, password auth disabled)
- Unix sockets: None
- Network interfaces: nginx binds to all interfaces (no `listen` IP restriction in templates)

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---|
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1× (unconditional) |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1× (unconditional) |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1× |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1× |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1× |
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1× (unconditional) |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1× (unconditional) |

Total: 7 template renders (`site.conf.erb` renders 3 times with different variables)

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

ps aux | grep nginx | grep -v grep
ps aux | grep fail2ban | grep -v grep

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|root'

# Verify default site is removed
ls -la /etc/nginx/sites-enabled/default 2>&1 | grep "No such file"  # should return "No such file"

# ============================================================
# 3. VIRTUAL HOST CONFIGS - verify each site individually
# ============================================================

# Site: test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "PASS: config exists" || echo "FAIL: config missing"
test -L /etc/nginx/sites-enabled/test.cluster.local && echo "PASS: symlink exists" || echo "FAIL: symlink missing"
readlink /etc/nginx/sites-enabled/test.cluster.local  # should be /etc/nginx/sites-available/test.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/test.cluster.local

# Site: ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "PASS: config exists" || echo "FAIL: config missing"
test -L /etc/nginx/sites-enabled/ci.cluster.local && echo "PASS: symlink exists" || echo "FAIL: symlink missing"
readlink /etc/nginx/sites-enabled/ci.cluster.local  # should be /etc/nginx/sites-available/ci.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/ci.cluster.local

# Site: status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "PASS: config exists" || echo "FAIL: config missing"
test -L /etc/nginx/sites-enabled/status.cluster.local && echo "PASS: symlink exists" || echo "FAIL: symlink missing"
readlink /etc/nginx/sites-enabled/status.cluster.local  # should be /etc/nginx/sites-available/status.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/status.cluster.local

# ============================================================
# 4. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# Site: test.cluster.local
ls -lah /opt/server/test/
test -f /opt/server/test/index.html && echo "PASS: index.html exists" || echo "FAIL: index.html missing"
stat -c "%U:%G %a" /opt/server/test/index.html  # should be www-data:www-data 644
stat -c "%U:%G %a" /opt/server/test             # should be www-data:www-data 755

# Site: ci.cluster.local
ls -lah /opt/server/ci/
test -f /opt/server/ci/index.html && echo "PASS: index.html exists" || echo "FAIL: index.html missing"
stat -c "%U:%G %a" /opt/server/ci/index.html    # should be www-data:www-data 644
stat -c "%U:%G %a" /opt/server/ci               # should be www-data:www-data 755

# Site: status.cluster.local
ls -lah /opt/server/status/
test -f /opt/server/status/index.html && echo "PASS: index.html exists" || echo "FAIL: index.html missing"
stat -c "%U:%G %a" /opt/server/status/index.html  # should be www-data:www-data 644
stat -c "%U:%G %a" /opt/server/status             # should be www-data:www-data 755

# ============================================================
# 5. SSL CERTIFICATES - verify each site individually
# ============================================================

# Site: test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt && echo "PASS: cert exists" || echo "FAIL: cert missing"
test -f /etc/ssl/private/test.cluster.local.key && echo "PASS: key exists" || echo "FAIL: key missing"
stat -c "%U:%G %a" /etc/ssl/private/test.cluster.local.key  # should be root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep "CN=test.cluster.local"
openssl verify -CAfile /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/test.cluster.local.crt  # self-signed: OK

# Site: ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "PASS: cert exists" || echo "FAIL: cert missing"
test -f /etc/ssl/private/ci.cluster.local.key && echo "PASS: key exists" || echo "FAIL: key missing"
stat -c "%U:%G %a" /etc/ssl/private/ci.cluster.local.key    # should be root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep "CN=ci.cluster.local"
openssl verify -CAfile /etc/ssl/certs/ci.cluster.local.crt /etc/ssl/certs/ci.cluster.local.crt  # self-signed: OK

# Site: status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt && echo "PASS: cert exists" || echo "FAIL: cert missing"
test -f /etc/ssl/private/status.cluster.local.key && echo "PASS: key exists" || echo "FAIL: key missing"
stat -c "%U:%G %a" /etc/ssl/private/status.cluster.local.key  # should be root:ssl-cert 640
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep "CN=status.cluster.local"
openssl verify -CAfile /etc/ssl/certs/status.cluster.local.crt /etc/ssl/certs/status.cluster.local.crt  # self-signed: OK

# SSL directory permissions
stat -c "%U:%G %a" /etc/ssl/certs    # should be root:root 755
stat -c "%U:%G %a" /etc/ssl/private  # should be root:ssl-cert 710

# ============================================================
# 6. HTTP/HTTPS CONNECTIVITY - test each site individually
# ============================================================

# Site: test.cluster.local
curl -v -o /dev/null -s -w "%{http_code}" http://test.cluster.local  # should return 301
curl -sk --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local -o /dev/null -w "%{http_code}"  # should return 200
curl -sk --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local | grep -i "test"  # should match page content

# Site: ci.cluster.local
curl -v -o /dev/null -s -w "%{http_code}" http://ci.cluster.local  # should return 301
curl -sk --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local -o /dev/null -w "%{http_code}"  # should return 200
curl -sk --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local | grep -i "ci"  # should match page content

# Site: status.cluster.local
curl -v -o /dev/null -s -w "%{http_code}" http://status.cluster.local  # should return