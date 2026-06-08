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
     - Allows SSH (port 22), HTTP (port 80), and HTTPS (port 443)
     - Enables the firewall
   - Deploys system security configuration template to /etc/sysctl.d/99-security.conf
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
   - Configures SSH security if enabled:
     - Disables root login if node['security']['ssh']['disable_root'] is true
     - Disables password authentication if node['security']['ssh']['password_auth'] is false
   - Resources: package (1), service (2), template (2), execute (8), file (0)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration template to /etc/nginx/nginx.conf
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
   - Deploys security configuration template to /etc/nginx/conf.d/security.conf
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
   - Enables and starts nginx service
   - Creates document root directory for test.cluster.local with www-data ownership
   - Creates document root directory for ci.cluster.local with www-data ownership
   - Creates document root directory for status.cluster.local with www-data ownership
   - Deploys index.html file to each document root
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL-related packages: openssl, ca-certificates
   - Creates ssl-cert group
   - Creates certificate and private key directories:
     - /etc/ssl/certs (certificate_path)
     - /etc/ssl/private (private_key_path)
   - Generates self-signed SSL certificates for test.cluster.local
   - Generates self-signed SSL certificates for ci.cluster.local
   - Generates self-signed SSL certificates for status.cluster.local
   - Sets appropriate permissions on key files
   - Resources: package (1), group (1), directory (2), execute (3)

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Deploys site configuration template to /etc/nginx/sites-available/test.cluster.local
   - Deploys site configuration template to /etc/nginx/sites-available/ci.cluster.local
   - Deploys site configuration template to /etc/nginx/sites-available/status.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for each site
   - Removes default nginx site configuration
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None detected
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
- /opt/allowed_keys/ (for organization's approved keys)

**Service endpoints to check**:
- Ports listening: 80, 443
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- nginx.conf.erb (1 time)
- security.conf.erb (1 time)
- site.conf.erb (3 times - one for each site)
- fail2ban.jail.local.erb (1 time)
- sysctl-security.conf.erb (1 time)

## Pre-flight checks:

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
ps aux | grep nginx

# Configuration validation
nginx -t
ufw status
fail2ban-client status

# Site availability - test.cluster.local
curl -I -k https://test.cluster.local
curl -I http://test.cluster.local  # Should redirect to HTTPS
openssl s_client -connect test.cluster.local:443 -servername test.cluster.local </dev/null | grep "subject="

# Site availability - ci.cluster.local
curl -I -k https://ci.cluster.local
curl -I http://ci.cluster.local  # Should redirect to HTTPS
openssl s_client -connect ci.cluster.local:443 -servername ci.cluster.local </dev/null | grep "subject="

# Site availability - status.cluster.local
curl -I -k https://status.cluster.local
curl -I http://status.cluster.local  # Should redirect to HTTPS
openssl s_client -connect status.cluster.local:443 -servername status.cluster.local </dev/null | grep "subject="

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep "Subject:"

# File permissions
ls -la /etc/ssl/private/test.cluster.local.key  # Should be 640, root:ssl-cert
ls -la /etc/ssl/private/ci.cluster.local.key  # Should be 640, root:ssl-cert
ls -la /etc/ssl/private/status.cluster.local.key  # Should be 640, root:ssl-cert

# Document root permissions
ls -la /opt/server/test  # Should be owned by www-data:www-data
ls -la /opt/server/ci  # Should be owned by www-data:www-data
ls -la /opt/server/status  # Should be owned by www-data:www-data

# Fail2ban configuration
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Firewall rules
ufw status verbose  # Should show SSH, HTTP, HTTPS allowed

# SSH hardening verification
grep "^PermitRootLogin" /etc/ssh/sshd_config  # Should be "no"
grep "^PasswordAuthentication" /etc/ssh/sshd_config  # Should be "no"

# Sysctl security settings
sysctl net.ipv4.conf.all.rp_filter  # Should be 1
sysctl net.ipv4.conf.all.accept_redirects  # Should be 0
sysctl net.ipv4.tcp_syncookies  # Should be 1

# Network listening
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443

# Logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/test.cluster.local_access.log
tail -f /var/log/nginx/ci.cluster.local_access.log
tail -f /var/log/nginx/status.cluster.local_access.log

# Organization's approved keys
ls -la /opt/allowed_keys/
cat /opt/allowed_keys/eloycoto.keys
```