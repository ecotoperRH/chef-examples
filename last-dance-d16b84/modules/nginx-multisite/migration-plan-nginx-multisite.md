---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server for three SSL-enabled virtual hosts: **test.cluster.local**, **ci.cluster.local**, and **status.cluster.local**. It installs Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; creates document roots and locally generated self-signed certificates; deploys global and virtual-host Nginx configuration; redirects HTTP to HTTPS; applies security headers, TLS settings, firewall rules, SSH hardening, and kernel network hardening. The site attributes, SSL paths, security settings, and detailed template contents should be revalidated against the source cookbook before production migration because they were not independently represented in the supplied structured analysis.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled Nginx virtual host serving test content
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; source content `test/index.html`

- **ci.cluster.local**: SSL-enabled Nginx virtual host serving CI content
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; source content `ci/index.html`

- **status.cluster.local**: SSL-enabled Nginx virtual host serving status content
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80` redirected to HTTPS; HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; source content `status/index.html`

Security areas configured by attributes:

- **fail2ban**: enabled
- **ufw**: enabled
- **ssh**: root login disabled and password authentication disabled

The site names and three-site iteration are consistent with the execution tree. The supplied structured analysis does not independently verify the attribute definitions or detailed template contents.

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

No provider files or custom resources are used by the execution tree. The cookbook uses only standard Chef resources.

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

No static file under `files/default/` or `files/` is listed in the supplied cookbook directory. The `nginx.rb` recipe references these dynamic `cookbook_file` sources:

```text
test/index.html
ci/index.html
status/index.html
```

Their presence was not verified in the supplied file analysis and must be resolved before claiming complete site-content coverage.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `security.rb`.
   - Includes `nginx.rb`.
   - Includes `ssl.rb`.
   - Includes `sites.rb`.
   - The Ansible migration must preserve this execution order.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
   - Configures Fail2ban jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`.
   - Applies UFW default-deny policy.
   - Allows SSH on port `22`, HTTP on port `80`, and HTTPS on port `443`.
   - Enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
   - Reloads sysctl settings with `sysctl -p /etc/sysctl.d/99-security.conf` when the sysctl template changes.
   - Disables root SSH login when `security.ssh.disable_root` is `true`.
   - Disables SSH password authentication when `security.ssh.password_auth` is `false`.
   - Uses `service[ssh]` only as a delayed restart target. The recipe does not enable, start, or otherwise manage the normal SSH service state.
   - Resources: one package resource, two service resources, two template resources, and eight execute resources: five UFW commands, one sysctl reload command, and two SSH hardening commands.
   - Detailed Fail2ban and sysctl values are described in the source plan but were not independently represented in the supplied structured analysis and require source-template verification.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` owned by `www-data:www-data` with mode `0755`.
   - Deploys `test/index.html` to `/opt/server/test/index.html` owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/ci` owned by `www-data:www-data` with mode `0755`.
   - Deploys `ci/index.html` to `/opt/server/ci/index.html` owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/status` owned by `www-data:www-data` with mode `0755`.
   - Deploys `status/index.html` to `/opt/server/status/index.html` owned by `www-data:www-data` with mode `0644`.
   - Template changes trigger delayed Nginx reloads.
   - Detailed Nginx global and security-template values require verification against the source templates.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates group `ssl-cert`.
   - Creates `/etc/ssl/certs` with owner `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root:ssl-cert` and mode `0710`.
   - Generates a self-signed RSA 2048-bit certificate and private key for **test.cluster.local**:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Key: `/etc/ssl/private/test.cluster.local.key`
     - Validity: `365` days
     - Key mode: `0640`
     - Key owner: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate and private key for **ci.cluster.local**:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Key: `/etc/ssl/private/ci.cluster.local.key`
     - Common name: `ci.cluster.local`
     - Validity: `365` days
     - Key mode: `0640`
     - Key owner: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate and private key for **status.cluster.local**:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Key: `/etc/ssl/private/status.cluster.local.key`
     - Common name: `status.cluster.local`
     - Validity: `365` days
     - Key mode: `0640`
     - Key owner: `root:ssl-cert`
   - Skips certificate generation when both the certificate and key already exist.
   - Certificate generation triggers delayed Nginx reloads.
   - Certificate and key generation behavior should be confirmed against the source recipe.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` for **test.cluster.local**.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` for **ci.cluster.local**.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` for **status.cluster.local**.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to `/etc/nginx/sites-available/status.cluster.local`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Each virtual host listens on HTTP port `80`, redirects to HTTPS, and listens on HTTPS port `443`.
   - Each virtual host uses HTTP/2, its configured document root, TLS certificate and key, site-specific access and error logs, security headers, static-file handling, and protected-path rules as defined by the source template.
   - Template, link, and removal changes trigger delayed Nginx reloads.
   - Detailed headers, HSTS, cipher, gzip, and `try_files` behavior require verification against `site.conf.erb`.

## Dependencies

**External cookbook dependencies**: None shown in the supplied metadata or execution tree.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `nginx`
- `fail2ban`
- `ssh` as an existing service and delayed restart target; this cookbook does not enable or start it during normal execution

**Supported platforms from metadata**:

- Ubuntu `>= 18.04`
- CentOS `>= 7.0`

