---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` configures an Nginx web server hosting three SSL-enabled static virtual hosts—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs Nginx, deploys static content, creates self-signed RSA-2048 TLS certificates, redirects HTTP to HTTPS, configures UFW and Fail2ban, applies kernel network hardening, and disables SSH root login and password authentication.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: SSL-enabled static website.
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Key Config: Redirects HTTP requests to HTTPS with `301`; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; virtual-host configuration `/etc/nginx/sites-available/test.cluster.local`; enabled symlink `/etc/nginx/sites-enabled/test.cluster.local`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static website.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Key Config: Redirects HTTP requests to HTTPS with `301`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; virtual-host configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled symlink `/etc/nginx/sites-enabled/ci.cluster.local`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static website.
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Key Config: Redirects HTTP requests to HTTPS with `301`; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; virtual-host configuration `/etc/nginx/sites-available/status.cluster.local`; enabled symlink `/etc/nginx/sites-enabled/status.cluster.local`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`.

## File Structure

Only Ruby files shown in the supplied execution tree are listed below.

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

**Templates:**
```text
```

**Attributes:**
```text
attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`, mode `0644`.
   - Configures Fail2ban defaults of `bantime = 3600`, `findtime = 600`, and `maxretry = 3`.
   - Enables the `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch` jails.
   - Configures UFW with a default inbound deny policy and allows SSH, HTTP, and HTTPS.
   - Enables UFW after its rules are configured.
   - Renders `sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`, mode `0644`.
   - Applies reverse-path filtering, ICMP redirect and source-route protections, martian logging, ICMP echo and broadcast protections, IPv6 disablement, and TCP SYN-cookie protection.
   - Updates `/etc/ssh/sshd_config` with `PermitRootLogin no`.
   - Updates `/etc/ssh/sshd_config` with `PasswordAuthentication no`.
   - Restarts `fail2ban`, reloads `/etc/sysctl.d/99-security.conf`, and restarts `ssh` only when their respective managed configuration changes.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs `nginx`.
   - Renders `nginx.conf.erb` to `/etc/nginx/nginx.conf`, mode `0644`.
   - Configures `www-data` as the worker user, `worker_processes auto`, `worker_connections 768`, gzip, global logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`, and includes for `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `security.conf.erb` to `/etc/nginx/conf.d/security.conf`, mode `0644`.
   - Disables server version disclosure, configures `login` request limiting at `10r/m`, configures `api` request limiting at `30r/m`, configures 1 KiB request buffers, sets 10-second client and send timeouts, and permits TLS 1.2 and TLS 1.3.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` recursively with owner and group `www-data` and mode `0755`.
   - Deploys Chef cookbook file `test/index.html` to `/opt/server/test/index.html` with owner and group `www-data` and mode `0644`.
   - Creates `/opt/server/ci` recursively with owner and group `www-data` and mode `0755`.
   - Deploys Chef cookbook file `ci/index.html` to `/opt/server/ci/index.html` with owner and group `www-data` and mode `0644`.
   - Creates `/opt/server/status` recursively with owner and group `www-data` and mode `0755`.
   - Deploys Chef cookbook file `status/index.html` to `/opt/server/status/index.html` with owner and group `www-data` and mode `0644`.
   - The supplied inventory does not contain the static Chef file artifacts; obtain the content for `test/index.html`, `ci/index.html`, and `status/index.html` before implementing Ansible copy tasks.
   - Changed Nginx configuration, site configuration, symlink, or certificate resources must validate with `nginx -t` before reloading Nginx.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` as `root:root`, mode `0755`.
   - Creates `/etc/ssl/private` as `root:ssl-cert`, mode `0710`.
   - Generates a self-signed RSA-2048 certificate for `test.cluster.local` when its certificate and private key do not exist.
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Subject CN: `test.cluster.local`
     - Validity: 365 days
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
   - Generates a self-signed RSA-2048 certificate for `ci.cluster.local` when its certificate and private key do not exist.
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Subject CN: `ci.cluster.local`
     - Validity: 365 days
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
   - Generates a self-signed RSA-2048 certificate for `status.cluster.local` when its certificate and private key do not exist.
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Subject CN: `status.cluster.local`
     - Validity: 365 days
     - Private-key ownership and mode: `root:ssl-cert`, `0640`
   - Certificate or private-key changes schedule a delayed Nginx reload.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`, mode `0644`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`.
   - Configures `test.cluster.local` with document root `/opt/server/test`, HTTP-to-HTTPS `301` redirects, and an HTTPS listener on `443 ssl http2` using `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key`.
   - Renders `site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`, mode `0644`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`.
   - Configures `ci.cluster.local` with document root `/opt/server/ci`, HTTP-to-HTTPS `301` redirects, and an HTTPS listener on `443 ssl http2` using `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key`.
   - Renders `site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`, mode `0644`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`.
   - Configures `status.cluster.local` with document root `/opt/server/status`, HTTP-to-HTTPS `301` redirects, and an HTTPS listener on `443 ssl http2` using `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Each site enables TLS 1.2 and TLS 1.3, HSTS with `max-age=31536000; includeSubDomains`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-XSS-Protection: 1; mode=block`, `Referrer-Policy: strict-origin-when-cross-origin`, and a restrictive Content Security Policy.
   - Each site denies access to `.htaccess`, `.git`, and `.svn` paths and returns `404` for non-existent files and directories.
   - Changed site configurations, symlinks, or default-site removal schedule a delayed Nginx reload.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`.

**Service dependencies**: `nginx` is enabled and started; `fail2ban` is enabled and started; `ssh` is restarted only when SSH-hardening settings change; UFW is enabled after SSH, HTTP, and HTTPS allow rules are configured.

The cookbook metadata declares Ubuntu `>= 18.04` and CentOS `>= 7.0`, but the implementation is Debian/Ubuntu-oriented because it uses UFW, `www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and `/var/log/auth.log`. Target Ubuntu/Debian explicitly or implement OS-family-specific tasks and variables.

