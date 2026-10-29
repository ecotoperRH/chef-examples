---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and enables NGINX, applies host and NGINX security hardening, generates development self-signed TLS certificates, and publishes three SSL-enabled static virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. Each site redirects HTTP port 80 to HTTPS port 443 and serves static content from a distinct `/opt/server/...` document root.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80` redirects to HTTPS `443`; HTTPS uses HTTP/2.
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; static page `/opt/server/test/index.html`; `ssl_enabled: true`.

- **ci.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80` redirects to HTTPS `443`; HTTPS uses HTTP/2.
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; static page `/opt/server/ci/index.html`; `ssl_enabled: true`.

- **status.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80` redirects to HTTPS `443`; HTTPS uses HTTP/2.
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; static page `/opt/server/status/index.html`; `ssl_enabled: true`.

Additional configured settings:

- Certificate directory: `/etc/ssl/certs`
- Private-key directory: `/etc/ssl/private`
- Fail2ban enabled attribute: `node['security']['fail2ban']['enabled'] = true`
- UFW enabled attribute: `node['security']['ufw']['enabled'] = true`
- SSH root login disabled: `node['security']['ssh']['disable_root'] = true`
- SSH password authentication disabled: `node['security']['ssh']['password_auth'] = false`

The `fail2ban.enabled` and `ufw.enabled` attributes are defined but are not used as Chef recipe conditions. A behaviorally equivalent migration must configure Fail2ban and UFW unconditionally unless intentionally changing the original behavior.

## File Structure

**Recipes:**
```text
cookbooks/nginx-multisite/recipes/default.rb
cookbooks/nginx-multisite/recipes/security.rb
cookbooks/nginx-multisite/recipes/nginx.rb
cookbooks/nginx-multisite/recipes/ssl.rb
cookbooks/nginx-multisite/recipes/sites.rb
```

**Providers:**
```text
```

No provider file is used in the supplied execution tree. Although the structural scan identifies `resources/lineinfile.rb`, no recipe invokes that custom resource, so it is not part of the executed migration scope.

**Templates:**
```text
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
```

**Attributes:**
```text
cookbooks/nginx-multisite/attributes/default.rb
```

**Files:**

No static source files are present in the supplied directory listing. However, the executed `cookbook_file` resources expect these source names:

- `test/index.html` → `/opt/server/test/index.html`
- `ci/index.html` → `/opt/server/ci/index.html`
- `status/index.html` → `/opt/server/status/index.html`

Obtain the actual HTML files before implementing the migration. Do not substitute invented page content because the Chef source content was not supplied.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes recipes in this exact order:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Resources used: `include_recipe` (4).

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs packages `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`, mode `0644`.
     - Enables jails `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`.
     - Sets `bantime = 3600`, `findtime = 600`, and default `maxretry = 3`.
     - Sets `nginx-limit-req` `maxretry = 10`.
     - Sets `nginx-botsearch` `maxretry = 2`.
     - Changes schedule a delayed restart of `fail2ban`.
   - Configures UFW idempotently:
     - Sets default policy to deny unless `Default: deny` is already reported.
     - Allows SSH unless port `22/tcp` is already reported.
     - Allows HTTP unless port `80/tcp` is already reported.
     - Allows HTTPS unless port `443/tcp` is already reported.
     - Enables UFW unless `Status: active` is already reported.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`, mode `0644`.
     - Applies reverse-path filtering, disables IPv4 and IPv6 redirects and source routing, enables Martian logging, disables ICMP echo and broadcast pings, disables IPv6, and enables TCP SYN-cookie protections.
     - Changes schedule delayed execution of `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because SSH root login is disabled.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because SSH password authentication is disabled.
   - SSH configuration changes schedule a delayed restart of service `ssh`.
   - Declares `ssh` only as a delayed-notification target.
   - Resources used: package (1), service (2), template (2), execute (8).

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs package `nginx`.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`, mode `0644`.
     - Sets user `www-data`, `worker_processes auto`, PID `/run/nginx.pid`, and `worker_connections 768`.
     - Configures global access and error logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`.
     - Includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
     - Changes schedule a delayed NGINX reload.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`, mode `0644`.
     - Sets `server_tokens off`.
     - Configures request-rate zones `login` at `10r/m` and `api` at `30r/m`, each with a `10m` shared-memory zone.
     - Sets client and header buffers to `1K`, maximum request body size to `1k`, and client-body, client-header, and send timeouts to 10 seconds.
     - Allows TLS 1.2 and TLS 1.3 only.
     - Changes schedule a delayed NGINX reload.
   - Enables and starts NGINX.
   - Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Resources used: package (1), template (2), service (1), directory (3), cookbook_file (3).

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs packages `openssl` and `ca-certificates`.
   - Creates group `ssl-cert`.
   - Creates `/etc/ssl/certs` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner/group `root:ssl-cert` and mode `0710`.
   - Generates a 365-day self-signed X.509 certificate and 2048-bit RSA private key for **test.cluster.local** when both files do not already exist:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Subject CN: `test.cluster.local`
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
     - Generation schedules a delayed NGINX reload.
   - Generates a 365-day self-signed X.509 certificate and 2048-bit RSA private key for **ci.cluster.local** when both files do not already exist:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Subject CN: `ci.cluster.local`
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
     - Generation schedules a delayed NGINX reload.
   - Generates a 365-day self-signed X.509 certificate and 2048-bit RSA private key for **status.cluster.local** when both files do not already exist:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Subject CN: `status.cluster.local`
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
     - Generation schedules a delayed NGINX reload.
   - Resources used: package (1), group (1), directory (2), execute (3).

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
   - Each site configuration creates an HTTP virtual host on port 80 that redirects with HTTP 301 to HTTPS, plus an HTTPS virtual host on port 443 with SSL and HTTP/2.
   - Each site configuration sets HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, and Content Security Policy headers.
   - Configures per-site logs:
     - `/var/log/nginx/test.cluster.local_access.log`
     - `/var/log/nginx/test.cluster.local_error.log`
     - `/var/log/nginx/ci.cluster.local_access.log`
     - `/var/log/nginx/ci.cluster.local_error.log`
     - `/var/log/nginx/status.cluster.local_access.log`
     - `/var/log/nginx/status.cluster.local_error.log`
   - Removes `/etc/nginx/sites-enabled/default`.
   - Changes to site templates, symlinks, or default-site removal schedule a delayed NGINX reload.
   - Resources used: template (3), link (3), file (1).

