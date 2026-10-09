---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an nginx web server hosting three HTTPS-enabled virtual sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs nginx, fail2ban, UFW, OpenSSL, and CA certificates; applies nginx and host security settings; generates self-signed TLS certificates; creates document roots and static content; configures SSH hardening and kernel network protections; removes the default nginx site; and enables HTTP-to-HTTPS redirects. The Ansible implementation must preserve the recipe order: security, nginx, SSL, then site configuration.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS-enabled static nginx virtual host
  - Location/Path: `/opt/server/test`
  - HTTP endpoint: port `80`
  - HTTPS endpoint: port `443`
  - SSL: enabled
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Site configuration: `/etc/nginx/sites-available/test.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/test.cluster.local`
  - Access log: `/var/log/nginx/test.cluster.local_access.log`
  - Error log: `/var/log/nginx/test.cluster.local_error.log`
  - Static content source: `test/index.html`
  - Static content destination: `/opt/server/test/index.html`

- **ci.cluster.local**: HTTPS-enabled static nginx virtual host
  - Location/Path: `/opt/server/ci`
  - HTTP endpoint: port `80`
  - HTTPS endpoint: port `443`
  - SSL: enabled
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Site configuration: `/etc/nginx/sites-available/ci.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/ci.cluster.local`
  - Access log: `/var/log/nginx/ci.cluster.local_access.log`
  - Error log: `/var/log/nginx/ci.cluster.local_error.log`
  - Static content source: `ci/index.html`
  - Static content destination: `/opt/server/ci/index.html`

- **status.cluster.local**: HTTPS-enabled static nginx virtual host
  - Location/Path: `/opt/server/status`
  - HTTP endpoint: port `80`
  - HTTPS endpoint: port `443`
  - SSL: enabled
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Site configuration: `/etc/nginx/sites-available/status.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/status.cluster.local`
  - Access log: `/var/log/nginx/status.cluster.local_access.log`
  - Error log: `/var/log/nginx/status.cluster.local_error.log`
  - Static content source: `status/index.html`
  - Static content destination: `/opt/server/status/index.html`

**Security configuration**:

- **fail2ban**
  - Enabled: `true`
  - Package: `fail2ban`
  - Service: `fail2ban`
  - Configuration: `/etc/fail2ban/jail.local`

- **ufw**
  - Enabled: `true`
  - Package: `ufw`
  - Default policy: deny
  - Allowed services: SSH, HTTP, and HTTPS

- **ssh**
  - Root login disabled: `true`
  - Password authentication disabled: `true`
  - Service resource: `ssh`

## File Structure

```text
cookbooks/nginx-multisite/
├── attributes/
│   └── default.rb
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── providers/
├── templates/
│   └── default/
│       ├── fail2ban.jail.local.erb
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       └── sysctl-security.conf.erb
└── files/
```

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

No provider files or custom-resource providers are used.

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

The recipes expect these logical `cookbook_file` sources:

- `test/index.html`
- `ci/index.html`
- `status/index.html`

These static source files are not present in the supplied directory listing and must be treated as expected input files without inventing additional cookbook paths.

## Module Explanation

The cookbook performs operations in this exact order from `cookbooks/nginx-multisite/recipes/default.rb`: security, nginx installation and document roots, SSL setup, and site virtual-host configuration.

### 1. Security (`cookbooks/nginx-multisite/recipes/security.rb`)

