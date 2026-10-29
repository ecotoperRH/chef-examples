---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: Configures an Nginx web server hosting three SSL-enabled virtual host sites (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`) with HTTP-to-HTTPS redirection, automated OpenSSL self-signed certificate generation, static web content deployment, and system security hardening via UFW firewall rules, Fail2ban jail policies, SSH daemon hardening, and kernel sysctl network parameters.

## Service Type and Instances

**Service Type**: Web Server (Nginx) and Security Services (Fail2ban, UFW)

**Configured Instances**:
- **test.cluster.local**: Virtual host site
  - Location/Path: Document root `/opt/server/test`
  - Port/Socket: Port 80 (HTTP redirect to HTTPS) and Port 443 (HTTPS / HTTP2)
  - Key Config: `ssl_enabled: true`, SSL certificate `/etc/ssl/certs/test.cluster.local.crt`, SSL private key `/etc/ssl/private/test.cluster.local.key`, virtual host config `/etc/nginx/sites-available/test.cluster.local`, enabled symlink `/etc/nginx/sites-enabled/test.cluster.local`, static index file deployed from `files/default/test/index.html` to `/opt/server/test/index.html`

- **ci.cluster.local**: Virtual host site
  - Location/Path: Document root `/opt/server/ci`
  - Port/Socket: Port 80 (HTTP redirect to HTTPS) and Port 443 (HTTPS / HTTP2)
  - Key Config: `ssl_enabled: true`, SSL certificate `/etc/ssl/certs/ci.cluster.local.crt`, SSL private key `/etc/ssl/private/ci.cluster.local.key`, virtual host config `/etc/nginx/sites-available/ci.cluster.local`, enabled symlink `/etc/nginx/sites-enabled/ci.cluster.local`, static index file deployed from `files/default/ci/index.html` to `/opt/server/ci/index.html`

- **status.cluster.local**: Virtual host site
  - Location/Path: Document root `/opt/server/status`
  - Port/Socket: Port 80 (HTTP redirect to HTTPS) and Port 443 (HTTPS / HTTP2)
  - Key Config: `ssl_enabled: true`, SSL certificate `/etc/ssl/certs/status.cluster.local.crt`, SSL private key `/etc/ssl/private/status.cluster.local.key`, virtual host config `/etc/nginx/sites-available/status.cluster.local`, enabled symlink `/etc/nginx/sites-enabled/status.cluster.local`, static index file deployed from `files/default/status/index.html` to `/opt/server/status/index.html`

## File Structure

**Recipes:**
```
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```

**Providers:**
```
```

**Templates:**
```
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/sysctl-security.conf.erb
```

**Attributes:**
```
attributes/default.rb
```

**Files:**
```
files/default/test/index.html
files/default/ci/index.html
files/default/status/index.html
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Acts as the entrypoint orchestrator.
   - Includes recipes in sequence:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Resources: include_recipe (4)

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs system security packages: `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Deploys Fail2ban jail settings to `/etc/fail2ban/jail.local`:
     - Template: `templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (mode: `0644`, notifies restart `service[fail2ban]` delayed). Configures jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`.
   - Configures UFW firewall rules via execute commands:
     - Sets default incoming policy to deny: `ufw --force default deny` (guard: `ufw status | grep -q "Default: deny"`)
     - Opens SSH: `ufw allow ssh` (guard: `ufw status | grep -q "22/tcp"`)
     - Opens HTTP: `ufw allow http` (guard: `ufw status | grep -q "80/tcp"`)
     - Opens HTTPS: `ufw allow https` (guard: `ufw status | grep -q "443/tcp"`)
     - Activates firewall: `ufw --force enable` (guard: `ufw status | grep -q "Status: active"`)
   - Deploys kernel network security parameters via sysctl:
     - Template: `templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (mode: `0644`, notifies run `execute[reload_sysctl]` delayed). Sets reverse-path filtering, disables ICMP redirects/source routing, enables martian logging, ignores ping broadcasts, disables IPv6, and enables TCP SYN cookies.
     - Execute resource `reload_sysctl`: runs `sysctl -p /etc/sysctl.d/99-security.conf` (action: `:nothing`).
   - Hardens SSH daemon configuration in `/etc/ssh/sshd_config`:
     - If `node['security']['ssh']['disable_root']` is true: runs sed to set `PermitRootLogin no` (guard: `grep -q '^PermitRootLogin no' /etc/ssh/sshd_config`, notifies restart `service[ssh]` delayed).
     - If `node['security']['ssh']['password_auth'] == false`: runs sed to set `PasswordAuthentication no` (guard: `grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config`, notifies restart `service[ssh]` delayed).
     - Defines `service[ssh]` with action `:nothing` to receive restart notifications.
   - Resources: package (1), service (2), template (2), execute (8)

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` web server package.
   - Deploys core Nginx configuration:
     - Template: `templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf` (mode: `0644`, notifies reload `service[nginx]` delayed). Configures `worker_processes auto`, `worker_connections 768`, gzip compression, and virtual host include directives.
   - Deploys HTTP security and rate-limiting configuration:
     - Template: `templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf` (mode: `0644`, notifies reload `service[nginx]` delayed). Disables `server_tokens`, configures request rate limiting zones (`zone=login:10m rate=10r/m`, `zone=api:10m rate=30r/m`), sets client buffer/timeout sizes, and configures TLS protocols (`TLSv1.2 TLSv1.3`).
   - Enables and starts the `nginx` service (supports restart, reload, status).
   - Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
     - Site **test.cluster.local**:
       - Creates directory `/opt/server/test` (owner: `www-data`, group: `www-data`, mode: `0755`, recursive: `true`).
       - Deploys static HTML file `files/default/test/index.html` → `/opt/server/test/index.html` (owner: `www-data`, group: `www-data`, mode: `0644`).
     - Site **ci.cluster.local**:
       - Creates directory `/opt/server/ci` (owner: `www-data`, group: `www-data`, mode: `0755`, recursive: `true`).
       - Deploys static HTML file `files/default/ci/index.html` → `/opt/server/ci/index.html` (owner: `www-data`, group: `www-data`, mode: `0644`).
     - Site **status.cluster.local**:
       - Creates directory `/opt/server/status` (owner: `www-data`, group: `www-data`, mode: `0755`, recursive: `true`).
       - Deploys static HTML file `files/default/status/index.html` → `/opt/server/status/index.html` (owner: `www-data`, group: `www-data`, mode: `0644`).
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL utilities: `openssl` and `ca-certificates`.
   - Creates system group `ssl-cert`.
   - Creates directory `/etc/ssl/certs` (owner: `root`, group: `root`, mode: `0755`).
   - Creates directory `/etc/ssl/private` (owner: `root`, group: `ssl-cert`, mode: `0710`).
   - Iterations: Runs 3 times for SSL-enabled sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
     - Site **test.cluster.local**:
       - Generates a 2048-bit RSA private key and self-signed X.509 certificate via OpenSSL (execute `generate-ssl-cert-test.cluster.local`):
         - Key file: `/etc/ssl/private/test.cluster.local.key` (mode: `0640`, owner: `root:ssl-cert`)
         - Certificate: `/etc/ssl/certs/test.cluster.local.crt` (validity: 365 days, subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`)
         - Guard: `not_if { File.exist?('/etc/ssl/certs/test.cluster.local.crt') && File.exist?('/etc/ssl/private/test.cluster.local.key') }`
         - Notifies: reload `service[nginx]` delayed
     - Site **ci.cluster.local**:
       - Generates a 2048-bit RSA private key and self-signed X.509 certificate via OpenSSL (execute `generate-ssl-cert-ci.cluster.local`):
         - Key file: `/etc/ssl/private/ci.cluster.local.key` (mode: `0640`, owner: `root:ssl-cert`)
         - Certificate: `/etc/ssl/certs/ci.cluster.local.crt` (validity: 365 days, subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`)
         - Guard: `not_if { File.exist?('/etc/ssl/certs/ci.cluster.local.crt') && File.exist?('/etc/ssl/private/ci.cluster.local.key') }`
         - Notifies: reload `service[nginx]` delayed
     - Site **status.cluster.local**:
       - Generates a 2048-bit RSA private key and self-signed X.509 certificate via OpenSSL (execute `generate-ssl-cert-status.cluster.local`):
         - Key file: `/etc/ssl/private/status.cluster.local.key` (mode: `0640`, owner: `root:ssl-cert`)
         - Certificate: `/etc/ssl/certs/status.cluster.local.crt` (validity: 365 days, subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`)
         - Guard: `not_if { File.exist?('/etc/ssl/certs/status.cluster.local.crt') && File.exist?('/etc/ssl/private/status.cluster.local.key') }`
         - Notifies: reload `service[nginx]` delayed
   - Resources: package (1), group (1), directory (2), execute (3)

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations: Runs 3 times for sites: **test.cluster.local**, **ci.cluster.local**, **status.cluster.local**:
     - Site **test.cluster.local**:
       - Deploys virtual host config from `templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` (mode: `0644`, variables: `server_name: test.cluster.local`, `document_root: /opt/server/test`, `ssl_enabled: true`, `cert_file: /etc/ssl/certs/test.cluster.local.crt`, `key_file: /etc/ssl/private/test.cluster.local.key`, notifies reload `service[nginx]` delayed).
       - Creates symbolic link from `/etc/nginx/sites-available/test.cluster.local` to `/etc/nginx/sites-enabled/test.cluster.local` (notifies reload `service[nginx]` delayed).
     - Site **ci.cluster.local**:
       - Deploys virtual host config from `templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` (mode: `0644`, variables: `server_name: ci.cluster.local`, `document_root: /opt/server/ci`, `ssl_enabled: true`, `cert_file: /etc/ssl/certs/ci.cluster.local.crt`, `key_file: /etc/ssl/private/ci.cluster.local.key`, notifies reload `service[nginx]` delayed).
       - Creates symbolic link from `/etc/nginx/sites-available/ci.cluster.local` to `/etc/nginx/sites-enabled/ci.cluster.local` (notifies reload `service[nginx]` delayed).
     - Site **status.cluster.local**:
       - Deploys virtual host config from `templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` (mode: `0644`, variables: `server_name: status.cluster.local`, `document_root: /opt/server/status`, `ssl_enabled: true`, `cert_file: /etc/ssl/certs/status.cluster.local.crt`, `key_file: /etc/ssl/private/status.cluster.local.key`, notifies reload `service[nginx]` delayed).
       - Creates symbolic link from `/etc/nginx/sites-available/status.cluster.local` to `/etc/nginx/sites-enabled/status.cluster.local` (notifies reload `service[nginx]` delayed).
   - Deletes the default virtual host file `/etc/nginx/sites-enabled/default` (action: `:delete`, notifies reload `service[nginx]` delayed).
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (no external cookbooks declared in `metadata.rb`)
**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`
**Service dependencies**: `nginx` (systemd), `fail2ban` (systemd), `ssh` / `sshd` (systemd)

## Credentials

**Detection Summary**: 3 credentials detected across 1 file (`recipes/ssl.rb`)

**Source**:
  - **Provider**: Internal / Dynamically Generated on Target Node
  - **URL**: None
  - **Path**: `/etc/ssl/private/`

### SSL Private Key - test.cluster.local
- **Variable(s)**: `key_file = "#{node['nginx']['ssl']['private_key_path']}/test.cluster.local.key"`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated 2048-bit RSA private key on target filesystem (`/etc/ssl/private/test.cluster.local.key`, permissions `0640`, owner `root:ssl-cert`).
- **Usage context**: TLS termination for virtual host `test.cluster.local` on port 443.

### SSL Private Key - ci.cluster.local
- **Variable(s)**: `key_file = "#{node['nginx']['ssl']['private_key_path']}/ci.cluster.local.key"`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated 2048-bit RSA private key on target filesystem (`/etc/ssl/private/ci.cluster.local.key`, permissions `0640`, owner `root:ssl-cert`).
- **Usage context**: TLS termination for virtual host `ci.cluster.local` on port 443.

### SSL Private Key - status.cluster.local
- **Variable(s)**: `key_file = "#{node['nginx']['ssl']['private_key_path']}/status.cluster.local.key"`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated 2048-bit RSA private key on target filesystem (`/etc/ssl/private/status.cluster.local.key`, permissions `0640`, owner `root:ssl-cert`).
- **Usage context**: TLS termination for virtual host `status.cluster.local` on port 443.

## Checks for the Migration

**Files to verify**:
- Base configuration files:
  - `/etc/nginx/nginx.conf`
  - `/etc/nginx/conf.d/security.conf`
  - `/etc/fail2ban/jail.local`
  - `/etc/sysctl.d/99-security.conf`
  - `/etc/ssh/sshd_config`
- Site virtual host configuration files:
  - `/etc/nginx/sites-available/test.cluster.local`
  - `/etc/nginx/sites-available/ci.cluster.local`
  - `/etc/nginx/sites-available/status.cluster.local`
- Virtual host symbolic links:
  - `/etc/nginx/sites-enabled/test.cluster.local`
  - `/etc/nginx/sites-enabled/ci.cluster.local`
  - `/etc/nginx/sites-enabled/status.cluster.local`
  - Verification that `/etc/nginx/sites-enabled/default` is absent
- SSL certificates and private keys:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/certs/status.cluster.local.crt`
  - `/etc/ssl/private/status.cluster.local.key`
