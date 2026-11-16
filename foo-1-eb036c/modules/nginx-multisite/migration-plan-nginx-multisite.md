---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: `nginx-multisite` is an Nginx web-server cookbook that executes security hardening, Nginx installation/configuration, local self-signed TLS certificate generation, and configuration of the three named sites `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. Each site has a distinct document root and corresponding Nginx site configuration, enabled-site link, TLS certificate, and private key. Template-specific settings, attribute defaults, notification behavior, and metadata declarations require source-file verification where noted.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:
- **test.cluster.local**: Static Nginx virtual host.
  - Location/Path: `/opt/server/test`
  - Port/Socket: TCP `80` and TCP `443` as configured by the site template; verify rendered template behavior.
  - Key Config: `ssl_enabled` is referenced by the recipe; certificate `/etc/ssl/certs/test.cluster.local.crt`, private key `/etc/ssl/private/test.cluster.local.key`, site configuration `/etc/nginx/sites-available/test.cluster.local`, enabled link `/etc/nginx/sites-enabled/test.cluster.local`.

- **ci.cluster.local**: Static Nginx virtual host.
  - Location/Path: `/opt/server/ci`
  - Port/Socket: TCP `80` and TCP `443` as configured by the site template; verify rendered template behavior.
  - Key Config: `ssl_enabled` is referenced by the recipe; certificate `/etc/ssl/certs/ci.cluster.local.crt`, private key `/etc/ssl/private/ci.cluster.local.key`, site configuration `/etc/nginx/sites-available/ci.cluster.local`, enabled link `/etc/nginx/sites-enabled/ci.cluster.local`.

- **status.cluster.local**: Static Nginx virtual host.
  - Location/Path: `/opt/server/status`
  - Port/Socket: TCP `80` and TCP `443` as configured by the site template; verify rendered template behavior.
  - Key Config: `ssl_enabled` is referenced by the recipe; certificate `/etc/ssl/certs/status.cluster.local.crt`, private key `/etc/ssl/private/status.cluster.local.key`, site configuration `/etc/nginx/sites-available/status.cluster.local`, enabled link `/etc/nginx/sites-enabled/status.cluster.local`.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

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
None. No custom resource provider is used in the executed recipe flow.
```

**Templates:**
```text
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/sysctl-security.conf.erb
templates/default/site.conf.erb
```

**Attributes:**
```text
attributes/default.rb
```

**Files:**
```text
None listed in the supplied executable-file analysis. The nginx recipe references cookbook-file sources test/index.html, ci/index.html, and status/index.html, but those source files are not present in the supplied directory listing.
```

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Resources used: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs the `fail2ban` and `ufw` packages.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Configures UFW through command execution.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Applies SSH hardening operations to `/etc/ssh/sshd_config` based on the referenced `node['security']['ssh']['disable_root']` and `node['security']['ssh']['password_auth']` attributes.
   - Declares the `ssh` service as a notification target.
   - Resources used: package, service, template, and execute resources.
   - Verify source-level guards, notifications, UFW rules, SSH conditional values, and rendered Fail2ban/sysctl settings before migration because these details are not available in the supplied structured analysis.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` with owner and group `www-data`, mode `0755`, and recursive creation enabled.
   - Deploys cookbook file source `test/index.html` to `/opt/server/test/index.html` with owner and group `www-data` and mode `0644`.
   - Creates `/opt/server/ci` with owner and group `www-data`, mode `0755`, and recursive creation enabled.
   - Deploys cookbook file source `ci/index.html` to `/opt/server/ci/index.html` with owner and group `www-data` and mode `0644`.
   - Creates `/opt/server/status` with owner and group `www-data`, mode `0755`, and recursive creation enabled.
   - Deploys cookbook file source `status/index.html` to `/opt/server/status/index.html` with owner and group `www-data` and mode `0644`.
   - Resources used: one package, two templates, one service, three directories, and three cookbook files.
   - Obtain and preserve the intended content for `test/index.html`, `ci/index.html`, and `status/index.html` from the cookbook repository or application owner before migration. Repository file presence was not established by the supplied execution analysis.
   - Verify rendered Nginx main and security-template settings, including worker settings, log paths, gzip, rate limits, TLS policy, and notification behavior.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs the `openssl` and `ca-certificates` packages.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner `root`, group `root`, and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root`, group `ssl-cert`, and mode `0710`.
   - Generates local self-signed TLS material for **test.cluster.local**:
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate command parameters include RSA `2048`, validity `365` days, subject CN `test.cluster.local`, and subject email `admin@example.com`.
     - Private-key ownership is `root:ssl-cert`; mode is `0640`.
   - Generates local self-signed TLS material for **ci.cluster.local**:
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate command parameters include RSA `2048`, validity `365` days, subject CN `ci.cluster.local`, and subject email `admin@example.com`.
     - Private-key ownership is `root:ssl-cert`; mode is `0640`.
   - Generates local self-signed TLS material for **status.cluster.local**:
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate command parameters include RSA `2048`, validity `365` days, subject CN `status.cluster.local`, and subject email `admin@example.com`.
     - Private-key ownership is `root:ssl-cert`; mode is `0640`.
   - Resources used: one package resource installing two packages, one group, two directories, and three execute resources.
   - Verify the `ssl_enabled` attribute values, certificate/key existence guards, and Nginx notification behavior from source before migration.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a link to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a link to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a link to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Resources used: three templates, three links, and one file deletion.
   - Verify the rendered `site.conf.erb` content, including listeners, HTTP-to-HTTPS redirect behavior, HTTP/2, TLS directives, headers, logging, and file-access restrictions, before migration.

