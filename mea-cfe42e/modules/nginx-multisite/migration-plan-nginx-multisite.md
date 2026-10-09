---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx with three SSL-enabled sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and starts Nginx and Fail2ban, configures UFW with default-deny inbound traffic while allowing SSH, HTTP, and HTTPS, applies kernel security settings, disables root SSH login and password authentication, generates self-signed RSA 2048-bit certificates, deploys three Nginx virtual-host configurations, and removes the default Nginx site. The security and SSL attribute values are referenced by the recipes; the supplied validation data does not independently include their attribute definitions.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

The configured site collection contains exactly three sites and is iterated in `nginx.rb`, `ssl.rb`, and `sites.rb`.

- **test.cluster.local**: SSL-enabled Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port: `80` and `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Nginx configuration: `/etc/nginx/sites-available/test.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: SSL-enabled Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port: `80` and `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Nginx configuration: `/etc/nginx/sites-available/ci.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: SSL-enabled Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port: `80` and `443`
  - SSL: Enabled
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Nginx configuration: `/etc/nginx/sites-available/status.cluster.local`
  - Enabled link: `/etc/nginx/sites-enabled/status.cluster.local`

The security configuration contains exactly three named areas:

- **fail2ban**
  - Enabled: `true`
  - Installs and starts the `fail2ban` service.
  - Deploys `/etc/fail2ban/jail.local`.

- **ufw**
  - Enabled: `true`
  - Installs UFW.
  - Applies a default-deny firewall policy.
  - Allows SSH, HTTP, and HTTPS.
  - Enables the firewall.

- **ssh**
  - `disable_root`: `true`
  - `password_auth`: `false`
  - Disables SSH root login.
  - Disables SSH password authentication.

The supplied validation data references these configured values but does not include an independent attribute-analysis section confirming the definitions in `cookbooks/nginx-multisite/attributes/default.rb`.

## File Structure

Only files involved in the cookbook execution are listed below.

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

No static files from `files/default` or `files` are listed in the supplied cookbook structure. The `cookbook_file` resources reference site content paths, but no corresponding static file paths are provided and none are invented in this plan.

## Module Explanation

The cookbook performs operations in this order.

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `cookbooks/nginx-multisite/recipes/security.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
   - Execution order is security, Nginx installation, SSL generation, and site configuration.
   - Resources: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Applies the UFW default-deny policy with `ufw --force default deny`.
   - Allows SSH with `ufw allow ssh`.
   - Allows HTTP with `ufw allow http`.
   - Allows HTTPS with `ufw allow https`.
   - Enables UFW with `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Defines `execute[reload_sysctl]` with command `sysctl -p /etc/sysctl.d/99-security.conf` and action `nothing`; it is not automatically executed unless explicitly notified or invoked by equivalent task logic.
   - When `disable_root` is `true`, changes `/etc/ssh/sshd_config` to set `PermitRootLogin no`.
   - When `password_auth` is `false`, changes `/etc/ssh/sshd_config` to set `PasswordAuthentication no`.
   - Defines the `ssh` service with action `nothing`; no automatic SSH restart or reload is shown.
   - Iterations:
     - **fail2ban**: package installation, service enablement/start, and jail configuration.
     - **ufw**: package installation, default-deny policy, SSH allowance, HTTP allowance, HTTPS allowance, and firewall enablement.
     - **ssh**: root-login and password-authentication hardening.
   - Resources: one package resource, two service resources, two template resources, and eight execute resources:
     - `ufw_default_deny`
     - `ufw_allow_ssh`
     - `ufw_allow_http`
     - `ufw_allow_https`
     - `ufw_enable`
     - `reload_sysctl`
     - root-login disabling
     - password-authentication disabling

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates the document root and deploys the index file for **test.cluster.local**:
     - Directory: `/opt/server/test`
     - File: `/opt/server/test/index.html`
     - Source expression: `#{site_folder}/index.html`
     - Mode: `0644`
   - Creates the document root and deploys the index file for **ci.cluster.local**:
     - Directory: `/opt/server/ci`
     - File: `/opt/server/ci/index.html`
     - Source expression: `#{site_folder}/index.html`
     - Mode: `0644`
   - Creates the document root and deploys the index file for **status.cluster.local**:
     - Directory: `/opt/server/status`
     - File: `/opt/server/status/index.html`
     - Source expression: `#{site_folder}/index.html`
     - Mode: `0644`
   - Resources: one package, two templates, one service, three directories, and three `cookbook_file` resources.
   - No `www-data` group resource is present in the supplied execution tree.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates a self-signed RSA 2048-bit certificate for **test.cluster.local**:
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Validity: 365 days
     - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
     - Private-key mode: `0640`
     - Private-key owner/group: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate for **ci.cluster.local**:
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Validity: 365 days
     - Common Name: `ci.cluster.local`
     - Email: `admin@example.com`
     - Private-key mode: `0640`
     - Private-key owner/group: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate for **status.cluster.local**:
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Validity: 365 days
     - Common Name: `status.cluster.local`
     - Email: `admin@example.com`
     - Private-key mode: `0640`
     - Private-key owner/group: `root:ssl-cert`
   - Resources: one package resource installing two packages, one group, two directories, and three certificate-generation execute resources.
   - The configured certificate and private-key directory values are referenced through the SSL attributes; the supplied validation data does not independently verify those attribute definitions.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **test.cluster.local**:
     - Destination: `/etc/nginx/sites-available/test.cluster.local`
     - `server_name`: `test.cluster.local`
     - `document_root`: `/opt/server/test`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/test.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/test.cluster.local.key`
     - Mode: `0644`
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a symbolic link to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **ci.cluster.local**:
     - Destination: `/etc/nginx/sites-available/ci.cluster.local`
     - `server_name`: `ci.cluster.local`
     - `document_root`: `/opt/server/ci`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/ci.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/ci.cluster.local.key`
     - Mode: `0644`
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a symbolic link to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for **status.cluster.local**:
     - Destination: `/etc/nginx/sites-available/status.cluster.local`
     - `server_name`: `status.cluster.local`
     - `document_root`: `/opt/server/status`
     - `ssl_enabled`: `true`
     - `cert_file`: `/etc/ssl/certs/status.cluster.local.crt`
     - `key_file`: `/etc/ssl/private/status.cluster.local.key`
     - Mode: `0644`
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a symbolic link to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Resources: three templates, three links, and one file deletion.
   - No explicit Nginx restart or reload is shown after the virtual-host configuration changes.