## Credentials

**Detection Summary**: 0 externally sourced credentials detected across the analyzed recipes, attributes, and rendered templates. Three TLS private keys are generated locally during convergence.

**Source**:
  - **Provider**: None detected for external secrets. TLS private keys are generated locally with OpenSSL.
  - **URL**: Not applicable.
  - **Path**: `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, and `/etc/ssl/private/status.cluster.local.key`

### Self-signed TLS Private Keys
- **Variable(s)**: `key_file` for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL; not stored in a Chef data bag, Chef Vault, CyberArk, Conjur, HashiCorp Vault, AWS Secrets Manager, or an environment variable.
- **Usage context**: Nginx TLS private keys for the HTTPS listeners on port `443`.
- **Access controls**: `/etc/ssl/private` is `root:ssl-cert`, mode `0710`; each private key is `root:ssl-cert`, mode `0640`.

No hardcoded passwords, API keys, database credentials, data bags, encrypted data bags, Chef Vault calls, CyberArk or Conjur references, or secret-bearing environment variables were detected.

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

**Service endpoints to check**: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` must each provide an HTTP endpoint on TCP port `80` that returns a `301` redirect and an HTTPS static-content endpoint on TCP port `443` that returns `200`. No Unix sockets are configured. UFW must allow SSH, TCP `80`, and TCP `443` while denying other inbound traffic by default.

**Templates rendered**:
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render.
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render.
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render.
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render.
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render.
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render.
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render.

## Pre-flight checks:
```bash
# Package and service status
dpkg-query -W nginx fail2ban ufw openssl ca-certificates
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
nginx -t

# Listener and firewall verification
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
ufw status verbose
ufw status | grep -F '22/tcp'
ufw status | grep -F '80/tcp'
ufw status | grep -F '443/tcp'

# SSH, Fail2ban, and sysctl verification
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
sshd -t
fail2ban-client ping
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
grep -E '^(bantime|findtime|maxretry) = ' /etc/fail2ban/jail.local
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies

# Nginx global security configuration
grep -E '^worker_processes auto;$' /etc/nginx/nginx.conf
grep -E '^worker_connections 768;$' /etc/nginx/nginx.conf
grep -E '^server_tokens off;$' /etc/nginx/conf.d/security.conf
grep -E '^ssl_protocols TLSv1.2 TLSv1.3;$' /etc/nginx/conf.d/security.conf

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/test.cluster.local)" = "/etc/nginx/sites-available/test.cluster.local"
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates | grep 'CN = test.cluster.local'
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | grep -E 'HTTP/.* 200'
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/ci.cluster.local)" = "/etc/nginx/sites-available/ci.cluster.local"
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates | grep 'CN = ci.cluster.local'
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | grep -E 'HTTP/.* 200'
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/status.cluster.local)" = "/etc/nginx/sites-available/status.cluster.local"
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates | grep 'CN = status.cluster.local'
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/ | grep -E 'HTTP/.* 301'
curl -skI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | grep -E 'HTTP/.* 200'
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log

# Confirm default virtual host removal and review service logs
test ! -e /etc/nginx/sites-enabled/default
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
```