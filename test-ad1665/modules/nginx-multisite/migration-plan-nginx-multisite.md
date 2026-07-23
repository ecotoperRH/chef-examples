---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server with multiple virtual hosts (3 sites), each with SSL enabled. It includes security hardening with fail2ban, UFW firewall, SSH hardening, and system-level security configurations.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Basic Nginx virtual host with SSL
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **ci.cluster.local**: Basic Nginx virtual host with SSL
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **status.cluster.local**: Basic Nginx virtual host with SSL
  - Location/Path: /opt/server/status
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

## File Structure

```
cookbooks/nginx-multisite/recipes/default.rb
cookbooks/nginx-multisite/recipes/nginx.rb
cookbooks/nginx-multisite/recipes/security.rb
cookbooks/nginx-multisite/recipes/sites.rb
cookbooks/nginx-multisite/recipes/ssl.rb
cookbooks/nginx-multisite/templates/default/fail2ban.jail.local.erb
cookbooks/nginx-multisite/templates/default/nginx.conf.erb
cookbooks/nginx-multisite/templates/default/security.conf.erb
cookbooks/nginx-multisite/templates/default/site.conf.erb
cookbooks/nginx-multisite/templates/default/sysctl-security.conf.erb
cookbooks/nginx-multisite/attributes/default.rb
```

## Module Explanation

The cookbook performs operations in this order:

1. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs security packages: fail2ban, ufw
   - Enables and starts fail2ban service
   - Deploys fail2ban jail configuration template to /etc/fail2ban/jail.local
     - Template: fail2ban.jail.local.erb → /etc/fail2ban/jail.local
   - Configures UFW firewall:
     - Sets default policy to deny
     - Allows SSH, HTTP, and HTTPS traffic
     - Enables the firewall
   - Deploys sysctl security configuration template to /etc/sysctl.d/99-security.conf
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
   - Configures SSH security if enabled:
     - Disables root login if node['security']['ssh']['disable_root'] is true
     - Disables password authentication if node['security']['ssh']['password_auth'] is false
   - Resources: package (1), service (1), template (2), execute (8), service (1)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration template to /etc/nginx/nginx.conf
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
   - Deploys security configuration template to /etc/nginx/conf.d/security.conf
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
   - Enables and starts nginx service
   - Creates document root directory for test.cluster.local
   - Creates document root directory for ci.cluster.local
   - Creates document root directory for status.cluster.local
   - Deploys index.html file to test.cluster.local document root
   - Deploys index.html file to ci.cluster.local document root
   - Deploys index.html file to status.cluster.local document root
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL-related packages: openssl, ca-certificates
   - Creates ssl-cert group
   - Creates certificate and private key directories:
     - /etc/ssl/certs (certificate_path)
     - /etc/ssl/private (private_key_path)
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
   - Creates symbolic link from sites-available to sites-enabled for test.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for ci.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for status.cluster.local
   - Removes default Nginx site configuration
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
- Network interfaces: All interfaces (default)

**Templates rendered**:
- nginx.conf.erb → /etc/nginx/nginx.conf (1 time)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 time)
- site.conf.erb → /etc/nginx/sites-available/[site_name] (3 times, one for each site)
- fail2ban.jail.local.erb → /etc/fail2ban/jail.local (1 time)
- sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf (1 time)

## Pre-flight checks:

```bash
# Nginx service status
systemctl status nginx
ps aux | grep nginx

# Nginx configuration validation
nginx -t

# Nginx sites verification - check each site individually
# Site: test.cluster.local
curl -I http://test.cluster.local  # Should return 301 redirect to HTTPS
curl -I -k https://test.cluster.local  # Should return 200 OK
curl -k https://test.cluster.local  # Should display index.html content

# Site: ci.cluster.local
curl -I http://ci.cluster.local  # Should return 301 redirect to HTTPS
curl -I -k https://ci.cluster.local  # Should return 200 OK
curl -k https://ci.cluster.local  # Should display index.html content

# Site: status.cluster.local
curl -I http://status.cluster.local  # Should return 301 redirect to HTTPS
curl -I -k https://status.cluster.local  # Should return 200 OK
curl -k https://status.cluster.local  # Should display index.html content

# SSL certificate verification for each site
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep Subject
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep Subject
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep Subject

# Security services verification
# Fail2ban status
systemctl status fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# UFW firewall status
ufw status verbose
ufw status numbered

# SSH security configuration
grep PermitRootLogin /etc/ssh/sshd_config
grep PasswordAuthentication /etc/ssh/sshd_config

# Sysctl security settings
sysctl -a | grep "net.ipv4.conf.all.rp_filter"
sysctl -a | grep "net.ipv4.conf.all.accept_redirects"
sysctl -a | grep "net.ipv4.tcp_syncookies"

# Directory permissions
ls -la /etc/ssl/certs/ | grep cluster.local
ls -la /etc/ssl/private/ | grep cluster.local
ls -la /opt/server/test/
ls -la /opt/server/ci/
ls -la /opt/server/status/

# Network listening
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443

# Logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/test.cluster.local_access.log
tail -f /var/log/nginx/test.cluster.local_error.log
tail -f /var/log/nginx/ci.cluster.local_access.log
tail -f /var/log/nginx/ci.cluster.local_error.log
tail -f /var/log/nginx/status.cluster.local_access.log
tail -f /var/log/nginx/status.cluster.local_error.log
tail -f /var/log/fail2ban.log
```