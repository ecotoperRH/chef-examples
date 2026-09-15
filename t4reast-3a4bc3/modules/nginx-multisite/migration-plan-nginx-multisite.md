---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This is a multi-site Nginx web server cookbook that configures 3 virtual hosts (test.cluster.local, ci.cluster.local, status.cluster.local) with SSL/TLS support, security hardening via fail2ban and UFW firewall, and system-level security configurations. All sites serve static HTML content from dedicated document roots with automatic self-signed certificate generation.

## Service Type and Instances

**Service Type**: Web Server (Nginx with multi-site hosting and security hardening)

**Configured Instances**:

- **test.cluster.local**: Test environment virtual host
  - Location/Path: `/opt/server/test`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Document root `/opt/server/test`, serves index.html, HTTP/2 support, HSTS enabled

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Document root `/opt/server/ci`, serves index.html, HTTP/2 support, HSTS enabled

- **status.cluster.local**: System status monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port: 80 (HTTP, redirects to HTTPS), 443 (HTTPS)
  - SSL: Enabled with self-signed certificate
  - Key Config: Document root `/opt/server/status`, serves index.html, HTTP/2 support, HSTS enabled

## File Structure

```
cookbooks/nginx-multisite/
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── attributes/
│   └── default.rb
├── templates/
│   └── default/
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       ├── fail2ban.jail.local.erb
│       └── sysctl-security.conf.erb
└── files/
    └── default/
        ├── test/
        │   └── index.html
        ├── ci/
        │   └── index.html
        └── status/
            └── index.html
```

## Module Explanation

The cookbook performs operations in this order:

