---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook deploys and secures an Nginx web server hosting three HTTPS-enabled sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and configures Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; applies kernel and SSH security settings; generates self-signed certificates; creates site content directories and index files; deploys one Nginx virtual host per site; enables the sites; and removes the default Nginx site.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; site configuration `/etc/nginx/sites-available/test.cluster.local`; enabled-site symlink `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; site configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled-site symlink `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; site configuration `/etc/nginx/sites-available/status.cluster.local`; enabled-site symlink `/etc/nginx/sites-enabled/status.cluster.local`

Security configuration:

- **Fail2ban**: Enabled, installed, enabled, and started
- **UFW**: Enabled with default incoming traffic denied; SSH, HTTP, and HTTPS allowed
- **SSH**: Root login disabled; password authentication disabled; the SSH service is declared with action `nothing`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
cookbooks/nginx-multisite/
├── attributes/
│   └── default.rb
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── templates/
│   └── default/
│       ├── fail2ban.jail.local.erb
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       └── sysctl-security.conf.erb
└── files/
    └── No static files are listed in the supplied cookbook structure.
```

No custom resource provider is used by the execution tree. The recipes use `cookbook_file` resources for site `index.html` files, but the corresponding static source files were not included in the provided directory listing.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - This ordering must be preserved in the migration. Security configuration runs before Nginx installation and site configuration.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures UFW with default incoming traffic denied.
   - Allows SSH, HTTP, and HTTPS through UFW.
   - Enables UFW using `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Declares `sysctl -p /etc/sysctl.d/99-security.conf` as an execute resource with action `nothing`; no automatic reload should be added unless a source notification is confirmed.
   - Changes `PermitRootLogin` to `no` in `/etc/ssh/sshd_config`.
   - Changes `PasswordAuthentication` to `no` in `/etc/ssh/sshd_config`.
   - Declares the `ssh` service with action `nothing`; an automatic SSH restart or reload must not be assumed.
   - Resources include one package resource installing two packages, two service resources, two template resources, and eight execute resources: five UFW commands, one sysctl command, one root-login command, and one password-authentication command.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` with mode `0755`.
   - Deploys `/opt/server/test/index.html` with mode `0644` using the dynamic `test/index.html` cookbook source.
   - Creates `/opt/server/ci` with mode `0755`.
   - Deploys `/opt/server/ci/index.html` with mode `0644` using the dynamic `ci/index.html` cookbook source.
   - Creates `/opt/server/status` with mode `0755`.
   - Deploys `/opt/server/status/index.html` with mode `0644` using the dynamic `status/index.html` cookbook source.
   - The supplied directory listing does not identify the concrete static source files represented by these dynamic cookbook sources. The migration must map the actual source content without inventing an unspecified source filename.
   - The recipe processes exactly `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates a self-signed certificate and RSA private key for `test.cluster.local`.
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-test.cluster.local]`
   - Generates a self-signed certificate and RSA private key for `ci.cluster.local`.
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-ci.cluster.local]`
   - Generates a self-signed certificate and RSA private key for `status.cluster.local`.
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Resource: `execute[generate-ssl-cert-status.cluster.local]`
   - Certificate generation uses X.509 certificates valid for 365 days, RSA keys with 2048 bits, and `-nodes` for unencrypted private keys.
   - Certificate subject values are country `US`, state `Example`, locality `Example`, organization `Example Org`, organizational unit `IT`, the corresponding site name as common name, and `admin@example.com` as email.
   - Private keys use mode `0640`, owner `root`, and group `ssl-cert`.
   - The recipe processes exactly `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
     - `server_name`: `test.cluster.local`
     - `document_root`: `/opt/server/test`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/test.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/test.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symlink to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
     - `server_name`: `ci.cluster.local`
     - `document_root`: `/opt/server/ci`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/ci.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/ci.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symlink to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
     - `server_name`: `status.cluster.local`
     - `document_root`: `/opt/server/status`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/status.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/status.cluster.local.key`
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symlink to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - The recipe processes exactly `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.

## Dependencies

**External cookbook dependencies**: None provided in the supplied execution tree or structured metadata summary.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: declared with action `nothing`; no automatic restart or reload

## Credentials

**Detection Summary**: Three generated TLS private keys were detected across one recipe file. No externally stored credentials, passwords, API tokens, data bags, vault lookups, or secret-manager integrations were detected.

**Source**:
  - **Provider**: Local OpenSSL execution via Chef `execute` resources in `cookbooks/nginx-multisite/recipes/ssl.rb`; no external secret provider
  - **URL**: Not applicable
  - **Path**: `cookbooks/nginx-multisite/recipes/ssl.rb`

### Generated TLS Private Keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Generated locally by OpenSSL. No passphrase is configured because the command uses `-nodes`.
- **Usage context**: TLS private keys for the HTTPS Nginx virtual hosts.
- **Permissions and ownership**: Mode `0640`, owner `root`, group `ssl-cert`

### Certificate Subject Email

- **Variable/value**: `admin@example.com`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded in the OpenSSL certificate subject
- **Usage context**: Subject email field in all three self-signed certificates
- **Credential status**: Not an authentication secret

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, CyberArk data bags, Vault URL or secret path, environment-variable secrets, database connection credentials, hardcoded passwords, API keys, or access tokens were detected.

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
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`

**Service endpoints to check**:

- HTTP: port `80`
- HTTPS: port `443`
- SSH: existing SSH service port; no custom SSH port is defined
- Unix sockets: none specified

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 rendering
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 rendering
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 rendering
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 rendering
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 rendering
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 rendering
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 rendering

## Pre-flight checks:

```bash
# Package verification
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Fail2ban service
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban
test -f /etc/fail2ban/jail.local
fail2ban-client status
fail2ban-client status sshd

# Nginx service
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx
nginx -t

# UFW status and expected rules
ufw status verbose
ufw status numbered
# Verify default incoming policy is deny and SSH, HTTP, and HTTPS are allowed

# Kernel security configuration
test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# SSH hardening
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config

# Main Nginx configuration
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
curl -I -H 'Host: test.cluster.local' http://127.0.0.1
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
curl -I -H 'Host: status.cluster.local' http://127.0.0.1
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local

# Default site must be removed
test ! -e /etc/nginx/sites-enabled/default

# TLS private-key permissions
stat -c '%U:%G %a %n' \
  /etc/ssl/private/test.cluster.local.key \
  /etc/ssl/private/ci.cluster.local.key \
  /etc/ssl/private/status.cluster.local.key

# Expected key ownership and mode:
# root:ssl-cert 640

# Listening ports
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

# Nginx process and logs
pgrep -a nginx
journalctl -u nginx --no-pager -n 50
```

HTTP checks must return successful responses for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. HTTPS checks use `-k` because the cookbook generates self-signed certificates rather than certificates from a public certificate authority.