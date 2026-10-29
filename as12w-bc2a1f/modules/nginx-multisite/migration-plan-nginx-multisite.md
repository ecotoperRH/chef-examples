---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This Chef cookbook configures nginx with three SSL-enabled virtual sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs nginx, fail2ban, UFW, OpenSSL, and CA certificates; creates site document roots and self-signed certificates; renders nginx, security, fail2ban, sysctl, and virtual-host configurations; enables SSH, HTTP, and HTTPS firewall rules; applies kernel security settings; disables root SSH login and SSH password authentication; and enables fail2ban and nginx. The migration must preserve the exact site names, paths, ports, security settings, certificate behavior, and service notifications.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; site logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: SSL-enabled nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; site logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: SSL-enabled nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; site logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`

Security namespaces configure fail2ban, UFW, and SSH directly rather than through a recipe loop:

- **fail2ban**: Enabled
- **ufw**: Enabled with default-deny policy and SSH, HTTP, and HTTPS allowed
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

No custom-resource provider is used by the execution tree.

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
```text
```

The recipes deploy `cookbook_file` resources for the following site index pages, but no static files are listed in the supplied cookbook file inventory:

```text
test/index.html
ci/index.html
status/index.html
```

The Ansible migration must provide these files through the role or an equivalent file source.

## Module Explanation

The cookbook performs operations in this order.

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Preserve this execution order because later configuration depends on packages, directories, certificates, and services prepared by earlier recipes.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures fail2ban defaults: ban time `3600`, find time `600`, maximum retries `3`, and backend `auto`.
   - Enables the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Configures UFW with default incoming policy `deny` and allows SSH, HTTP, and HTTPS.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies reverse-path filtering, disabled redirects and source routing, martian logging, ICMP restrictions, disabled IPv6, SYN flood protection, and TCP backlog/retry settings.
   - Reloads sysctl settings with `sysctl -p /etc/sysctl.d/99-security.conf` when the sysctl template changes.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` when root-login disabling is enabled.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` when password authentication is disabled.
   - Restarts `ssh` only when either SSH setting changes; distributions using `sshd` require service-name validation.
   - Resource counts: `package` (1), `service` (2), `template` (2), `execute` (8), for a total of `13` resource declarations.
   - Execute resources are `ufw_default_deny`, `ufw_allow_ssh`, `ufw_allow_http`, `ufw_allow_https`, `ufw_enable`, `reload_sysctl`, `disable root login`, and `disable password auth`.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the exact package `nginx`.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures worker user `www-data`, automatic worker processes, `/run/nginx.pid`, `768` worker connections, sendfile, TCP optimizations, keepalive timeout `65`, MIME types, access and error logs, gzip, and the `conf.d` and `sites-enabled` includes.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures `server_tokens off`, request-rate zones for `login` (`10m`, `10r/m`) and `api` (`10m`, `30r/m`), small buffers, `client_max_body_size 1k`, timeouts of `10`, TLS session settings, TLS 1.2 and TLS 1.3, the configured cipher list, and preferred server ciphers.
   - Enables and starts nginx; configuration changes notify an nginx reload.
   - Creates `/opt/server/test`, owned by `www-data:www-data` with mode `0755`, and deploys `test/index.html` to `/opt/server/test/index.html`, owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/ci`, owned by `www-data:www-data` with mode `0755`, and deploys `ci/index.html` to `/opt/server/ci/index.html`, owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/status`, owned by `www-data:www-data` with mode `0755`, and deploys `status/index.html` to `/opt/server/status/index.html`, owned by `www-data:www-data` with mode `0644`.
   - The `www-data` account and group are platform prerequisites; no `group[www-data]` Chef resource is present in the analyzed execution tree.
   - Resource counts: `package` (1), `template` (2), `service` (1), `directory` (3), and `cookbook_file` (3).

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` owned by `root:root` with mode `0755`.
   - Creates `/etc/ssl/private` owned by `root:ssl-cert` with mode `0710`.
   - Generates a self-signed certificate and private key for `test.cluster.local`:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Key: `/etc/ssl/private/test.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-test.cluster.local]`
   - Generates a self-signed certificate and private key for `ci.cluster.local`:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Key: `/etc/ssl/private/ci.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-ci.cluster.local]`
   - Generates a self-signed certificate and private key for `status.cluster.local`:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Key: `/etc/ssl/private/status.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-status.cluster.local]`
   - Generates certificates with OpenSSL using RSA 2048-bit keys and a 365-day validity period.
   - Uses certificate subjects with the corresponding site name as the common name and `admin@example.com` as certificate metadata.
   - Skips generation when both the certificate and key already exist.
   - Sets private-key mode `0640` and ownership `root:ssl-cert`.
   - Delayed certificate changes notify an nginx reload.
   - Resource counts: `package` (1), `group` (1), `directory` (2), and `execute` (3).

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` once for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` linking to `/etc/nginx/sites-available/test.cluster.local`.
   - Uses document root `/opt/server/test`, SSL enabled, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
   - Renders the same template once for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` linking to `/etc/nginx/sites-available/ci.cluster.local`.
   - Uses document root `/opt/server/ci`, SSL enabled, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
   - Renders the same template once for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` linking to `/etc/nginx/sites-available/status.cluster.local`.
   - Uses document root `/opt/server/status`, SSL enabled, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
   - Each site configuration contains an HTTP listener on port `80`, an HTTP-to-HTTPS redirect, an HTTPS HTTP/2 listener on port `443`, TLS 1.2 and TLS 1.3, the configured cipher list, HSTS and security headers, gzip, `try_files $uri $uri/ =404`, and restrictions on `.htaccess`, `.git`, and `.svn`.
   - Site render iterations are explicitly `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; total `site.conf.erb` render count is `3`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Resource counts: `template` (3), `link` (3), and `file` (1).

The referenced site definitions, SSL settings, document roots, paths, and SSH attributes must be verified against `cookbooks/nginx-multisite/attributes/default.rb`, because the supplied structured analysis does not include its contents.

## Dependencies

**External cookbook dependencies**: None identified in `metadata.rb`.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`.

