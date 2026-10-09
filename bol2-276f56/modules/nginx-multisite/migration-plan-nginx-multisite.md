---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook provisions an Nginx web server for three SSL-enabled sites—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; applies SSH and kernel-security configuration; creates site document roots and index files; generates self-signed TLS certificates; renders and enables one Nginx virtual host per site; and removes the default Nginx site. File modes, rendered directives, endpoint behavior, security attribute values, and platform metadata should be verified against the source files before implementation.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Nginx SSL virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - SSL: Enabled
  - Nginx site configuration: `/etc/nginx/sites-available/test.cluster.local`
  - Enabled-site link: `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: Nginx SSL virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - SSL: Enabled
  - Nginx site configuration: `/etc/nginx/sites-available/ci.cluster.local`
  - Enabled-site link: `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: Nginx SSL virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - SSL: Enabled
  - Nginx site configuration: `/etc/nginx/sites-available/status.cluster.local`
  - Enabled-site link: `/etc/nginx/sites-enabled/status.cluster.local`

**Security areas identified**:

- **fail2ban**: Security configuration and service resource are present.
- **ufw**: Firewall configuration resources are present.
- **ssh**: Conditional resources configure root-login and password-authentication settings.

The exact values claimed for `fail2ban.enabled`, `ufw.enabled`, `ssh.disable_root`, and `ssh.password_auth` require verification against `cookbooks/nginx-multisite/attributes/default.rb`.

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

No provider files are used by the execution tree.

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

No static file path under `files/default/` or `files/` is listed in the analyzed cookbook structure. The recipes use `cookbook_file` resources for the following per-site files, whose source files must be located separately:

- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`

## Module Explanation

The cookbook performs operations in this order:

1. `default.rb`
2. `security.rb`
3. `nginx.rb`
4. `ssl.rb`
5. `sites.rb`

### 1. Default recipe

**Recipe**: `cookbooks/nginx-multisite/recipes/default.rb`

- Includes `cookbooks/nginx-multisite/recipes/security.rb`.
- Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
- Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
- Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
- The Ansible implementation must preserve this order.

### 2. Security recipe

**Recipe**: `cookbooks/nginx-multisite/recipes/security.rb`

- Installs `fail2ban` and `ufw`.
- Enables and starts the `fail2ban` service.
- Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
- Sets the UFW default policy to deny.
- Allows SSH, HTTP, and HTTPS through UFW.
- Enables UFW.
- Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
- Defines `execute[reload_sysctl]` with command `sysctl -p /etc/sysctl.d/99-security.conf` and action `nothing`; the supplied execution tree does not show a notification that triggers it.
- Conditionally configures `/etc/ssh/sshd_config` to set `PermitRootLogin no`.
- Conditionally configures `/etc/ssh/sshd_config` to set `PasswordAuthentication no`.
- Defines `service[ssh]` with action `nothing`; no SSH restart or reload is shown.

**Resources**: package (1), service (2), template (2), execute (8).

The Ansible implementation should preserve the UFW order: deny by default, allow SSH, allow HTTP, allow HTTPS, then enable the firewall. SSH restart behavior should be handled cautiously to avoid terminating the migration connection.

### 3. Nginx recipe

**Recipe**: `cookbooks/nginx-multisite/recipes/nginx.rb`

- Installs the `nginx` package.
- Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`.
- Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`.
- Enables and starts the `nginx` service.
- Creates `/opt/server/test`.
- Deploys `/opt/server/test/index.html` using a `cookbook_file` resource.
- Creates `/opt/server/ci`.
- Deploys `/opt/server/ci/index.html` using a `cookbook_file` resource.
- Creates `/opt/server/status`.
- Deploys `/opt/server/status/index.html` using a `cookbook_file` resource.

**Resources**: package (1), template (2), service (1), directory (3), cookbook_file (3).

No explicit resource creating the `www-data` group is present in the execution tree.

### 4. SSL recipe

**Recipe**: `cookbooks/nginx-multisite/recipes/ssl.rb`

- Installs `openssl` and `ca-certificates`.
- Creates the `ssl-cert` group.
- Creates `/etc/ssl/certs`.
- Creates `/etc/ssl/private`.
- Generates a self-signed certificate and private key for `test.cluster.local`:
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Key: `/etc/ssl/private/test.cluster.local.key`
  - Command resource: `generate-ssl-cert-test.cluster.local`
- Generates a self-signed certificate and private key for `ci.cluster.local`:
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Key: `/etc/ssl/private/ci.cluster.local.key`
  - Command resource: `generate-ssl-cert-ci.cluster.local`
- Generates a self-signed certificate and private key for `status.cluster.local`:
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Key: `/etc/ssl/private/status.cluster.local.key`
  - Command resource: `generate-ssl-cert-status.cluster.local`

All three sites have `ssl_enabled: true` in the analyzed site configuration. Each generated certificate is intended to be:

- Self-signed
- RSA 2048-bit
- Valid for 365 days
- Unencrypted
- Subject country: `US`
- Subject state: `Example`
- Subject locality: `Example`
- Organization: `Example Org`
- Organizational unit: `IT`
- Common name: the site hostname
- Email: `admin@example.com`

Each private key is intended to use mode `0640` and ownership `root:ssl-cert`; these properties should be verified against the recipe and implementation requirements.

**Resources**: package (1), group (1), directory (2), execute (3).

### 5. Sites recipe

**Recipe**: `cookbooks/nginx-multisite/recipes/sites.rb`

- Renders and enables the `test.cluster.local` virtual host:
  - Template source: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
  - Destination: `/etc/nginx/sites-available/test.cluster.local`
  - Document root: `/opt/server/test`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Enabled link: `/etc/nginx/sites-enabled/test.cluster.local`

- Renders and enables the `ci.cluster.local` virtual host:
  - Template source: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
  - Destination: `/etc/nginx/sites-available/ci.cluster.local`
  - Document root: `/opt/server/ci`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Enabled link: `/etc/nginx/sites-enabled/ci.cluster.local`

- Renders and enables the `status.cluster.local` virtual host:
  - Template source: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
  - Destination: `/etc/nginx/sites-available/status.cluster.local`
  - Document root: `/opt/server/status`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Enabled link: `/etc/nginx/sites-enabled/status.cluster.local`

- Removes `/etc/nginx/sites-enabled/default`.

**Resources**: template (3), link (3), file (1).

The site template receives `server_name`, `document_root`, `ssl_enabled`, `cert_file`, and `key_file` on every render.

## Template Rendering Counts

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb`
  - Render count: 1
  - Destination: `/etc/fail2ban/jail.local`

- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb`
  - Render count: 1
  - Destination: `/etc/nginx/nginx.conf`

- `cookbooks/nginx-multisite/templates/default/security.conf.erb`
  - Render count: 1
  - Destination: `/etc/nginx/conf.d/security.conf`

- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb`
  - Render count: 1
  - Destination: `/etc/sysctl.d/99-security.conf`

- `cookbooks/nginx-multisite/templates/default/site.conf.erb`
  - Render count: 3
  - Destinations:
    - `/etc/nginx/sites-available/test.cluster.local`
    - `/etc/nginx/sites-available/ci.cluster.local`
    - `/etc/nginx/sites-available/status.cluster.local`

## Dependencies

**External cookbook dependencies**: None listed in the supplied metadata; metadata analysis should be confirmed.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: Enabled and started by `cookbooks/nginx-multisite/recipes/security.rb`.
- `nginx`: Enabled and started by `cookbooks/nginx-multisite/recipes/nginx.rb`.
- `ssh`: Referenced with action `nothing`; no SSH restart or start is shown.

**Platform information**: Ubuntu `>= 18.04` and CentOS `>= 7.0` were stated in the original plan but are not represented in the supplied structured analysis and must be verified. UFW may require platform-specific handling on CentOS.

## Credentials

**Detection Summary**: No external credentials or secret-management references were detected. Three locally generated TLS private keys and three locally generated self-signed certificates are created by the cookbook.

**Source**:
  - **Provider**: None detected
  - **URL**: None detected
  - **Path**: None detected

### TLS Private Keys

- **Variable(s)**: `key_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: Nginx HTTPS private keys
- **Files**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Intended properties**: RSA 2048-bit, no passphrase, mode `0640`, owner/group `root:ssl-cert`

### TLS Certificates

- **Variable(s)**: `cert_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated self-signed certificate files
- **Usage context**: Nginx HTTPS server certificates
- **Files**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Validity**: 365 days
- **Subject common names**:
  - `test.cluster.local`
  - `ci.cluster.local`
  - `status.cluster.local`

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
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`

**Service endpoints to check**:

- HTTP port `80`
- HTTPS port `443`
- SSH service port permitted by `ufw allow ssh`
- `test.cluster.local`
- `ci.cluster.local`
- `status.cluster.local`

**Templates rendered**:

- `fail2ban.jail.local.erb`: 1 render
- `nginx.conf.erb`: 1 render
- `security.conf.erb`: 1 render
- `sysctl-security.conf.erb`: 1 render
- `site.conf.erb`: 3 renders

**Security settings to verify**:

- UFW default policy is deny.
- UFW allows SSH, HTTP, and HTTPS.
- `PermitRootLogin no` is present if the source attribute enables it.
- `PasswordAuthentication no` is present if the source attribute disables password authentication.
- `/etc/sysctl.d/99-security.conf` contains the expected rendered settings.
- The exact rendered directives and modes must be verified from the templates and attributes.

## Pre-flight checks

```bash
# Package verification
dpkg -l nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
rpm -q nginx fail2ban ufw openssl ca-certificates

# Nginx service
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx
nginx -t

# Fail2ban service
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Global Nginx configuration
test -f /etc/nginx/nginx.conf
grep -E '^[[:space:]]*(user|worker_processes|events|http)' /etc/nginx/nginx.conf

# Nginx security configuration
test -f /etc/nginx/conf.d/security.conf
cat /etc/nginx/conf.d/security.conf

# test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -E 'test\.cluster\.local|/opt/server/test|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/test.cluster.local
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
stat -c '%A %U:%G %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | \
  grep 'CN = test.cluster.local'
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/

# ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -E 'ci\.cluster\.local|/opt/server/ci|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/ci.cluster.local
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
stat -c '%A %U:%G %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | \
  grep 'CN = ci.cluster.local'
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/

# status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -E 'status\.cluster\.local|/opt/server/status|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/status.cluster.local
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
stat -c '%A %U:%G %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | \
  grep 'CN = status.cluster.local'
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/

# Default site
test ! -e /etc/nginx/sites-enabled/default

# UFW
ufw status verbose
ufw status | grep -E '22|80|443'

# SSH hardening
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config

# Kernel security configuration
test -f /etc/sysctl.d/99-security.conf
cat /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# Listening ports
ss -tlnp | grep -E ':(80|443)\b'
netstat -tulpn 2>/dev/null | grep -E ':(80|443)\b'

# Nginx logs
journalctl -u nginx --no-pager -n 50
tail -n 50 /var/log/nginx/error.log
```