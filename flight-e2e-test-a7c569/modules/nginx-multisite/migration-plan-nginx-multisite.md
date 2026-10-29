---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook deploys nginx with three HTTPS-enabled virtual hosts—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It installs and configures nginx, OpenSSL, CA certificates, fail2ban, and UFW; creates self-signed certificates; deploys static site content; configures HTTP-to-HTTPS redirects and security settings; hardens SSH and kernel parameters; and opens SSH, HTTP, and HTTPS firewall ports. Template-content details and attribute values should be verified against the source cookbook because the supplied structured analysis confirms the execution tree and resource paths but does not independently include attribute or template-content analysis.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Static HTTPS virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - Private key: `/etc/ssl/private/test.cluster.local.key`
  - Static file: `/opt/server/test/index.html`
  - HTTP behavior: Redirects to HTTPS
  - Access log: `/var/log/nginx/test.cluster.local_access.log`
  - Error log: `/var/log/nginx/test.cluster.local_error.log`

- **ci.cluster.local**: Static HTTPS virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - Private key: `/etc/ssl/private/ci.cluster.local.key`
  - Static file: `/opt/server/ci/index.html`
  - HTTP behavior: Redirects to HTTPS
  - Access log: `/var/log/nginx/ci.cluster.local_access.log`
  - Error log: `/var/log/nginx/ci.cluster.local_error.log`

- **status.cluster.local**: Static HTTPS virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: HTTP `80`; HTTPS `443`
  - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - Private key: `/etc/ssl/private/status.cluster.local.key`
  - Static file: `/opt/server/status/index.html`
  - HTTP behavior: Redirects to HTTPS
  - Access log: `/var/log/nginx/status.cluster.local_access.log`
  - Error log: `/var/log/nginx/status.cluster.local_error.log`

**Security configuration**:

- **fail2ban**: Installed, enabled, and started; protects SSH and nginx-related activity.
- **ufw**: Installed and enabled with a default deny policy; allows TCP ports `22`, `80`, and `443`.
- **ssh**: Root login disabled and password authentication disabled when the corresponding security settings are enabled.

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

No provider files are used by the execution tree. SSL certificate generation uses standard `execute` resources rather than custom providers.

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

The execution tree references these `cookbook_file` sources, but they were not present in the supplied directory listing:

```text
test/index.html
ci/index.html
status/index.html
```

The Ansible migration must provide these files or replace the Chef `cookbook_file` resources with equivalent content sources.

## Module Explanation

The cookbook performs operations in this order:

1. `default` (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `security`, `nginx`, `ssl`, and `sites` in that order.
   - The equivalent Ansible role should execute security, nginx, SSL, and site task files in the same order.

2. `security` (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts `fail2ban`.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local`.
   - Configures fail2ban jails for `sshd`, `nginx-http-auth`, `nginx-limit-req`, and `nginx-botsearch`.
   - Applies the UFW default deny policy and allows SSH, HTTP, and HTTPS.
   - Enables UFW.
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf`.
   - Applies the configured security sysctl values and reloads them when the file changes.
   - Sets `PermitRootLogin no` in `/etc/ssh/sshd_config` when root-login hardening is enabled.
   - Sets `PasswordAuthentication no` in `/etc/ssh/sshd_config` when password authentication is disabled.
   - Restarts SSH only when the SSH configuration changes.
   - Uses delayed notifications in Chef; Ansible should use handlers for fail2ban restart, sysctl reload, and SSH restart.
   - Resource summary: two package names, two services, two templates, and eight execute resources.

3. `nginx` (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf`.
   - Enables and starts the nginx service.
   - Reloads nginx when global configuration, security configuration, site links, certificates, or virtual-host configuration changes.
   - Creates the following document roots:
     - `/opt/server/test`, owned by `www-data:www-data`, mode `0755`
     - `/opt/server/ci`, owned by `www-data:www-data`, mode `0755`
     - `/opt/server/status`, owned by `www-data:www-data`, mode `0755`
   - Deploys the following static files with owner `www-data:www-data` and mode `0644`:
     - `/opt/server/test/index.html` from `test/index.html`
     - `/opt/server/ci/index.html` from `ci/index.html`
     - `/opt/server/status/index.html` from `status/index.html`
   - Iterations: the site directory and static-file operations run for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`.

4. `ssl` (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs` with owner `root:root` and mode `0755`.
   - Creates `/etc/ssl/private` with owner `root:ssl-cert` and mode `0710`.
   - Generates self-signed RSA certificates and private keys for the three SSL-enabled sites.
   - Generated private keys use mode `0640` and owner `root:ssl-cert`.
   - Skips certificate generation when both the certificate and key already exist.
   - Notifies an nginx reload when certificate material is newly generated.
   - Iterations:
     - `test.cluster.local`: certificate `/etc/ssl/certs/test.cluster.local.crt`; key `/etc/ssl/private/test.cluster.local.key`; common name `test.cluster.local`
     - `ci.cluster.local`: certificate `/etc/ssl/certs/ci.cluster.local.crt`; key `/etc/ssl/private/ci.cluster.local.key`; common name `ci.cluster.local`
     - `status.cluster.local`: certificate `/etc/ssl/certs/status.cluster.local.crt`; key `/etc/ssl/private/status.cluster.local.key`; common name `status.cluster.local`

5. `sites` (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders `cookbooks/nginx-multisite/templates/default/site.conf.erb` to one file per site under `/etc/nginx/sites-available`.
   - Creates one enabled-site symlink per site under `/etc/nginx/sites-enabled`.
   - Removes `/etc/nginx/sites-enabled/default`.
   - Notifies an nginx reload when a virtual-host file, symlink, or default-site removal changes.
   - Iterations:
     - `test.cluster.local`:
       - Configuration: `/etc/nginx/sites-available/test.cluster.local`
       - Symlink: `/etc/nginx/sites-enabled/test.cluster.local`
       - Document root: `/opt/server/test`
       - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
       - Private key: `/etc/ssl/private/test.cluster.local.key`
     - `ci.cluster.local`:
       - Configuration: `/etc/nginx/sites-available/ci.cluster.local`
       - Symlink: `/etc/nginx/sites-enabled/ci.cluster.local`
       - Document root: `/opt/server/ci`
       - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
       - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - `status.cluster.local`:
       - Configuration: `/etc/nginx/sites-available/status.cluster.local`
       - Symlink: `/etc/nginx/sites-enabled/status.cluster.local`
       - Document root: `/opt/server/status`
       - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
       - Private key: `/etc/ssl/private/status.cluster.local.key`

Template-content details such as exact fail2ban jail values, nginx security directives, TLS ciphers, headers, HSTS, CSP, and sysctl settings were reported in the original plan but were not independently included in the supplied structured template analysis. Verify those values against the source templates before implementation.

## Dependencies

**External cookbook dependencies**: None listed in the supplied metadata or execution tree.

**System package dependencies**:

- `nginx`
- `openssl`
- `ca-certificates`
- `fail2ban`
- `ufw`

**Service dependencies**:

- `nginx`
- `fail2ban`
- `ssh`

**Platform dependencies**: Platform metadata was not included in the supplied structured analysis. Verify supported distributions before migration. UFW-specific tasks must be gated or replaced on systems that do not use UFW.

## Credentials

**Detection Summary**: No externally sourced credentials were detected. Generated TLS private keys are sensitive local files created by the cookbook across the SSL, site, and attribute-related implementation files.

**Source**:
  - **Provider**: None detected
  - **URL**: None
  - **Path**: None

### Generated TLS private keys

- **Variable(s)**: Site-derived certificate and key paths; exact attribute names require verification against `cookbooks/nginx-multisite/attributes/default.rb`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/attributes/default.rb`
- **Current storage**: Locally generated files under `/etc/ssl/private`; no data bag, vault, environment-variable, or external secret-manager retrieval was detected
- **Usage context**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Permissions**: Mode `0640`, owned by `root:ssl-cert`

### Generated TLS certificates

- **Variable(s)**: Site-derived certificate paths; exact attribute names require verification against `cookbooks/nginx-multisite/attributes/default.rb`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
  - `cookbooks/nginx-multisite/attributes/default.rb`
- **Current storage**: Locally generated self-signed certificate files
- **Usage context**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`

No passwords, API keys, database credentials, encrypted data bags, Chef Vault items, CyberArk references, Conjur variables, or secret-related environment variables were detected.

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

- `test.cluster.local`: HTTP `80`, HTTPS `443`
- `ci.cluster.local`: HTTP `80`, HTTPS `443`
- `status.cluster.local`: HTTP `80`, HTTPS `443`
- SSH: TCP `22`

**Sockets and logs**:

- nginx PID file: `/run/nginx.pid`
- Global access log: `/var/log/nginx/access.log`
- Global error log: `/var/log/nginx/error.log`
- `test.cluster.local` logs: `/var/log/nginx/test.cluster.local_access.log`, `/var/log/nginx/test.cluster.local_error.log`
- `ci.cluster.local` logs: `/var/log/nginx/ci.cluster.local_access.log`, `/var/log/nginx/ci.cluster.local_error.log`
- `status.cluster.local` logs: `/var/log/nginx/status.cluster.local_access.log`, `/var/log/nginx/status.cluster.local_error.log`
- SSH authentication log: `/var/log/auth.log`
- No application Unix socket is configured.

**Templates rendered**:

| Template | Destination | Render count |
|---|---|---:|
| `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` | `/etc/fail2ban/jail.local` | 1 |
| `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` | `/etc/nginx/nginx.conf` | 1 |
| `cookbooks/nginx-multisite/templates/default/security.conf.erb` | `/etc/nginx/conf.d/security.conf` | 1 |
| `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` | `/etc/sysctl.d/99-security.conf` | 1 |
| `cookbooks/nginx-multisite/templates/default/site.conf.erb` | `/etc/nginx/sites-available/test.cluster.local` | 1 |
| `cookbooks/nginx-multisite/templates/default/site.conf.erb` | `/etc/nginx/sites-available/ci.cluster.local` | 1 |
| `cookbooks/nginx-multisite/templates/default/site.conf.erb` | `/etc/nginx/sites-available/status.cluster.local` | 1 |

**Total template render operations**: `7`

## Pre-flight checks:

```bash
# Package checks
dpkg -l nginx openssl ca-certificates fail2ban ufw 2>/dev/null || \
rpm -q nginx openssl ca-certificates fail2ban ufw

# Service checks
systemctl status nginx
systemctl status fail2ban
systemctl status ssh

# nginx syntax and listener checks
nginx -t
nginx -T | grep -E 'server_name (test\.cluster\.local|ci\.cluster\.local|status\.cluster\.local)'
nginx -T | grep -E 'listen (80|443)'

# Firewall checks
ufw status verbose
ufw status | grep -E '22/tcp|80/tcp|443/tcp'

# SSH hardening checks
grep -E '^[[:space:]]*(PermitRootLogin|PasswordAuthentication)[[:space:]]+no' \
  /etc/ssh/sshd_config

# Sysctl configuration check
sysctl -p /etc/sysctl.d/99-security.conf

# test.cluster.local HTTP redirect
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/

# test.cluster.local HTTPS endpoint
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/

# test.cluster.local document root and static file
ls -ld /opt/server/test
ls -lh /opt/server/test/index.html
stat -c '%U:%G %a %n' /opt/server/test/index.html

# test.cluster.local certificate and key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key
readlink -f /etc/nginx/sites-enabled/test.cluster.local

# ci.cluster.local HTTP redirect
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/

# ci.cluster.local HTTPS endpoint
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/

# ci.cluster.local document root and static file
ls -ld /opt/server/ci
ls -lh /opt/server/ci/index.html
stat -c '%U:%G %a %n' /opt/server/ci/index.html

# ci.cluster.local certificate and key
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key
readlink -f /etc/nginx/sites-enabled/ci.cluster.local

# status.cluster.local HTTP redirect
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/

# status.cluster.local HTTPS endpoint
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/

# status.cluster.local document root and static file
ls -ld /opt/server/status
ls -lh /opt/server/status/index.html
stat -c '%U:%G %a %n' /opt/server/status/index.html

# status.cluster.local certificate and key
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -subject -dates
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key
readlink -f /etc/nginx/sites-enabled/status.cluster.local

# Default site must be absent
test ! -e /etc/nginx/sites-enabled/default

# nginx process and endpoint checks
test -S /run/nginx.pid || test -f /run/nginx.pid
ss -ltnp | grep -E ':(80|443)\b'
```

Expected results:

- `nginx`, `fail2ban`, and `ssh` are installed and available; nginx and fail2ban are enabled and running.
- `nginx -t` succeeds.
- Each HTTP virtual host redirects to its corresponding HTTPS URL.
- Each HTTPS virtual host returns successful content from its own static file.
- Certificates contain the corresponding site common name.
- Private keys are owned by `root:ssl-cert` with mode `640`.
- Site directories are owned by `www-data:www-data` with mode `0755`.
- Static files are owned by `www-data:www-data` with mode `0644`.
- Ports `22/tcp`, `80/tcp`, and `443/tcp` are allowed by the firewall.
- `/etc/nginx/sites-enabled/default` does not exist.