## Dependencies

**External cookbook dependencies**: None declared in the supplied `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

No package versions are pinned by the Chef cookbook.

**Service dependencies**:
- `nginx`: enabled and started.
- `fail2ban`: enabled and started.
- `ssh`: restarted only when SSH root-login or password-authentication configuration changes.

The cookbook metadata claims Ubuntu and CentOS support, but implementation details are Ubuntu/Debian-oriented: service name `ssh`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and Fail2ban SSH log path `/var/log/auth.log`. Validate CentOS separately because it commonly uses service `sshd`, `/var/log/secure` or journald, and different NGINX site-directory conventions.

## Credentials

**Detection Summary**: 0 externally supplied credentials detected across the executed recipes and templates.

**Source**:
  - **Provider**: None detected
  - **URL**: Not applicable
  - **Path**: Not applicable

### Development TLS Private Keys
- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Generated locally by `openssl`; not retrieved from a secret store.
- **Usage context**: Private keys for development self-signed TLS certificates used by the corresponding NGINX virtual hosts.

Treat generated private keys as sensitive artifacts. Preserve directory mode `0710`, key ownership `root:ssl-cert`, and key mode `0640`. For production, provide CA-issued certificates and private keys through approved credential injection or external secret management rather than generating self-signed certificates. The hardcoded `admin@example.com` certificate-subject value is contact metadata and not an authentication credential.

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
/var/log/nginx/test.cluster.local_access.log
/var/log/nginx/test.cluster.local_error.log
/var/log/nginx/ci.cluster.local_access.log
/var/log/nginx/ci.cluster.local_error.log
/var/log/nginx/status.cluster.local_access.log
/var/log/nginx/status.cluster.local_error.log
```

