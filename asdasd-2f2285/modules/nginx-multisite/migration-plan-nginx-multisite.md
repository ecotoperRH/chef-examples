---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This cookbook installs and configures Nginx with multiple virtual hosts (3 sites), each with SSL enabled. It also sets up security measures including fail2ban, UFW firewall, and system hardening. The three configured sites are test.cluster.local, ci.cluster.local, and status.cluster.local.

## Service Type and Instances

**Service Type**: Web Server

**Configured Instances**:

- **test.cluster.local**: Main test environment website
  - Location/Path: /opt/server/test
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, serves static content

- **ci.cluster.local**: Continuous integration environment website
  - Location/Path: /opt/server/ci
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, serves static content

- **status.cluster.local**: Status monitoring website
  - Location/Path: /opt/server/status
  - Port/Socket: 80 (redirect to 443), 443 (SSL)
  - Key Config: SSL enabled, serves static content

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
   - Deploys system security settings via sysctl
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
   - Configures SSH security:
     - Disables root login if node['security']['ssh']['disable_root'] is true
     - Disables password authentication if node['security']['ssh']['password_auth'] is false
   - Resources: package (1), service (1), template (2), execute (8), service (1)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
   - Deploys security configuration for nginx
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
   - Enables and starts nginx service
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
   - Creates certificate and private key directories:
     - /etc/ssl/certs (certificate_path)
     - /etc/ssl/private (private_key_path)
   - Generates self-signed SSL certificate for test.cluster.local
   - Generates self-signed SSL certificate for ci.cluster.local
   - Generates self-signed SSL certificate for status.cluster.local
   - Sets appropriate permissions on key files
   - Resources: package (1), group (1), directory (2), execute (3)

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Creates nginx site configuration for test.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/test.cluster.local
   - Creates nginx site configuration for ci.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/ci.cluster.local
   - Creates nginx site configuration for status.cluster.local
     - Template: site.conf.erb → /etc/nginx/sites-available/status.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for test.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for ci.cluster.local
   - Creates symbolic link from sites-available to sites-enabled for status.cluster.local
   - Removes default nginx site
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None specified in the provided files
**System package dependencies**: nginx, fail2ban, ufw, openssl, ca-certificates
**Service dependencies**: nginx, fail2ban, ssh

## Credentials

**Detection Summary**: No credentials detected across the files

**Source**:
  - **Provider**: None detected
  - **URL**: N/A
  - **Path**: N/A

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive.

## Checks for the Migration

**Files to verify**:
- /etc/nginx/nginx.conf
- /etc/nginx/conf.d/security.conf
- /etc/fail2ban/jail.local
- /etc/sysctl.d/99-security.conf
- /etc/ssh/sshd_config
- /etc/nginx/sites-available/test.cluster.local
- /etc/nginx/sites-available/ci.cluster.local
- /etc/nginx/sites-available/status.cluster.local
- /etc/nginx/sites-enabled/test.cluster.local
- /etc/nginx/sites-enabled/ci.cluster.local
- /etc/nginx/sites-enabled/status.cluster.local
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
- Unix sockets: /run/nginx.pid
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- fail2ban.jail.local.erb → /etc/fail2ban/jail.local (1 time)
- nginx.conf.erb → /etc/nginx/nginx.conf (1 time)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 time)
- sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf (1 time)
- site.conf.erb → /etc/nginx/sites-available/[site_name] (3 times, one for each site)

## Pre-flight checks:

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
ps aux | grep nginx

# Configuration validation
nginx -t
nginx -T | grep -E 'server_name|listen'

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
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep -E 'Subject:|Not After'
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep -E 'Subject:|Not After'
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep -E 'Subject:|Not After'

# Security configuration
cat /etc/fail2ban/jail.local | grep -E 'enabled|bantime|maxretry'
ufw status verbose
sysctl -a | grep -E 'rp_filter|accept_redirects|send_redirects|accept_source_route|log_martians|icmp_echo_ignore'

# SSH security settings
grep -E 'PermitRootLogin|PasswordAuthentication' /etc/ssh/sshd_config

# File permissions
ls -la /etc/ssl/private/*.key
ls -la /etc/ssl/certs/*.crt
ls -la /opt/server/*/index.html

# Logs
tail -n 50 /var/log/nginx/access.log
tail -n 50 /var/log/nginx/error.log
tail -n 50 /var/log/nginx/test.cluster.local_access.log
tail -n 50 /var/log/nginx/ci.cluster.local_access.log
tail -n 50 /var/log/nginx/status.cluster.local_access.log
tail -n 50 /var/log/fail2ban.log

# Network listening
netstat -tulpn | grep -E ':80|:443'
ss -tlnp | grep nginx
lsof -i :80
lsof -i :443
```