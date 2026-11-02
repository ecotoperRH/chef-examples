---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx with three sites—**test.cluster.local**, **ci.cluster.local**, and **status.cluster.local**—using site-specific document roots, self-signed RSA 2048 TLS certificates, and enabled virtual-host links. It also installs Fail2ban and UFW, applies sysctl and SSH hardening, removes the default Nginx site, and renders global and per-site configuration. The exact attribute values, template listeners, security directives, and HTTP/HTTPS response behavior must be verified from the cookbook attributes and template files before migration.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP port `80` and HTTPS port `443`, subject to `site.conf.erb` verification
  - Key Config: Site configuration `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`; index `/opt/server/test/index.html`; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; `ssl_enabled: true` according to the supplied analysis

- **ci.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP port `80` and HTTPS port `443`, subject to `site.conf.erb` verification
  - Key Config: Site configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`; index `/opt/server/ci/index.html`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; `ssl_enabled: true` according to the supplied analysis

- **status.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP port `80` and HTTPS port `443`, subject to `site.conf.erb` verification
  - Key Config: Site configuration `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`; index `/opt/server/status/index.html`; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; `ssl_enabled: true` according to the supplied analysis

**Security Configuration**:

- **fail2ban**: Enabled by default; installs, enables, and starts the `fail2ban` service; renders `/etc/fail2ban/jail.local`.
- **ufw**: Enabled by default; sets the default incoming policy to deny and allows SSH, HTTP, and HTTPS.
- **ssh**: Configured with `disable_root: true` and `password_auth: false` according to the supplied analysis; disables root SSH login and SSH password authentication. The SSH service resource has action `nothing`.

The values above require confirmation from `cookbooks/nginx-multisite/attributes/default.rb`. The supplied analysis confirms the three site names and the security areas but does not include the complete attributes file.

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

No static files under `files/default/*` or `files/*` are listed in the supplied analysis. The cookbook declares `cookbook_file` resources for the following index files, but their source files are not present in the supplied directory listing:

```text
test.cluster.local/index.html
ci.cluster.local/index.html
status.cluster.local/index.html
```

Verify source-file availability before implementing the Ansible role.

## Module Explanation

The cookbook performs operations in this order:

1. `cookbooks/nginx-multisite/recipes/default.rb`
2. `cookbooks/nginx-multisite/recipes/security.rb`
3. `cookbooks/nginx-multisite/recipes/nginx.rb`
4. `cookbooks/nginx-multisite/recipes/ssl.rb`
5. `cookbooks/nginx-multisite/recipes/sites.rb`

### 1. `default` (`cookbooks/nginx-multisite/recipes/default.rb`)

- Includes `cookbooks/nginx-multisite/recipes/security.rb`.
- Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
- Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
- Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
- Preserves the execution order: security, Nginx, TLS, then site configuration.

### 2. `security` (`cookbooks/nginx-multisite/recipes/security.rb`)

- Installs:
  - `fail2ban`
  - `ufw`
- Enables and starts the `fail2ban` service.
- Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
- Applies UFW commands in this order:
  1. `ufw --force default deny`
  2. `ufw allow ssh`
  3. `ufw allow http`
  4. `ufw allow https`
  5. `ufw --force enable`
- Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
- Defines `sysctl -p /etc/sysctl.d/99-security.conf` with action `nothing`; no active notification or trigger is shown, so Ansible should explicitly apply the settings if activation is required.
- When `disable_root` is enabled, changes `/etc/ssh/sshd_config` to `PermitRootLogin no`.
- When `password_auth` is false, changes `/etc/ssh/sshd_config` to `PasswordAuthentication no`.
- Defines the SSH service with action `nothing`; no active SSH restart, reload, enable, or start is shown.
- Uses `community.general.ufw` for the equivalent firewall state and `ansible.builtin.lineinfile` for SSH settings.

Resources: one package resource installing two packages, two service resources, two templates, five UFW execute resources, two conditional SSH execute resources, and one inactive sysctl execute resource.

### 3. `nginx` (`cookbooks/nginx-multisite/recipes/nginx.rb`)

- Installs the `nginx` package.
- Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
- Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
- Enables and starts the `nginx` service.
- Creates the following document roots with mode `0755`:
  - `/opt/server/test`
  - `/opt/server/ci`
  - `/opt/server/status`
- Deploys the following index files with mode `0644`:
  - Source `test.cluster.local/index.html` to `/opt/server/test/index.html`
  - Source `ci.cluster.local/index.html` to `/opt/server/ci/index.html`
  - Source `status.cluster.local/index.html` to `/opt/server/status/index.html`
- The source availability of all three `cookbook_file` inputs remains unverified.
- No Nginx reload or restart notification is shown for configuration changes. Ansible should run `nginx -t` and reload Nginx when changed configuration requires activation.

Iterations:

- **test.cluster.local**: Creates `/opt/server/test` and deploys `/opt/server/test/index.html`.
- **ci.cluster.local**: Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html`.
- **status.cluster.local**: Creates `/opt/server/status` and deploys `/opt/server/status/index.html`.

### 4. `ssl` (`cookbooks/nginx-multisite/recipes/ssl.rb`)

- Installs:
  - `openssl`
  - `ca-certificates`
- Creates the `ssl-cert` group.
- Creates `/etc/ssl/certs` with mode `0755` and group `root`.
- Creates `/etc/ssl/private` with mode `0710` and group `ssl-cert`.
- Generates self-signed certificates using RSA 2048 keys, 365-day validity, and the subject pattern:
  `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com`
- Uses `-nodes`, so the private keys have no passphrase.
- Sets each private key to mode `0640` and owner/group `root:ssl-cert`.

Iterations:

- **test.cluster.local**:
  - Key: `/etc/ssl/private/test.cluster.local.key`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Common name: `test.cluster.local`

- **ci.cluster.local**:
  - Key: `/etc/ssl/private/ci.cluster.local.key`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Common name: `ci.cluster.local`

- **status.cluster.local**:
  - Key: `/etc/ssl/private/status.cluster.local.key`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Common name: `status.cluster.local`

### 5. `sites` (`cookbooks/nginx-multisite/recipes/sites.rb`)

- Renders the site template for all three configured sites.
- Creates an enabled-site link for all three configured sites.
- Removes `/etc/nginx/sites-enabled/default`.
- Does not show an explicit Nginx reload or restart after site changes.
- The exact listeners, redirects, security directives, and response behavior must be verified from `cookbooks/nginx-multisite/templates/default/site.conf.erb` and `cookbooks/nginx-multisite/templates/default/security.conf.erb`.

Iterations:

- **test.cluster.local**:
  - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local`.
  - Variables: `server_name: test.cluster.local`, `document_root: /opt/server/test`, `ssl_enabled: true`, certificate `/etc/ssl/certs/test.cluster.local.crt`, key `/etc/ssl/private/test.cluster.local.key`.
  - Sets mode `0644`.
  - Creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to the available-site configuration.

- **ci.cluster.local**:
  - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local`.
  - Variables: `server_name: ci.cluster.local`, `document_root: /opt/server/ci`, `ssl_enabled: true`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, key `/etc/ssl/private/ci.cluster.local.key`.
  - Sets mode `0644`.
  - Creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to the available-site configuration.

- **status.cluster.local**:
  - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local`.
  - Variables: `server_name: status.cluster.local`, `document_root: /opt/server/status`, `ssl_enabled: true`, certificate `/etc/ssl/certs/status.cluster.local.crt`, key `/etc/ssl/private/status.cluster.local.key`.
  - Sets mode `0644`.
  - Creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to the available-site configuration.

## Dependencies

**External cookbook dependencies**: Not specified in the supplied metadata analysis.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `nginx`: Enabled and started.
- `fail2ban`: Enabled and started.
- `ssh`: Referenced with action `nothing`; no active service action is shown.

## Credentials

**Detection Summary**: 3 generated TLS private keys detected across 3 site instances. No external secret manager, data bag, Chef Vault, CyberArk, Conjur, environment-variable secret, database credential, API token, or hardcoded password was detected.

**Source**:

- **Provider**: Hardcoded/generated locally by OpenSSL
- **URL**: None detected
- **Path**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`

### TLS private key for `test.cluster.local`

- **Variable(s)**: `key_file`, resolved to `/etc/ssl/private/test.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated file
- **Usage context**: HTTPS private key for the `test.cluster.local` Nginx virtual host
- **Permissions**: `0640`
- **Owner/group**: `root:ssl-cert`

### TLS private key for `ci.cluster.local`

- **Variable(s)**: `key_file`, resolved to `/etc/ssl/private/ci.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated file
- **Usage context**: HTTPS private key for the `ci.cluster.local` Nginx virtual host
- **Permissions**: `0640`
- **Owner/group**: `root:ssl-cert`

### TLS private key for `status.cluster.local`

- **Variable(s)**: `key_file`, resolved to `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated file
- **Usage context**: HTTPS private key for the `status.cluster.local` Nginx virtual host
- **Permissions**: `0640`
- **Owner/group**: `root:ssl-cert`

The certificates are self-signed and use the following non-secret subject values:

```text
C=US
ST=Example
L=Example
O=Example Org
OU=IT
emailAddress=admin@example.com
```

No password is used because OpenSSL is invoked with `-nodes`.

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
- `/etc/nginx/sites-enabled/default` — must be absent
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`

**Service endpoints to check**:

- HTTP port `80`, subject to `site.conf.erb` verification
- HTTPS port `443`, subject to `site.conf.erb` verification
- SSH port `22`, allowed by UFW
- Unix sockets: none specified

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render

## Pre-flight checks:

```bash
# Verify attributes and source files before migration
sed -n '1,240p' cookbooks/nginx-multisite/attributes/default.rb
find cookbooks/nginx-multisite -type f | sort
test -f cookbooks/nginx-multisite/templates/default/site.conf.erb
test -f cookbooks/nginx-multisite/templates/default/security.conf.erb
test -f cookbooks/nginx-multisite/test.cluster.local/index.html
test -f cookbooks/nginx-multisite/ci.cluster.local/index.html
test -f cookbooks/nginx-multisite/status.cluster.local/index.html

# Package verification
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Service status
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Nginx configuration validation
nginx -t
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
grep -nE 'worker|events|http|include' /etc/nginx/nginx.conf
sed -n '1,240p' /etc/nginx/conf.d/security.conf

# Verify default site removal
test ! -e /etc/nginx/sites-enabled/default

# Verify UFW state and rules
ufw status verbose
ufw status numbered
ufw status | grep -E '22|80|443'

# Verify Fail2ban and sysctl configuration
test -f /etc/fail2ban/jail.local
test -f /etc/sysctl.d/99-security.conf
grep -nE 'net\.|kernel\.' /etc/sysctl.d/99-security.conf

# Verify SSH hardening
grep -n '^PermitRootLogin no$' /etc/ssh/sshd_config
grep -n '^PasswordAuthentication no$' /etc/ssh/sshd_config

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%A %U:%G %n' /etc/ssl/private/test.cluster.local.key
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%A %U:%G %n' /etc/ssl/private/ci.cluster.local.key
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%A %U:%G %n' /etc/ssl/private/status.cluster.local.key
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Certificate identity and validity
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

# Network listening checks
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN

# Service logs
journalctl -u nginx --no-pager -n 50
journalctl -u fail2ban --no-pager -n 50

# Confirm configured log locations
grep -n 'error_log\|access_log' /etc/nginx/nginx.conf
```