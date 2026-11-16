---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; applies host security settings; creates document roots and placeholder index files; generates self-signed TLS certificates for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; renders and enables one Nginx virtual-host configuration per site; and enables the Nginx and Fail2ban services. The site variables and generated certificates indicate intended HTTPS support, but the exact Nginx listen directives must be confirmed from the rendered configuration.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Nginx virtual host serving the test site
  - Location/Path: `/opt/server/test`
  - Port/Socket: Expected HTTP `80` and HTTPS `443`; verify rendered listen directives
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; site configuration `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: Nginx virtual host serving the CI site
  - Location/Path: `/opt/server/ci`
  - Port/Socket: Expected HTTP `80` and HTTPS `443`; verify rendered listen directives
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; site configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: Nginx virtual host serving the status site
  - Location/Path: `/opt/server/status`
  - Port/Socket: Expected HTTP `80` and HTTPS `443`; verify rendered listen directives
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; site configuration `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`

Security configuration namespaces:

- **fail2ban**: Intrusion-prevention service, enabled and started
- **ufw**: Host firewall with default-deny incoming policy and SSH, HTTP, and HTTPS allowed
- **ssh**: SSH hardening with root login disabled and password authentication disabled

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

The execution tree shows `cookbook_file` resources deploying `index.html`, but no static file path under `files/default/` or `files/` is provided. The resource source expression is `#{site_folder}/index.html`.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Uses four `include_recipe` resources.
   - The Ansible role should call corresponding task files in this order.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs packages `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Sets UFW’s default incoming policy to deny.
   - Allows SSH, HTTP, and HTTPS through UFW.
   - Enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Declares `sysctl -p /etc/sysctl.d/99-security.conf` as `execute[reload_sysctl]` with action `nothing`; no notification is shown.
   - Because `security.ssh.disable_root` is `true`, changes `PermitRootLogin` to `no` in `/etc/ssh/sshd_config`.
   - Because `security.ssh.password_auth` is `false`, changes `PasswordAuthentication` to `no` in `/etc/ssh/sshd_config`.
   - Declares `service[ssh]` with action `nothing`; no SSH restart is shown.
   - Resources: one package resource installing two packages, two service resources (`fail2ban` and `ssh`), two templates, and eight execute resources:
     - `ufw_default_deny`
     - `ufw_allow_ssh`
     - `ufw_allow_http`
     - `ufw_allow_https`
     - `ufw_enable`
     - `reload_sysctl`
     - `disable root login`
     - `disable password auth`

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs package `nginx`.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` and deploys `/opt/server/test/index.html` using a `cookbook_file` resource with source expression `#{site_folder}/index.html` and mode `0644`.
   - Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html` using a `cookbook_file` resource with source expression `#{site_folder}/index.html` and mode `0644`.
   - Creates `/opt/server/status` and deploys `/opt/server/status/index.html` using a `cookbook_file` resource with source expression `#{site_folder}/index.html` and mode `0644`.
   - Resources: one package, two templates, one service, three directories, and three `cookbook_file` resources.
   - No `www-data` group resources are included because they do not appear in the supplied execution tree.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs packages `openssl` and `ca-certificates`.
   - Creates group `ssl-cert`.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates a self-signed RSA 2048-bit certificate and unencrypted private key for `test.cluster.local`:
     - Key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Validity: 365 days
     - Subject CN: `test.cluster.local`
     - Resource: `execute[generate-ssl-cert-test.cluster.local]`
     - Key mode: `0640`
     - Key owner/group: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate and unencrypted private key for `ci.cluster.local`:
     - Key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Validity: 365 days
     - Subject CN: `ci.cluster.local`
     - Resource: `execute[generate-ssl-cert-ci.cluster.local]`
     - Key mode: `0640`
     - Key owner/group: `root:ssl-cert`
   - Generates a self-signed RSA 2048-bit certificate and unencrypted private key for `status.cluster.local`:
     - Key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Validity: 365 days
     - Subject CN: `status.cluster.local`
     - Resource: `execute[generate-ssl-cert-status.cluster.local]`
     - Key mode: `0640`
     - Key owner/group: `root:ssl-cert`
   - Resources: one package resource installing two packages, one group, two directories, and three certificate-generation execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, using document root `/opt/server/test`, SSL enabled, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a link to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, using document root `/opt/server/ci`, SSL enabled, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a link to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, using document root `/opt/server/status`, SSL enabled, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a link to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Resources: three templates, three links, and one file deletion.
   - No Nginx reload or restart is shown after site configuration changes.

