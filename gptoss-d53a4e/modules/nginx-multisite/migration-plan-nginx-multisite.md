---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx‑multisite

**TLDR**: This cookbook provisions a hardened Nginx web‑server that hosts three TLS‑enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`). It also installs and configures security tooling (fail2ban, ufw, SSH hardening, sysctl tweaks). All resources are explicit – no hidden loops – making a straightforward Ansible translation.

## Service Type and Instances

**Service Type**: Web Server (Nginx) with integrated security hardening.

**Configured Instances**:
- **test.cluster.local**: TLS‑enabled virtual host  
  - Location/Path: `/opt/server/test`  
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`  
  - Key Config: SSL enabled, self‑signed cert `/etc/ssl/certs/test.cluster.local.crt` and key `/etc/ssl/private/test.cluster.local.key`
- **ci.cluster.local**: TLS‑enabled virtual host  
  - Location/Path: `/opt/server/ci`  
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`  
  - Key Config: SSL enabled, self‑signed cert `/etc/ssl/certs/ci.cluster.local.crt` and key `/etc/ssl/private/ci.cluster.local.key`
- **status.cluster.local**: TLS‑enabled virtual host  
  - Location/Path: `/opt/server/status`  
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`  
  - Key Config: SSL enabled, self‑signed cert `/etc/ssl/certs/status.cluster.local.crt` and key `/etc/ssl/private/status.cluster.local.key`

## File Structure

**MANDATORY: Preserve this section from the original plan.**
```
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```

```
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/sysctl-security.conf.erb
```

```
attributes/default.rb
```

*(No static `files/` directory is present in the repository listing; the `cookbook_file` resources reference files that would be placed under `files/default/<site>/index.html` in a full cookbook but are not required for the migration plan.)*

## Module Explanation

The cookbook performs operations in this order:

**1. `cookbooks/nginx-multisite/recipes/default.rb`**
- `include_recipe` `nginx-multisite::security`
- `include_recipe` `nginx-multisite::nginx`
- `include_recipe` `nginx-multisite::ssl`
- `include_recipe` `nginx-multisite::sites`

**2. `cookbooks/nginx-multisite/recipes/security.rb`**
- `package[%w[fail2ban ufw]]` → `:install`
- `service[fail2ban]` → `[:enable, :start]`
- `template[/etc/fail2ban/jail.local]` → source `fail2ban.jail.local.erb`
- `execute[ufw_default_deny]` → `ufw --force default deny`
- `execute[ufw_allow_ssh]` → `ufw allow ssh`
- `execute[ufw_allow_http]` → `ufw allow http`
- `execute[ufw_allow_https]` → `ufw allow https`
- `execute[ufw_enable]` → `ufw --force enable`
- `template[/etc/sysctl.d/99-security.conf]` → source `sysctl-security.conf.erb`
- `execute[reload_sysctl]` → `sysctl -p /etc/sysctl.d/99-security.conf` (action `:nothing`)
- Conditional `if node['security']['ssh']['disable_root']` → `execute[disable root login]` runs `sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config`
- Conditional `if node['security']['ssh']['password_auth'] == false` → `execute[disable password auth]` runs `sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config`
- `service[ssh]` → `:nothing`

**3. `cookbooks/nginx-multisite/recipes/nginx.rb`**
- `package[nginx]` → `:install`
- `template[/etc/nginx/nginx.conf]` → source `nginx.conf.erb`
- `template[/etc/nginx/conf.d/security.conf]` → source `security.conf.erb`
- `service[nginx]` → `[:enable, :start]`

*Per‑site actions (expanded):*

- **test.cluster.local**
  - `directory[/opt/server/test]` → `:create`, mode `0755`
  - `cookbook_file[/opt/server/test/index.html]` → source `test/index.html`, mode `0644`
- **ci.cluster.local**
  - `directory[/opt/server/ci]` → `:create`, mode `0755`
  - `cookbook_file[/opt/server/ci/index.html]` → source `ci/index.html`, mode `0644`
- **status.cluster.local**
  - `directory[/opt/server/status]` → `:create`, mode `0755`
  - `cookbook_file[/opt/server/status/index.html]` → source `status/index.html`, mode `0644`

**4. `cookbooks/nginx-multisite/recipes/ssl.rb`**
- `package[%w[openssl ca-certificates]]` → `:install`
- `group[ssl-cert]` → `:create`
- `directory[node['nginx']['ssl']['certificate_path']]` → `:create`, mode `0755`
- `directory[node['nginx']['ssl']['private_key_path']]` → `:create`, mode `0710`

*Per‑site actions (expanded):*

- **test.cluster.local** → `execute[generate-ssl-cert-test]` runs an `openssl req` command creating `/etc/ssl/certs/test.cluster.local.crt` and `/etc/ssl/private/test.cluster.local.key` (permissions `640`, owner `root:ssl-cert`)
- **ci.cluster.local** → `execute[generate-ssl-cert-ci]` creates `/etc/ssl/certs/ci.cluster.local.crt` and `/etc/ssl/private/ci.cluster.local.key`
- **status.cluster.local** → `execute[generate-ssl-cert-status]` creates `/etc/ssl/certs/status.cluster.local.crt` and `/etc/ssl/private/status.cluster.local.key`

