---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures a hardened nginx web server hosting 3 SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`) on a single node. It installs and configures nginx with a global security configuration, generates self-signed TLS certificates for each site, deploys per-site nginx virtual host configurations with HTTP→HTTPS redirects, and hardens the host OS via UFW firewall rules, fail2ban intrusion prevention (with 5 jails), and kernel-level sysctl security parameters. SSH root login and password authentication are also disabled.

## Service Type and Instances

**Service Type**: Web Server (nginx multi-site / reverse proxy front-end)

**Configured Instances**:

- **test.cluster.local**: Test/development environment virtual host
  - Location/Path: `/opt/server/test` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP/2 enabled, HSTS header, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/test/index.html` → `/opt/server/test/index.html`

- **ci.cluster.local**: CI/CD Dashboard virtual host
  - Location/Path: `/opt/server/ci` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP/2 enabled, HSTS header, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/ci/index.html` → `/opt/server/ci/index.html`

- **status.cluster.local**: System Status Dashboard virtual host
  - Location/Path: `/opt/server/status` (document root)
  - Port/Socket: 80 (HTTP → HTTPS redirect), 443 (HTTPS/TLS)
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: `ssl_enabled: true`, self-signed cert (RSA 2048, 365 days), HTTP/2 enabled, HSTS header, TLSv1.2+TLSv1.3 only
  - Static file: `files/default/status/index.html` → `/opt/server/status/index.html`

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
- Configures UFW firewall via 5 idempotent execute resources:
  - `ufw_default_deny`: runs `ufw --force default deny` (skipped if already set)
  - `ufw_allow_ssh`: runs `ufw allow ssh` (skipped if 22/tcp already allowed)
  - `ufw_allow_http`: runs `ufw allow http` (skipped if 80/tcp already allowed)
  - `ufw_allow_https`: runs `ufw allow https` (skipped if 443/tcp already allowed)
  - `ufw_enable`: runs `ufw --force enable` (skipped if already active)
- Deploys kernel security hardening:
  - Template: `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode 0644)
  - Sets: IP spoofing protection (`rp_filter=1`), ICMP redirect ignore, source routing disabled, martian logging, ICMP ping ignore (`icmp_echo_ignore_all=1`), IPv6 disabled, TCP SYN flood protection (`tcp_syncookies=1`, `tcp_max_syn_backlog=2048`)
  - Notifies: `execute[reload_sysctl]` run (delayed) → `sysctl -p /etc/sysctl.d/99-security.conf`
- **Conditional** — if `node['security']['ssh']['disable_root']` is `true` (default: true):
  - `execute[disable root login]`: `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- **Conditional** — if `node['security']['ssh']['password_auth']` is `false` (default: false):
  - `execute[disable password auth]`: `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` (idempotent: skipped if already set)
  - Notifies: `service[ssh]` restart (delayed)
- `service[ssh]` declared with `action :nothing` — only triggered by the above notifiers
- Resources: package (1, 2 packages), service (2: fail2ban + ssh), template (2), execute (7)

---

**3. nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
- Installs package: `nginx`
- Deploys global nginx configuration:
  - Template: `nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode 0644)
  - Settings: `user www-data`, `worker_processes auto`, `worker_connections 768`, `sendfile on`, `tcp_nopush on`, `keepalive_timeout 65`, gzip enabled, includes `conf.d/*.conf` and `sites-enabled/*`
  - Notifies: `service[nginx]` reload (delayed)
- Deploys nginx security snippet:
  - Template: `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode 0644)
  - Settings: `server_tokens off`, rate-limit zones (`login:10m rate=10r/m`, `api:10m rate=30r/m`), buffer overflow protections (`client_body_buffer_size 1K`, `client_max_body_size 1k`), timeout settings (body/header/send = 10s), global SSL settings (TLSv1.2+TLSv1.3, strong cipher suite, session cache 10m)
  - Notifies: `service[nginx]` reload (delayed)
- Enables and starts the `nginx` service
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
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

---

**4. ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
- Installs packages: `openssl`, `ca-certificates`
- Creates system group: `ssl-cert`
- Creates SSL certificate directory: `/etc/ssl/certs` (owner=root, group=root, mode=0755)
- Creates SSL private key directory: `/etc/ssl/private` (owner=root, group=ssl-cert, mode=0710)
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local` (all have `ssl_enabled: true`, so none are skipped)
  - **test.cluster.local**:
    - `execute[generate-ssl-cert-test.cluster.local]`: generates self-signed cert if `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/test.cluster.local.key -out /etc/ssl/certs/test.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/test.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/test.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - `execute[generate-ssl-cert-ci.cluster.local]`: generates self-signed cert if `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ci.cluster.local.key -out /etc/ssl/certs/ci.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/ci.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/ci.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - `execute[generate-ssl-cert-status.cluster.local]`: generates self-signed cert if `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` do not already exist
    - Command: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/status.cluster.local.key -out /etc/ssl/certs/status.cluster.local.crt -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com"` then `chmod 640 /etc/ssl/private/status.cluster.local.key` and `chown root:ssl-cert /etc/ssl/private/status.cluster.local.key`
    - Notifies: `service[nginx]` reload (delayed)
