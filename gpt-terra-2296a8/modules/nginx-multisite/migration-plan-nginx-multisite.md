---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and hardens Nginx, configures Fail2ban, UFW, kernel, and SSH security settings, creates self-signed TLS certificates, and deploys three SSL-enabled static virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. Each site redirects HTTP port 80 to HTTPS port 443 and serves content from a dedicated `/opt/server/...` document root.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80` redirects to HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; static content source `test/index.html`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80` redirects to HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; static content source `ci/index.html`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80` redirects to HTTPS `443` with HTTP/2
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; static content source `status/index.html`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`

Additional configuration:

- Certificate directory: `/etc/ssl/certs`
- Private-key directory: `/etc/ssl/private`
- Fail2ban attribute: `node['security']['fail2ban']['enabled'] = true`
- UFW attribute: `node['security']['ufw']['enabled'] = true`
- SSH root login disabled: `node['security']['ssh']['disable_root'] = true`
- SSH password authentication disabled: `node['security']['ssh']['password_auth'] = false`
- The Fail2ban and UFW enabled attributes are defined but do not guard package installation or firewall commands.

## File Structure

```text
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```

```text
Providers:
None
```

```text
Templates:
None listed here; the supplied execution-tree restriction permits only .rb files in this section.
```

```text
attributes/default.rb
```

```text
Files:
None listed in the supplied execution tree.
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
   - Renders `fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`; changes schedule a delayed Fail2ban restart.
   - Configures Fail2ban with `bantime = 3600`, `findtime = 600`, and `maxretry = 3`.
   - Enables the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Applies UFW default-deny policy and allows SSH, HTTP, and HTTPS:
     - `ufw --force default deny`
     - `ufw allow ssh`
     - `ufw allow http`
     - `ufw allow https`
     - `ufw --force enable`
   - Renders `sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`; changes run `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Applies kernel hardening including reverse-path filtering, disabled redirects and source routing, martian logging, ICMP restrictions, disabled IPv6, SYN cookies, `net.ipv4.tcp_max_syn_backlog = 2048`, `net.ipv4.tcp_synack_retries = 2`, and `net.ipv4.tcp_syn_retries = 5`.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['disable_root']` is `true`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `node['security']['ssh']['password_auth']` is `false`.
   - Declares the `ssh` service with no immediate action; it restarts only when either SSH hardening command changes the configuration.
   - Resources used: package (1), service (2), template (2), execute (8).

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`; changes schedule a delayed Nginx reload.
   - Renders `security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`; changes schedule a delayed Nginx reload.
   - Enables and starts the `nginx` service.
   - Configures Nginx with worker user `www-data`, `worker_processes auto`, PID `/run/nginx.pid`, `worker_connections 768`, global access and error logs, gzip, `sendfile`, `tcp_nopush`, `tcp_nodelay`, and a 65-second keepalive timeout.
   - Configures global HTTP hardening: `server_tokens off`, login and API rate-limit zones, restricted client buffers and body size, client and send timeouts, TLS 1.2/TLS 1.3, and SSL session cache and timeout settings.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`; deploys `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.
   - Resources used: package (1), template (2), service (1), directory (3), cookbook_file (3).

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with ownership `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with ownership `root:ssl-cert` and mode `0710`.
   - Iterations:
     - **test.cluster.local**: Generates `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` using a 2048-bit RSA key and a self-signed X.509 certificate valid for 365 days with CN `test.cluster.local`. The key is owned by `root:ssl-cert` with mode `0640`. Generation is skipped when both files exist. Changes schedule a delayed Nginx reload.
     - **ci.cluster.local**: Generates `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` using a 2048-bit RSA key and a self-signed X.509 certificate valid for 365 days with CN `ci.cluster.local`. The key is owned by `root:ssl-cert` with mode `0640`. Generation is skipped when both files exist. Changes schedule a delayed Nginx reload.
     - **status.cluster.local**: Generates `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` using a 2048-bit RSA key and a self-signed X.509 certificate valid for 365 days with CN `status.cluster.local`. The key is owned by `root:ssl-cert` with mode `0640`. Generation is skipped when both files exist. Changes schedule a delayed Nginx reload.
   - Generated certificate subject format: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site-name>/emailAddress=admin@example.com`.
   - Resources used: package (1), group (1), directory (2), execute (3).

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations:
     - **test.cluster.local**: Renders `site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, using document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`. Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symbolic link to `/etc/nginx/sites-available/test.cluster.local`.
     - **ci.cluster.local**: Renders `site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, using document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`. Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symbolic link to `/etc/nginx/sites-available/ci.cluster.local`.
     - **status.cluster.local**: Renders `site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, using document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`. Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symbolic link to `/etc/nginx/sites-available/status.cluster.local`.
   - Template and symbolic-link changes schedule a delayed Nginx reload.
   - Removes `/etc/nginx/sites-enabled/default`; removal schedules a delayed Nginx reload.
   - Each virtual host listens on port 80 and redirects requests to HTTPS with `return 301 https://$server_name$request_uri;`.
   - Each HTTPS virtual host listens on `443 ssl http2`, serves its site-specific document root, uses TLS 1.2 and TLS 1.3, enables HSTS, applies security headers, enables gzip with a 1024-byte minimum, denies `.htaccess`, `.git`, and `.svn` paths, and writes named access and error logs.
   - Resources used: template (3), link (3), file (1).

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`.

**Service dependencies**:
- `nginx`: enabled and started; reloaded after Nginx configuration, TLS certificate/key generation, virtual-host configuration, symbolic-link creation, and default-site removal.
- `fail2ban`: enabled and started; restarted after changes to `/etc/fail2ban/jail.local`.
- `ssh`: restarted only after SSH hardening changes.
- `ufw`: enabled after default-deny policy and SSH/HTTP/HTTPS allow rules are configured.

Supported operating systems: Ubuntu `>= 18.04` and CentOS `>= 7.0`.

## Credentials

**Detection Summary**: 3 sensitive private keys are generated across 2 recipe/template contexts. No passwords, API tokens, data bags, vault integrations, embedded database credentials, or environment-variable secrets were detected.

**Source**:
  - **Provider**: Internal / locally generated self-signed TLS material
  - **URL**: None detected
  - **Path**: `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, `/etc/ssl/private/status.cluster.local.key`

