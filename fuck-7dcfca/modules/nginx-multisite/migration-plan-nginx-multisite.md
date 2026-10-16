---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx for three sites—`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It creates each document root and index file, generates one locally signed TLS certificate and private key per site, renders global and virtual-host configuration, enables Fail2ban and UFW, applies security sysctl settings, and disables SSH root login and password authentication. Listener ports 80 and 443 must be confirmed from the `site.conf.erb` template before migration.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Nginx virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: Ports 80 and 443 are expected from the plan but require verification in `site.conf.erb`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/test.cluster.local.crt`; private key `/etc/ssl/private/test.cluster.local.key`

- **ci.cluster.local**: Nginx virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: Ports 80 and 443 are expected from the plan but require verification in `site.conf.erb`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/ci.cluster.local.crt`; private key `/etc/ssl/private/ci.cluster.local.key`

- **status.cluster.local**: Nginx virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: Ports 80 and 443 are expected from the plan but require verification in `site.conf.erb`
  - Key Config: SSL enabled; certificate `/etc/ssl/certs/status.cluster.local.crt`; private key `/etc/ssl/private/status.cluster.local.key`

Security configuration is not an instance loop. It consists of Fail2ban, UFW, and SSH hardening resources:

- Fail2ban package and service management
- UFW default-deny policy with SSH, HTTP, and HTTPS allowed
- SSH settings:
  - `PermitRootLogin no`
  - `PasswordAuthentication no`

## File Structure

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
├── providers/
└── files/
```

No provider files or static files under `files/default/` or `files/` are included in the supplied directory listing. The three `cookbook_file` resources require these migration inputs to be recovered or supplied:

- `test/index.html`
- `ci/index.html`
- `status/index.html`

## Module Explanation

