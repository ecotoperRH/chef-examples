---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server with multiple virtual hosts (3 sites), each with SSL enabled. It includes security hardening through fail2ban, UFW firewall, SSH hardening, and system-level security configurations.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Main test environment website
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **ci.cluster.local**: Continuous integration environment website
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **status.cluster.local**: Status monitoring website
  - Location/Path: /opt/server/status
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
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
   - Configures system security via sysctl
   - Hardens SSH configuration (disables root login, disables password authentication)
   - Resources: package (1), service (2), template (2), execute (7), file (0)

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Configures main nginx.conf with worker settings and includes
   - Configures security.conf with hardening settings
   - Creates document root directories for each site
   - Places index.html files in each document root
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)
   - Iterations: Creates document root directory and places index.html file for test.cluster.local, ci.cluster.local, status.cluster.local

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL packages: openssl, ca-certificates
   - Creates SSL certificate and private key directories
   - Generates self-signed SSL certificates for each site
   - Resources: package (1), group (1), directory (2), execute (3)
   - Iterations: Generates a self-signed certificate for test.cluster.local, ci.cluster.local, status.cluster.local

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates Nginx site configuration files for each site
   - Creates symlinks from sites-available to sites-enabled
   - Removes default site configuration
   - Resources: template (3), link (3), file (1)
   - Iterations: Creates site configuration and enables it for test.cluster.local, ci.cluster.local, status.cluster.local

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

**Service endpoints to check**:
- Ports listening: 80, 443
- Network interfaces: All interfaces (default)

**Templates rendered**:
- nginx.conf.erb → /etc/nginx/nginx.conf (1 time)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 time)
- site.conf.erb → /etc/nginx/sites-available/test.cluster.local (1 time)
- site.conf.erb → /etc/nginx/sites-available/ci.cluster.local (1 time)
- site.conf.erb → /etc/nginx/sites-available/status.cluster.local (1 time)
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
nginx -T | grep server_name

# Site availability - test.cluster.local
curl -I -H "Host: test.cluster.local" http://localhost
curl -I -k -H "Host: test.cluster.local" https://localhost
openssl s_client -connect localhost:443 -servername test.cluster.local </dev/null | grep "subject="

# Site availability - ci.cluster.local
curl -I -H "Host: ci.cluster.local" http://localhost
curl -I -k -H "Host: ci.cluster.local" https://localhost
openssl s_client -connect localhost:443 -servername ci.cluster.local </dev/null | grep "subject="

# Site availability - status.cluster.local
curl -I -H "Host: status.cluster.local" http://localhost
curl -I -k -H "Host: status.cluster.local" https://localhost
openssl s_client -connect localhost:443 -servername status.cluster.local </dev/null | grep "subject="

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep "Subject:"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep "Subject:"

# File permissions
ls -la /etc/ssl/private/test.cluster.local.key  # Should be 640, root:ssl-cert
ls -la /etc/ssl/private/ci.cluster.local.key  # Should be 640, root:ssl-cert
ls -la /etc/ssl/private/status.cluster.local.key  # Should be 640, root:ssl-cert

# Security configurations
cat /etc/fail2ban/jail.local | grep enabled
ufw status verbose  # Should show default deny with SSH, HTTP, HTTPS allowed
sysctl -a | grep "net.ipv4.conf.all.accept_redirects"  # Should be 0
grep "PermitRootLogin" /etc/ssh/sshd_config  # Should be "no"
grep "PasswordAuthentication" /etc/ssh/sshd_config  # Should be "no"

# Fail2ban status
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth

# Document roots
ls -la /opt/server/test/
ls -la /opt/server/ci/
ls -la /opt/server/status/

# Logs
tail -n 20 /var/log/nginx/access.log
tail -n 20 /var/log/nginx/error.log
tail -n 20 /var/log/nginx/test.cluster.local_access.log
tail -n 20 /var/log/nginx/ci.cluster.local_access.log
tail -n 20 /var/log/nginx/status.cluster.local_access.log

# Network listening
netstat -tulpn | grep nginx  # Should show ports 80 and 443
ss -tlnp | grep nginx  # Should show ports 80 and 443
lsof -i :80
lsof -i :443
```