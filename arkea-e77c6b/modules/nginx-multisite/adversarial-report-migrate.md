

## Adversarial Review Findings

**Agent:** Dangerous Operations

**Summary:** The analysis identifies five critical findings involving unsafe, host-wide, and potentially service- or access-disrupting configuration changes without opt-in controls, preflight validation, backups, or reliable rollback paths.

### [CRITICAL] tasks/sites.yml — “Remove default NGINX virtual host”, lines 42–46

Existing default NGINX site is deleted without proving it is disposable. The task unconditionally removes /etc/nginx/sites-enabled/default, which may be customized or route production traffic on migrated or previously managed hosts. There is no ownership marker, content validation, opt-in variable, backup, or migration check, and the notified reload makes the deletion immediately service-affecting. Remediation: make removal explicitly opt-in with a default of false; inspect the symlink target and remove only a known package-provided default target; back up the symlink/configuration or fail if it points to an unknown or custom site.

**Evidence:**
```
- name: Remove default NGINX virtual host
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: Validate and reload NGINX
```

### [CRITICAL] tasks/security.yml — “Set UFW default incoming policy to deny”, lines 26–32; defaults/main.yml:15

Firewall policy is changed to default-deny without a connectivity safety gate. UFW inbound policy is set to deny before the role adds SSH, HTTP, and HTTPS rules, while nginx_multisite_ufw_enabled defaults to true. This can interrupt existing services not covered by those rules and lock out automation or operators not using the assumed ssh UFW application profile. The policy persists and is not rolled back if later tasks fail. Remediation: add required rules, including management CIDRs, custom SSH ports, and application-specific ports, before changing policy or enabling UFW; require explicit opt-in; validate current management connectivity and port first; and use a rescue block to restore the prior policy if rule creation or enablement fails.

**Evidence:**
```
- name: Set UFW default incoming policy to deny
  ansible.builtin.shell:
    cmd: |
      ufw status verbose | grep -q 'Default: deny' || \
        ufw --force default deny
  when: nginx_multisite_ufw_enabled | bool

nginx_multisite_ufw_enabled: true
```

### [CRITICAL] tasks/security.yml — “Disable SSH root login”, lines 73–83; “Disable SSH password authentication”, lines 85–95; handlers/main.yml — “Restart SSH”, lines 15–18

SSH password and root authentication are disabled with no access preflight, then SSH is restarted. Root login is disabled and password authentication defaults to false, but the role does not verify a non-root account with a valid authorized key and sudo access. Hosts accessed using root or password authentication can become permanently inaccessible after the deferred restart. No sshd -t validation is performed before restarting, so invalid configuration can take SSH offline. Remediation: default hardening changes to disabled unless explicitly approved; preflight an approved non-root break-glass/admin account, authorized-key access, and sudo capability; validate with sshd -t before reload/restart; prefer reload where supported; and use block/rescue to restore backed-up configuration if validation or activation fails.

**Evidence:**
```
nginx_multisite_disable_root_login: true
nginx_multisite_password_authentication: false

- name: Disable SSH root login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: ^#?PermitRootLogin\\s+.*$
    line: PermitRootLogin no
  notify: Restart SSH

- name: Disable SSH password authentication
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: ^#?PasswordAuthentication\\s+.*$
    line: PasswordAuthentication no
  notify: Restart SSH

- name: Restart SSH
  ansible.builtin.service:
    name: ssh
    state: restarted
```

### [CRITICAL] tasks/ssl.yml — “Generate missing self-signed TLS certificates”, lines 30–44

TLS generation can overwrite an existing private key when only the certificate is absent. Idempotency checks only for the .crt file; if the key exists but the certificate does not, openssl -newkey with -keyout can replace the existing key. This destroys key continuity and can break certificates, services, or external systems relying on the key. No key backup is taken, and the generated assets are immediately used by NGINX. Remediation: manage keys and certificates separately with appropriate crypto modules; check both states; fail safely if exactly one exists rather than overwriting it; generate temporary files and atomically install only after validation; and provide backups or explicit rotation controls.

**Evidence:**
```
- name: Generate missing self-signed TLS certificates
  ansible.builtin.shell:
    cmd: |
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout '{{ nginx_multisite_private_key_path }}/{{ item_nginx_multisite['key'] }}.key' \
        -out '{{ nginx_multisite_certificate_path }}/{{ item_nginx_multisite['key'] }}.crt' \
        ...
    creates: "{{ nginx_multisite_certificate_path }}/{{ item_nginx_multisite['key'] }}.crt"
```

### [CRITICAL] templates/sysctl-security.conf.j2, lines 25–34; deployed by tasks/security.yml, lines 60–66; applied by handlers/main.yml, lines 7–13

Kernel hardening unconditionally disables IPv6 and ICMP responses system-wide. Although the template comment says IPv6 should be disabled only if not needed, it disables IPv6 for all, default, and loopback interfaces, persists the setting across reboot, and applies it to the running host. This can break IPv6-only or dual-stack management, DNS/service discovery, load balancer health checks, and application dependencies. Ignoring all ICMP echo requests can also break monitoring and diagnostics. There is no environment preflight, opt-in control, or rollback. Remediation: split disruptive settings into explicit variables with safe defaults of false, especially IPv6 disablement and ICMP suppression; detect IPv6 addresses, routes, and listeners and fail rather than apply destructive changes; apply only during an approved maintenance window; and retain rollback configuration and handler behavior.

**Evidence:**
```
# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

- name: Reload kernel networking settings
  ansible.builtin.command:
    argv:
      - sysctl
      - -p
      - /etc/sysctl.d/99-security.conf
```

---