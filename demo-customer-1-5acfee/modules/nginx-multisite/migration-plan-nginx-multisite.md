---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an Nginx web server hosting three SSL-enabled static virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and starts Nginx and Fail2ban, configures UFW with deny-by-default and SSH/HTTP/HTTPS allowances, hardens kernel and SSH settings, creates self-signed TLS certificates, deploys Nginx virtual-host configurations and static content, and removes Nginx’s default enabled site.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` redirects to TCP `443`; HTTPS uses HTTP/2.
  - Key Config: Self-signed certificate `/etc/ssl/certs/test.cluster.local.crt`, private key `/etc/ssl/private/test.cluster.local.key`, static content source `test/index.html`, access log `/var/log/nginx/test.cluster.local_access.log`, and error log `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` redirects to TCP `443`; HTTPS uses HTTP/2.
  - Key Config: Self-signed certificate `/etc/ssl/certs/ci.cluster.local.crt`, private key `/etc/ssl/private/ci.cluster.local.key`, static content source `ci/index.html`, access log `/var/log/nginx/ci.cluster.local_access.log`, and error log `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` redirects to TCP `443`; HTTPS uses HTTP/2.
  - Key Config: Self-signed certificate `/etc/ssl/certs/status.cluster.local.crt`, private key `/etc/ssl/private/status.cluster.local.key`, static content source `status/index.html`, access log `/var/log/nginx/status.cluster.local_access.log`, and error log `/var/log/nginx/status.cluster.local_error.log`.

## File Structure

```text
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb

templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/sysctl-security.conf.erb
templates/default/site.conf.erb

attributes/default.rb
```

No custom resource provider is executed by the supplied execution tree.

No static file is present in the supplied directory listing. The cookbook references the following `cookbook_file` sources, which must be obtained and supplied as application-content artifacts before migration:

```text
test/index.html
ci/index.html
status/index.html
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
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures Fail2ban defaults: ban time `3600`, find time `600`, maximum retries `3`, SSH protection, Nginx HTTP-auth protection, Nginx request-limit protection, and Nginx bot-search protection.
   - Restarts `fail2ban` on a delayed notification when `/etc/fail2ban/jail.local` changes.
   - Configures UFW with a default deny policy, allows SSH/TCP `22`, HTTP/TCP `80`, and HTTPS/TCP `443`, then enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies `/etc/sysctl.d/99-security.conf` with `sysctl -p /etc/sysctl.d/99-security.conf` after changes.
   - Applies kernel hardening including reverse-path filtering, disabled ICMP redirects and source routing, martian logging, disabled ICMP echo replies, disabled IPv6, TCP SYN cookies, `net.ipv4.tcp_max_syn_backlog = 2048`, `net.ipv4.tcp_synack_retries = 2`, and `net.ipv4.tcp_syn_retries = 5`.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
   - Restarts `ssh` on a delayed notification when either SSH directive changes.
   - Resources used: package, service, template, and execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures Nginx to run as `www-data`, uses `worker_processes auto`, `worker_connections 768`, PID file `/run/nginx.pid`, logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`, enables gzip, and includes `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures global Nginx hardening: `server_tokens off`, `login` rate limit of `10r/m`, `api` rate limit of `30r/m`, restrictive client buffers and timeouts, TLS limited to `TLSv1.2` and `TLSv1.3`, TLS session cache `shared:SSL:10m`, and TLS session timeout `10m`.
   - Enables and starts the `nginx` service. Configuration changes trigger a delayed Nginx reload.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively as `www-data:www-data` with mode `0755`; deploys `test/index.html` to `/opt/server/test/index.html` as `www-data:www-data` with mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively as `www-data:www-data` with mode `0755`; deploys `ci/index.html` to `/opt/server/ci/index.html` as `www-data:www-data` with mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively as `www-data:www-data` with mode `0755`; deploys `status/index.html` to `/opt/server/status/index.html` as `www-data:www-data` with mode `0644`.
   - Resources used: package, template, service, directory, and cookbook_file resources.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` owned by `root:root` with mode `0755`.
   - Creates `/etc/ssl/private` owned by `root:ssl-cert` with mode `0710`.
   - Iterations:
     - **test.cluster.local**: Generates a self-signed RSA 2048-bit certificate valid for `365` days at `/etc/ssl/certs/test.cluster.local.crt` with private key `/etc/ssl/private/test.cluster.local.key`. The certificate subject is `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`. The key is `root:ssl-cert`, mode `0640`.
     - **ci.cluster.local**: Generates a self-signed RSA 2048-bit certificate valid for `365` days at `/etc/ssl/certs/ci.cluster.local.crt` with private key `/etc/ssl/private/ci.cluster.local.key`. The certificate subject is `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`. The key is `root:ssl-cert`, mode `0640`.
     - **status.cluster.local**: Generates a self-signed RSA 2048-bit certificate valid for `365` days at `/etc/ssl/certs/status.cluster.local.crt` with private key `/etc/ssl/private/status.cluster.local.key`. The certificate subject is `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`. The key is `root:ssl-cert`, mode `0640`.
   - Certificate generation triggers a delayed Nginx reload.
   - Resources used: package, group, directory, and execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations:
     - **test.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`; creates `/etc/nginx/sites-enabled/test.cluster.local` as a symbolic link to `/etc/nginx/sites-available/test.cluster.local`.
     - **ci.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`; creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symbolic link to `/etc/nginx/sites-available/ci.cluster.local`.
     - **status.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`; creates `/etc/nginx/sites-enabled/status.cluster.local` as a symbolic link to `/etc/nginx/sites-available/status.cluster.local`.
   - Each virtual-host configuration listens on TCP `80` and returns a `301` redirect to `https://$server_name$request_uri`.
   - Each HTTPS virtual host listens on TCP `443` with `ssl http2`, uses its site-specific certificate and key, and permits only `TLSv1.2` and `TLSv1.3`.
   - Each site configures HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`, a self-restricted Content Security Policy permitting inline JavaScript and CSS, static `try_files $uri $uri/ =404`, and denies `.htaccess`, `.git`, and `.svn` paths.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Template changes, link changes, and default-site removal trigger a delayed Nginx reload.
   - Resources used: template, link, and file resources.

## Dependencies

**External cookbook dependencies**: None declared in the supplied `metadata.rb`.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`.

