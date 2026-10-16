---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` provisions Nginx with three HTTPS virtual hosts—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; creates document roots and static index files; generates local self-signed TLS certificates; configures virtual hosts; enables firewall and Fail2ban protection; applies kernel and SSH hardening; and removes the default Nginx site.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**: 3 Nginx virtual hosts

All sites have `ssl_enabled: true`.

- **test.cluster.local**: Test web site
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTPS/TCP 443; HTTP/TCP 80 may be configured by the rendered site template
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; static file `/opt/server/test/index.html`; source `test/index.html`

- **ci.cluster.local**: Continuous-integration web site
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTPS/TCP 443; HTTP/TCP 80 may be configured by the rendered site template
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; static file `/opt/server/ci/index.html`; source `ci/index.html`

- **status.cluster.local**: Status web site
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTPS/TCP 443; HTTP/TCP 80 may be configured by the rendered site template
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; static file `/opt/server/status/index.html`; source `status/index.html`

Security configuration:

- **Fail2ban**
  - Enabled: `true`
  - Package: `fail2ban`
  - Service: `fail2ban`

- **UFW**
  - Enabled: `true`
  - Default incoming policy: deny
  - Allowed services: SSH, HTTP, HTTPS

- **SSH**
  - `PermitRootLogin no`
  - `PasswordAuthentication no`

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

No provider files are used by the executed recipes.

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

The recipes reference these site-specific `cookbook_file` sources, which are not present in the supplied directory listing and must be confirmed before implementation:

```text
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
   - Ansible execution order:
     ```yaml
     - import_tasks: security.yml
     - import_tasks: nginx.yml
     - import_tasks: ssl.yml
     - import_tasks: sites.yml
     ```

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Deploys `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` once to `/etc/fail2ban/jail.local` with mode `0644`.
   - Enables and starts `fail2ban`; changes to the jail configuration trigger a delayed restart.
   - Configures UFW with default deny, allows SSH/TCP 22, HTTP/TCP 80, and HTTPS/TCP 443, and enables the firewall.
   - Deploys `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` once to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Reloads the sysctl configuration with `sysctl -p /etc/sysctl.d/99-security.conf` when the template changes.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` when `security.ssh.disable_root` is true.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` when `security.ssh.password_auth` is false.
   - Queues a delayed SSH restart when either SSH setting changes.
   - Resource summary: 1 package resource installing 2 packages, 2 service resources, 2 templates, and **8 execute resources**: 5 UFW commands, 1 sysctl reload resource, 1 root-login command, and 1 password-authentication command.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Deploys `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` once to `/etc/nginx/nginx.conf` with mode `0644`.
   - Deploys `cookbooks/nginx-multisite/templates/default/security.conf.erb` once to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the Nginx service; configuration changes trigger delayed reloads.
   - Creates `/opt/server/test` for `test.cluster.local`, owned by `www-data:www-data` with mode `0755`.
   - Deploys `test/index.html` to `/opt/server/test/index.html`, owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/ci` for `ci.cluster.local`, owned by `www-data:www-data` with mode `0755`.
   - Deploys `ci/index.html` to `/opt/server/ci/index.html`, owned by `www-data:www-data` with mode `0644`.
   - Creates `/opt/server/status` for `status.cluster.local`, owned by `www-data:www-data` with mode `0755`.
   - Deploys `status/index.html` to `/opt/server/status/index.html`, owned by `www-data:www-data` with mode `0644`.
   - Resource summary: 1 package, 2 templates, 1 service, 3 directories, and 3 cookbook files.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` owned by `root:root` with mode `0755`.
   - Creates `/etc/ssl/private` owned by `root:ssl-cert` with mode `0710`.
   - Generates certificates only when both the certificate and key are absent, using `openssl req -x509 -nodes -days 365 -newkey rsa:2048`.
   - Uses subject fields `C=US`, `ST=Example`, `L=Example`, `O=Example Org`, `OU=IT`, `CN=<site_name>`, and `emailAddress=admin@example.com`.
   - Sets generated private keys to `root:ssl-cert` with mode `0640`.
   - Generates the following certificate and key pairs:
     - `test.cluster.local`: `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key`
     - `ci.cluster.local`: `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key`
     - `status.cluster.local`: `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key`
   - Each certificate-generation command queues a delayed Nginx reload.
   - Resource summary: 1 package resource installing 2 packages, 1 group, 2 directories, and 3 certificate-generation commands.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` once for each named site, for 3 total renders.
   - Each render receives `server_name`, `document_root`, `ssl_enabled`, `cert_file`, and `key_file`.
   - For `test.cluster.local`, renders `/etc/nginx/sites-available/test.cluster.local` and links `/etc/nginx/sites-enabled/test.cluster.local` to it.
   - For `ci.cluster.local`, renders `/etc/nginx/sites-available/ci.cluster.local` and links `/etc/nginx/sites-enabled/ci.cluster.local` to it.
   - For `status.cluster.local`, renders `/etc/nginx/sites-available/status.cluster.local` and links `/etc/nginx/sites-enabled/status.cluster.local` to it.
   - Template and link changes trigger delayed Nginx reloads.
   - Deletes `/etc/nginx/sites-enabled/default`; deletion triggers a delayed Nginx reload.
   - Resource summary: 3 templates, 3 links, and 1 file deletion.

## Dependencies

**External cookbook dependencies**: None shown in the supplied execution tree or directory listing.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `nginx`: enabled and started; reloaded when Nginx configuration, site links, or certificates change
- `fail2ban`: enabled and started; restarted when `/etc/fail2ban/jail.local` changes
- `ssh`: restarted when SSH hardening settings change; this cookbook does not explicitly enable or start it

**System group dependencies**:

- `www-data`: owns all document roots and index files
- `ssl-cert`: owns `/etc/ssl/private` and generated private keys

## Credentials

**Detection Summary**: No external credentials or secret-manager integrations were detected. Two categories of locally generated sensitive TLS artifacts are present across `cookbooks/nginx-multisite/recipes/ssl.rb` and `cookbooks/nginx-multisite/recipes/sites.rb`.

**Source**:
  - **Provider**: None detected; certificates and private keys are generated locally by the SSL recipe.
  - **URL**: Not applicable.
  - **Path**: Local filesystem paths under `/etc/ssl/certs` and `/etc/ssl/private`.

No data bags, encrypted data bags, Chef Vault, CyberArk, Conjur, HashiCorp Vault, AWS Secrets Manager, environment-variable secrets, database credentials, passwords, API tokens, or access keys were detected.

### TLS Private Keys

- **Variable(s)**: `key_file`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: HTTPS private keys for:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source provider**: None; generated locally by the SSL recipe
- **Permissions**: Mode `0640`, owner `root`, group `ssl-cert`

### TLS Certificates

- **Variable(s)**: `cert_file`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated self-signed certificates
- **Usage context**: HTTPS certificates for:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Source provider**: None; generated locally by the SSL recipe
- **Validity**: 365 days
- **Key type**: RSA 2048-bit

The Ansible migration should preserve local self-signed certificate generation unless the target environment requires an organizational CA or secret-management system.

## Checks for the Migration

**Files to verify**:

```text
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/etc/nginx/sites-enabled/default
/opt/server/test/index.html
/opt/server/ci/index.html
/opt/server/status/index.html
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/private/status.cluster.local.key
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
```

**Service endpoints to check**:

- SSH: TCP/22
- HTTP: TCP/80
- HTTPS: TCP/443
- `test.cluster.local`: HTTPS/TCP 443
- `ci.cluster.local`: HTTPS/TCP 443
- `status.cluster.local`: HTTPS/TCP 443

Confirm exact Nginx listener directives from the rendered `nginx.conf.erb` and `site.conf.erb` templates.

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb`:
  - `/etc/nginx/sites-available/test.cluster.local`: 1 render
  - `/etc/nginx/sites-available/ci.cluster.local`: 1 render
  - `/etc/nginx/sites-available/status.cluster.local`: 1 render
  - Total: 3 renders

