---
source-path: cookbooks/nginx-multisite
---

# Migration Plan: nginx-multisite

**TLDR**: This is a web server cookbook that configures Nginx with 3 SSL-enabled virtual hosts (test.cluster.local, ci.cluster.local, status.cluster.local), each serving static HTML content from separate document roots. It includes comprehensive security hardening with UFW firewall, Fail2Ban intrusion detection, SSH hardening, and kernel security parameters. All sites use self-signed SSL certificates and HTTP-to-HTTPS redirects.

## Service Type and Instances

**Service Type**: Web Server (Nginx with SSL/TLS)

**Configured Instances**:

- **test.cluster.local**: Test environment virtual host
  - Location/Path: `/opt/server/test`
  - Port/Socket: 80 (HTTP redirect), 443 (HTTPS)
  - Key Config: SSL enabled, serves index.html from files/default/test/index.html, HTTP redirects to HTTPS
  - SSL Certificate: `/etc/ssl/certs/test.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/test.cluster.local.key`

- **ci.cluster.local**: CI/CD dashboard virtual host
  - Location/Path: `/opt/server/ci`
  - Port/Socket: 80 (HTTP redirect), 443 (HTTPS)
  - Key Config: SSL enabled, serves index.html from files/default/ci/index.html, HTTP redirects to HTTPS
  - SSL Certificate: `/etc/ssl/certs/ci.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/ci.cluster.local.key`

- **status.cluster.local**: System status monitoring virtual host
  - Location/Path: `/opt/server/status`
  - Port/Socket: 80 (HTTP redirect), 443 (HTTPS)
  - Key Config: SSL enabled, serves index.html from files/default/status/index.html, HTTP redirects to HTTPS
  - SSL Certificate: `/etc/ssl/certs/status.cluster.local.crt`
  - SSL Private Key: `/etc/ssl/private/status.cluster.local.key`

## File Structure