## Dependencies

**External cookbook dependencies**: None shown in the supplied metadata and execution tree.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started by `cookbooks/nginx-multisite/recipes/security.rb`.
- `nginx`: enabled and started by `cookbooks/nginx-multisite/recipes/nginx.rb`.
- `ssh`: referenced with action `nothing` by `cookbooks/nginx-multisite/recipes/security.rb`.

**Firewall allowances**:

- SSH
- HTTP
- HTTPS

## Credentials

**Detection Summary**: No application credentials, passwords, API tokens, data bags, Chef Vault items, CyberArk references, or external secret-manager references were detected. Three locally generated TLS private keys and three locally generated TLS certificates are sensitive files but are not retrieved from a credential store.

**Source**:
  - **Provider**: None detected for secret retrieval
  - **URL**: None detected
  - **Path**: None detected

### Self-signed TLS private keys

- **Variable(s)**: `key_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files, not a data bag, vault, environment variable, or hardcoded credential.
- **Usage context**: TLS private keys for the HTTPS virtual hosts.
- **Paths**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Protection**: Mode `0640`, owner/group `root:ssl-cert`.

### Self-signed TLS certificates

- **Variable(s)**: `cert_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated certificate files.
- **Usage context**: TLS certificates for the HTTPS virtual hosts.
- **Paths**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Certificate subject email**: `admin@example.com`
- **Certificate subject Common Names**:
  - `test.cluster.local`
  - `ci.cluster.local`
  - `status.cluster.local`

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, CyberArk data bag, `node['vault']`, or `node['secrets']` usage is shown.

## Checks for the Migration

**Files to verify**:

- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
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
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/etc/nginx/sites-enabled/default` must not exist

**Service endpoints to check**:

- HTTP: port `80`
- HTTPS: port `443`
- SSH: SSH service allowed by firewall; numeric port is not defined in the execution tree
- Nginx Unix socket: none specified
- Hostnames:
  - `test.cluster.local`
  - `ci.cluster.local`
  - `status.cluster.local`

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render
- `site.conf.erb` total: 3 renders

## Pre-flight checks:

```bash
# Package verification
dpkg -l fail2ban ufw nginx openssl ca-certificates

# Security service status
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Fail2ban configuration
test -f /etc/fail2ban/jail.local
fail2ban-client status

# UFW policy and rules
ufw status verbose
ufw status numbered
ufw status | grep -E '22|80|443'

# Expected UFW behavior:
# - Default incoming policy is deny
# - SSH is allowed
# - HTTP is allowed
# - HTTPS is allowed

# Kernel security configuration
test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf
cat /etc/sysctl.d/99-security.conf

# SSH hardening
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config

# Nginx service and configuration
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx
nginx -t
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
grep -E '^[^#].*' /etc/nginx/nginx.conf | head -50
grep -E '^[^#].*' /etc/nginx/conf.d/security.conf

# SSL directories and group
getent group ssl-cert
test -d /etc/ssl/certs
test -d /etc/ssl/private
stat -c '%U:%G %a %n' /etc/ssl/certs /etc/ssl/private

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -text | grep 'Public-Key'
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -text | grep 'Public-Key'
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -text | grep 'Public-Key'
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/

# Default site removal
test ! -e /etc/nginx/sites-enabled/default

# Listening ports
ss -tlnp | grep ':80 '
ss -tlnp | grep ':443 '
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN

# Nginx logs and recent errors
journalctl -u nginx --no-pager -n 100
tail -n 100 /var/log/nginx/error.log
```

Expected results:

- `fail2ban` is enabled and active.
- `nginx` is enabled and active.
- `nginx -t` reports a successful configuration test.
- Ports `80` and `443` are listening.
- `test.cluster.local` has its document root, index file, certificate, private key, site configuration, and enabled symlink.
- `ci.cluster.local` has its document root, index file, certificate, private key, site configuration, and enabled symlink.
- `status.cluster.local` has its document root, index file, certificate, private key, site configuration, and enabled symlink.
- All generated private keys are owned by `root:ssl-cert` with mode `0640`.
- `/etc/nginx/sites-enabled/default` is absent.
- HTTP and HTTPS requests reach the correct virtual host for all three hostnames.