1. **security** (`cookbooks/nginx-multisite/recipes/security.rb`):
   - Installs security packages: fail2ban, ufw
   - Enables and starts fail2ban service
   - Deploys fail2ban configuration template to `/etc/fail2ban/jail.local`
     - Template: fail2ban.jail.local.erb → `/etc/fail2ban/jail.local`
     - Configures jails: sshd, nginx-http-auth, nginx-limit-req, nginx-botsearch
     - Ban time: 3600 seconds, max retries: 3-10 depending on jail
   - Configures UFW firewall with conditional execution:
     - Sets default policy to deny all incoming traffic
     - Allows SSH (port 22)
     - Allows HTTP (port 80)
     - Allows HTTPS (port 443)
     - Enables UFW with force flag
   - Deploys sysctl security configuration to `/etc/sysctl.d/99-security.conf`
     - Template: sysctl-security.conf.erb → `/etc/sysctl.d/99-security.conf`
     - Configures: IP spoofing protection, ICMP redirect blocking, source routing disable, TCP SYN flood protection, IPv6 disable
     - Reloads sysctl configuration
   - Conditionally modifies SSH configuration (if `node['security']['ssh']['disable_root']` = true):
     - Disables root login via sed command
     - Notifies SSH service restart
   - Conditionally modifies SSH configuration (if `node['security']['ssh']['password_auth']` = false):
     - Disables password authentication via sed command
     - Notifies SSH service restart

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration to `/etc/nginx/nginx.conf`
     - Template: nginx.conf.erb → `/etc/nginx/nginx.conf`
     - Configures: worker processes (auto), worker connections (768), gzip compression, logging
   - Deploys security configuration to `/etc/nginx/conf.d/security.conf`
     - Template: security.conf.erb → `/etc/nginx/conf.d/security.conf`
     - Configures: server tokens off, rate limiting zones, buffer overflow protection, timeout settings, SSL settings
   - Enables and starts nginx service
   - Creates document root directory for test.cluster.local with owner www-data, group www-data, mode 0755
   - Deploys index.html static file for test.cluster.local from `cookbooks/nginx-multisite/files/default/test/index.html` to `/opt/server/test/index.html`
   - Creates document root directory for ci.cluster.local with owner www-data, group www-data, mode 0755
   - Deploys index.html static file for ci.cluster.local from `cookbooks/nginx-multisite/files/default/ci/index.html` to `/opt/server/ci/index.html`
   - Creates document root directory for status.cluster.local with owner www-data, group www-data, mode 0755
   - Deploys index.html static file for status.cluster.local from `cookbooks/nginx-multisite/files/default/status/index.html` to `/opt/server/status/index.html`

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL packages: openssl, ca-certificates
   - Creates ssl-cert system group
   - Creates certificate directory `/etc/ssl/certs` with owner root, group root, mode 0755
   - Creates private key directory `/etc/ssl/private` with owner root, group ssl-cert, mode 0710
   - Generates self-signed X.509 certificate for test.cluster.local using openssl command
     - Certificate path: `/etc/ssl/certs/test.cluster.local.crt`
     - Private key path: `/etc/ssl/private/test.cluster.local.key`
     - Certificate details: RSA 2048-bit, 365-day validity, subject CN=test.cluster.local
     - Sets private key permissions: mode 0640, owner root, group ssl-cert
     - Conditional execution: only runs if certificate and key files don't already exist
   - Generates self-signed X.509 certificate for ci.cluster.local using openssl command
     - Certificate path: `/etc/ssl/certs/ci.cluster.local.crt`
     - Private key path: `/etc/ssl/private/ci.cluster.local.key`
     - Certificate details: RSA 2048-bit, 365-day validity, subject CN=ci.cluster.local
     - Sets private key permissions: mode 0640, owner root, group ssl-cert
     - Conditional execution: only runs if certificate and key files don't already exist
   - Generates self-signed X.509 certificate for status.cluster.local using openssl command
     - Certificate path: `/etc/ssl/certs/status.cluster.local.crt`
     - Private key path: `/etc/ssl/private/status.cluster.local.key`
     - Certificate details: RSA 2048-bit, 365-day validity, subject CN=status.cluster.local
     - Sets private key permissions: mode 0640, owner root, group ssl-cert
     - Conditional execution: only runs if certificate and key files don't already exist

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Deploys site-specific nginx configuration for test.cluster.local to `/etc/nginx/sites-available/test.cluster.local`
     - Template: site.conf.erb → `/etc/nginx/sites-available/test.cluster.local`
     - Template variables: server_name=test.cluster.local, document_root=/opt/server/test, ssl_enabled=true, cert_file=/etc/ssl/certs/test.cluster.local.crt, key_file=/etc/ssl/private/test.cluster.local.key
     - Configuration includes: HTTP to HTTPS redirect, SSL certificate and key paths, SSL protocols TLSv1.2/TLSv1.3, HSTS header max-age=31536000, security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP), gzip compression, per-site access and error logs
   - Creates symbolic link from `/etc/nginx/sites-enabled/test.cluster.local` to `/etc/nginx/sites-available/test.cluster.local`
   - Deploys site-specific nginx configuration for ci.cluster.local to `/etc/nginx/sites-available/ci.cluster.local`
     - Template: site.conf.erb → `/etc/nginx/sites-available/ci.cluster.local`
     - Template variables: server_name=ci.cluster.local, document_root=/opt/server/ci, ssl_enabled=true, cert_file=/etc/ssl/certs/ci.cluster.local.crt, key_file=/etc/ssl/private/ci.cluster.local.key
     - Configuration includes: HTTP to HTTPS redirect, SSL certificate and key paths, SSL protocols TLSv1.2/TLSv1.3, HSTS header max-age=31536000, security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP), gzip compression, per-site access and error logs
   - Creates symbolic link from `/etc/nginx/sites-enabled/ci.cluster.local` to `/etc/nginx/sites-available/ci.cluster.local`
   - Deploys site-specific nginx configuration for status.cluster.local to `/etc/nginx/sites-available/status.cluster.local`
     - Template: site.conf.erb → `/etc/nginx/sites-available/status.cluster.local`
     - Template variables: server_name=status.cluster.local, document_root=/opt/server/status, ssl_enabled=true, cert_file=/etc/ssl/certs/status.cluster.local.crt, key_file=/etc/ssl/private/status.cluster.local.key
     - Configuration includes: HTTP to HTTPS redirect, SSL certificate and key paths, SSL protocols TLSv1.2/TLSv1.3, HSTS header max-age=31536000, security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP), gzip compression, per-site access and error logs
   - Creates symbolic link from `/etc/nginx/sites-enabled/status.cluster.local` to `/etc/nginx/sites-available/status.cluster.local`
   - Deletes default nginx site configuration at `/etc/nginx/sites-enabled/default`

## Dependencies

**External cookbook dependencies**: None detected

