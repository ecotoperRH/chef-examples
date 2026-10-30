---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an Nginx web server hosting three HTTPS-enabled sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and starts Nginx and Fail2ban, configures UFW to allow SSH, HTTP, and HTTPS, applies kernel security settings, disables root SSH login and SSH password authentication when the corresponding attributes are enabled, creates self-signed certificates for all three sites, deploys site content, and enables Nginx virtual-host symlinks. Attribute values for the SSH settings, SSL paths, and site collection are referenced by the recipes but were not independently verified because the supplied analysis omitted the contents of `attributes/default.rb`.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **`test.cluster.local`**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; site configuration `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`; SSL enabled

- **`ci.cluster.local`**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; site configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`; SSL enabled

- **`status.cluster.local`**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; site configuration `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`; SSL enabled

**Security services and configuration areas**:

- **`fail2ban`**: Enabled and started as `fail2ban`; configuration at `/etc/fail2ban/jail.local`
- **`ufw`**: Enabled with a default deny policy; SSH, HTTP, and HTTPS are allowed
- **`ssh`**: The recipe references `disable_root` and `password_auth` attributes to disable root login and password authentication. Their values are not independently verified in the supplied attribute analysis.

## File Structure

The following paths are relative to the cookbook root, `cookbooks/nginx-multisite`.

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

No provider files are used by the execution tree.

**Templates:**

```text
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/sysctl-security.conf.erb
```

**Attributes:**

```text
attributes/default.rb
```

**Files:**

No static files under `files/default/` or `files/` are listed in the supplied cookbook analysis. The recipes deploy `index.html` using `cookbook_file`, but the source file paths are dynamic and the corresponding static files are not included in the supplied directory listing.

## Module Explanation

The cookbook performs operations in this order:

1. **Default entry recipe** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `cookbooks/nginx-multisite/recipes/security.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
   - Uses four `include_recipe` resources.

2. **Security configuration** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Sets the UFW default policy to deny.
   - Allows SSH with `ufw allow ssh`.
   - Allows HTTP with `ufw allow http`.
   - Allows HTTPS with `ufw allow https`.
   - Enables UFW with `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Defines `sysctl -p /etc/sysctl.d/99-security.conf` as `execute[reload_sysctl]` with action `nothing`; the supplied execution tree does not identify its notification trigger.
   - Conditionally executes the root-login hardening command when `node['security']['ssh']['disable_root']` is enabled:
     ```bash
     sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
     ```
   - Conditionally executes the password-authentication hardening command when `node['security']['ssh']['password_auth'] == false`:
     ```bash
     sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
     ```
   - Defines `service[ssh]` with action `nothing`; no triggering notification is identified.
   - Resource totals: one package resource installing two packages, two services, two templates, and eight execute resources.

3. **Nginx installation and document roots** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` and deploys `/opt/server/test/index.html` for `test.cluster.local`.
   - Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html` for `ci.cluster.local`.
   - Creates `/opt/server/status` and deploys `/opt/server/status/index.html` for `status.cluster.local`.
   - The three `index.html` files use dynamic `cookbook_file` source paths represented by `#{site_folder}/index.html`.
   - Resource totals: one package, two templates, one service, three directories, and three cookbook files.
   - No explicit Nginx reload or restart trigger is shown for configuration changes.

4. **SSL package, directories, and certificates** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710` and group `ssl-cert`.
   - Generates the following certificate and key for `test.cluster.local`:
     - Key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Certificate: self-signed, RSA 2048-bit, valid for 365 days
     - Subject common name: `test.cluster.local`
     - Subject fields: `C=US`, `ST=Example`, `L=Example`, `O=Example Org`, `OU=IT`, and `emailAddress=admin@example.com`
     - Key mode and ownership: `0640`, `root:ssl-cert`
   - Generates the following certificate and key for `ci.cluster.local`:
     - Key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Certificate: self-signed, RSA 2048-bit, valid for 365 days
     - Subject common name: `ci.cluster.local`
     - Key mode and ownership: `0640`, `root:ssl-cert`
   - Generates the following certificate and key for `status.cluster.local`:
     - Key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Certificate: self-signed, RSA 2048-bit, valid for 365 days
     - Subject common name: `status.cluster.local`
     - Key mode and ownership: `0640`, `root:ssl-cert`
   - Uses the command pattern:
     ```bash
     openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout <key_file> \
       -out <cert_file> \
       -subj "/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site_name>/emailAddress=admin@example.com"
     ```
   - Resource totals: one package resource installing two packages, one group, two directories, and three certificate-generation execute resources.

5. **Nginx virtual-host configuration** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local` with document root `/opt/server/test`, SSL enabled, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local`, inferred from the recipe to link to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local` with document root `/opt/server/ci`, SSL enabled, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local`, inferred from the recipe to link to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local` with document root `/opt/server/status`, SSL enabled, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local`, inferred from the recipe to link to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Resource totals: three templates, three links, and one file deletion.

## Dependencies

**External cookbook dependencies**: Not specified in the supplied metadata analysis.

**System package dependencies**:
- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: referenced as a notification target with action `nothing`; no explicit restart or reload is shown
- `ufw`: enabled through command execution
- Sysctl reload: defined as an execute resource with action `nothing`

## Credentials

**Detection Summary**: Six TLS artifacts detected: three locally generated private keys and three locally generated self-signed certificates. No external credential provider or secret-management integration was detected.

**Source**:
  - **Provider**: None detected
  - **URL**: None detected
  - **Path**: Local filesystem paths under `/etc/ssl/certs` and `/etc/ssl/private`

### TLS Private Keys

- **Variable(s)**: `node['nginx']['ssl']['private_key_path']`; site-specific key paths for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/attributes/default.rb`
- **Current storage**: Generated locally by OpenSSL; not stored in a data bag, vault, or external secret manager
- **Usage context**: Nginx TLS private keys with mode `0640` and ownership `root:ssl-cert`