### Self-signed TLS Private Keys
- **Variable(s)**: `key_file`, `node['nginx']['ssl']['private_key_path']`, `node['nginx']['ssl']['certificate_path']`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated with `openssl` and stored on the managed host.
- **Usage context**:
  - `test.cluster.local`: `ssl_certificate_key /etc/ssl/private/test.cluster.local.key`
  - `ci.cluster.local`: `ssl_certificate_key /etc/ssl/private/ci.cluster.local.key`
  - `status.cluster.local`: `ssl_certificate_key /etc/ssl/private/status.cluster.local.key`
- **Protection**: `/etc/ssl/private` is owned by `root:ssl-cert` with mode `0710`; individual private keys are owned by `root:ssl-cert` with mode `0640`.

## Checks for the Migration

**Files to verify**: `/etc/fail2ban/jail.local`, `/etc/sysctl.d/99-security.conf`, `/etc/ssh/sshd_config`, `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/security.conf`, `/etc/nginx/sites-available/test.cluster.local`, `/etc/nginx/sites-available/ci.cluster.local`, `/etc/nginx/sites-available/status.cluster.local`, `/etc/nginx/sites-enabled/test.cluster.local`, `/etc/nginx/sites-enabled/ci.cluster.local`, `/etc/nginx/sites-enabled/status.cluster.local`, `/opt/server/test/index.html`, `/opt/server/ci/index.html`, `/opt/server/status/index.html`, `/etc/ssl/certs/test.cluster.local.crt`, `/etc/ssl/certs/ci.cluster.local.crt`, `/etc/ssl/certs/status.cluster.local.crt`, `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, `/etc/ssl/private/status.cluster.local.key`, `/var/log/nginx/access.log`, `/var/log/nginx/error.log`, `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`, `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`, `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`.

**Service endpoints to check**:
- TCP port `22`: SSH, permitted through UFW.
- TCP port `80`: Nginx HTTP endpoint; redirects each named host to HTTPS.
- TCP port `443`: Nginx HTTPS endpoint; serves each named host.
- Unix sockets: none configured.
- Nginx binds with `listen 80` and `listen 443 ssl http2` without address-specific binding.

**Templates rendered**:
- `fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`: 1 render.
- `sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`: 1 render.
- `nginx.conf.erb` to `/etc/nginx/nginx.conf`: 1 render.
- `security.conf.erb` to `/etc/nginx/conf.d/security.conf`: 1 render.
- `site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`: 1 render.
- `site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`: 1 render.
- `site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`: 1 render.

## Pre-flight checks:
```bash
# Package and service status
dpkg -l nginx fail2ban ufw openssl ca-certificates 2>/dev/null || rpm -q nginx fail2ban openssl ca-certificates
systemctl status nginx
systemctl status fail2ban
systemctl status ssh

# Nginx syntax and global configuration
nginx -t
grep -E 'worker_processes|worker_connections|access_log|error_log' /etc/nginx/nginx.conf
grep -E 'server_tokens|limit_req_zone|ssl_protocols|client_max_body_size' /etc/nginx/conf.d/security.conf

# Firewall and SSH hardening
ufw status verbose
ufw status | grep -E '22/tcp|80/tcp|443/tcp'
ufw status verbose | grep 'Default: deny'
grep '^PermitRootLogin no' /etc/ssh/sshd_config
grep '^PasswordAuthentication no' /etc/ssh/sshd_config

# Fail2ban and sysctl configuration
fail2ban-client ping
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
grep -E 'bantime = 3600|findtime = 600|maxretry = 3' /etc/fail2ban/jail.local
grep -E 'rp_filter|accept_redirects|accept_source_route|log_martians|icmp_echo_ignore_all|disable_ipv6|tcp_syncookies' /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies

# TLS material: test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep 'CN = test.cluster.local'

# TLS material: ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep 'CN = ci.cluster.local'

# TLS material: status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep 'CN = status.cluster.local'

# Site configuration: test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local | grep '^/etc/nginx/sites-available/test.cluster.local$'
grep -E 'server_name test\.cluster\.local|root /opt/server/test|listen 443 ssl http2' /etc/nginx/sites-available/test.cluster.local
test -f /opt/server/test/index.html
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -k -s --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | head

# Site configuration: ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local | grep '^/etc/nginx/sites-available/ci.cluster.local$'
grep -E 'server_name ci\.cluster\.local|root /opt/server/ci|listen 443 ssl http2' /etc/nginx/sites-available/ci.cluster.local
test -f /opt/server/ci/index.html
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | head

# Site configuration: status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local | grep '^/etc/nginx/sites-available/status.cluster.local$'
grep -E 'server_name status\.cluster\.local|root /opt/server/status|listen 443 ssl http2' /etc/nginx/sites-available/status.cluster.local
test -f /opt/server/status/index.html
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -k -s --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | head

# Default-site, logs, and listeners
test ! -e /etc/nginx/sites-enabled/default
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
ss -tlnp | grep ':22'
```