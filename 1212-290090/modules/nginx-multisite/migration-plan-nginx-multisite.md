---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx as a multisite web server with three HTTPS-enabled virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and configures Fail2ban and UFW, applies SSH and kernel security settings, creates self-signed RSA certificates, deploys site document roots and placeholder `index.html` files, enables the Nginx and Fail2ban services, and permits SSH, HTTP, and HTTPS through UFW.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` and TCP `443`
  - Key Config: `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`

- **ci.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` and TCP `443`
  - Key Config: `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`

- **status.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` and TCP `443`
  - Key Config: `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`

- **fail2ban**: Host intrusion-prevention service
  - Location/Path: `/etc/fail2ban/jail.local`
  - Port/Socket: None
  - Key Config: Package `fail2ban`; service enabled and started

- **ufw**: Host firewall
  - Location/Path: UFW system configuration
  - Port/Socket: Allows SSH, HTTP, and HTTPS
  - Key Config: Default policy `deny`; firewall enabled

- **ssh**: SSH service subject to hardening
  - Location/Path: `/etc/ssh/sshd_config`
  - Port/Socket: SSH service port
  - Key Config: Expected settings are `PermitRootLogin no` and `PasswordAuthentication no`; the supplied execution analysis does not independently verify the source attribute values.

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

No custom-resource provider is used by the execution tree.

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

No static file path is listed in the directory listing. The recipes deploy three dynamic `cookbook_file` resources for the site `index.html` files, with source paths represented dynamically as `#{site_folder}/index.html`.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Resources: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
   - Sets the UFW default policy to deny with `ufw --force default deny`.
   - Allows SSH with `ufw allow ssh`.
   - Allows HTTP with `ufw allow http`.
   - Allows HTTPS with `ufw allow https`.
   - Enables UFW with `ufw --force enable`.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
   - Defines `execute[reload_sysctl]` with action `nothing`; run `sysctl -p /etc/sysctl.d/99-security.conf` only when the intended sysctl configuration changes.
   - Conditionally disables SSH root login with `execute[disable root login]`:
     ```bash
     sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
     ```
   - Conditionally disables SSH password authentication with `execute[disable password auth]`:
     ```bash
     sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
     ```
   - Declares `service[ssh]` with action `nothing`; the execution tree does not show an SSH restart or reload notification.
   - Security configuration namespaces are `fail2ban`, `ufw`, and `ssh`.
   - Resource counts: one package resource, two service resources, two template resources, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the Nginx service.
   - Creates `/opt/server/test` and deploys `/opt/server/test/index.html` for `test.cluster.local`.
   - Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html` for `ci.cluster.local`.
   - Creates `/opt/server/status` and deploys `/opt/server/status/index.html` for `status.cluster.local`.
   - The three `cookbook_file` resources use the dynamic source pattern `#{site_folder}/index.html`.
   - Iterations:
     - `test.cluster.local`: document root `/opt/server/test`; SSL enabled.
     - `ci.cluster.local`: document root `/opt/server/ci`; SSL enabled.
     - `status.cluster.local`: document root `/opt/server/status`; SSL enabled.
   - Resource counts: one package, two templates, one service, three directories, and three `cookbook_file` resources.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates a self-signed RSA 2048-bit certificate valid for 365 days for `test.cluster.local`:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Subject CN: `test.cluster.local`
   - Generates a self-signed RSA 2048-bit certificate valid for 365 days for `ci.cluster.local`:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Subject CN: `ci.cluster.local`
   - Generates a self-signed RSA 2048-bit certificate valid for 365 days for `status.cluster.local`:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Subject CN: `status.cluster.local`
   - All certificates use organization `Example Org`, organizational unit `IT`, and email `admin@example.com`.
   - All private keys receive mode `0640` and ownership `root:ssl-cert`.
   - Certificate-generation commands should be guarded with `creates` or certificate/key existence and validity checks to prevent regeneration on every run.
   - Iterations:
     - `test.cluster.local`: certificate and key generated.
     - `ci.cluster.local`: certificate and key generated.
     - `status.cluster.local`: certificate and key generated.
   - Resource counts: one package, one group, two directories, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` targeting `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` targeting `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` targeting `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Iterations:
     - `test.cluster.local`: document root `/opt/server/test`, certificate `/etc/ssl/certs/test.cluster.local.crt`, key `/etc/ssl/private/test.cluster.local.key`.
     - `ci.cluster.local`: document root `/opt/server/ci`, certificate `/etc/ssl/certs/ci.cluster.local.crt`, key `/etc/ssl/private/ci.cluster.local.key`.
     - `status.cluster.local`: document root `/opt/server/status`, certificate `/etc/ssl/certs/status.cluster.local.crt`, key `/etc/ssl/private/status.cluster.local.key`.
   - Resource counts: three templates, three links, and one file resource.
   - The execution tree does not show an Nginx reload or restart notification. A controlled reload handler may be added if required by the migration implementation.

