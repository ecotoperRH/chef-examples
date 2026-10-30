---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures nginx with three SSL-enabled virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs nginx, fail2ban, UFW, OpenSSL, and CA certificates; creates site document roots and self-signed RSA certificates; deploys nginx, security, fail2ban, sysctl, SSH, and virtual-host configuration; enables HTTP-to-HTTPS redirects; applies security headers and TLS settings; enables fail2ban and UFW; hardens kernel networking; and disables SSH root login and password authentication. Attribute values, template contents, and complete credential-scan results require manual verification because structured analysis for those files was not supplied.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**: 3 nginx virtual hosts

### `test.cluster.local`

- **Purpose**: Static HTTPS site
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2; HSTS; security headers; gzip; `try_files`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Static content source: `test/index.html`
  - Access log: `/var/log/nginx/test.cluster.local_access.log`
  - Error log: `/var/log/nginx/test.cluster.local_error.log`

### `ci.cluster.local`

- **Purpose**: Static HTTPS site
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2; HSTS; security headers; gzip; `try_files`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Static content source: `ci/index.html`
  - Access log: `/var/log/nginx/ci.cluster.local_access.log`
  - Error log: `/var/log/nginx/ci.cluster.local_error.log`

### `status.cluster.local`

- **Purpose**: Static HTTPS site
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; HTTP redirects to HTTPS; HTTP/2; HSTS; security headers; gzip; `try_files`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Static content source: `status/index.html`
  - Access log: `/var/log/nginx/status.cluster.local_access.log`
  - Error log: `/var/log/nginx/status.cluster.local_error.log`

### Security services

- **fail2ban**
  - Enabled: `true`
  - Package: `fail2ban`
  - Service action: enable and start
  - Configuration: `/etc/fail2ban/jail.local`

- **ufw**
  - Enabled: `true`
  - Package: `ufw`
  - Default policy: deny
  - Allowed services: SSH, HTTP, HTTPS
  - Firewall action: enable

- **ssh**
  - Root login disabled: `true`
  - Password authentication disabled: `true`
  - Configuration file: `/etc/ssh/sshd_config`
  - Restart behavior: delayed restart when either SSH setting changes

## File Structure

```text
cookbooks/nginx-multisite/
├── attributes/
│   └── default.rb
├── files/
│   └── No static files listed
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── templates/
│   └── default/
│       ├── fail2ban.jail.local.erb
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       └── sysctl-security.conf.erb
└── providers/
    └── No provider files
```

