---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and enables NGINX, configures SSL-enabled virtual hosts for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, creates document roots and site index files, generates a self-signed TLS certificate/key pair for each site, and applies host security configuration through Fail2ban, UFW, sysctl hardening, and SSH hardening. Each site redirects HTTP port 80 traffic to HTTPS port 443.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: Document root `/opt/server/test`; configuration `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: Document root `/opt/server/ci`; configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: Document root `/opt/server/status`; configuration `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`

## File Structure

```text
cookbooks/nginx-multisite/
├── attributes/
│   └── default.rb
└── recipes/
    ├── default.rb
    ├── security.rb
    ├── nginx.rb
    ├── ssl.rb
    └── sites.rb
```

**Providers:**
```text
None
```

**Templates:**
```text
Template source files were not included in the supplied file inventory. The analyzed recipes reference:
fail2ban.jail.local.erb
sysctl-security.conf.erb
nginx.conf.erb
security.conf.erb
site.conf.erb
```

**Files:**
```text
No deployed static source files were supplied in the directory listing. The nginx recipe references:
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
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures Fail2ban with a 3600-second ban time, 600-second find time, three retries, and the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Restarts Fail2ban when `/etc/fail2ban/jail.local` changes.
   - Sets the UFW default policy to deny incoming traffic.
   - Allows SSH on TCP/22, HTTP on TCP/80, and HTTPS on TCP/443.
   - Enables UFW.
   - Renders `sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies `/etc/sysctl.d/99-security.conf` using `sysctl -p /etc/sysctl.d/99-security.conf` when the file changes.
   - Configures `PermitRootLogin no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['disable_root']` is `true`.
   - Configures `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['password_auth']` is `false`.
   - Restarts the `ssh` service only when either SSH configuration setting changes.
   - Resources used: one package resource installing two packages, two service resources, two template resources, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Configures NGINX with user `www-data`, `worker_processes auto`, PID `/run/nginx.pid`, `worker_connections 768`, `keepalive_timeout 65`, global access log `/var/log/nginx/access.log`, global error log `/var/log/nginx/error.log`, and includes for `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Configures `server_tokens off`, login rate limiting at `10r/m`, API rate limiting at `30r/m`, `client_max_body_size 1k`, 10-second client timeouts, TLS 1.2 and TLS 1.3, shared TLS session cache `SSL:10m`, and TLS session timeout `10m`.
   - Enables and starts the `nginx` service.
   - Changes to either NGINX configuration file trigger an NGINX reload.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Resources used: one package resource, two template resources, one service resource, three directory resources, and three cookbook file resources.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner/group `root:ssl-cert` and mode `0710`.
   - Generates self-signed RSA-2048 certificates valid for 365 days when the certificate or key is absent.
   - Iterations:
     - **test.cluster.local**: Generates `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` with subject CN `test.cluster.local`; sets key mode `0640` and ownership `root:ssl-cert`.
     - **ci.cluster.local**: Generates `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` with subject CN `ci.cluster.local`; sets key mode `0640` and ownership `root:ssl-cert`.
     - **status.cluster.local**: Generates `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` with subject CN `status.cluster.local`; sets key mode `0640` and ownership `root:ssl-cert`.
   - Newly generated TLS material triggers an NGINX reload.
   - Certificate-generation pattern:
     ```bash
     openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout <key_file> \
       -out <cert_file> \
       -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com"
     chmod 640 <key_file>
     chown root:ssl-cert <key_file>
     ```
   - Resources used: one package resource installing two packages, one group resource, two directory resources, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `site.conf.erb` once for each configured site.
   - Iterations:
     - **test.cluster.local**: Renders `/etc/nginx/sites-available/test.cluster.local` with server name `test.cluster.local`, document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`; creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to `/etc/nginx/sites-available/test.cluster.local`.
     - **ci.cluster.local**: Renders `/etc/nginx/sites-available/ci.cluster.local` with server name `ci.cluster.local`, document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`; creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to `/etc/nginx/sites-available/ci.cluster.local`.
     - **status.cluster.local**: Renders `/etc/nginx/sites-available/status.cluster.local` with server name `status.cluster.local`, document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`; creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Template, enabled-link, and default-site deletion changes trigger an NGINX reload.
   - Each virtual host has an HTTP server block on port 80 that returns a 301 redirect to HTTPS and an HTTPS server block on port 443 using `ssl http2`.
   - Each HTTPS virtual host uses TLS 1.2 and TLS 1.3, HSTS with `max-age=31536000; includeSubDomains`, security headers, site-specific access and error logs, `try_files $uri $uri/ =404`, and access denial for `.htaccess`, `.git`, and `.svn`.
   - Resources used: three template resources, three link resources, and one file resource.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**: `fail2ban`, `ufw`, `nginx`, `openssl`, `ca-certificates`.

**Service dependencies**:
- `fail2ban`: Enabled and started; restarted when `/etc/fail2ban/jail.local` changes.
- `nginx`: Enabled and started; reloaded when NGINX configuration, TLS material, enabled-site links, or default-site deletion changes.
- `ssh`: Restarted only when `PermitRootLogin` or `PasswordAuthentication` configuration changes.
- `ufw`: Configured with default inbound deny and allow rules for TCP/22, TCP/80, and TCP/443.

Supported platforms are Ubuntu `>= 18.04` and CentOS `>= 7.0`. The use of UFW and SSH service name `ssh` is Ubuntu/Debian-oriented; an Ansible migration must branch by OS family or implement an equivalent CentOS firewall policy.

## Credentials

**Detection Summary**: 3 sensitive TLS private-key artifacts detected. No external secret manager, Chef Vault, encrypted data bag, data bag, password, API token, embedded database credential, or externally supplied private key was detected.

**Source**:
  - **Provider**: Internal locally generated self-signed TLS material
  - **URL**: Not applicable
  - **Path**: `/etc/ssl/private`

### test.cluster.local TLS Private Key
- **Variable(s)**: `node['nginx']['ssl']['private_key_path']`, `key_file`
- **Source file(s)**: `cookbooks/nginx-multisite/attributes/default.rb`, `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL at `/etc/ssl/private/test.cluster.local.key`
- **Usage context**: Private key for the `test.cluster.local` NGINX TLS listener; referenced by `ssl_certificate_key`.
- **Access protection**: Mode `0640`, owner `root`, group `ssl-cert`; parent directory mode `0710`, owner `root`, group `ssl-cert`.