The cookbook performs operations in this order:

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes `security.rb`.
   - Includes `nginx.rb`.
   - Includes `ssl.rb`.
   - Includes `sites.rb`.
   - Execution order is security, Nginx installation and global configuration, TLS generation, then virtual-host configuration.
   - Resources: four `include_recipe` resources.

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs `fail2ban` and `ufw`.
   - Enables and starts the `fail2ban` service.
   - Renders `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` to `/etc/fail2ban/jail.local` with mode `0644`.
   - Executes UFW commands in this order:
     1. `ufw --force default deny`
     2. `ufw allow ssh`
     3. `ufw allow http`
     4. `ufw allow https`
     5. `ufw --force enable`
   - Renders `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` to `/etc/sysctl.d/99-security.conf` with mode `0644`.
   - Defines `sysctl -p /etc/sysctl.d/99-security.conf` with action `nothing`; no execution notification is shown.
   - Conditionally disables SSH root login with:
     ```bash
     sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
     ```
   - Conditionally disables SSH password authentication with:
     ```bash
     sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
     ```
   - Defines the `ssh` service with action `nothing`; no restart or reload notification is shown.
   - Resources: one package resource installing two packages, two service resources, two templates, and eight execute resources.

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs the `nginx` package without a specified version.
   - Renders `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` to `/etc/nginx/nginx.conf` with mode `0644`.
   - Renders `cookbooks/nginx-multisite/templates/default/security.conf.erb` to `/etc/nginx/conf.d/security.conf` with mode `0644`.
   - Enables and starts the `nginx` service.
   - Creates `/opt/server/test` and deploys `/opt/server/test/index.html`.
   - Creates `/opt/server/ci` and deploys `/opt/server/ci/index.html`.
   - Creates `/opt/server/status` and deploys `/opt/server/status/index.html`.
   - The three index-file source contents are absent from the supplied directory listing and must be recovered before implementation.
   - Iterations:
     - **test.cluster.local**: directory `/opt/server/test`; file `/opt/server/test/index.html`
     - **ci.cluster.local**: directory `/opt/server/ci`; file `/opt/server/ci/index.html`
     - **status.cluster.local**: directory `/opt/server/status`; file `/opt/server/status/index.html`
   - Resources: one package, two templates, one service, three directories, and three `cookbook_file` resources.
   - No active `www-data` group resource is confirmed by the execution sequence.

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs `openssl` and `ca-certificates`.
   - Creates the `ssl-cert` group.
   - Creates `/etc/ssl/certs`.
   - Creates `/etc/ssl/private`.
   - Directory modes and ownership are not confirmed by the supplied execution tree and must not be assumed without further analysis.
   - Generates a self-signed RSA 2048-bit certificate valid for 365 days for each SSL-enabled site.
   - **test.cluster.local**:
     - Private key: `/etc/ssl/private/test.cluster.local.key`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Common Name: `test.cluster.local`
     - Key commands set mode `0640` and ownership `root:ssl-cert`.
   - **ci.cluster.local**:
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Common Name: `ci.cluster.local`
     - Key commands set mode `0640` and ownership `root:ssl-cert`.
   - **status.cluster.local**:
     - Private key: `/etc/ssl/private/status.cluster.local.key`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Common Name: `status.cluster.local`
     - Key commands set mode `0640` and ownership `root:ssl-cert`.
   - Each certificate uses subject values:
     ```text
     /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=<site>/emailAddress=admin@example.com
     ```
   - Iterations:
     - `test.cluster.local`
     - `ci.cluster.local`
     - `status.cluster.local`
   - Resources: one package resource installing two packages, one group, two directories, and three execute resources.

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Renders one virtual-host configuration for each site.
   - Creates one enabled-site symlink for each site.
   - **test.cluster.local**:
     - Template: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
     - Destination: `/etc/nginx/sites-available/test.cluster.local`
     - Symlink: `/etc/nginx/sites-enabled/test.cluster.local`
     - Document root: `/opt/server/test`
     - SSL enabled: `true`
     - Certificate: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key: `/etc/ssl/private/test.cluster.local.key`
   - **ci.cluster.local**:
     - Template: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
     - Destination: `/etc/nginx/sites-available/ci.cluster.local`
     - Symlink: `/etc/nginx/sites-enabled/ci.cluster.local`
     - Document root: `/opt/server/ci`
     - SSL enabled: `true`
     - Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key: `/etc/ssl/private/ci.cluster.local.key`
   - **status.cluster.local**:
     - Template: `cookbooks/nginx-multisite/templates/default/site.conf.erb`
     - Destination: `/etc/nginx/sites-available/status.cluster.local`
     - Symlink: `/etc/nginx/sites-enabled/status.cluster.local`
     - Document root: `/opt/server/status`
     - SSL enabled: `true`
     - Certificate: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key: `/etc/ssl/private/status.cluster.local.key`
   - Iterations:
     - **test.cluster.local**: one template render and one symlink
     - **ci.cluster.local**: one template render and one symlink
     - **status.cluster.local**: one template render and one symlink
   - Deletes `/etc/nginx/sites-enabled/default`.
   - Template variables are `server_name`, `document_root`, `ssl_enabled`, `cert_file`, and `key_file`.
   - Resources: three templates, three links, and one deleted file.
   - No explicit Nginx reload or restart is shown. A controlled reload handler should be added only after `nginx -t` validation.
   - Listener directives for ports 80 and 443 are not confirmed by the supplied analysis and must be verified in `site.conf.erb`.

## Dependencies

**External cookbook dependencies**: Not specified. Inspect the actual `metadata.rb` before adding dependencies to the Ansible design.

**System package dependencies**:

- `fail2ban`
- `ufw`
- `nginx`
- `openssl`
- `ca-certificates`

**Service dependencies**:

- `fail2ban`: enabled and started
- `nginx`: enabled and started
- `ssh`: declared with action `nothing`; no active restart or start action is shown

**Network policy**:

- Default incoming policy denied
- SSH allowed
- HTTP allowed
- HTTPS allowed

