---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is a web-server cookbook that installs and enables NGINX, configures UFW, Fail2ban, SSH hardening, and kernel sysctl settings, and serves three SSL-enabled static sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. Each site redirects HTTP on port 80 to HTTPS on port 443, uses a locally generated RSA-2048 self-signed certificate valid for 365 days, and has individual NGINX access and error logs.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443; HTTPS uses HTTP/2.
  - Key Config: Static content at `/opt/server/test/index.html`; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443; HTTPS uses HTTP/2.
  - Key Config: Static content at `/opt/server/ci/index.html`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static NGINX virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP TCP/80 redirects to HTTPS TCP/443; HTTPS uses HTTP/2.
  - Key Config: Static content at `/opt/server/status/index.html`; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`.

- **fail2ban**: Intrusion-prevention service.
  - Location/Path: `/etc/fail2ban/jail.local`
  - Port/Socket: Monitors SSH and NGINX authentication, rate-limit, and bot-search activity.
  - Key Config: Enabled and started; `bantime = 3600`, `findtime = 600`, and `maxretry = 3`.

- **ufw**: Host firewall.
  - Location/Path: UFW system configuration.
  - Port/Socket: Allows TCP/22, TCP/80, and TCP/443.
  - Key Config: Enabled with a default inbound deny policy.

- **ssh**: SSH daemon hardening configuration.
  - Location/Path: `/etc/ssh/sshd_config`
  - Port/Socket: TCP/22 permitted through UFW.
  - Key Config: `PermitRootLogin no` and `PasswordAuthentication no`.

## File Structure

**Recipes:**
```text
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```

**Providers:**
```text
```

No custom resource provider is invoked by the execution tree.

**Templates:**
```text
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/sysctl-security.conf.erb
templates/default/site.conf.erb
```

**Attributes:**
```text
attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes recipes in this exact order:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Resources used: four `include_recipe` resources.
   - Preserve this execution order during migration because NGINX is installed and started before TLS certificates and virtual-host configurations are deployed.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs packages `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`; changes restart Fail2ban.
   - Configures Fail2ban with `bantime = 3600`, `findtime = 600`, `maxretry = 3`, and enabled jails for SSH, NGINX HTTP authentication, NGINX rate limits, and NGINX bot search.
   - Applies UFW default-deny policy, permits SSH/TCP 22, HTTP/TCP 80, and HTTPS/TCP 443, then enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`; changes run `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Applies reverse-path filtering, disables IPv4 and IPv6 redirects and source routing, enables martian logging and TCP SYN cookies, disables IPv6 globally/default/loopback, ignores ICMP echo requests and broadcast pings, and configures `net.ipv4.tcp_max_syn_backlog = 2048`, `net.ipv4.tcp_synack_retries = 2`, and `net.ipv4.tcp_syn_retries = 5`.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because `security.ssh.disable_root` is `true`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `security.ssh.password_auth` is `false`.
   - Changes to SSH configuration restart `sshd`.
   - Resources used: package, service, template, and execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs package `nginx`.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`; changes reload NGINX.
   - Configures NGINX to run as user `nginx`, use `worker_processes auto`, store its PID at `/run/nginx.pid`, use `worker_connections 768`, log globally to `/var/log/nginx/access.log` and `/var/log/nginx/error.log`, enable gzip, and include `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`; changes reload NGINX.
   - Configures `server_tokens off`, login and API rate-limit zones, small client request buffers, `client_max_body_size 1k`, 10-second client/send timeouts, TLS 1.2 and TLS 1.3 only, and the explicit source-template cipher list.
   - Enables and starts the `nginx` service.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner/group `nginx:nginx` and mode `0755`; deploys source `test/index.html` to `/opt/server/test/index.html` with owner/group `nginx:nginx` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner/group `nginx:nginx` and mode `0755`; deploys source `ci/index.html` to `/opt/server/ci/index.html` with owner/group `nginx:nginx` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner/group `nginx:nginx` and mode `0755`; deploys source `status/index.html` to `/opt/server/status/index.html` with owner/group `nginx:nginx` and mode `0644`.
   - Resources used: package (1), template (2), service (1), directory (3), cookbook_file (3).
   - The source content files `test/index.html`, `ci/index.html`, and `status/index.html` must be obtained or recreated before migration; do not omit their destination files.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs packages `openssl` and `ca-certificates`.
   - Creates group `ssl-cert`.
   - Creates `/etc/ssl/certs` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner/group `root:ssl-cert` and mode `0710`.
   - Iterations:
     - **test.cluster.local**: Generates `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` when absent. The certificate is self-signed, RSA-2048, valid for 365 days, and has subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`. The private key is `root:ssl-cert` with mode `0640`.
     - **ci.cluster.local**: Generates `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key` when absent. The certificate is self-signed, RSA-2048, valid for 365 days, and has subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`. The private key is `root:ssl-cert` with mode `0640`.
     - **status.cluster.local**: Generates `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key` when absent. The certificate is self-signed, RSA-2048, valid for 365 days, and has subject `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`. The private key is `root:ssl-cert` with mode `0640`.
   - Certificate or key generation reloads NGINX.
   - Resources used: package (1), group (1), directory (2), execute (3).

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates `/etc/nginx/sites-available` with owner/group `root:root` and mode `0755`.
   - Creates `/etc/nginx/sites-enabled` with owner/group `root:root` and mode `0755`.
   - The structured analysis records three additional directory resource executions associated with the named site iterations: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
   - Iterations:
     - **test.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, using server name `test.cluster.local`, document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, private key `/etc/ssl/private/test.cluster.local.key`, and `ssl_enabled: true`. Creates symlink `/etc/nginx/sites-enabled/test.cluster.local` targeting `/etc/nginx/sites-available/test.cluster.local`.
     - **ci.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, using server name `ci.cluster.local`, document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, private key `/etc/ssl/private/ci.cluster.local.key`, and `ssl_enabled: true`. Creates symlink `/etc/nginx/sites-enabled/ci.cluster.local` targeting `/etc/nginx/sites-available/ci.cluster.local`.
     - **status.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, using server name `status.cluster.local`, document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, private key `/etc/ssl/private/status.cluster.local.key`, and `ssl_enabled: true`. Creates symlink `/etc/nginx/sites-enabled/status.cluster.local` targeting `/etc/nginx/sites-available/status.cluster.local`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Template, symlink, or default-site removal changes reload NGINX.
   - Each site configuration creates an HTTP port-80 server that returns a 301 redirect to `https://$server_name$request_uri`, and an HTTPS port-443 HTTP/2 server with TLS 1.2/1.3, HSTS, security headers, gzip, `try_files $uri $uri/ =404`, protected `.htaccess`, `.git`, and `.svn` paths, and site-specific access/error logs.
   - Resources used: directory (5), template (3), link (3), file (1).

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: Enabled and started; reloaded when NGINX configuration, TLS material, sites, or enabled-site links change.
- `fail2ban`: Enabled and started; restarted when `/etc/fail2ban/jail.local` changes.
- `sshd`: Restarted when `/etc/ssh/sshd_config` changes.
- UFW: Enabled with default inbound deny policy and SSH, HTTP, and HTTPS permitted.

