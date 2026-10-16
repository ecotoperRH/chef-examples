---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures nginx as a multi-site HTTPS web server on Ubuntu or CentOS with three virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs nginx, fail2ban, UFW, OpenSSL, and CA certificates; creates site document roots and index files; generates self-signed certificates; configures HTTP-to-HTTPS redirects, security headers, rate limits, firewall rules, SSH hardening, and kernel network protections.

## Service Type and Instances

**Service Type**: Web Server

**Supported platforms**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

**Configured Instances**:

- **test.cluster.local**: HTTPS nginx virtual host serving the test site
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2, HSTS, security headers, gzip, rate limiting, and static-file fallback enabled

- **ci.cluster.local**: HTTPS nginx virtual host serving the CI site
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2, HSTS, security headers, gzip, rate limiting, and static-file fallback enabled

- **status.cluster.local**: HTTPS nginx virtual host serving the status site
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2, HSTS, security headers, gzip, rate limiting, and static-file fallback enabled

- **fail2ban**: Intrusion prevention service
  - Location/Path: `/etc/fail2ban/jail.local`
  - Port/Socket: SSH and nginx log monitoring
  - Key Config: Enabled and started; `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails configured

- **ufw**: Host firewall
  - Location/Path: UFW system configuration
  - Port/Socket: Allows `22/tcp`, `80/tcp`, and `443/tcp`
  - Key Config: Enabled with default incoming policy `deny`

- **ssh**: SSH service
  - Location/Path: `/etc/ssh/sshd_config`
  - Port/Socket: `22/tcp`
  - Key Config: Root login disabled and password authentication disabled

## File Structure

The following files are used by the cookbook and are listed using paths relative to `cookbooks/nginx-multisite`.

```text
attributes/default.rb
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/sysctl-security.conf.erb
```

**Providers:**

```text
None
```

No custom resource provider is used in the execution tree. `resources/lineinfile.rb` is mentioned by structural analysis but is not invoked by any supplied recipe.

**Dynamic cookbook file sources:**

```text
test/index.html
ci/index.html
status/index.html
```

These sources are referenced by `cookbook_file` resources but are not present in the supplied file inventory and must be verified before implementing the Ansible role.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - The Ansible implementation must preserve this execution order.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures global fail2ban values: `bantime = 3600`, `findtime = 600`, `maxretry = 3`, and backend `auto`.
   - Configures the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Applies UFW default-deny policy and allows SSH, HTTP, and HTTPS.
   - Enables UFW when it is not already active.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies reverse-path filtering, redirect and source-route protections, martian logging, ICMP protections, IPv6 disabling, and TCP SYN flood protections.
   - Executes `sysctl -p /etc/sysctl.d/99-security.conf` as a delayed notification.
   - Disables SSH root login by setting `PermitRootLogin no`.
   - Disables SSH password authentication by setting `PasswordAuthentication no`.
   - Restarts `ssh` only when the SSH configuration changes.
   - Execute resources: **8**:
     - `ufw_default_deny`
     - `ufw_allow_ssh`
     - `ufw_allow_http`
     - `ufw_allow_https`
     - `ufw_enable`
     - `reload_sysctl`
     - `disable root login`
     - `disable password auth`

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures worker user `www-data`, automatic worker processes, PID `/run/nginx.pid`, `768` worker connections, keepalive timeout `65`, standard access and error logs, gzip, and site includes.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures server-token hiding, `login` and `api` rate-limit zones, request and header buffers, `client_max_body_size 1k`, ten-second client/header/send timeouts, TLS session settings, TLS 1.2 and TLS 1.3, explicit ciphers, and server cipher preference.
   - Enables and starts nginx with restart, reload, and status actions.
   - Creates the document root and deploys the index file for **test.cluster.local**:
     - Directory: `/opt/server/test`
     - File: `/opt/server/test/index.html`
     - Source: `test/index.html`
     - Owner/group: `www-data:www-data`
     - Directory mode: `0755`
     - File mode: `0644`
   - Creates the document root and deploys the index file for **ci.cluster.local**:
     - Directory: `/opt/server/ci`
     - File: `/opt/server/ci/index.html`
     - Source: `ci/index.html`
     - Owner/group: `www-data:www-data`
     - Directory mode: `0755`
     - File mode: `0644`
   - Creates the document root and deploys the index file for **status.cluster.local**:
     - Directory: `/opt/server/status`
     - File: `/opt/server/status/index.html`
     - Source: `status/index.html`
     - Owner/group: `www-data:www-data`
     - Directory mode: `0755`
     - File mode: `0644`
   - Site iteration totals: three directory resources and three `cookbook_file` resources.
   - Document-root and index-file resources do not notify nginx in the supplied execution tree.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root`, group `ssl-cert`, and mode `0710`.
   - Generates a self-signed 2048-bit RSA certificate valid for `365` days for **test.cluster.local**:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Subject CN: `test.cluster.local`
     - Email: `admin@example.com`
     - Key owner/group: `root:ssl-cert`
     - Key mode: `0640`
   - Generates a self-signed 2048-bit RSA certificate valid for `365` days for **ci.cluster.local**:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Subject CN: `ci.cluster.local`
     - Email: `admin@example.com`
     - Key owner/group: `root:ssl-cert`
     - Key mode: `0640`
   - Generates a self-signed 2048-bit RSA certificate valid for `365` days for **status.cluster.local**:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Subject CN: `status.cluster.local`
     - Email: `admin@example.com`
     - Key owner/group: `root:ssl-cert`
     - Key mode: `0640`
   - Skips certificate generation when both the certificate and key already exist.
   - Newly generated certificates or keys trigger a delayed nginx reload.
   - Execute resources: three, one for each named site.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **test.cluster.local** to `/etc/nginx/sites-available/test.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to `/etc/nginx/sites-available/test.cluster.local`.
   - Uses document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **ci.cluster.local** to `/etc/nginx/sites-available/ci.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to `/etc/nginx/sites-available/ci.cluster.local`.
   - Uses document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **status.cluster.local** to `/etc/nginx/sites-available/status.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to `/etc/nginx/sites-available/status.cluster.local`.
   - Uses document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Each site provides an HTTP listener on port `80`, HTTP-to-HTTPS redirection, an HTTP/2 HTTPS listener on port `443`, TLS 1.2 and TLS 1.3, HSTS, security headers, gzip, `try_files`, `.htaccess` denial, and `.git`/`.svn` denial.
   - Site-specific access logs:
     - `/var/log/nginx/test.cluster.local_access.log`
     - `/var/log/nginx/ci.cluster.local_access.log`
     - `/var/log/nginx/status.cluster.local_access.log`
   - Site-specific error logs:
     - `/var/log/nginx/test.cluster.local_error.log`
     - `/var/log/nginx/ci.cluster.local_error.log`
     - `/var/log/nginx/status.cluster.local_error.log`
   - Site templates, links, and default-site deletion trigger delayed nginx reloads when changed.
   - Iteration totals: three templates and three symbolic links.

## Dependencies

**External cookbook dependencies**: None declared in the supplied metadata.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started; restarted when `/etc/fail2ban/jail.local` changes
- `nginx`: enabled and started; reloaded when nginx configuration, certificates, virtual host templates, links, or default-site deletion changes
- `ssh`: restarted when SSH hardening changes `/etc/ssh/sshd_config`

**Network dependencies**:

- SSH: `22/tcp`
- HTTP: `80/tcp`
- HTTPS: `443/tcp`

## Credentials

**Detection Summary**: No operational credentials detected. Three runtime-generated TLS private keys are treated as sensitive files.

**Source**:

- **Provider**: None detected
- **URL**: None detected
- **Path**: None detected

### TLS Private Keys

- **Variable(s)**: None; keys are generated at runtime
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Local filesystem
- **Usage context**: nginx HTTPS termination
- **Files**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Required protection**: Owner `root`, group `ssl-cert`, mode `0640`

The literal `admin@example.com` value is certificate metadata, not an authentication credential. No data bags, encrypted data bags, Chef Vault, Conjur, CyberArk, Vault URLs, database credentials, API tokens, password attributes, or environment-variable secrets were detected.

## Checks for the Migration

**Files to verify**:

- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/etc/nginx/sites-enabled/default` must not exist
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
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