- Installs packages `fail2ban` and `ufw`.
- Enables and starts `service[fail2ban]`.
- Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`, notifying a delayed fail2ban restart.
- Configures fail2ban with:
  - Ban time: `3600` seconds
  - Find time: `600` seconds
  - Maximum retries: `3`
  - Backend: `auto`
  - Enabled jails: `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`
  - SSH log: `/var/log/auth.log`
  - Nginx error-log pattern: `/var/log/nginx/*error.log`
  - Nginx access-log pattern: `/var/log/nginx/*access.log`
- Applies UFW default deny policy and allows SSH, HTTP, and HTTPS.
- Enables UFW when it is not already active.
- Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`, notifying delayed execution of `reload_sysctl`.
- Reloads sysctl settings with `sysctl -p /etc/sysctl.d/99-security.conf`.
- Disables root SSH login when `node['security']['ssh']['disable_root']` is `true`.
- Disables SSH password authentication when `node['security']['ssh']['password_auth'] == false`.
- Restarts `service[ssh]` only when SSH configuration changes.

**Resources**:

- Package: `1` resource installing `fail2ban` and `ufw`
- Service: `2` resources, `fail2ban` and `ssh`
- Template: `2` resources
- Execute: `8` resources:
  - `ufw_default_deny`
  - `ufw_allow_ssh`
  - `ufw_allow_http`
  - `ufw_allow_https`
  - `ufw_enable`
  - `reload_sysctl`
  - `disable root login`
  - `disable password auth`
- No directory, file, link, or custom resources

### 2. Nginx Installation and Document Roots (`cookbooks/nginx-multisite/recipes/nginx.rb`)

- Installs package `nginx`.
- Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`, notifying a delayed nginx reload.
- Configures:
  - Worker user: `www-data`
  - Worker processes: `auto`
  - PID file: `/run/nginx.pid`
  - Worker connections: `768`
  - Access log: `/var/log/nginx/access.log`
  - Error log: `/var/log/nginx/error.log`
  - Keepalive timeout: `65`
  - Gzip
  - `/etc/nginx/conf.d/*.conf`
  - `/etc/nginx/sites-enabled/*`
- Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`, notifying a delayed nginx reload.
- Configures nginx security settings including `server_tokens off`, login and API rate zones, request-size restrictions, ten-second client and send timeouts, TLS 1.2 and 1.3, the configured cipher list, a shared `10m` SSL session cache, and a `10m` SSL session timeout.
- Enables and starts `service[nginx]`, which supports restart, reload, and status operations.

The site iteration expands as follows:

- **test.cluster.local**
  - Creates `/opt/server/test` recursively as `www-data:www-data`, mode `0755`.
  - Deploys `test/index.html` to `/opt/server/test/index.html` as `www-data:www-data`, mode `0644`.

- **ci.cluster.local**
  - Creates `/opt/server/ci` recursively as `www-data:www-data`, mode `0755`.
  - Deploys `ci/index.html` to `/opt/server/ci/index.html` as `www-data:www-data`, mode `0644`.

- **status.cluster.local**
  - Creates `/opt/server/status` recursively as `www-data:www-data`, mode `0755`.
  - Deploys `status/index.html` to `/opt/server/status/index.html` as `www-data:www-data`, mode `0644`.

**Resources**:

- Package: `1`
- Template: `2`
- Service: `1`
- Directory: `3`
- Cookbook file: `3`
- Site iterations: `3`

### 3. SSL Setup (`cookbooks/nginx-multisite/recipes/ssl.rb`)

- Installs packages `openssl` and `ca-certificates`.
- Creates group `ssl-cert`.
- Creates `/etc/ssl/certs` as `root:root`, mode `0755`.
- Creates `/etc/ssl/private` as `root:ssl-cert`, mode `0710`.
- Generates 2048-bit RSA, 365-day, self-signed certificates only when the corresponding certificate and key do not both exist.
- Generated private keys are owned by `root:ssl-cert`, mode `0640`.
- Certificate generation notifies a delayed nginx reload.

The SSL iteration expands as follows:

- **test.cluster.local**
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Key: `/etc/ssl/private/test.cluster.local.key`
  - Subject common name: `test.cluster.local`
  - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`

- **ci.cluster.local**
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Key: `/etc/ssl/private/ci.cluster.local.key`
  - Subject common name: `ci.cluster.local`
  - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`

- **status.cluster.local**
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Key: `/etc/ssl/private/status.cluster.local.key`
  - Subject common name: `status.cluster.local`
  - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`

**Resources**:

- Package: `1` resource installing `openssl` and `ca-certificates`
- Group: `1`
- Directory: `2`
- Execute: `3`
- SSL iterations: `3`

### 4. Site Virtual Hosts (`cookbooks/nginx-multisite/recipes/sites.rb`)

The recipe runs after SSL generation and renders `cookbooks/nginx-multisite/templates/default/site.conf.erb`.

The site iteration expands as follows:

- **test.cluster.local**
  - Destination: `/etc/nginx/sites-available/test.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/test.cluster.local`
  - Link target: `/etc/nginx/sites-available/test.cluster.local`
  - Document root: `/opt/server/test`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Key: `/etc/ssl/private/test.cluster.local.key`
  - Mode: `0644`

- **ci.cluster.local**
  - Destination: `/etc/nginx/sites-available/ci.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/ci.cluster.local`
  - Link target: `/etc/nginx/sites-available/ci.cluster.local`
  - Document root: `/opt/server/ci`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Key: `/etc/ssl/private/ci.cluster.local.key`
  - Mode: `0644`

- **status.cluster.local**
  - Destination: `/etc/nginx/sites-available/status.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/status.cluster.local`
  - Link target: `/etc/nginx/sites-available/status.cluster.local`
  - Document root: `/opt/server/status`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Key: `/etc/ssl/private/status.cluster.local.key`
  - Mode: `0644`

Each rendered virtual host contains:

- HTTP listener on port `80`
- HTTP-to-HTTPS redirect
- HTTPS listener on port `443`
- HTTP/2
- Site-specific document root
- TLS certificate and key paths
- TLS 1.2 and TLS 1.3
- One-year HSTS with `includeSubDomains`
- `X-Frame-Options DENY`
- `X-Content-Type-Options nosniff`
- `X-XSS-Protection`
- `Referrer-Policy`
- Content Security Policy
- Gzip compression
- Static-file `try_files`
- Denial of `.htaccess`, `.git`, and `.svn`
- Site-specific access and error logs

The recipe also deletes `/etc/nginx/sites-enabled/default` and notifies a delayed nginx reload.

**Resources**:

- Template: `3`
- Link: `3`
- File deletion: `1`
- Site iterations: `3`

## Dependencies

**External cookbook dependencies**: None shown in the supplied metadata and execution tree.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: restartable through delayed notifications; not started or enabled by this cookbook

**Operating system metadata**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

The recipes use Debian/Ubuntu-oriented paths and service names, including `/etc/ufw`, `/etc/ssh/sshd_config`, `/var/log/auth.log`, `www-data`, `sites-available`, and `sites-enabled`. The Ansible role must verify platform-specific equivalents before claiming CentOS parity.

## Credentials

**Detection Summary**: No passwords, API tokens, data bags, vault lookups, database credentials, or environment-variable secrets were detected. Self-signed TLS private keys are generated locally and must be protected as sensitive material.

**Source**:

- **Provider**: None detected
- **URL**: Not applicable
- **Path**: Not applicable

### Self-Signed TLS Material

- **Variable(s)**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/certs/status.cluster.local.crt`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Generated locally by an `openssl req -x509` command
- **Usage context**: nginx TLS certificates and private keys
- **Protection**:
  - Private-key directory: `root:ssl-cert`, mode `0710`
  - Private keys: `root:ssl-cert`, mode `0640`
- **Migration behavior**: Certificate generation is skipped when both the certificate and key already exist. Ansible must preserve this idempotent condition.

The certificate subject includes `admin@example.com` as metadata; it is not an authentication credential.

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

**Expected ownership and modes**:

- Document roots: `www-data:www-data`, mode `0755`
- Static index files: `www-data:www-data`, mode `0644`
- Certificate directory: `root:root`, mode `0755`
- Private-key directory: `root:ssl-cert`, mode `0710`
- Private keys: `root:ssl-cert`, mode `0640`
- Nginx configuration files: mode `0644`

**Service endpoints to check**:

- HTTP: port `80`
- HTTPS: port `443`
- SSH: port `22`
- Unix socket: none configured

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: `1` render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: `1` render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: `1` render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: `1` render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: `1` render
- `site.conf.erb` total: `3` renders

## Pre-flight checks

```bash
# Service status
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Validate nginx configuration
nginx -t
nginx -T | grep -E 'test\.cluster\.local|ci\.cluster\.local|status\.cluster\.local'

# Verify listening ports
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

# Verify firewall rules
ufw status verbose
ufw status | grep '22/tcp'
ufw status | grep '80/tcp'
ufw status | grep '443/tcp'

# Verify SSH and kernel security
grep -E 'PermitRootLogin no' /etc/ssh/sshd_config
grep -E 'PasswordAuthentication no' /etc/ssh/sshd_config
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv6.conf.all.disable_ipv6

# Verify fail2ban jails
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Verify default site removal
test ! -e /etc/nginx/sites-enabled/default

# Verify test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates

# Verify ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates

# Verify status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

# Confirm HTTP redirects
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/

# Expected: HTTP returns 301 with a Location header beginning with https://

# Confirm HTTPS security headers
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Expected headers:
# Strict-Transport-Security
# X-Frame-Options
# X-Content-Type-Options
# Referrer-Policy

# Verify logs
test -f /var/log/nginx/access.log
test -f /var/log/nginx/error.log
test -f /var/log/nginx/test.cluster.local_access.log
test -f /var/log/nginx/test.cluster.local_error.log
test -f /var/log/nginx/ci.cluster.local_access.log
test -f /var/log/nginx/ci.cluster.local_error.log
test -f /var/log/nginx/status.cluster.local_access.log
test -f /var/log/nginx/status.cluster.local_error.log
test -f /var/log/auth.log

# Inspect logs
journalctl -u nginx --no-pager -n 50
journalctl -u fail2ban --no-pager -n 50
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log

# Verify certificate and key permissions
stat -c '%U:%G %a %n' /etc/ssl/certs/test.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/certs/ci.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/certs/status.cluster.local.crt
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
```

The Ansible role must preserve idempotency for UFW rules, SSH hardening, sysctl reloads, certificate generation, nginx reloads, and deletion of `/etc/nginx/sites-enabled/default`.