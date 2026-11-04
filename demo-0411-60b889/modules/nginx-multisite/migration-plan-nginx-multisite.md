---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and enables Nginx, applies host and Nginx security controls, deploys static content for three SSL-configured virtual hosts, and configures HTTP-to-HTTPS redirects. The configured sites are **test.cluster.local**, **ci.cluster.local**, and **status.cluster.local**. Nginx serves content from `/opt/server/test`, `/opt/server/ci`, and `/opt/server/status` on ports 80 and 443. Due to the validated Chef condition in `ssl.rb`, the cookbook does **not** generate certificates for these sites when `ssl_enabled` is `true`; the required certificate and key files must therefore exist before Nginx is configured and reloaded.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP 80 redirects permanently to TCP 443
  - Key Config: Nginx vhost `/etc/nginx/sites-available/test.cluster.local`; enabled through `/etc/nginx/sites-enabled/test.cluster.local`; certificate `/etc/ssl/certs/test.cluster.local.crt`; key `/etc/ssl/private/test.cluster.local.key`; access log `/var/log/nginx/test.cluster.local_access.log`; error log `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP 80 redirects permanently to TCP 443
  - Key Config: Nginx vhost `/etc/nginx/sites-available/ci.cluster.local`; enabled through `/etc/nginx/sites-enabled/ci.cluster.local`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; key `/etc/ssl/private/ci.cluster.local.key`; access log `/var/log/nginx/ci.cluster.local_access.log`; error log `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP 80 redirects permanently to TCP 443
  - Key Config: Nginx vhost `/etc/nginx/sites-available/status.cluster.local`; enabled through `/etc/nginx/sites-enabled/status.cluster.local`; certificate `/etc/ssl/certs/status.cluster.local.crt`; key `/etc/ssl/private/status.cluster.local.key`; access log `/var/log/nginx/status.cluster.local_access.log`; error log `/var/log/nginx/status.cluster.local_error.log`.

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
```

No custom resource provider is executed by the supplied execution tree.

**Templates:**
```text
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/sysctl-security.conf.erb
templates/default/site.conf.erb
```

**Attributes:**
```text
attributes/default.rb
```

**Files:**

No static source files are listed in the supplied cookbook directory listing. The `cookbook_file` resources reference `test/index.html`, `ci/index.html`, and `status/index.html`, but those source files were not supplied. Obtain their content separately before implementing the Ansible equivalent.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes recipes in this order:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Uses four `include_recipe` resources.
   - The migration must preserve this ordering: security configuration, Nginx installation and content deployment, SSL directory handling, then virtual-host configuration.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`, mode `0644`.
     - Configures `bantime=3600`, `findtime=600`, and `maxretry=3`.
     - Enables the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
     - Changes notify a delayed Fail2ban restart.
   - Configures UFW through guarded commands:
     - `ufw --force default deny`
     - `ufw allow ssh`
     - `ufw allow http`
     - `ufw allow https`
     - `ufw --force enable`
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`, mode `0644`.
     - Configures reverse-path filtering, redirect and source-route restrictions, Martian logging, ICMP restrictions, IPv6 disablement, SYN cookies, and TCP SYN retry/backlog settings.
     - Changes notify delayed execution of `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Because `security.ssh.disable_root=true`, sets `PermitRootLogin no` in `/etc/ssh/sshd_config`; changes notify a delayed restart of `ssh`.
   - Because `security.ssh.password_auth=false`, sets `PasswordAuthentication no` in `/etc/ssh/sshd_config`; changes notify a delayed restart of `ssh`.
   - The `security.fail2ban.enabled` and `security.ufw.enabled` attributes do not conditionally control recipe execution; Fail2ban and UFW are always installed and configured.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`, mode `0644`.
     - Configures user `www-data`, `worker_processes auto`, and `worker_connections 768`.
     - Configures global logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`.
     - Includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
     - Changes notify a delayed Nginx reload.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`, mode `0644`.
     - Configures `server_tokens off`.
     - Configures rate-limit zones `login` at `10r/m` and `api` at `30r/m`, both with `10m` shared memory.
     - Configures request and header buffer limits, 10-second timeouts, and TLS protocol/cipher defaults.
     - Changes notify a delayed Nginx reload.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`.
   - Deploys `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`.
   - Deploys `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`.
   - Deploys `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - The three homepage source files are absent from the supplied cookbook listing and must be obtained before migration. Do not substitute arbitrary content.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner/group `root:ssl-cert` and mode `0710`.
   - Evaluates certificate-generation resources for **test.cluster.local**, **ci.cluster.local**, and **status.cluster.local**.
   - The validated Chef execution condition is `unless config['ssl_enabled']`.
   - Because all three configured sites have `ssl_enabled: true`, certificate-generation resources do **not** execute for:
     - **test.cluster.local**: `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` are not generated by this cookbook.
     - **ci.cluster.local**: `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` are not generated by this cookbook.
     - **status.cluster.local**: `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` are not generated by this cookbook.
   - The vhost configuration still references these certificate and key paths. Certificates and private keys must therefore be provisioned externally before Nginx configuration validation and reload.
   - If the Chef conditional was intended to generate certificates when SSL is enabled, correct and validate the Chef source before treating certificate generation as migration behavior.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`, mode `0644`.
     - Uses `server_name test.cluster.local`, document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`, mode `0644`.
     - Uses `server_name ci.cluster.local`, document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`, mode `0644`.
     - Uses `server_name status.cluster.local`, document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Changes to vhost files, enabled-site symlinks, or default-site removal notify a delayed Nginx reload.
   - Each vhost:
     - Listens on port 80 and returns an HTTP 301 redirect to `https://$server_name$request_uri`.
     - Listens on port 443 with `ssl http2`.
     - Enables TLS 1.2 and TLS 1.3.
     - Uses the named site certificate and private key.
     - Configures HSTS with `max-age=31536000; includeSubDomains`.
     - Configures `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, and `Content-Security-Policy`.
     - Serves static files with `try_files $uri $uri/ =404`.
     - Denies `.htaccess`, `.git`, and `.svn` paths.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: enabled and started; reloads after valid global configuration, security configuration, vhost configuration, enabled-site symlink, or default-site changes.
- `fail2ban`: enabled and started; restarts after `/etc/fail2ban/jail.local` changes.
- `ssh`: restarts only when `PermitRootLogin` or `PasswordAuthentication` changes.

**Platform dependencies**:
- Metadata declares Ubuntu `>= 18.04` and CentOS `>= 7.0`.
- The configured Nginx paths, `www-data` account, UFW package, and `ssh` service name are Debian/Ubuntu-oriented.
- For Red Hat-family hosts, verify and adapt package names, Nginx paths, web-service account, firewall implementation, and SSH service name.

## Credentials

**Detection Summary**: 0 credentials detected across the executed recipes, templates, and default attributes.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

No credentials or secrets were detected in this cookbook. The TLS private keys referenced by the virtual hosts are sensitive artifacts, but the validated Chef execution path does not generate or source them. Provision them through the target organization’s approved certificate and secret-management process.

## Checks for the Migration

**Files to verify**:
```text
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/opt/server/test/index.html
/opt/server/ci/index.html
/opt/server/status/index.html
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/private/status.cluster.local.key
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/nginx/test.cluster.local_access.log
/var/log/nginx/test.cluster.local_error.log
/var/log/nginx/ci.cluster.local_access.log
/var/log/nginx/ci.cluster.local_error.log
/var/log/nginx/status.cluster.local_access.log
/var/log/nginx/status.cluster.local_error.log
/var/log/auth.log
```

**Service endpoints to check**:
- **test.cluster.local HTTP**: TCP port `80`; returns HTTP `301` to `https://test.cluster.local/`.
- **test.cluster.local HTTPS**: TCP port `443`; serves static content with the externally provisioned certificate.
- **ci.cluster.local HTTP**: TCP port `80`; returns HTTP `301` to `https://ci.cluster.local/`.
- **ci.cluster.local HTTPS**: TCP port `443`; serves static content with the externally provisioned certificate.
- **status.cluster.local HTTP**: TCP port `80`; returns HTTP `301` to `https://status.cluster.local/`.
- **status.cluster.local HTTPS**: TCP port `443`; serves static content with the externally provisioned certificate.
- **SSH**: TCP port `22`; allowed by UFW, with root login and password authentication disabled.
- **Fail2ban**: No externally exposed service port.
- **Unix sockets**: No application Unix socket is configured.

