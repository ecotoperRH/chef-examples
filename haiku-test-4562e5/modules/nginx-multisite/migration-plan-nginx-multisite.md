---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This is a multi-site Nginx web server cookbook that configures 3 virtual hosts (test.cluster.local, ci.cluster.local, status.cluster.local) with SSL/TLS encryption, security hardening via UFW firewall and Fail2Ban intrusion detection, and kernel-level security tuning. All sites serve static HTML content from separate document roots with HTTPS enforcement and comprehensive security headers.

## Service Type and Instances

**Service Type**: Web Server (Nginx with multi-site hosting and security hardening)

**Configured Instances**:

- **test.cluster.local**: Test environment virtual host
  - Location/Path: `/opt/server/test`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Serves static HTML content, HSTS enabled, security headers configured

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Serves CI/CD dashboard HTML, HSTS enabled, security headers configured

- **status.cluster.local**: System status monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Serves system status page HTML, HSTS enabled, security headers configured

## File Structure

```
cookbooks/nginx-multisite/
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── templates/default/
│   ├── nginx.conf.erb
│   ├── security.conf.erb
│   ├── site.conf.erb
│   ├── fail2ban.jail.local.erb
│   └── sysctl-security.conf.erb
├── attributes/
│   └── default.rb
└── files/default/
    ├── test/index.html
    ├── ci/index.html
    └── status/index.html
```

## Module Explanation

The cookbook performs operations in this order:

1. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs security packages: fail2ban, ufw
   - Enables and starts fail2ban service
   - Deploys fail2ban configuration template to /etc/fail2ban/jail.local
     - Template: fail2ban.jail.local.erb → /etc/fail2ban/jail.local
     - Configures 5 jails: sshd (3 retries, 3600s ban), nginx-http-auth (3 retries, 3600s ban), nginx-limit-req (10 retries, 3600s ban), nginx-botsearch (2 retries, 3600s ban)
     - Default settings: bantime=3600, findtime=600, maxretry=3
   - Configures UFW firewall with conditional checks:
     - Sets default policy to deny all incoming traffic
     - Allows SSH (port 22)
     - Allows HTTP (port 80)
     - Allows HTTPS (port 443)
     - Enables UFW with --force flag
   - Deploys sysctl security configuration template to /etc/sysctl.d/99-security.conf
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
     - Configures kernel parameters: IP spoofing protection (rp_filter=1), ICMP redirect blocking, source routing disabled, Martian logging enabled, ICMP ping ignore, IPv6 disabled, TCP SYN flood protection (syncookies=1, max_syn_backlog=2048)
   - Reloads sysctl configuration via execute resource
   - Conditionally disables SSH root login if node['security']['ssh']['disable_root'] = true
     - Modifies /etc/ssh/sshd_config: PermitRootLogin no
   - Conditionally disables SSH password authentication if node['security']['ssh']['password_auth'] = false
     - Modifies /etc/ssh/sshd_config: PasswordAuthentication no
   - Restarts SSH service if configuration changes detected
   - Resources: package (2), service (2), template (2), execute (7)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration template to /etc/nginx/nginx.conf
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
     - Configures: user=www-data, worker_processes=auto, worker_connections=768, sendfile=on, gzip=on
   - Deploys security configuration template to /etc/nginx/conf.d/security.conf
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
     - Configures: server_tokens=off, rate limiting zones (login 10r/m, api 30r/m), buffer size limits, timeout settings, SSL session cache/timeout, TLS 1.2/1.3 only, strong ciphers
   - Enables and starts nginx service
   - Creates document root directories and deploys static content:
     - **test.cluster.local**: Creates /opt/server/test with owner=www-data, group=www-data, mode=0755; deploys files/default/test/index.html → /opt/server/test/index.html
     - **ci.cluster.local**: Creates /opt/server/ci with owner=www-data, group=www-data, mode=0755; deploys files/default/ci/index.html → /opt/server/ci/index.html
     - **status.cluster.local**: Creates /opt/server/status with owner=www-data, group=www-data, mode=0755; deploys files/default/status/index.html → /opt/server/status/index.html
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL packages: openssl, ca-certificates
   - Creates ssl-cert system group
   - Creates certificate directory /etc/ssl/certs with owner=root, group=root, mode=0755
   - Creates private key directory /etc/ssl/private with owner=root, group=ssl-cert, mode=0710
   - Generates self-signed X.509 certificates for each site (RSA 2048-bit, 365-day validity):
     - **test.cluster.local**: Certificate /etc/ssl/certs/test.cluster.local.crt, Private key /etc/ssl/private/test.cluster.local.key
     - **ci.cluster.local**: Certificate /etc/ssl/certs/ci.cluster.local.crt, Private key /etc/ssl/private/ci.cluster.local.key
     - **status.cluster.local**: Certificate /etc/ssl/certs/status.cluster.local.crt, Private key /etc/ssl/private/status.cluster.local.key
     - Subject for all: /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN={site_name}/emailAddress=admin@example.com
     - Sets private key permissions: mode=640, owner=root, group=ssl-cert
     - Only generates if certificate and key don't already exist (idempotent)
   - Resources: package (2), group (1), directory (2), execute (3)

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Deploys site-specific nginx configuration for each virtual host:
     - **test.cluster.local**: Template site.conf.erb → /etc/nginx/sites-available/test.cluster.local with server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
     - **ci.cluster.local**: Template site.conf.erb → /etc/nginx/sites-available/ci.cluster.local with server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
     - **status.cluster.local**: Template site.conf.erb → /etc/nginx/sites-available/status.cluster.local with server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
   - Each site configuration includes:
     - HTTP listener on port 80 with 301 redirect to HTTPS
     - HTTPS listener on port 443 with HTTP/2 support
     - SSL certificate and key paths
     - TLS 1.2/1.3 only, strong ciphers
     - HSTS header: max-age=31536000, includeSubDomains
     - Security headers: X-Frame-Options=DENY, X-Content-Type-Options=nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy
     - Gzip compression enabled for text/css/javascript/json
     - try_files directive for static file serving
     - Deny access to .ht, .git, .svn files
     - Separate access/error logs per site
   - Creates symbolic links from sites-enabled to sites-available:
     - /etc/nginx/sites-enabled/test.cluster.local → /etc/nginx/sites-available/test.cluster.local
     - /etc/nginx/sites-enabled/ci.cluster.local → /etc/nginx/sites-available/ci.cluster.local
     - /etc/nginx/sites-enabled/status.cluster.local → /etc/nginx/sites-available/status.cluster.local
   - Deletes default nginx site configuration at /etc/nginx/sites-enabled/default
   - All template and link changes trigger nginx reload via notifies directive
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (standalone cookbook)

