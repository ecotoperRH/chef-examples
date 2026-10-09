---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures nginx with three HTTPS-enabled virtual hosts—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs nginx, fail2ban, UFW, OpenSSL, and CA certificates; applies firewall, SSH, kernel, nginx, and fail2ban hardening; generates self-signed certificates; deploys one static landing page per site; and enables HTTP-to-HTTPS virtual-host configurations on ports 80 and 443.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Static HTTPS site
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP ports `80` and `443`
  - Key Config: HTTP redirects to HTTPS; HTTPS uses HTTP/2; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; SSL enabled

- **ci.cluster.local**: Static HTTPS site
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP ports `80` and `443`
  - Key Config: HTTP redirects to HTTPS; HTTPS uses HTTP/2; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; SSL enabled

- **status.cluster.local**: Static HTTPS site
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP ports `80` and `443`
  - Key Config: HTTP redirects to HTTPS; HTTPS uses HTTP/2; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; SSL enabled

**Security configuration**:

- **fail2ban**: Enabled and started; monitors SSH and nginx-related logs
- **ufw**: Enabled with default incoming policy `deny`; allows SSH, HTTP, and HTTPS
- **ssh**: Root login disabled; password authentication disabled

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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

No provider is used by the execution tree. `resources/lineinfile.rb` is mentioned by structural analysis but is not invoked by an executed recipe.

**Templates:**
```text
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
```

**Attributes:**
```text
cookbooks/nginx-multisite/attributes/default.rb
```

**Files:**

No static files are listed in the supplied cookbook directory listing. The recipes reference these `cookbook_file` source paths:

```text
test/index.html
ci/index.html
status/index.html
```

These source files must be supplied in the Ansible role or deployment content if the static landing pages are required.

## Module Explanation

The cookbook entry point is `cookbooks/nginx-multisite/recipes/default.rb`. It includes recipes in this execution order:

1. `nginx-multisite::security`
2. `nginx-multisite::nginx`
3. `nginx-multisite::ssl`
4. `nginx-multisite::sites`

### 1. Security

**Recipe**: `cookbooks/nginx-multisite/recipes/security.rb`

- Installs the `fail2ban` and `ufw` packages.
- Enables and starts the `fail2ban` service.
- Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
- Configures fail2ban global values:
  - `bantime`: `3600`
  - `findtime`: `600`
  - `maxretry`: `3`
  - Backend: `auto`
- Configures enabled jails:
  - SSH: port `ssh`, log `/var/log/auth.log`, maximum retries `3`
  - nginx HTTP authentication: ports `http,https`, log `/var/log/nginx/*error.log`, maximum retries `3`
  - nginx rate limiting: ports `http,https`, log `/var/log/nginx/*error.log`, maximum retries `10`
  - nginx bot search: ports `http,https`, log `/var/log/nginx/*access.log`, maximum retries `2`
- Notifies a delayed fail2ban restart when the jail template changes.
- Applies UFW commands in order:
  1. Set default incoming policy to deny.
  2. Allow SSH on port `22/tcp`.
  3. Allow HTTP on port `80/tcp`.
  4. Allow HTTPS on port `443/tcp`.
  5. Enable UFW.
- Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
- Configures reverse-path filtering, redirect and source-route protection, martian packet logging, ICMP suppression, IPv6 disabling, SYN-cookie protection, and TCP backlog and retry settings.
- Applies the sysctl file with `sysctl -p /etc/sysctl.d/99-security.conf` when the file changes.
- Sets `PermitRootLogin no` in `/etc/ssh/sshd_config`.
- Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
- Restarts SSH only when either SSH setting changes.
- Uses 8 execute resources:
  - 5 UFW commands
  - 1 sysctl reload command
  - 1 conditional root-login command
  - 1 conditional password-authentication command

### 2. nginx Installation and Site Content

**Recipe**: `cookbooks/nginx-multisite/recipes/nginx.rb`

- Installs the `nginx` package.
- Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
- Configures:
  - Worker user `www-data`
  - Worker processes `auto`
  - PID file `/run/nginx.pid`
  - Worker connections `768`
  - Access log `/var/log/nginx/access.log`
  - Error log `/var/log/nginx/error.log`
  - `sendfile on`
  - `tcp_nopush on`
  - `tcp_nodelay on`
  - Keepalive timeout `65`
  - Gzip enabled
  - Includes `/etc/nginx/conf.d/*.conf`
  - Includes `/etc/nginx/sites-enabled/*`
- Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
- Configures nginx version hiding, login and API rate limits, request-buffer limits, request timeouts, TLS 1.2 and TLS 1.3, TLS session caching, TLS session timeout, preferred server ciphers, and the explicit TLS cipher list.
- Enables and starts the nginx service.
- Schedules a delayed nginx reload when either nginx template changes.
- Creates the following directories, each owned by `www-data:www-data` with mode `0755` and recursive creation enabled:
  - `/opt/server/test`
  - `/opt/server/ci`
  - `/opt/server/status`
- Deploys the following static files, each owned by `www-data:www-data` with mode `0644`:
  - `test/index.html` to `/opt/server/test/index.html`
  - `ci/index.html` to `/opt/server/ci/index.html`
  - `status/index.html` to `/opt/server/status/index.html`

### 3. SSL Certificate Preparation

**Recipe**: `cookbooks/nginx-multisite/recipes/ssl.rb`

- Installs the `openssl` and `ca-certificates` packages.
- Creates the `ssl-cert` group.
- Creates `/etc/ssl/certs` owned by `root:root` with mode `0755`.
- Creates `/etc/ssl/private` owned by `root:ssl-cert` with mode `0710`.
- Generates self-signed certificates only when the corresponding certificate and private-key files are absent.
- Uses RSA 2048-bit keys, 365-day validity, and the subject template:
  ```text
  /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site-name>/emailAddress=admin@example.com
  ```
- Sets private keys to mode `0640` and ownership `root:ssl-cert`.
- Schedules a delayed nginx reload after generating a certificate.

Expanded certificate iterations:

- **test.cluster.local**
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Subject CN: `test.cluster.local`

- **ci.cluster.local**
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Subject CN: `ci.cluster.local`

- **status.cluster.local**
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Subject CN: `status.cluster.local`

Ansible should use `community.crypto.openssl_privatekey` and `community.crypto.x509_certificate` where available while preserving the no-regeneration behavior.

### 4. Virtual Host Configuration

**Recipe**: `cookbooks/nginx-multisite/recipes/sites.rb`

- Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` three times.
- Creates three enabled-site symbolic links.
- Removes `/etc/nginx/sites-enabled/default`.
- Schedules a delayed nginx reload when a site template, link, or default-site removal changes.

Expanded site iterations:

- **test.cluster.local**
  - Template destination: `/etc/nginx/sites-available/test.cluster.local`
  - Document root: `/opt/server/test`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Link: `/etc/nginx/sites-enabled/test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local`
  - Access log: `/var/log/nginx/test.cluster.local_access.log`
  - Error log: `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**
  - Template destination: `/etc/nginx/sites-available/ci.cluster.local`
  - Document root: `/opt/server/ci`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Link: `/etc/nginx/sites-enabled/ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local`
  - Access log: `/var/log/nginx/ci.cluster.local_access.log`
  - Error log: `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**
  - Template destination: `/etc/nginx/sites-available/status.cluster.local`
  - Document root: `/opt/server/status`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Link: `/etc/nginx/sites-enabled/status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local`
  - Access log: `/var/log/nginx/status.cluster.local_access.log`
  - Error log: `/var/log/nginx/status.cluster.local_error.log`

Each virtual host provides:

- HTTP listener on port `80`
- HTTP-to-HTTPS redirect
- HTTPS listener on port `443`
- HTTP/2
- Static-file lookup with `try_files`
- TLS 1.2 and TLS 1.3
- One-year HSTS with subdomain inclusion
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection`
- Strict referrer policy
- Content Security Policy
- Gzip compression
- Denial of `.htaccess`, `.git`, and `.svn` paths
- Site-specific access and error logs

## Dependencies

**External cookbook dependencies**: None declared in the supplied metadata.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: restarted only after SSH hardening changes