**5. `cookbooks/nginx-multisite/recipes/sites.rb`**
*Per‑site actions (expanded):*

- **test.cluster.local**
  - `template[/etc/nginx/sites-available/test.cluster.local]` → source `site.conf.erb` (variables: `server_name=test.cluster.local`, `document_root=/opt/server/test`, `ssl_enabled=true`, `cert_file=/etc/ssl/certs/test.cluster.local.crt`, `key_file=/etc/ssl/private/test.cluster.local.key`)
  - `link[/etc/nginx/sites-enabled/test.cluster.local]` → `:create` (symlink)
- **ci.cluster.local**
  - `template[/etc/nginx/sites-available/ci.cluster.local]` → source `site.conf.erb` (variables accordingly)
  - `link[/etc/nginx/sites-enabled/ci.cluster.local]` → `:create`
- **status.cluster.local**
  - `template[/etc/nginx/sites-available/status.cluster.local]` → source `site.conf.erb`
  - `link[/etc/nginx/sites-enabled/status.cluster.local]` → `:create`

- `file[/etc/nginx/sites-enabled/default]` → `:delete` (removes the default site)

## Dependencies

**External cookbook dependencies**: None listed in `metadata.rb`.

**System package dependencies**: `nginx`, `fail2ban`, `ufw`, `openssl`, `ca-certificates`

**Service dependencies**: `systemd` (for `nginx` and `fail2ban`), `ssh` daemon (hardening), `ufw` firewall

## Credentials

**Detection Summary**: 0 credentials detected across all files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non‑sensitive.

## Checks for the Migration

**Files to verify**
- `/etc/nginx/nginx.conf`
- `/etc/nginx/conf.d/security.conf`
- `/etc/nginx/sites-available/test.cluster.local`
- `/etc/nginx/sites-available/ci.cluster.local`
- `/etc/nginx/sites-available/status.cluster.local`
- `/etc/nginx/sites-enabled/test.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/ci.cluster.local` (symlink)
- `/etc/nginx/sites-enabled/status.cluster.local` (symlink)
- `/etc/fail2ban/jail.local`
- `/etc/sysctl.d/99-security.conf`
- `/etc/ssl/certs/test.cluster.local.crt`
- `/etc/ssl/certs/ci.cluster.local.crt`
- `/etc/ssl/certs/status.cluster.local.crt`
- `/etc/ssl/private/test.cluster.local.key`
- `/etc/ssl/private/ci.cluster.local.key`
- `/etc/ssl/private/status.cluster.local.key`
- Document root directories `/opt/server/test`, `/opt/server/ci`, `/opt/server/status` with `index.html`

**Service endpoints to check**
- HTTP: **80** (all three sites)
- HTTPS: **443** (all three sites)
- SSH: **22** (hardening checks)
- UFW status (rules for ssh, http, https)

**Templates rendered**
- `fail2ban.jail.local.erb` → `/etc/fail2ban/jail.local` (once)
- `nginx.conf.erb` → `/etc/nginx/nginx.conf` (once)
- `security.conf.erb` → `/etc/nginx/conf.d/security.conf` (once)
- `site.conf.erb` → `/etc/nginx/sites-available/<site>` (3 times)
- `sysctl-security.conf.erb` → `/etc/sysctl.d/99-security.conf` (once)

## Pre‑flight Checks
```bash
# 1. Verify package installation
dpkg -l | grep -E 'nginx|fail2ban|ufw|openssl|ca-certificates'

# 2. Service status
systemctl status nginx
systemctl status fail2ban
systemctl status ufw
systemctl status ssh

# 3. Firewall rules
ufw status verbose

# 4. SSH hardening
grep -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config

# 5. Nginx site reachability (HTTP & HTTPS)
for site in test.cluster.local ci.cluster.local status.cluster.local; do
  echo "=== $site (HTTP) ==="
  curl -I -s http://$site/ | head -n 1
  echo "=== $site (HTTPS) ==="
  curl -k -I -s https://$site/ | head -n 1
done

# 6. TLS certificate sanity
for site in test.cluster.local ci.cluster.local status.cluster.local; do
  openssl x509 -noout -subject -in /etc/ssl/certs/${site}.crt
done

# 7. Verify document roots and index.html
for dir in /opt/server/test /opt/server/ci /opt/server/status; do
  ls -l ${dir}
  test -f ${dir}/index.html && echo "index.html present in ${dir}"
done

# 8. Sysctl security settings
sysctl -a | grep -E 'net.ipv4.ip_forward|net.ipv4.conf.all.rp_filter'
```

All checks must succeed **per site**; any missing file, service, or firewall rule indicates an incomplete migration.