- Document roots and deployed static index files:
  - `/opt/server/test/index.html`
  - `/opt/server/ci/index.html`
  - `/opt/server/status/index.html`
- Log files:
  - `/var/log/nginx/access.log`
  - `/var/log/nginx/error.log`
  - `/var/log/nginx/test.cluster.local_access.log`
  - `/var/log/nginx/test.cluster.local_error.log`
  - `/var/log/nginx/ci.cluster.local_access.log`
  - `/var/log/nginx/ci.cluster.local_error.log`
  - `/var/log/nginx/status.cluster.local_access.log`
  - `/var/log/nginx/status.cluster.local_error.log`
  - `/var/log/fail2ban.log`

**Service endpoints to check**:
- Ports listening:
  - Port 22 (SSH)
  - Port 80 (HTTP)
  - Port 443 (HTTPS)
- Network interfaces: 0.0.0.0 (all interfaces)

**Templates rendered**:
- `templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (rendered 1 time)
- `templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf` (rendered 1 time)
- `templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf` (rendered 1 time)
- `templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (rendered 1 time)
- `templates/default/site.conf.erb` → rendered 3 times:
  - `/etc/nginx/sites-available/test.cluster.local`
  - `/etc/nginx/sites-available/ci.cluster.local`
  - `/etc/nginx/sites-available/status.cluster.local`

