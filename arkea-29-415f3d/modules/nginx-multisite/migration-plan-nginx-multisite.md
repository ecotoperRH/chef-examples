---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` configures an Nginx web server hosting three SSL-enabled static virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs Nginx, creates document roots and index pages, generates a self-signed RSA-2048 certificate per site, redirects HTTP to HTTPS, applies hardened Nginx/TLS headers, permits only SSH/HTTP/HTTPS through UFW, and configures Fail2ban, SSH hardening, and kernel network-security settings.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves HTTPS; no Unix socket.
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves HTTPS; no Unix socket.
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves HTTPS; no Unix socket.
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`.

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

No custom resources or provider files are used in the supplied execution tree.

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

**Files:**

No static source files are present in the supplied directory listing. The `cookbook_file` resources deploy index pages to the following destinations; the migration must supply equivalent page content:

```text
/opt/server/test/index.html
/opt/server/ci/index.html
/opt/server/status/index.html
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes recipes in this exact sequence: `nginx-multisite::security`, `nginx-multisite::nginx`, `nginx-multisite::ssl`, and `nginx-multisite::sites`.
   - Uses four `include_recipe` resources.
   - Nginx starts before certificates and site definitions are created; delayed notifications reload Nginx at the end of convergence after relevant configuration, certificate, or enabled-site changes.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`; the `security.fail2ban.enabled` and `security.ufw.enabled` attributes exist but are not used as conditions, so both are always installed and configured.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`; changes trigger a delayed Fail2ban restart.
   - Configures Fail2ban with `bantime = 3600`, `findtime = 600`, and `maxretry = 3`; enables `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Configures UFW with default deny, permits SSH/TCP `22`, HTTP/TCP `80`, and HTTPS/TCP `443`, then enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`; changes trigger delayed execution of `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Applies IPv4 reverse-path filtering, disables IPv4/IPv6 redirects and source routing, enables Martian-packet logging and TCP SYN cookies, disables IPv6, ignores ICMP echo requests and broadcast pings, and sets `tcp_max_syn_backlog = 2048`, `tcp_synack_retries = 2`, and `tcp_syn_retries = 5`.
   - Sets `PermitRootLogin no` and `PasswordAuthentication no` in `/etc/ssh/sshd_config`; changes trigger a delayed SSH restart.
   - Declares `service[ssh]` as a delayed-notification target.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`; changes trigger a delayed Nginx reload.
   - Configures worker user `www-data`, `worker_processes auto`, PID `/run/nginx.pid`, `worker_connections 768`, global logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`, gzip, `keepalive_timeout 65`, and includes for `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`; changes trigger a delayed Nginx reload.
   - Configures `server_tokens off`, rate-limit zones `login` at `10r/m` and `api` at `30r/m`, request and header buffer restrictions, 10-second body/header/send timeouts, TLS `1.2` and `1.3`, configured cipher preferences, and TLS session cache `shared:SSL:10m` with timeout `10m`.
   - Enables and starts the `nginx` service.
   - Iterations: runs three times for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `test/index.html` to `/opt/server/test/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `ci/index.html` to `/opt/server/ci/index.html` with owner/group `www-data:www-data` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner/group `www-data:www-data` and mode `0755`; deploys source `status/index.html` to `/opt/server/status/index.html` with owner/group `www-data:www-data` and mode `0644`.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with ownership `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with ownership `root:ssl-cert` and mode `0710`.
   - Iterations: runs three times for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; all sites have `ssl_enabled: true`.
     - **test.cluster.local**: Generates self-signed X.509 certificate `/etc/ssl/certs/test.cluster.local.crt` and RSA-2048 private key `/etc/ssl/private/test.cluster.local.key` if absent. The certificate has subject CN `test.cluster.local`, validity `365` days, and the private key is `root:ssl-cert` with mode `0640`. Generation triggers a delayed Nginx reload.
     - **ci.cluster.local**: Generates self-signed X.509 certificate `/etc/ssl/certs/ci.cluster.local.crt` and RSA-2048 private key `/etc/ssl/private/ci.cluster.local.key` if absent. The certificate has subject CN `ci.cluster.local`, validity `365` days, and the private key is `root:ssl-cert` with mode `0640`. Generation triggers a delayed Nginx reload.
     - **status.cluster.local**: Generates self-signed X.509 certificate `/etc/ssl/certs/status.cluster.local.crt` and RSA-2048 private key `/etc/ssl/private/status.cluster.local.key` if absent. The certificate has subject CN `status.cluster.local`, validity `365` days, and the private key is `root:ssl-cert` with mode `0640`. Generation triggers a delayed Nginx reload.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations: runs three times for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
     - **test.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, using document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`. Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`. Changes trigger a delayed Nginx reload.
     - **ci.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, using document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`. Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`. Changes trigger a delayed Nginx reload.
     - **status.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, using document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`. Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`. Changes trigger a delayed Nginx reload.
   - Deletes `/etc/nginx/sites-enabled/default`; deletion triggers a delayed Nginx reload.
   - Each site template configures an HTTP/TCP `80` server returning HTTP `301` to HTTPS, an HTTPS listener `443 ssl http2`, TLS `1.2` and `1.3`, HSTS, hardened response headers, gzip, `try_files $uri $uri/ =404`, denial of `.htaccess`, `.git`, and `.svn` paths, and per-site access/error logs.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`. Supported platforms are Ubuntu `>= 18.04` and CentOS `>= 7.0`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx` — enabled and started; reloaded after configuration, certificate, or site-enable changes.