```
cookbooks/nginx-multisite/
├── recipes/
│   ├── default.rb
│   ├── security.rb
│   ├── nginx.rb
│   ├── ssl.rb
│   └── sites.rb
├── templates/
│   └── default/
│       ├── nginx.conf.erb
│       ├── security.conf.erb
│       ├── site.conf.erb
│       ├── fail2ban.jail.local.erb
│       └── sysctl-security.conf.erb
├── attributes/
│   └── default.rb
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
   - Deploys fail2ban configuration template to /etc/fail2ban/jail.local
     - Template: fail2ban.jail.local.erb → /etc/fail2ban/jail.local
     - Configures 4 jails: sshd (bantime 3600s, maxretry 3), nginx-http-auth (bantime 3600s, maxretry 3), nginx-limit-req (bantime 3600s, maxretry 10), nginx-botsearch (bantime 3600s, maxretry 2)
   - Configures UFW firewall with commands:
     - Sets default deny policy
     - Allows SSH (port 22)
     - Allows HTTP (port 80)
     - Allows HTTPS (port 443)
     - Enables UFW
   - Deploys sysctl security configuration template to /etc/sysctl.d/99-security.conf
     - Template: sysctl-security.conf.erb → /etc/sysctl.d/99-security.conf
     - Configures kernel parameters: IP spoofing protection, ICMP redirect blocking, source routing disable, Martian logging, ICMP ping ignore, IPv6 disable, TCP SYN flood protection
   - Conditionally disables SSH root login (if node['security']['ssh']['disable_root'] = true)
     - Modifies /etc/ssh/sshd_config: PermitRootLogin no
   - Conditionally disables SSH password authentication (if node['security']['ssh']['password_auth'] = false)
     - Modifies /etc/ssh/sshd_config: PasswordAuthentication no
   - Reloads sysctl configuration
   - Restarts SSH service if SSH config changed
   - Resources: package (2), service (2), template (2), execute (7)

2. **nginx** (`cookbooks/nginx-multisite/recipes/nginx.rb`):
   - Installs nginx package
   - Deploys main nginx configuration template to /etc/nginx/nginx.conf
     - Template: nginx.conf.erb → /etc/nginx/nginx.conf
     - Configures: user www-data, worker_processes auto, worker_connections 768, gzip compression, includes sites-enabled
   - Deploys nginx security configuration template to /etc/nginx/conf.d/security.conf
     - Template: security.conf.erb → /etc/nginx/conf.d/security.conf
     - Configures: server_tokens off, rate limiting zones (login 10r/m, api 30r/m), buffer size limits, timeout settings, SSL session cache/timeout, TLS 1.2/1.3 protocols, strong ciphers
   - Enables and starts nginx service
   - Creates document root directories and deploys index.html files:
     - **test.cluster.local**: Creates /opt/server/test with owner www-data, group www-data, mode 0755; deploys files/default/test/index.html → /opt/server/test/index.html
     - **ci.cluster.local**: Creates /opt/server/ci with owner www-data, group www-data, mode 0755; deploys files/default/ci/index.html → /opt/server/ci/index.html
     - **status.cluster.local**: Creates /opt/server/status with owner www-data, group www-data, mode 0755; deploys files/default/status/index.html → /opt/server/status/index.html
   - Resources: package (1), template (2), service (1), directory (3), cookbook_file (3)

3. **ssl** (`cookbooks/nginx-multisite/recipes/ssl.rb`):
   - Installs SSL packages: openssl, ca-certificates
   - Creates ssl-cert system group
   - Creates SSL certificate directory /etc/ssl/certs with owner root, group root, mode 0755
   - Creates SSL private key directory /etc/ssl/private with owner root, group ssl-cert, mode 0710
   - Generates self-signed SSL certificates for each site:
     - **test.cluster.local**: Generates /etc/ssl/certs/test.cluster.local.crt and /etc/ssl/private/test.cluster.local.key using openssl req -x509 command; certificate validity 365 days, RSA 2048-bit, subject /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=test.cluster.local/emailAddress=admin@example.com; sets private key permissions 640, owner root, group ssl-cert; only generates if certificate and key don't already exist
     - **ci.cluster.local**: Generates /etc/ssl/certs/ci.cluster.local.crt and /etc/ssl/private/ci.cluster.local.key using openssl req -x509 command; certificate validity 365 days, RSA 2048-bit, subject /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=ci.cluster.local/emailAddress=admin@example.com; sets private key permissions 640, owner root, group ssl-cert; only generates if certificate and key don't already exist
     - **status.cluster.local**: Generates /etc/ssl/certs/status.cluster.local.crt and /etc/ssl/private/status.cluster.local.key using openssl req -x509 command; certificate validity 365 days, RSA 2048-bit, subject /C=US/ST=Example/L=Example/O=Example Org/OU=IT/CN=status.cluster.local/emailAddress=admin@example.com; sets private key permissions 640, owner root, group ssl-cert; only generates if certificate and key don't already exist
   - Resources: package (2), group (1), directory (2), execute (3)

4. **sites** (`cookbooks/nginx-multisite/recipes/sites.rb`):
   - Deploys site-specific nginx configurations:
     - **test.cluster.local**: Deploys site.conf.erb template to /etc/nginx/sites-available/test.cluster.local; configures HTTP listener on port 80 with redirect to HTTPS, HTTPS listener on port 443 with SSL/TLS configuration, server name test.cluster.local, document root /opt/server/test, SSL certificate /etc/ssl/certs/test.cluster.local.crt, SSL private key /etc/ssl/private/test.cluster.local.key, TLS protocols TLSv1.2 and TLSv1.3, strong cipher suite, HSTS header max-age=31536000 includeSubDomains, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip compression enabled, access log /var/log/nginx/test.cluster.local_access.log, error log /var/log/nginx/test.cluster.local_error.log; creates symbolic link from /etc/nginx/sites-enabled/test.cluster.local to /etc/nginx/sites-available/test.cluster.local
     - **ci.cluster.local**: Deploys site.conf.erb template to /etc/nginx/sites-available/ci.cluster.local; configures HTTP listener on port 80 with redirect to HTTPS, HTTPS listener on port 443 with SSL/TLS configuration, server name ci.cluster.local, document root /opt/server/ci, SSL certificate /etc/ssl/certs/ci.cluster.local.crt, SSL private key /etc/ssl/private/ci.cluster.local.key, TLS protocols TLSv1.2 and TLSv1.3, strong cipher suite, HSTS header max-age=31536000 includeSubDomains, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip compression enabled, access log /var/log/nginx/ci.cluster.local_access.log, error log /var/log/nginx/ci.cluster.local_error.log; creates symbolic link from /etc/nginx/sites-enabled/ci.cluster.local to /etc/nginx/sites-available/ci.cluster.local
     - **status.cluster.local**: Deploys site.conf.erb template to /etc/nginx/sites-available/status.cluster.local; configures HTTP listener on port 80 with redirect to HTTPS, HTTPS listener on port 443 with SSL/TLS configuration, server name status.cluster.local, document root /opt/server/status, SSL certificate /etc/ssl/certs/status.cluster.local.crt, SSL private key /etc/ssl/private/status.cluster.local.key, TLS protocols TLSv1.2 and TLSv1.3, strong cipher suite, HSTS header max-age=31536000 includeSubDomains, security headers (X-Frame-Options DENY, X-Content-Type-Options nosniff, X-XSS-Protection, Referrer-Policy, Content-Security-Policy), gzip compression enabled, access log /var/log/nginx/status.cluster.local_access.log, error log /var/log/nginx/status.cluster.local_error.log; creates symbolic link from /etc/nginx/sites-enabled/status.cluster.local to /etc/nginx/sites-available/status.cluster.local
   - Deletes default nginx site configuration: /etc/nginx/sites-enabled/default
   - Reloads nginx service after each site configuration change
   - Resources: template (3), link (3), file (1)

## Dependencies

**External cookbook dependencies**: None (standalone cookbook)

**System package dependencies**: 
- nginx (web server)
- fail2ban (intrusion detection)
- ufw (firewall)
- openssl (SSL/TLS certificate generation)
- ca-certificates (certificate authority certificates)

**Service dependencies**: 
- nginx (managed by systemd)
- fail2ban (managed by systemd)
- ssh (managed by systemd, modified for security hardening)

## Credentials

**Detection Summary**: No credentials or secrets were detected in this cookbook.

**Source**:
  - **Provider**: None detected
  - **URL**: Not applicable
  - **Path**: Not applicable

All configuration values in this cookbook are non-sensitive. SSL certificates are self-signed and generated during provisioning. No passwords, API keys, database credentials, or other sensitive data are stored in the cookbook.

## Checks for the Migration

**Files to verify**:
- Configuration files:
  - /etc/nginx/nginx.conf
  - /etc/nginx/conf.d/security.conf
  - /etc/nginx/sites-available/test.cluster.local
  - /etc/nginx/sites-available/ci.cluster.local
  - /etc/nginx/sites-available/status.cluster.local
  - /etc/nginx/sites-enabled/test.cluster.local (symlink)
  - /etc/nginx/sites-enabled/ci.cluster.local (symlink)
  - /etc/nginx/sites-enabled/status.cluster.local (symlink)
  - /etc/fail2ban/jail.local
  - /etc/sysctl.d/99-security.conf
  - /etc/ssh/sshd_config (modified for security)

- Data directories:
  - /opt/server/test/
  - /opt/server/ci/
  - /opt/server/status/
  - /etc/ssl/certs/
  - /etc/ssl/private/

- Log files:
  - /var/log/nginx/access.log
  - /var/log/nginx/error.log
  - /var/log/nginx/test.cluster.local_access.log
  - /var/log/nginx/test.cluster.local_error.log
  - /var/log/nginx/ci.cluster.local_access.log
  - /var/log/nginx/ci.cluster.local_error.log
  - /var/log/nginx/status.cluster.local_access.log
  - /var/log/nginx/status.cluster.local_error.log
  - /var/log/fail2ban.log
  - /var/log/auth.log

**Service endpoints to check**:
- Ports listening: 
  - 22/tcp (SSH)
  - 80/tcp (HTTP)
  - 443/tcp (HTTPS)
- Unix sockets: None
- Network interfaces: All interfaces (0.0.0.0)

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
ps aux | grep nginx
ps aux | grep fail2ban

# Nginx configuration validation
nginx -t
nginx -T | head -50

# Port listening verification
netstat -tulpn | grep -E ':(22|80|443)'
ss -tlnp | grep -E ':(22|80|443)'
lsof -i :80
lsof -i :443
lsof -i :22

# Virtual host connectivity - test.cluster.local
curl -I http://test.cluster.local/
curl -I https://test.cluster.local/ --insecure
curl -s https://test.cluster.local/ --insecure | grep -o '<title>.*</title>'
curl -s https://test.cluster.local/ --insecure | grep "Test Environment"

# Virtual host connectivity - ci.cluster.local
curl -I http://ci.cluster.local/
curl -I https://ci.cluster.local/ --insecure
curl -s https://ci.cluster.local/ --insecure | grep -o '<title>.*</title>'
curl -s https://ci.cluster.local/ --insecure | grep "CI/CD Dashboard"

# Virtual host connectivity - status.cluster.local
curl -I http://status.cluster.local/
curl -I https://status.cluster.local/ --insecure
curl -s https://status.cluster.local/ --insecure | grep -o '<title>.*</title>'
curl -s https://status.cluster.local/ --insecure | grep "System Status"

# HTTP to HTTPS redirect verification
curl -I -L http://test.cluster.local/ --insecure | grep -E 'HTTP|Location'
curl -I -L http://ci.cluster.local/ --insecure | grep -E 'HTTP|Location'
curl -I -L http://status.cluster.local/ --insecure | grep -E 'HTTP|Location'

# SSL certificate verification
openssl x509 -in /etc/ssl/certs/test.cluster.local.crt -text -noout | grep -E 'Subject:|Issuer:|Not Before|Not After'
openssl x509 -in /etc/ssl/certs/ci.cluster.local.crt -text -noout | grep -E 'Subject:|Issuer:|Not Before|Not After'
openssl x509 -in /etc/ssl/certs/status.cluster.local.crt -text -noout | grep -E 'Subject:|Issuer:|Not Before|Not After'

# SSL certificate file permissions
ls -lh /etc/ssl/certs/test.cluster.local.crt
ls -lh /etc/ssl/certs/ci.cluster.local.crt
ls -lh /etc/ssl/certs/status.cluster.local.crt
ls -lh /etc/ssl/private/test.cluster.local.key
ls -lh /etc/ssl/private/ci.cluster.local.key
ls -lh /etc/ssl/private/status.cluster.local.key

# Document root verification
ls -lah /opt/server/test/
ls -lah /opt/server/ci/
ls -lah /opt/server/status/
cat /opt/server/test/index.html | head -5
cat /opt/server/ci/index.html | head -5
cat /opt/server/status/index.html | head -5

# Firewall status
ufw status
ufw status verbose
iptables -L -n | head -20

# Fail2Ban status
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth
fail2ban-client status nginx-limit-req
fail2ban-client status nginx-botsearch

# SSH security configuration
grep "PermitRootLogin" /etc/ssh/sshd_config
grep "PasswordAuthentication" /etc/ssh/sshd_config
sshd -T | grep -E 'permitrootlogin|passwordauthentication'

# Kernel security parameters
sysctl -a | grep -E 'rp_filter|accept_redirects|accept_source_route|log_martians|icmp_echo_ignore|tcp_syncookies'
cat /etc/sysctl.d/99-security.conf

# Nginx security headers verification
curl -I https://test.cluster.local/ --insecure | grep -E 'X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Strict-Transport-Security'
curl -I https://ci.cluster.local/ --insecure | grep -E 'X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Strict-Transport-Security'
curl -I https://status.cluster.local/ --insecure | grep -E 'X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Strict-Transport-Security'

# Nginx access logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/test.cluster.local_access.log
tail -f /var/log/nginx/ci.cluster.local_access.log
tail -f /var/log/nginx/status.cluster.local_access.log

# Nginx error logs
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/test.cluster.local_error.log
tail -f /var/log/nginx/ci.cluster.local_error.log
tail -f /var/log/nginx/status.cluster.local_error.log

# Fail2Ban logs
tail -f /var/log/fail2ban.log
grep "Ban" /var/log/fail2ban.log | tail -20

# System logs
journalctl -u nginx -f
journalctl -u fail2ban -f
journalctl -u ssh -f

# Gzip compression verification
curl -I -H "Accept-Encoding: gzip" https://test.cluster.local/ --insecure | grep -i 'content-encoding'

# Rate limiting configuration
grep -A 5 "limit_req_zone" /etc/nginx/conf.d/security.conf

# Directory ownership and permissions
stat /opt/server/test/
stat /opt/server/ci/
stat /opt/server/status/
stat /etc/ssl/certs/
stat /etc/ssl/private/

# Symlink verification
ls -lh /etc/nginx/sites-enabled/
readlink /etc/nginx/sites-enabled/test.cluster.local
readlink /etc/nginx/sites-enabled/ci.cluster.local
readlink /etc/nginx/sites-enabled/status.cluster.local

# Default site removal verification
ls -lh /etc/nginx/sites-enabled/default 2>&1 | grep -i "no such file"

# Process resource usage
ps aux | grep nginx | grep -v grep
top -p $(pgrep -f 'nginx: master' | head -1) -n 1

# Network connections
netstat -antp | grep nginx
ss -antp | grep nginx
```