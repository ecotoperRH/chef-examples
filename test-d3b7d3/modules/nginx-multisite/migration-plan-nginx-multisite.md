---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server for three HTTPS-enabled virtual sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; applies firewall, kernel, and SSH hardening; creates document roots and placeholder index files; generates self-signed certificates; renders and enables one Nginx virtual-host configuration per site; and removes the default Nginx site.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`

- **ci.cluster.local**: HTTPS virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`

- **status.cluster.local**: HTTPS virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`

**Security configuration**:

- **fail2ban**
  - Enabled: `true`
  - Package: `fail2ban`
  - Service: `fail2ban`

- **ufw**
  - Enabled: `true`
  - Package: `ufw`
  - Default firewall policy: deny incoming
  - Allowed services: SSH, HTTP, HTTPS

- **ssh**
  - Disable root login: `true`
  - Password authentication: `false`

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

No provider files are used by the execution tree. The `resources/lineinfile.rb` file mentioned in structural analysis is not invoked by the execution tree and is excluded.

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

The recipes deploy `index.html` with `cookbook_file`, but the supplied directory listing does not provide the corresponding static file paths. Locate the actual source files before implementing Ansible `copy` tasks; do not invent source paths.

## Module Explanation

The cookbook performs operations in this order:

1. **Default entry recipe** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `cookbooks/nginx-multisite/recipes/security.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
   - The Ansible main task file must include these task files in the same order.

2. **Security configuration** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Sets the UFW default policy to deny:
     ```bash
     ufw --force default deny
     ```
   - Allows SSH:
     ```bash
     ufw allow ssh
     ```
   - Allows HTTP:
     ```bash
     ufw allow http
     ```
   - Allows HTTPS:
     ```bash
     ufw allow https
     ```
   - Enables UFW:
     ```bash
     ufw --force enable
     ```
   - Preserve the firewall order: default deny, allow SSH, allow HTTP, allow HTTPS, then enable UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Defines `execute[reload_sysctl]` with action `nothing` and command:
     ```bash
     sysctl -p /etc/sysctl.d/99-security.conf
     ```
   - The execution tree does not show a notification invoking `reload_sysctl`; do not automatically reload sysctl unless the migration design explicitly maps that behavior.
   - When `node['security']['ssh']['disable_root']` is `true`, updates `/etc/ssh/sshd_config` to:
     ```text
     PermitRootLogin no
     ```
     using a regular expression matching commented or uncommented settings.
   - When `node['security']['ssh']['password_auth'] == false`, updates `/etc/ssh/sshd_config` to:
     ```text
     PasswordAuthentication no
     ```
     using a regular expression matching commented or uncommented settings.
   - Defines the `ssh` service with action `nothing`; no start, enable, or restart action is shown.
   - Resource count: 1 package resource installing two packages, 2 service resources, 2 template resources, 6 unconditional execute resources, and 2 conditional SSH-hardening execute resources, for **8 execute resources total**.

3. **Nginx installation and document roots** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package without a specified version.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` and deploys `/opt/server/test/index.html` with mode `0644`; the `cookbook_file` source is dynamically formed from `test/index.html` and must be located before migration.
   - Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html` with mode `0644`; the `cookbook_file` source is dynamically formed from `ci/index.html` and must be located before migration.
   - Creates `/opt/server/status` and deploys `/opt/server/status/index.html` with mode `0644`; the `cookbook_file` source is dynamically formed from `status/index.html` and must be located before migration.
   - The structural analysis mentions `group 'www-data'`, but the execution tree does not include that resource; do not add a separate `www-data` task without independently confirming the recipe requires it.

