---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx for three HTTPS-enabled virtual sites—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It also configures Fail2ban, UFW, kernel security settings, SSH hardening, self-signed TLS certificates, per-site document roots, Nginx virtual-host configurations, and removal of the default site. The Ansible implementation must preserve the recipe execution order and explicitly manage all three sites.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTPS listen port is defined by the rendered Nginx configuration; no numeric port is confirmed by the execution analysis
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; configuration `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTPS listen port is defined by the rendered Nginx configuration; no numeric port is confirmed by the execution analysis
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; configuration `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: HTTPS Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTPS listen port is defined by the rendered Nginx configuration; no numeric port is confirmed by the execution analysis
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; configuration `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`

- **fail2ban**: Host intrusion-prevention service
  - Location/Path: `/etc/fail2ban/jail.local`
  - Port/Socket: SSH jail configuration, if enabled by the rendered configuration
  - Key Config: Enabled and started

- **ufw**: Host firewall
  - Location/Path: UFW system configuration
  - Port/Socket: SSH, HTTP, and HTTPS service rules
  - Key Config: Default incoming policy denied; SSH, HTTP, and HTTPS allowed; firewall enabled

- **ssh**: SSH daemon hardening
  - Location/Path: `/etc/ssh/sshd_config`
  - Port/Socket: Existing SSH daemon socket
  - Key Config: Root login disabled; password authentication disabled; no service restart or reload is performed by the source execution tree

## File Structure

The following directory listing is preserved from the original migration plan.

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

```text
```

No static files under `files/` are listed as deployed by the execution tree. The `cookbook_file` resources reference dynamic site-specific source paths, but those source files are not included in the supplied file listing.

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `cookbooks/nginx-multisite/recipes/security.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/nginx.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/ssl.rb`.
   - Includes `cookbooks/nginx-multisite/recipes/sites.rb`.
   - The Ansible role must execute task sections in the same order: security, Nginx installation and base configuration, SSL directories and certificates, and site virtual-host configuration.

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
   - Defines `execute[reload_sysctl]` with command `sysctl -p /etc/sysctl.d/99-security.conf` and action `nothing`; no notification or subscription invokes it in the execution tree.
   - Executes `sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config` because root login disabling is enabled.
   - Executes `sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config` because password authentication is disabled.
   - Defines the `ssh` service with action `nothing`; the source does not start, enable, reload, or restart SSH.
   - Uses eight execute resources: `ufw_default_deny`, `ufw_allow_ssh`, `ufw_allow_http`, `ufw_allow_https`, `ufw_enable`, `reload_sysctl`, the root-login command, and the password-authentication command.
   - Uses one package resource containing two packages, two service resources, and two template resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` with mode `0755` and deploys `test.cluster.local/index.html` to `/opt/server/test/index.html` with mode `0644`.
   - Creates `/opt/server/ci` with mode `0755` and deploys `ci.cluster.local/index.html` to `/opt/server/ci/index.html` with mode `0644`.
   - Creates `/opt/server/status` with mode `0755` and deploys `status.cluster.local/index.html` to `/opt/server/status/index.html` with mode `0644`.
   - Uses one package resource, two template resources, one service resource, three directory resources, and three `cookbook_file` resources.
   - No Nginx reload or restart notification is shown. A controlled Ansible handler may be added only if immediate activation of configuration changes is required.
   - No separate `www-data` group resource is confirmed by the execution tree.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with mode `0755`.
   - Creates `/etc/ssl/private` with mode `0710`.
   - Generates a self-signed 2048-bit RSA certificate and private key for `test.cluster.local`:
     - Key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Validity: 365 days
     - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com`
     - Applies mode `0640` and ownership `root:ssl-cert` to the private key.
   - Generates a self-signed 2048-bit RSA certificate and private key for `ci.cluster.local`:
     - Key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Validity: 365 days
     - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com`
     - Applies mode `0640` and ownership `root:ssl-cert` to the private key.
   - Generates a self-signed 2048-bit RSA certificate and private key for `status.cluster.local`:
     - Key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Validity: 365 days
     - Subject: `/C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com`
     - Applies mode `0640` and ownership `root:ssl-cert` to the private key.
   - Uses one package resource containing two packages, one group resource, two directory resources, and three certificate-generation execute resources.
   - No separate `root` group resource is confirmed by the execution tree.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local` with mode `0644`, using document root `/opt/server/test`, SSL enabled, certificate `/etc/ssl/certs/test.cluster.local.crt`, and key `/etc/ssl/private/test.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/test.cluster.local` as a link to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local` with mode `0644`, using document root `/opt/server/ci`, SSL enabled, certificate `/etc/ssl/certs/ci.cluster.local.crt`, and key `/etc/ssl/private/ci.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/ci.cluster.local` as a link to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local` with mode `0644`, using document root `/opt/server/status`, SSL enabled, certificate `/etc/ssl/certs/status.cluster.local.crt`, and key `/etc/ssl/private/status.cluster.local.key`.
   - Creates `/etc/nginx/sites-enabled/status.cluster.local` as a link to `/etc/nginx/sites-available/status.cluster.local`.
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Uses three template resources, three link resources, and one file resource.
   - No service reload or restart is shown in the source execution tree.

## Dependencies

**External cookbook dependencies**: None provided in the supplied metadata analysis.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: declared with action `nothing`; no start, enable, reload, or restart action

