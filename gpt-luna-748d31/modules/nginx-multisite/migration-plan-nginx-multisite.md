---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx for three virtual sites—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`—with separate document roots, virtual-host configurations, and HTTPS certificate references. It also installs and configures Fail2ban, UFW, SSH hardening, and kernel security settings. All sites have `ssl_enabled: True`, so the conditional self-signed certificate commands are not executed with the supplied defaults. The rendered Nginx templates must be checked to confirm exact listen addresses and ports.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Static Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80` and HTTPS `443`, if configured by the rendered template
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`
  - Nginx configuration:
    - `/etc/nginx/sites-available/test.cluster.local`
    - `/etc/nginx/sites-enabled/test.cluster.local`
  - Static content: `/opt/server/test/index.html`

- **ci.cluster.local**: Static Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80` and HTTPS `443`, if configured by the rendered template
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`
  - Nginx configuration:
    - `/etc/nginx/sites-available/ci.cluster.local`
    - `/etc/nginx/sites-enabled/ci.cluster.local`
  - Static content: `/opt/server/ci/index.html`

- **status.cluster.local**: Static Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80` and HTTPS `443`, if configured by the rendered template
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`
  - Nginx configuration:
    - `/etc/nginx/sites-available/status.cluster.local`
    - `/etc/nginx/sites-enabled/status.cluster.local`
  - Static content: `/opt/server/status/index.html`

**Security services and settings**:

- **fail2ban**
  - Enabled and started
  - Managed service: `fail2ban`

- **ufw**
  - Enabled
  - Default policy: deny
  - Allows SSH, HTTP, and HTTPS through the `ssh`, `http`, and `https` application rules

- **ssh**
  - Root login disabled: `disable_root: true`
  - Password authentication disabled: `password_auth: false`
  - The recipe does not explicitly restart or reload SSH

**Network ports**:

- SSH: permitted through the UFW `ssh` application rule
- HTTP: permitted through the UFW `http` application rule, normally port `80`
- HTTPS: permitted through the UFW `https` application rule, normally port `443`

The supplied execution tree does not show explicit `listen` directives from the rendered templates. Confirm the exact Nginx bind addresses and ports from the rendered `site.conf.erb` output.

## File Structure

The following files are relevant to the migration and are limited to files shown in the supplied cookbook analysis.

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

No provider files are used by the executed recipe tree.

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

No static files under `files/default/` or `files/` were listed. The site `index.html` files are deployed through `cookbook_file`, but their source locations are dynamic in the recipe and are not included in the supplied directory listing.

## Module Explanation

The cookbook performs operations in this order:

1. `cookbooks/nginx-multisite/recipes/default.rb`
2. `cookbooks/nginx-multisite/recipes/security.rb`
3. `cookbooks/nginx-multisite/recipes/nginx.rb`
4. `cookbooks/nginx-multisite/recipes/ssl.rb`
5. `cookbooks/nginx-multisite/recipes/sites.rb`

### 1. Default entry recipe

**File**: `cookbooks/nginx-multisite/recipes/default.rb`

- Includes `cookbooks/nginx-multisite/recipes/security.rb`
- Includes `cookbooks/nginx-multisite/recipes/nginx.rb`
- Includes `cookbooks/nginx-multisite/recipes/ssl.rb`
- Includes `cookbooks/nginx-multisite/recipes/sites.rb`
- Preserves the execution order so security configuration runs first, Nginx is installed before site configuration, and SSL directories exist before certificate paths are referenced.

### 2. Security configuration

**File**: `cookbooks/nginx-multisite/recipes/security.rb`

- Installs `fail2ban` and `ufw`.
- Enables and starts the `fail2ban` service.
- Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
- Applies UFW rules in this order:
  1. `ufw --force default deny`
  2. `ufw allow ssh`
  3. `ufw allow http`
  4. `ufw allow https`
  5. `ufw --force enable`
- Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
- Declares `sysctl -p /etc/sysctl.d/99-security.conf` as `execute[reload_sysctl]` with `action: nothing`. No notification is shown, so it remains inactive under the supplied Chef execution tree.
- When `node['security']['ssh']['disable_root']` is `true`, executes:
  ```bash
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  ```
- When `node['security']['ssh']['password_auth'] == false`, executes:
  ```bash
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  ```
- Declares the SSH service with `action: nothing`; no restart or reload is performed by the supplied recipe.

**Resource counts**:

- Package: 1
- Service: 2
- Template: 2
- Execute: 8
- Total declared resources: 13

The eight execute resources are `ufw_default_deny`, `ufw_allow_ssh`, `ufw_allow_http`, `ufw_allow_https`, `ufw_enable`, `reload_sysctl`, `disable root login`, and `disable password auth`.

### 3. Nginx installation and document roots

**File**: `cookbooks/nginx-multisite/recipes/nginx.rb`

- Installs the `nginx` package.
- Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
- Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
- Enables and starts the `nginx` service.

The recipe expands the site iteration into the following operations:

#### Site: `test.cluster.local`

- Creates `/opt/server/test` with mode `0755`.
- Deploys `/opt/server/test/index.html` with mode `0644`.

#### Site: `ci.cluster.local`

- Creates `/opt/server/ci` with mode `0755`.
- Deploys `/opt/server/ci/index.html` with mode `0644`.

#### Site: `status.cluster.local`

- Creates `/opt/server/status` with mode `0755`.
- Deploys `/opt/server/status/index.html` with mode `0644`.

**Resource counts**:

- Package: 1
- Template: 2
- Service: 1
- Directory: 3
- Cookbook file: 3

### 4. SSL package and certificate directories

**File**: `cookbooks/nginx-multisite/recipes/ssl.rb`

- Installs `openssl` and `ca-certificates`.
- Creates the `ssl-cert` group.
- Creates `/etc/ssl/certs` with mode `0755` and group `root`.
- Creates `/etc/ssl/private` with mode `0710` and group `ssl-cert`.

Conditional certificate-generation logic is evaluated for all three sites:

#### Site: `test.cluster.local`

If `ssl_enabled` is `false`, declares `execute[generate-ssl-cert-test.cluster.local]` to generate:

- Certificate: `/etc/ssl/certs/test.cluster.local.crt`
- Private key: `/etc/ssl/private/test.cluster.local.key`
- 2048-bit RSA self-signed certificate
- Validity: 365 days
- Common Name: `test.cluster.local`
- Subject email: `admin@example.com`
- Key mode: `640`
- Key ownership: `root:ssl-cert`

#### Site: `ci.cluster.local`

If `ssl_enabled` is `false`, declares `execute[generate-ssl-cert-ci.cluster.local]` to generate:

- Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
- Private key: `/etc/ssl/private/ci.cluster.local.key`
- 2048-bit RSA self-signed certificate
- Validity: 365 days
- Common Name: `ci.cluster.local`
- Subject email: `admin@example.com`
- Key mode: `640`
- Key ownership: `root:ssl-cert`

#### Site: `status.cluster.local`

If `ssl_enabled` is `false`, declares `execute[generate-ssl-cert-status.cluster.local]` to generate:

- Certificate: `/etc/ssl/certs/status.cluster.local.crt`
- Private key: `/etc/ssl/private/status.cluster.local.key`
- 2048-bit RSA self-signed certificate
- Validity: 365 days
- Common Name: `status.cluster.local`
- Subject email: `admin@example.com`
- Key mode: `640`
- Key ownership: `root:ssl-cert`

All three sites have `ssl_enabled: True`, so zero certificate-generation commands execute with the supplied defaults.

**Resource counts**:

- Package: 1
- Group: 1
- Directory: 2
- Conditional execute resources: 3 possible declarations, 0 executed by default

### 5. Per-site Nginx virtual-host configuration

**File**: `cookbooks/nginx-multisite/recipes/sites.rb`

The recipe renders one configuration, creates one enabled-site link, and processes one site per configured hostname.

#### Site: `test.cluster.local`

- Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`.
- Template variables:
  - `server_name`: `test.cluster.local`
  - `document_root`: `/opt/server/test`
  - `ssl_enabled`: `True`
  - `cert_file`: `/etc/ssl/certs/test.cluster.local.crt`
  - `key_file`: `/etc/ssl/private/test.cluster.local.key`
