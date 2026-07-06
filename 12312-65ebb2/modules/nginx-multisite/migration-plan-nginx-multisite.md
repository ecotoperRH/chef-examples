---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook configures Nginx as a web server with multiple virtual hosts (3 sites), each with SSL enabled. It includes security hardening through fail2ban, UFW firewall, SSH hardening, and system-level security configurations.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Standard Nginx virtual host with SSL
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **ci.cluster.local**: Standard Nginx virtual host with SSL
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (HTTPS)
  - Key Config: SSL enabled, HTTP to HTTPS redirect

- **status.cluster.local**: Standard Nginx virtual host with SSL
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
   - Configures system security via sysctl
   - Hardens SSH configuration (disables root login, disables password authentication)
   - Resources: package (1), service (2), template (2), execute (7), file (0)

3. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Configures main nginx.conf file
   - Deploys security-specific nginx configuration
   - Enables and starts nginx service
   - Creates document root directory for test.cluster.local
   - Creates document root directory for ci.cluster.local
   - Creates document root directory for status.cluster.local
   - Deploys index.html file to test.cluster.local document root
   - Deploys index.html file to ci.cluster.local document root
   - Deploys index.html file to status.cluster.local document root
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

4. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL-related packages: openssl, ca-certificates
   - Creates ssl-cert group
   - Creates certificate and private key directories
   - Generates self-signed SSL certificate for test.cluster.local
   - Generates self-signed SSL certificate for ci.cluster.local
   - Generates self-signed SSL certificate for status.cluster.local
   - Resources: package (1), group (1), directory (2), execute (3)

5. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates Nginx site configuration for test.cluster.local
   - Creates Nginx site configuration for ci.cluster.local
   - Creates Nginx site configuration for status.cluster.local
   - Creates symlink from sites-available to sites-enabled for test.cluster.local
   - Creates symlink from sites-available to sites-enabled for ci.cluster.local
   - Creates symlink from sites-available to sites-enabled for status.cluster.local
   - Removes default nginx site
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None specified in the provided analysis
**System package dependencies**: nginx, fail2ban, ufw, openssl, ca-certificates
**Service dependencies**: nginx, fail2ban, ssh

## Credentials

**Detection Summary**: No credentials detected across the cookbook files.

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The SSL certificates are generated during the deployment process and don't require pre-existing secrets.

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
cat /etc/nginx/conf.d/security.conf | grep -E 'server_tokens|limit_req_zone|ssl_protocols'

# Site configuration - test.cluster.local
cat /etc/nginx/sites-available/test.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/test.cluster.local
curl -I -k https://test.cluster.local
curl -I http://test.cluster.local  # Should redirect to HTTPS
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep Subject

# Site configuration - ci.cluster.local
cat /etc/nginx/sites-available/ci.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/ci.cluster.local
curl -I -k https://ci.cluster.local
curl -I http://ci.cluster.local  # Should redirect to HTTPS
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep Subject

# Site configuration - status.cluster.local
cat /etc/nginx/sites-available/status.cluster.local | grep -E 'server_name|root|ssl_certificate'
ls -la /etc/nginx/sites-enabled/status.cluster.local
curl -I -k https://status.cluster.local
curl -I http://status.cluster.local  # Should redirect to HTTPS
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep Subject

# SSL certificate verification
ls -la /etc/ssl/certs/test.cluster.local.crt
ls -la /etc/ssl/private/test.cluster.local.key
ls -la /etc/ssl/certs/ci.cluster.local.crt
ls -la /etc/ssl/private/ci.cluster.local.key
ls -la /etc/ssl/certs/status.cluster.local.crt
ls -la /etc/ssl/private/status.cluster.local.key

# Security configuration
cat /etc/fail2ban/jail.local | grep -E 'enabled|bantime|maxretry'
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth

# Firewall status
ufw status verbose
ufw status numbered

# SSH hardening verification
grep -E "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config

# Sysctl security settings
sysctl -a | grep -E "rp_filter|accept_redirects|send_redirects|accept_source_route|log_martians|icmp_echo_ignore"

# Document root verification
ls -la /opt/server/test/
ls -la /opt/server/ci/
ls -la /opt/server/status/

# Network listening
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443

# Logs
tail -n 20 /var/log/nginx/access.log
tail -n 20 /var/log/nginx/error.log
tail -n 20 /var/log/nginx/test.cluster.local_access.log
tail -n 20 /var/log/nginx/test.cluster.local_error.log
tail -n 20 /var/log/nginx/ci.cluster.local_access.log
tail -n 20 /var/log/nginx/ci.cluster.local_error.log
tail -n 20 /var/log/nginx/status.cluster.local_access.log
tail -n 20 /var/log/nginx/status.cluster.local_error.log
```