---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook provisions an Nginx web server for three HTTPS-enabled sites: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and starts Nginx, Fail2ban, UFW, OpenSSL, and CA certificates; creates site document roots and index files; generates self-signed TLS certificates; renders global, security, Fail2ban, and virtual-host configuration; enables the sites; removes the default Nginx site; applies security sysctl settings; and conditionally hardens SSH root login and password authentication.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`; virtual host `/etc/nginx/sites-available/test.cluster.local`; enabled link `/etc/nginx/sites-enabled/test.cluster.local`

- **ci.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`; virtual host `/etc/nginx/sites-available/ci.cluster.local`; enabled link `/etc/nginx/sites-enabled/ci.cluster.local`

- **status.cluster.local**: HTTPS-enabled Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`, HTTPS `443`
  - Key Config: Certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`; virtual host `/etc/nginx/sites-available/status.cluster.local`; enabled link `/etc/nginx/sites-enabled/status.cluster.local`

Security configuration uses separate `fail2ban`, `ufw`, and `ssh` namespaces. The execution tree contains conditional SSH hardening for `PermitRootLogin` and `PasswordAuthentication`; the exact attribute declarations and defaults are not available in the supplied analysis.

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

No provider file is used by the execution tree.

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

No static files under `files/default/*` or `files/*` are listed in the supplied analysis. The `index.html` resources use dynamically constructed `cookbook_file` source paths; verify those source files separately before implementing Ansible `copy` tasks.

## Module Explanation

The cookbook performs operations in this order:

1. `default.rb` includes `security.rb`, `nginx.rb`, `ssl.rb`, and `sites.rb`.
2. `security.rb` installs and configures Fail2ban and UFW, renders security sysctl configuration, and conditionally hardens SSH.
3. `nginx.rb` installs and starts Nginx, renders global configuration, and creates the three site document roots and index files.
4. `ssl.rb` installs SSL packages, creates the `ssl-cert` group and SSL directories, and generates certificates and keys for the three sites.
5. `sites.rb` renders and enables the three Nginx virtual hosts and removes the default site.

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `nginx-multisite::security`.
   - Includes `nginx-multisite::nginx`.
   - Includes `nginx-multisite::ssl`.
   - Includes `nginx-multisite::sites`.
   - Preserve this execution order in the Ansible role.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
   - Enables and starts the `fail2ban` service.
   - Executes UFW commands in this order: default deny, allow SSH, allow HTTP, allow HTTPS, and enable UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
   - Declares `sysctl -p /etc/sysctl.d/99-security.conf` as an on-demand action; apply it in Ansible only when the intended migration semantics require activation.
   - Conditionally sets `PermitRootLogin no` in `/etc/ssh/sshd_config`.
   - Conditionally sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` when the observed password-authentication condition is false.
   - The SSH service is declared with action `nothing`; do not assume an independent SSH restart unless configuration changes notify a handler.
   - Resources: `package: 1`, `service: 2`, `template: 2`, `execute: 8`.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`.
   - Enables and starts the Nginx service.
   - Creates `/opt/server/test` and `/opt/server/test/index.html` for `test.cluster.local`.
   - Creates `/opt/server/ci` and `/opt/server/ci/index.html` for `ci.cluster.local`.
   - Creates `/opt/server/status` and `/opt/server/status/index.html` for `status.cluster.local`.
   - The three index files use dynamically constructed `cookbook_file` source paths that require independent source-file verification.
   - Resources: `package: 1`, `template: 2`, `service: 1`, `directory: 3`, `cookbook_file: 3`.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` and `/etc/ssl/private`.
   - Generates a self-signed RSA 2048 certificate and private key for `test.cluster.local`.
   - Generates a self-signed RSA 2048 certificate and private key for `ci.cluster.local`.
   - Generates a self-signed RSA 2048 certificate and private key for `status.cluster.local`.
   - Each certificate is valid for 365 days and uses a subject containing the corresponding hostname and `admin@example.com`.
   - Each private key is created with mode `0640` and ownership `root:ssl-cert`.
   - Use `creates` guards or `community.crypto` modules to prevent certificate regeneration on every run.
   - Resources: `package: 1`, `group: 1`, `directory: 2`, `execute: 3`.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local`.
   - Links `/etc/nginx/sites-enabled/test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local`.
   - Links `/etc/nginx/sites-enabled/ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local`.
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` for `status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local`.
   - Links `/etc/nginx/sites-enabled/status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Validate the configuration with `nginx -t` before reloading Nginx after virtual-host changes.
   - Resources: `template: 3`, `link: 3`, `file: 1`.