## Pre-flight checks:
```bash
# Service status checks
systemctl is-active nginx
systemctl status nginx --no-pager
systemctl is-active fail2ban
systemctl status fail2ban --no-pager
systemctl is-active ssh || systemctl is-active sshd

# Nginx configuration syntax check
nginx -t

# Firewall and security status
ufw status verbose
grep -E '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config

# Fail2ban jail status checks
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Sysctl kernel security parameters validation
sysctl net.ipv4.conf.all.rp_filter | grep " = 1"
sysctl net.ipv4.conf.all.accept_redirects | grep " = 0"
sysctl net.ipv4.tcp_syncookies | grep " = 1"
sysctl net.ipv4.icmp_echo_ignore_all | grep " = 1"
sysctl net.ipv6.conf.all.disable_ipv6 | grep " = 1"

# Network port listening verification
ss -tulpn | grep -E ':(80|443|22)\b'
lsof -i :80
lsof -i :443
lsof -i :22

# Virtual host symlinks verification
ls -la /etc/nginx/sites-enabled/test.cluster.local
ls -la /etc/nginx/sites-enabled/ci.cluster.local
ls -la /etc/nginx/sites-enabled/status.cluster.local
test ! -f /etc/nginx/sites-enabled/default && echo "Default virtual host is successfully removed"

# SSL Certificate validation - Site: test.cluster.local
test -s /etc/ssl/certs/test.cluster.local.crt
test -s /etc/ssl/private/test.cluster.local.key
ls -la /etc/ssl/private/test.cluster.local.key | grep "root ssl-cert"
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
openssl rsa -in /etc/ssl/private/test.cluster.local.key -check -noout

# SSL Certificate validation - Site: ci.cluster.local
test -s /etc/ssl/certs/ci.cluster.local.crt
test -s /etc/ssl/private/ci.cluster.local.key
ls -la /etc/ssl/private/ci.cluster.local.key | grep "root ssl-cert"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
openssl rsa -in /etc/ssl/private/ci.cluster.local.key -check -noout

# SSL Certificate validation - Site: status.cluster.local
test -s /etc/ssl/certs/status.cluster.local.crt
test -s /etc/ssl/private/status.cluster.local.key
ls -la /etc/ssl/private/status.cluster.local.key | grep "root ssl-cert"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
openssl rsa -in /etc/ssl/private/status.cluster.local.key -check -noout

# Document root and permissions verification
ls -ld /opt/server/test /opt/server/ci /opt/server/status
ls -la /opt/server/test/index.html | grep "www-data www-data"
ls -la /opt/server/ci/index.html | grep "www-data www-data"
ls -la /opt/server/status/index.html | grep "www-data www-data"

# Web endpoint checks - Site: test.cluster.local
curl -s -I -H "Host: test.cluster.local" http://127.0.0.1/ | grep -E 'HTTP/1.1 301|Location: https://test.cluster.local/'
curl -k -s -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep "HTTP/2 200"
curl -k -s -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E "Strict-Transport-Security|X-Frame-Options: DENY|X-Content-Type-Options: nosniff"
curl -k -s --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -q "Test"

# Web endpoint checks - Site: ci.cluster.local
curl -s -I -H "Host: ci.cluster.local" http://127.0.0.1/ | grep -E 'HTTP/1.1 301|Location: https://ci.cluster.local/'
curl -k -s -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep "HTTP/2 200"
curl -k -s -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E "Strict-Transport-Security|X-Frame-Options: DENY|X-Content-Type-Options: nosniff"
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -q "CI"

# Web endpoint checks - Site: status.cluster.local
curl -s -I -H "Host: status.cluster.local" http://127.0.0.1/ | grep -E 'HTTP/1.1 301|Location: https://status.cluster.local/'
curl -k -s -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep "HTTP/2 200"
curl -k -s -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E "Strict-Transport-Security|X-Frame-Options: DENY|X-Content-Type-Options: nosniff"
curl -k -s --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -q "Status"

# Log checks for errors
tail -n 30 /var/log/nginx/error.log
tail -n 30 /var/log/nginx/test.cluster.local_error.log
tail -n 30 /var/log/nginx/ci.cluster.local_error.log
tail -n 30 /var/log/nginx/status.cluster.local_error.log
tail -n 30 /var/log/fail2ban.log
```