- File mode: `0644`
- Creates link `/etc/nginx/sites-enabled/test.cluster.local`.

#### Site: `ci.cluster.local`

- Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`.
- Template variables:
  - `server_name`: `ci.cluster.local`
  - `document_root`: `/opt/server/ci`
  - `ssl_enabled`: `True`
  - `cert_file`: `/etc/ssl/certs/ci.cluster.local.crt`
  - `key_file`: `/etc/ssl/private/ci.cluster.local.key`
- File mode: `0644`
- Creates link `/etc/nginx/sites-enabled/ci.cluster.local`.

#### Site: `status.cluster.local`

- Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`.
- Template variables:
  - `server_name`: `status.cluster.local`
  - `document_root`: `/opt/server/status`
  - `ssl_enabled`: `True`
  - `cert_file`: `/etc/ssl/certs/status.cluster.local.crt`
  - `key_file`: `/etc/ssl/private/status.cluster.local.key`
- File mode: `0644`
- Creates link `/etc/nginx/sites-enabled/status.cluster.local`.

After all three site configurations are processed, deletes `/etc/nginx/sites-enabled/default`.

No Nginx reload or restart is shown after the site templates and links change. Preserve that behavior unless the migration intentionally adds a validated `nginx -t` notification followed by an Nginx reload.