**Service dependencies**:
- `nginx`: Enabled and started; reloads after global configuration, virtual-host configuration, site-link, default-site, certificate, or private-key changes.
- `fail2ban`: Enabled and started; restarts after `/etc/fail2ban/jail.local` changes.
- `ssh`: Restarts after SSH hardening directive changes.

## Credentials

**Detection Summary**: 3 generated TLS private keys detected across 2 recipe/template files. No passwords, API tokens, Chef data bags, encrypted data bags, Chef Vault calls, CyberArk/Conjur calls, environment-variable secrets, or embedded database credentials were detected.

**Source**:
  - **Provider**: Internal / locally generated self-signed TLS material
  - **URL**: None
  - **Path**: `/etc/ssl/private`

### Test Site TLS Private Key
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/test.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`, `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by the `openssl req -x509` command.
- **Usage context**: Private key for the `test.cluster.local` HTTPS virtual host, referenced by Nginx through `ssl_certificate_key`.
- **Permissions**: `root:ssl-cert`, mode `0640`.

### CI Site TLS Private Key
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/ci.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`, `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by the `openssl req -x509` command.
- **Usage context**: Private key for the `ci.cluster.local` HTTPS virtual host, referenced by Nginx through `ssl_certificate_key`.
- **Permissions**: `root:ssl-cert`, mode `0640`.

### Status Site TLS Private Key
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`, `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by the `openssl req -x509` command.
- **Usage context**: Private key for the `status.cluster.local` HTTPS virtual host, referenced by Nginx through `ssl_certificate_key`.
- **Permissions**: `root:ssl-cert`, mode `0640`.

## Checks for the Migration

**Files to verify**:
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/opt/server/test`
- `/opt/server/test/index.html`
- `/opt/server/ci`
- `/opt/server/ci/index.html`
- `/opt/server/status`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`

The following path must be absent:
- `/etc/nginx/sites-enabled/default`

**Service endpoints to check**:
- TCP port `22`: SSH, allowed by UFW.
- TCP port `80`: Nginx HTTP; `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` redirect to HTTPS.
- TCP port `443`: Nginx HTTPS; `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` serve static content.
- No Unix sockets are configured.
- Nginx is not configured with a specific bind address and listens on applicable local interfaces.

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
# Packages and services
dpkg-query -W -f='${Package} ${Status}\n' nginx fail2ban ufw openssl ca-certificates 2>/dev/null \
  || rpm -q nginx fail2ban ufw openssl ca-certificates

systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl is-active ssh

nginx -t
fail2ban-client ping

# Firewall, SSH, and sysctl hardening
ufw status verbose
grep -x 'PermitRootLogin no' /etc/ssh/sshd_config
grep -x 'PasswordAuthentication no' /etc/ssh/sshd_config
sshd -t

test -f /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv6.conf.all.disable_ipv6

# Nginx global configuration
grep -x 'server_tokens off;' /etc/nginx/conf.d/security.conf
grep -x 'ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
grep -x 'worker_processes auto;' /etc/nginx/nginx.conf
grep -x 'include /etc/nginx/sites-enabled/\*;' /etc/nginx/nginx.conf

# test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -F 'server_name test.cluster.local;' /etc/nginx/sites-available/test.cluster.local
grep -F 'root /opt/server/test;' /etc/nginx/sites-available/test.cluster.local
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -skI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
openssl s_client -connect 127.0.0.1:443 -servername test.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject

# ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -F 'server_name ci.cluster.local;' /etc/nginx/sites-available/ci.cluster.local
grep -F 'root /opt/server/ci;' /etc/nginx/sites-available/ci.cluster.local
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -skI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
openssl s_client -connect 127.0.0.1:443 -servername ci.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject

# status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -F 'server_name status.cluster.local;' /etc/nginx/sites-available/status.cluster.local
grep -F 'root /opt/server/status;' /etc/nginx/sites-available/status.cluster.local
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -skI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
openssl s_client -connect 127.0.0.1:443 -servername status.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject

# Default site and listeners
test ! -e /etc/nginx/sites-enabled/default
ss -tlnp | grep ':22 '
ss -tlnp | grep ':80 '
ss -tlnp | grep ':443 '
lsof -nP -iTCP:80 -sTCP:LISTEN
lsof -nP -iTCP:443 -sTCP:LISTEN
```