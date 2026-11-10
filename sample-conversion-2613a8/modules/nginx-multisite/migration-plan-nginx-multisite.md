---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an Nginx web server hosting three SSL-enabled static virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and starts Nginx; configures global HTTP, TLS, and security settings; creates document roots and index pages; generates self-signed RSA certificates; enables all virtual hosts; removes the default Nginx site; and applies Fail2ban, UFW, SSH-hardening, and kernel `sysctl` security controls.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves TLS traffic.
  - Key Config: `ssl_enabled: true`; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; site configuration `/etc/nginx/sites-available/test.cluster.local`; enabled-site link `/etc/nginx/sites-enabled/test.cluster.local`; index page `/opt/server/test/index.html`; logs `/var/log/nginx/test.cluster.local_access.log` and `/var/log/nginx/test.cluster.local_error.log`.

- **ci.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves TLS traffic.
  - Key Config: `ssl_enabled: true`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; site configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled-site link `/etc/nginx/sites-enabled/ci.cluster.local`; index page `/opt/server/ci/index.html`; logs `/var/log/nginx/ci.cluster.local_access.log` and `/var/log/nginx/ci.cluster.local_error.log`.

- **status.cluster.local**: SSL-enabled static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` redirects to HTTPS; TCP `443` serves TLS traffic.
  - Key Config: `ssl_enabled: true`; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; site configuration `/etc/nginx/sites-available/status.cluster.local`; enabled-site link `/etc/nginx/sites-enabled/status.cluster.local`; index page `/opt/server/status/index.html`; logs `/var/log/nginx/status.cluster.local_access.log` and `/var/log/nginx/status.cluster.local_error.log`.

## File Structure

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

**Templates:**
```text
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
```

**Attributes:**
```text
cookbooks/nginx-multisite/attributes/default.rb
```

**Files:**

No static files are listed in the supplied cookbook directory listing. The cookbook dynamically deploys index-page sources named `test/index.html`, `ci/index.html`, and `status/index.html`; obtain their content separately before implementing equivalent Ansible `copy` or `template` tasks.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes recipes in this order:
     1. `nginx-multisite::security`
     2. `nginx-multisite::nginx`
     3. `nginx-multisite::ssl`
     4. `nginx-multisite::sites`
   - Resources used: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`; changes schedule a delayed Fail2ban restart.
   - Configures UFW idempotently:
     - Runs `ufw --force default deny` unless UFW already reports `Default: deny`.
     - Runs `ufw allow ssh` unless UFW already reports `22/tcp`.
     - Runs `ufw allow http` unless UFW already reports `80/tcp`.
     - Runs `ufw allow https` unless UFW already reports `443/tcp`.
     - Runs `ufw --force enable` unless UFW is active.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`; changes schedule the delayed command `sysctl -p /etc/sysctl.d/99-security.conf`.
   - Because `node['security']['ssh']['disable_root']` is `true`, sets `PermitRootLogin no` in `/etc/ssh/sshd_config` when not already configured and schedules a delayed restart of `ssh`.
   - Because `node['security']['ssh']['password_auth']` is `false`, sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` when not already configured and schedules a delayed restart of `ssh`.
   - Resources used: one package resource installing two packages, two service resources, two template resources, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`; changes schedule a delayed Nginx reload.
   - Configures Nginx with worker user `www-data`, `worker_processes auto`, `worker_connections 768`, global logs at `/var/log/nginx/access.log` and `/var/log/nginx/error.log`, and includes for `/etc/nginx/conf.d/*.conf` and `/etc/nginx/sites-enabled/*`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`; changes schedule a delayed Nginx reload.
   - Configures `server_tokens off`, rate-limit zones `login:10m` at `10r/m` and `api:10m` at `30r/m`, `client_max_body_size 1k`, 10-second client and send timeouts, TLS versions `TLSv1.2 TLSv1.3`, SSL session cache `shared:SSL:10m`, and SSL session timeout `10m`.
   - Enables and starts the `nginx` service, supporting status, reload, and restart actions.
   - Iterations:
     - **test.cluster.local**: Creates `/opt/server/test` recursively with owner and group `www-data` and mode `0755`; deploys source `test/index.html` to `/opt/server/test/index.html` with owner and group `www-data` and mode `0644`.
     - **ci.cluster.local**: Creates `/opt/server/ci` recursively with owner and group `www-data` and mode `0755`; deploys source `ci/index.html` to `/opt/server/ci/index.html` with owner and group `www-data` and mode `0644`.
     - **status.cluster.local**: Creates `/opt/server/status` recursively with owner and group `www-data` and mode `0755`; deploys source `status/index.html` to `/opt/server/status/index.html` with owner and group `www-data` and mode `0644`.
   - Resources used: one package resource, two template resources, one service resource, three directory resources, and three cookbook-file resources.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner `root`, group `root`, and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root`, group `ssl-cert`, and mode `0710`.
   - Iterations:
     - **test.cluster.local**: When both certificate and key do not already exist, generates a 365-day self-signed RSA 2048-bit certificate with subject CN `test.cluster.local`; writes `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key`; sets the key to owner `root`, group `ssl-cert`, and mode `0640`; certificate creation schedules a delayed Nginx reload.
     - **ci.cluster.local**: When both certificate and key do not already exist, generates a 365-day self-signed RSA 2048-bit certificate with subject CN `ci.cluster.local`; writes `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key`; sets the key to owner `root`, group `ssl-cert`, and mode `0640`; certificate creation schedules a delayed Nginx reload.
     - **status.cluster.local**: When both certificate and key do not already exist, generates a 365-day self-signed RSA 2048-bit certificate with subject CN `status.cluster.local`; writes `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key`; sets the key to owner `root`, group `ssl-cert`, and mode `0640`; certificate creation schedules a delayed Nginx reload.
   - Certificate subject format: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site>/emailAddress=admin@example.com`.
   - Resources used: one package resource installing two packages, one group resource, two directory resources, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Iterations:
     - **test.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`; creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to `/etc/nginx/sites-available/test.cluster.local`; changes schedule a delayed Nginx reload.
     - **ci.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`; creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to `/etc/nginx/sites-available/ci.cluster.local`; changes schedule a delayed Nginx reload.
     - **status.cluster.local**: Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`; creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to `/etc/nginx/sites-available/status.cluster.local`; changes schedule a delayed Nginx reload.
   - Deletes `/etc/nginx/sites-enabled/default`; deletion schedules a delayed Nginx reload.
   - Each site listens on port `80` and returns HTTP `301` redirects to HTTPS, then listens on `443 ssl http2`.
   - Each TLS virtual host configures HSTS (`max-age=31536000; includeSubDomains`), `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, and `Content-Security-Policy` headers.
   - Each virtual host enables gzip for configured text, JavaScript, XML, and JSON content; returns `404` for missing content through `try_files $uri $uri/ =404`; and denies `.htaccess`, `.git`, and `.svn` paths.
   - Resources used: three template resources, three link resources, and one file resource.

## Dependencies

**External cookbook dependencies**: None declared in `metadata.rb`.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: Enabled and started; reloaded after global configuration, security configuration, certificate, virtual-host configuration, enabled-site link, or default-site changes.
- `fail2ban`: Enabled and started; restarted after `/etc/fail2ban/jail.local` changes.
- `ssh`: Restarted only after changes to `PermitRootLogin` or `PasswordAuthentication`.

Supported metadata platforms are Ubuntu `>= 18.04` and CentOS `>= 7.0`. The cookbook uses Debian/Ubuntu conventions including `ufw`, `www-data`, service name `ssh`, `/etc/nginx/sites-available`, and `/etc/nginx/sites-enabled`; use platform-specific conditions or scope the initial migration to Ubuntu.

## Credentials

**Detection Summary**: 3 sensitive TLS private keys detected across 3 files.

**Source**:
  - **Provider**: None detected for externally managed secrets; certificates are locally generated self-signed certificates.
  - **URL**: Not applicable.
  - **Path**: `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, `/etc/ssl/private/status.cluster.local.key`

### Self-signed TLS Private Keys

- **Variable(s)**: `key_file` for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally using an `openssl req -x509 -nodes` command; not stored in a Chef data bag, Chef Vault, or external secret manager.
- **Usage context**: TLS private keys for the three Nginx HTTPS listeners on TCP port `443`.
- **Protection applied by Chef**: `/etc/ssl/private` is owned by `root:ssl-cert` with mode `0710`; each private key is owned by `root:ssl-cert` with mode `0640`.

For production migration, do not store private keys in plaintext inventory. Use an AAP credential, Ansible Vault, or an approved external secret-management system. The existing Chef behavior generates self-signed development certificates; production certificates should be obtained through the organization’s certificate-management process.

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
/var/log/auth.log
```

**Service endpoints to check**:
- TCP `22`: SSH, allowed through UFW.
- TCP `80`: Nginx HTTP redirects, allowed through UFW.
- TCP `443`: Nginx HTTPS virtual hosts, allowed through UFW.
- Unix sockets: None configured.
- Nginx listen directives do not specify an address; Nginx binds according to its normal default behavior.

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render.
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render.

## Pre-flight checks:
```bash
# Package verification
dpkg-query -W -f='${Package} ${Status}\n' nginx fail2ban ufw openssl ca-certificates

# Service status
systemctl status nginx --no-pager
systemctl status fail2ban --no-pager
systemctl status ssh --no-pager

# Nginx configuration validation
nginx -t

# Fail2ban validation
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Firewall validation
ufw status verbose
ufw status | grep -F '22/tcp'
ufw status | grep -F '80/tcp'
ufw status | grep -F '443/tcp'
ufw status verbose | grep -F 'Default: deny'

# SSH hardening validation
grep -E '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication no$' /etc/ssh/sshd_config
sshd -T | grep -E 'permitrootlogin no|passwordauthentication no'

# Kernel hardening validation
grep -E 'net.ipv4.conf.all.rp_filter = 1' /etc/sysctl.d/99-security.conf
grep -E 'net.ipv4.icmp_echo_ignore_all = 1' /etc/sysctl.d/99-security.conf
grep -E 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.d/99-security.conf
grep -E 'net.ipv4.tcp_syncookies = 1' /etc/sysctl.d/99-security.conf
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies

# Global Nginx configuration validation
grep -E '^worker_processes auto;' /etc/nginx/nginx.conf
grep -E '^server_tokens off;' /etc/nginx/conf.d/security.conf
grep -E '^ssl_protocols TLSv1.2 TLSv1.3;' /etc/nginx/conf.d/security.conf
grep -E '^client_max_body_size 1k;' /etc/nginx/conf.d/security.conf

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
grep -E 'server_name test\.cluster\.local;' /etc/nginx/sites-available/test.cluster.local
grep -E 'root /opt/server/test;' /etc/nginx/sites-available/test.cluster.local
grep -E 'ssl_certificate /etc/ssl/certs/test\.cluster\.local\.crt;' /etc/nginx/sites-available/test.cluster.local
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
grep -E 'server_name ci\.cluster\.local;' /etc/nginx/sites-available/ci.cluster.local
grep -E 'root /opt/server/ci;' /etc/nginx/sites-available/ci.cluster.local
grep -E 'ssl_certificate /etc/ssl/certs/ci\.cluster\.local\.crt;' /etc/nginx/sites-available/ci.cluster.local
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
grep -E 'server_name status\.cluster\.local;' /etc/nginx/sites-available/status.cluster.local
grep -E 'root /opt/server/status;' /etc/nginx/sites-available/status.cluster.local
grep -E 'ssl_certificate /etc/ssl/certs/status\.cluster\.local\.crt;' /etc/nginx/sites-available/status.cluster.local
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

# Default-site, listener, and log validation
test ! -e /etc/nginx/sites-enabled/default
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log
tail -n 50 /var/log/auth.log
```