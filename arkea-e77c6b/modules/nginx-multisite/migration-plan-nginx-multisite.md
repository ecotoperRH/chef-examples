---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and hardens NGINX, Fail2ban, UFW, SSH, and kernel networking settings. It configures three SSL-enabled virtual hosts—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`—with self-signed 365-day RSA-2048 certificates, HTTP-to-HTTPS redirects, individual document roots, and site-specific NGINX logs. Preserve Chef execution order: security baseline, NGINX installation and content deployment, certificate generation, then virtual-host deployment and default-site removal.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` redirects to TCP `443`; no Unix socket.
  - Key Config: HTTP/2 on HTTPS; certificate `/etc/ssl/certs/test.cluster.local.crt`; key `/etc/ssl/private/test.cluster.local.key`; access log `/var/log/nginx/test.cluster.local_access.log`; error log `/var/log/nginx/test.cluster.local_error.log`; source content `test/index.html`.

- **ci.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` redirects to TCP `443`; no Unix socket.
  - Key Config: HTTP/2 on HTTPS; certificate `/etc/ssl/certs/ci.cluster.local.crt`; key `/etc/ssl/private/ci.cluster.local.key`; access log `/var/log/nginx/ci.cluster.local_access.log`; error log `/var/log/nginx/ci.cluster.local_error.log`; source content `ci/index.html`.

- **status.cluster.local**: SSL-enabled static web site.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` redirects to TCP `443`; no Unix socket.
  - Key Config: HTTP/2 on HTTPS; certificate `/etc/ssl/certs/status.cluster.local.crt`; key `/etc/ssl/private/status.cluster.local.key`; access log `/var/log/nginx/status.cluster.local_access.log`; error log `/var/log/nginx/status.cluster.local_error.log`; source content `status/index.html`.

## File Structure

```text
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
resources/lineinfile.rb
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/sysctl-security.conf.erb
templates/default/site.conf.erb
attributes/default.rb
```

No static content files are listed in the provided cookbook directory listing. However, `cookbooks/nginx-multisite/recipes/nginx.rb` references `test/index.html`, `ci/index.html`, and `status/index.html` through `cookbook_file` resources. Obtain the intended HTML content from the original cookbook artifact or another approved source before implementing equivalent Ansible `copy` tasks.

