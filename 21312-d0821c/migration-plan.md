# MIGRATION FROM ANSIBLE TO ANSIBLE

## Executive Summary

This repository contains an existing Ansible role for Nginx that requires modernization rather than a full migration from another technology. The role is functional but uses legacy Ansible syntax, module names, and patterns that should be updated to follow current Ansible best practices. The modernization effort is estimated to be low to medium complexity and can be completed in 1-2 days by an experienced Ansible developer.

## Module Migration Plan

This repository contains Ansible roles that need modernization:

### MODULE INVENTORY

- **nginx**:
    - Description: Nginx web server installation and configuration with support for multiple sites, custom HTTP parameters, and platform-specific configurations
    - Path: roles/nginx
    - Technology: Ansible
    - Key Features: Multi-site configuration, RedHat/Debian support, EPEL repository management, custom HTTP parameters

### Infrastructure Files

- `roles/nginx/files/epel.repo`: EPEL repository configuration for RedHat systems - should be preserved but consider using the `community.general.yum_repository` module instead
- `roles/nginx/templates/*.j2`: Jinja2 templates for Nginx configuration - need Python 3 compatibility updates and proper spacing in variable references

### Target Details

Based on the source configuration:

- **Operating System**: Both RedHat (EL 5, 6) and Debian (Ubuntu precise, quantal, raring, saucy) families are supported
- **Virtual Machine Technology**: Not specified in the configuration
- **Cloud Platform**: Not specified in the configuration

## Migration Approach

### Key Dependencies to Address

- **python-selinux**: Replace with python3-selinux for Python 3 compatibility
- **nginx**: No change needed, but consider specifying a minimum version

### Security Considerations

- SSL/TLS configuration in templates should be updated to remove deprecated protocols (TLSv1, TLSv1.1) and use only TLSv1.2 and TLSv1.3
- No explicit credential management was found in the role
- File permissions should be explicitly set for all files created by template and copy modules

### Technical Challenges

- **Python 2 to 3 compatibility**: Templates use Python 2 specific methods like `iteritems()` that need to be replaced with `items()`
- **Legacy module syntax**: The role uses old-style module invocation (key=value) instead of YAML dictionary format
- **Legacy loop syntax**: The role uses `with_items` instead of the modern `loop` directive
- **Unquoted octal modes**: File permissions are specified as unquoted octal values which is deprecated
- **Missing FQCN**: Module names should be updated to use Fully Qualified Collection Names

### Migration Order

1. Update module names to use FQCN (e.g., `yum:` → `ansible.builtin.yum:`)
2. Convert key=value syntax to YAML dictionary format
3. Update loop syntax from `with_items` to `loop`
4. Quote octal modes and add missing file permissions
5. Update Python 2 specific code in templates
6. Add argument specification in meta/argument_specs.yml
7. Update fact access patterns (e.g., `ansible_os_family` → `ansible_facts['os_family']`)
8. Update boolean values from `yes`/`no` to `true`/`false`
9. Update package dependencies for Python 3 compatibility

### Assumptions

- The role is intended to be used with both RedHat and Debian based systems
- The role is expected to support multiple Nginx sites with custom configurations
- The role assumes EPEL repository is needed for RedHat systems
- The role assumes SELinux might be enabled on RedHat systems
- The role does not handle SSL certificate management directly
- The role does not include advanced features like HTTP/2, rate limiting, or load balancing
- The role was originally written for Ansible 1.4 and needs updates for compatibility with current Ansible versions