## Dependencies

**External cookbook dependencies**: Not verified from the supplied analysis. Review `cookbooks/nginx-multisite/metadata.rb` before migration.

**System package dependencies**:
- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:
- `nginx`: enabled and started by `cookbooks/nginx-multisite/recipes/nginx.rb`.
- `fail2ban`: enabled and started by `cookbooks/nginx-multisite/recipes/security.rb`.
- `ssh`: declared as a notification target in `cookbooks/nginx-multisite/recipes/security.rb`.
- UFW: configured through command execution rather than a Chef service resource.

**Platform compatibility**: Verify platform support in `cookbooks/nginx-multisite/metadata.rb`. The use of `ufw`, `www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, and the `ssh` service name is Debian/Ubuntu-oriented and requires tested platform-specific handling if targeting other operating systems.

## Credentials

**Detection Summary**: 3 locally generated TLS private keys are identified across `cookbooks/nginx-multisite/recipes/ssl.rb`.

**Source**:
  - **Provider**: Internal locally generated self-signed TLS material
  - **URL**: None
  - **Path**: `/etc/ssl/private/`

### TLS Private Key — test.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/test.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by `openssl req`.
- **Usage context**: Private key for the HTTPS configuration of `test.cluster.local`.
- **Protection**: Mode `0640`; ownership `root:ssl-cert`.

### TLS Private Key — ci.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/ci.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by `openssl req`.
- **Usage context**: Private key for the HTTPS configuration of `ci.cluster.local`.
- **Protection**: Mode `0640`; ownership `root:ssl-cert`.

### TLS Private Key — status.cluster.local
- **Variable(s)**: `key_file`, resolved as `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`; referenced by `cookbooks/nginx-multisite/templates/default/site.conf.erb`
- **Current storage**: Generated locally by `openssl req`.
- **Usage context**: Private key for the HTTPS configuration of `status.cluster.local`.
- **Protection**: Mode `0640`; ownership `root:ssl-cert`.

Credential detection for Chef data bags, Chef Vault, external secret providers, environment variables, templates, and hardcoded passwords was not included in the supplied analysis and must be completed before migration.

## Checks for the Migration

**Files to verify**:
```text
/etc/nginx/nginx.conf
/etc/nginx/conf.d/security.conf
/etc/nginx/sites-available/test.cluster.local
/etc/nginx/sites-enabled/test.cluster.local
/etc/nginx/sites-available/ci.cluster.local
/etc/nginx/sites-enabled/ci.cluster.local
/etc/nginx/sites-available/status.cluster.local
/etc/nginx/sites-enabled/status.cluster.local
/etc/nginx/sites-enabled/default
/etc/fail2ban/jail.local
/etc/sysctl.d/99-security.conf
/etc/ssh/sshd_config
/etc/ssl/certs/test.cluster.local.crt
/etc/ssl/private/test.cluster.local.key
/etc/ssl/certs/ci.cluster.local.crt
/etc/ssl/private/ci.cluster.local.key
/etc/ssl/certs/status.cluster.local.crt
/etc/ssl/private/status.cluster.local.key
/opt/server/test
/opt/server/test/index.html
/opt/server/ci
/opt/server/ci/index.html
/opt/server/status
/opt/server/status/index.html
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/nginx/test.cluster.local_access.log
/var/log/nginx/test.cluster.local_error.log
/var/log/nginx/ci.cluster.local_access.log
/var/log/nginx/ci.cluster.local_error.log
/var/log/nginx/status.cluster.local_access.log
/var/log/nginx/status.cluster.local_error.log
```

**Service endpoints to check**:
- **test.cluster.local**: Verify TCP `80` behavior and TCP `443` HTTPS behavior against the rendered Nginx site configuration.
- **ci.cluster.local**: Verify TCP `80` behavior and TCP `443` HTTPS behavior against the rendered Nginx site configuration.
- **status.cluster.local**: Verify TCP `80` behavior and TCP `443` HTTPS behavior against the rendered Nginx site configuration.
- **SSH**: Verify TCP `22` remains available when UFW is enabled and SSH hardening has been applied.
- **Unix sockets**: None identified in the supplied execution analysis.

**Templates rendered**:
- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: **1 time**
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: **1 time**
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: **1 time**
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: **1 time**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: **1 time**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: **1 time**
- `cookbooks/nginx-multisite/templates/default/site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: **1 time**