The recipes use Debian/Ubuntu-oriented paths, commands, users, groups, and service names, including `/var/log/auth.log`, `ufw`, `www-data`, and `ssh`. CentOS package names, service names, user/group names, firewall behavior, and log paths must be verified before claiming cross-platform parity.

## Credentials

**Detection Summary**: No application credentials, data bags, vault references, API tokens, database passwords, environment-variable secrets, or hardcoded application credentials were detected.

The cookbook generates local self-signed TLS certificates and private keys. These are locally generated artifacts rather than retrieved credentials.

**Source**:

- **Provider**: None detected
- **URL**: None
- **Path**: None

### Self-signed TLS private keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files; not stored in a Chef data bag or vault
- **Usage context**: Nginx TLS private keys for the three HTTPS virtual hosts
- **Permissions**: Mode `640`, owner `root`, group `ssl-cert`

### TLS certificate files

- **Variable(s)**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated self-signed certificate files
- **Usage context**: Nginx HTTPS certificate configuration
- **Validity**: `365` days
- **Subject email**: `admin@example.com`

These are development-style self-signed artifacts. Production migration should replace them with certificates and keys managed through the approved PKI or secret-management system.

## Checks for the Migration

**Files to verify**:

- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
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

**Service endpoints to check**:

- SSH: TCP `22`
- HTTP: TCP `80`
- HTTPS: TCP `443`

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: rendered `1` time
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: rendered `1` time
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: rendered `1` time
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: rendered `1` time
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: rendered `1` time
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: rendered `1` time
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: rendered `1` time
- `site.conf.erb` total: rendered `3` times

## Pre-flight checks

Run these checks after the Ansible role completes. The SSH checks verify an existing prerequisite service; the role does not ensure that SSH is enabled or started.

### Service status

```bash
systemctl is-active nginx
systemctl is-enabled nginx
systemctl is-active fail2ban
systemctl is-enabled fail2ban
systemctl is-active ssh || systemctl is-active sshd
```

Expected state:

- `nginx`: enabled and active
- `fail2ban`: enabled and active
- `ssh` or `sshd`: active before migration; enablement is managed outside this cookbook

### Package verification

```bash
dpkg -l nginx fail2ban ufw openssl ca-certificates
```

On RPM-based systems:

```bash
rpm -q nginx fail2ban ufw openssl ca-certificates
```

### Nginx syntax and listening ports

```bash
nginx -t
ss -tlnp | grep -E ':(80|443)\b'
```

Expected result:

```text
syntax is ok
test is successful
```

Expected listeners:

- TCP `80`
- TCP `443`

### Firewall verification

```bash
ufw status verbose
ufw status numbered
```

Verify:

- Default incoming policy is deny
- SSH is allowed on port `22`
- HTTP is allowed on port `80`
- HTTPS is allowed on port `443`
- UFW is active

### SSH hardening verification

```bash
grep -E '^PermitRootLogin|^PasswordAuthentication' /etc/ssh/sshd_config
sshd -t
systemctl is-active ssh || systemctl is-active sshd
```

Expected configuration:

```text
PermitRootLogin no
PasswordAuthentication no
```

### Kernel security verification

```bash
sysctl net.ipv4.conf.default.rp_filter
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog
```

Expected values include:

```text
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
```

### Fail2ban verification

```bash
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch
```

Verify that these four jails are enabled:

- `sshd`
- `nginx-http-auth`
- `nginx-limit-req`
- `nginx-botsearch`

### test.cluster.local

```bash
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key

curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -k -s --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
```

Expected results:

- HTTP returns a `301` redirect to HTTPS
- HTTPS returns `200 OK`
- HTTPS serves `/opt/server/test/index.html`
- The response includes expected security headers such as `Strict-Transport-Security`, `X-Frame-Options`, and `X-Content-Type-Options`
- The certificate subject contains `CN=test.cluster.local`

### ci.cluster.local

```bash
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key

curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -k -s --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
```

Expected results:

- HTTP returns a `301` redirect to HTTPS
- HTTPS returns `200 OK`
- HTTPS serves `/opt/server/ci/index.html`
- The certificate subject contains `CN=ci.cluster.local`

### status.cluster.local

```bash
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key

curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -k -s --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/ | head

openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
```

Expected results:

- HTTP returns a `301` redirect to HTTPS
- HTTPS returns `200 OK`
- HTTPS serves `/opt/server/status/index.html`
- The certificate subject contains `CN=status.cluster.local`

### File permissions

```bash
stat -c '%U:%G %a %n' /etc/ssl/private
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
```

Expected results:

- `/etc/ssl/private`: `root:ssl-cert` with mode `710`
- Each private key: `root:ssl-cert` with mode `640`

### Nginx configuration and site links

```bash
grep -E 'user|worker_processes|worker_connections|keepalive_timeout|access_log|error_log|gzip on|sites-enabled' /etc/nginx/nginx.conf
grep -E 'server_tokens|limit_req_zone|client_max_body_size|ssl_protocols' /etc/nginx/conf.d/security.conf

readlink -f /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test ! -e /etc/nginx/sites-enabled/default
```

Verify that the global configuration includes the expected worker, logging, gzip, and sites-enabled settings, and that all three enabled-site links point to their corresponding `sites-available` files. Detailed security-template values must be compared with the source templates before being treated as validated.