---
source-path: roles/nginx
---

# Migration Plan: nginx

**TLDR**: This role installs and configures Nginx web server on RedHat and Debian-based systems. It needs modernization to use FQCN module names, proper boolean values, quoted octal modes, loop syntax updates, and Python 3 compatibility in templates. The role also needs proper file permissions for security and updated SSL protocols.

## Service Type and Configuration

**Service Type**: Web Server

**Key Operations**:
- Installs Nginx packages on RedHat and Debian-based systems
- Creates directory structure for site configurations
- Configures Nginx with main configuration file and default site
- Sets up custom site configurations based on variables
- Manages the Nginx service (start, restart, reload)
- Configures SELinux support on RedHat systems

## File Structure

**Task Files:**
- roles/nginx/tasks/main.yml

**Handler Files:**
- roles/nginx/handlers/main.yml

**Variable Files:**
- roles/nginx/defaults/main.yml
- roles/nginx/vars/main.yml

**Meta:**
- roles/nginx/meta/main.yml

**Templates:**
- roles/nginx/templates/default.conf.j2
- roles/nginx/templates/default.j2
- roles/nginx/templates/nginx.conf.j2
- roles/nginx/templates/site.j2

**Static Files:**
- roles/nginx/files/epel.repo

## Module Explanation

The role performs operations in this order:

1. **Install and Configure Nginx** (`roles/nginx/tasks/main.yml`):
   - Installs SELinux Python module on RedHat systems
   - Copies EPEL repository configuration for RedHat systems
   - Installs Nginx packages on RedHat systems using a variable list
   - Installs Nginx packages on Debian systems using a variable list
   - Creates directory structure for site configurations
   - Configures Nginx with main configuration file
   - Sets up default site configuration
   - Creates and enables custom site configurations
   - Ensures Nginx service is started and enabled

## Modernization Mapping

| Legacy Pattern | Modern Equivalent | Files Affected | Notes |
|---|---|---|---|
| `yum:` | `ansible.builtin.yum:` | tasks/main.yml | FQCN |
| `copy:` | `ansible.builtin.copy:` | tasks/main.yml | FQCN |
| `apt:` | `ansible.builtin.apt:` | tasks/main.yml | FQCN |
| `file:` | `ansible.builtin.file:` | tasks/main.yml | FQCN |
| `template:` | `ansible.builtin.template:` | tasks/main.yml | FQCN |
| `service:` | `ansible.builtin.service:` | tasks/main.yml, handlers/main.yml | FQCN |
| `with_items: redhat_pkg` | `loop: "{{ redhat_pkg }}"` | tasks/main.yml | Loop modernization |
| `with_items: ubuntu_pkg` | `loop: "{{ ubuntu_pkg }}"` | tasks/main.yml | Loop modernization |
| `with_items: nginx_sites` | `loop: "{{ nginx_sites }}"` | tasks/main.yml | Loop modernization |
| `mode=0755` | `mode: '0755'` | tasks/main.yml | Quoted octal mode |
| `enabled=yes` | `enabled: true` | tasks/main.yml | Boolean modernization |
| `update_cache=yes` | `update_cache: true` | tasks/main.yml | Boolean modernization |
| `ansible_os_family` | `ansible_facts['os_family']` | tasks/main.yml, templates/nginx.conf.j2 | Fact access |
| `ansible_processor_count` | `ansible_facts['processor_count']` | templates/nginx.conf.j2 | Fact access |
| `nginx_http_params.iteritems()` | `nginx_http_params.items()` | templates/nginx.conf.j2 | Python 3 compatibility |
| `item.server.iteritems()` | `item.server.items()` | templates/site.j2 | Python 3 compatibility |
| `v.iteritems()` | `v.items()` | templates/site.j2 | Python 3 compatibility |
| `k.find('location')` | `'location' in k` | templates/site.j2 | Python 3 string operation |
| Inline key=value syntax | YAML dictionary format | tasks/main.yml, handlers/main.yml | Syntax modernization |
| Missing `mode` parameter | Add `mode: '0644'` | template tasks in tasks/main.yml | File permissions |
| `ssl_protocols TLSv1 TLSv1.1 TLSv1.2` | `ssl_protocols TLSv1.2 TLSv1.3` | templates/nginx.conf.j2 | Security update |
| `python-selinux` | `python3-selinux` | vars/main.yml | Python 3 compatibility |