## Pre-flight checks:

```bash
# Confirm required packages
dpkg-query -W nginx fail2ban ufw openssl ca-certificates

# Confirm service states
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl is-active ssh

# Validate Nginx
nginx -t
systemctl status nginx --no-pager

# Verify global Nginx configuration
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
grep -nE 'include|listen|server' /etc/nginx/nginx.conf
grep -nE 'server_tokens|headers|security' /etc/nginx/conf.d/security.conf

# Verify test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
grep -nE 'server_name|root|ssl|listen' /etc/nginx/sites-available/test.cluster.local
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

# Verify ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
grep -nE 'server_name|root|ssl|listen' /etc/nginx/sites-available/ci.cluster.local
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

# Verify status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
grep -nE 'server_name|root|ssl|listen' /etc/nginx/sites-available/status.cluster.local
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Verify ownership and permissions
stat -c '%U:%G %a %n' \
  /opt/server/test /opt/server/test/index.html \
  /opt/server/ci /opt/server/ci/index.html \
  /opt/server/status /opt/server/status/index.html \
  /etc/ssl/certs/test.cluster.local.crt \
  /etc/ssl/certs/ci.cluster.local.crt \
  /etc/ssl/certs/status.cluster.local.crt \
  /etc/ssl/private/test.cluster.local.key \
  /etc/ssl/private/ci.cluster.local.key \
  /etc/ssl/private/status.cluster.local.key

# Validate certificates and expiration
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates -checkend 0
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates -checkend 0
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates -checkend 0

# Verify certificate/key modulus matches for test.cluster.local
openssl x509 -noout -modulus \
  -in /etc/ssl/certs/test.cluster.local.crt | openssl sha256
openssl rsa -noout -modulus \
  -in /etc/ssl/private/test.cluster.local.key | openssl sha256

# Verify certificate/key modulus matches for ci.cluster.local
openssl x509 -noout -modulus \
  -in /etc/ssl/certs/ci.cluster.local.crt | openssl sha256
openssl rsa -noout -modulus \
  -in /etc/ssl/private/ci.cluster.local.key | openssl sha256

# Verify certificate/key modulus matches for status.cluster.local
openssl x509 -noout -modulus \
  -in /etc/ssl/certs/status.cluster.local.crt | openssl sha256
openssl rsa -noout -modulus \
  -in /etc/ssl/private/status.cluster.local.key | openssl sha256

# Verify firewall
ufw status verbose
ufw status numbered

# Verify SSH hardening
grep -E '^PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config
sshd -t
systemctl status ssh --no-pager

# Verify Fail2ban
systemctl status fail2ban --no-pager
fail2ban-client ping
test -f /etc/fail2ban/jail.local

# Verify sysctl configuration
test -f /etc/sysctl.d/99-security.conf
sysctl --system
cat /etc/sysctl.d/99-security.conf

# Verify listeners
ss -tlnp | grep -E ':(80|443)\b'

# Verify default-site removal
test ! -e /etc/nginx/sites-enabled/default
```