**System package dependencies**: 
- nginx (web server)
- fail2ban (intrusion prevention)
- ufw (firewall)
- openssl (SSL/TLS certificate generation)
- ca-certificates (certificate authority certificates)

**Service dependencies**: 
- nginx (main web server service)
- fail2ban (security service)
- ssh (modified for security hardening)

## Credentials

**Detection Summary**: No credentials or secrets were detected in this cookbook. All configuration values appear to be non-sensitive.

The cookbook uses:
- Self-signed SSL certificates generated at runtime (not pre-existing secrets)
- Static security configuration values (sysctl, firewall rules, fail2ban settings)
- No data bags, encrypted data bags, or vault references
- No environment variables containing secrets
- No hardcoded passwords or API keys

## Checks for the Migration

**Files to verify**:
- `/etc/nginx/nginx.conf` - Main nginx configuration
- `/etc/nginx/conf.d/security.conf` - Security configuration
- `/etc/nginx/sites-available/test.cluster.local` - Test site configuration
- `/etc/nginx/sites-available/ci.cluster.local` - CI site configuration
- `/etc/nginx/sites-available/status.cluster.local` - Status site configuration
- `/etc/nginx/sites-enabled/test.cluster.local` - Test site symlink
- `/etc/nginx/sites-enabled/ci.cluster.local` - CI site symlink
- `/etc/nginx/sites-enabled/status.cluster.local` - Status site symlink
- `/etc/nginx/sites-enabled/default` - Should be deleted
- `/opt/server/test/index.html` - Test site content
- `/opt/server/ci/index.html` - CI site content
- `/opt/server/status/index.html` - Status site content
- `/etc/ssl/certs/test.cluster.local.crt` - Test site certificate
- `/etc/ssl/certs/ci.cluster.local.crt` - CI site certificate
- `/etc/ssl/certs/status.cluster.local.crt` - Status site certificate
- `/etc/ssl/private/test.cluster.local.key` - Test site private key
- `/etc/ssl/private/ci.cluster.local.key` - CI site private key
- `/etc/ssl/private/status.cluster.local.key` - Status site private key
- `/etc/fail2ban/jail.local` - Fail2ban configuration
- `/etc/sysctl.d/99-security.conf` - Sysctl security settings
- `/var/log/nginx/access.log` - Nginx access log
- `/var/log/nginx/error.log` - Nginx error log
- `/var/log/nginx/test.cluster.local_access.log` - Test site access log
- `/var/log/nginx/test.cluster.local_error.log` - Test site error log
- `/var/log/nginx/ci.cluster.local_access.log` - CI site access log
- `/var/log/nginx/ci.cluster.local_error.log` - CI site error log
- `/var/log/nginx/status.cluster.local_access.log` - Status site access log
- `/var/log/nginx/status.cluster.local_error.log` - Status site error log

**Service endpoints to check**:
- Ports listening: 80 (HTTP), 443 (HTTPS)
- Network interfaces: All interfaces (0.0.0.0)

**Templates rendered**:
- nginx.conf.erb → `/etc/nginx/nginx.conf` (rendered once)
- security.conf.erb → `/etc/nginx/conf.d/security.conf` (rendered once)
- site.conf.erb → `/etc/nginx/sites-available/test.cluster.local` (rendered once)
- site.conf.erb → `/etc/nginx/sites-available/ci.cluster.local` (rendered once)
- site.conf.erb → `/etc/nginx/sites-available/status.cluster.local` (rendered once)
- fail2ban.jail.local.erb → `/etc/fail2ban/jail.local` (rendered once)
- sysctl-security.conf.erb → `/etc/sysctl.d/99-security.conf` (rendered once)

## Pre-flight checks