**Resource counts**:

- Template: 3
- Link: 3
- File deletion: 1

## Dependencies

**External cookbook dependencies**: Not specified; metadata contents were not supplied.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started by `cookbooks/nginx-multisite/recipes/security.rb`
- `nginx`: enabled and started by `cookbooks/nginx-multisite/recipes/nginx.rb`
- `ssh`: referenced with `action: nothing`; the recipe modifies `/etc/ssh/sshd_config` but does not restart or reload SSH

## Credentials

**Detection Summary**: No passwords, API keys, data bags, encrypted data bags, Chef Vault items, CyberArk references, Conjur variables, or database credentials were detected. SSL private-key and certificate paths are configuration artifacts, not secret-store credentials.

**Source**:

- **Provider**: None detected
- **URL**: None detected
- **Path**: No secret-manager path or data-bag name detected

### SSL private keys

- **Variable(s)**:
  - `node['nginx']['ssl']['private_key_path']`
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/attributes/default.rb`
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Filesystem paths; no key material is supplied in the analyzed cookbook.
- **Usage context**: Nginx TLS private keys and optional self-signed certificate generation.

### SSL certificates

- **Variable(s)**:
  - `node['nginx']['ssl']['certificate_path']`
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/attributes/default.rb`
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Filesystem paths; certificates are not retrieved from a vault or data bag.
- **Usage context**: Nginx TLS certificate configuration.

### Certificate subject email

- **Variable(s)**: None; hardcoded as `admin@example.com`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded in the OpenSSL command
- **Usage context**: Subject email for optional self-signed certificates; not an authentication credential

No credentials or secrets were detected in the cookbook templates.

## Checks for the Migration

**Files to verify**:

- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
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
- `/etc/ssl/certs`
- `/etc/ssl/private`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/ssh/sshd_config`

**Service endpoints to check**:

- `test.cluster.local`: HTTP `80` and HTTPS `443`, if present in the rendered configuration
- `ci.cluster.local`: HTTP `80` and HTTPS `443`, if present in the rendered configuration
- `status.cluster.local`: HTTP `80` and HTTPS `443`, if present in the rendered configuration
- SSH: UFW `ssh` application rule; exact numeric port is not defined by the execution tree

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

## Pre-flight checks

```bash
# Verify installed packages
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Verify services
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx

systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

systemctl status ssh

# Verify firewall state
ufw status verbose

# Validate Nginx configuration
nginx -t

# Verify global configuration
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf

# Verify Fail2ban and kernel configuration
test -f /etc/fail2ban/jail.local
test -f /etc/sysctl.d/99-security.conf

# Verify SSH hardening
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config
sshd -t

# Verify UFW rules
ufw status | grep -E '22|ssh'
ufw status | grep -E '80|http'
ufw status | grep -E '443|https'

# Read-only kernel checks; do not use sysctl --system unless immediate reload
# is an intentional migration behavior change.
sysctl -a
```

### `test.cluster.local`

```bash
test -d /opt/server/test
test -f /opt/server/test/index.html
stat -c '%a %n' /opt/server/test /opt/server/test/index.html

test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/test.cluster.local

test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key

curl -I --resolve test.cluster.local:80:127.0.0.1 \
  http://test.cluster.local/

curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/
```

### `ci.cluster.local`

```bash
test -d /opt/server/ci
test -f /opt/server/ci/index.html
stat -c '%a %n' /opt/server/ci /opt/server/ci/index.html

test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/ci.cluster.local

test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key

curl -I --resolve ci.cluster.local:80:127.0.0.1 \
  http://ci.cluster.local/

curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/
```

### `status.cluster.local`

```bash
test -d /opt/server/status
test -f /opt/server/status/index.html
stat -c '%a %n' /opt/server/status /opt/server/status/index.html

test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/status.cluster.local

test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key

curl -I --resolve status.cluster.local:80:127.0.0.1 \
  http://status.cluster.local/

curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/
```

### SSL directories and network listeners

```bash
test -d /etc/ssl/certs
test -d /etc/ssl/private
stat -c '%a %U:%G %n' /etc/ssl/certs /etc/ssl/private

test ! -e /etc/nginx/sites-enabled/default

ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
ps aux | grep '[n]ginx'
```

If the three certificate files do not exist, confirm whether certificates are externally provisioned. The supplied defaults do not execute self-signed certificate generation. The exact Nginx interfaces and listen directives must be taken from the rendered virtual-host configurations.