## Credentials

**Detection Summary**: 3 sensitive credential artifacts detected across 1 file. No Chef data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, HashiCorp Vault, AWS Secrets Manager, environment-variable secrets, hardcoded passwords, API tokens, or database credentials were detected.

**Source**:
  - **Provider**: Internal/self-generated development TLS material
  - **URL**: None
  - **Path**: `/etc/ssl/private`

### test.cluster.local TLS Private Key
- **Variable(s)**: `key_file`, derived as `/etc/ssl/private/test.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by OpenSSL on the managed node.
- **Usage context**: Private key used by the `test.cluster.local` HTTPS virtual host through `ssl_certificate_key`; mode `0640`, owner/group `root:ssl-cert`.

### ci.cluster.local TLS Private Key
- **Variable(s)**: `key_file`, derived as `/etc/ssl/private/ci.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by OpenSSL on the managed node.
- **Usage context**: Private key used by the `ci.cluster.local` HTTPS virtual host through `ssl_certificate_key`; mode `0640`, owner/group `root:ssl-cert`.

### status.cluster.local TLS Private Key
- **Variable(s)**: `key_file`, derived as `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by OpenSSL on the managed node.
- **Usage context**: Private key used by the `status.cluster.local` HTTPS virtual host through `ssl_certificate_key`; mode `0640`, owner/group `root:ssl-cert`.

## Checks for the Migration

**Files to verify**:
```text
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available
/etc/nginx/sites-enabled
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/etc/nginx/sites-enabled/default
/opt/server/test
/opt/server/test/index.html
/opt/server/ci
/opt/server/ci/index.html
/opt/server/status
/opt/server/status/index.html
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/private/ci.cluster.local.key
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

**Service endpoints to check**:
- SSH: TCP port 22, permitted by UFW.
- NGINX HTTP: TCP port 80.
- NGINX HTTPS: TCP port 443.
- No Unix sockets are explicitly configured.

**Templates rendered**:
| Template | Destination | Render count |
|---|---|---:|
| `fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 |
| `sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 |
| `nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 |
| `security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 |
| `site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 |

## Pre-flight checks:
```bash
# Service status and configuration validation
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status nginx --no-pager
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status fail2ban --no-pager
nginx -t

# Listener and firewall validation
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
ufw status verbose
ufw status | grep -F '22/tcp'
ufw status | grep -F '80/tcp'
ufw status | grep -F '443/tcp'

# Fail2ban validation
fail2ban-client ping
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# SSH and kernel hardening validation
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_max_syn_backlog

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/test.cluster.local.key
curl -sS -o /dev/null -D - -H 'Host: test.cluster.local' http://127.0.0.1/ | grep -E 'HTTP/.* 301'
curl -skS --resolve test.cluster.local:443:127.0.0.1 -o /dev/null -D - https://test.cluster.local/ | grep -E 'HTTP/.* 200'
openssl s_client -connect 127.0.0.1:443 -servername test.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/ci.cluster.local.key
curl -sS -o /dev/null -D - -H 'Host: ci.cluster.local' http://127.0.0.1/ | grep -E 'HTTP/.* 301'
curl -skS --resolve ci.cluster.local:443:127.0.0.1 -o /dev/null -D - https://ci.cluster.local/ | grep -E 'HTTP/.* 200'
openssl s_client -connect 127.0.0.1:443 -servername ci.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/status.cluster.local.key
curl -sS -o /dev/null -D - -H 'Host: status.cluster.local' http://127.0.0.1/ | grep -E 'HTTP/.* 301'
curl -skS --resolve status.cluster.local:443:127.0.0.1 -o /dev/null -D - https://status.cluster.local/ | grep -E 'HTTP/.* 200'
openssl s_client -connect 127.0.0.1:443 -servername status.cluster.local </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log

# Default-site and NGINX security configuration validation
test ! -e /etc/nginx/sites-enabled/default
grep -E '^server_tokens off;' /etc/nginx/conf.d/security.conf
grep -E '^ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
grep -E '^client_max_body_size 1k;' /etc/nginx/conf.d/security.conf

# General service and NGINX log review
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
```