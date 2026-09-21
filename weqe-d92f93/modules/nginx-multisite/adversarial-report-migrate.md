

## Adversarial Review Findings

**Agent:** No sshd config

**Summary:** Four CRITICAL findings were identified across three files in the roles/nginx_multisite role. Two tasks in tasks/security.yml directly modify /etc/ssh/sshd_config (disabling root login and password authentication), both of which are active by default due to true defaults in defaults/main.yml. A handler in handlers/main.yml restarts the SSH daemon as a consequence of those prohibited changes, compounding the risk of operator lockout. A fourth task in tasks/ssl.yml creates the ssl-cert system group, violating the prohibition on user/group management. All four findings are CRITICAL.

### [CRITICAL] roles/nginx_multisite/tasks/security.yml (lines ~107–116)

sshd_config Modified — SSH Root Login Disabled. This task directly modifies /etc/ssh/sshd_config to set PermitRootLogin no. Changing any sshd configuration is explicitly prohibited. The conditional guard does not prevent this from running in practice because the default value of nginx_multisite_ssh_disable_root is true, meaning this task fires unconditionally in any standard deployment.

**Evidence:**
```
- name: Disable SSH root login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: ^#?PermitRootLogin
    line: PermitRootLogin no
    state: present
    backup: true
  when: nginx_multisite_ssh_disable_root | bool
  notify: Restart ssh

# Default in roles/nginx_multisite/defaults/main.yml:
nginx_multisite_ssh_disable_root: true
```

### [CRITICAL] roles/nginx_multisite/tasks/security.yml (lines ~118–127)

sshd_config Modified — SSH Password Authentication Disabled. This task directly modifies /etc/ssh/sshd_config to set PasswordAuthentication no. Same class of violation as Finding 1. The default value of nginx_multisite_ssh_disable_password_auth is true, meaning this task also fires unconditionally in any standard deployment.

**Evidence:**
```
- name: Disable SSH password authentication
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: ^#?PasswordAuthentication
    line: PasswordAuthentication no
    state: present
    backup: true
  when: nginx_multisite_ssh_disable_password_auth | bool
  notify: Restart ssh

# Default in roles/nginx_multisite/defaults/main.yml:
nginx_multisite_ssh_disable_password_auth: true
```

### [CRITICAL] roles/nginx_multisite/handlers/main.yml (lines ~13–15)

SSH Daemon Restarted via Handler. This handler exists solely to restart the SSH daemon after the prohibited sshd_config modifications. Restarting sshd is a direct consequence of and inseparable from the prohibited config changes. It compounds the risk: if the modified config is malformed, restarting sshd could lock all operators out of the host.

**Evidence:**
```
- name: Restart ssh
  ansible.builtin.service:
    name: ssh
    state: restarted
```

### [CRITICAL] roles/nginx_multisite/tasks/ssl.yml (lines 7–10)

System Group Created — ssl-cert. This task uses ansible.builtin.group to create the ssl-cert group if it does not already exist. Adding groups is a form of user/group management and is explicitly prohibited by policy. Group creation falls squarely within the prohibition against adding or deleting users.

**Evidence:**
```
- name: Ensure ssl-cert group exists
  ansible.builtin.group:
    name: ssl-cert
    state: present
```

---