The recipes reference `test/index.html`, `ci/index.html`, and `status/index.html` as `cookbook_file` sources, but those files were not present in the supplied directory listing.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Preserves the dependency order required for security packages, nginx installation, certificates, document roots, and virtual-host activation.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures fail2ban with bantime `3600`, findtime `600`, default max retries `3`, SSH protection on `ssh` using `/var/log/auth.log`, nginx authentication protection on `http,https`, nginx request-rate protection with max retries `10`, and nginx bot-search protection with max retries `2`.
   - Delays a fail2ban restart when `/etc/fail2ban/jail.local` changes.
   - Applies UFW default deny policy.
   - Allows SSH on `22/tcp`.
   - Allows HTTP on `80/tcp`.
   - Allows HTTPS on `443/tcp`.
   - Enables UFW.
   - Preserves guards that avoid repeating already-applied UFW configuration.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Configures reverse-path filtering, redirect and source-route rejection, martian logging, ICMP suppression, IPv6 disablement, SYN cookies, TCP backlog, and retry settings.
   - Delays `sysctl -p /etc/sysctl.d/99-security.conf` when the sysctl template changes.
   - Changes `PermitRootLogin` to `no` in `/etc/ssh/sshd_config` when not already configured.
   - Changes `PasswordAuthentication` to `no` in `/etc/ssh/sshd_config` when not already configured.
   - Delays an `ssh` service restart when either SSH setting changes.
   - Declares the `ssh` service as a notification target with action `nothing`.
   - Resource summary: one package resource installing two packages, two service resources, two templates, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures worker user `www-data`, automatic worker processes, PID `/run/nginx.pid`, `768` worker connections, standard access and error logs, gzip, module inclusion, `conf.d` inclusion, virtual-host inclusion, and keepalive timeout `65`.
   - Delays an nginx reload when the main configuration changes.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures `server_tokens off`, `login` and `api` rate-limit zones, restrictive client buffers and timeouts, maximum body size `1k`, TLS `1.2` and `1.3`, SSL session caching, a `10m` SSL session timeout, the configured ECDHE/DHE cipher list, and preferred server ciphers.
   - Delays an nginx reload when the security configuration changes.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` owned by `www-data:www-data` with mode `0755`.
   - Deploys `test/index.html` to `/opt/server/test/index.html` owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/ci` owned by `www-data:www-data` with mode `0755`.
   - Deploys `ci/index.html` to `/opt/server/ci/index.html` owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/status` owned by `www-data:www-data` with mode `0755`.
   - Deploys `status/index.html` to `/opt/server/status/index.html` owned by `www-data:www-data` with mode `0644`.
   - Iterations: three directory and static-file iterations, explicitly for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
   - Resource summary: one package, two templates, one service, three directories, and three cookbook files.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` owned by `root:root` with mode `0755`.
   - Creates `/etc/ssl/private` owned by `root:ssl-cert` with mode `0710`.
   - Generates a self-signed RSA 2048 certificate for `test.cluster.local` at `/etc/ssl/certs/test.cluster.local.crt` and key at `/etc/ssl/private/test.cluster.local.key`.
   - Generates a self-signed RSA 2048 certificate for `ci.cluster.local` at `/etc/ssl/certs/ci.cluster.local.crt` and key at `/etc/ssl/private/ci.cluster.local.key`.
   - Generates a self-signed RSA 2048 certificate for `status.cluster.local` at `/etc/ssl/certs/status.cluster.local.crt` and key at `/etc/ssl/private/status.cluster.local.key`.
   - Uses 365-day validity and certificate subject metadata including `US`, `Example`, `Example Org`, `IT`, and `admin@example.com` where specified.
   - Runs certificate generation only when the corresponding certificate and key do not both exist.
   - Applies mode `0640` and ownership `root:ssl-cert` to all three private keys.
   - Delays an nginx reload after each certificate-generation command.
   - Iterations: three certificate iterations, explicitly for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
   - Resource summary: one package resource installing two packages, two directory resources, one group resource, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to the test site configuration.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to the CI site configuration.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to the status site configuration.
   - Delays nginx reloads when the site templates or links change.
   - Removes `/etc/nginx/sites-enabled/default` and delays an nginx reload when it is removed.
   - Uses document roots `/opt/server/test`, `/opt/server/ci`, and `/opt/server/status`.
   - Uses the matching site-specific certificates and private keys.
   - Configures HTTP port `80`, HTTP-to-HTTPS redirection, HTTPS port `443`, HTTP/2, TLS 1.2 and 1.3, HSTS, security headers, gzip, `try_files`, protected `.htaccess`, `.git`, and `.svn` paths, and site-specific access and error logs.
   - Iterations: three virtual-host iterations, explicitly for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
   - Resource summary: three templates, three links, and one file resource.

Template contents, rendered values, modes, and notification relationships should be manually verified because structured template analysis was not supplied.

## Dependencies

**External cookbook dependencies**: None declared in the supplied metadata.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`

**Service dependencies**: `fail2ban`, `nginx`, and `ssh` (SSH is restarted only through delayed notifications when hardening changes).

**Required system users and groups**: Existing `www-data` user and group; existing `root` user and group; created `ssl-cert` group.

**Supported operating systems from metadata**: Ubuntu `>= 18.04`; CentOS `>= 7.0`.

UFW, `/var/log/auth.log`, Debian-style nginx paths, and the `ssh` service name require validation on CentOS.

## Credentials

**Detection Summary**: 0 application credentials reported across the supplied cookbook analysis; complete scanning of recipes, templates, and attributes was not included and requires verification.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

### Self-signed TLS private keys

- **Variable(s)**: `key_file`; `/etc/ssl/private/test.cluster.local.key`; `/etc/ssl/private/ci.cluster.local.key`; `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: nginx HTTPS private keys
- **Generation**: OpenSSL RSA 2048 self-signed certificate commands
- **Permissions**: Mode `0640`, owner `root`, group `ssl-cert`

### Certificate subject email

