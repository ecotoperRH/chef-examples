---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server with multiple virtual hosts (3 sites), each with SSL enabled. It includes security hardening through fail2ban, UFW firewall, SSH hardening, and system-level security configurations.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: SSL-enabled Nginx virtual host
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **ci.cluster.local**: SSL-enabled Nginx virtual host
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **status.cluster.local**: SSL-enabled Nginx virtual host
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

1. **default** (`cookbooks/nginx-multisite/recipes/default.rb`):
   - Includes other recipes in sequence: security, nginx, ssl, sites
   - Resources: include_recipe (4)

2. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs security packages: fail2ban, ufw
   - Configures fail2ban with custom jail settings
   - Sets up UFW firewall with default deny policy and allows SSH, HTTP, HTTPS
   - Configures system-level security via sysctl
   - Hardens SSH configuration (disables root login and password authentication)
   - Resources: package (1), service (2), template (2), execute (7)

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs Nginx package
   - Configures main nginx.conf and security.conf
   - Enables and starts Nginx service
   - Creates document root directory for test.cluster.local
   - Creates document root directory for ci.cluster.local
   - Creates document root directory for status.cluster.local
   - Deploys index.html file to test.cluster.local document root
   - Deploys index.html file to ci.cluster.local document root
   - Deploys index.html file to status.cluster.local document root
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL-related packages: openssl, ca-certificates
   - Creates SSL certificate group and directories
   - Generates self-signed SSL certificate for test.cluster.local
   - Generates self-signed SSL certificate for ci.cluster.local
   - Generates self-signed SSL certificate for status.cluster.local
   - Resources: package (1), group (1), directory (2), execute (3)

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates Nginx site configuration for test.cluster.local
   - Creates Nginx site configuration for ci.cluster.local
   - Creates Nginx site configuration for status.cluster.local
   - Enables test.cluster.local site by creating symlink in sites-enabled
   - Enables ci.cluster.local site by creating symlink in sites-enabled
   - Enables status.cluster.local site by creating symlink in sites-enabled
   - Removes default Nginx site
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None specified in the provided data
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
- Network interfaces: All interfaces (default)

**Templates rendered**:
- nginx.conf.erb → /etc/nginx/nginx.conf (1 time)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 time)
- site.conf.erb → /etc/nginx/sites-available/test.cluster.local, /etc/nginx/sites-available/ci.cluster.local, /etc/nginx/sites-available/status.cluster.local (3 times)
- fail2ban.jail.local.erb → /etc/fail2ban/jail.local (1 time)
- sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf (1 time)

## Pre-flight checks:

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
ps aux | grep nginx

# Configuration validation
nginx -t
cat /etc/nginx/nginx.conf | grep -E 'worker_processes|worker_connections'
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|ssl_protocols'

# Site configuration - test.cluster.local
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/test.cluster.local
ls -la /opt/server/test/
curl -I -k https://test.cluster.local
curl -I http://test.cluster.local # Should redirect to HTTPS

# Site configuration - ci.cluster.local
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/ci.cluster.local
ls -la /opt/server/ci/
curl -I -k https://ci.cluster.local
curl -I http://ci.cluster.local # Should redirect to HTTPS

# Site configuration - status.cluster.local
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/status.cluster.local
ls -la /opt/server/status/
curl -I -k https://status.cluster.local
curl -I http://status.cluster.local # Should redirect to HTTPS

# SSL certificates
ls -la /etc/ssl/certs/test.cluster.local.crt
ls -la /etc/ssl/private/test.cluster.local.key
ls -la /etc/ssl/certs/ci.cluster.local.crt
ls -la /etc/ssl/private/ci.cluster.local.key
ls -la /etc/ssl/certs/status.cluster.local.crt
ls -la /etc/ssl/private/status.cluster.local.key
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep "Subject:"

# Security configurations
cat /etc/fail2ban/jail.local | grep -E 'bantime|maxretry|enabled'
fail2ban-client status
ufw status verbose
cat /etc/ssh/sshd_config | grep -E 'PermitRootLogin|PasswordAuthentication'
sysctl -a | grep -E 'rp_filter|accept_redirects|syncookies'
cat /etc/sysctl.d/99-security.conf

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

# Network listening
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443

# Organization's approved keys
ls -la /opt/allowed_keys/
cat /opt/allowed_keys/* | wc -l  # Check if keys are present
```