## Dependencies

**External cookbook dependencies**: None shown.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: declared with action `nothing`; no restart or start action shown

**Firewall dependencies**:

- Default incoming policy: deny
- SSH: allowed
- HTTP: allowed
- HTTPS: allowed

## Credentials

**Detection Summary**: No external application credentials or secret-manager references were detected. Three locally generated TLS private keys and three locally generated TLS certificates are created by the cookbook.

**Source**:
  - **Provider**: None detected for external secrets
  - **URL**: None detected
  - **Path**: No secret-manager or data-bag path detected

### TLS Private Keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: HTTPS private keys for the three Nginx virtual hosts
- **Generation**: OpenSSL self-signed certificate commands using RSA 2048-bit unencrypted keys (`-nodes`)
- **Permissions**: Mode `0640`, owner `root`, group `ssl-cert`

### TLS Certificates

- **Variable(s)**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated self-signed certificate files
- **Usage context**: TLS certificates for the three Nginx virtual hosts
- **Validity**: 365 days
- **Subject email**: `admin@example.com`

The Ansible implementation should treat private keys as sensitive files and avoid exposing their contents in task output.

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

**Service endpoints to check**:

- HTTP port `80`
- HTTPS port `443`
- Confirm the exact listen directives in the rendered Nginx site configurations before migration.

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render

**Total template render operations**: 7

## Pre-flight checks:

```bash
# Package and service status
dpkg -l nginx fail2ban ufw openssl ca-certificates

systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

# Nginx configuration validation
nginx -t
cat /etc/nginx/nginx.conf
cat /etc/nginx/conf.d/security.conf
systemctl status nginx

# test.cluster.local
ls -ld /opt/server/test
ls -l /opt/server/test/index.html
ls -l /etc/nginx/sites-available/test.cluster.local
ls -l /etc/nginx/sites-enabled/test.cluster.local
ls -l /etc/ssl/certs/test.cluster.local.crt
ls -l /etc/ssl/private/test.cluster.local.key
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G %n' /etc/ssl/private/test.cluster.local.key

# ci.cluster.local
ls -ld /opt/server/ci
ls -l /opt/server/ci/index.html
ls -l /etc/nginx/sites-available/ci.cluster.local
ls -l /etc/nginx/sites-enabled/ci.cluster.local
ls -l /etc/ssl/certs/ci.cluster.local.crt
ls -l /etc/ssl/private/ci.cluster.local.key
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G %n' /etc/ssl/private/ci.cluster.local.key

# status.cluster.local
ls -ld /opt/server/status
ls -l /opt/server/status/index.html
ls -l /etc/nginx/sites-available/status.cluster.local
ls -l /etc/nginx/sites-enabled/status.cluster.local
ls -l /etc/ssl/certs/status.cluster.local.crt
ls -l /etc/ssl/private/status.cluster.local.key
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
stat -c '%a %U %G %n' /etc/ssl/private/status.cluster.local.key

# Site enablement
test ! -e /etc/nginx/sites-enabled/default
readlink -f /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local

# Port and process checks
ss -tlnp | grep -E ':(80|443)\b'
ps aux | grep '[n]ginx'

# Security checks
systemctl status fail2ban
fail2ban-client status
ufw status verbose
grep -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config
cat /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# Logs
journalctl -u nginx --no-pager -n 100
journalctl -u fail2ban --no-pager -n 100
```

Expected results:

- `nginx` and `fail2ban` are installed, enabled, and running.
- `ufw`, `openssl`, and `ca-certificates` are installed.
- `nginx -t` succeeds.
- Each site has its document root, index file, available configuration, enabled link, certificate, and private key.
- Each certificate contains the expected site-specific common name.
- Each private key has mode `640` and ownership `root:ssl-cert`.
- HTTP and HTTPS requests respond for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`, subject to confirmation of the rendered Nginx listen directives.
- `/etc/nginx/sites-enabled/default` does not exist.
- The enabled links resolve to their matching files under `/etc/nginx/sites-available/`.
- Nginx listens on the configured HTTP and HTTPS ports.
- Fail2ban is active.
- UFW is active with default deny behavior and allows SSH, HTTP, and HTTPS.
- `PermitRootLogin no` and `PasswordAuthentication no` are present.
- The security sysctl file loads successfully.
- Nginx and Fail2ban logs contain no configuration, certificate-permission, virtual-host, or initialization errors.