- **Variable(s)**: `admin@example.com`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded non-secret certificate subject metadata
- **Usage context**: Certificate subject email
- **Security classification**: Not a password, token, or authentication secret

No data bags, vault references, external secret-manager integrations, database connection strings, environment-variable secrets, or hardcoded passwords were reported. Complete verification requires credential analysis of `recipes/*.rb`, `templates/default/*.erb`, and `attributes/default.rb`.

## Checks for the Migration

**Files to verify**:

- `cookbooks/nginx-multisite/recipes/default.rb`
- `cookbooks/nginx-multisite/recipes/security.rb`
- `cookbooks/nginx-multisite/recipes/nginx.rb`
- `cookbooks/nginx-multisite/recipes/ssl.rb`
- `cookbooks/nginx-multisite/recipes/sites.rb`
- `cookbooks/nginx-multisite/attributes/default.rb`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/etc/nginx/sites-enabled/default` — should be absent
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

**Service endpoints to check**: HTTP `80`; HTTPS `443`; SSH `22`; nginx PID `/run/nginx.pid`; nginx worker user `www-data`

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render

`site.conf.erb` renders 3 times total.

## Pre-flight checks:

```bash
# Package verification
dpkg -l nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
rpm -q nginx fail2ban ufw openssl ca-certificates

# Service status
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status ssh || systemctl status sshd

# Configuration validation
nginx -t
nginx -T
grep -E 'user |worker_processes|worker_connections|access_log|error_log|gzip on|sites-enabled' \
  /etc/nginx/nginx.conf
grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols|ssl_ciphers' \
  /etc/nginx/conf.d/security.conf

# Security validation
fail2ban-client status
fail2ban-client status sshd
grep -E 'bantime|findtime|maxretry|enabled|logpath|port' /etc/fail2ban/jail.local
ufw status verbose
ufw status | grep -E '22/tcp|80/tcp|443/tcp'
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config

# Kernel validation
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies

# nginx process and listeners
cat /run/nginx.pid
ps aux | grep '[n]ginx'
ss -tlnp | grep ':80 '
ss -tlnp | grep ':443 '
test ! -e /etc/nginx/sites-enabled/default
```

### `test.cluster.local`

```bash
ls -ld /opt/server/test
ls -l /opt/server/test/index.html
stat -c '%U:%G %a %n' /opt/server/test /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -k -s --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | head
curl -k -s -D - -o /dev/null --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/ | grep -E \
  'HTTP/|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|Content-Security-Policy'
tail -n 20 /var/log/nginx/test.cluster.local_access.log
tail -n 20 /var/log/nginx/test.cluster.local_error.log
```

### `ci.cluster.local`

```bash
ls -ld /opt/server/ci
ls -l /opt/server/ci/index.html
stat -c '%U:%G %a %n' /opt/server/ci /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | head
curl -k -s -D - -o /dev/null --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/ | grep -E \
  'HTTP/|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|Content-Security-Policy'
tail -n 20 /var/log/nginx/ci.cluster.local_access.log
tail -n 20 /var/log/nginx/ci.cluster.local_error.log
```

### `status.cluster.local`

```bash
ls -ld /opt/server/status
ls -l /opt/server/status/index.html
stat -c '%U:%G %a %n' /opt/server/status /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -k -s --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | head
curl -k -s -D - -o /dev/null --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/ | grep -E \
  'HTTP/|Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options|Content-Security-Policy'
tail -n 20 /var/log/nginx/status.cluster.local_access.log
tail -n 20 /var/log/nginx/status.cluster.local_error.log
```

### TLS certificate and key pairing

```bash
openssl x509 -noout -modulus \
  -in /etc/ssl/certs/test.cluster.local.crt | openssl md5
openssl rsa -noout -modulus \
  -in /etc/ssl/private/test.cluster.local.key | openssl md5

openssl x509 -noout -modulus \
  -in /etc/ssl/certs/ci.cluster.local.crt | openssl md5
openssl rsa -noout -modulus \
  -in /etc/ssl/private/ci.cluster.local.key | openssl md5

openssl x509 -noout -modulus \
  -in /etc/ssl/certs/status.cluster.local.crt | openssl md5
openssl rsa -noout -modulus \
  -in /etc/ssl/private/status.cluster.local.key | openssl md5
```