```bash
# Service status
systemctl status nginx
systemctl status fail2ban
ps aux | grep nginx
ps aux | grep fail2ban

# Nginx configuration validation
nginx -t
nginx -T | head -50

# Port listening verification
netstat -tulpn | grep -E ':(80|443)'
ss -tlnp | grep -E ':(80|443)'
lsof -i :80
lsof -i :443

# Test site (test.cluster.local) - HTTPS
curl -k -I https://test.cluster.local/
curl -k -s https://test.cluster.local/ | grep -i "Test Environment"
curl -k -s https://test.cluster.local/ | grep "test.cluster.local"

# CI site (ci.cluster.local) - HTTPS
curl -k -I https://ci.cluster.local/
curl -k -s https://ci.cluster.local/ | grep -i "CI/CD Dashboard"
curl -k -s https://ci.cluster.local/ | grep "ci.cluster.local"

# Status site (status.cluster.local) - HTTPS
curl -k -I https://status.cluster.local/
curl -k -s https://status.cluster.local/ | grep -i "System Status"
curl -k -s https://status.cluster.local/ | grep "status.cluster.local"

# HTTP to HTTPS redirect verification
curl -I http://test.cluster.local/ | grep -i "301\|location"
curl -I http://ci.cluster.local/ | grep -i "301\|location"
curl -I http://status.cluster.local/ | grep -i "301\|location"

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep -E "Subject:|CN=|Not Before|Not After"

# SSL certificate file permissions
ls -l /etc/ssl/certs/test.cluster.local.crt /etc/ssl/certs/ci.cluster.local.crt /etc/ssl/certs/status.cluster.local.crt
ls -l /etc/ssl/private/test.cluster.local.key /etc/ssl/private/ci.cluster.local.key /etc/ssl/private/status.cluster.local.key

# Document root verification
ls -la /opt/server/test/
ls -la /opt/server/ci/
ls -la /opt/server/status/
cat /opt/server/test/index.html | head -5
cat /opt/server/ci/index.html | head -5
cat /opt/server/status/index.html | head -5

# Firewall status
ufw status
ufw status verbose | grep -E "22|80|443"

# Fail2ban status
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# Sysctl security settings verification
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv4.icmp_echo_ignore_all
sysctl net.ipv4.tcp_syncookies
cat /etc/sysctl.d/99-security.conf | grep -v "^#" | grep -v "^$"

# SSH configuration verification
grep "^PermitRootLogin" /etc/ssh/sshd_config
grep "^PasswordAuthentication" /etc/ssh/sshd_config

# Nginx configuration files
cat /etc/nginx/nginx.conf | grep -E "worker_processes|worker_connections|sendfile|gzip"
cat /etc/nginx/conf.d/security.conf | grep -E "server_tokens|ssl_protocols|ssl_ciphers"
cat /etc/nginx/sites-available/test.cluster.local | grep -E "server_name|document_root|ssl_certificate|ssl_protocols"
cat /etc/nginx/sites-available/ci.cluster.local | grep -E "server_name|document_root|ssl_certificate|ssl_protocols"
cat /etc/nginx/sites-available/status.cluster.local | grep -E "server_name|document_root|ssl_certificate|ssl_protocols"

# Symlink verification
ls -l /etc/nginx/sites-enabled/test.cluster.local
ls -l /etc/nginx/sites-enabled/ci.cluster.local
ls -l /etc/nginx/sites-enabled/status.cluster.local
test ! -f /etc/nginx/sites-enabled/default && echo "Default site removed" || echo "Default site still exists"

# Nginx logs
tail -20 /var/log/nginx/access.log
tail -20 /var/log/nginx/error.log
tail -20 /var/log/nginx/test.cluster.local_access.log
tail -20 /var/log/nginx/ci.cluster.local_access.log
tail -20 /var/log/nginx/status.cluster.local_access.log

# Fail2ban logs
tail -20 /var/log/fail2ban.log

# Security headers verification
curl -k -I https://test.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options"
curl -k -I https://ci.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options"
curl -k -I https://status.cluster.local/ | grep -i "strict-transport-security\|x-frame-options\|x-content-type-options"

# Gzip compression verification
curl -k -I https://test.cluster.local/ | grep -i "content-encoding"

# Directory ownership and permissions
stat /opt/server/test/ | grep -E "Access:|Uid:|Gid:"
stat /opt/server/ci/ | grep -E "Access:|Uid:|Gid:"
stat /opt/server/status/ | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/certs/ | grep -E "Access:|Uid:|Gid:"
stat /etc/ssl/private/ | grep -E "Access:|Uid:|Gid:"

# Group membership verification
getent group ssl-cert
getent group www-data

# Process verification
ps aux | grep "[n]ginx" | wc -l
ps aux | grep "[f]ail2ban" | wc -l

# Network connections
netstat -tulpn | grep nginx
ss -tlnp | grep nginx
```