### ci.cluster.local TLS Private Key
- **Variable(s)**: `node['nginx']['ssl']['private_key_path']`, `key_file`
- **Source file(s)**: `cookbooks/nginx-multisite/attributes/default.rb`, `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL at `/etc/ssl/private/ci.cluster.local.key`
- **Usage context**: Private key for the `ci.cluster.local` NGINX TLS listener; referenced by `ssl_certificate_key`.
- **Access protection**: Mode `0640`, owner `root`, group `ssl-cert`; parent directory mode `0710`, owner `root`, group `ssl-cert`.

### status.cluster.local TLS Private Key
- **Variable(s)**: `node['nginx']['ssl']['private_key_path']`, `key_file`
- **Source file(s)**: `cookbooks/nginx-multisite/attributes/default.rb`, `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL at `/etc/ssl/private/status.cluster.local.key`
- **Usage context**: Private key for the `status.cluster.local` NGINX TLS listener; referenced by `ssl_certificate_key`.
- **Access protection**: Mode `0640`, owner `root`, group `ssl-cert`; parent directory mode `0710`, owner `root`, group `ssl-cert`.

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
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/private/status.cluster.local.key
/opt/server/test/index.html
/opt/server/ci/index.html
/opt/server/status/index.html
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/nginx/test.cluster.local_access.log
/var/log/nginx/test.cluster.local_error.log
/var/log/nginx/ci.cluster.local_access.log
/var/log/nginx/ci.cluster.local_error.log
/var/log/nginx/status.cluster.local_access.log
/var/log/nginx/status.cluster.local_error.log
```

**Service endpoints to check**:
- NGINX HTTP: TCP/80
- NGINX HTTPS: TCP/443
- SSH: TCP/22
- No Unix socket is configured.
- NGINX does not specify an explicit listen address and uses normal wildcard binding behavior.

**Templates rendered**:
- `fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`: 1 render
- `sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`: 1 render
- `nginx.conf.erb` to `/etc/nginx/nginx.conf`: 1 render
- `security.conf.erb` to `/etc/nginx/conf.d/security.conf`: 1 render
- `site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`: 1 render

## Pre-flight checks:
```bash
# Package and service status
dpkg -l nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
  rpm -q nginx fail2ban openssl ca-certificates

systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl is-active ssh || systemctl is-active sshd

# SSH hardening and configuration validity
sshd -t
grep -E '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config
# Expected:
# PermitRootLogin no
# PasswordAuthentication no

# NGINX configuration and firewall validation
nginx -t
ufw status verbose
# Expected: active; default incoming policy deny; allow rules for 22/tcp, 80/tcp, and 443/tcp.

# Sysctl and Fail2ban validation
sysctl -p /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies
fail2ban-client -t
fail2ban-client status
fail2ban-client status sshd

# TLS material validation
stat -c '%a %U:%G %n' \
  /etc/ssl/private \
  /etc/ssl/private/test.cluster.local.key \
  /etc/ssl/private/ci.cluster.local.key \
  /etc/ssl/private/status.cluster.local.key

openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

# test.cluster.local
stat -c '%a %U:%G %n' /opt/server/test /opt/server/test/index.html
nginx -t
readlink -f /etc/nginx/sites-enabled/test.cluster.local
curl --resolve test.cluster.local:80:127.0.0.1 \
  -sS -o /dev/null -D - http://test.cluster.local/ | \
  grep -E '^HTTP/|^Location: https://test\.cluster\.local/'
curl --resolve test.cluster.local:443:127.0.0.1 \
  -k -sS -o /dev/null -D - https://test.cluster.local/ | head -n 1

# ci.cluster.local
stat -c '%a %U:%G %n' /opt/server/ci /opt/server/ci/index.html
nginx -t
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
curl --resolve ci.cluster.local:80:127.0.0.1 \
  -sS -o /dev/null -D - http://ci.cluster.local/ | \
  grep -E '^HTTP/|^Location: https://ci\.cluster\.local/'
curl --resolve ci.cluster.local:443:127.0.0.1 \
  -k -sS -o /dev/null -D - https://ci.cluster.local/ | head -n 1

# status.cluster.local
stat -c '%a %U:%G %n' /opt/server/status /opt/server/status/index.html
nginx -t
readlink -f /etc/nginx/sites-enabled/status.cluster.local
curl --resolve status.cluster.local:80:127.0.0.1 \
  -sS -o /dev/null -D - http://status.cluster.local/ | \
  grep -E '^HTTP/|^Location: https://status\.cluster\.local/'
curl --resolve status.cluster.local:443:127.0.0.1 \
  -k -sS -o /dev/null -D - https://status.cluster.local/ | head -n 1

# Default site, listener, and service logs
test ! -e /etc/nginx/sites-enabled/default
ss -tlnp | grep -E ':(22|80|443)\b'
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
```