### TLS Certificates

- **Variable(s)**: `node['nginx']['ssl']['certificate_path']`; site-specific certificate paths for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/attributes/default.rb`
- **Current storage**: Generated locally as self-signed certificates
- **Usage context**: Nginx TLS certificate configuration

### Certificate Subject Email

- **Variable/value**: `admin@example.com`
- **Source file**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded in the OpenSSL command
- **Usage context**: Subject email field in the generated self-signed certificates

No data bags, encrypted data bags, Chef Vault, Conjur, CyberArk, environment-variable secret lookups, database credentials, API keys, or hardcoded passwords were identified.

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
- `/etc/nginx/sites-enabled/default` must be absent
- `/opt/server/test`
- `/opt/server/test/index.html`
- `/opt/server/ci`
- `/opt/server/ci/index.html`
- `/opt/server/status`
- `/opt/server/status/index.html`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`

**Service endpoints to check**:
- `test.cluster.local`: HTTP TCP `80`, HTTPS TCP `443`
- `ci.cluster.local`: HTTP TCP `80`, HTTPS TCP `443`
- `status.cluster.local`: HTTP TCP `80`, HTTPS TCP `443`
- SSH: existing SSH port, normally TCP `22`, allowed through the UFW `ssh` application profile
- Unix sockets: none specified

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`; render count: 1
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`; render count: 1
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`; render count: 1
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`; render count: 1
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` →:
  - `/etc/nginx/sites-available/test.cluster.local`
  - `/etc/nginx/sites-available/ci.cluster.local`
  - `/etc/nginx/sites-available/status.cluster.local`
  - Render count: 3

## Pre-flight checks:

```bash
# Verify required packages
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Verify managed services
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

# Validate Nginx configuration
nginx -t

# Verify Nginx configuration files
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
test -f /etc/nginx/sites-available/test.cluster.local
test -f /etc/nginx/sites-available/ci.cluster.local
test -f /etc/nginx/sites-available/status.cluster.local

# Verify enabled links
readlink -f /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test ! -e /etc/nginx/sites-enabled/default

# Verify test.cluster.local content
test -d /opt/server/test
test -f /opt/server/test/index.html
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%a %U:%G' /etc/ssl/private/test.cluster.local.key
openssl x509 -noout -modulus -in /etc/ssl/certs/test.cluster.local.crt | openssl md5
openssl rsa -noout -modulus -in /etc/ssl/private/test.cluster.local.key | openssl md5
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject | grep 'CN = test.cluster.local'
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

# Verify ci.cluster.local content
test -d /opt/server/ci
test -f /opt/server/ci/index.html
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%a %U:%G' /etc/ssl/private/ci.cluster.local.key
openssl x509 -noout -modulus -in /etc/ssl/certs/ci.cluster.local.crt | openssl md5
openssl rsa -noout -modulus -in /etc/ssl/private/ci.cluster.local.key | openssl md5
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject | grep 'CN = ci.cluster.local'
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

# Verify status.cluster.local content
test -d /opt/server/status
test -f /opt/server/status/index.html
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%a %U:%G' /etc/ssl/private/status.cluster.local.key
openssl x509 -noout -modulus -in /etc/ssl/certs/status.cluster.local.crt | openssl md5
openssl rsa -noout -modulus -in /etc/ssl/private/status.cluster.local.key | openssl md5
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject | grep 'CN = status.cluster.local'
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Verify security configuration
test -f /etc/fail2ban/jail.local
test -f /etc/sysctl.d/99-security.conf
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config
sysctl -p /etc/sysctl.d/99-security.conf

# Verify firewall rules
ufw status verbose
ufw status | grep -E '22|80|443|ssh|http|https'

# Verify Fail2ban
fail2ban-client status
fail2ban-client status sshd

# Verify listeners
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN

# Review service logs
journalctl -u nginx --no-pager -n 50
journalctl -u fail2ban --no-pager -n 50
```

Migration execution must preserve the recipe order: security preparation, Nginx installation and base configuration, certificate generation, and virtual-host configuration. Nginx configuration validation should run after the site files and enabled-site links are present.