## Credentials

**Detection Summary**: Six locally generated TLS artifacts across two recipe files; no external application credentials or secret-provider integrations detected.

**Source**:

- **Provider**: None detected
- **URL**: None detected
- **Path**: None detected

### TLS Private Keys

- **Variable(s)**: Dynamic `key_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated files
- **Usage context**: Nginx TLS private keys
- **Paths**:
  - `/etc/ssl/private/test.cluster.local.key`
  - `/etc/ssl/private/ci.cluster.local.key`
  - `/etc/ssl/private/status.cluster.local.key`
- **Permissions**: Mode `0640`
- **Ownership**: `root:ssl-cert`

### TLS Certificates

- **Variable(s)**: Dynamic `cert_file`
- **Source file(s)**:
  - `cookbooks/nginx-multisite/recipes/ssl.rb`
  - `cookbooks/nginx-multisite/recipes/sites.rb`
- **Current storage**: Locally generated self-signed certificates
- **Usage context**: Nginx TLS certificates
- **Paths**:
  - `/etc/ssl/certs/test.cluster.local.crt`
  - `/etc/ssl/certs/ci.cluster.local.crt`
  - `/etc/ssl/certs/status.cluster.local.crt`
- **Properties**:
  - RSA 2048-bit key
  - Self-signed
  - Valid for 365 days
  - Subject email `admin@example.com`

No data bags, Chef Vault references, Conjur variables, CyberArk references, HashiCorp Vault references, AWS Secrets Manager references, secret environment variables, hardcoded passwords, or database credentials were detected.

## Checks for the Migration

**Files to verify**:

- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssh/sshd_config`
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local`
- `/etc/nginx/sites-enabled/ci.cluster.local`
- `/etc/nginx/sites-enabled/status.cluster.local`
- `/opt/server/test/index.html`
- `/opt/server/ci/index.html`
- `/opt/server/status/index.html`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`

`/etc/nginx/sites-enabled/default` must not exist after migration.

**Service endpoints to check**:

- `test.cluster.local`: ports 80 and 443, pending verification in `site.conf.erb`
- `ci.cluster.local`: ports 80 and 443, pending verification in `site.conf.erb`
- `status.cluster.local`: ports 80 and 443, pending verification in `site.conf.erb`

**Unix sockets**: None configured or referenced.

**Templates rendered**:

- `cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local`: 1 render
- `cookbooks/nginx-multisite/templates/default/nginx.conf.erb` → `/etc/nginx/nginx.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/security.conf.erb` → `/etc/nginx/conf.d/security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf`: 1 render
- `cookbooks/nginx-multisite/templates/default/site.conf.erb`:
  - `/etc/nginx/sites-available/test.cluster.local`: 1 render
  - `/etc/nginx/sites-available/ci.cluster.local`: 1 render
  - `/etc/nginx/sites-available/status.cluster.local`: 1 render
  - Total: 3 renders

## Pre-flight checks

```bash
# Verify required packages
dpkg -l fail2ban ufw nginx openssl ca-certificates

# Verify managed services
systemctl status fail2ban
systemctl status nginx
systemctl is-enabled fail2ban
systemctl is-enabled nginx

# Validate Nginx configuration before any reload
nginx -t
nginx -T | grep -E 'test\.cluster\.local|ci\.cluster\.local|status\.cluster\.local'

# Inspect rendered Nginx configuration and confirm listener directives
grep -E 'include|listen|server_name|root|ssl_certificate|ssl_certificate_key' \
  /etc/nginx/nginx.conf \
  /etc/nginx/conf.d/security.conf \
  /etc/nginx/sites-available/test.cluster.local \
  /etc/nginx/sites-available/ci.cluster.local \
  /etc/nginx/sites-available/status.cluster.local

# Verify security configuration
ufw status verbose
ufw status numbered
test -f /etc/fail2ban/jail.local
systemctl status fail2ban
fail2ban-client status

test -f /etc/sysctl.d/99-security.conf
sysctl -p /etc/sysctl.d/99-security.conf
cat /etc/sysctl.d/99-security.conf

grep -E '^[[:space:]]*PermitRootLogin' /etc/ssh/sshd_config
grep -E '^[[:space:]]*PasswordAuthentication' /etc/ssh/sshd_config

# Verify SSH access before enforcing SSH hardening
# Confirm a non-root key-based administrative login is available.

# Verify default site removal
test ! -e /etc/nginx/sites-enabled/default
```