- `fail2ban` — enabled and started; restarted after `/etc/fail2ban/jail.local` changes.
- `ssh` — restarted only after changes to `PermitRootLogin` or `PasswordAuthentication`.

## Credentials

**Detection Summary**: Three generated TLS private keys were detected in one source file. No data bags, encrypted data bags, Chef Vault, external secret-manager references, environment-variable secrets, hardcoded passwords, API tokens, or database connection strings were detected.

**Source**:
  - **Provider**: Internal / locally generated self-signed TLS material
  - **URL**: None
  - **Path**: `/etc/ssl/private`

### TLS Private Key — test.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/test.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by `openssl req -x509 -nodes -newkey rsa:2048`
- **Usage context**: Private key for the `test.cluster.local` Nginx HTTPS virtual host; ownership `root:ssl-cert`, mode `0640`.

### TLS Private Key — ci.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/ci.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by `openssl req -x509 -nodes -newkey rsa:2048`
- **Usage context**: Private key for the `ci.cluster.local` Nginx HTTPS virtual host; ownership `root:ssl-cert`, mode `0640`.

### TLS Private Key — status.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by `openssl req -x509 -nodes -newkey rsa:2048`
- **Usage context**: Private key for the `status.cluster.local` Nginx HTTPS virtual host; ownership `root:ssl-cert`, mode `0640`.

## Checks for the Migration

**Files to verify**:
```text
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/etc/nginx/sites-enabled/default (must be absent)
/opt/server/test
/opt/server/test/index.html
/opt/server/ci
/opt/server/ci/index.html
/opt/server/status
/opt/server/status/index.html
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/status.cluster.local.key
/var/log/auth.log
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
- SSH: TCP `22`.
- `test.cluster.local`: TCP `80` returns an HTTP `301` redirect; TCP `443` serves HTTPS.
- `ci.cluster.local`: TCP `80` returns an HTTP `301` redirect; TCP `443` serves HTTPS.
- `status.cluster.local`: TCP `80` returns an HTTP `301` redirect; TCP `443` serves HTTPS.
- Unix socket: none configured.
- Nginx listen address: no explicit address is configured; Nginx uses platform-default interfaces for TCP `80` and `443`.

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
# Package and service state.
nginx -v
fail2ban-client --version
openssl version
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Validate Nginx and SSH before reload or restart.
nginx -t
sshd -t

# Firewall must default to deny and allow only SSH, HTTP, and HTTPS.
ufw status verbose
ufw status | grep -F 'Default: deny'
ufw status | grep -E '22/tcp|OpenSSH'
ufw status | grep -E '80/tcp|Nginx HTTP'
ufw status | grep -E '443/tcp|Nginx HTTPS'

# SSH hardening.
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
systemctl is-active ssh

# Sysctl and Fail2ban configuration.
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv4.tcp_synack_retries
sysctl net.ipv4.tcp_syn_retries
fail2ban-client -t
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Nginx global configuration.
grep -E '^worker_processes auto;' /etc/nginx/nginx.conf
grep -E '^worker_connections 768;' /etc/nginx/nginx.conf
grep -E '^server_tokens off;' /etc/nginx/conf.d/security.conf
grep -E '^ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
test ! -e /etc/nginx/sites-enabled/default

# test.cluster.local.
test -d /opt/server/test
test -f /opt/server/test/index.html
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep -F 'CN = test.cluster.local'
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skSI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E 'HTTP/.* 200|HTTP/.* 403'

# ci.cluster.local.
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep -F 'CN = ci.cluster.local'
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skSI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E 'HTTP/.* 200|HTTP/.* 403'

# status.cluster.local.
test -d /opt/server/status
test -f /opt/server/status/index.html
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep -F 'CN = status.cluster.local'
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skSI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E 'HTTP/.* 200|HTTP/.* 403'

# Listener, logs, and service journal checks.
ss -tlnp | grep -E ':(80|443)\b'
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
```