The custom resource `cookbooks/nginx-multisite/resources/lineinfile.rb` is not referenced by the executed recipe flow and is not part of this migration module.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Contains no direct system configuration resources.
   - Includes recipes in strict execution order:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Resources used: four `include_recipe` resources.
   - Implement Ansible task imports in this order:
     ```yaml
     - ansible.builtin.import_tasks: security.yml
     - ansible.builtin.import_tasks: nginx.yml
     - ansible.builtin.import_tasks: ssl.yml
     - ansible.builtin.import_tasks: sites.yml
     ```

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures Fail2ban global settings:
     - `bantime = 3600`
     - `findtime = 600`
     - `maxretry = 3`
     - `backend = auto`
   - Enables the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Applies UFW default-deny policy with `ufw --force default deny`.
   - Allows SSH with `ufw allow ssh`.
   - Allows HTTP with `ufw allow http`.
   - Allows HTTPS with `ufw allow https`.
   - Enables UFW with `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies kernel networking hardening, including reverse-path filtering, ICMP redirect and source-route rejection, martian logging, ICMP echo-request rejection, broadcast-ping rejection, TCP SYN-cookie protection, and IPv6 disablement.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['disable_root']` is `true`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['password_auth']` is `false`.
   - Delayed notifications:
     - Restart `fail2ban` when `/etc/fail2ban/jail.local` changes.
     - Run `sysctl -p /etc/sysctl.d/99-security.conf` when `/etc/sysctl.d/99-security.conf` changes.
     - Restart `ssh` when either SSH hardening setting changes.
   - Resources used: package, service, template, and execute resources.
   - Preserve the operational prerequisite that a non-root administrative account has working SSH public-key authentication and `sudo` access before disabling root login and password authentication.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Configures global NGINX settings:
     - User `www-data`.
     - `worker_processes auto`.
     - PID file `/run/nginx.pid`.
     - Includes `/etc/nginx/modules-enabled/*.conf`, `/etc/nginx/conf.d/*.conf`, and `/etc/nginx/sites-enabled/*`.
     - `worker_connections 768`.
     - Enables `sendfile`, `tcp_nopush`, `tcp_nodelay`, and gzip.
     - `keepalive_timeout 65`.
     - Global access log `/var/log/nginx/access.log`.
     - Global error log `/var/log/nginx/error.log`.
   - Configures shared NGINX security settings:
     - `server_tokens off`.
     - Rate-limit zone `login`: `10m`, `10r/m`.
     - Rate-limit zone `api`: `10m`, `30r/m`.
     - Client/body/header buffer limits of 1 KB.
     - Body, header, and send timeouts of 10 seconds.
     - TLS `1.2` and `1.3`.
     - Explicit RSA/DHE cipher list and server cipher preference.
     - Shared SSL session cache of 10 MB and session timeout of 10 minutes.
   - Iterations expanded:
     - **test.cluster.local**:
       - Creates `/opt/server/test` recursively with owner `www-data`, group `www-data`, and mode `0755`.
       - Deploys `test/index.html` to `/opt/server/test/index.html` with owner `www-data`, group `www-data`, and mode `0644`.
     - **ci.cluster.local**:
       - Creates `/opt/server/ci` recursively with owner `www-data`, group `www-data`, and mode `0755`.
       - Deploys `ci/index.html` to `/opt/server/ci/index.html` with owner `www-data`, group `www-data`, and mode `0644`.
     - **status.cluster.local**:
       - Creates `/opt/server/status` recursively with owner `www-data`, group `www-data`, and mode `0755`.
       - Deploys `status/index.html` to `/opt/server/status/index.html` with owner `www-data`, group `www-data`, and mode `0644`.
   - A change to `/etc/nginx/nginx.conf` or `/etc/nginx/conf.d/security.conf` schedules a delayed NGINX reload.
   - Validate NGINX configuration with `nginx -t` before reloading.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner `root`, group `root`, and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root`, group `ssl-cert`, and mode `0710`.
   - Generates self-signed X.509 certificates using RSA 2048-bit keys and 365-day validity.
   - Uses the subject structure:
     ```text
     /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com
     ```
   - Iterations expanded:
     - **test.cluster.local**:
       - Generates `/etc/ssl/certs/test.cluster.local.crt`.
       - Generates `/etc/ssl/private/test.cluster.local.key`.
       - Uses subject CN `test.cluster.local`.
       - Sets private-key ownership to `root:ssl-cert` and mode to `0640`.
     - **ci.cluster.local**:
       - Generates `/etc/ssl/certs/ci.cluster.local.crt`.
       - Generates `/etc/ssl/private/ci.cluster.local.key`.
       - Uses subject CN `ci.cluster.local`.
       - Sets private-key ownership to `root:ssl-cert` and mode to `0640`.
     - **status.cluster.local**:
       - Generates `/etc/ssl/certs/status.cluster.local.crt`.
       - Generates `/etc/ssl/private/status.cluster.local.key`.
       - Uses subject CN `status.cluster.local`.
       - Sets private-key ownership to `root:ssl-cert` and mode to `0640`.
   - A newly generated certificate/key pair schedules a delayed NGINX reload.
   - Chef only creates the certificate/key pair when both files do not already exist; it does not rotate an existing certificate after expiry. Retain this behavior or explicitly implement managed renewal as a migration design decision.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for each named site.
   - Every rendered virtual host:
     - Listens on TCP port `80` and redirects requests to `https://$server_name$request_uri` with HTTP `301`.
     - Listens on TCP port `443 ssl http2`.
     - Serves static content from the configured document root.
     - Enables TLS `1.2` and `1.3`.
     - Sets HSTS to `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
     - Adds `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`, and a same-origin Content Security Policy with explicit inline script/style allowances.
     - Enables gzip.
     - Uses `try_files $uri $uri/ =404`.
     - Denies access to `.htaccess`, `.git`, and `.svn` paths.
   - Iterations expanded:
     - **test.cluster.local**:
       - Renders `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
       - Sets `server_name test.cluster.local`.
       - Sets document root `/opt/server/test`.
       - Sets certificate `/etc/ssl/certs/test.cluster.local.crt`.
       - Sets private key `/etc/ssl/private/test.cluster.local.key`.
       - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`.
       - Writes logs to `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`.
     - **ci.cluster.local**:
       - Renders `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
       - Sets `server_name ci.cluster.local`.
       - Sets document root `/opt/server/ci`.
       - Sets certificate `/etc/ssl/certs/ci.cluster.local.crt`.
       - Sets private key `/etc/ssl/private/ci.cluster.local.key`.
       - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`.
       - Writes logs to `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`.
     - **status.cluster.local**:
       - Renders `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
       - Sets `server_name status.cluster.local`.
       - Sets document root `/opt/server/status`.
       - Sets certificate `/etc/ssl/certs/status.cluster.local.crt`.
       - Sets private key `/etc/ssl/private/status.cluster.local.key`.
       - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`.
       - Writes logs to `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Changes to site configuration files, site symlinks, or default-site removal schedule a delayed NGINX reload.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: enabled and started; reload after NGINX configuration, certificate, site, symlink, or default-site changes.
- `fail2ban`: enabled and started; restarted after Fail2ban configuration changes.
- `ssh`: restarted only after SSH hardening changes.
- UFW: enabled with default-deny policy and TCP allowances for ports `22`, `80`, and `443`.

Supported operating systems declared by cookbook metadata:
- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

The executed resources use Debian/Ubuntu-oriented conventions including UFW, `www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and the `ssh` service name. Before deploying to CentOS, validate package names, firewall implementation, web-service user, NGINX configuration layout, and SSH unit name.

## Credentials

**Detection Summary**: 3 sensitive private-key artifacts detected across 2 executed files.

**Source**:
- **Provider**: None detected; certificate key pairs are generated locally on the managed host.
- **URL**: Not applicable.
- **Path**: `/etc/ssl/private/`

### Self-signed TLS private keys
- **Variable(s)**: `key_file`, `node['nginx']['ssl']['private_key_path']`, `site_name`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Locally generated private keys on the target host.
- **Usage context**: NGINX TLS server keys referenced by SSL virtual-host configurations.

Private keys:
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`

Associated public certificates:
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`

No externally stored passwords, API tokens, Chef data bags, encrypted data bags, Chef Vault items, CyberArk or Conjur references, AWS Secrets Manager references, or environment-variable secrets were detected.

## Checks for the Migration

**Files to verify**:
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`
- `/opt/server/test`
- `/opt/server/test/index.html`
- `/opt/server/ci`
- `/opt/server/ci/index.html`
- `/opt/server/status`
- `/opt/server/status/index.html`
- `/var/log/nginx/access.log`
- `/var/log/nginx/error.log`
- `/var/log/nginx/test.cluster.local_access.log`
- `/var/log/nginx/test.cluster.local_error.log`
- `/var/log/nginx/ci.cluster.local_access.log`
- `/var/log/nginx/ci.cluster.local_error.log`
- `/var/log/nginx/status.cluster.local_access.log`
- `/var/log/nginx/status.cluster.local_error.log`
- `/var/log/auth.log`

**Service endpoints to check**:
- SSH: TCP port `22`
- NGINX HTTP: TCP port `80`
- NGINX HTTPS: TCP port `443`
- No Unix socket is configured.
- NGINX `listen` directives do not specify a bind address; validate active IPv4 listeners.
- IPv6 connectivity is not expected because `/etc/sysctl.d/99-security.conf` disables IPv6.

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: renders 1 time.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: renders 1 time.

## Pre-flight checks:

```bash
# Package and service status.
dpkg-query -W -f='${Package} ${Status}\n' nginx fail2ban ufw openssl ca-certificates
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status nginx --no-pager
systemctl status fail2ban --no-pager

# Validate NGINX and SSH configuration.
nginx -t
sshd -t

# Confirm global NGINX configuration and shared security settings.
grep -F 'include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
grep -F 'include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
grep -F 'server_tokens off;' /etc/nginx/conf.d/security.conf
grep -F 'ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
grep -F 'limit_req_zone $binary_remote_addr zone=login:10m rate=10r/m;' /etc/nginx/conf.d/security.conf
grep -F 'limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;' /etc/nginx/conf.d/security.conf

# Confirm UFW policy and allowed ports.
ufw status verbose
ufw status | grep -F 'Default: deny'
ufw status | grep -E '22/tcp.*ALLOW'
ufw status | grep -E '80/tcp.*ALLOW'
ufw status | grep -E '443/tcp.*ALLOW'

# Confirm SSH hardening.
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
systemctl status ssh --no-pager

# Confirm kernel-security configuration.
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv6.conf.all.disable_ipv6
grep -F 'net.ipv4.tcp_syncookies = 1' /etc/sysctl.d/99-security.conf
grep -F 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.d/99-security.conf

# Confirm Fail2ban and enabled jails.
fail2ban-client ping
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
grep -F 'maxretry = 3' /etc/fail2ban/jail.local
grep -F 'maxretry = 10' /etc/fail2ban/jail.local

# test.cluster.local files, configuration, certificate, redirect, HTTPS, and logs.
stat -c '%U:%G %a %n' /opt/server/test /opt/server/test/index.html
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -F 'server_name test.cluster.local;' /etc/nginx/sites-available/test.cluster.local
grep -F 'root /opt/server/test;' /etc/nginx/sites-available/test.cluster.local
grep -F 'ssl_certificate /etc/ssl/certs/test.cluster.local.crt;' /etc/nginx/sites-available/test.cluster.local
grep -F 'ssl_certificate_key /etc/ssl/private/test.cluster.local.key;' /etc/nginx/sites-available/test.cluster.local
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep -F 'CN = test.cluster.local'
curl --resolve test.cluster.local:80:127.0.0.1 -sSI http://test.cluster.local/ | grep -E 'HTTP/1\.[01] 301|location: https://test\.cluster\.local/'
curl --resolve test.cluster.local:443:127.0.0.1 -k -sSI https://test.cluster.local/ | grep -E 'HTTP/2 200|HTTP/1\.[01] 200'
curl --resolve test.cluster.local:443:127.0.0.1 -k -sSI https://test.cluster.local/ | grep -Fi 'strict-transport-security: max-age=31536000; includesubdomains'
test -e /var/log/nginx/test.cluster.local_access.log
test -e /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log

# ci.cluster.local files, configuration, certificate, redirect, HTTPS, and logs.
stat -c '%U:%G %a %n' /opt/server/ci /opt/server/ci/index.html
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -F 'server_name ci.cluster.local;' /etc/nginx/sites-available/ci.cluster.local
grep -F 'root /opt/server/ci;' /etc/nginx/sites-available/ci.cluster.local
grep -F 'ssl_certificate /etc/ssl/certs/ci.cluster.local.crt;' /etc/nginx/sites-available/ci.cluster.local
grep -F 'ssl_certificate_key /etc/ssl/private/ci.cluster.local.key;' /etc/nginx/sites-available/ci.cluster.local
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep -F 'CN = ci.cluster.local'
curl --resolve ci.cluster.local:80:127.0.0.1 -sSI http://ci.cluster.local/ | grep -E 'HTTP/1\.[01] 301|location: https://ci\.cluster\.local/'
curl --resolve ci.cluster.local:443:127.0.0.1 -k -sSI https://ci.cluster.local/ | grep -E 'HTTP/2 200|HTTP/1\.[01] 200'
curl --resolve ci.cluster.local:443:127.0.0.1 -k -sSI https://ci.cluster.local/ | grep -Fi 'strict-transport-security: max-age=31536000; includesubdomains'
test -e /var/log/nginx/ci.cluster.local_access.log
test -e /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log

# status.cluster.local files, configuration, certificate, redirect, HTTPS, and logs.
stat -c '%U:%G %a %n' /opt/server/status /opt/server/status/index.html
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -F 'server_name status.cluster.local;' /etc/nginx/sites-available/status.cluster.local
grep -F 'root /opt/server/status;' /etc/nginx/sites-available/status.cluster.local
grep -F 'ssl_certificate /etc/ssl/certs/status.cluster.local.crt;' /etc/nginx/sites-available/status.cluster.local
grep -F 'ssl_certificate_key /etc/ssl/private/status.cluster.local.key;' /etc/nginx/sites-available/status.cluster.local
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep -F 'CN = status.cluster.local'
curl --resolve status.cluster.local:80:127.0.0.1 -sSI http://status.cluster.local/ | grep -E 'HTTP/1\.[01] 301|location: https://status\.cluster\.local/'
curl --resolve status.cluster.local:443:127.0.0.1 -k -sSI https://status.cluster.local/ | grep -E 'HTTP/2 200|HTTP/1\.[01] 200'
curl --resolve status.cluster.local:443:127.0.0.1 -k -sSI https://status.cluster.local/ | grep -Fi 'strict-transport-security: max-age=31536000; includesubdomains'
test -e /var/log/nginx/status.cluster.local_access.log
test -e /var/log/nginx/status.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log

# Listener, default-site, global-log, and journal checks.
ss -ltnp | grep -E ':80\s'
ss -ltnp | grep -E ':443\s'
ss -ltnp | grep -E ':22\s'
test ! -e /etc/nginx/sites-enabled/default
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/auth.log
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
journalctl -u ssh -n 100 --no-pager
```