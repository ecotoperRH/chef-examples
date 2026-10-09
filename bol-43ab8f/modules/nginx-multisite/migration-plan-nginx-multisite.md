---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx with three HTTPS-enabled virtual sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and configures Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; applies SSH and kernel security hardening; creates site document roots and index files; generates self-signed 365-day RSA 2048-bit certificates; renders and enables three Nginx virtual-host configurations; and removes the default Nginx site. The Ansible migration must preserve the recipe execution order and all site-specific paths, names, ports, permissions, and security settings.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` and `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; virtual-host name `test.cluster.local`

- **ci.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` and `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; virtual-host name `ci.cluster.local`

- **status.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` and `443`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; virtual-host name `status.cluster.local`

**Security configuration**:

- `security.fail2ban.enabled`: `true`
- `security.ufw.enabled`: `true`
- `security.ssh.disable_root`: `true`
- `security.ssh.password_auth`: `false`

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

No static files under `files/` are listed in the supplied analysis. The `index.html` resources are `cookbook_file` resources, but their source files were not included in the supplied directory listing and must not be invented in the migration inventory.

## Module Explanation

The cookbook performs operations in this order:

1. `default` (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Preserves the execution order: security, Nginx installation, SSL setup, then site configuration.

2. `security` (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Executes UFW commands in order:
     1. `ufw --force default deny`
     2. `ufw allow ssh`
     3. `ufw allow http`
     4. `ufw allow https`
     5. `ufw --force enable`
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Declares `sysctl -p /etc/sysctl.d/99-security.conf` as `action: nothing`; the supplied execution tree does not invoke it.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` because `security.ssh.disable_root` is `true`.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` because `security.ssh.password_auth` is `false`.
   - Declares the `ssh` service with `action: nothing`; no SSH restart or reload is shown.
   - Resources: one package resource, two service resources, two templates, and eight execute resources.

3. `nginx` (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates document roots with mode `0755` and index files with mode `0644`:
     - `test.cluster.local`: `/opt/server/test` and `/opt/server/test/index.html`
     - `ci.cluster.local`: `/opt/server/ci` and `/opt/server/ci/index.html`
     - `status.cluster.local`: `/opt/server/status` and `/opt/server/status/index.html`
   - The source files for the `cookbook_file` index resources were not included in the supplied file listing.
   - No Nginx reload or restart notification is shown for configuration or content changes.
   - Resources: one package, two templates, one service, three directories, and three `cookbook_file` resources.

4. `ssl` (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates certificates for the following exact sites:
     - `test.cluster.local`: certificate `/etc/ssl/certs/test.cluster.local.crt`; key `/etc/ssl/private/test.cluster.local.key`
     - `ci.cluster.local`: certificate `/etc/ssl/certs/ci.cluster.local.crt`; key `/etc/ssl/private/ci.cluster.local.key`
     - `status.cluster.local`: certificate `/etc/ssl/certs/status.cluster.local.crt`; key `/etc/ssl/private/status.cluster.local.key`
   - Uses self-signed certificates valid for 365 days with RSA 2048-bit keys.
   - Uses subject values with country `US`, state `Example`, locality `Example`, organization `Example Org`, organizational unit `IT`, the site-specific common name, and `admin@example.com`.
   - Applies mode `0640` and ownership `root:ssl-cert` to each private key.
   - Certificate-generation iterations:
     - `test.cluster.local`: `execute[generate-ssl-cert-test.cluster.local]`
     - `ci.cluster.local`: `execute[generate-ssl-cert-ci.cluster.local]`
     - `status.cluster.local`: `execute[generate-ssl-cert-status.cluster.local]`
   - Resources: one package, one group, two directories, and three certificate-generation commands.

5. `sites` (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders and enables one virtual-host configuration for each named site.
   - `test.cluster.local`:
     - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
     - Uses document root `/opt/server/test`.
     - Uses certificate `/etc/ssl/certs/test.cluster.local.crt`.
     - Uses key `/etc/ssl/private/test.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/test.cluster.local` linked to `/etc/nginx/sites-available/test.cluster.local`.
   - `ci.cluster.local`:
     - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
     - Uses document root `/opt/server/ci`.
     - Uses certificate `/etc/ssl/certs/ci.cluster.local.crt`.
     - Uses key `/etc/ssl/private/ci.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/ci.cluster.local` linked to `/etc/nginx/sites-available/ci.cluster.local`.
   - `status.cluster.local`:
     - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
     - Uses document root `/opt/server/status`.
     - Uses certificate `/etc/ssl/certs/status.cluster.local.crt`.
     - Uses key `/etc/ssl/private/status.cluster.local.key`.
     - Creates `/etc/nginx/sites-enabled/status.cluster.local` linked to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - The `site.conf.erb` template renders three times total.
   - Resources: three templates, three links, and one file deletion.

## Dependencies

**External cookbook dependencies**: Not provided in the supplied metadata analysis.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: declared with action `nothing`; no explicit restart or reload is shown

## Credentials

**Detection Summary**: No external credentials, data bags, vault references, API tokens, database passwords, or environment-variable secrets were detected. Three generated TLS private keys and three generated self-signed certificates are created locally.

**Source**:

- **Provider**: None detected
- **URL**: None detected
- **Path**: None detected

### Generated TLS Private Keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally by OpenSSL; not stored in a data bag, vault, or environment variable
- **Usage context**: TLS private keys for the three Nginx HTTPS virtual hosts
- **Permissions**: Mode `0640`, owned by `root:ssl-cert`

### Self-Signed TLS Certificates

- **Variable(s)**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Generated locally as self-signed certificates
- **Usage context**: Public certificate files referenced by the Nginx site configurations
- **Certificate lifetime**: 365 days
- **Key format**: RSA 2048-bit

No `data_bag_item`, `encrypted_data_bag_item`, `chef_vault_item`, `ChefVault::Item`, `conjur_variable`, CyberArk data bag, `node['vault']`, `node['secrets']`, or credential-bearing database connection string is shown in the supplied analysis.

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
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/status.cluster.local.key`