### test.cluster.local

```bash
test -d /opt/server/test
test -f /opt/server/test/index.html
test -f /etc/nginx/sites-available/test.cluster.local
test -L /etc/nginx/sites-enabled/test.cluster.local
readlink -f /etc/nginx/sites-enabled/test.cluster.local

test -f /etc/ssl/certs/test.cluster.local.crt
test -f /etc/ssl/private/test.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/test.cluster.local.key

openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout \
  -subject -issuer -dates -ext subjectAltName
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -noout -checkend 0

# Run only if site.conf.erb confirms listeners on ports 80 and 443
curl -I -H 'Host: test.cluster.local' http://127.0.0.1/
curl -k -I --resolve test.cluster.local:443:127.0.0.1 \
  https://test.cluster.local/
```

Expected key metadata:

```text
root:ssl-cert 640
```

Expected certificate subject includes:

```text
CN=test.cluster.local
```

### ci.cluster.local

```bash
test -d /opt/server/ci
test -f /opt/server/ci/index.html
test -f /etc/nginx/sites-available/ci.cluster.local
test -L /etc/nginx/sites-enabled/ci.cluster.local
readlink -f /etc/nginx/sites-enabled/ci.cluster.local

test -f /etc/ssl/certs/ci.cluster.local.crt
test -f /etc/ssl/private/ci.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/ci.cluster.local.key

openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout \
  -subject -issuer -dates -ext subjectAltName
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -noout -checkend 0

# Run only if site.conf.erb confirms listeners on ports 80 and 443
curl -I -H 'Host: ci.cluster.local' http://127.0.0.1/
curl -k -I --resolve ci.cluster.local:443:127.0.0.1 \
  https://ci.cluster.local/
```

Expected key metadata:

```text
root:ssl-cert 640
```

Expected certificate subject includes:

```text
CN=ci.cluster.local
```

### status.cluster.local

```bash
test -d /opt/server/status
test -f /opt/server/status/index.html
test -f /etc/nginx/sites-available/status.cluster.local
test -L /etc/nginx/sites-enabled/status.cluster.local
readlink -f /etc/nginx/sites-enabled/status.cluster.local

test -f /etc/ssl/certs/status.cluster.local.crt
test -f /etc/ssl/private/status.cluster.local.key
stat -c '%U:%G %a %n' /etc/ssl/private/status.cluster.local.key

openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout \
  -subject -issuer -dates -ext subjectAltName
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -noout -checkend 0

# Run only if site.conf.erb confirms listeners on ports 80 and 443
curl -I -H 'Host: status.cluster.local' http://127.0.0.1/
curl -k -I --resolve status.cluster.local:443:127.0.0.1 \
  https://status.cluster.local/
```

Expected key metadata:

```text
root:ssl-cert 640
```

Expected certificate subject includes:

```text
CN=status.cluster.local
```

### Listening-port checks

Run after confirming the `listen` directives in `site.conf.erb`:

```bash
ss -tlnp | grep ':80'
ss -tlnp | grep ':443'

netstat -tulpn | grep -E ':80|:443'
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN
```

### Logs

```bash
journalctl -u nginx --no-pager -n 100
journalctl -u fail2ban --no-pager -n 100
journalctl -u ssh --no-pager -n 100
```

Review Nginx configuration errors, certificate-loading failures, Fail2ban startup errors, UFW status, and SSH configuration errors.