**Service endpoints to check**:
- `test.cluster.local`: HTTP `80`; HTTPS `443`.
- `ci.cluster.local`: HTTP `80`; HTTPS `443`.
- `status.cluster.local`: HTTP `80`; HTTPS `443`.
- No Unix socket is configured.
- NGINX has no explicitly configured bind address.

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render.

## Pre-flight checks:
```bash
# Package and service status
dpkg-query -W nginx fail2ban ufw openssl ca-certificates
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
nginx -t
fail2ban-client ping
ufw status verbose

# Validate NGINX global configuration and security configuration
grep -E 'worker_processes auto|worker_connections 768|access_log /var/log/nginx/access.log|error_log /var/log/nginx/error.log' /etc/nginx/nginx.conf
grep -E 'server_tokens off|rate=10r/m|rate=30r/m|ssl_protocols TLSv1.2 TLSv1.3' /etc/nginx/conf.d/security.conf

# Validate UFW and host security configuration
ufw status | grep -F 'Default: deny'
ufw status | grep -E '22/tcp|OpenSSH'
ufw status | grep -E '80/tcp|80'
ufw status | grep -E '443/tcp|443'
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
systemctl status ssh --no-pager || systemctl status sshd --no-pager
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies

# Validate test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
stat -c '%U:%G %a %n' /opt/server/test /opt/server/test/index.html
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -E 'server_name test\.cluster\.local|listen 80;|listen 443 ssl http2;|root /opt/server/test;|ssl_certificate /etc/ssl/certs/test\.cluster\.local\.crt;|ssl_certificate_key /etc/ssl/private/test\.cluster\.local\.key;' /etc/nginx/sites-available/test.cluster.local
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep -F 'CN = test.cluster.local'
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -E '^HTTP/.* 301|^Location: https://test\.cluster\.local/'
curl -skI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E '^HTTP/.* 200|^Strict-Transport-Security:'

# Validate ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
stat -c '%U:%G %a %n' /opt/server/ci /opt/server/ci/index.html
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -E 'server_name ci\.cluster\.local|listen 80;|listen 443 ssl http2;|root /opt/server/ci;|ssl_certificate /etc/ssl/certs/ci\.cluster\.local\.crt;|ssl_certificate_key /etc/ssl/private/ci\.cluster\.local\.key;' /etc/nginx/sites-available/ci.cluster.local
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep -F 'CN = ci.cluster.local'
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -E '^HTTP/.* 301|^Location: https://ci\.cluster\.local/'
curl -skI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E '^HTTP/.* 200|^Strict-Transport-Security:'

# Validate status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
stat -c '%U:%G %a %n' /opt/server/status /opt/server/status/index.html
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -E 'server_name status\.cluster\.local|listen 80;|listen 443 ssl http2;|root /opt/server/status;|ssl_certificate /etc/ssl/certs/status\.cluster\.local\.crt;|ssl_certificate_key /etc/ssl/private/status\.cluster\.local\.key;' /etc/nginx/sites-available/status.cluster.local
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep -F 'CN = status.cluster.local'
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -E '^HTTP/.* 301|^Location: https://status\.cluster\.local/'
curl -skI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E '^HTTP/.* 200|^Strict-Transport-Security:'

# Validate default-site removal, logs, and listening ports
test ! -e /etc/nginx/sites-enabled/default
test -f /var/log/nginx/test.cluster.local_access.log
test -f /var/log/nginx/test.cluster.local_error.log
test -f /var/log/nginx/ci.cluster.local_access.log
test -f /var/log/nginx/ci.cluster.local_error.log
test -f /var/log/nginx/status.cluster.local_access.log
test -f /var/log/nginx/status.cluster.local_error.log
ss -tlnp | grep -E ':(80|443)\b'
```