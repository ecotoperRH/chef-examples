---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures an Nginx web server with multiple virtual hosts (3 sites), each with SSL enabled. It includes security hardening with fail2ban, UFW firewall, SSH hardening, and system-level security configurations.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Basic Nginx virtual host with SSL
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, self-signed certificate

- **ci.cluster.local**: CI server virtual host with SSL
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, self-signed certificate

- **status.cluster.local**: Status page virtual host with SSL
  - Location/Path: /opt/server/status
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, self-signed certificate

## File Structure

```
recipes/default.rb
recipes/nginx.rb
recipes/security.rb
recipes/sites.rb
recipes/ssl.rb
templates/default/fail2ban.jail.local.erb
templates/default/nginx.conf.erb
templates/default/security.conf.erb
templates/default/site.conf.erb
templates/default/sysctl-security.conf.erb
attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs security packages: fail2ban, ufw
   - Configures and enables fail2ban service
     - Template: fail2ban.jail.local.erb → /etc/fail2ban/jail.local
   - Configures UFW firewall:
     - Sets default policy to deny
     - Allows SSH (port 22), HTTP (port 80), and HTTPS (port 443)
     - Enables the firewall
   - Deploys system security settings
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
   - Hardens SSH configuration:
     - Disables root login (if node['security']['ssh']['disable_root'] is true)
     - Disables password authentication (if node['security']['ssh']['password_auth'] is false)
   - Resources: package (1), service (1), template (2), execute (8)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs Nginx package
   - Deploys main Nginx configuration
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
   - Deploys security configuration for Nginx
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
   - Enables and starts Nginx service
   - Creates document root directory for test.cluster.local
   - Creates document root directory for ci.cluster.local
   - Creates document root directory for status.cluster.local
   - Deploys index.html file for test.cluster.local
   - Deploys index.html file for ci.cluster.local
   - Deploys index.html file for status.cluster.local
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL-related packages: openssl, ca-certificates
   - Creates ssl-cert group
   - Creates SSL certificate and private key directories
   - Generates self-signed SSL certificate for test.cluster.local
   - Generates self-signed SSL certificate for ci.cluster.local
   - Generates self-signed SSL certificate for status.cluster.local
   - Sets appropriate permissions on key files
   - Resources: package (1), group (1), directory (2), execute (3)

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates Nginx site configuration for test.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/test.cluster.local
   - Creates Nginx site configuration for ci.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/ci.cluster.local
   - Creates Nginx site configuration for status.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/status.cluster.local
   - Creates symbolic link to enable test.cluster.local
     - Link: /etc/nginx/sites-available/test.cluster.local → /etc/nginx/sites-enabled/test.cluster.local
   - Creates symbolic link to enable ci.cluster.local
     - Link: /etc/nginx/sites-available/ci.cluster.local → /etc/nginx/sites-enabled/ci.cluster.local
   - Creates symbolic link to enable status.cluster.local
     - Link: /etc/nginx/sites-available/status.cluster.local → /etc/nginx/sites-enabled/status.cluster.local
   - Removes default Nginx site
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None
**System package dependencies**: nginx, fail2ban, ufw, openssl, ca-certificates
**Service dependencies**: nginx, fail2ban, ssh

## Credentials

**Detection Summary**: No credentials detected across files

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive.

## Checks for the Migration

**Files to verify**:
- /etc/nginx/nginx.conf
- /etc/nginx/conf.d/security.conf
- /etc/nginx/sites-available/test.cluster.local
- /etc/nginx/sites-available/ci.cluster.local
- /etc/nginx/sites-available/status.cluster.local
- /etc/nginx/sites-enabled/test.cluster.local
- /etc/nginx/sites-enabled/ci.cluster.local
- /etc/nginx/sites-enabled/status.cluster.local
- /etc/fail2ban/jail.local
- /etc/sysctl.d/99-security.conf
- /etc/ssl/certs/test.cluster.local.crt
- /etc/ssl/certs/ci.cluster.local.crt
- /etc/ssl/certs/status.cluster.local.crt
- /etc/ssl/private/test.cluster.local.key
- /etc/ssl/private/ci.cluster.local.key
- /etc/ssl/private/status.cluster.local.key
- /opt/server/test/index.html
- /opt/server/ci/index.html
- /opt/server/status/index.html

**Service endpoints to check**:
- Ports listening: 80, 443
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- nginx.conf.erb → /etc/nginx/nginx.conf (1 time)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 time)
- site.conf.erb → /etc/nginx/sites-available/[site_name] (3 times, one for each site)
- fail2ban.jail.local.erb → /etc/fail2ban/jail.local (1 time)
- sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf (1 time)

## Pre-flight checks:

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
systemctl status ufw

# Nginx configuration validation
nginx -t

# Site availability - test.cluster.local
curl -I -k https://test.cluster.local
curl -I http://test.cluster.local  # Should redirect to HTTPS
openssl s_client -connect test.cluster.local:443 -servername test.cluster.local </dev/null 2>/dev/null | grep "subject="

# Site availability - ci.cluster.local
curl -I -k https://ci.cluster.local
curl -I http://ci.cluster.local  # Should redirect to HTTPS
openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local </dev/null 2>/dev/null | grep "subject="

# Site availability - status.cluster.local
curl -I -k https://status.cluster.local
curl -I http://status.cluster.local  # Should redirect to HTTPS
openssl s_client -connect status.cluster.local:443 -servername status.cluster.local </dev/null 2>/dev/null | grep "subject="

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep "Subject:"

# Firewall status
ufw status verbose
ufw status numbered

# Fail2ban status
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# SSH hardening verification
grep "PermitRootLogin" /etc/ssh/sshd_config
grep "PasswordAuthentication" /etc/ssh/sshd_config

# System security settings
sysctl -a | grep "net.ipv4.conf.all.rp_filter"
sysctl -a | grep "net.ipv4.conf.all.accept_redirects"
sysctl -a | grep "net.ipv4.tcp_syncookies"

# File permissions
ls -la /etc/ssl/private/
ls -la /etc/ssl/certs/
ls -la /opt/server/test/
ls -la /opt/server/ci/
ls -la /opt/server/status/

# Network listening
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443

# Log verification
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/test.cluster.local_error.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_error.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_error.log
```