## Dependencies

**External cookbook dependencies**: None listed.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: enabled and started
- `fail2ban`: enabled and started
- `ssh`: configuration commands execute conditionally; service resource action is `nothing`
- `ufw`: enabled with `ufw --force enable`

**Firewall dependencies**:
- Default incoming policy: deny
- SSH: allowed
- HTTP: allowed
- HTTPS: allowed

## Credentials

**Detection Summary**: No application credentials, passwords, API keys, data bags, vault references, or secret-manager integrations were detected. Three locally generated TLS private keys are created and consumed by the Nginx virtual hosts.

**Source**:
  - **Provider**: None detected
  - **URL**: None detected
  - **Path**: No secret path or data bag detected

### Self-signed TLS private keys

- **Variable(s)**: `key_file`; `/etc/ssl/private/test.cluster.local.key`; `/etc/ssl/private/ci.cluster.local.key`; `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: TLS private keys used by the HTTPS Nginx virtual hosts
- **Permissions**: Mode `0640`
- **Ownership**: `root:ssl-cert`

### TLS certificate subject email

- **Variable(s)**: Literal `admin@example.com`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Hardcoded in the OpenSSL command
- **Usage context**: Subject email address in all three self-signed certificates
- **Secret status**: Not a credential; certificate metadata

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, CyberArk, Conjur, `node['vault']`, or `node['secrets']` usage is shown.

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
- `/etc/nginx/sites-enabled/default` — should be absent
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
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
- HTTP: TCP port `80`
- HTTPS: TCP port `443`
- SSH: configured SSH service port

**Templates rendered**:
- `fail2ban.jail.local.erb`: 1 render
- `nginx.conf.erb`: 1 render
- `security.conf.erb`: 1 render
- `sysctl-security.conf.erb`: 1 render
- `site.conf.erb`: 3 renders
  - `/etc/nginx/sites-available/test.cluster.local`
  - `/etc/nginx/sites-available/ci.cluster.local`
  - `/etc/nginx/sites-available/status.cluster.local`

## Pre-flight checks:

```bash
# Package verification
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Nginx service status
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx

# Fail2ban service status
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# UFW status and rules
ufw status verbose
ufw status numbered

# Expected firewall behavior:
# - Default incoming policy should be DENY
# - SSH should be ALLOW
# - HTTP should be ALLOW
# - HTTPS should be ALLOW

# Nginx configuration validation
nginx -t
nginx -T

# Main and security configuration
grep -nE '^[[:space:]]*(user|worker_processes|events|http)' /etc/nginx/nginx.conf
cat /etc/nginx/conf.d/security.conf

# Enabled-site links
readlink -f /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test ! -e /etc/nginx/sites-enabled/default && echo "default site removed"

# test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
grep -nE 'test\.cluster\.local|/opt/server/test|443|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/test.cluster.local
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/

# ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
grep -nE 'ci\.cluster\.local|/opt/server/ci|443|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/ci.cluster.local
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/

# status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
grep -nE 'status\.cluster\.local|/opt/server/status|443|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/status.cluster.local
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/

# Certificate inspection: test.cluster.local
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key

# Certificate inspection: ci.cluster.local
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key

# Certificate inspection: status.cluster.local
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key

# Expected private-key ownership and mode:
# root:ssl-cert 640

# Fail2ban configuration
test -f /etc/fail2ban/jail.local
fail2ban-client ping
fail2ban-client status

# Sysctl configuration
test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# SSH hardening and syntax
grep -nE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config
sshd -t

# Expected settings:
# PermitRootLogin no
# PasswordAuthentication no

# Network listening checks
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN

# Service logs
journalctl -u nginx --no-pager -n 100
journalctl -u fail2ban --no-pager -n 100
```

Expected validation results:

- `test.cluster.local` returns a successful HTTP or HTTPS response.
- `ci.cluster.local` returns a successful HTTP or HTTPS response.
- `status.cluster.local` returns a successful HTTP or HTTPS response.
- HTTPS checks use `-k` because the certificates are self-signed.
- `nginx -t` reports successful syntax.
- TCP ports `80` and `443` are listening.
- Each site-specific enabled link resolves to its corresponding file in `/etc/nginx/sites-available/`.
- `/etc/nginx/sites-enabled/default` does not exist.
- All private keys are owned by `root:ssl-cert` with mode `0640`.