**Network services and firewall access**:

- SSH allowed through UFW
- HTTP allowed through UFW
- HTTPS allowed through UFW
- Numeric Nginx listen ports are not confirmed by the execution analysis and must be obtained from the rendered configuration

## Credentials

**Detection Summary**: No externally supplied passwords, API keys, data bags, Chef Vault items, CyberArk references, Conjur variables, environment-variable secrets, or database connection strings were detected. Three locally generated TLS private keys are created.

**Source**:

- **Provider**: None detected
- **URL**: None detected
- **Path**: None detected

### Self-Signed TLS Private Keys

- **Variable(s)**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`
- **Current storage**: Locally generated files
- **Usage context**: TLS private keys for the three Nginx HTTPS virtual hosts
- **Permissions**: Mode `0640`
- **Ownership**: `root:ssl-cert`

The certificate subject includes `admin@example.com`, but this is not a credential. No encrypted or unencrypted data bags, Vault integrations, hardcoded passwords, or external secret references were detected.

## Checks for the Migration

**Files to verify**:

- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
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

- `test.cluster.local`: HTTP and HTTPS listen directives discovered from the rendered configuration
- `ci.cluster.local`: HTTP and HTTPS listen directives discovered from the rendered configuration
- `status.cluster.local`: HTTP and HTTPS listen directives discovered from the rendered configuration
- UFW services: SSH, HTTP, and HTTPS

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

Run these checks after the Ansible role completes.

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
systemctl is-enabled nginx
systemctl is-enabled fail2ban

# Expected:
# nginx is active and enabled.
# fail2ban is active and enabled.

# Nginx configuration validation
nginx -t
nginx -T

# Confirm all configured virtual hosts
nginx -T | grep -E 'test\.cluster\.local|ci\.cluster\.local|status\.cluster\.local'

# Discover actual HTTP and HTTPS listen ports from rendered configuration.
# Do not assume numeric port 443 because it is not confirmed by the execution analysis.
grep -R "listen" /etc/nginx/nginx.conf /etc/nginx/conf.d /etc/nginx/sites-enabled
ss -tlnp | grep nginx

# Firewall validation
ufw status verbose
ufw status numbered

# Fail2ban validation
fail2ban-client status
fail2ban-client status sshd
test -f /etc/fail2ban/jail.local

# SSH hardening validation
grep -E '^[[:space:]]*PermitRootLogin' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication' /etc/ssh/sshd_config
sshd -t

# Kernel security configuration
test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# Default site removal
test ! -e /etc/nginx/sites-enabled/default

# Logs
journalctl -u nginx --no-pager -n 100
journalctl -u fail2ban --no-pager -n 100
journalctl -u ssh --no-pager -n 100
```

### Site: `test.cluster.local`

```bash
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
```

Use the actual HTTPS port discovered from the rendered Nginx configuration:

```bash
curl -k -I --resolve test.cluster.local:${TEST_HTTPS_PORT}:127.0.0.1 \
  https://test.cluster.local:${TEST_HTTPS_PORT}/
```

Expected results:

- The document root and index file exist.
- The enabled-site link resolves to `/etc/nginx/sites-available/test.cluster.local`.
- The certificate and private key exist.
- The certificate subject contains `CN=test.cluster.local`.
- The private key has ownership `root:ssl-cert` and mode `640`.
- The HTTPS request returns a successful response, such as `200 OK`.

### Site: `ci.cluster.local`

```bash
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
```

Use the actual HTTPS port discovered from the rendered Nginx configuration:

```bash
curl -k -I --resolve ci.cluster.local:${CI_HTTPS_PORT}:127.0.0.1 \
  https://ci.cluster.local:${CI_HTTPS_PORT}/
```

Expected results:

- The document root and index file exist.
- The enabled-site link resolves to `/etc/nginx/sites-available/ci.cluster.local`.
- The certificate and private key exist.
- The certificate subject contains `CN=ci.cluster.local`.
- The private key has ownership `root:ssl-cert` and mode `640`.
- The HTTPS request returns a successful response, such as `200 OK`.

### Site: `status.cluster.local`

```bash
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
```

Use the actual HTTPS port discovered from the rendered Nginx configuration:

```bash
curl -k -I --resolve status.cluster.local:${STATUS_HTTPS_PORT}:127.0.0.1 \
  https://status.cluster.local:${STATUS_HTTPS_PORT}/
```

Expected results:

- The document root and index file exist.
- The enabled-site link resolves to `/etc/nginx/sites-available/status.cluster.local`.
- The certificate and private key exist.
- The certificate subject contains `CN=status.cluster.local`.
- The private key has ownership `root:ssl-cert` and mode `640`.
- The HTTPS request returns a successful response, such as `200 OK`.

### Expected firewall and security results

- UFW default incoming policy is denied.
- SSH, HTTP, and HTTPS are allowed.
- Fail2ban is active and its configured jail file exists.
- `/etc/ssh/sshd_config` contains:
  - `PermitRootLogin no`
  - `PasswordAuthentication no`
- `sshd -t` completes successfully before any SSH reload is considered.
- `/etc/sysctl.d/99-security.conf` exists and its values are applied or intentionally deferred according to the migration decision.
- Nginx logs contain no configuration or certificate errors.
- Fail2ban logs contain no startup errors.
- SSH logs contain no configuration errors.