**Service endpoints to check**:

- `test.cluster.local`: TCP `80` and `443`
- `ci.cluster.local`: TCP `80` and `443`
- `status.cluster.local`: TCP `80` and `443`
- UFW SSH allowance: SSH service or TCP port `22`

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render

`site.conf.erb` renders three times in total.

## Pre-flight checks

```bash
# Verify required packages
dpkg -l nginx fail2ban ufw openssl ca-certificates

# Verify managed services
systemctl is-enabled nginx
systemctl is-active nginx
systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status nginx --no-pager
systemctl status fail2ban --no-pager

# Validate Nginx configuration
nginx -t
grep -E 'include|sites-enabled|conf.d' /etc/nginx/nginx.conf
cat /etc/nginx/conf.d/security.conf

# Verify site configuration files
ls -l /etc/nginx/sites-available/test.cluster.local
ls -l /etc/nginx/sites-available/ci.cluster.local
ls -l /etc/nginx/sites-available/status.cluster.local

# Verify enabled-site links
readlink -f /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test ! -e /etc/nginx/sites-enabled/default

# Verify test.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/
curl -k --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

# Verify ci.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/
curl -k --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

# Verify status.cluster.local
grep -E 'server_name|root|listen|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/sites-available/status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -issuer -dates
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/
curl -k --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Verify firewall state
ufw status verbose
ufw status numbered

# Verify SSH hardening
grep -E '^[# ]*PermitRootLogin|^[# ]*PasswordAuthentication' \
  /etc/ssh/sshd_config
sshd -t

# Verify kernel security configuration
test -f /etc/sysctl.d/99-security.conf
cat /etc/sysctl.d/99-security.conf
sysctl --system

# Verify listening endpoints
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

# Review service logs
journalctl -u nginx --no-pager -n 50
journalctl -u fail2ban --no-pager -n 50
```

Expected validation results:

- `nginx` and `fail2ban` are installed, enabled, and active.
- `ufw`, `openssl`, and `ca-certificates` are installed.
- `nginx -t` succeeds.
- All three enabled-site links resolve to their corresponding `sites-available` files.
- `/etc/nginx/sites-enabled/default` does not exist.
- `test.cluster.local` uses `/opt/server/test` and its matching certificate and key.
- `ci.cluster.local` uses `/opt/server/ci` and its matching certificate and key.
- `status.cluster.local` uses `/opt/server/status` and its matching certificate and key.
- All three certificates are self-signed and contain the correct site-specific common name.
- All three private keys are owned by `root:ssl-cert` with mode `640`.
- HTTP and HTTPS return an HTTP response for all three sites, normally `200`, `301`, or the status defined by `site.conf.erb`.
- UFW has a default incoming deny policy and allows SSH, HTTP, and HTTPS.
- Effective SSH settings are `PermitRootLogin no` and `PasswordAuthentication no`.
- The `reload_sysctl` Chef resource has `action: nothing`; confirm whether the Ansible implementation preserves that behavior or intentionally applies the sysctl file.
- Nginx listens on TCP ports `80` and `443`.