**System package dependencies**: 
- nginx (web server)
- fail2ban (intrusion detection)
- ufw (firewall)
- openssl (SSL/TLS certificate generation)
- ca-certificates (CA certificate bundle)

**Service dependencies**: 
- systemd services managed: nginx, fail2ban, ssh
- Nginx reload triggered by: template changes, link creation, file deletion

## Credentials

No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive. The cookbook uses self-signed SSL certificates generated at runtime with hardcoded subject information (no private keys or sensitive data embedded in templates or attributes).

## Checks for the Migration

**Files to verify**:
- /etc/nginx/nginx.conf (main configuration)
- /etc/nginx/conf.d/security.conf (security settings)
- /etc/nginx/sites-available/test.cluster.local (test site config)
- /etc/nginx/sites-available/ci.cluster.local (CI site config)
- /etc/nginx/sites-available/status.cluster.local (status site config)
- /etc/nginx/sites-enabled/test.cluster.local (symlink)
- /etc/nginx/sites-enabled/ci.cluster.local (symlink)
- /etc/nginx/sites-enabled/status.cluster.local (symlink)
- /etc/ssl/certs/test.cluster.local.crt (test certificate)
- /etc/ssl/certs/ci.cluster.local.crt (CI certificate)
- /etc/ssl/certs/status.cluster.local.crt (status certificate)
- /etc/ssl/private/test.cluster.local.key (test private key)
- /etc/ssl/private/ci.cluster.local.key (CI private key)
- /etc/ssl/private/status.cluster.local.key (status private key)
- /opt/server/test/index.html (test site content)
- /opt/server/ci/index.html (CI site content)
- /opt/server/status/index.html (status site content)
- /etc/fail2ban/jail.local (fail2ban configuration)
- /etc/sysctl.d/99-security.conf (kernel security parameters)
- /var/log/nginx/access.log (nginx access log)
- /var/log/nginx/error.log (nginx error log)
- /var/log/nginx/test.cluster.local_access.log (test site access log)
- /var/log/nginx/test.cluster.local_error.log (test site error log)
- /var/log/nginx/ci.cluster.local_access.log (CI site access log)
- /var/log/nginx/ci.cluster.local_error.log (CI site error log)
- /var/log/nginx/status.cluster.local_access.log (status site access log)
- /var/log/nginx/status.cluster.local_error.log (status site error log)

**Service endpoints to check**:
- Ports listening: 80 (HTTP), 443 (HTTPS)
- Network interfaces: All interfaces (0.0.0.0)
- Virtual hosts: test.cluster.local, ci.cluster.local, status.cluster.local

**Templates rendered**:
- nginx.conf.erb → /etc/nginx/nginx.conf (1 render)
- security.conf.erb → /etc/nginx/conf.d/security.conf (1 render)
- site.conf.erb → /etc/nginx/sites-available/test.cluster.local (1 render)
- site.conf.erb → /etc/nginx/sites-available/ci.cluster.local (1 render)
- site.conf.erb → /etc/nginx/sites-available/status.cluster.local (1 render)
- fail2ban.jail.local.erb → /etc/fail2ban/jail.local (1 render)
- sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf (1 render)