`cookbooks/nginx-multisite/templates/default/site.conf.erb` renders **3 times** in total.

## Pre-flight checks:
```bash
# Package and service status
dpkg-query -W -f='${Package} ${Status}\n' nginx fail2ban ufw openssl ca-certificates 2>/dev/null || \
rpm -q nginx fail2ban ufw openssl ca-certificates

systemctl is-enabled nginx
systemctl is-active nginx
systemctl status nginx --no-pager

systemctl is-enabled fail2ban
systemctl is-active fail2ban
systemctl status fail2ban --no-pager

# Validate Nginx before reload or endpoint testing.
nginx -t

# Verify deployed configuration files.
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf
test -f /etc/fail2ban/jail.local
test -f /etc/sysctl.d/99-security.conf
test -f /etc/ssh/sshd_config

# Validate SSH configuration while retaining the current management session.
sshd -t
sshd -T | grep -E 'permitrootlogin no|passwordauthentication no'

# Verify UFW state and expected service rules when UFW is enabled.
ufw status verbose
ufw status | grep -E '(22|ssh)'
ufw status | grep -E '(80|http)'
ufw status | grep -E '(443|https)'

# Verify Fail2ban availability.
fail2ban-client ping
fail2ban-client status

# Site: test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/test.cluster.local)" = \
  "/etc/nginx/sites-available/test.cluster.local"
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
curl -sSI --resolve test.cluster.local:80:127.0.0.1 http://test.cluster.local/
curl -skI --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local/

# Site: ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/ci.cluster.local)" = \
  "/etc/nginx/sites-available/ci.cluster.local"
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
curl -sSI --resolve ci.cluster.local:80:127.0.0.1 http://ci.cluster.local/
curl -skI --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local/

# Site: status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
test "$(readlink -f /etc/nginx/sites-enabled/status.cluster.local)" = \
  "/etc/nginx/sites-available/status.cluster.local"
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%a %U:%G %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
curl -sSI --resolve status.cluster.local:80:127.0.0.1 http://status.cluster.local/
curl -skI --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local/

# Default Nginx site must be absent.
test ! -e /etc/nginx/sites-enabled/default

# Confirm Nginx and SSH listeners.
ss -tlnp | grep -E ':(22|80|443)\b'

# Review service logs.
journalctl -u nginx -n 100 --no-pager
journalctl -u fail2ban -n 100 --no-pager
journalctl -u ssh -n 100 --no-pager
```