- `test.cluster.local`: HTTP `80`, HTTPS `443`
- `ci.cluster.local`: HTTP `80`, HTTPS `443`
- `status.cluster.local`: HTTP `80`, HTTPS `443`
- SSH: `22`

**Templates rendered**:

- `fail2ban.jail.local.erb`: once
- `nginx.conf.erb`: once
- `security.conf.erb`: once
- `sysctl-security.conf.erb`: once
- `site.conf.erb`: three times:
  - `test.cluster.local`
  - `ci.cluster.local`
  - `status.cluster.local`

## Pre-flight checks

```bash
# Package checks
dpkg -l nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
rpm -q nginx fail2ban ufw openssl ca-certificates

# Service checks
systemctl status nginx
systemctl status fail2ban
systemctl status ssh

# Configuration validation
nginx -t
sshd -t
sysctl -p /etc/sysctl.d/99-security.conf

# Nginx files
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
test -f /etc/nginx/sites-available/test.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test ! -e /etc/nginx/sites-enabled/default

# Site content: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html

# Site content: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html

# Site content: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html

# TLS files and permissions
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key

# Site endpoint: test.cluster.local
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/

# Site endpoint: ci.cluster.local
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/

# Site endpoint: status.cluster.local
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/

# Listening ports
ss -tlnp | grep -E ':(80|443)\b'

# Firewall
ufw status verbose
ufw status numbered

# Fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# SSH hardening
grep -E '^PermitRootLogin|^PasswordAuthentication' /etc/ssh/sshd_config
sshd -T | grep -E 'permitrootlogin|passwordauthentication'

# Kernel security
sysctl net.ipv4.conf.default.rp_filter
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv6.conf.all.accept_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv6.conf.all.accept_source_route
sysctl net.ipv4.conf.all.log_martians
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.icmp_echo_ignore_broadcasts
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv4.tcp_synack_retries
sysctl net.ipv4.tcp_syn_retries
```

Expected results:

- All required packages are installed.
- `nginx` and `fail2ban` are enabled and running.
- SSH reports `PermitRootLogin no` and `PasswordAuthentication no`.
- `nginx -t` succeeds.
- UFW is active with default incoming policy `deny`.
- Ports `22/tcp`, `80/tcp`, and `443/tcp` are allowed.
- nginx listens on ports `80` and `443`.
- HTTP requests for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` redirect to HTTPS.
- HTTPS requests for all three sites return a successful response.
- Certificates contain the corresponding site CN and are valid for `365` days.
- Each private key is owned by `root:ssl-cert` with mode `640`.
- The `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` fail2ban jails are enabled.
- Reverse-path filtering, redirect/source-route protections, martian logging, ICMP protections, IPv6 disabling, and TCP SYN flood protections match `/etc/sysctl.d/99-security.conf`.