- Resources: package (1, 2 packages), group (1), directory (2), execute (3)

---

**5. sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
- Iterations: Runs 3 times for sites: `test.cluster.local`, `ci.cluster.local`, `status.cluster.local`
  - **test.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local` (mode 0644)
      - Variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with HTTP/2, SSL cert paths, TLSv1.2+TLSv1.3, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `/etc/nginx/sites-available/test.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **ci.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local` (mode 0644)
      - Variables: `server_name=ci.cluster.local`, `document_root=/opt/server/ci`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/ci.cluster.local.crt`, `key_file=/etc/ssl/private/ci.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with HTTP/2, SSL cert paths, TLSv1.2+TLSv1.3, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `/etc/nginx/sites-available/ci.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
  - **status.cluster.local**:
    - Template: `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local` (mode 0644)
      - Variables: `server_name=status.cluster.local`, `document_root=/opt/server/status`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/status.cluster.local.crt`, `key_file=/etc/ssl/private/status.cluster.local.key`
      - Rendered config: HTTP server block on port 80 with `return 301 https://...`, HTTPS server block on port 443 with HTTP/2, SSL cert paths, TLSv1.2+TLSv1.3, HSTS header (`max-age=31536000; includeSubDomains`), security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip, `try_files`, deny `.ht*` and `.git/.svn`, per-site access/error logs
      - Notifies: `service[nginx]` reload (delayed)
    - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `/etc/nginx/sites-available/status.cluster.local`
      - Notifies: `service[nginx]` reload (delayed)
- Deletes the default nginx site: `file[/etc/nginx/sites-enabled/default]` (action: delete)
  - Notifies: `service[nginx]` reload (delayed)
- Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no `depends` entries in `metadata.rb`)

**System package dependencies**:
- `nginx` — web server
- `fail2ban` — intrusion prevention / brute-force protection
- `ufw` — Uncomplicated Firewall (iptables front-end)
- `openssl` — TLS certificate generation
- `ca-certificates` — CA certificate bundle

**Service dependencies** (systemd services managed):
- `nginx` — enabled, started; reloaded on any config/cert/site change
- `fail2ban` — enabled, started; restarted on jail.local change
- `ssh` (sshd) — action :nothing; restarted only when sshd_config is modified

## Credentials

**Detection Summary**: 0 credentials detected across 6 files.

**Source**:
- **Provider**: None detected
- **URL**: N/A
- **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates generated are self-signed with a hardcoded placeholder subject (`/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`) — this is intentional for development/internal use and does not constitute a secret. No data bags, Chef Vault, CyberArk, or environment variable secrets are referenced anywhere in the cookbook.