**Platform support**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`
- Chef `>= 16.0`

**Network dependencies**:

- TCP `22`: SSH, allowed through UFW
- TCP `80`: nginx HTTP, allowed through UFW
- TCP `443`: nginx HTTPS, allowed through UFW
- nginx PID file: `/run/nginx.pid`
- No cookbook-defined Unix socket or custom IPC endpoint

## Credentials

**Detection Summary**: No application credentials, passwords, API tokens, data bags, vault references, or external secret-manager integrations were detected. Three locally generated TLS private keys are sensitive filesystem artifacts.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

### TLS Private Keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/attributes/default.rb`
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated filesystem keys
- **Usage context**: TLS private keys for the three nginx HTTPS virtual hosts
- **Permissions**: Mode `0640`, owned by `root:ssl-cert`

### Self-Signed Certificate Identity

- **Variable(s)**: `emailAddress=admin@example.com`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Embedded in the OpenSSL command
- **Usage context**: Subject identity for generated self-signed certificates
- **Classification**: Identity value, not an authentication credential

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, secret environment variables, hardcoded passwords, database credentials, or API keys were detected.

## Checks for the Migration

**Files to verify**:

```text
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/etc/nginx/sites-enabled/default
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
/opt/server/test/index.html
/opt/server/ci/index.html
/opt/server/status/index.html
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/status.cluster.local.key
```

`/etc/nginx/sites-enabled/default` is expected to be absent.

**Service endpoints to check**:

- `test.cluster.local`: ports `80` and `443`
- `ci.cluster.local`: ports `80` and `443`
- `status.cluster.local`: ports `80` and `443`

Expected behavior:

- Port 80 returns HTTP `301` to the equivalent HTTPS URL.
- Port 443 returns the corresponding static site.
- HTTPS presents a certificate with a CN matching the requested hostname.
- HTTP/2 is enabled on HTTPS.

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb`: 1 render
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb`: 1 render
- `cookbooks/nginx-multisite/templates/default/security.conf.erb`: 1 render
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb`: 3 renders
  - `test.cluster.local`
  - `ci.cluster.local`
  - `status.cluster.local`

## Pre-flight checks:

```bash
# Package and service status
dpkg-query -W nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
rpm -q nginx fail2ban ufw openssl ca-certificates

systemctl status nginx
systemctl status fail2ban
systemctl status ssh

# nginx and SSH configuration validation
nginx -t
sshd -t

nginx -T | grep -E \
'test.cluster.local|ci.cluster.local|status.cluster.local|listen 80|listen 443'

grep -E \
'worker_processes|worker_connections|access_log|error_log|gzip on|sites-enabled' \
/etc/nginx/nginx.conf

grep -E \
'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols|ssl_ciphers' \
/etc/nginx/conf.d/security.conf

grep -E \
'^(PermitRootLogin|PasswordAuthentication)' \
/etc/ssh/sshd_config

# test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key

curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/
curl -k -s --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/test.cluster.local.crt \
  -noout -subject -dates

grep -E \
'server_name|root|ssl_certificate|ssl_certificate_key|listen|access_log|error_log' \
/etc/nginx/sites-available/test.cluster.local

# ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key

curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt \
  -noout -subject -dates

grep -E \
'server_name|root|ssl_certificate|ssl_certificate_key|listen|access_log|error_log' \
/etc/nginx/sites-available/ci.cluster.local

# status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key

curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/
curl -k -s --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/status.cluster.local.crt \
  -noout -subject -dates

grep -E \
'server_name|root|ssl_certificate|ssl_certificate_key|listen|access_log|error_log' \
/etc/nginx/sites-available/status.cluster.local

# nginx listeners
ss -tlnp | grep -E ':80|:443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN

# Firewall
ufw status verbose
ufw status numbered

# fail2ban
fail2ban-client ping
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

grep -E \
'^(bantime|findtime|maxretry|backend|enabled|port|logpath)' \
/etc/fail2ban/jail.local

# Kernel security settings
sysctl net.ipv4.conf.default.rp_filter
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv6.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv6.conf.all.accept_source_route
sysctl net.ipv4.conf.all.log_martians
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.icmp_echo_ignore_broadcasts
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv6.conf.default.disable_ipv6
sysctl net.ipv6.conf.lo.disable_ipv6
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv4.tcp_synack_retries
sysctl net.ipv4.tcp_syn_retries

cat /etc/sysctl.d/99-security.conf

# Logs
journalctl -u nginx --no-pager -n 100
journalctl -u fail2ban --no-pager -n 100
journalctl -u ssh --no-pager -n 100

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