4. **SSL packages, directories, and certificates** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`, preserving the intended `root:ssl-cert` ownership and group handling confirmed from the recipe.
   - Generates a self-signed certificate and RSA 2048-bit private key for `test.cluster.local`:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Resource: `generate-ssl-cert-test.cluster.local`
     - Validity: 365 days
     - Common name: `test.cluster.local`
     - Subject email: `admin@example.com`
     - Private-key mode: `640`
     - Private-key ownership: `root:ssl-cert`
   - Generates a self-signed certificate and RSA 2048-bit private key for `ci.cluster.local`:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Resource: `generate-ssl-cert-ci.cluster.local`
     - Validity: 365 days
     - Common name: `ci.cluster.local`
     - Subject email: `admin@example.com`
     - Private-key mode: `640`
     - Private-key ownership: `root:ssl-cert`
   - Generates a self-signed certificate and RSA 2048-bit private key for `status.cluster.local`:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Resource: `generate-ssl-cert-status.cluster.local`
     - Validity: 365 days
     - Common name: `status.cluster.local`
     - Subject email: `admin@example.com`
     - Private-key mode: `640`
     - Private-key ownership: `root:ssl-cert`
   - Each of the three sites has `ssl_enabled: true`; no SSL iteration is skipped.

5. **Virtual-host configuration and site activation** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with:
     - `server_name`: `test.cluster.local`
     - `document_root`: `/opt/server/test`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/test.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/test.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` pointing to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with:
     - `server_name`: `ci.cluster.local`
     - `document_root`: `/opt/server/ci`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/ci.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/ci.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` pointing to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with:
     - `server_name`: `status.cluster.local`
     - `document_root`: `/opt/server/status`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/status.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/status.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` pointing to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - No Nginx reload or restart notification is shown for templates, links, or default-site deletion. Add a handler only if the intended migrated behavior is to validate and reload Nginx.

## Dependencies

**External cookbook dependencies**: None shown in the execution tree; external cookbook dependency information is otherwise unavailable.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

No package versions are specified.

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: referenced with action `nothing`; not started, enabled, or restarted by the execution tree

## Credentials

**Detection Summary**: No external credentials were detected. Three generated TLS private keys and three generated self-signed certificates are created locally across two recipe files; no data bags, vault integrations, API tokens, database passwords, or external secret providers were identified.

**Source**:
  - **Provider**: None detected
  - **URL**: None detected
  - **Path**: No data-bag, vault, CyberArk, or external secret path detected

### Generated TLS Private Keys

- **Variable(s)**: `key_file`, `node['nginx']['ssl']['private_key_path']`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by the OpenSSL command; not stored in a data bag or vault.
- **Usage context**: Nginx HTTPS private keys for:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Permissions**: Mode `640`, ownership `root:ssl-cert`.

### Generated Self-Signed Certificates

- **Variable(s)**: `cert_file`, `node['nginx']['ssl']['certificate_path']`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL.
- **Usage context**: Nginx HTTPS server certificates:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Certificate properties**: Self-signed, RSA 2048-bit key, valid for 365 days, with a site-specific common name.

### Certificate Subject Email

- **Variable/value**: `admin@example.com`
- **Source file**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded in the OpenSSL subject string.
- **Usage context**: Certificate subject metadata only; it is not an authentication credential.

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
- `/opt/server/test`
- `/opt/server/test/index.html`
- `/opt/server/ci`
- `/opt/server/ci/index.html`
- `/opt/server/status`
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
- `/etc/nginx/sites-enabled/default` — must not exist after migration

**Service endpoints to check**:

- HTTP: port `80`
- HTTPS: port `443`
- SSH: UFW service `ssh`; no numeric SSH port is specified
- `test.cluster.local`: HTTP and HTTPS
- `ci.cluster.local`: HTTP and HTTPS
- `status.cluster.local`: HTTP and HTTPS

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb`: 1 render to `/etc/fail2ban/jail.local`
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb`: 1 render to `/etc/nginx/nginx.conf`
- `cookbooks/nginx-multisite/templates/default/security.conf.erb`: 1 render to `/etc/nginx/conf.d/security.conf`
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb`: 1 render to `/etc/sysctl.d/99-security.conf`
- `cookbooks/nginx-multisite/templates/default/site.conf.erb`: 3 renders:
  - `/etc/nginx/sites-available/test.cluster.local`
  - `/etc/nginx/sites-available/ci.cluster.local`
  - `/etc/nginx/sites-available/status.cluster.local`

## Pre-flight checks:

```bash
# Package verification
dpkg -l nginx
dpkg -l fail2ban
dpkg -l ufw
dpkg -l openssl
dpkg -l ca-certificates

# Service status
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

# Nginx configuration syntax
nginx -t

# Listening ports
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

# Nginx process and logs
ps aux | grep '[n]ginx'
journalctl -u nginx --no-pager -n 100

# Test site
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -I --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/

# CI site
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -I --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/

# Status site
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -I --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/

# UFW status and rules
ufw status verbose

# Expected firewall behavior:
# - Default incoming policy: deny
# - SSH allowed
# - HTTP allowed
# - HTTPS allowed

# Fail2ban status
fail2ban-client status
systemctl status fail2ban

# Sysctl configuration
cat /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# SSH hardening
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config

# SSL group and key permissions
getent group ssl-cert
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key

# Confirm the default site was removed
test ! -e /etc/nginx/sites-enabled/default
```