---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a hardened web-server cookbook that installs NGINX, Fail2ban, UFW, OpenSSL, and CA certificates. It configures three SSL-enabled static virtual hosts—**test.cluster.local**, **ci.cluster.local**, and **status.cluster.local**—with separate `/opt/server/...` document roots, HTTP-to-HTTPS redirects on port 80, HTTPS on port 443, and self-signed 365-day RSA-2048 certificates. It also applies NGINX, Fail2ban, UFW, SSH, and kernel-security hardening.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/test`; static content at `/opt/server/test/index.html`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS; HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; access log `/var/log/nginx/test.cluster.local_access.log`; error log `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/ci`; static content at `/opt/server/ci/index.html`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS; HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; access log `/var/log/nginx/ci.cluster.local_access.log`; error log `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/status`; static content at `/opt/server/status/index.html`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS; HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; access log `/var/log/nginx/status.cluster.local_access.log`; error log `/var/log/nginx/status.cluster.local_error.log`

Additional configured security values:
- `node['security']['fail2ban']['enabled'] = true`
- `node['security']['ufw']['enabled'] = true`
- `node['security']['ssh']['disable_root'] = true`
- `node['security']['ssh']['password_auth'] = false`

The Fail2ban and UFW `enabled` attributes are defined but are not used as conditions in the executed recipes. Preserve Chef behavior by installing and configuring Fail2ban and UFW unconditionally unless the target design intentionally changes that behavior.

## File Structure

**Recipes:**
```text
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```

**Providers:**
```text
None. No custom resource provider is used in the execution flow.
```

**Templates:**
```text
None listed here: per the supplied execution-tree rule, this File Structure section contains only executed .rb files. All rendered ERB templates are documented in “Module Explanation” and “Templates rendered.”
```

**Attributes:**
```text
attributes/default.rb
```

**Files:**
```text
None listed in the supplied directory listing. The cookbook does reference dynamically named cookbook-file sources for three index pages; their source files were not supplied in the execution tree or directory listing.
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Resources used: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Restarts `fail2ban` through a delayed notification when `/etc/fail2ban/jail.local` changes.
   - Configures UFW idempotently:
     - Sets the default incoming policy to deny with `ufw --force default deny`.
     - Allows SSH with `ufw allow ssh`.
     - Allows HTTP with `ufw allow http`.
     - Allows HTTPS with `ufw allow https`.
     - Enables UFW with `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies `/etc/sysctl.d/99-security.conf` through delayed `sysctl -p /etc/sysctl.d/99-security.conf` when the template changes.
   - Configures kernel hardening including reverse-path filtering, disabled IPv4 and IPv6 redirects/source routing, martian logging, disabled ICMP echo requests and broadcast pings, disabled IPv6, SYN cookies, `net.ipv4.tcp_max_syn_backlog = 2048`, `net.ipv4.tcp_synack_retries = 2`, and `net.ipv4.tcp_syn_retries = 5`.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because `security.ssh.disable_root` is `true`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `security.ssh.password_auth` is `false`.
   - Restarts the `ssh` service through a delayed notification only when either SSH setting changes.
   - Resources used: one package resource installing two packages, two service resources, two templates, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures NGINX with worker user `www-data`, automatic worker-process selection, PID `/run/nginx.pid`, `worker_connections 768`, global access log `/var/log/nginx/access.log`, global error log `/var/log/nginx/error.log`, gzip, `/etc/nginx/conf.d/*.conf`, and `/etc/nginx/sites-enabled/*`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures `server_tokens off`, rate-limit zones `login` at `10r/m` and `api` at `30r/m`, 1K client/body/header buffer limits, `client_max_body_size 1k`, 10-second client body/header/send timeouts, SSL session cache `shared:SSL:10m`, SSL session timeout `10m`, TLS 1.2/TLS 1.3, and an explicit cipher suite with server cipher preference.
   - Enables and starts the `nginx` service. NGINX configuration changes schedule a delayed reload.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`; copies `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`; copies `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`; copies `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Resources used: one package, two templates, one service, three directories, and three cookbook files.
   - The source files `test/index.html`, `ci/index.html`, and `status/index.html` are referenced but were not supplied in the directory listing. The migration must obtain and deploy equivalent content.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner/group `root:ssl-cert` and mode `0710`.
   - Generates self-signed X.509 certificates only when a site certificate/key pair does not already exist.
   - Iterations:
     - **test.cluster.local**: Generates `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key`; certificate is RSA-2048, self-signed, valid for 365 days, with CN `test.cluster.local`; private key ownership is `root:ssl-cert` and mode is `0640`.
     - **ci.cluster.local**: Generates `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key`; certificate is RSA-2048, self-signed, valid for 365 days, with CN `ci.cluster.local`; private key ownership is `root:ssl-cert` and mode is `0640`.
     - **status.cluster.local**: Generates `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key`; certificate is RSA-2048, self-signed, valid for 365 days, with CN `status.cluster.local`; private key ownership is `root:ssl-cert` and mode is `0640`.
   - Uses the certificate subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site-name>/emailAddress=admin@example.com`.
   - Certificate or key generation schedules a delayed NGINX reload.
   - Resources used: one package resource installing two packages, one group, two directories, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations:
     - **test.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`; uses server name `test.cluster.local`, document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`; creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`.
     - **ci.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`; uses server name `ci.cluster.local`, document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`; creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`.
     - **status.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`; uses server name `status.cluster.local`, document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`; creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Changed site templates, enabled-site links, or default-site removal schedule a delayed NGINX reload.
   - Each virtual host listens on port 80 and redirects to HTTPS with HTTP 301; listens on `443 ssl http2`; uses TLS 1.2/TLS 1.3; enables HSTS; sets `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, and Content Security Policy headers; enables gzip; uses `try_files $uri $uri/ =404`; blocks `.htaccess`, `.git`, and `.svn`; and writes site-specific access and error logs.
   - Resources used: three templates, three links, and one file resource.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: Enabled and started; reloaded after NGINX configuration changes, certificate/key generation, enabled-site link changes, or default-site removal.
- `fail2ban`: Enabled and started; restarted after `/etc/fail2ban/jail.local` changes.
- `ssh`: Restarted only after changes to `PermitRootLogin` or `PasswordAuthentication`.

Metadata declares support for Ubuntu `>= 18.04` and CentOS `>= 7.0`. However, the executed resources use UFW, the Debian-style `ssh` service name, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and the `www-data` user/group. Target Debian/Ubuntu explicitly or implement tested platform-specific mappings.

## Credentials

**Detection Summary**: 0 credentials detected across 6 analyzed Ruby files.

**Source**:
  - **Provider**: None detected
  - **URL**: Not applicable
  - **Path**: Not applicable

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive.

The cookbook generates sensitive TLS private keys locally:
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`

These keys are generated at convergence time rather than retrieved from a credential provider. Preserve `root:ssl-cert` ownership and mode `0640`, do not collect or log key content, and use an approved PKI or secret-management workflow for production certificates.

## Checks for the Migration

**Files to verify**:
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/ssl/certs`
- `/etc/ssl/private`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`
- `/opt/server/test`
- `/opt/server/test/index.html`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/var/log/nginx/test.cluster.local_access.log`
- `/var/log/nginx/test.cluster.local_error.log`
- `/opt/server/ci`
- `/opt/server/ci/index.html`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/var/log/nginx/ci.cluster.local_access.log`
- `/var/log/nginx/ci.cluster.local_error.log`
- `/opt/server/status`
- `/opt/server/status/index.html`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/var/log/nginx/status.cluster.local_access.log`
- `/var/log/nginx/status.cluster.local_error.log`
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`
- `/var/log/auth.log`

**Service endpoints to check**:
- **test.cluster.local**: TCP/80 returns HTTP 301 redirect to HTTPS; TCP/443 returns the static site over HTTPS.
- **ci.cluster.local**: TCP/80 returns HTTP 301 redirect to HTTPS; TCP/443 returns the static site over HTTPS.
- **status.cluster.local**: TCP/80 returns HTTP 301 redirect to HTTPS; TCP/443 returns the static site over HTTPS.
- NGINX listens on its default available interfaces; no explicit listen address is configured.
- No Unix sockets are configured.

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: **1 render**
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: **1 render**
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: **1 render**
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: **1 render**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: **1 render**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: **1 render**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: **1 render**

Total template renders: **7**

## Pre-flight checks:
```bash
# Package and service status
systemctl status nginx --no-pager
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status fail2ban --no-pager
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# NGINX and listening ports
nginx -t
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

# UFW firewall state and allowed ports
ufw status verbose
ufw status | grep '22/tcp'
ufw status | grep '80/tcp'
ufw status | grep '443/tcp'

# SSH hardening
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config

# Kernel hardening and Fail2ban
grep -E 'net.ipv4.conf.all.rp_filter = 1' /etc/sysctl.d/99-security.conf
grep -E 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.d/99-security.conf
grep -E 'net.ipv4.tcp_syncookies = 1' /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv6.conf.all.disable_ipv6
fail2ban-client ping
fail2ban-client status
test -f /etc/fail2ban/jail.local
grep -E '^\[sshd\]$' /etc/fail2ban/jail.local
grep -E '^\[nginx-http-auth\]$' /etc/fail2ban/jail.local
grep -E '^\[nginx-limit-req\]$' /etc/fail2ban/jail.local
grep -E '^\[nginx-botsearch\]$' /etc/fail2ban/jail.local

# Global NGINX security configuration
grep -E '^server_tokens off;' /etc/nginx/conf.d/security.conf
grep -E '^ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
grep -E '^client_max_body_size 1k;' /etc/nginx/conf.d/security.conf
grep -E '^limit_req_zone .*zone=login:10m rate=10r/m;' /etc/nginx/conf.d/security.conf
grep -E '^limit_req_zone .*zone=api:10m rate=30r/m;' /etc/nginx/conf.d/security.conf

# test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep 'CN = test.cluster.local'
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -E 'HTTP/.* 301'
curl -ksSI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E 'HTTP/.* 200'
curl -ksSI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -i 'strict-transport-security'
test -f /var/log/nginx/test.cluster.local_access.log
test -f /var/log/nginx/test.cluster.local_error.log

# ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep 'CN = ci.cluster.local'
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -E 'HTTP/.* 301'
curl -ksSI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E 'HTTP/.* 200'
curl -ksSI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -i 'strict-transport-security'
test -f /var/log/nginx/ci.cluster.local_access.log
test -f /var/log/nginx/ci.cluster.local_error.log

# status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep 'CN = status.cluster.local'
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -E 'HTTP/.* 301'
curl -ksSI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E 'HTTP/.* 200'
curl -ksSI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -i 'strict-transport-security'
test -f /var/log/nginx/status.cluster.local_access.log
test -f /var/log/nginx/status.cluster.local_error.log

# Default-site removal and log review
test ! -e /etc/nginx/sites-enabled/default
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
journalctl -u ssh -n 100 --no-pager
```