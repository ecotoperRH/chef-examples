---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx‑multisite

**TLDR**: This cookbook configures an Nginx web‑server with three TLS‑enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, `status.cluster.local`). It also hardens the host (fail2ban, ufw, SSH) and generates self‑signed certificates for each site. All resources are deterministic – no data bags, vaults or external secrets are used.

## Service Type and Instances

**Service Type**: Web Server (Nginx)

**Configured Instances**:
- **test.cluster.local**: TLS‑enabled virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`
  - Key Config: SSL enabled – cert `/etc/ssl/certs/test.cluster.local.crt`, key `/etc/ssl/private/test.cluster.local.key`
- **ci.cluster.local**: TLS‑enabled virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`
  - Key Config: SSL enabled – cert `/etc/ssl/certs/ci.cluster.local.crt`, key `/etc/ssl/private/ci.cluster.local.key`
- **status.cluster.local**: TLS‑enabled virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: `80 (HTTP), 443 (HTTPS)`
  - Key Config: SSL enabled – cert `/etc/ssl/certs/status.cluster.local.crt`, key `/etc/ssl/private/status.cluster.local.key`

## File Structure

**MANDATORY: Preserve this section from the original plan.**
```
Recipes
```
recipes/default.rb
recipes/security.rb
recipes/nginx.rb
recipes/ssl.rb
recipes/sites.rb
```
Attributes
```
attributes/default.rb
```
Templates
```
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/fail2ban.jail.local.erb
templates/default/sysctl-security.conf.erb
```
Static Files (cookbook_file)
```
files/default/index.html   # (used for each site – source path is dynamic per site)
```

## Module Explanation

The cookbook runs `nginx‑multisite::default` which includes the sub‑recipes in the exact order below. All resources are listed in the order they are declared.

1. **cookbooks/nginx-multisite/recipes/default.rb**
   - Includes `nginx-multisite::security` → `security.rb`
   - Includes `nginx-multisite::nginx` → `nginx.rb`
   - Includes `nginx-multisite::ssl` → `ssl.rb`
   - Includes `nginx-multisite::sites` → `sites.rb`

2. **cookbooks/nginx-multisite/recipes/security.rb**
   - `package[fail2ban]` – install fail2ban
   - `service[fail2ban]` – enable & start
   - `template[/etc/fail2ban/jail.local]` – deploy `fail2ban.jail.local.erb` (mode 0644)
   - `execute[ufw_default_deny]` – `ufw --force default deny`
   - `execute[ufw_allow_ssh]` – `ufw allow ssh`
   - `execute[ufw_allow_http]` – `ufw allow http`
   - `execute[ufw_allow_https]` – `ufw allow https`
   - `execute[ufw_enable]` – `ufw --force enable`
   - `template[/etc/sysctl.d/99-security.conf]` – deploy `sysctl-security.conf.erb` (mode 0644)
   - `execute[reload_sysctl]` – `sysctl -p /etc/sysctl.d/99-security.conf` (triggered by template)
   - `execute[disable root login]` – sed to set `PermitRootLogin no` in `/etc/ssh/sshd_config`
   - `execute[disable password auth]` – sed to set `PasswordAuthentication no` in `/etc/ssh/sshd_config`
   - `service[ssh]` – reload (triggered by the two execute resources)

3. **cookbooks/nginx-multisite/recipes/nginx.rb**
   - `package[nginx]` – install nginx
   - `template[/etc/nginx/nginx.conf]` – deploy `nginx.conf.erb` (mode 0644)
   - `template[/etc/nginx/conf.d/security.conf]` – deploy `security.conf.erb` (mode 0644)
   - `service[nginx]` – enable & start
   - **Loop over `node['nginx']['sites']`** (expanded):
     - **test.cluster.local**
       - `directory[/opt/server/test]` – create (mode 0755)
       - `cookbook_file[/opt/server/test/index.html]` – copy `files/default/index.html` (mode 0644)
     - **ci.cluster.local**
       - `directory[/opt/server/ci]` – create (mode 0755)
       - `cookbook_file[/opt/server/ci/index.html]` – copy `files/default/index.html` (mode 0644)
     - **status.cluster.local**
       - `directory[/opt/server/status]` – create (mode 0755)
       - `cookbook_file[/opt/server/status/index.html]` – copy `files/default/index.html` (mode 0644)

4. **cookbooks/nginx-multisite/recipes/ssl.rb**
   - `package[openssl ca-certificates]` – install openssl and ca‑certificates
   - `group[ssl-cert]` – create group `ssl-cert`
   - `directory[/etc/ssl/certs]` – create (mode 0755)
   - `directory[/etc/ssl/private]` – create (mode 0710)
   - **Loop over `node['nginx']['sites']`** (expanded):
     - **test.cluster.local**
       - `execute[generate-ssl-cert-test.cluster.local]` – runs openssl to create self‑signed cert `/etc/ssl/certs/test.cluster.local.crt` and key `/etc/ssl/private/test.cluster.local.key`; sets permissions `640` and ownership `root:ssl-cert`
     - **ci.cluster.local**
       - `execute[generate-ssl-cert-ci.cluster.local]` – same command with `ci.cluster.local`
     - **status.cluster.local**
       - `execute[generate-ssl-cert-status.cluster.local]` – same command with `status.cluster.local`

5. **cookbooks/nginx-multisite/recipes/sites.rb**
   - **Loop over `node['nginx']['sites']`** (expanded):
     - **test.cluster.local**
       - `template[/etc/nginx/sites-available/test.cluster.local]` – deploy `site.conf.erb` (mode 0644) with variables:
         - `server_name = test.cluster.local`
         - `document_root = /opt/server/test`
         - `ssl_enabled = true`
         - `cert_file = /etc/ssl/certs/test.cluster.local.crt`
         - `key_file = /etc/ssl/private/test.cluster.local.key`
       - `link[/etc/nginx/sites-enabled/test.cluster.local]` – create symlink to the file in `sites-available`
     - **ci.cluster.local**
       - `template[/etc/nginx/sites-available/ci.cluster.local]` – same pattern with `ci` values
       - `link[/etc/nginx/sites-enabled/ci.cluster.local]` – symlink
     - **status.cluster.local**
       - `template[/etc/nginx/sites-available/status.cluster.local]` – same pattern with `status` values
       - `link[/etc/nginx/sites-enabled/status.cluster.local]` – symlink
   - `file[/etc/nginx/sites-enabled/default]` – delete default site

## Dependencies

- **External cookbook dependencies**: None (all resources are core Chef resources)
- **System package dependencies**: `nginx`, `openssl`, `ca-certificates`, `fail2ban`
- **Service dependencies**: `nginx` (systemd), `fail2ban` (systemd), `ssh` (reloaded), `ufw` (CLI)

## Credentials

**Detection Summary**: 0 credentials detected.

No credentials or secrets were detected in this cookbook. All configuration values appear to be non‑sensitive.

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
- Document roots: `/opt/server/test/index.html`, `/opt/server/ci/index.html`, `/opt/server/status/index.html`
- SSL certificates: `/etc/ssl/certs/test.cluster.local.crt`, `/etc/ssl/certs/ci.cluster.local.crt`, `/etc/ssl/certs/status.cluster.local.crt`
- SSL keys: `/etc/ssl/private/test.cluster.local.key`, `/etc/ssl/private/ci.cluster.local.key`, `/etc/ssl/private/status.cluster.local.key`
- Firewall rules (`ufw status verbose`)
- Fail2ban jail (`/etc/fail2ban/jail.local`)

**Service endpoints to check**

| Service | Port | Expected Response |
|---------|------|-------------------|
| HTTP (all sites) | 80 | `200 OK` with the static `index.html` page |
| HTTPS (all sites) | 443 | `200 OK` with the same page, using the self‑signed cert (ignore warning) |

**Templates rendered**

| Template | Render Count | Destination(s) |
|----------|--------------|----------------|
| `nginx.conf.erb` | 1 | `/etc/nginx/nginx.conf` |
| `security.conf.erb` | 1 | `/etc/nginx/conf.d/security.conf` |
| `site.conf.erb` | 3 | `/etc/nginx/sites-available/<site>` (one per site) |
| `fail2ban.jail.local.erb` | 1 | `/etc/fail2ban/jail.local` |
| `sysctl-security.conf.erb` | 1 | `/etc/sysctl.d/99-security.conf` |

## Pre‑flight checks:
```bash
# 1. Verify Nginx service
systemctl status nginx
ps aux | grep nginx

# 2. Verify each virtual host (HTTP)
for site in test.cluster.local ci.cluster.local status.cluster.local; do
  curl -I http://$site/   # should return 200 OK and the static index.html
done

# 3. Verify each virtual host (HTTPS) – ignore self‑signed warning
for site in test.cluster.local ci.cluster.local status.cluster.local; do
  curl -k -I https://$site/   # should return 200 OK
done

# 4. Verify document roots and index.html files
for dir in /opt/server/test /opt/server/ci /opt/server/status; do
  ls -l $dir/index.html
done

# 5. Verify SSL certificates and permissions
for site in test.cluster.local ci.cluster.local status.cluster.local; do
  cert="/etc/ssl/certs/${site}.crt"
  key="/etc/ssl/private/${site}.key"
  echo "=== $site ==="
  openssl x509 -noout -subject -in $cert
  ls -l $key
done

# 6. Verify firewall (ufw) rules
ufw status verbose

# 7. Verify fail2ban is active
systemctl status fail2ban
fail2ban-client status

# 8. Verify SSH hardening
grep -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config
systemctl status ssh

# 9. Verify sysctl security settings applied
sysctl -a | grep -E 'net.ipv4.ip_forward|kernel.randomize_va_space'
```