> **Note for Solutions Architect**: If this cookbook is being migrated for a production environment, the self-signed certificate generation should be replaced with a proper PKI solution (e.g., Let's Encrypt via `community.crypto.acme_certificate`, an internal CA, or pre-provisioned certificates stored in AAP Credential Manager / HashiCorp Vault). The `admin@example.com` email and `Example Org` subject fields in the openssl command are placeholders and must be updated.

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
| `/opt/server/test/index.html` | Static file | Deployed from cookbook files |
| `/opt/server/ci/index.html` | Static file | Deployed from cookbook files |
| `/opt/server/status/index.html` | Static file | Deployed from cookbook files |
| `/etc/ssl/certs/test.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/test.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/ci.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/ci.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/ssl/certs/status.cluster.local.crt` | TLS cert | Self-signed, RSA 2048, 365 days |
| `/etc/ssl/private/status.cluster.local.key` | TLS key | mode 640, owner root:ssl-cert |
| `/etc/fail2ban/jail.local` | Config | Rendered from `fail2ban.jail.local.erb` |
| `/etc/sysctl.d/99-security.conf` | Config | Rendered from `sysctl-security.conf.erb` |
| `/etc/ssh/sshd_config` | Config | `PermitRootLogin no`, `PasswordAuthentication no` |

**Service endpoints to check**:
- Ports listening: **80** (nginx HTTP, all 3 sites — redirect only), **443** (nginx HTTPS, all 3 sites)
- Unix sockets: None
- Network interfaces: All interfaces (nginx listens on `0.0.0.0:80` and `0.0.0.0:443`)

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

## Pre-flight Checks

```bash
# ============================================================
# 1. SERVICE STATUS
# ============================================================
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx        # Expected: enabled
systemctl is-enabled fail2ban     # Expected: enabled
ps aux | grep nginx | grep -v grep  # Expected: master + worker processes

# ============================================================
# 2. NGINX CONFIGURATION SYNTAX
# ============================================================
nginx -t
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful

# Verify global config key settings
grep -E 'worker_processes|worker_connections|keepalive_timeout|server_tokens' \
  /etc/nginx/nginx.conf /etc/nginx/conf.d/security.conf
# Expected: worker_processes auto, worker_connections 768, keepalive_timeout 65, server_tokens off

# Verify security.conf rate limiting and buffer settings
grep -E 'limit_req_zone|client_body_buffer_size|client_max_body_size|ssl_protocols' \
  /etc/nginx/conf.d/security.conf
# Expected: login zone 10r/m, api zone 30r/m, client_body_buffer_size 1K, TLSv1.2 TLSv1.3

# ============================================================
# 3. SITE CONFIGS - verify each site individually
# ============================================================

# Site: test.cluster.local
test -f /etc/nginx/sites-available/test.cluster.local && echo "EXISTS" || echo "MISSING"
readlink /etc/nginx/sites-enabled/test.cluster.local
# Expected: /etc/nginx/sites-available/test.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/test.cluster.local
# Expected: server_name test.cluster.local, listen 443 ssl http2, root /opt/server/test
grep 'return 301' /etc/nginx/sites-available/test.cluster.local
# Expected: return 301 https://$server_name$request_uri

# Site: ci.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local && echo "EXISTS" || echo "MISSING"
readlink /etc/nginx/sites-enabled/ci.cluster.local
# Expected: /etc/nginx/sites-available/ci.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/ci.cluster.local
# Expected: server_name ci.cluster.local, listen 443 ssl http2, root /opt/server/ci
grep 'return 301' /etc/nginx/sites-available/ci.cluster.local
# Expected: return 301 https://$server_name$request_uri

# Site: status.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local && echo "EXISTS" || echo "MISSING"
readlink /etc/nginx/sites-enabled/status.cluster.local
# Expected: /etc/nginx/sites-available/status.cluster.local
grep -E 'server_name|ssl_certificate|root|listen' /etc/nginx/sites-available/status.cluster.local
# Expected: server_name status.cluster.local, listen 443 ssl http2, root /opt/server/status
grep 'return 301' /etc/nginx/sites-available/status.cluster.local
# Expected: return 301 https://$server_name$request_uri

# Default site must be removed
test ! -f /etc/nginx/sites-enabled/default && echo "DEFAULT REMOVED OK" || echo "ERROR: default site still present"

# ============================================================
# 4. DOCUMENT ROOTS AND STATIC FILES
# ============================================================

# test.cluster.local document root
ls -lah /opt/server/test/
stat /opt/server/test/index.html
# Expected: owner www-data:www-data, mode 0644

# ci.cluster.local document root
ls -lah /opt/server/ci/
stat /opt/server/ci/index.html
# Expected: owner www-data:www-data, mode 0644

# status.cluster.local document root
ls -lah /opt/server/status/
stat /opt/server/status/index.html
# Expected: owner www-data:www-data, mode 0644

# ============================================================
# 5. SSL CERTIFICATES - verify each site individually
# ============================================================

# test.cluster.local certificate
test -f /etc/ssl/certs/test.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/test.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=test.cluster.local, notAfter ~365 days from issue
stat /etc/ssl/private/test.cluster.local.key | grep -E 'Access|Uid|Gid'
# Expected: mode 0640, owner root, group ssl-cert
openssl verify -CAfile /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/test.cluster.local.crt
# Expected: /etc/ssl/certs/test.cluster.local.crt: OK (self-signed)

# ci.cluster.local certificate
test -f /etc/ssl/certs/ci.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/ci.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=ci.cluster.local, notAfter ~365 days from issue
stat /etc/ssl/private/ci.cluster.local.key | grep -E 'Access|Uid|Gid'
# Expected: mode 0640, owner root, group ssl-cert
openssl verify -CAfile /etc/ssl/certs/ci.cluster.local.crt /etc/ssl/certs/ci.cluster.local.crt
# Expected: /etc/ssl/certs/ci.cluster.local.crt: OK (self-signed)

# status.cluster.local certificate
test -f /etc/ssl/certs/status.cluster.local.crt && echo "CERT EXISTS" || echo "CERT MISSING"
test -f /etc/ssl/private/status.cluster.local.key && echo "KEY EXISTS" || echo "KEY MISSING"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -issuer
# Expected: CN=status.cluster.local, notAfter ~365 days from issue
stat /etc/ssl/private/status.cluster.local.key | grep -E 'Access|Uid|Gid'
# Expected: mode 0640, owner root, group ssl-cert
openssl verify -CAfile /etc/ssl/certs/status.cluster.local.crt /etc/ssl/certs/status.cluster.local.crt
# Expected: /etc/ssl/certs/status.cluster.local.crt: OK (self-signed)

# SSL directory permissions
stat /etc/ssl/certs | grep -E 'Access'
# Expected: mode 0755, owner root:root
stat /etc/ssl/private | grep -E 'Access'
# Expected: mode 0710, owner root:ssl-cert

# ============================================================
# 6. HTTP CONNECTIVITY - test each site individually
# ============================================================

# test.cluster.local - HTTP should redirect to HTTPS
curl -v -o /dev/null -s -w "%{http_code}" http://test.cluster.local/
# Expected: 301

# test.cluster.local - HTTPS should return 200
curl -k -o /dev/null -s -w "%{http_code}" https://test.cluster.local/
# Expected: 200

# ci.cluster.local - HTTP should redirect to HTTPS
curl -v -o /dev/null -s -w "%{http_code}" http://ci.cluster.local/
# Expected: 301

# ci.cluster.local - HTTPS should return 200
curl -k -o /dev/null -s