## Dependencies

**External cookbook dependencies**: No external cookbook dependency names are provided in the supplied metadata analysis.

**System package dependencies**:

- `nginx`
- `fail2ban`
- `ufw`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `nginx`
- `fail2ban`
- `ssh` configuration is modified conditionally; the execution tree declares `service[ssh]` with action `nothing`.

**Additional dependencies**:

- The `ssl-cert` system group must exist.
- No additional `www-data` task should be added solely from an unsupported structural note.

## Credentials

**Detection Summary**: No passwords, API tokens, data bags, encrypted data bags, Chef Vault items, CyberArk references, Conjur variables, or database credentials were detected.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

### Self-signed TLS Private Keys

- **Variable(s)**: `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, `/etc/ssl/private/status.cluster.local.key`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files; not stored in a data bag, vault, or environment variable
- **Usage context**: TLS private keys for the three Nginx HTTPS virtual hosts
- **Permissions and ownership**: Mode `0640`, owned by `root:ssl-cert`

### Self-signed TLS Certificates

- **Variable(s)**: `/etc/ssl/certs/test.cluster.local.crt`, `/etc/ssl/certs/ci.cluster.local.crt`, `/etc/ssl/certs/status.cluster.local.crt`
- **Source file(s)**: `cookbooks/nginx-multisite/recipes/ssl.rb`, `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated certificate files
- **Usage context**: TLS certificates for the three Nginx HTTPS virtual hosts
- **Certificate properties**: RSA 2048, self-signed, valid for 365 days

The certificate subject contains the non-secret administrative email address `admin@example.com`; it is not a credential.

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

- HTTP: port `80`
- HTTPS: port `443`
- SSH: port `22`
- UFW rules allowing SSH, HTTP, and HTTPS
- No Unix socket is specified by the execution tree.

**Templates rendered**:

- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/test.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/ci.cluster.local`: 1 render
- `site.conf.erb` → `/etc/nginx/sites-available/status.cluster.local`: 1 render
- `site.conf.erb`: 3 total renders

## Pre-flight checks:

```bash
# Package verification
dpkg -l nginx
dpkg -l fail2ban
dpkg -l ufw
dpkg -l openssl
dpkg -l ca-certificates

# Nginx service status
systemctl status nginx
systemctl is-enabled nginx
systemctl is-active nginx

# Fail2ban service status
systemctl status fail2ban
systemctl is-enabled fail2ban
systemctl is-active fail2ban

# Nginx configuration validation
nginx -t
nginx -T
test -f /etc/nginx/nginx.conf
test -f /etc/nginx/conf.d/security.conf

# Verify test.cluster.local
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local
test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
curl -I -H 'Host: test.cluster.local' http://127.0.0.1
curl -k -I --resolve test.cluster.local:443:127.0.0.1 https://test.cluster.local

# Verify ci.cluster.local
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local
test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 https://ci.cluster.local

# Verify status.cluster.local
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local
test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
curl -I -H 'Host: status.cluster.local' http://127.0.0.1
curl -k -I --resolve status.cluster.local:443:127.0.0.1 https://status.cluster.local

# Default site must be removed
test ! -e /etc/nginx/sites-enabled/default

# TLS certificate and key verification
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates

# Firewall verification
ufw status verbose
ufw status numbered

# Fail2ban validation
fail2ban-client status
fail2ban-client ping
test -f /etc/fail2ban/jail.local

# Kernel security configuration
test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf

# SSH hardening verification
grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+no' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+no' /etc/ssh/sshd_config

# Listening ports
ss -tlnp | grep ':80 '
ss -tlnp | grep ':443 '
ss -tlnp | grep ':22 '

# Nginx logs
journalctl -u nginx --no-pager -n 50
```

Expected results:

- `nginx -t` reports a successful configuration test.
- Nginx and Fail2ban are enabled and active.
- `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` each have a document root, index file, virtual-host file, enabled-site link, certificate, and private key.
- HTTP and HTTPS requests reach the corresponding site.
- `/etc/nginx/sites-enabled/default` does not exist.
- Ports `80` and `443` are listening.
- UFW allows SSH, HTTP, and HTTPS while retaining a default-deny policy.
- SSH hardening reflects the applicable execution-tree conditions.