**Service dependencies**:

- `fail2ban`: Enabled and started; restarted when `/etc/fail2ban/jail.local` changes.
- `nginx`: Enabled and started; reloaded when global nginx configuration, security configuration, certificates, site templates, site links, or the default site changes.
- `ssh`: Restarted when SSH hardening settings change. Validate whether the target platform uses `ssh` or `sshd`.

**Platform metadata**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

Validate UFW availability, nginx package behavior, and service naming on the target operating system.

## Credentials

**Detection Summary**: No credentials or secret-management integrations were detected in the analyzed execution tree. The attributes file requires additional inspection before the absence of hardcoded secrets can be considered fully validated.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

### Self-Signed Certificate Metadata
- **Variable(s)**: Certificate subject values generated by the SSL recipe
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced attributes require verification in `cookbooks/nginx-multisite/attributes/default.rb`
- **Current storage**: Locally generated certificates and private keys
- **Usage context**: The static email address `admin@example.com` is certificate subject metadata, not an authentication credential. Certificates are self-signed and are not retrieved from a certificate authority.

No `data_bag_item`, encrypted data bag, Chef Vault, Conjur, CyberArk, Vault, environment-variable secret, password, token, or API-key integration was identified. Confirm the contents of `cookbooks/nginx-multisite/attributes/default.rb` before final credential validation.

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
/etc/ssl/private/test.cluster.local.key
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/status.cluster.local.key
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/nginx/test.cluster.local_access.log
/var/log/nginx/test.cluster.local_error.log
/var/log/nginx/ci.cluster.local_access.log
/var/log/nginx/ci.cluster.local_error.log
/var/log/nginx/status.cluster.local_access.log
/var/log/nginx/status.cluster.local_error.log
```

Confirm that `/etc/nginx/sites-enabled/default` does not exist.

**Service endpoints to check**:

- `test.cluster.local`: HTTP `80`, HTTPS `443`
- `ci.cluster.local`: HTTP `80`, HTTPS `443`
- `status.cluster.local`: HTTP `80`, HTTPS `443`
- Unix sockets: None configured
- Network binding: nginx listens on all applicable interfaces through ports `80` and `443`

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: `1` render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: `1` render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: `1` render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: `1` render

**Total template render operations**: `7`.

## Pre-flight checks

```bash
# Confirm required packages and services
dpkg-query -W nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
  rpm -q nginx fail2ban ufw openssl ca-certificates

systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status ssh || systemctl status sshd

# Validate fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
grep -E 'bantime|findtime|maxretry|backend|enabled|port|logpath' \
  /etc/fail2ban/jail.local

# Validate UFW
ufw status verbose
ufw status | grep -E '22/tcp|80/tcp|443/tcp'

# Validate kernel settings
sysctl net.ipv4.conf.default.rp_filter
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv6.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog

# Validate SSH hardening
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
sshd -t

# Validate nginx
nginx -t
nginx -T | grep -E 'server_name|listen|ssl_certificate|ssl_certificate_key'
test ! -e /etc/nginx/sites-enabled/default

# Validate listeners
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN
```

Expected results:

- `fail2ban` and `nginx` are enabled and active.
- SSH is active under the platform’s correct service name.
- UFW is active with default incoming policy `deny`.
- UFW allows SSH, HTTP, and HTTPS.
- Required sysctl values include:
  - `net.ipv4.conf.default.rp_filter = 1`
  - `net.ipv4.conf.all.rp_filter = 1`
  - `net.ipv4.conf.all.accept_redirects = 0`
  - `net.ipv6.conf.all.accept_redirects = 0`
  - `net.ipv4.conf.all.send_redirects = 0`
  - `net.ipv4.conf.all.accept_source_route = 0`
  - `net.ipv6.conf.all.disable_ipv6 = 1`
  - `net.ipv4.icmp_echo_ignore_all = 1`
  - `net.ipv4.tcp_syncookies = 1`
  - `net.ipv4.tcp_max_syn_backlog = 2048`
- SSH configuration validation succeeds.
- `nginx -t` succeeds.
- nginx listens on TCP ports `80` and `443`.
- The default nginx site is absent.

### `test.cluster.local`

```bash
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key

curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G' /etc/ssl/private/test.cluster.local.key
```

Expected results:

- HTTP returns a `301` redirect to HTTPS.
- HTTPS returns a successful response, normally `200 OK`.
- The certificate subject contains `CN=test.cluster.local`.
- The private key reports `640 root ssl-cert`.

### `ci.cluster.local`

```bash
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key

curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G' /etc/ssl/private/ci.cluster.local.key
```

Expected results:

- HTTP returns a `301` redirect to HTTPS.
- HTTPS returns a successful response, normally `200 OK`.
- The certificate subject contains `CN=ci.cluster.local`.
- The private key reports `640 root ssl-cert`.

### `status.cluster.local`

```bash
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key

curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G' /etc/ssl/private/status.cluster.local.key
```

Expected results:

- HTTP returns a `301` redirect to HTTPS.
- HTTPS returns a successful response, normally `200 OK`.
- The certificate subject contains `CN=status.cluster.local`.
- The private key reports `640 root ssl-cert`.

### Site log checks

```bash
test -f /var/log/nginx/test.cluster.local_access.log
test -f /var/log/nginx/test.cluster.local_error.log
test -f /var/log/nginx/ci.cluster.local_access.log
test -f /var/log/nginx/ci.cluster.local_error.log
test -f /var/log/nginx/status.cluster.local_access.log
test -f /var/log/nginx/status.cluster.local_error.log

tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/test.cluster.local_error.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_error.log
tail -20 /var/log/nginx/status.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_error.log
```