## Dependencies

**Role dependencies**: None (from meta/main.yml)

**External packages**:
- RedHat: libselinux-python, nginx
- Debian: python-selinux (to be updated to python3-selinux), nginx

**Services managed**: 
- nginx (start, restart, reload)

**Variables to preserve**:
- All variables in vars/main.yml including `env: {'RUNLEVEL': 1}`
- Preserve `environment: env` directive in apt task

## Template Modernization

- **nginx.conf.j2**: 
  - Replace `ansible_os_family` with `ansible_facts['os_family']`
  - Replace `ansible_processor_count` with `ansible_facts['processor_count']`
  - Replace `nginx_http_params.iteritems()` with `nginx_http_params.items()`
  - Update SSL protocols to use only TLSv1.2 and TLSv1.3 (remove TLSv1 and TLSv1.1)
  - Parameterize SSL protocols as a variable for better flexibility

- **site.j2**:
  - Replace `item.server.iteritems()` with `item.server.items()`
  - Replace `v.iteritems()` with `v.items()`
  - Replace `k.find('location') == -1` with `'location' not in k`
  - Replace `k.find('location') != -1` with `'location' in k`

- **default.conf.j2** and **default.j2**:
  - Check for and update any Python 2 specific constructs
  - Ensure proper fact access using `ansible_facts` dictionary

## Argument Specification

```yaml
# meta/argument_specs.yml
---
argument_specs:
  main:
    short_description: Install and configure Nginx web server
    description: Install and configure Nginx web server with custom site configurations
    author: Benno Joy
    options:
      nginx_max_clients:
        type: int
        default: 512
        description: Maximum number of simultaneous client connections
      nginx_http_params:
        type: dict
        default:
          sendfile: "on"
          tcp_nopush: "on"
          tcp_nodelay: "on"
          keepalive_timeout: 65
        description: HTTP parameters for Nginx configuration
      nginx_log_dir:
        type: str
        default: "/var/log/nginx"
        description: Directory for Nginx log files
      nginx_access_log_name:
        type: str
        default: "access.log"
        description: Name of the access log file
      nginx_error_log_name:
        type: str
        default: "error.log"
        description: Name of the error log file
      nginx_separate_logs_per_site:
        type: bool
        default: false
        description: Whether to create separate log files for each site
      nginx_sites:
        type: list
        elements: dict
        default: []
        description: List of site configurations to create
```

## Checks for the Migration

**Files to verify**:
- roles/nginx/tasks/main.yml
- roles/nginx/handlers/main.yml
- roles/nginx/defaults/main.yml
- roles/nginx/vars/main.yml
- roles/nginx/meta/main.yml
- roles/nginx/meta/argument_specs.yml
- roles/nginx/templates/nginx.conf.j2
- roles/nginx/templates/site.j2
- roles/nginx/templates/default.conf.j2
- roles/nginx/templates/default.j2
- roles/nginx/files/epel.repo

**Services to check**:
- nginx

**Templates to validate**:
- roles/nginx/templates/nginx.conf.j2
- roles/nginx/templates/site.j2
- roles/nginx/templates/default.conf.j2
- roles/nginx/templates/default.j2

## Pre-flight checks:
```bash
# Verify Nginx configuration syntax
sudo nginx -t

# Check Nginx service status
sudo systemctl status nginx

# Verify site configurations
ls -la /etc/nginx/sites-available/
ls -la /etc/nginx/sites-enabled/

# Check for proper file permissions
find /etc/nginx -type f -exec ls -la {} \;

# Test connectivity to configured sites
for site in $(ls /etc/nginx/sites-enabled/); do
  port=$(grep -m 1 "listen" /etc/nginx/sites-available/$site | awk '{print $2}' | tr -d ';')
  curl -I http://localhost:$port
done
```