**Templates rendered**:
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: renders **1 time**.
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: renders **1 time**.
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: renders **1 time**.
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: renders **1 time**.
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: renders **1 time**.
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: renders **1 time**.
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: renders **1 time**.

`site.conf.erb` renders **3 times total**.

## Pre-flight checks:
```bash
# Installed packages
dpkg-query -W -f='${Package} ${Version}\n' nginx fail2ban ufw openssl ca-certificates

# Service state
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status nginx --no-pager

systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status fail2ban --no-pager

systemctl is-active ssh
systemctl status ssh --no-pager

# Required certificate and private-key artifacts must be provisioned before nginx -t.
# The validated Chef ssl.rb condition does not generate them when ssl_enabled=true.
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key

# Nginx syntax must succeed before any reload
nginx -t

# Nginx global configuration
grep -Fx 'user www-data;' /etc/nginx/nginx.conf
grep -Fx 'worker_processes auto;' /etc/nginx/nginx.conf
grep -Fx 'worker_connections 768;' /etc/nginx/nginx.conf
grep -Fx 'include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
grep -Fx 'include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf

# Nginx security configuration
grep -Fx 'server_tokens off;' /etc/nginx/conf.d/security.conf
grep -Fx 'limit_req_zone $binary_remote_addr zone=login:10m rate=10r/m;' /etc/nginx/conf.d/security.conf
grep -Fx 'limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;' /etc/nginx/conf.d/security.conf
grep -Fx 'ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf

# Firewall policy and allowed services
ufw status verbose
ufw status | grep -F '22/tcp'
ufw status | grep -F '80/tcp'
ufw status | grep -F '443/tcp'

# SSH hardening
grep -Ex '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -Ex '^PasswordAuthentication no$' /etc/ssh/sshd_config

# Security sysctl settings
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies

# Fail2ban configuration and active jails
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
grep -Fx 'bantime = 3600' /etc/fail2ban/jail.local
grep -Fx 'maxretry = 3' /etc/fail2ban/jail.local

# test.cluster.local certificate, vhost, content, redirect, and HTTPS response
stat -c '%U:%G %a %n' /etc/ssl/certs/test.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep -F 'CN = test.cluster.local'
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local | grep -Fx '/etc/nginx/sites-available/test.cluster.local'
test -d /opt/server/test
test -f /opt/server/test/index.html
stat -c '%U:%G %a %n' /opt/server/test /opt/server/test/index.html
grep -Fx 'server_name test.cluster.local;' /etc/nginx/sites-available/test.cluster.local
grep -Fx 'root /opt/server/test;' /etc/nginx/sites-available/test.cluster.local
grep -Fx 'ssl_certificate /etc/ssl/certs/test.cluster.local.crt;' /etc/nginx/sites-available/test.cluster.local
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -E '^HTTP/.* 301'
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -Fi 'location: https://test.cluster.local/'
curl -skI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E '^HTTP/.* 200'

# ci.cluster.local certificate, vhost, content, redirect, and HTTPS response
stat -c '%U:%G %a %n' /etc/ssl/certs/ci.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep -F 'CN = ci.cluster.local'
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local | grep -Fx '/etc/nginx/sites-available/ci.cluster.local'
test -d /opt/server/ci
test -f /opt/server/ci/index.html
stat -c '%U:%G %a %n' /opt/server/ci /opt/server/ci/index.html
grep -Fx 'server_name ci.cluster.local;' /etc/nginx/sites-available/ci.cluster.local
grep -Fx 'root /opt/server/ci;' /etc/nginx/sites-available/ci.cluster.local
grep -Fx 'ssl_certificate /etc/ssl/certs/ci.cluster.local.crt;' /etc/nginx/sites-available/ci.cluster.local
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -E '^HTTP/.* 301'
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -Fi 'location: https://ci.cluster.local/'
curl -skI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E '^HTTP/.* 200'

# status.cluster.local certificate, vhost, content, redirect, and HTTPS response
stat -c '%U:%G %a %n' /etc/ssl/certs/status.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep -F 'CN = status.cluster.local'
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local | grep -Fx '/etc/nginx/sites-available/status.cluster.local'
test -d /opt/server/status
test -f /opt/server/status/index.html
stat -c '%U:%G %a %n' /opt/server/status /opt/server/status/index.html
grep -Fx 'server_name status.cluster.local;' /etc/nginx/sites-available/status.cluster.local
grep -Fx 'root /opt/server/status;' /etc/nginx/sites-available/status.cluster.local
grep -Fx 'ssl_certificate /etc/ssl/certs/status.cluster.local.crt;' /etc/nginx/sites-available/status.cluster.local
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -E '^HTTP/.* 301'
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -Fi 'location: https://status.cluster.local/'
curl -skI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E '^HTTP/.* 200'

# Packaged default vhost must be absent
test ! -e /etc/nginx/sites-enabled/default

# Listening ports
ss -tlnp | grep -E ':(80|443)\b'
lsof -nP -iTCP:80 -sTCP:LISTEN
lsof -nP -iTCP:443 -sTCP:LISTEN

# Global and site-specific logs
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log
tail -n 50 /var/log/auth.log
```