## Pre-flight checks

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
systemctl status ssh
ps aux | grep nginx | grep -v grep

# Nginx configuration validation
nginx -t
nginx -T | head -50

# Virtual host verification - test.cluster.local
curl -k -I https://test.cluster.local/
curl -k -I http://test.cluster.local/ | grep -i "301\|location"
curl -k https://test.cluster.local/ | grep -i "test environment"
curl -k https://test.cluster.local/ | grep -i "test.cluster.local"

# Virtual host verification - ci.cluster.local
curl -k -I https://ci.cluster.local/
curl -k -I http://ci.cluster.local/ | grep -i "301\|location"
curl -k https://ci.cluster.local/ | grep -i "ci/cd dashboard"
curl -k https://ci.cluster.local/ | grep -i "ci.cluster.local"

# Virtual host verification - status.cluster.local
curl -k -I https://status.cluster.local/
curl -k -I http://status.cluster.local/ | grep -i "301\|location"
curl -k https://status.cluster.local/ | grep -i "system status"
curl -k https://status.cluster.local/ | grep -i "status.cluster.local"

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"

# SSL certificate file permissions
ls -l /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/ci.cluster.local.crt /etc/ssl/certs/status.cluster.local.crt
ls -l /etc/ssl/private/test.cluster.local.key /etc/ssl/private/ci.cluster.local.key /etc/ssl/private/status.cluster.local.key
stat /etc/ssl/private/test.cluster.local.key | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/private/ci.cluster.local.key | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/private/status.cluster.local.key | grep -E "Access:|Uid:|Gid:"

# SSL/TLS protocol verification
openssl s_client -connect test.cluster.local:443 -tls1_2 </dev/null | grep -i "protocol\|cipher"
openssl s_client -connect ci.cluster.local:443 -tls1_2 </dev/null | grep -i "protocol\|cipher"
openssl s_client -connect status.cluster.local:443 -tls1_2 </dev/null | grep -i "protocol\|cipher"

# Security headers verification - test.cluster.local
curl -k -I https://test.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options\|x-xss-protection\|content-security-policy"

# Security headers verification - ci.cluster.local
curl -k -I https://ci.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options\|x-xss-protection\|content-security-policy"

# Security headers verification - status.cluster.local
curl -k -I https://status.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options\|x-xss-protection\|content-security-policy"

# Document root verification
ls -lah /opt/server/test/
ls -lah /opt/server/ci/
ls -lah /opt/server/status/
cat /opt/server/test/index.html | head -5
cat /opt/server/ci/index.html | head -5
cat /opt/server/status/index.html | head -5

# Firewall verification
ufw status
ufw status verbose | grep -E "22/tcp|80/tcp|443/tcp"
iptables -L -n | grep -E "22|80|443"

# Fail2ban verification
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Kernel security parameters verification
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv4.conf.all.log_martians
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.icmp_echo_ignore_broadcasts
sysctl net.ipv6.conf.all.disable_ipv6
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.tcp_max_syn_backlog

# SSH configuration verification
grep "PermitRootLogin" /etc/ssh/sshd_config | grep -v "^#"
grep "PasswordAuthentication" /etc/ssh/sshd_config | grep -v "^#"

# Port listening verification
netstat -tulpn | grep -E "80|443"
ss -tlnp | grep -E "80|443"
lsof -i :80
lsof -i :443

# Nginx logs verification
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_access.log

# Fail2ban logs verification
tail -20 /var/log/fail2ban.log
grep "Ban" /var/log/fail2ban.log | tail -10

# Gzip compression verification
curl -k -I https://test.cluster.local/ | grep -i "content-encoding"

# HTTP to HTTPS redirect verification
curl -I http://test.cluster.local/ 2>&1 | grep -E "301|Location"
curl -I http://ci.cluster.local/ 2>&1 | grep -E "301|Location"
curl -I http://status.cluster.local/ 2>&1 | grep -E "301|Location"

# Nginx worker processes
ps aux | grep "nginx: worker" | wc -l

# Nginx configuration includes
grep -r "include" /etc/nginx/nginx.conf
grep -r "include" /etc/nginx/conf.d/
grep -r "include" /etc/nginx/sites-enabled/

# Symlink verification
ls -l /etc/nginx/sites-enabled/ | grep -E "test.cluster.local|ci.cluster.local|status.cluster.local"

# Default site removal verification
ls -l /etc/nginx/sites-enabled/default 2>&1 | grep -i "no such file"

# Directory permissions
stat /opt/server/test/ | grep -E "Access:|Uid:|Gid:"
stat /opt/server/ci/ | grep -E "Access:|Uid:|Gid:"
stat /opt/server/status/ | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/certs/ | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/private/ | grep -E "Access:|Uid:|Gid:"
```